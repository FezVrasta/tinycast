# Calendar and meeting join

Two surfaces over the Mac's own calendar: a **join card** at the top of an empty launcher, and a
**Join Next Meeting** global shortcut that never opens the palette at all. Around them sit four
launcher commands, a `My Schedule` sub-screen, and individual events as searchable launcher entries.

## Invariants

- **Nothing polls.** `.EKEventStoreChanged` is the reload signal, held through the RAII
  `NotificationToken`. The only timer is `MeetingClock`, which ticks on the minute boundary and only
  while the palette is up. Its `Task` is stored and cancelled in `stop()` and in an `isolated deinit`.
- **The card's window is `[start - lead, min(start + lead, end)]`.** The grace period exists because
  everyone joins late; the `min` is why it never outlives a meeting shorter than the lead.
- **Recurrence comes from `predicateForEvents(withStart:end:calendars:)`**, which expands occurrences
  itself. Masters are never fetched and recurrence is never hand-rolled.
- **`UpcomingWindow.agenda` is the only place that says which events count** — timed, not declined,
  in start order. The card, the chord, the schedule and the launcher slice all go through it, so they
  cannot drift apart.
- **`calendarEnabled` doubles as consent**, so it is in `SettingsBackupCoverage.deliberatelyExcluded`
  and only `CalendarCoordinator.setCalendarEnabled` may write it. Tinycast's own dialog comes first,
  the macOS prompt second, and only from the gesture that asked.
- **Per-calendar toggles live on `CalendarStore`, not `AppSettings`.** Calendar identifiers are
  machine-specific, so they are deliberately outside the backup mirror — the same reasoning as
  `palettePosition`.
- **`Model/` stays Foundation-only**; `calendar-test` compiles the shipped sources. EventKit lives in
  `Service/CalendarStore.swift` and nothing EventKit-shaped leaves it.

## The pure layer

`Model/` holds the whole decision, with every clock read injected:

- **`MeetingLink`** — the join link plus its `Provider`. Ten named services, plus `.generic` for any
  other `http(s)` link the event carries.
- **`MeetingEvent`** — one occurrence, flattened out of `EKEvent`.
- **`UpcomingWindow`** — `agenda`, `carded`, `joinable` and `countdown`.
- **`MeetingDay`** — the Today / Tomorrow buckets, mirroring the clipboard's `DateBucket`.

### Finding the link

`MeetingLink.detect(fields:)` is handed `[event.url, event.location, event.notes]` in that order and
scans each for `http(s)` runs. **A named provider anywhere beats a bare link found earlier**, so a
"reset your password" URL at the top of an invite never wins over the Meet link below it.

Link extraction is hand-rolled rather than `NSDataDetector`: a detector is not `Sendable`, and
rebuilding one per event costs more than the scan it replaces. A URL ends at whitespace or a quote,
and trailing punctuation is trimmed, so `(https://whereby.com/acme).` yields the URL alone.

**A URL on a known host that fails that provider's path rule is rejected outright, not demoted to
`.generic`** — `zoom.us/download` sits in half the invites people are sent, and `meet.google.com/tel/…`
is a dial-in helper rather than a meeting.

### Opening it

`MeetingLauncher.join` prefers the desktop app: `MeetingLink.appURL` rewrites a Zoom link to
`zoommtg://zoom.us/join?confno=…` (carrying `pwd` when present) and a `teams.microsoft.com` link to
`msteams:` plus its path and query. Nothing else is rewritten — the rest of the table has no
unambiguous scheme, and guessing one would open the wrong thing. If no app claims the scheme, the
plain `https` link opens instead.

No brand artwork ships with the app, so every named provider draws `video.fill` and the **name**
carries the identity; `.generic` draws `link`.

## The card

The card is `LauncherScreen.Row.meeting`, prepended the way the calculator card is. The two can never
both lead: **the calculator only answers a typed query and the card only an empty one**, which is what
keeps the flat selection index a single-row offset. `LauncherList.LeadCard` is that fact made
structural — one optional card, one selected flag, one activate closure, whichever feature owns it.

The countdown re-renders from `MeetingClock.now`, not from a keystroke, so `in 4 min` becomes
`in 3 min` on the boundary. A partial minute rounds **up** (`in 1 min` at 20 seconds out), and the
first minute past the start reads `now` rather than `0 min ago`.

Like the calculator card, a card appearing while the palette is already open shifts the highlight down
by one row. That is the existing behaviour of the row above it and is left alone.

## The chord

`UpcomingWindow.joinable` is deliberately wider than `carded`, and answers in this order:

1. Whatever the card is showing — so the chord always joins what is on screen.
2. Anything currently running, however long ago it started.
3. The next meeting with a link.

It reads the live clock rather than `MeetingClock`, because a chord fires with the palette closed and
nothing ticking.

## Commands

`Join Next Meeting` is the only one with a `HotKeyAction`; the other three are launcher rows and ⌘K
actions. All four leave the launcher when the feature is off, through
`CalendarCoordinator.applyEnabled`, the `applyQuicklinksPresence` twin.

| Command | Does |
| --- | --- |
| Join Next Meeting | Opens the link for the carded, running, or next meeting. Bindable. |
| Copy Meeting Link | The same meeting's link, to the pasteboard. |
| My Schedule | Opens the `.schedule` palette mode. |
| Open in Calendar | Hands the meeting to Calendar.app. |

A miss reports through the HUD (`Nothing to join right now`), not a dialog: it is transient and there
is nothing to acknowledge.

## Reading the store

`CalendarStore` queries `[startOfToday, endOfTomorrow + 1 day)` in the Mac's own zone. **The fetch
stays on the main actor**: two days of events is a sub-millisecond query and `EKEventStore` is not
`Sendable`, so pushing it off-main would be a fight with no measurable gain. Both the launch-time load
and the per-summon refresh are deferred into a `Task`, because the first EventKit query pays for its
XPC warm-up and both of those paths are protected.

The `EKEventStore` itself is built on first use, so a Mac with the feature off never loads EventKit.
After a grant the store is dropped and rebuilt — one built before the grant does not see the new
calendars.

`MeetingEvent.id` is the event identifier plus the occurrence's start, because a recurring series
shares one identifier across every instance. `calendarItemID` is kept separately: it is the only
handle `ical://ekevent/…` accepts, and a recurring occurrence opens its series.

A cancelled event never reaches a surface. A declined one is dropped by `agenda`, and an all-day one
with it.

## Settings

The Calendar pane carries the master switch (routed through the coordinator so the consent gate cannot
be bypassed), the `Join Next Meeting` recorder, the join-window picker, and the per-calendar checkbox
list — `LauncherItemsSection`'s shape, including the one `Form` row holding a `LazyVStack`, because a
`Form` realizes every row it is handed.

The hidden-calendar set stores **exclusions**, so a calendar added after the setting was written
defaults to on. Holidays and Birthdays are what people switch off.

The Permissions pane shows calendar access alongside Accessibility, but only ever opens System
Settings: the Calendar pane's own switch is the one place that may prompt.
