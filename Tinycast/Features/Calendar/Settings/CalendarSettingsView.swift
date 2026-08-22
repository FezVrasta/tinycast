import SwiftUI

struct CalendarSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(CalendarStore.self) private var store

    var body: some View {
        @Bindable var settings = settings
        Form {
            FeatureSwitchSection(
                header: "Calendar",
                enableTitle: "Join meetings from Tinycast",
                enableSubtitle:
                    "Reads today's and tomorrow's events to find join links. Nothing leaves this Mac.",
                launcherSubtitle: "List individual meetings alongside apps and commands.",
                isEnabled: enabledBinding,
                showsInLauncher: $settings.calendarShowInLauncher)

            if store.access == .denied {
                Section {
                    SettingsRow(
                        title: "Calendar access is off",
                        subtitle: "Turn Tinycast on under Privacy & Security ▸ Calendars."
                    ) {
                        Button("Open System Settings…") { Permissions.openCalendarSettings() }
                    }
                }
            }

            Section {
                SettingsRow(title: "Join Next Meeting") {
                    ShortcutRecorder(action: .joinNextMeeting)
                }
                Picker(selection: $settings.joinWindowMinutes) {
                    ForEach(JoinWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                } label: {
                    Text("Show the join card")
                    Text("How early the card appears, and how long past the start it stays.")
                }
            } header: {
                Text("Joining")
            }
            .settingsEnabled(settings.calendarEnabled)

            CalendarPickerSection()
                .settingsEnabled(settings.calendarEnabled)
        }
        .formStyle(.grouped)
        .releasesFocusOnOutsideClick()
    }

    /// Routed through the coordinator so enabling, which is also consent, confirms first.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.calendarEnabled },
            set: { core.calendarCoordinator.setCalendarEnabled($0) }
        )
    }
}

/// The per-calendar switches. Machine-local by nature, so they live on the store rather than
/// `AppSettings`, and never travel in a settings backup.
private struct CalendarPickerSection: View {
    @Environment(CalendarStore.self) private var store
    @State private var query = ""

    private var calendars: [MeetingCalendar] {
        guard !query.isEmpty else { return store.calendars }
        return store.calendars.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.accountName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Section {
            SettingsFilterField(prompt: "Search calendars…", query: $query)

            if calendars.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // One row holding a lazy stack: a `Form` realizes every row it is handed.
                LazyVStack(spacing: 0) {
                    ForEach(calendars) { calendar in
                        if calendar.id != calendars.first?.id { Divider() }
                        CalendarRow(calendar: calendar)
                            .padding(.vertical, Self.rowPadding)
                    }
                }
                .padding(.vertical, -Self.rowPadding)
            }
        } header: {
            Text("Calendars")
        }
    }

    /// A grouped `Form` row's own vertical padding.
    private static let rowPadding: CGFloat = 15

    private var emptyMessage: String {
        if !query.isEmpty { return "No matches for “\(query)”." }
        return store.access == .granted ? "No calendars on this Mac." : "Nothing to show yet."
    }
}

private struct CalendarRow: View {
    let calendar: MeetingCalendar
    @Environment(CalendarStore.self) private var store

    var body: some View {
        SettingsRow(title: calendar.title, subtitle: calendar.accountName) {
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("Include \(calendar.title) in meetings")
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { store.isEnabled(calendar) },
            set: { store.setEnabled($0, for: calendar) }
        )
    }
}
