//
//  NotchwheelApp.swift
//  Notchwheel
//
//  Entry point. Notchwheel lives only in the menu bar (LSUIElement = YES hides the Dock icon).
//

import SwiftUI

@main
struct NotchwheelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Notchwheel", systemImage: "circle.dashed") {
            MenuContent(state: appDelegate.state)
        }
    }
}

/// Starts the drag watcher once the app has launched.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var watcher: DragWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let watcher = DragWatcher(state: state)
        watcher.start()
        self.watcher = watcher
    }
}

/// What the menu bar menu shows. Until the notch pill (Milestone 4), results show up here.
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
