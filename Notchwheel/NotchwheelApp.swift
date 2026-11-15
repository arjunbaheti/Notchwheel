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

/// What the menu bar menu shows. For now: the last drop, so a test can confirm the right segment.
struct MenuContent: View {
    var state: AppState

    var body: some View {
        Text(state.watching ? "Hold ⌥ while dragging files" : "Starting…")
        if let drop = state.lastDrop {
            Divider()
            Text("Drop #\(state.dropCount): \(drop.segment.title) · \(drop.urls.count) file\(drop.urls.count == 1 ? "" : "s") at \(drop.date.formatted(date: .omitted, time: .standard))")
            ForEach(drop.urls.prefix(5), id: \.self) { url in
                Text(url.lastPathComponent)
            }
            if drop.urls.count > 5 {
                Text("…and \(drop.urls.count - 5) more")
            }
        }
        Divider()
        Button("Quit Notchwheel") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
