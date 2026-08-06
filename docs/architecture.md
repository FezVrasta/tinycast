# Architecture

How Tinycast is wired together. See the per-subsystem docs for internals:
[palette](palette.md), [launcher](launcher.md), [calculator](calculator.md),
[clipboard](clipboard.md), [custom commands](custom-commands.md), [snippets](snippets.md),
[hotkeys](hotkeys.md), [ui](ui.md).
System-action catalog, launcher integration and permission behavior are documented in
[launcher](launcher.md#system-actions).

## The layering: pure, effect, view

Every feature splits three ways, and the split is what the standalone harnesses in `Tools/` check.

- **`Model/` — pure.** Foundation only (plus SQLite3 or CoreGraphics where the data demands it). No
  AppKit, no SwiftUI, no clock read, no filesystem, no network. Everything from the environment is
  **injected**: `CalcEngine` takes `now` / `calendar` / `rates`, `LauncherRankingStore` takes `now`
  and its file URL, `WindowActionMemory` takes `now` as a parameter, `UninstallRules` is handed
  directory *names* rather than URLs, and `QuicklinkStore` is handed the home directory. This is the
  layer that decides things.
- **`Service/` — effects.** Stores, monitors, runners, scanners and AppKit glue. Every
  `AXUIElement` call, `CGEventTap`, `NSWorkspace.open`, `URLSession` request, `FileManager` walk and
  CoreAudio read lives here. This is the layer that *does* things, and it is deliberately not
  compiled by any harness.
- **`UI/` and `Settings/` — views** plus the feature's coordinator. Declarative, thin, and holding no
  policy of its own.

The rule is checkable, which is the point: **a file under `Model/` may not import AppKit or SwiftUI**,
because `Tools/*-test.swift` compiles the shipped sources rather than a copy of them. A harness that
stops compiling is the signal that a decision has leaked into the effect layer, or an effect into the
decision layer.

The boundary is drawn so the *safe* state is the default. `CalcEngine.evaluate`'s `currency:`
parameter defaults to `.off`, so forgetting to pass a consented source disables the feature rather
than enabling it. Confirmation gates live in the coordinator, never in the runner — which is why
`ShellCommandRunner` and `SystemActionRunner` can stay harness-compilable while the "are you sure?"
step still cannot be bypassed.

Two things sit deliberately outside a feature folder: `Features/PaletteRowIndex.swift`, because the
palette rather than any one feature owns the flat selection index, and `DesignSystem/` +
`Platform/`, which are the shared primitives and system shims every feature draws on.

## Single-owner core

`AppCore.shared` (`App/AppCore.swift`) is a `@MainActor` singleton that owns every long-lived
manager — `AppIndex`, `ClipboardStore`, `ClipboardManager`, `SnippetsStore`,
`SnippetKeywordListener`, `SnippetTextInjector`, `HotKeyManager`, `AppSettings`, `FavoritesStore`,
`VisibilityStore`, `LauncherRankingStore`, `CustomCommandStore`, `CalculatorHistoryStore`,
`CurrencyRateStore`, `RunningAppsMonitor`, `PaletteState` — plus the window controllers, including
`DialogController` (dialogs are reached from elsewhere via `AppCore.showNotice` /
`confirm`, so the controller stays single-owned).
`AppDelegate.applicationDidFinishLaunching` calls
`AppCore.shared.start()` and nothing else; that is the single wiring point. All palette / paste /
launch actions are methods on `AppCore` that the SwiftUI views call.

## Entry points and windows

`TinycastApp` (`@main`) declares only a `MenuBarExtra` scene; everything else visible is driven
imperatively from AppKit.

- **Command palette** — a borderless floating `NSPanel` (`Palette/PalettePanel.swift`) hosting SwiftUI
  via `NSHostingView`, managed by `PaletteWindowController`. It toggles between a compact bar and the
  full launcher by resizing the window. `PaletteWindowController` solely owns the frame (resolved once
  per show to a top-left anchor so it grows downward), and the hosting view sets `sizingOptions = []`
  so SwiftUI never drives the window size — without that the hosting view resizes the panel to fit
  content and the top edge drifts on the compact↔expanded swap. The panel auto-dismisses on
  `windowDidResignKey`.
- **Settings / About** — plain `NSWindow`s via `AuxWindowController` (in
  `Windows/AuxWindowController.swift`). SwiftUI `Settings` / `Window` scenes are unreliable for accessory
  apps, so this is deliberate.
- **Dialogs** borderless `DialogPanel`s driven by `DialogController`, the app's only
  presenter for confirmations, failure reports and value prompts. **HUDs** are separate:
  `MessageHUDController` and `VolumeHUDController` (`Windows/HUD/`), both over a shared `HUDPresenter`. `NSAlert` is deliberately unused: its
  `runModal` nested run loop lets Carbon hotkeys stack dialogs, and an Aqua alert clashes with the
  forced-dark surface. Presentation is `async`, so nothing blocks the main actor. See
  [ui.md](ui.md#dialogs--hud).

The app forces `.darkAqua` appearance globally; the Liquid Glass material is tuned for a dark surface
only.

## Snippets

`SnippetRepository` is a Foundation-only `Sendable` value that owns all snippet disk access under
`~/Library/Application Support/<bundle-id>/Snippets/`, keeping stable, beta and dev isolated. The
model, Markdown codec, template engine, repository, keyword buffer, event classification and listener
lifecycle policy compile in the standalone harness without AppKit. `SnippetsStore` is the `@MainActor`
publisher/coordinator: initialization is cheap, repository work runs off-main, and a debounced
generation-ordered watcher reloads external edits and rearms after directory replacement. A stored
snippet is identified by its source file path, so editing frontmatter never invalidates selection or
launcher identity. `AppCore` projects every successful store snapshot into `AppIndex` and
`SnippetKeywordListener`; neither consumer reads or parses snippet files independently. The store
runs only while the feature switch is on — snippets ship off — so an untouched feature costs no
load, no watcher and no tap.

The feature switch doubles as keyword-expansion consent: it is an explicit opt-in confirmed in
Settings and excluded from settings backups. When an enabled feature comes back at startup, the
listener waits until Accessibility is granted — the only permission it needs, since its tap is
listen-only — then its health check installs the tap without prompting. Permission prompts
originate only from the enabling gesture in Settings, never from startup, the listener, callbacks or the
health check. The listener owns only matching and tap lifecycle; `AppCore` owns template expansion and
argument prompts, while `SnippetTextInjector` owns target activation, keyword deletion, text delivery,
temporary pasteboard restoration and cursor placement. See [snippets.md](snippets.md) for storage,
frontmatter, templates, conflicts, permissions and delivery invariants.

## Concurrency

The target builds in **Swift 6 language mode** (tools version 6.0, no language-mode override), so
data-race safety violations are hard errors. Almost everything is `@MainActor`; cross-actor model
types are `Sendable`. Heavy / IO work (app scan, image decode, the FX rate fetch) is deliberately
pushed off-main via `Task.detached` / `nonisolated`. Keep that boundary when adding code.
`SystemAction.swift` is the pure, `Sendable` metadata boundary; `SystemActionRunner` owns AppKit,
CoreAudio, process and Accessibility side effects, while `AppCore` owns confirmation and failure UI.

House idioms for the sharp edges:

- Block-observer lifetimes go through the RAII `NotificationToken` (`Platform/NotificationToken.swift`)
  instead of removal in a `deinit`.
- `ClipboardStore` uses `isolated deinit` for its SQLite teardown.
- Raw Carbon / C pointers get decoded to plain values before crossing into actor code (see
  `hotKeyCarbonEventHandler`).

## The tree

The folder layout is the layering above, made navigable — one folder per feature, each holding
everything that feature owns.

```
Tinycast/
  App/                  @main, AppDelegate, AppCore — the composition root
  DesignSystem/         Theme (the token source), KeyCapChip, Tooltip, SymbolImage,
                        VisualEffectView, PopoverMenu, SettingsComponents, Scrolling/, Interaction/
  Platform/             system shims: Permissions, LaunchAtLogin, CursorScreen, AppDisplayName,
                        NotificationToken, AppPaths, Signposts, Images/
  Palette/              the palette shell: PalettePanel, PaletteWindowController, RootPaletteView,
                        the PaletteScreen protocol, PaletteCoordinator, PaletteState / PaletteMode
  Windows/              the non-palette AppKit surfaces: AuxWindowController, Dialog/, HUD/, About/
  Features/
    PaletteRowIndex.swift        the flat selection index — palette-owned, so it sits at the top
    Launcher/  Clipboard/  Calculator/  Emoji/  Quicklinks/  Snippets/  Uninstall/
    SystemActions/  CustomCommands/  HotKeys/  Backup/  WindowManagement/  Onboarding/
        Model/     pure — the standalone-harness inputs
        Service/   effects — stores, monitors, runners, AppKit glue
        UI/        screens, views, and the feature's coordinator
        Settings/  the feature's own panes
    Settings/            the Settings shell only: SettingsRootView, SettingsTab, AppSettings,
                         and Panes/ for the two panes no feature owns (General, Permissions)
Tools/                   the standalone harnesses and the data generators
```

A larger feature splits into all four sub-folders; a small one stays flat. Every `SettingsTab` maps
to one `…SettingsView` built on the `SettingsPane` / `SettingsCard` scaffold, and the four
launcher-category panes are thin wrappers over the shared `LauncherItemsCard`.
