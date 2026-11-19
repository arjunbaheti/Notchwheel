//
//  NotchPill.swift
//  Notchwheel
//
//  The black pill that grows out of the notch to show progress and the result (PRD P0-6).
//  A borderless, non-activating panel sits above the menu bar, centred on the notch; SwiftUI
//  draws a notch-coloured shape that expands from the notch's size to fit one line of text.
//  On screens without a notch it hangs from the top centre instead.
//

import AppKit
import SwiftUI

/// Where the notch is and how big the panel should be. Pure maths, so it can be unit-tested.
enum NotchGeometry {
    static let panelWidth: CGFloat = 560   // room for the longest summary line; transparent around the pill
    static let rowHeight: CGFloat = 38     // the text row that appears under the notch
    static let minPillWidth: CGFloat = 300

    struct Notch: Equatable {
        var midX: CGFloat
        var width: CGFloat    // 0 on screens without a notch
        var height: CGFloat   // 0 on screens without a notch
        var top: CGFloat      // the screen's top edge, in global coordinates (y up)
    }

    /// `leftWidth` / `rightWidth` are the widths of `NSScreen.auxiliaryTopLeftArea` and
    /// `auxiliaryTopRightArea`; whatever is between them is the notch.
    static func notch(screenFrame f: CGRect, safeAreaTop: CGFloat, leftWidth: CGFloat?, rightWidth: CGFloat?) -> Notch {
        if safeAreaTop > 0, let l = leftWidth, let r = rightWidth, f.width - l - r > 0 {
            let width = f.width - l - r
            return Notch(midX: f.minX + l + width / 2, width: width, height: safeAreaTop, top: f.maxY)
        }
        return Notch(midX: f.midX, width: 0, height: 0, top: f.maxY)
    }

    /// The panel's frame: hanging from the top of the screen, centred on the notch.
    static func panelFrame(for n: Notch) -> CGRect {
        let height = n.height + rowHeight
        return CGRect(x: n.midX - panelWidth / 2, y: n.top - height, width: panelWidth, height: height)
    }
}

@Observable
final class PillModel {
    enum Status: Equatable { case working, success, partial, failure }

    var status: Status = .working
    var text = ""
    var expanded = false
    var canReveal = false
    var notch = NotchGeometry.Notch(midX: 0, width: 0, height: 0, top: 0)
}

/// Tells other notch apps (Arjun's Notch) to step aside while the pill shows. System-wide
/// distributed notifications: no permission needed, and harmless if nobody is listening.
nonisolated enum NotchSignal {
    static let pillWillShow = Notification.Name("com.arjunbaheti.Notchwheel.pillWillShow")
    static let pillDidHide = Notification.Name("com.arjunbaheti.Notchwheel.pillDidHide")

    static func post(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }
}

final class NotchPill: NSPanel {
    private let model = PillModel()
    private var outputs: [URL] = []
    private var hideTimer: Timer?
    /// Bumped on every new message, so a late hide from an older one can't hide a newer one.
    private var generation = 0

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)   // above the menu bar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = FirstClickHostingView(rootView: PillView(
            model: model,
            onClick: { [weak self] in self?.reveal() },
            onHover: { [weak self] inside in self?.hoverChanged(inside) }
        ))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// AppKit normally pushes windows below the menu bar; the pill needs to sit in it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func showWorking(_ text: String) {
        present(.working, text, outputs: [])
    }

    func showResult(_ result: BatchResult) {
        let status: PillModel.Status =
            result.outputs.isEmpty ? .failure
            : (result.failures.isEmpty && result.skipped.isEmpty ? .success : .partial)
        present(status, result.summary, outputs: result.outputs)
        scheduleHide(after: status == .success ? 3 : 4.5)
    }

    // MARK: - Private

    private func present(_ status: PillModel.Status, _ text: String, outputs: [URL]) {
        generation += 1
        hideTimer?.invalidate()
        self.outputs = outputs
        model.status = status
        model.text = text
        model.canReveal = !outputs.isEmpty
        ignoresMouseEvents = status == .working   // nothing to click yet; don't block the menu bar

        guard !isVisible else { return }
        NotchSignal.post(NotchSignal.pillWillShow)
        let screen = Self.targetScreen()
        let notch = NotchGeometry.notch(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            leftWidth: screen.auxiliaryTopLeftArea?.width,
            rightWidth: screen.auxiliaryTopRightArea?.width)
        model.notch = notch
        model.expanded = false
        setFrame(NotchGeometry.panelFrame(for: notch), display: false)
        orderFrontRegardless()
        // Next run-loop turn, so SwiftUI animates out of the notch.
        DispatchQueue.main.async { self.model.expanded = true }
    }

    /// The screen the cursor is on (that's where the drop happened), else the main screen.
    private static func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideTimer?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapse() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private func hoverChanged(_ inside: Bool) {
        guard model.status != .working, isVisible else { return }
        if inside { hideTimer?.invalidate() } else { scheduleHide(after: 1.5) }
    }

    private func reveal() {
        guard !outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
        collapse()
    }

    private func collapse() {
        hideTimer?.invalidate()
        let current = generation
        model.expanded = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.generation == current else { return }
            self.orderOut(nil)
            NotchSignal.post(NotchSignal.pillDidHide)
        }
    }
}

/// Lets the first click land even though the panel is never the key window.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PillView: View {
    var model: PillModel
    var onClick: () -> Void
    var onHover: (Bool) -> Void

    private var notchWidth: CGFloat { max(model.notch.width, 120) }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.notch.height)   // the notch itself: camera lives here
            row
                .frame(height: NotchGeometry.rowHeight)
                .opacity(model.expanded ? 1 : 0)
        }
        .padding(.horizontal, 22)
        .frame(minWidth: max(notchWidth + 60, NotchGeometry.minPillWidth))
        // Collapsed: exactly the notch, so it looks like the notch is growing.
        .frame(width: model.expanded ? nil : notchWidth,
               height: model.expanded ? model.notch.height + NotchGeometry.rowHeight : model.notch.height)
        .background(NotchShape().fill(.black))
        .clipShape(NotchShape())
        .contentShape(NotchShape())
        .onTapGesture(perform: onClick)
        .onHover(perform: onHover)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.32, bounce: 0.25), value: model.expanded)
        .animation(.easeInOut(duration: 0.2), value: model.text)
    }

    private var row: some View {
        HStack(spacing: 8) {
            icon.frame(width: 18)
            Text(model.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
            if model.canReveal {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .help("Show in Finder")
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var icon: some View {
        switch model.status {
        case .working:
            ProgressView().controlSize(.small).tint(.white).colorScheme(.dark)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .partial:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.yellow)
        case .failure:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

/// Notch-style outline: flat top with small outward curves at the corners (so it blends into the
/// menu bar like the real notch), rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat = 6
    var bottomRadius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let t = topRadius
        let b = min(bottomRadius, rect.height / 2, (rect.width - 2 * t) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
