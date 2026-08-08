import AppKit
import SwiftUI

/// The Settings window's body, as a real AppKit split view.
///
/// Not a SwiftUI `HStack` or `NavigationSplitView`: only a genuine `NSSplitViewController` lets the
/// toolbar use `.sidebarTrackingSeparator`, which is what seats the pane title and the back/forward
/// control in the detail column rather than crammed against the traffic lights.
@MainActor
final class SettingsSplitViewController: NSSplitViewController {
    init(sidebar: some View, detail: some View) {
        super.init(nibName: nil, bundle: nil)

        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(rootView: sidebar))
        // Fixed, as the column was before: nothing here reflows with width.
        sidebarItem.minimumThickness = Theme.Size.settingsSidebar
        sidebarItem.maximumThickness = Theme.Size.settingsSidebar
        sidebarItem.canCollapse = false

        let detailItem = NSSplitViewItem(viewController: NSHostingController(rootView: detail))
        detailItem.minimumThickness = Theme.Size.settingsDetailMinimum

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
