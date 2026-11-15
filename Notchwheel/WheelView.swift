//
//  WheelView.swift
//  Notchwheel
//
//  SwiftUI drawing of the radial wheel. Hit-testing and the drop itself live in WheelPanel.
//

import SwiftUI

@Observable
final class WheelModel {
    var shown = false
    var hovered: WheelSegment?
    var fileCount = 0
}

struct WheelView: View {
    var model: WheelModel

    var body: some View {
        ZStack {
            ForEach(WheelSegment.allCases) { segment in
                let on = model.hovered == segment
                RingSegment(segment: segment)
                    .fill(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial))
                    .overlay(RingSegment(segment: segment).stroke(Color.primary.opacity(on ? 0 : 0.12), lineWidth: 1))
                    .scaleEffect(on ? 1.045 : 1)
                SegmentLabel(segment: segment, on: on)
                    .position(labelPoint(for: segment))
            }
            centre
        }
        .frame(width: WheelGeometry.size, height: WheelGeometry.size)
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .scaleEffect(model.shown ? 1 : 0.82)
        .opacity(model.shown ? 1 : 0)
        .animation(.spring(duration: 0.22, bounce: 0.3), value: model.shown)
        .animation(.easeOut(duration: 0.12), value: model.hovered)
    }

    private var centre: some View {
        VStack(spacing: 2) {
            Text("\(model.fileCount) file\(model.fileCount == 1 ? "" : "s")")
                .font(.system(size: 13, weight: .semibold))
            Text(model.hovered?.detail ?? "Pick an action")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: WheelGeometry.innerRadius * 2 - 12)
        .frame(width: WheelGeometry.innerRadius * 2 - 6, height: WheelGeometry.innerRadius * 2 - 6)
        .background(.regularMaterial, in: Circle())
        .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private func labelPoint(for segment: WheelSegment) -> CGPoint {
        let radians = WheelGeometry.drawingAngle(of: segment) * .pi / 180
        let r = (WheelGeometry.innerRadius + WheelGeometry.outerRadius) / 2
        let c = WheelGeometry.size / 2
        return CGPoint(x: c + r * cos(radians), y: c + r * sin(radians))
    }
}

private struct SegmentLabel: View {
    let segment: WheelSegment
    let on: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: segment.symbol)
                .font(.system(size: 20, weight: .medium))
            Text(segment.title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(on ? Color.white : Color.primary)
        .scaleEffect(on ? 1.08 : 1)
    }
}

/// One slice of the ring, built from sampled points (y-down drawing coordinates).
struct RingSegment: Shape {
    let segment: WheelSegment

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let gap = 1.6 // degrees trimmed off each side, leaving a hairline between slices
        let mid = WheelGeometry.drawingAngle(of: segment)
        let a0 = mid - WheelGeometry.sweep / 2 + gap
        let a1 = mid + WheelGeometry.sweep / 2 - gap
        let steps = 32
        func point(_ r: CGFloat, _ degrees: Double) -> CGPoint {
            let t = degrees * .pi / 180
            return CGPoint(x: c.x + r * cos(t), y: c.y + r * sin(t))
        }
        var path = Path()
        for i in 0...steps {
            let p = point(WheelGeometry.outerRadius, a0 + (a1 - a0) * Double(i) / Double(steps))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        for i in 0...steps {
            path.addLine(to: point(WheelGeometry.innerRadius, a1 - (a1 - a0) * Double(i) / Double(steps)))
        }
        path.closeSubpath()
        return path
    }
}
