import AppKit

/// Owns joining a meeting: the consent gate, the card's and the chord's actions, feature presence.
@MainActor
final class CalendarCoordinator {
    private let store: CalendarStore
    private let clock: MeetingClock
    private let appIndex: AppIndex
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    /// Dialogs and the HUD, so both stay owned by `AppCore`.
    private unowned let core: AppCore

    init(
        store: CalendarStore,
        clock: MeetingClock,
        appIndex: AppIndex,
        settings: AppSettings,
        paletteCoordinator: PaletteCoordinator,
        core: AppCore
    ) {
        self.store = store
        self.clock = clock
        self.appIndex = appIndex
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// The window every surface reads, so the card, the chord and the schedule cannot disagree.
    var window: UpcomingWindow { UpcomingWindow(leadMinutes: settings.joinWindowMinutes.rawValue) }

    /// The meeting the join card shows, or nil when none is due. `now` comes from the ticking clock.
    var cardedMeeting: MeetingEvent? {
        guard settings.calendarEnabled else { return nil }
        return window.carded(from: store.events, now: clock.now)
    }

    /// Today and tomorrow, timed and accepted, in start order.
    var agenda: [MeetingEvent] { UpcomingWindow.agenda(from: store.events) }

    // MARK: - Feature switch

    /// The switch funnels here so enabling, which is also consent, confirms first.
    func setCalendarEnabled(_ enabled: Bool) {
        guard enabled != settings.calendarEnabled else { return }
        if !enabled {
            settings.calendarEnabled = false
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: "Enable calendar?",
                    message:
                        "Tinycast reads today's and tomorrow's events to find join links. Nothing leaves this Mac.",
                    symbol: "calendar", confirmTitle: "Continue", tone: .neutral,
                    confirmRole: .standard)
            else { return }

            settings.calendarEnabled = true
            // The one prompt for this feature, raised from the gesture that asked for it.
            guard await store.requestAccess() else { return }
            applyEnabled()
        }
    }

    /// Publishes or withdraws everything the feature contributes to the launcher.
    func applyEnabled() {
        let enabled = settings.calendarEnabled
        appIndex.setCommandsVisible(
            [.joinNextMeeting, .copyMeetingLink, .mySchedule, .openInCalendar], enabled)
        guard enabled else {
            store.stop()
            publishEntries()
            return
        }
        store.onChange = { [weak self] in self?.publishEntries() }
        store.start()
        publishEntries()
    }

    private func publishEntries() {
        guard settings.calendarEnabled, settings.calendarShowInLauncher else {
            appIndex.setMeetings([])
            return
        }
        appIndex.setMeetings(agenda.map(Self.entry(for:)))
    }

    private static func entry(for meeting: MeetingEvent) -> AppEntry {
        AppEntry(
            id: meeting.entryID, name: meeting.title,
            url: URL(
                string: "tinycast://meeting/"
                    + (meeting.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
                        ?? ""))!,
            bundleID: nil, kind: .meeting,
            matchAliases: [meeting.calendarName],
            symbolName: meeting.link?.provider.sfSymbol ?? "calendar")
    }

    // MARK: - Palette lifecycle

    /// Both hooks the palette needs: events go stale while it is closed, and the countdown only
    /// has to tick while someone can see it.
    func paletteDidShow() {
        guard settings.calendarEnabled else { return }
        clock.start()
        // Off the summon path: the card is observation-driven, so it can land a frame later.
        Task { store.reload() }
    }

    func paletteDidHide() {
        clock.stop()
    }

    // MARK: - Commands

    func joinNextMeeting() {
        guard let meeting = nextJoinable() else {
            report("Nothing to join right now")
            return
        }
        join(meeting)
    }

    func copyNextMeetingLink() {
        guard let meeting = nextJoinable() else {
            report("Nothing to join right now")
            return
        }
        copyLink(meeting)
    }

    func openNextMeetingInCalendar() {
        guard let meeting = window.joinable(from: store.events, now: Date()) ?? agenda.first else {
            report("Nothing scheduled today or tomorrow")
            return
        }
        openInCalendar(meeting)
    }

    /// Live rather than clock-driven: a chord fires without the palette, so nothing is ticking.
    private func nextJoinable() -> MeetingEvent? {
        guard settings.calendarEnabled else { return nil }
        return window.joinable(from: store.events, now: Date())
    }

    // MARK: - Row actions

    /// ↵ on a meeting row: join it, or hand a linkless one to Calendar.
    func activateMeeting(id: String) {
        guard let meeting = store.event(id: id) else { return }
        join(meeting)
    }

    func join(_ meeting: MeetingEvent) {
        guard let link = meeting.link else {
            openInCalendar(meeting)
            return
        }
        paletteCoordinator.hidePalette(restoreFocus: false)
        if MeetingLauncher.join(link) { return }
        Task {
            _ = await core.reportFailure(
                title: "Couldn't open the meeting link",
                message: "Nothing on this Mac would open \(link.url.absoluteString).",
                symbol: "video.slash", recovery: nil)
        }
    }

    func copyLink(_ meeting: MeetingEvent) {
        guard let link = meeting.link else {
            report("This meeting has no link")
            return
        }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(link.url.absoluteString)
        core.showMessage("Meeting link copied")
    }

    func openInCalendar(_ meeting: MeetingEvent) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        MeetingLauncher.showInCalendar(meeting)
    }

    func showSchedule() {
        paletteCoordinator.showPalette(mode: .schedule)
    }

    /// A miss is transient, so it reports through the HUD rather than a dialog needing dismissal.
    private func report(_ message: String) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        core.showMessage(message, tone: .neutral)
    }
}
