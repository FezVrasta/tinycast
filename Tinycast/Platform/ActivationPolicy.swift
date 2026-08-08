import AppKit

/// The app runs as an accessory; a titled window needs `.regular` for a Dock icon, a main menu and
/// working traffic lights. Held by window identity rather than a count, so a repeated open or close
/// is a no-op instead of stranding the Dock icon on a drifted tally.
@MainActor
final class ActivationPolicy {
    private var openWindows: Set<ObjectIdentifier> = []

    func windowDidOpen(_ window: NSWindow) {
        openWindows.insert(ObjectIdentifier(window))
        NSApp.setActivationPolicy(.regular)
    }

    func windowDidClose(_ window: NSWindow) {
        openWindows.remove(ObjectIdentifier(window))
        if openWindows.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}
