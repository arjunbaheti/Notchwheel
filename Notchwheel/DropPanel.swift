//
//  DropPanel.swift
//  Notchwheel
//
//  Milestone 1 spike: a plain circle in a borderless, non-activating floating panel that accepts
//  dropped files. Milestone 2 replaces the circle with the five-segment wheel.
//

import AppKit

final class DropPanel: NSPanel {
    static let size: CGFloat = 220

    init(onDrop: @escaping ([URL]) -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu                 // above normal and floating windows
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false          // we're never the active app
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = DropCircleView(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size), onDrop: onDrop)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `point` is in screen coordinates (origin bottom-left), as NSEvent.mouseLocation returns.
    func show(centredOn point: NSPoint) {
        setFrameOrigin(NSPoint(x: point.x - Self.size / 2, y: point.y - Self.size / 2))
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
        (contentView as? DropCircleView)?.highlighted = false
    }
}

/// Draws the circle and receives the drop. Only the circle itself is a target: dropping on the
/// transparent corners of the panel does nothing (PRD P0-2).
final class DropCircleView: NSView {
    private let onDrop: ([URL]) -> Void

    var highlighted = false {
        didSet { if highlighted != oldValue { needsDisplay = true } }
    }

    init(frame: NSRect, onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var circleRect: NSRect { bounds.insetBy(dx: 10, dy: 10) }

    private func insideCircle(_ sender: NSDraggingInfo) -> Bool {
        let p = convert(sender.draggingLocation, from: nil)
        let r = circleRect
        let dx = p.x - r.midX, dy = p.y - r.midY
        return dx * dx + dy * dy <= (r.width / 2) * (r.width / 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(ovalIn: circleRect)
        (highlighted ? NSColor.controlAccentColor : NSColor.windowBackgroundColor)
            .withAlphaComponent(highlighted ? 0.85 : 0.92)
            .setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 3
        path.stroke()

        let label = highlighted ? "Release to drop" : "Drop here"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: highlighted ? NSColor.white : NSColor.labelColor,
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }

    // MARK: Drag destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }

    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlighted = insideCircle(sender)
        return highlighted ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard insideCircle(sender),
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty
        else { return false }
        onDrop(urls)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) { highlighted = false }
}
