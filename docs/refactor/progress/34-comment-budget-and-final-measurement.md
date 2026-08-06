# Phase 34 — Comment budget, comment pass, and final measurement

---

## Status

| Field                         | Value                                                |
| ----------------------------- | ---------------------------------------------------- |
| **Status**                    | Complete                                             |
| **Started**                   | 2026-08-07                                           |
| **Completed**                 | 2026-08-07                                           |
| **Operator**                  | abue-ammar                                           |
| **Branch**                    | `refactor/34-comment-budget-and-final-measurement`   |
| **Commit**                    | see branch HEAD                                      |
| **Claude conversations used** | 1                                                    |
| **Actual effort**             | ~1 session vs. estimate of L                         |

---

## Completed tasks

- [x] Objective 1 — the `AGENTS.md` comment clause replaced by the six-rule budget
- [x] Objective 2 — every stacked block and over-cap line triaged: delete, compress, or relocate
- [x] Objective 3 — baselines re-measured and the before/after table published (see caveat below)
- [x] Objective 4 — `docs/architecture.md` describes the pure/effect/view layering and the folder tree

## Acceptance criteria

- [x] AC1 — six-rule budget in `AGENTS.md` — verified by: the section is present, with the two
      greppable commands appended so rules 1 and 2 are checkable rather than aspirational.
      **Not in its own commit** — see Deviations.
- [x] AC2 — stacked comment blocks **0** — verified by: the phase's own `awk` command returns `0`
      across the whole tree, *including* the two off-limits files (neither contained one).
- [x] AC3 — comment lines over 100 chars **0** outside the off-limits files — verified by: 24 remain
      in total, **23 of them in `EdgeDissolve.swift` / `ThinScrollbar.swift`** (must-not-change) and
      **1 in `CurrencyData.generated.swift`** (the phase forbids editing generated files). Editable
      hand-written source is at 0.
- [x] AC4 — every deleted paragraph is redundant or lives in `docs/` — verified by: each long block
      was checked against its subsystem doc first; where the doc did not already carry it, the
      explanation was **relocated before** the source comment was cut (four new doc sections, below).
- [x] AC5 — no code statement changed — verified **mechanically**:
      `git diff -- Tinycast/ | grep '^[-+]' | grep -v '^[-+][-+]' | grep -v '^\s*[-+]\s*//'`
      returns **0 lines**. The Swift half of the diff is provably comment-only.
- [x] AC6 — `docs/architecture.md` describes the layering and the tree — verified by: two new
      sections, "The layering: pure, effect, view" and "The tree".
- [~] AC7 — measurement table complete — **partially met.** Every row is present, but the seven
      runtime rows have **no baseline to compare against**; see Measurements.
- [x] AC8 — all harnesses pass, Debug and Release build, UI pixel-identical — verified by: 18/18
      harnesses green, both configurations clean at 0 → 0 warnings. UI identity follows from AC5
      rather than from a visual pass — nothing in this diff compiles.

---

## Verification

| Checklist                  | Result   | Notes                                                                 |
| -------------------------- | -------- | --------------------------------------------------------------------- |
| `checklists/build.md`      | PASS     | Debug + Release, 0 → 0 warnings on an on-branch baseline; `xcodegen` idempotent |
| `checklists/testing.md`    | PASS     | All **18** harnesses (the kickoff says 19; there are 18 — phase 33 established that) |
| `checklists/regression.md` | NOT RUN  | **Operator waived further testing.** No manual pass, no runtime sweep |
| `checklists/review.md`     | NOT RUN  | Its §5 comment greps are the phase's own AC2/AC3, which did run       |

### Measurements

| Metric                         | Phase 01 baseline | Now                                    | Δ                                            |
| ------------------------------ | ----------------- | -------------------------------------- | -------------------------------------------- |
| Release binary size            | 3,473,448 B       | 3,655,736 B                            | +182,288 (+5.25 %), **under 4 MB**           |
| Cold launch, median of 3       | **never captured**| not measured                           | no baseline exists                            |
| `AppCore.start`                | **never captured**| not measured                           | no baseline exists                            |
| `AppIndex.scan` cold / warm    | **never captured**| not measured                           | no baseline exists                            |
| `PaletteWindowController.show` | **never captured**| not measured                           | no baseline exists                            |
| `UninstallScanner.scan`        | **never captured**| not measured                           | no baseline exists                            |
| RSS after 10 palette opens     | **never captured**| not measured                           | no baseline exists                            |
| RSS after 50 clipboard images  | **never captured**| not measured                           | no baseline exists                            |
| `RootPaletteView` line count   | 1126              | **662**                                | −41 %; target ~350 **not reached**            |
| `AppCore` line count           | 1348              | **284**                                | −79 %; target ~250, close                     |
| Comment lines / total          | 1850 / 26379      | **1653 / 27289**                       | −197 comments; density 7.0 % → 6.1 %          |
| Stacked blocks                 | 181               | **0**                                  | target met                                    |
| Comments > 100 chars           | 953               | **0** editable / 23 off-limits / 1 gen | target met everywhere it could be             |

**The binary delta is not this phase's.** Comments do not compile, so phase 34's own contribution to
binary size is exactly zero; the +182 KB accumulated across phases 02–33 and is reported here only
because this is the roadmap's report card and phase 01 is the only anchor that exists.

**The seven runtime rows cannot be filled.** Phase 01's progress file records that its objective 3
never landed — `AppCore.start`, `AppIndex.scan`, `PaletteWindowController.show`,
`UninstallScanner.scan`, cold launch and both RSS figures were never captured. Measuring them now
would produce "after" numbers with nothing to compare against, so they are left blank rather than
presented as a result. The signposts are in place, so any of them can still be taken from `main` at
any time; they are simply not a *comparison*.

---

## Failed tasks

| What | Why it failed | Decision |
| ---- | ------------- | -------- |
| none |               |          |

---

## Issues encountered

- **A formatter reflowed code mid-pass.** Five sites in `WindowLayout.swift` were re-wrapped
  (brace placement and line breaks — no statement changed) by something reformatting on write in this
  workspace. All five were reverted by hand, which is what lets AC5 come back at literally zero
  non-comment lines. **The next phase should expect the same** and check `git diff` for reflow before
  claiming a clean diff.
- **`docs/hotkeys.md` had no Hyper Key section at all.** The most load-bearing comments in the
  codebase — the Caps Lock → F18 HID remap and *why* it is unavoidable (the caps-lock toggle fires
  below every `CGEventTap`), toggle semantics versus `CGEventSource.keyState` racing the release, the
  left-side device bits, the `"TYCT"` self-marker, the watchdog — were documented **nowhere else**.
  Relocating rather than compressing them was the whole difference between a safe pass and losing
  hard-won platform knowledge.
- **AC2 and budget rule 4 contradict each other.** Rule 4 exempts `///` on a public type or method
  from the never-two-consecutive rule, but AC2's measurement command counts `///` runs too and demands
  `0`. AC2 was satisfied, so no stacked `///` survives anywhere and rule 4's exemption is currently
  unexercisable. Worth resolving in the budget text before the next agent reads it as permission.
- The over-cap gate is measured in **bytes**, not characters — `awk`'s `length` is byte-based in the C
  locale, and an em dash costs 3. Several first-pass rewrites landed at 101–104 and had to be trimmed
  again. Targeting bytes is the stricter and correct reading, since the greppable command *is* the rule.

---

## Deviations from the phase document

- **The budget did not land in its own commit, and the pass is not one commit per subsystem.** The
  phase makes both hard gates — a reviewer is supposed to read ~14 pure comment diffs. The operator
  chose "one uncommitted diff" up front, having been told what it costs. The mechanical
  proof (AC5 returning zero non-comment lines) is what stands in for per-subsystem readability.
- **Four subsystems the phase's suggested order omits were still swept**, because AC2/AC3 cover the
  whole tree: `DesignSystem/`, `Platform/`, and the `Settings` / `Backup` / `SystemActions` /
  `CustomCommands` / `Onboarding` features.
- **`regression.md` was not run** — the operator waived further testing after the build and harnesses
  came back green.
- One over-compression was **caught and reversed** during the pass: `LauncherList.rows`' slice-order
  note explains why filtering by kind preserves the flat selection index — an `AGENTS.md` invariant.
  It was cut to a bare formatting note, then restored as a one-line pointer once `docs/launcher.md`
  was confirmed to carry the full order.

### Where relocated knowledge went

| Source | Destination |
| ------ | ----------- |
| `HyperKeyTap.swift`, `HyperKey.swift`, `CapsLockRemap` — remap, device bits, toggle semantics, lifecycle | **`docs/hotkeys.md` § The Hyper Key** (new) |
| `ClipboardStore.swift` — the two-branch load query, FTS trigram minimum, `promote`'s transaction, owned vs. external images | **`docs/clipboard.md` § Store** (extended) |
| `EmojiGridView.swift` — per-row interaction and its ~100 MB cost, rows as scroll targets | **`docs/emoji.md` § Rendering** (new) |
| `CalcDateTime.swift` — the four grammars, bias, the letter-free-operand rule | **`docs/calculator.md` § Evaluation pipeline** (extended) |
| `WindowLayout.swift`, `WindowMover.swift`, `CurrencyRateStore.swift`, `QuicklinkStore.swift`, `RootPaletteView.swift`, `PalettePanel.swift` | already present in `docs/window-management.md`, `calculator.md`, `quicklinks.md`, `palette.md` — deleted and replaced by a pointer |

---

## Follow-up work

| Observation | Where | Suggested phase |
| ----------- | ----- | --------------- |
| Rule 4's `///` exemption is unexercisable while AC2 demands 0 stacked blocks. Reconcile the wording. | `AGENTS.md` § Comments | doc fix, no phase |
| Stale paths: `EmojiIndex.swift` / `FrequentEmojiStore.swift` listed under `Model/` (both moved to `Service/` in 29) and `EmojiGridView.swift` outside `UI/` | `docs/emoji.md` § Layout | doc fix, no phase |
| Something reformats Swift on write in this workspace, silently reflowing untouched code | workspace tooling | investigate before 35 |
| The seven phase-01 runtime baselines remain uncaptured; the roadmap closes without them | `docs/refactor/progress/01-*.md` | optional, post-roadmap |

---

## Rollback notes

- **Revert command:** `git revert <sha>`
- **Is a plain revert sufficient?** Yes. The Swift half is comment-only and compiles either way; the
  docs half is additive. Reverting restores the prose and re-inflates both metrics.
- **Dependent phases that must also be reverted:** none. **Phase 35 depends on 29, 30 and 34** — but
  on the *structure* those phases established, not on this comment pass, so a revert here does not
  block 35.
- **Data risk on revert:** none — nothing persisted changed, and no code path was touched.

---

## Sign-off

- [x] All acceptance criteria met (AC7 partial, and why is recorded above)
- [ ] All four checklists passed — **build + testing only; regression and review waived by the operator**
- [x] `ROADMAP.md` status table updated
- [x] Follow-ups recorded above, not fixed in this phase
- [ ] Merged to `main`
- [x] **Stopped.** Phase 35 is a separate session.
