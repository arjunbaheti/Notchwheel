//
//  NotchwheelApp.swift
//  Notchwheel
//
//  Entry point. Notchwheel lives only in the menu bar (LSUIElement = YES hides the Dock icon).
//

import SwiftUI
import os

@main
struct NotchwheelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Notchwheel", systemImage: "circle.dashed") {
            MenuContent(state: appDelegate.state)
        }
    }
}

/// Starts the drag watcher once the app has launched, and runs each drop through the image engine,
/// reporting progress and the result in the notch pill.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var watcher: DragWatcher?
    private let pill = NotchPill()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let watcher = DragWatcher(state: state) { [weak self] segment, urls in
            self?.process(urls, with: segment)
        }
        watcher.start()
        self.watcher = watcher
    }

    private func process(_ urls: [URL], with segment: WheelSegment) {
        state.dropCount += 1
        state.lastDrop = .init(date: Date(), segment: segment, urls: urls)
        state.working = true
        pill.showWorking(segment.progressText(fileCount: urls.count))
        appLog.notice("\(segment.title, privacy: .public): \(urls.count) file(s)")
        Task {
            let result = await segment.run(on: urls)   // runs off the main thread
            state.working = false
            state.lastResult = result
            pill.showResult(result)
            appLog.notice("\(result.summary, privacy: .public) in \(result.seconds, format: .fixed(precision: 2)) s")
            NSSound(named: result.outputs.isEmpty ? "Basso" : "Pop")?.play()
        }
    }
}

/// What the menu bar menu shows: the last result, as a backup to the notch pill.
struct MenuContent: View {
    var state: AppState

    var body: some View {
        Text(state.watching ? "Hold ⌥ while dragging images" : "Starting…")
        if let drop = state.lastDrop {
            Divider()
            if state.working {
                Text("\(drop.segment.title): working on \(drop.urls.count) file\(drop.urls.count == 1 ? "" : "s")…")
            } else if let result = state.lastResult {
                Text("\(drop.segment.title): \(result.summary)")
                Text("Took \(result.seconds, format: .number.precision(.fractionLength(2))) s at \(drop.date.formatted(date: .omitted, time: .shortened))")
                ForEach(Array(result.failures.prefix(3).enumerated()), id: \.offset) { _, failure in
                    Text("Failed: \(failure.input.lastPathComponent) (\(failure.reason))")
                }
                if !result.outputs.isEmpty {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(result.outputs)
                    }
                }
            }
        }
        Divider()
        Button("Quit Notchwheel") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
