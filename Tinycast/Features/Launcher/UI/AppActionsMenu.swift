import SwiftUI

/// Actions menu content for a launcher app, shown bottom-right on right-click or from the Actions pill.
@MainActor
enum AppActionsMenu {
    static func content(
        app: AppEntry, searchQuery: String, core: AppCore, favorites: FavoritesStore,
        running: Bool, onResetRanking: @escaping () -> Void
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: openTitle(app), systemImage: "list.bullet.rectangle", shortcut: "↵"
            ) { core.launch(app, searchQuery: searchQuery) }
        ]
        if favorites.isFavorite(app) {
            items.append(
                PopoverMenuItem(title: "Remove from Favorites", systemImage: "star.slash") {
                    favorites.toggle(app)
                })
        } else {
            items.append(
                PopoverMenuItem(title: "Add to Favorites", systemImage: "star") {
                    favorites.toggle(app)
                })
        }
        if core.launcherRanking.hasRanking(for: app.preferenceKey) {
            items.append(
                PopoverMenuItem(title: "Reset Ranking", systemImage: "arrow.counterclockwise") {
                    onResetRanking()
                })
        }
        if app.canRevealInFinder {
            items.append(
                PopoverMenuItem(
                    title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵"
                ) {
                    core.showInFinder(app)
                })
        }
        if running, app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: "Quit Application", systemImage: "power", shortcut: "⌃⇧Q",
                    isDestructive: true
                ) {
                    core.quit(app)
                })
        }
        if app.kind == .application {
            items.append(
                PopoverMenuItem(
                    title: "Uninstall Application", systemImage: "trash", isDestructive: true
                ) {
                    core.beginUninstall(app)
                })
        }
        return PopoverMenuContent(header: app.name, items: items)
    }

    private static func openTitle(_ app: AppEntry) -> String {
        switch app.kind {
        case .application: return "Open Application"
        case .systemSettings: return "Open System Setting"
        case .command: return "Run Command"
        case .customCommand: return "Run Custom Command"
        case .snippet: return "Paste Snippet"
        case .systemAction: return "Run System Action"
        case .windowCommand: return "Move Window"
        case .quicklink: return "Open Quicklink"
        }
    }
}
