---
name: macos15-compat
description: Release Tinycast for macOS 15 (Sequoia), or repair the compatibility patch when it breaks. Run from the compat/macos15 branch and it handles everything — sync with main, fix the patch, verify, tag, push. Use for "release for macOS 15", "ship sequoia build", "fix macOS 15", "sequoia build broken", "update the compat patch".
---

# Ship / repair Tinycast for macOS 15

You own this end to end. The user runs the skill and does no git themselves — no merge, no tag, no
push. Drive it to a published release, or to a clear statement of what is blocked.

**Default action is a full release.** If the user said "check", "verify", "just sync" or similar,
pass `--dry-run` and publish nothing.

## Hard rules

1. **Never modify a tracked file on `main`.** Not even temporarily meaning to revert it. The patch
   exists so `main` stays byte-identical. All gating happens in a throwaway export.
2. **`compat/macos15` must never carry edits under `Tinycast/`** — only `compat/` and the workflow.
   `release.sh` aborts if it detects otherwise.
3. **Build with Xcode 26 and lower only the deployment target.** Never "fix" macOS 15 by building
   with an older Xcode — that forces ~30 files of unrelated concurrency churn (`@MainActor`
   annotations, `@preconcurrency import Darwin`, `#if compiler(>=6.2)` fences). It was tried on an
   abandoned branch; don't repeat it.
4. **Keep the patch minimal.** Gate the API, don't refactor, don't touch prose. Every extra line is
   future conflict surface.

## Step 1 — Run it

```sh
./compat/release.sh          # or --dry-run when the user only wants a check
```

This does the whole job: preflight, `git fetch`, merge `origin/main`, `compat/verify.sh`, derive the
version from the newest stable mainline tag, push the branch, create and push `v<version>-sequoia`.
The tag is what triggers the release workflow.

If the user isn't on `compat/macos15`, the script refuses rather than switching branches under them.
Check out the branch (or add a worktree) and re-run:

```sh
git worktree add /tmp/tinycast-compat compat/macos15
```

**Exit 0 → go to Step 4.** Otherwise:

| Exit | Meaning | Go to |
|---|---|---|
| 1 | Merge conflict with `origin/main` | Step 2 |
| 2 | Verify failed — patch rotted, or a new macOS 26 API | Step 3 |
| 3 | Preflight (dirty tree, wrong branch, tag exists, bad version) | fix as reported, re-run |

For "tag already exists": that version was already shipped to Sequoia. Ask the user whether they
want `--retag` (replace it) or a different `--version`. Don't guess.

## Step 2 — Merge conflict

Only `compat/` files should ever conflict. A conflict under `Tinycast/**` means the branch wrongly
carries app-source edits — take `main`'s side verbatim (`git checkout --theirs <path>`) and mention
it in your report, because it shouldn't have happened.

## Step 3 — Repair, then re-run

Diagnose with the fast loop (~35s):

```sh
./compat/verify.sh --quick
```

**Exit 1 — the patch no longer applies.** Regenerate it; never hand-edit hunk offsets:

```sh
SP=$(mktemp -d)
mkdir -p "$SP/pristine" "$SP/gated"
git archive HEAD Tinycast | tar -x -C "$SP/pristine"
cp -R "$SP/pristine/Tinycast" "$SP/gated/Tinycast"
```

Edit **`$SP/gated/Tinycast/...` only** to re-apply the gates, then:

```sh
: > compat/macos15.patch
for f in Core/Theme.swift Features/PopoverMenu.swift; do   # add any newly-gated file
  diff -u --label "a/Tinycast/$f" --label "b/Tinycast/$f" \
    "$SP/pristine/Tinycast/$f" "$SP/gated/Tinycast/$f" >> compat/macos15.patch
done
```

`diff` exits 1 when files differ — that's the normal case, don't let it abort the loop.

**Exit 2 — an unguarded macOS 26 API.** The gates, both funnelled through one `ViewModifier` in
`Tinycast/Core/Theme.swift`:

- `frosted(in:)` — interactive floating pill/circle. 26: `glassEffect(.regular.interactive().tint(Theme.Colors.glassFrost), in:)` + `.tint(.clear)`. Sequoia: `.ultraThinMaterial` + `Theme.Colors.glassFrost` overlay + 0.5pt `Theme.Colors.border.opacity(0.6)` hairline + `shadow(black 0.22, radius 6, y 2)`.
- `frostedMenu(in:)` — non-interactive popover panel; same fallback, plain `.glassEffect(.regular, in:)` on 26.
- `Tinycast/Features/PopoverMenu.swift` calls `.frostedMenu(in:)`, not `glassEffect` directly.

For a new 26-only API, match that shape: route it through **one** helper in `Theme.swift` rather than
sprinkling `#available` at call sites; plain `if #available(macOS 26.0, *)` (no `#if compiler` fence
— the toolchain is always Xcode 26); anything existing only to serve glass (like `.tint(.clear)`)
goes **inside** the 26 branch; a hand-drawn shadow belongs only on the fallback branch. Check
`docs/ui.md` for the intended look and reuse `Theme.swift` tokens — don't add new ones.

**⚠️ The compiler reports availability errors ONE PER RUN.** A clean run right after one fix proves
nothing. Loop `./compat/verify.sh --quick` until it is genuinely clean. This is the easiest way to
declare victory too early here.

Facts worth not re-deriving:

- Only `glassEffect` is genuinely 26-gated. `isolated deinit` back-deploys fine at target 15 under
  Xcode 26 — **not** a blocker, don't "fix" it.
- `onScrollGeometryChange` / `onGeometryChange` are macOS **15.0** exactly. They work, but 15 is a
  hard floor; macOS 14 is not reachable without real work.
- `LSMinimumSystemVersion` is `$(MACOSX_DEPLOYMENT_TARGET)`, so the override propagates with no
  `xcodegen` run.
- Exit 3 with a non-weak glass symbol means a missing `#available` guard, not a linker flag — a
  strong undefined symbol makes dyld kill the app at launch on Sequoia.

Then commit **only** `compat/` and re-run Step 1:

```sh
git add compat && git status --short   # confirm NOTHING under Tinycast/ is staged
git commit -m "compat: resync macOS 15 patch with main@<short-sha>"
./compat/release.sh
```

## Step 4 — Watch the run and report

The tag triggers the workflow; don't stop at the tag push.

```sh
gh run list --workflow=release-sequoia.yml -L1
gh run watch <id>    # or poll; report the outcome
```

If it fails, read the failing step's log (`gh run view <id> --log-failed`) and say what broke. Two
first-release blockers to recognize:

- `Casks/tinycast-sequoia.rb not found in tap` → the one-time tap setup in `compat/README.md` hasn't
  been done. Homebrew is the only update path (no Sparkle), so its `depends_on macos:` guards are
  the sole thing keeping a Sequoia machine off the macOS 26 build.
- `SIGNING_P12_BASE64 not set` → without it the build would be signed differently and silently drop
  every user's Accessibility grant.

Report, briefly:

- the version shipped and the release URL;
- anything that had drifted and what you did about it;
- that **`main` is unchanged** — verify with `git diff --stat origin/main..origin/compat/macos15`
  showing nothing under `Tinycast/`;
- **explicitly, that nothing was tested on real macOS 15.** A green workflow proves it compiles,
  links, and declares a 15.0 floor — not that the fallback material looks right or the app behaves.
  Say so plainly; never let a green check imply more than it shows.
