//
//  WheelSegment.swift
//  Notchwheel
//
//  The six actions on the wheel (PRD P0-3, plus PDF) and the geometry shared by drawing and hit-testing.
//

import Foundation

enum WheelSegment: Int, CaseIterable, Identifiable {
    case compress, toJPG, toPNG, toHEIC, resize, toPDF

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .compress: "Compress"
        case .toJPG: "JPG"
        case .toPNG: "PNG"
        case .toHEIC: "HEIC"
        case .resize: "Resize"
        case .toPDF: "PDF"
        }
    }

    var symbol: String {
        switch self {
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .toJPG: "j.square"
        case .toPNG: "p.square"
        case .toHEIC: "h.square"
        case .resize: "aspectratio"
        case .toPDF: "doc.richtext"
        }
    }

    /// Shown in the notch pill while a batch runs, e.g. "Converting 3 files to JPG…".
    func progressText(fileCount n: Int) -> String {
        let files = "\(n) file\(n == 1 ? "" : "s")"
        switch self {
        case .compress: return "Compressing \(files)…"
        case .toJPG, .toPNG, .toHEIC: return "Converting \(files) to \(title)…"
        case .resize: return "Resizing \(files)…"
        case .toPDF: return "Making a PDF from \(files)…"
        }
    }

    /// One-line summary shown in the middle of the wheel while hovering.
    var detail: String {
        switch self {
        case .compress: "JPG 75% · max 2560 px"
        case .toJPG: "Convert to JPG"
        case .toPNG: "Convert to PNG"
        case .toHEIC: "Convert to HEIC"
        case .resize: "Longest edge 2048 px"
        case .toPDF: "Combine into one PDF"
        }
    }
}

/// Wheel layout. Segment 0 sits at the top; the rest follow clockwise.
enum WheelGeometry {
    static let size: CGFloat = 280          // panel width and height
    static let outerRadius: CGFloat = 132
    static let innerRadius: CGFloat = 48    // the centre hole: dropping there does nothing
    static let sweep = 360.0 / Double(WheelSegment.allCases.count)

    /// The segment under `point`, given relative to the wheel's centre with y pointing UP
    /// (AppKit coordinates). Nil in the centre hole or outside the wheel (PRD P0-2).
    static func segment(at point: CGPoint) -> WheelSegment? {
        let distance = hypot(point.x, point.y)
        guard distance >= innerRadius, distance <= outerRadius else { return nil }
        // Degrees clockwise from 12 o'clock, shifted half a segment so segment 0 is centred on top.
        let fromTop = 90 - atan2(point.y, point.x) * 180 / .pi
        let shifted = (fromTop + 360 + sweep / 2).truncatingRemainder(dividingBy: 360)
        return WheelSegment(rawValue: Int(shifted / sweep) % WheelSegment.allCases.count)
    }

    /// How far past a segment's edge the cursor can wander before the highlight lets go. Without
    /// this, a cursor resting on a boundary flips the highlight on and off and the wheel twitches.
    static let angleHysteresis = 6.0          // degrees
    static let radiusHysteresis: CGFloat = 8  // points

    /// Like `segment(at:)`, but keeps `current` while the cursor is still near it.
    static func segment(at point: CGPoint, keeping current: WheelSegment?) -> WheelSegment? {
        guard let current else { return segment(at: point) }
        let distance = hypot(point.x, point.y)
        if distance >= innerRadius - radiusHysteresis, distance <= outerRadius + radiusHysteresis {
            let fromTop = (90 - atan2(point.y, point.x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            var offset = abs(fromTop - Double(current.rawValue) * sweep)
            if offset > 180 { offset = 360 - offset }
            if offset <= sweep / 2 + angleHysteresis { return current }
        }
        return segment(at: point)
    }

    /// Centre angle of a segment in screen-drawing terms: degrees clockwise from 3 o'clock with y
    /// pointing DOWN (SwiftUI coordinates).
    static func drawingAngle(of segment: WheelSegment) -> Double {
        Double(segment.rawValue) * sweep - 90
    }
}
