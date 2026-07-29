---
name: macos15-compat
description: Sync and repair Tinycast's macOS 15 (Sequoia) compatibility patch against whatever state main is in. Use when the Sequoia release fails, compat/verify.sh reports the patch no longer applies, main gained a macOS 26-only API, or before cutting a -sequoia tag. Triggers on "fix macOS 15", "sequoia build broken", "update the compat patch", "macos15 compatibility".
---

# Repair Tinycast's macOS 15 compatibility

Bring `compat/macos15.patch` back in sync with `main`, whatever state `main` is in, and prove it
builds. Finish with a green `./compat/verify.sh` or a clear statement of what is blocked.

## Hard rules

1. **Never modify a tracked file on `main`.** Not even temporarily with the intent to revert. The
   patch exists precisely so `main` stays byte-identical. All gating happens in a throwaway export.
2. **Never commit to `main`.** All work lands on `compat/macos15`.
3. **Build with Xcode 26 and lower only the deployment target.** Do not "fix" macOS 15 by building
   with an older Xcode — that path forces ~30 files of unrelated concurrency churn
   (`@MainActor` annotations, `@preconcurrency import Darwin`, `#if compiler(>=6.2)` fences) for
   zero benefit. All of that was tried on an abandoned branch; don't repeat it.
4. **Keep the patch minimal.** Gate the API, don't refactor. Every extra line is future merge
   conflict surface. Do not touch prose/comments in `main` just to make them read better.

## Step 1 — Orient without disturbing anything

```sh
git rev-parse --abbrev-ref HEAD          # which branch is checked out
git status --porcelain                   # must be clean before switching branches
git log --oneline -1 main compat/macos15
```

Get onto `compat/macos15` **without** touching the user's `main` checkout. Prefer a worktree:

```sh
git worktree add /tmp/tinycast-compat compat/macos15   # then work in /tmp/tinycast-compat
```

If `compat/macos15` does not exist yet, create it from `main`: `git worktree add -b compat/macos15 /tmp/tinycast-compat main`.

## Step 2 — Fast-forward the branch onto main

`compat/macos15` must contain everything `main` has, plus `compat/` and the Sequoia workflow.

```sh
git merge --no-edit main
```

Conflicts here should only ever be in `compat/` or `.github/workflows/release-sequoia.yml` (files
`main` doesn't have, so normally none at all). If a conflict appears in `Tinycast/**`, something has
gone wrong — the branch must never carry its own edits to app sources. Resolve by taking `main`'s
side verbatim: `git checkout --theirs <path>`.

## Step 3 — Diagnose

```sh
./compat/verify.sh --quick
```

Exit code tells you which repair you need:

| Exit | Meaning | Go to |
|---|---|---|
| 0 | Already in sync. Run the full `./compat/verify.sh`, then Step 6. | — |
| 1 | Patch no longer applies — a gated call site moved. | Step 4 |
| 2 | Compile/availability error — usually a NEW macOS 26 API in `main`. | Step 5 |
| 3 | Built, but wrong deployment floor or non-weak glass symbol. | Step 5 |

## Step 4 — Regenerate a rotted patch

The patch is a plain unified diff of two throwaway trees. Rebuild it; never hand-edit hunk offsets.

```sh
SP=$(mktemp -d)
mkdir -p "$SP/pristine" "$SP/gated"
git archive HEAD Tinycast | tar -x -C "$SP/pristine"
cp -R "$SP/pristine/Tinycast" "$SP/gated/Tinycast"
```

Now edit **`$SP/gated/Tinycast/...` only** to re-apply the gates (Step 5 lists them), then:

```sh
: > compat/macos15.patch
for f in Core/Theme.swift Features/PopoverMenu.swift; do   # add any newly-gated file here
  diff -u --label "a/Tinycast/$f" --label "b/Tinycast/$f" \
    "$SP/pristine/Tinycast/$f" "$SP/gated/Tinycast/$f" >> compat/macos15.patch
done
```

`diff` exits 1 when files differ, which is the normal case — don't let `set -e` abort the loop.

## Step 5 — Gate a macOS 26-only API

**The compiler reports availability errors ONE PER RUN.** A clean-looking run after one fix does not
mean you are done — iterate `./compat/verify.sh --quick` until it is genuinely clean. This is the
single easiest way to declare victory too early here.

The existing gates, both funnelled through one `ViewModifier` in `Tinycast/Core/Theme.swift`:

- `frosted(in:)` — the interactive floating pill/circle. macOS 26: `glassEffect(.regular.interactive().tint(Theme.Colors.glassFrost), in:)` + `.tint(.clear)`. Sequoia: `.ultraThinMaterial` + a `Theme.Colors.glassFrost` overlay + a 0.5pt `Theme.Colors.border.opacity(0.6)` hairline + `shadow(black 0.22, radius 6, y 2)`.
- `frostedMenu(in:)` — the non-interactive popover panel; same fallback, plain `.glassEffect(.regular, in:)` on 26.
- `Tinycast/Features/PopoverMenu.swift` calls `.frostedMenu(in:)` instead of `.glassEffect` directly.

For a **new** 26-only API, follow the same shape:

- Route it through **one** helper (extend `FrostedSurface` or add a sibling in `Theme.swift`) rather than sprinkling `#available` at call sites — that is what keeps the patch two hunks instead of ten.
- Use a plain `if #available(macOS 26.0, *)`. No `#if compiler(>=6.2)` fence is needed; the toolchain is always Xcode 26.
- Put anything that only exists to serve the glass path (like `.tint(.clear)`) **inside** the 26 branch.
- Glass carries its own elevation; a hand-drawn shadow belongs only on the fallback branch.
- Consult `docs/ui.md` for the intended look before inventing a fallback. Reuse `Theme.swift` tokens; do not add new ones.

Facts worth not re-deriving:

- Only `glassEffect` is genuinely 26-gated. `isolated deinit` back-deploys fine to target 15 under Xcode 26 — it is **not** a blocker; do not "fix" it.
- `onScrollGeometryChange` / `onGeometryChange` are macOS **15.0** exactly. They work, but macOS 15 is a hard floor; macOS 14 is not reachable without real work.
- `LSMinimumSystemVersion` is `$(MACOSX_DEPLOYMENT_TARGET)` in `Info.plist`, so the command-line override propagates with no `xcodegen` run.
- Exit 3 with a non-weak glass symbol means an `#available` guard is missing somewhere, not a linker flag problem — a strong undefined symbol makes dyld kill the app at launch on Sequoia.

## Step 6 — Prove it and report

```sh
./compat/verify.sh          # full: both targets, Release build, 15.0 floor, weak-linkage assert
```

Then commit **only** `compat/` (and the workflow, if you touched it):

```sh
git add compat .github/workflows/release-sequoia.yml
git status --short          # confirm NOTHING under Tinycast/ is staged
git commit -m "compat: resync macOS 15 patch with main@<short-sha>"
```

If anything under `Tinycast/**` shows up staged, stop and unstage it — the branch must never carry
app-source edits.

Report to the user:

- what had drifted and why (moved call site / new API / merge);
- the `verify.sh` result, quoting the `minos=` line;
- that **nothing on `main` changed** (`git -C <main-checkout> status --porcelain` is empty);
- the next command they'd run to ship: `git tag v<version>-sequoia && git push origin v<version>-sequoia`;
- **explicitly, that no runtime testing on real macOS 15 happened** unless it did. A green build
  proves it compiles, links, and declares a 15.0 floor — not that the fallback material looks right
  or that the app behaves. Say so; don't let a green check imply more than it shows.

Do not push and do not create tags unless the user asks.
