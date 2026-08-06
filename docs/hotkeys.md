# Hotkeys (in-house, zero dependencies)

`Features/HotKeys/` holds:

- `KeyShortcut` — Sendable model, Carbon keycode + modifiers, layout-aware glyphs via `UCKeyTranslate`.
- `HotKeyBinding` — what an action is actually bound to: a `.combo(KeyShortcut)` or a
  `.doubleTap(DoubleTapModifier)`.
- `HotKeyCenter` — the Carbon `RegisterEventHotKey` layer, pausable.
- `DoubleTapModifier` / `DoubleTapDetector` / `DoubleTapMonitor` — the double-tap stack.

`HotKeyManager` owns them all: persistence, conflict lookup, and dispatch. Every action reads and
writes one `HotKeyBinding`, so the two kinds share persistence, conflict detection, the recorder and
the keycap rendering — only the _engine_ differs.

## Persistence

Bindings persist as JSON strings under `hotkey.<action>` UserDefaults keys, computed in one place —
`HotKeyAction.defaultsKey`, which doubles as the `HotKeyCenter` registration id. The set of bound
bundle IDs lives in `boundAppBundleIDs` and is re-registered on launch. System Settings panes use
`boundPaneBundleIDs`; custom commands and quicklinks use their stable UUIDs in
`boundCustomCommandIDs` and `boundQuicklinkIDs`. Those two are the per-item case — unlike a fixed
catalog, there is no `allCases` to walk — so each needs an index for `start()` to re-register from
and to prune bindings whose record was deleted while Tinycast wasn't running. That prune is why
`QuicklinkStore` loads at launch even when the feature is off
(see [quicklinks.md](quicklinks.md#hotkeys)).

`HotKeyBinding` takes the synthesised `Codable`, so a `.combo` writes
`{"combo":{"_0":{"carbonKeyCode":N,"carbonModifiers":N}}}` and a `.doubleTap` writes
`{"doubleTap":{"_0":"command"}}`. `KeyShortcut` keeps a hand-written `init(from:)` — not a format seam,
but the guarantee that every decode runs through the initializer that masks device modifier bits off.
`SettingsBackup.HotkeyBackup` stores the same values, so the backup file carries this shape too; only
export → import within one build is guaranteed to round-trip.

`LegacyHotKeyRecords` adopts the records shipped before this namespace existed — `v0.7.5` wrote a bare
`{"carbonKeyCode":N,"carbonModifiers":N}` under `KeyboardShortcuts_<name>`. It runs once from
`start()`, consumes each old record, and never overwrites a key the user has already rebound. It is
scheduled for deletion; see [refactor/POLICY.md](refactor/POLICY.md).

System actions and window commands are the fixed-catalog case: they persist under
`hotkey.systemAction.<raw-id>` and `hotkey.windowCommand.<raw-id>`
and need **no** bound-ID index, because `start()` and `conflictOwner` can just iterate `allCases` and
`register` no-ops on an unbound item. A registered window-command shortcut still runs nothing while the
feature switch is off — `AppCore.runWindowCommand` re-checks it (see
[window-management.md](window-management.md)); a system-action shortcut likewise goes through
`AppCore.runSystemAction(id:)`, so the confirmation gate holds for a hotkey exactly as it does for the
palette.

## Double-tap modifiers

Any action can instead be bound to a **double-tapped lone modifier** — ⌃, ⌥, ⇧ or ⌘. Carbon cannot
register a modifier-only shortcut at all, so this is a separate engine that meets the combo path only
at `HotKeyBinding`.

`DoubleTapDetector` is the recognizer: Foundation-only, pure, and clock-injected (`now` is a caller-
supplied monotonic timestamp), so `Tools/hotkey-test.swift` drives it without an event tap. A **tap**
is a press that starts from no modifiers held, keeps exactly one of the four held with no `fn`
alongside, sees no key press or mouse click, and is released within `maxHold` (250 ms — the same
window `HyperKeyTap` calls a quick press). A **double-tap** is a second tap of the same modifier
starting within `maxGap` (300 ms) of the first one's release.

Only _momentary_ keys may feed `hasOtherModifiers`. Caps Lock must not: `maskAlphaShift` tracks the
**latch**, not a press, so testing it would disqualify every tap for as long as Caps Lock is on and
silently kill the feature. Caps Lock is still ineligible as a _binding_ — that is what the Hyper Key
is for.

It **fires on the second release, not the second press**. The modifier is then already up when the
action runs, so the palette never opens with a phantom ⌘ held and focus restoration isn't polluted —
and "double-tap and hold" is a deliberate non-event.

`DoubleTapMonitor` is the one platform file. It is a **listen-only** `CGEventTap` and it installs only
while something is actually bound to a double-tap, so users who never use the feature pay nothing. Two
details are load-bearing:

- It is `.tailAppendEventTap`, unlike the two head-inserted taps, so it observes events **after**
  `HyperKeyTap`'s rewrite. A Hyper-remapped right-side modifier therefore arrives as the full ⌃⌥⇧⌘
  chord and correctly reads as "not a lone modifier" — the left-side twin still double-taps.
- Like every keyboard tap it needs the **Accessibility** grant, and it never prompts for it. The
  binding records regardless; the recorder shows an inline warning that opens System Settings, and the
  one-second health timer installs the tap the moment the grant lands.

⇧ is bindable this way even though `KeyShortcut` rejects a bare ⇧ combo: a double-_tap_ is unambiguous
where a bare ⇧ combo would shadow typing.

## The Hyper Key

`HyperKeyTap` turns one physical key — Caps Lock or a right-side modifier — into the ⌃⌥(⇧)⌘ chord
system-wide. It is a **modifying** `CGEventTap`, a separate layer from `HotKeyCenter` because Carbon
cannot intercept a lone key at all. The rewritten flags flow onward into Carbon matching, so existing
combo hotkeys fire from Hyper+key with no extra registration.

Which key is chosen persists as a `HyperKey` string raw value in `AppSettings` — renaming a case is a
migration, and a removed case decodes to `.none`. **F-keys are deliberately not candidates:** the
top-row media functions fire *below* the tap, so binding F1 as Hyper still dimmed the display.

### Caps Lock has to stop being Caps Lock

The caps-lock toggle — both the LED and the latch — happens below every `CGEventTap`, so no tap can
suppress it. The key must therefore stop being Caps Lock **at the source**: while Caps Lock serves as
Hyper, `CapsLockRemap` installs an IOKit `UserKeyMapping` remapping it to **F18**, the same mechanism
`hidutil` uses. The tap then intercepts F18 in its place. The remap is cleared on unbind and on quit,
and never survives a reboot. Remaps apply on a serial queue, so rapid on→off→on toggles land in call
order instead of racing as independent detached tasks and leaving the wrong final state.

Because the remap is asynchronous, there is a fallback for the window before it takes hold: the key
still arrives as Caps Lock, so the tap rides the modifier path instead. The LED toggles during that
window — that is un-remapped HID behaviour, not something Tinycast can stop.

Once remapped, Caps Lock arrives as **keyDown/keyUp** rather than `flagsChanged`. Both ends are
converted into Left Control `flagsChanged` transitions, so everything downstream sees the Hyper chord
move with the key rather than a swallowed press. A classic `IOHIDSystem` connection reads and drives
the Caps Lock LED and lock state; it is used only by the explicit Quick Press toggle and the one-time
unlatch when the remap is installed.

### Press tracking uses toggle semantics

`flagsChanged` does not describe its own direction, so a modifier-style Hyper key is tracked by
toggling. The obvious alternative — querying `CGEventSource` key state — **races the release**,
inverting the state machine and breaking Quick Press. A missed release therefore lingers only until
the watchdog or the next press clears it. Work that posts events or touches IOKit is deferred to the
next runloop turn rather than run inside the tap callback, where it would risk re-entrancy.

The flags OR'd into every rewritten event are the generic ⌃⌥(⇧)⌘ masks **plus the left-side device
bits** (`NX_DEVICE…KEYMASK`, from `IOLLEvent.h`). Some consumers distinguish sides, and generic-only
flags do not always read as fully pressed. The Hyper key's own residue is scrubbed in the same pass:
Caps Lock's alpha-shift bit, or — for a key modifier outside the Hyper set — its generic mask and both
device bits. Events the tap posts carry a `"TYCT"` marker in `.eventSourceUserData`, the same FourCC
`HotKeyCenter` uses, so the tap never reacts to its own synthetics.

### Lifecycle

Like every keyboard tap it needs the **Accessibility** grant and never prompts for it. A one-second
watchdog runs while a key is configured: it retries installation until the grant lands, notices
revocation, revives a tap the system disabled on timeout or user input, and clears a stuck hold. On
fast user switching another session owns the keyboard, so half-held state is dropped and rewriting
stops until this session is active again. The HID remap outlives the process, so
`applicationWillTerminate` hands the key back to the system before exiting.

## Recorder

The settings recorder (`Features/Settings/ShortcutRecorder.swift`) is deliberately **not** a focusable
control: the active recorder is `HotKeyManager.recordingAction` state, and keys are captured by local
NSEvent monitors while both engines are paused. It records both kinds — type a combo, or double-tap a
modifier — by feeding its `.flagsChanged` / `.keyDown` monitors into the _same_ `DoubleTapDetector`
the global monitor uses, so recording needs no event tap and no permission.

Setting `recordingAction` is what starts and stops the capture, so there is exactly **one**
`ShortcutCaptureSession` (`HotKeys/Service/`) for the app rather than one per row — which is what lets the
callout above the field render the live state from outside the row that opened it. The field itself
only ever shows the binding; the prompt, the live preview and the conflict message all live in the
callout. See [ui.md](ui.md#the-shortcut-recorder-callout).
