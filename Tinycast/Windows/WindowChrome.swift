import AppKit

/// Titlebar decoration a window opts into. `AppWindowController` holds it for the window's lifetime
/// and drops it on close, so anything the chrome drives dies with the window it decorated.
@MainActor
protocol WindowChrome: AnyObject {
    func install(in window: NSWindow)
}
