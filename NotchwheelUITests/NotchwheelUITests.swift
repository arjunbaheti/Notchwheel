//
//  NotchwheelUITests.swift
//  NotchwheelUITests
//
//  Intentionally empty. Xcode's template tests launched the app and then failed because XCTest
//  can't terminate a menu-bar-only (LSUIElement) app, and the wheel only appears during a real
//  Finder drag, which UI tests can't drive. The gesture is tested by hand; logic lives in
//  NotchwheelTests.
//

import XCTest

final class NotchwheelUITests: XCTestCase {}
