import AppKit
import SwiftUI

/// Hosts the aux windows, torn down on close so their SwiftUI trees deallocate.
@MainActor
final class AuxWindowController: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]

    /// Returns `true` when a new window was created, `false` when an existing one was re-raised.
    @discardableResult
    func show<Content: View>(
        id: String, title: String, size: CGSize, seamlessTitleBar: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> Bool {
        let window: NSWindow
        let isNew: Bool
        if let existing = windows[id] {
            window = existing
            isNew = false
        } else {
            isNew = true
            var style: NSWindow.StyleMask = [.titled, .closable]
            if seamlessTitleBar { style.insert(.fullSizeContentView) }
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: style,
                backing: .buffered,
                defer: false
            )
            window.title = title
            // Edge-to-edge under a transparent titlebar, so it reads as one surface.
            if seamlessTitleBar {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.isMovableByWindowBackground = true
            }
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: content())
            // Keep the requested size: an unconstrained fill would blow the window up.
            hosting.sizingOptions = []
            window.contentView = hosting
            window.delegate = self
            window.center()
            windows[id] = window
        }
        // Promote to regular for a Dock icon; demoted when the last aux window closes.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // `NSApp.activate` is async, so re-assert key next turn to land it up front.
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
        }
        return isNew
    }

    /// Re-focus an open aux window, or false when none is; `windows` holds only live ones.
    @discardableResult
    func focusExisting() -> Bool {
        guard let window = windows.values.first(where: { $0.isVisible }) ?? windows.values.first
        else { return false }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// Close programmatically; `windowWillClose` does the teardown.
    func close(id: String) {
        windows[id]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let id = windows.first(where: { $0.value === window })?.key
        else { return }
        windows.removeValue(forKey: id)
        if windows.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}
