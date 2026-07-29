# macOS 15 (Sequoia) channel

Tinycast's `main` targets macOS 26 and uses Liquid Glass. This branch (`compat/macos15`) ships the
same app to macOS 15 **without changing a single file on `main`**.

## Why a patch and not a lower deployment target

`glassEffect(_:in:)` is `@available(macOS 26)`. Lowering `MACOSX_DEPLOYMENT_TARGET` is only a build
setting, but the compiler then hard-errors at every call site, and no build flag suppresses that —
the deployment target *is* the availability contract. So some source must be gated. It's two call
sites, and they live here as `macos15.patch` instead of on `main`.

Verified: with those two sites gated, the whole app compiles at `-target arm64-apple-macos15.0`,
builds `Release`, and produces `minos 15.0` / `LSMinimumSystemVersion 15.0` against SDK 26.5. The
six SwiftUI glass symbols become **weak** imports, so dyld binds them to null on Sequoia and the
`#available` guard means they're never called.

## What's gated

Both in one `ViewModifier` (`FrostedSurface`) in `Tinycast/Core/Theme.swift`:

| Helper | macOS 26 | macOS 15 |
|---|---|---|
| `frosted(in:)` — floating pill + menu circle | `glassEffect(.regular.interactive().tint(glassFrost))` | `.ultraThinMaterial` + frost overlay + 0.5pt hairline + soft shadow |
| `frostedMenu(in:)` — popover panels | `glassEffect(.regular)` | same fallback |

`docs/ui.md` confines glass to floating controls, so that is the entire visual surface affected. The
main palette surface is `NSVisualEffectView` vibrancy — macOS 10.10 API, unchanged on Sequoia, it
just renders as classic blur.

## Build with Xcode 26, not Xcode 16

The artifact is built against the **new** SDK with only the deployment target lowered. An abandoned
earlier attempt built on `macos-15` with Xcode 16.2 instead and needed ~30 files of unrelated
concurrency churn (`@MainActor` annotations, `@preconcurrency import Darwin`,
`#if compiler(>=6.2)` fences). None of that is necessary. Don't redo it.

## Everyday use

```sh
./compat/release.sh           # ship it (see below) — the normal entry point
./compat/verify.sh --quick    # ~35s: patch applies + typechecks at 15 AND 26
./compat/verify.sh            # + Release build, 15.0 floor assert, weak-linkage assert
```

`verify.sh` never touches your working tree — it exports tracked files to a temp dir and patches the
copy, so it's safe to run with uncommitted changes on any branch.

When `main` moves, resync:

```sh
git checkout compat/macos15 && git merge main
./compat/verify.sh
```

If the patch has rotted or `main` gained a new macOS 26-only API, run the **`macos15-compat` skill**
(`.claude/skills/macos15-compat/`) — it regenerates the patch and re-verifies.

## Cutting a release

One command, from this branch:

```sh
./compat/release.sh              # sync with main, verify, tag, push — the whole thing
./compat/release.sh --dry-run    # everything except publishing
```

The version defaults to the newest **stable** mainline tag, so `v0.7.5` ships as `v0.7.5-sequoia` —
the Sequoia build tracks whatever shipped on macOS 26. Override with `--version 0.8.0`, replace an
existing tag with `--retag`.

If it exits non-zero (patch rotted, or `main` gained a macOS 26-only API), run the **`macos15-compat`
skill** — it repairs and then releases. That's the intended path: run the skill, do no git yourself.

Releases are **tag-triggered** rather than a button, because `workflow_dispatch` only fires for
workflows present on the default branch and this one deliberately isn't there. `release.sh` creates
and pushes the tag for you.

The workflow verifies compatibility *before* publishing anything, then builds, asserts the 15.0
floor on the shipping binary, packages a DMG, publishes a GitHub Release, and bumps the tap cask.

Identity notes:

- **Bundle ID and display name match the mainline channel** (`com.tinycast.app` / `Tinycast`), so a
  Sequoia user who later upgrades to macOS 26 keeps prefs, caches, login item and Accessibility
  grant — all keyed by `Bundle.main.bundleIdentifier`.
- Releases are **always** marked prerelease, including stable-Sequoia:
  `website/src/lib/use-version.ts` reads `/releases/latest`, which GitHub defines as the latest
  *non-prerelease*, so a full release here would hijack the version shown on the site.

## One-time tap setup (required before the first release)

There is **no in-app updater** — Homebrew is the only update path, so the cask guards are the entire
safety mechanism keeping a Sequoia machine from being handed the macOS 26 build. In
`abue-ammar/homebrew-tinycast`, copy `Casks/tinycast.rb` to `Casks/tinycast-sequoia.rb` and:

```ruby
# Casks/tinycast-sequoia.rb
depends_on macos: "<= :sequoia"
conflicts_with cask: "abue-ammar/tinycast/tinycast"
# ...url points at the -sequoia DMG asset

# Casks/tinycast.rb  — add:
depends_on macos: ">= :tahoe"
conflicts_with cask: "abue-ammar/tinycast/tinycast-sequoia"
```

Keep the existing `postflight` that runs `xattr -dr com.apple.quarantine`. The cask-bump step
hard-errors if `Casks/<cask>.rb` doesn't already exist, so do this first. Repeat for
`tinycast@beta-sequoia` if you want a Sequoia beta channel.

## Not verified

The build is proven to compile, link and declare a macOS 15 floor. **Nothing here has been run on
real macOS 15.** Before publishing, on a Sequoia machine confirm: the fallback material reads as a
floating control rather than a flat box; the Accessibility prompt and paste-to-`previousApp` focus
restoration work; the Hyper Key `hidutil` caps remap works; emoji grid and clipboard image
thumbnails render. The `onScrollGeometryChange`-driven edge dissolve and thin scrollbar are the
highest-risk items — those APIs are macOS 15.0 exactly, with no headroom.
