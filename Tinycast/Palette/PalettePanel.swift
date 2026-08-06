import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless floating panel that hosts the SwiftUI command palette.
final class PalettePanel: NSPanel {
    /// Bare backspace, which the field editor swallows before `onKeyPress` could see it.
    var onBareBackspace: (() -> Bool)?
    /// Command chords the field editor swallows, plus the ones no main menu handles.
    var onCommandShortcut: ((NSEvent) -> Bool)?
    /// Arms hover from `sendEvent`, the one place both event streams pass through.
    weak var paletteState: PaletteState? {
        didSet {
            paletteState?.onMenuOpenChanged = { [weak self] open in self?.setSearchCaretHidden(open) }
        }
    }

    /// Keys driving an open menu; they reach `onKeyPress` even while editing is frozen.
    private static let menuNavKeys: Set<Int> = [
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab
    ]

    /// Caret hiding on SwiftUI's own field editor. See docs/palette.md#menu-open-input-freeze.
    private func setSearchCaretHidden(_ hidden: Bool) {
        guard let editor = firstResponder as? NSTextView else { return }
        editor.insertionPointColor = hidden ? .clear : .white
        // Force a redraw so the caret flips at once rather than waiting out the blink timer.
        editor.updateInsertionPointStateAndRestartTimer(!hidden)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved: paletteState?.hoverHighlightArmed = true
        case .keyDown: paletteState?.hoverHighlightArmed = false
        default: break
        }
        // A footer menu owns the keyboard. See docs/palette.md#menu-open-input-freeze.
        if event.type == .keyDown,
            paletteState?.menuOpen == true,
            event.modifierFlags.isDisjoint(with: [.command, .control]),
            !Self.menuNavKeys.contains(Int(event.keyCode)) {
            return
        }
        if event.type == .keyDown,
            Int(event.keyCode) == kVK_Delete,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            onBareBackspace?() == true {
            return
        }
        // The controller owns the chords the field editor or a missing main menu would eat.
        if event.type == .keyDown,
            event.modifierFlags.contains(.command),
            onCommandShortcut?(event) == true
        {
            return
        }
        super.sendEvent(event)
    }
    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 475),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        acceptsMouseMovedEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        // The controller owns the frame; without this the top edge drifts on the swap.
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
