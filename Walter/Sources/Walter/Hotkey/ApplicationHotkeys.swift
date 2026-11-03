// Config-to-action wiring, independent of popup lifetime and mockable OS handoff.
import AppKit

final class ApplicationHotkeys {
    private struct Snapshot: Equatable {
        let open: String
        let close: String
        let apps: [ConfigManager.AppHotkey]
        let errors: [String]
    }
    private struct ConfigurationError: Error, CustomStringConvertible {
        let description: String
    }

    private let manager: HotkeyManager
    private let apps: AllowedApps
    private let openApp: (URL) -> Void
    private let toggle: () -> Void
    private let report: (Error) -> Void
    private var applied: Snapshot?
    private var hasWorkingLauncher = false

    init(manager: HotkeyManager, apps: AllowedApps = AllowedApps(),
         openApp: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
         toggle: @escaping () -> Void, report: @escaping (Error) -> Void) {
        self.manager = manager
        self.apps = apps
        self.openApp = openApp
        self.toggle = toggle
        self.report = report
    }

    func apply(_ config: ConfigManager) {
        let snapshot = Snapshot(open: config.keybindings.open, close: config.keybindings.close,
                                apps: config.appHotkeys, errors: config.appHotkeyErrors)
        // Theme saves and panel rebuilds must not recreate app actions/handles.
        guard snapshot != applied else { return }
        do {
            let launcher = try launcherRequest(snapshot.open)
            _ = try HotkeyBinding.parse(snapshot.close)
            guard snapshot.errors.isEmpty else {
                throw ConfigurationError(description: snapshot.errors.joined(separator: "\n"))
            }
            var requests = [launcher]
            var bindings: Set<HotkeyBinding> = [launcher.binding]
            for entry in snapshot.apps {
                let binding: HotkeyBinding
                do { binding = try HotkeyBinding.parse(entry.binding) }
                catch { throw ConfigurationError(description: "[app_hotkeys] \(entry.binding): \(error)") }
                guard binding.modifiers != 0 else { throw HotkeyError.invalid(entry.binding) }
                guard bindings.insert(binding).inserted else {
                    throw ConfigurationError(description: "[app_hotkeys] \(entry.binding): \(HotkeyError.duplicate)")
                }
                guard apps.validatedURL(for: entry.path) != nil else { throw invalidApp(entry) }
                requests.append(.init(name: "[app_hotkeys] \(entry.binding) → \(entry.path)", binding: binding, action: { [weak self] in
                    guard let self else { return }
                    // Keep the configured path: re-resolve links at every press,
                    // rather than trusting the destination found during reload.
                    if !self.apps.launch(path: entry.path, open: self.openApp) {
                        self.report(self.invalidApp(entry))
                    }
                }))
            }
            try manager.replace(with: requests)
            hasWorkingLauncher = true
            applied = snapshot
        } catch {
            // The manager rolls back the entire transaction, including actions.
            // On first load a bad app entry must not prevent launcher access.
            var messages = [String(describing: error)]
            if !hasWorkingLauncher {
                for message in installLauncherFallback(snapshot.open) where !messages.contains(message) {
                    messages.append(message)
                }
            }
            // One alert per failed update, even if startup fallback also fails.
            report(ConfigurationError(description: messages.joined(separator: "\n")))
        }
    }

    private func launcherRequest(_ text: String) throws -> HotkeyManager.Request {
        let binding = try HotkeyBinding.parse(text)
        guard binding.modifiers != 0 else { throw HotkeyError.invalid(text) }
        return .init(name: "launcher", binding: binding, action: toggle)
    }

    private func installLauncherFallback(_ configured: String) -> [String] {
        let candidates = configured == ConfigManager.Keybindings().open
            ? [configured] : [configured, ConfigManager.Keybindings().open]
        var errors: [String] = []
        for candidate in candidates {
            do {
                try manager.replace(with: [launcherRequest(candidate)])
                hasWorkingLauncher = true
                return errors
            } catch { errors.append(String(describing: error)) }
        }
        return errors
    }

    private func invalidApp(_ entry: ConfigManager.AppHotkey) -> ConfigurationError {
        ConfigurationError(description: "[app_hotkeys] \(entry.binding): Missing or disallowed app at \(entry.path). Use a real .app inside /Applications or /System/Applications, without escaping symlinks or embedded packages.")
    }
}
