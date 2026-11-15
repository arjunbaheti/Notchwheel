//
//  FileAction.swift
//  Notchwheel
//
//  The contract every wheel action follows, plus the batch runner that applies one to many files.
//  New engines (PDF, video; PRD P2) conform to FileAction and slot into the wheel without UI changes.
//

import Foundation

/// Turns one input file into one new output file next to it. Must never modify the input (P0-5).
nonisolated protocol FileAction: Sendable {
    var name: String { get }
    /// Throws `FileActionError.unsupported` for inputs this action doesn't handle (they're skipped).
    func process(_ input: URL) throws -> URL
}

nonisolated enum FileActionError: Error, Equatable {
    /// Not something this action works on, e.g. a PDF dropped on an image action.
    case unsupported(String)
    /// It should have worked but didn't (unreadable file, no write permission...).
    case failed(String)
}

nonisolated struct BatchResult: Sendable {
    struct Failure: Sendable { let input: URL; let reason: String }

    var outputs: [URL] = []
    var skipped: [URL] = []
    var failures: [Failure] = []
    var bytesIn: Int64 = 0
    var bytesOut: Int64 = 0
    var seconds: Double = 0

    /// e.g. "4 files, 18.6 MB → 2.3 MB · 2 skipped (not images)" (PRD P0-6, P0-7).
    var summary: String {
        var parts: [String] = []
        if !outputs.isEmpty {
            let size = ByteCountFormatter()
            size.countStyle = .file
            parts.append("\(outputs.count) file\(outputs.count == 1 ? "" : "s"), \(size.string(fromByteCount: bytesIn)) → \(size.string(fromByteCount: bytesOut))")
        }
        if !skipped.isEmpty { parts.append("\(skipped.count) skipped (not images)") }
        if !failures.isEmpty { parts.append("\(failures.count) failed") }
        return parts.isEmpty ? "Nothing to do" : parts.joined(separator: " · ")
    }
}

nonisolated enum BatchRunner {
    /// Runs `action` on every input, one file per CPU core at a time, off the main thread.
    /// Never throws: each file ends up as an output, a skip or a failure.
    @concurrent
    static func run(_ action: any FileAction, on inputs: [URL]) async -> BatchResult {
        enum Outcome: Sendable {
            case done(output: URL, bytesIn: Int64, bytesOut: Int64)
            case skipped(URL)
            case failed(URL, String)
        }

        let start = Date()
        var result = BatchResult()
        let width = max(1, ProcessInfo.processInfo.activeProcessorCount)

        await withTaskGroup(of: Outcome.self) { group in
            var pending = inputs.makeIterator()
            func addNext() -> Bool {
                guard let input = pending.next() else { return false }
                group.addTask {
                    do {
                        let output = try action.process(input)
                        return .done(output: output, bytesIn: fileSize(input), bytesOut: fileSize(output))
                    } catch FileActionError.unsupported {
                        return .skipped(input)
                    } catch FileActionError.failed(let reason) {
                        return .failed(input, reason)
                    } catch {
                        return .failed(input, error.localizedDescription)
                    }
                }
                return true
            }
            for _ in 0..<width where addNext() {}
            for await outcome in group {
                switch outcome {
                case let .done(output, bytesIn, bytesOut):
                    result.outputs.append(output)
                    result.bytesIn += bytesIn
                    result.bytesOut += bytesOut
                case let .skipped(input):
                    result.skipped.append(input)
                case let .failed(input, reason):
                    result.failures.append(.init(input: input, reason: reason))
                }
                _ = addNext()
            }
        }
        result.seconds = Date().timeIntervalSince(start)
        return result
    }

    private static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
