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
    let state = SpikeState()
    private var watcher: DragWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let watcher = DragWatcher(state: state)
        watcher.start()
        self.watcher = watcher
    }
}

/// What the menu bar menu shows. Milestone 1 only: proves the drop landed.
struct MenuContent: View {
    var state: SpikeState

    var body: some View {
        Text(state.watching ? "Hold ⌥ while dragging files" : "Starting…")
        if let drop = state.lastDrop {
            Divider()
            Text("Drop #\(state.dropCount): \(drop.urls.count) file\(drop.urls.count == 1 ? "" : "s") at \(drop.date.formatted(date: .omitted, time: .standard))")
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
