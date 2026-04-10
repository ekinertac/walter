// LoginItemManager.swift — Register Walter as a login item
//
// Uses SMAppService (macOS 13+) to add/remove Walter from login items.
// This is the modern API — no helper bundles, no deprecated LSSharedFileList.
//
// Called by: AppDelegate on launch (registers if not already registered).

import ServiceManagement

class LoginItemManager {

    /// Registers Walter to start at login. Idempotent — safe to call every launch.
    static func enableLoginItem() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            if service.status != .enabled {
                do {
                    try service.register()
                    print("LoginItem: registered (will start at login)")
                } catch {
                    print("LoginItem: registration failed — \(error.localizedDescription)")
                }
            } else {
                print("LoginItem: already enabled")
            }
        }
    }

    /// Removes Walter from login items.
    static func disableLoginItem() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                try service.unregister()
                print("LoginItem: unregistered")
            } catch {
                print("LoginItem: unregister failed — \(error.localizedDescription)")
            }
        }
    }
}
