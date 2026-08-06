import SwiftUI

extension Notification.Name {
    /// Switch an already-open Settings window to a pane (object: the target `SettingsTab`).
    static let tinycastSelectSettingsTab = Notification.Name("TinycastSelectSettingsTab")
}

struct SettingsRootView: View {
    @State private var tab: SettingsTab

    init(initialTab: SettingsTab = .general) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            // Not a `TabView`: `NSTabView` re-hosts on selection and breaks the recorder.
            Group {
                switch tab {
                case .general: GeneralSettingsView()
                case .applications: ApplicationsSettingsView()
                case .systemSettings: SystemSettingsSettingsView()
                case .systemActions: SystemActionsSettingsView()
                case .commands: CommandsSettingsView()
                case .quicklinks: QuicklinksSettingsView()
                case .snippets: SnippetsSettingsView()
                case .windowManagement: WindowManagementSettingsView()
                case .clipboard: ClipboardSettingsView()
                case .emoji: EmojiSettingsView()
                case .permissions: PermissionsSettingsView()
                case .backup: BackupSettingsView()
                case .miscellaneous: MiscellaneousSettingsView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Only the background bleeds; the content keeps its safe area, so no spacer.
            .background(
                VisualEffectView(material: .contentBackground, blending: .behindWindow)
                    .ignoresSafeArea()
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .tinycastSelectSettingsTab)) { note in
            if let target = note.object as? SettingsTab { tab = target }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
            ForEach(SettingsTab.allCases) { item in
                sidebarRow(item)
            }

            Spacer()
        }
        .padding(.top, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(width: Theme.Size.settingsSidebar)
        .frame(maxHeight: .infinity)
        // Bleed to every edge; a plain `Divider` would stop at the safe area.
        .background(
            ZStack(alignment: .trailing) {
                VisualEffectView(material: .sidebar, blending: .behindWindow)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            }
            .ignoresSafeArea()
        )
    }

    private func sidebarRow(_ item: SettingsTab) -> some View {
        SidebarRow(
            title: item.title,
            systemImage: item.systemImage,
            tint: item.tint,
            isSelected: tab == item
        ) { tab = item }
    }
}

/// One sidebar entry: an icon tile and label, with selection and hover states.
private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.lg) {
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
                Text(title)
                    .font(Theme.Typography.rowTitle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The selected-row fill already marks the tab; a focus ring is just noise.
        .focusEffectDisabled()
        .onHover { hovering = $0 }
    }

    // Match the launcher list: a soft neutral fill, with a fainter hover layer.
    private var background: Color {
        if isSelected { return Theme.Colors.selection }
        if hovering { return Theme.Colors.rowHover }
        return .clear
    }
}
