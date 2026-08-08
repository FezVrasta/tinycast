import SwiftUI

/// Settings' whole lifecycle, independent of the palette: opening, pane routing and closing.
/// Nothing here shows or hides the palette, and nothing in the palette closes this window.
@MainActor
final class SettingsCoordinator {
    private let window: AppWindowController
    /// Environment injection only — never for state this type owns.
    private unowned let core: AppCore

    init(core: AppCore) {
        self.core = core
        window = AppWindowController(
            title: "Settings", contentSize: Theme.Size.settingsWindow, resizable: true,
            autosaveName: "SettingsWindow", activation: core.activationPolicy)
    }

    /// A fresh window mounts on `tab`; an open one switches to it in place.
    func showSettings(tab: SettingsTab = .general) {
        let isNew = window.show {
            SettingsRootView(initialTab: tab)
                .environment(self.core)
                .environment(self.core.settings)
                .environment(self.core.appIndex)
                .environment(self.core.hotKeys)
                .environment(self.core.visibility)
                .environment(self.core.customCommands)
                .environment(self.core.snippetsStore)
                .environment(self.core.quicklinks)
        }
        if !isNew {
            NotificationCenter.default.post(name: .tinycastSelectSettingsTab, object: tab)
        }
    }

    func showAbout() {
        showSettings(tab: .about)
    }

    func showBackupSettings() {
        showSettings(tab: .backup)
    }

    /// ⌘Q and the window's close button land here; the app itself keeps running.
    func closeSettings() {
        window.close()
    }

    func focusExisting() -> Bool {
        window.focus()
    }
}
