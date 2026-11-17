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
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 60)) == .toJPG)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 240)) == .resize)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 300)) == .toPDF)
    }

    @Test func boundariesFallOnTheRightSide() {
        let half = WheelGeometry.sweep / 2
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: half - 0.5)) == .compress)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: half + 0.5)) == .toJPG)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 360 - half + 0.5)) == .compress)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 360 - half - 0.5)) == .toPDF)   // last segment
    }

    @Test func centreHoleAndOutsideAreNotTargets() {
        #expect(WheelGeometry.segment(at: .zero) == nil)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 10, radius: WheelGeometry.innerRadius - 1)) == nil)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 10, radius: WheelGeometry.outerRadius + 1)) == nil)
    }

    /// Compress spans -half…half. Resting just past its edge must not flip the highlight back and forth.
    @Test func highlightIsStickyNearBoundaries() {
        let half = WheelGeometry.sweep / 2
        let justPastEdge = point(clockwiseFromTop: half + 3)      // 3° into JPG
        #expect(WheelGeometry.segment(at: justPastEdge) == .toJPG)
        #expect(WheelGeometry.segment(at: justPastEdge, keeping: .compress) == .compress)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: half + 14), keeping: .compress) == .toJPG)
        // Wrap-around: Compress also stays highlighted just past its left edge.
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 360 - half - 3), keeping: .compress) == .compress)
        // Radially: a little outside the ring keeps it, well outside lets go.
        let edge = WheelGeometry.outerRadius
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 0, radius: edge + 4), keeping: .compress) == .compress)
        #expect(WheelGeometry.segment(at: point(clockwiseFromTop: 0, radius: edge + 20), keeping: .compress) == nil)
        #expect(WheelGeometry.segment(at: .zero, keeping: .compress) == nil)  // centre hole
    }
}
