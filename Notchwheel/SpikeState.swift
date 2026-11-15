//
//  SpikeState.swift
//  Notchwheel
//
//  Shared state for the Milestone 1 spike, shown in the menu bar menu.
//

import Foundation
import Observation

@Observable
final class SpikeState {
    struct Drop {
        let date: Date
        let urls: [URL]
    }

    var watching = false
    var dropCount = 0
    var lastDrop: Drop?
}
