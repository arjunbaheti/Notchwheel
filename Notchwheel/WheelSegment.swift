//
//  WheelSegment.swift
//  Notchwheel
//
//  The five actions on the wheel (PRD P0-3) and the geometry shared by drawing and hit-testing.
//

import Foundation

enum WheelSegment: Int, CaseIterable, Identifiable {
    case compress, toJPG, toPNG, toHEIC, resize

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .compress: "Compress"
        case .toJPG: "JPG"
        case .toPNG: "PNG"
        case .toHEIC: "HEIC"
        case .resize: "Resize"
        }
    }

    var symbol: String {
        switch self {
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .toJPG: "j.square"
        case .toPNG: "p.square"
        case .toHEIC: "h.square"
        case .resize: "aspectratio"
        }
    }

    /// Shown in the notch pill while a batch runs, e.g. "Converting 3 files to JPG…".
    func progressText(fileCount n: Int) -> String {
        let files = "\(n) file\(n == 1 ? "" : "s")"
        switch self {
        case .compress: return "Compressing \(files)…"
        case .toJPG, .toPNG, .toHEIC: return "Converting \(files) to \(title)…"
        case .resize: return "Resizing \(files)…"
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

    /// Centre angle of a segment in screen-drawing terms: degrees clockwise from 3 o'clock with y
    /// pointing DOWN (SwiftUI coordinates).
    static func drawingAngle(of segment: WheelSegment) -> Double {
        Double(segment.rawValue) * sweep - 90
    }
}
