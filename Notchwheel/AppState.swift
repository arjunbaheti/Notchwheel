//
//  AppState.swift
//  Notchwheel
//
//  State shown in the menu bar menu.
//

import Foundation
import Observation

@Observable
final class AppState {
    struct Drop {
        let date: Date
        let segment: WheelSegment
        let urls: [URL]
    }

    var watching = false
    var dropCount = 0
    var lastDrop: Drop?
}
