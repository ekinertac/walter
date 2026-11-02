import AppKit

/// Popup-local routing only; unhandled keys continue through the responder chain.
/// Tests supply plain values and callbacks, never events, windows, or an app.
enum PopupShortcuts {
    static func handle(characters: String, modifiers: NSEvent.ModifierFlags,
                       popupActive: Bool, quit: (() -> Void)?,
                       showConfigLocation: (() -> Void)?) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard popupActive, modifiers.intersection(relevant) == .command else { return false }
        let action: (() -> Void)?
        switch characters.lowercased() {
        case "q": action = quit
        case ",": action = showConfigLocation
        default: return false
        }
        guard let action else { return false }
        action()
        return true
    }
}

struct ConfigLocationNotice {
    let title = "Walter configuration"
    let path: String
    var message: String {
        "Configuration file:\n\(path)\n\nEdit this file to change Walter’s settings. Saved changes reload automatically."
    }

    init(configURL: URL) { path = configURL.path }
}

/// Modal presentation is injected so tests cannot display an alert. Restore via
/// the current panel after dismissal, not a panel captured before config reload.
final class ConfigLocationPresenter {
    private var isPresenting = false

    func show(configURL: URL, present: (ConfigLocationNotice) -> Void,
              restoreFocus: () -> Void) {
        guard !isPresenting else { return }
        isPresenting = true
        defer {
            isPresenting = false
            restoreFocus()
        }
        present(ConfigLocationNotice(configURL: configURL))
    }

    static func shouldRestoreFocus(popupVisible: Bool, applicationActive: Bool) -> Bool {
        popupVisible && applicationActive
    }
}
