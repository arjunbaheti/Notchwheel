//
//  NotchPillTests.swift
//  NotchwheelTests
//
//  Where the pill goes and what it says.
//

import CoreGraphics
import Testing
@testable import Notchwheel

struct NotchPillTests {
    /// A 14" MacBook Pro: 1512×982 points, 32 pt notch about 185 pt wide.
    @Test func pillIsCentredOnTheNotchAndHangsFromTheTop() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = NotchGeometry.notch(screenFrame: screen, safeAreaTop: 32, leftWidth: 663, rightWidth: 664)
        #expect(notch.width == 185)
        #expect(notch.height == 32)
        #expect(notch.midX == 663 + 92.5)

        let frame = NotchGeometry.panelFrame(for: notch)
        #expect(frame.maxY == 982)                                   // touches the top edge
        #expect(frame.midX == notch.midX)                            // centred on the notch
        #expect(frame.height == 32 + NotchGeometry.rowHeight)        // notch plus one text row
    }

    /// External monitor to the right of the laptop: no notch, so top centre of that screen.
    @Test func screensWithoutANotchUseTheTopCentre() {
        let screen = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let notch = NotchGeometry.notch(screenFrame: screen, safeAreaTop: 0, leftWidth: nil, rightWidth: nil)
        #expect(notch.width == 0 && notch.height == 0)
        let frame = NotchGeometry.panelFrame(for: notch)
        #expect(frame.midX == CGFloat(1512 + 1280))
        #expect(frame.maxY == 1440)
        #expect(frame.height == NotchGeometry.rowHeight)
    }

    @Test func progressTextNamesTheAction() {
        #expect(WheelSegment.compress.progressText(fileCount: 10) == "Compressing 10 files…")
        #expect(WheelSegment.toJPG.progressText(fileCount: 1) == "Converting 1 file to JPG…")
        #expect(WheelSegment.resize.progressText(fileCount: 2) == "Resizing 2 files…")
    }
}
