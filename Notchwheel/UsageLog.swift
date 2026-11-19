//
//  UsageLog.swift
//  Notchwheel
//
//  A local CSV of every drop (PRD success metrics: uses per week, time to finish, size reduction).
//  Lives in ~/Library/Application Support/Notchwheel/usage.csv and never leaves the Mac. Open it in
//  Numbers after a couple of weeks to see whether the app is earning its place.
//

import Foundation
import os

nonisolated enum UsageLog {
    static let header = "date,action,files,mb_in,mb_out,seconds,outputs,skipped,failed"

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Notchwheel/usage.csv")
    }

    static func line(date: Date, action: String, files: Int, result: BatchResult) -> String {
        let mb = { (bytes: Int64) in String(format: "%.2f", Double(bytes) / 1_000_000) }
        return [
            date.ISO8601Format(), action, "\(files)", mb(result.bytesIn), mb(result.bytesOut),
            String(format: "%.2f", result.seconds),
            "\(result.outputs.count)", "\(result.skipped.count)", "\(result.failures.count)",
        ].joined(separator: ",")
    }

    /// Appends one row, creating the file (with a header) the first time. Never throws: a logging
    /// problem must not get in the way of the actual work.
    static func record(action: String, files: Int, result: BatchResult, date: Date = Date(), to url: URL = defaultURL) {
        let row = line(date: date, action: action, files: files, result: result) + "\n"
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try (header + "\n").write(to: url, atomically: true, encoding: .utf8)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(row.utf8))
        } catch {
            appLog.error("Usage log write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
