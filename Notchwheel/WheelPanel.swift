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
        // By default the window server sends events (and drags) through pixels it thinks are
        // transparent. Liquid Glass is composited outside our backing store, so the whole wheel
        // looked transparent and drops fell through to Finder (which, with ⌥ held, copies the file).
        ignoresMouseEvents = false

        // The drop target is the panel's root view and the SwiftUI drawing sits inside it. Its
        // hitTest claims every point, so nothing SwiftUI adds (Liquid Glass inserts views of its
        // own) can end up between the cursor and the drop target.
        let target = WheelDropTarget(frame: frame, model: model, onDrop: onDrop)
        let wheel = NSHostingView(rootView: WheelView(model: model))
        wheel.frame = frame
        wheel.autoresizingMask = [.width, .height]
        wheel.unregisterDraggedTypes()
        target.addSubview(wheel)
        contentView = target
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

    /// Claim every point so no SwiftUI/glass subview can become the drag destination instead.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    /// A nearly invisible disc under the wheel, so the window has real (non-zero alpha) pixels
    /// wherever the wheel is and the window server routes the drag here, not to the window below.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.01).setFill()
        let r = WheelGeometry.outerRadius + WheelGeometry.radiusHysteresis
        NSBezierPath(ovalIn: NSRect(x: bounds.midX - r, y: bounds.midY - r, width: r * 2, height: r * 2)).fill()
    }

    /// Sticky: stays on the highlighted segment until the cursor is clearly elsewhere, and the drop
    /// uses the same answer, so what's highlighted is always what you get.
    private func segment(for sender: NSDraggingInfo) -> WheelSegment? {
        let p = convert(sender.draggingLocation, from: nil)   // y-up, non-flipped view
        return WheelGeometry.segment(at: CGPoint(x: p.x - bounds.midX, y: p.y - bounds.midY), keeping: model.hovered)
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
