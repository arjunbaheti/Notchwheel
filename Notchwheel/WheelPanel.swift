//
//  WheelPanel.swift
//  Notchwheel
//
//  A borderless, non-activating floating panel that shows the wheel under the cursor and receives
//  the drop. SwiftUI draws the wheel; a transparent AppKit view on top is the drag destination
//  and maps the cursor to a segment (PRD technical approach, step 2).
//

import AppKit
import SwiftUI

final class WheelPanel: NSPanel {
    let model = WheelModel()

    init(onDrop: @escaping (WheelSegment, [URL]) -> Void) {
        let size = WheelGeometry.size
        let frame = NSRect(x: 0, y: 0, width: size, height: size)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu                 // above normal and floating windows
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false                  // SwiftUI draws its own shadow
        hidesOnDeactivate = false          // we're never the active app
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let container = NSView(frame: frame)
        let wheel = NSHostingView(rootView: WheelView(model: model))
        wheel.frame = frame
        wheel.autoresizingMask = [.width, .height]
        container.addSubview(wheel)
        // On top of the SwiftUI view so it is the one that receives the drag.
        let target = WheelDropTarget(frame: frame, model: model, onDrop: onDrop)
        target.autoresizingMask = [.width, .height]
        container.addSubview(target)
        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `point` is in screen coordinates (origin bottom-left), as NSEvent.mouseLocation returns.
    /// Near a screen edge the wheel is nudged inwards so it is never cut off.
    func show(centredOn point: NSPoint, fileCount: Int) {
        let size = WheelGeometry.size
        var origin = NSPoint(x: point.x - size / 2, y: point.y - size / 2)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            let f = screen.frame
            origin.x = min(max(origin.x, f.minX), f.maxX - size)
            origin.y = min(max(origin.y, f.minY), f.maxY - size)
        }
        setFrameOrigin(origin)
        model.fileCount = fileCount
        model.hovered = nil
        model.shown = false
        orderFrontRegardless()
        // Next run-loop turn, so SwiftUI animates from hidden to shown.
        DispatchQueue.main.async { self.model.shown = true }
    }

    func hide() {
        orderOut(nil)
        model.shown = false
        model.hovered = nil
    }
}

/// Transparent drag destination covering the panel.
private final class WheelDropTarget: NSView {
    private let model: WheelModel
    private let onDrop: (WheelSegment, [URL]) -> Void

    init(frame: NSRect, model: WheelModel, onDrop: @escaping (WheelSegment, [URL]) -> Void) {
        self.model = model
        self.onDrop = onDrop
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func segment(for sender: NSDraggingInfo) -> WheelSegment? {
        let p = convert(sender.draggingLocation, from: nil)   // y-up, non-flipped view
        return WheelGeometry.segment(at: CGPoint(x: p.x - bounds.midX, y: p.y - bounds.midY))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }

    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        let hit = segment(for: sender)
        if model.hovered != hit { model.hovered = hit }
        return hit == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { model.hovered = nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let hit = segment(for: sender),
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty
        else { return false }
        onDrop(hit, urls)
        return true
    }
}
