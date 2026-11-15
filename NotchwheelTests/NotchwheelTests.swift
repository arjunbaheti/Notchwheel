//
//  NotchwheelTests.swift
//  NotchwheelTests
//
//  Created by Arjun Baheti on 15/11/2026.
//

import CoreGraphics
import Foundation
import Testing
@testable import Notchwheel

/// Which segment the cursor is over (y points up, as in AppKit).
struct WheelGeometryTests {
    private let mid = (WheelGeometry.innerRadius + WheelGeometry.outerRadius) / 2

    /// A point on the ring at `degrees` clockwise from 12 o'clock.
    private func point(clockwiseFromTop degrees: Double, radius: CGFloat? = nil) -> CGPoint {
        let r = radius ?? mid
        let t = (90 - degrees) * .pi / 180
        return CGPoint(x: r * cos(t), y: r * sin(t))
    }

    @Test func segmentsRunClockwiseFromTheTop() {
        for segment in WheelSegment.allCases {
            let centre = Double(segment.rawValue) * WheelGeometry.sweep
            #expect(WheelGeometry.segment(at: point(clockwiseFromTop: centre)) == segment)
        }
    }

    @Test func topIsCompressAndUpperRightIsJPG() {
        #expect(WheelGeometry.segment(at: CGPoint(x: 0, y: mid)) == .compress)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 72)) == .toJPG)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 288)) == .resize)
    }

    @Test func boundariesFallOnTheRightSide() {
        let half = WheelGeometry.sweep / 2
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: half - 0.5)) == .compress)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: half + 0.5)) == .toJPG)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 360 - half + 0.5)) == .compress)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 360 - half - 0.5)) == .resize)
    }

    @Test func centreHoleAndOutsideAreNotTargets() {
        #expect(WheelGeometry.segment(at: .zero) == nil)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 10, radius: WheelGeometry.innerRadius - 1)) == nil)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 10, radius: WheelGeometry.outerRadius + 1)) == nil)
    }
}
