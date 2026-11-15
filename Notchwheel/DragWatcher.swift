//
//  DragWatcher.swift
//  Notchwheel
//
//  Notices when the user is dragging files anywhere on screen with ⌥ held, and shows the wheel
//  under the cursor (PRD P0-1).
//
//  It polls global input state 60 times a second instead of using a global NSEvent monitor:
//  NSEvent.pressedMouseButtons, NSEvent.modifierFlags and the system drag pasteboard can all be
//  read without Accessibility or Input Monitoring permission, and polling keeps working while
//  Finder runs its own drag loop.
//

import AppKit
import os

let appLog = Logger(subsystem: "com.arjunbaheti.Notchwheel", category: "app")

final class DragWatcher {
    /// ⌥ must be held this long during a file drag before the panel appears (PRD P0-1).
    private let holdDelay: TimeInterval = 0.15

    private let state: AppState
    private let panel: WheelPanel
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var timer: Timer?

    private var mouseWasDown = false
    private var changeCountAtMouseDown = 0
    private var optionHeldSince: Date?
    /// Cached "does the current drag carry files?" for one pasteboard change count.
    private var checkedChangeCount = -1
    private var dragHasFiles = false

    init(state: AppState) {
        self.state = state
        self.panel = WheelPanel { segment, urls in
            state.dropCount += 1
            state.lastDrop = .init(date: Date(), segment: segment, urls: urls)
            state.working = true
            appLog.notice("\(segment.title, privacy: .public): \(urls.count) file(s)")
            let action = segment.action
            Task {
                let result = await BatchRunner.run(action, on: urls) // runs off the main thread
                state.working = false
                state.lastResult = result
                appLog.notice("\(result.summary, privacy: .public) in \(result.seconds, format: .fixed(precision: 2)) s")
                print("Notchwheel \(segment.title): \(result.summary) in \(String(format: "%.2f", result.seconds)) s")
                result.failures.forEach { print("  failed: \($0.input.lastPathComponent): \($0.reason)") }
                NSSound(named: result.outputs.isEmpty ? "Basso" : "Pop")?.play()
            }
        }
    }

    func start() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common so it keeps firing while menus or other event-tracking loops are running.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        state.watching = true
        appLog.notice("Drag watcher started")
    }

    private func tick() {
        let mouseDown = NSEvent.pressedMouseButtons & 1 != 0

        if mouseDown && !mouseWasDown {
            // A new press: any drag that starts from here bumps the drag pasteboard's change count.
            changeCountAtMouseDown = dragPasteboard.changeCount
        }
        if !mouseDown && mouseWasDown {
            // Released: the drop (if any) has been delivered. Hide shortly after, so the panel
            // doesn't vanish before it finishes handling the drop.
            optionHeldSince = nil
            if panel.isVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.panel.hide() }
            }
        }
        mouseWasDown = mouseDown
        guard mouseDown else { return }

        let draggingFiles = dragPasteboard.changeCount != changeCountAtMouseDown && currentDragHasFiles()
        let optionHeld = NSEvent.modifierFlags.contains(.option)

        if draggingFiles && optionHeld {
            let since = optionHeldSince ?? Date()
            optionHeldSince = since
            if !panel.isVisible && Date().timeIntervalSince(since) >= holdDelay {
                panel.show(centredOn: NSEvent.mouseLocation, fileCount: draggedFileCount())
            }
        } else {
            optionHeldSince = nil
            // Letting go of ⌥ mid-drag cancels: the panel hides and the drag carries on (P0-2).
            if panel.isVisible && !optionHeld { panel.hide() }
        }
    }

    private func draggedFileCount() -> Int {
        (dragPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []).count
    }

    private func currentDragHasFiles() -> Bool {
        let count = dragPasteboard.changeCount
        if count != checkedChangeCount {
            checkedChangeCount = count
            dragHasFiles = dragPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        }
        return dragHasFiles
    }
}
