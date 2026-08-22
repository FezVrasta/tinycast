// Standalone test for meeting-link detection, the join window and the day buckets.
import Foundation

@main
@MainActor
struct CalendarTests {
    static var failures = 0
    static var passes = 0

    /// Injected everywhere a date is built, so no assertion depends on the machine's zone.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func main() {
        providerDetection()
        rejectsNonMeetingPages()
        fieldPrecedence()
        linkScanning()
        appURLRewrites()
        agendaFiltering()
        cardWindow()
        chordFallsBackWiderThanTheCard()
        countdownStrings()
        dayBuckets()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Provider detection

    static func providerDetection() {
        expect(provider("https://us02web.zoom.us/j/8901234567") == .zoom, "a Zoom /j/ link is Zoom")
        expect(provider("https://zoom.us/w/123?pwd=xy") == .zoom, "a Zoom webinar link is Zoom")
        expect(provider("https://acme.zoomgov.com/j/55") == .zoom, "zoomgov is Zoom")
        expect(
            provider("https://meet.google.com/abc-defg-hij") == .googleMeet,
            "a Meet code is Google Meet")
        expect(
            provider("https://teams.microsoft.com/l/meetup-join/19%3ameeting_Zm8") == .teams,
            "a Teams meetup-join link is Teams")
        expect(provider("https://teams.live.com/meet/9312") == .teams, "a Teams personal link is Teams")
        expect(provider("https://acme.webex.com/acme/j.php?MTID=m1") == .webex, "a Webex site is Webex")
        expect(provider("https://meet.jit.si/DailyStandup") == .jitsi, "meet.jit.si is Jitsi")
        expect(provider("https://8x8.vc/room") == .jitsi, "8x8.vc is Jitsi")
        expect(provider("https://whereby.com/acme") == .whereby, "whereby.com is Whereby")
        expect(provider("https://chime.aws/1234567890") == .chime, "chime.aws is Amazon Chime")
        expect(
            provider("https://global.gotomeeting.com/join/123456789") == .gotoMeeting,
            "gotomeeting.com is GoTo Meeting")
        expect(provider("https://app.goto.com/meeting/xy") == .gotoMeeting, "app.goto.com is GoTo")
        expect(provider("https://bluejeans.com/123456") == .blueJeans, "bluejeans.com is BlueJeans")
        expect(provider("https://join.skype.com/abcdef") == .skype, "join.skype.com is Skype")
        expect(
            provider("https://example.com/rooms/standup") == .generic,
            "an unknown host is still a joinable link")
        expect(MeetingLink.detect(in: "no links here at all") == nil, "plain prose has no link")
        expect(
            MeetingLink.detect(in: "mailto:someone@example.com") == nil,
            "a mailto address is not a join link")
    }

    static func rejectsNonMeetingPages() {
        expect(
            MeetingLink.detect(in: "https://zoom.us/download") == nil,
            "a Zoom download page is not a meeting, and does not fall back to a bare link")
        expect(
            MeetingLink.detect(in: "https://meet.google.com/tel/123") == nil,
            "a Meet dial-in helper is not a meeting")
        expect(
            MeetingLink.detect(in: "https://teams.microsoft.com/downloads") == nil,
            "a Teams download page is not a meeting")
        expect(
            MeetingLink.detect(in: "Join: https://zoom.us/download or https://zoom.us/j/42")?.provider
                == .zoom,
            "a rejected page does not stop the real link being found")
    }

    // MARK: - Where the link comes from

    static func fieldPrecedence() {
        let link = MeetingLink.detect(fields: [
            "https://example.com/first", "https://meet.google.com/abc-defg-hij"
        ])
        expect(link?.provider == .googleMeet, "a named provider beats a bare link found earlier")
        let bare = MeetingLink.detect(fields: [nil, "https://example.com/room", "https://other.test/x"])
        expect(
            bare?.url.absoluteString == "https://example.com/room",
            "with no named provider the earliest bare link wins")
        expect(MeetingLink.detect(fields: [nil, nil]) == nil, "empty fields yield no link")
    }

    static func linkScanning() {
        expect(
            MeetingLink.detect(in: "Dial in (https://whereby.com/acme).")?.url.absoluteString
                == "https://whereby.com/acme",
            "trailing punctuation is not part of the URL")
        expect(
            MeetingLink.detect(in: "<a href=\"https://whereby.com/acme\">join</a>")?.url
                .absoluteString == "https://whereby.com/acme",
            "a quoted href yields the URL alone")
        expect(
            MeetingLink.detect(in: "line one\nhttps://whereby.com/acme\nline three")?.url
                .absoluteString == "https://whereby.com/acme",
            "a newline ends the URL")
        expect(
            MeetingLink.detect(in: "HTTPS://WHEREBY.COM/Acme")?.provider == .whereby,
            "the scheme and host match case-insensitively")
    }

    static func appURLRewrites() {
        expect(
            link("https://us02web.zoom.us/j/8901234567")?.appURL?.absoluteString
                == "zoommtg://zoom.us/join?confno=8901234567",
            "a Zoom link rewrites to the desktop app")
        expect(
            link("https://us02web.zoom.us/j/89?pwd=SeCrEt")?.appURL?.absoluteString
                == "zoommtg://zoom.us/join?confno=89&pwd=SeCrEt",
            "the Zoom passcode travels with the rewrite")
        expect(
            link("https://teams.microsoft.com/l/meetup-join/19%3ameeting_Zm8?x=1")?.appURL?
                .absoluteString == "msteams:/l/meetup-join/19%3ameeting_Zm8?x=1",
            "a Teams link rewrites to msteams:, path and query intact")
        expect(
            link("https://meet.google.com/abc-defg-hij")?.appURL == nil,
            "a provider with no unambiguous scheme opens the web instead")
        expect(link("https://example.com/room")?.appURL == nil, "a bare link opens the web")
    }

    // MARK: - The join window

    static func agendaFiltering() {
        let events = [
            event(id: "late", start: 60), event(id: "early", start: 0),
            event(id: "allday", start: 30, isAllDay: true),
            event(id: "declined", start: 30, isDeclined: true)
        ]
        let agenda = UpcomingWindow.agenda(from: events)
        expect(agenda.map(\.id) == ["early", "late"], "the agenda is timed, accepted and in start order")
    }

    static func cardWindow() {
        let window = UpcomingWindow(leadMinutes: 5)
        let meeting = event(id: "standup", start: 60, minutes: 30)
        let start = at(60)
        expect(
            window.carded(from: [meeting], now: start.addingTimeInterval(-300))?.id == "standup",
            "the card appears exactly five minutes out")
        expect(
            window.carded(from: [meeting], now: start.addingTimeInterval(-301)) == nil,
            "one second earlier it is not there yet")
        expect(
            window.carded(from: [meeting], now: start.addingTimeInterval(299))?.id == "standup",
            "it survives almost five minutes past the start, because everyone joins late")
        expect(
            window.carded(from: [meeting], now: start.addingTimeInterval(300)) == nil,
            "the grace period ends five minutes past the start")

        let brief = event(id: "brief", start: 60, minutes: 3)
        expect(
            window.carded(from: [brief], now: at(60).addingTimeInterval(179))?.id == "brief",
            "a three-minute meeting is carded until it ends")
        expect(
            window.carded(from: [brief], now: at(60).addingTimeInterval(180)) == nil,
            "the grace period never outlives the meeting")

        let linkless = event(id: "linkless", start: 60, link: nil)
        expect(
            window.carded(from: [linkless], now: start) == nil,
            "a meeting with no link is never carded")
        expect(
            UpcomingWindow.agenda(from: [linkless]).map(\.id) == ["linkless"],
            "but it stays on the agenda, so it is still listed and searchable")
    }

    static func chordFallsBackWiderThanTheCard() {
        let window = UpcomingWindow(leadMinutes: 5)
        let running = event(id: "running", start: 0, minutes: 60)
        let next = event(id: "next", start: 120)
        let now = at(0).addingTimeInterval(1800)

        expect(window.carded(from: [running], now: now) == nil, "half an hour in, the card is gone")
        expect(
            window.joinable(from: [running], now: now)?.id == "running",
            "the chord still joins the call that is running")
        expect(
            window.joinable(from: [next], now: now)?.id == "next",
            "with nothing running it offers the next one")
        expect(
            window.joinable(from: [running, next], now: at(120).addingTimeInterval(-120))?.id
                == "next",
            "inside the card window the chord joins what is on screen")
        expect(
            window.joinable(from: [], now: now) == nil, "an empty day offers nothing to join")
        expect(
            window.joinable(from: [event(id: "past", start: -120)], now: now) == nil,
            "a meeting that is over is not offered")
    }

    static func countdownStrings() {
        let start = at(60)
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(-240)) == "in 4 min",
            "four minutes out reads as in 4 min")
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(-60)) == "in 1 min",
            "one minute out reads as in 1 min")
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(-1)) == "in 1 min",
            "a partial minute rounds up rather than reading as now")
        expect(UpcomingWindow.countdown(to: start, now: start) == "now", "the start reads as now")
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(59)) == "now",
            "the first minute after the start still reads as now")
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(120)) == "2 min ago",
            "past the start it counts up")
    }

    // MARK: - Day buckets

    static func dayBuckets() {
        let now = date(year: 2026, month: 8, day: 23, hour: 22)
        expect(
            MeetingDay(for: now.addingTimeInterval(3600), now: now, calendar: calendar) == .today,
            "an hour before midnight is still today")
        expect(
            MeetingDay(for: now.addingTimeInterval(2 * 3600), now: now, calendar: calendar)
                == .tomorrow,
            "an hour past midnight is tomorrow")
        expect(
            MeetingDay(for: now.addingTimeInterval(48 * 3600), now: now, calendar: calendar) == nil,
            "the day after tomorrow has no bucket")
        expect(
            MeetingDay(for: now.addingTimeInterval(-24 * 3600), now: now, calendar: calendar) == nil,
            "yesterday has no bucket")
    }

    // MARK: - Helpers

    static let epoch = Date(timeIntervalSinceReferenceDate: 0)

    static func at(_ minutes: Int) -> Date {
        epoch.addingTimeInterval(TimeInterval(minutes * 60))
    }

    static func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static func link(_ text: String) -> MeetingLink? { MeetingLink.detect(in: text) }

    static func provider(_ text: String) -> MeetingLink.Provider? { link(text)?.provider }

    static func event(
        id: String, start minutes: Int, minutes duration: Int = 30, isAllDay: Bool = false,
        isDeclined: Bool = false, link: MeetingLink? = MeetingLink.detect(in: "https://example.com/x")
    ) -> MeetingEvent {
        MeetingEvent(
            id: id, title: id, start: at(minutes),
            end: at(minutes).addingTimeInterval(TimeInterval(duration * 60)),
            isAllDay: isAllDay, isDeclined: isDeclined, calendarID: "cal", calendarName: "Work",
            calendarItemID: id, link: link)
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            fail(label)
        }
    }

    static func fail(_ label: String) {
        print("FAIL: \(label)")
        failures += 1
    }
}
