import Observation

/// The open Settings window's current pane and its back/forward history: written by the sidebar,
/// read by the titlebar.
///
/// Deliberately not on `AppCore`. This is one window's session, not long-lived app state — it is
/// built when the window opens and released in `windowWillClose`, so history never survives a close.
@MainActor
@Observable
final class SettingsNavigationState {
    private var history: SettingsHistory

    init(tab: SettingsTab) {
        history = SettingsHistory(current: tab)
    }

    var tab: SettingsTab { history.current }
    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    func select(_ tab: SettingsTab) { history.select(tab) }
    func goBack() { history.goBack() }
    func goForward() { history.goForward() }
}
