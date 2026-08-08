import SwiftUI

/// The grouped pane list. Stock `.sidebar` styling throughout — the group headers, the selection
/// capsule and the symbol tint are all system-supplied, so nothing here styles a row.
struct SettingsSidebarView: View {
    @Environment(SettingsNavigationState.self) private var navigation

    var body: some View {
        List(selection: selection) {
            ForEach(SettingsSection.allCases) { section in
                Section(section.title) {
                    ForEach(section.tabs) { tab in
                        Label(tab.title, systemImage: tab.systemImage).tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// `List` hands back an optional selection; routing it through `select` is what records history.
    private var selection: Binding<SettingsTab?> {
        Binding(
            get: { navigation.tab },
            set: { if let tab = $0 { navigation.select(tab) } }
        )
    }
}
