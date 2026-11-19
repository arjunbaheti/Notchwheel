//
//  LoginItem.swift
//  Notchwheel
//
//  "Launch at Login" for the menu (PRD P0-8), via macOS's own login-items service.
//  Only offered when running from /Applications: registering a debug build from Xcode's build
//  folder would make macOS launch that copy at login instead of the installed one.
//

import AppKit
import Observation
import ServiceManagement
import os

@Observable
final class LoginItem {
    private(set) var enabled = false
    /// Shown under the toggle when macOS needs a click in System Settings, or something failed.
    private(set) var note: String?

    var isInstalled: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }

    init() { refresh() }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            note = nil
        } catch {
            note = "Couldn't change: \(error.localizedDescription)"
            appLog.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled
        if status == .requiresApproval { note = "Allow Notchwheel in System Settings › Login Items" }
    }
}
