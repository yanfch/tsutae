import AppKit

@MainActor
final class AppPresentationController {
    static let shared = AppPresentationController()

    static let showDockIconDefaultsKey = "settings.showDockIcon"

    private init() {}

    func applyCurrentDockPreference() {
        applyDockIconVisibility(
            UserDefaults.standard.bool(forKey: Self.showDockIconDefaultsKey)
        )
    }

    func setDockIconVisible(_ isVisible: Bool) {
        UserDefaults.standard.set(isVisible, forKey: Self.showDockIconDefaultsKey)
        let shouldRestoreSettingsWindow = isVisible == false && SettingsWindowCoordinator.shared.hasVisibleSettingsWindow

        applyDockIconVisibility(isVisible)
        if shouldRestoreSettingsWindow {
            SettingsWindowCoordinator.shared.restoreSettingsAfterActivationPolicyChange()
        }
    }

    private func applyDockIconVisibility(_ isVisible: Bool) {
        NSApp.setActivationPolicy(isVisible ? .regular : .accessory)
    }
}
