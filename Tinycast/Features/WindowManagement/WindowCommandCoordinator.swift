import AppKit

/// Owns window-command activation: the one funnel from a palette row or a global hotkey to the mover.
@MainActor
final class WindowCommandCoordinator {
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    private let windowMover: WindowMover

    init(
        settings: AppSettings, paletteCoordinator: PaletteCoordinator, windowMover: WindowMover
    ) {
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.windowMover = windowMover
    }

    /// The one funnel for both palette activation and a command's global hotkey, so the feature switch
    /// can't be bypassed by either — a shortcut stays registered while the feature is off and must move
    /// nothing.
    ///
    /// The command acts on the app the user was in, so the palette hands focus back before dispatching,
    /// the same dance the paste path does. Focus is restored rather than dropped: the window being moved
    /// is the one they want to keep working in.
    func runWindowCommand(id: WindowCommand.ID) {
        guard settings.windowManagementEnabled else { return }
        let target = paletteCoordinator.targetApp
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: true) }
        windowMover.perform(
            id, target: target, gap: CGFloat(settings.windowGap),
            cycleOnRepeat: settings.windowCycleOnRepeat)
    }
}
