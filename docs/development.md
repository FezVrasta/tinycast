# Development

The local loop: set up, build, run, regenerate. Shipping a build is [release.md](release.md);
verifying a change is [testing.md](testing.md).

## Requirements

- macOS 26 or later (Liquid Glass).
- Xcode 26 — it provides the SwiftUI macro plugin and the SDK.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), and for linting:
  `brew install swiftlint`.

## First-time setup

Create the `Tinycast Self-Signed` code-signing identity once — builds sign with it, which is what keeps
macOS from forgetting the Accessibility grant on every rebuild. Follow **[signing.md](signing.md) §1**,
a few `openssl`/`security` commands.

That is the whole required setup. Editor configuration is personal and the repo does not prescribe it;
the section below is a note for anyone who wants it, not a step.

## Build & run

```sh
open Tinycast.xcodeproj    # then ⌘R
```

Or from the command line:

```sh
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug build
```

`xcodebuild` uses whatever `xcode-select` points at; if that's the Command Line Tools rather than
Xcode, prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the SwiftUI
`@State`/`@FocusState` macros need Xcode's macOS platform).

`Tinycast.xcodeproj` is committed and generated from `project.yml` via XcodeGen — after changing
project settings in `project.yml`, run `xcodegen generate` and commit the result. There is no
`Package.swift`, and `Bundle.module` must never be used ([decisions.md](decisions.md) entry 25).

### The dev channel

Debug builds are a separate channel: **`Tinycast Dev.app`**, bundle id `com.tinycast.app.dev`. Every
persisted thing is keyed by bundle id — `~/Library/Preferences/<id>.plist` (settings and hotkey
bindings), `~/Library/Caches/<id>/` (clipboard history, calculator history, exchange rates, frequent
emoji), `~/Library/Application Support/<id>/` (the onboarding marker and snippets), the `SMAppService`
login item, and the Accessibility / Input Monitoring (TCC) grants — so a local build can neither read
nor clobber an installed app's state, and both run side by side.

Consequences worth knowing:

- The dev build asks for Accessibility on its own the first time, and starts with **no** hotkeys bound
  and onboarding unseen. Grant and bind once; it persists across rebuilds, because the fixed build path
  and the `Tinycast Self-Signed` identity keep the TCC grant alive.
- Don't bind the same global hotkey in both — whichever registered first wins.
- The Hyper Key's Caps Lock remap is `hidutil` state, which is **system-wide, not per-bundle**: quitting
  one build clears the remap for the other, which then needs a rebind or a relaunch to restore it.

## Editor

Xcode works out of the box and needs nothing here. Everything below is optional, and which editor you
use is your business — the repo prescribes none of it.

VS Code gets code intelligence from SourceKit-LSP, which needs a `buildServer.json` because there is no
`Package.swift`. Generate it once:

```sh
brew install xcode-build-server
xcode-build-server config -project Tinycast.xcodeproj -scheme Tinycast \
    --build_root "$PWD/build/DerivedData"
```

`--build_root` must match the `-derivedDataPath` in `.vscode/tasks.json`, or the editor indexes a
different build than the one **F5** runs. The file is git-ignored because it embeds an absolute path,
and `sourcekit-lsp` looks for it at the workspace root by name, so it cannot live in a subfolder.

Then populate the index with one build — the **Build Tinycast.app (debug)** task (⌘⇧B) or **F5**. That
task keeps `.compile` in sync afterwards, so new and renamed files keep resolving.

### Symbols in `Tests/`

`xcodebuild` never compiles the harnesses — they are not in the Xcode project — so nothing emits a
compile command for them, and without one an open harness reports every shipped type it uses as *cannot
find in scope*. Measured on `fuzz-test.swift`: 60 errors with no entry, 0 with one.

```sh
./Scripts/run-tests.sh --index    # merge the harness compile commands into .compile
```

It reads the source lists from `run-tests.sh` itself, so they cannot drift from what the suite actually
compiles. The build task runs it too. Two things it has to get right, both of which fail silently
otherwise: every path is absolute, because `sourcekit-lsp` resolves the command itself and does not
apply `directory` to relative arguments; and the command carries an explicit `-sdk`.

Re-run it after adding a harness, then **Swift: Restart LSP Server** from the Command Palette — an
already-running server does not re-read `.compile`.

## Linting

```sh
./Scripts/lint.sh          # lint the whole project
./Scripts/lint.sh --fix    # auto-correct the mechanical subset first
```

[SwiftLint](https://github.com/realm/SwiftLint) is the only code-quality tool here. `.swiftlint.yml` at
the repo root excludes the generated files and the two off-limits files in `DesignSystem/Scrolling/`,
and carries the two comment rules from [standards.md](standards.md#comments) as `custom_rules`.

The config sticks to rules that catch defects and stays quiet about style, because **there is no
formatter** — see [decisions.md](decisions.md) entry 26 for the measurements behind that. Formatting is
Xcode's re-indent (⌃I), as it always has been. Two consequences worth knowing:

- `empty_count` is **disabled**, and `isEmpty`-style rewrites are unsafe here generally:
  `LauncherRankingRecord` and `PaletteRowIndex` have a `count` that is a hit count, not a collection
  count. A rule that rewrites `count > 0` to `!isEmpty` on them does not compile.
- `force_try` is an error; `force_cast` only warns, because the AX and AppKit bridges have four
  legitimate ones.

Errors block, warnings do not. CI runs this same script on every PR and annotates the diff with each
violation — see [release.md](release.md#continuous-integration) — so run it locally first rather than
finding out from a review.

## Generated data

Two Swift files are emitted by scripts and must never be hand-edited. Both download their source, so
run them online, then commit the result:

```sh
node Scripts/gen-emoji.js            # -> Tinycast/Features/Emoji/Model/EmojiData.generated.swift
node Scripts/gen-currencies.js       # -> Tinycast/Features/Calculator/Model/CurrencyData.generated.swift
```

`gen-currencies.js` joins two sources on the ISO code: **Frankfurter**'s currency list — the same feed
`CurrencyRateStore` fetches rates from, so the table and the rate source cannot drift apart — and
**Unicode CLDR**'s `en` currency data, which supplies display names, signs and the singular/plural
noun. It reads the pinned `cldr-json` checkout rather than the host's `Intl`, whose output shifts with
the local ICU version and would make the file unreproducible.

Only unambiguous data is emitted. Anything two currencies claim — `dollars`, `pounds`, `krona` — is
left out and decided by hand in `CalcCurrency.contested`, the one currency table still written by hand.
Re-run the script when a currency is added or retired; nothing breaks in the meantime, since an
unquoted code just reports "no exchange rate".
