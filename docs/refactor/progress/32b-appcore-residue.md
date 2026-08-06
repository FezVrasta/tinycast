# Phase 32b — Close the `AppCore` residue

---

## Status

| Field                         | Value                                     |
| ----------------------------- | ----------------------------------------- |
| **Status**                    | Complete                                  |
| **Started**                   | 2026-08-07                                |
| **Completed**                 | 2026-08-07                                |
| **Operator**                  | abue-ammar                                |
| **Branch**                    | `refactor/32b-appcore-residue`            |
| **Commit**                    | single commit on the branch               |
| **Claude conversations used** | 1                                         |
| **Actual effort**             | ~35 min vs. estimate of M (2–4 h)         |

---

## Completed tasks

- [x] Objective 1 — `QuicklinkCoordinator` takes `paletteCoordinator` like its six siblings; the
      `showPalette` / `hidePalette` forwarders are gone. **Exceeded:** `handleReopen` and `showSettings`
      went with them, so `AppCore` now carries no palette forwarder at all. See _Deviations_
- [x] Objective 2 — `WindowCommandCoordinator` extracted, the eleventh coordinator; `runWindowCommand`
      deleted from `AppCore`. The body moved verbatim apart from the forced
      `hidePalette` → `paletteCoordinator.hidePalette` requalification
- [x] Objective 3 — `gather(from:)` / `apply(to:)` take a required `core`; `BackupActions` takes `core`
      on its three entry points and both private helpers. No `= .shared` default was added anywhere
- [x] All 17 harnesses run and passing, twice — once after the three objectives, once after the extra
      forwarder removal
- [x] Dead-code sweep: every remaining `AppCore` member re-checked for live call sites; none orphaned

## Acceptance criteria

- [x] AC1 — `grep -rn "AppCore.shared" Tinycast` returns exactly six: `AppDelegate` (3),
      `TinycastApp` (3). No other file appears
- [x] AC2 — `AppCore` implements no feature action. Remaining surface is stored properties, coordinator
      wiring, `init`, `start()`, `hotKeyDisplayName`, `prepareForTermination()`, the feature-switch
      tracking and the five-method dialog façade. **Stronger than written:** `handleReopen()` and
      `showSettings()` are also gone
- [x] AC3 — `grep -rn "core\.showPalette\|core\.hidePalette" Tinycast` returns nothing
- [x] AC4 — coordinator count is **11**. Every coordinator needing palette control is handed
      `paletteCoordinator` at construction; the graph stays acyclic and `PaletteCoordinator` gained
      nothing
- [x] AC5 — `grep -c "func runWindowCommand" Tinycast` is 1, and `guard settings.windowManagementEnabled`
      is the first statement inside it
- [x] AC6 — neither `gather` nor `apply` has a default argument; `BackupActions` contains no
      `AppCore.shared`
- [ ] AC7 — `AppCore.swift` under 280 lines — **NOT MET. 290** (from 319, −29). The target was
      mis-derived: the document predicts −45 from three methods totalling ~28 lines. Even with the
      fourth forwarder removed it cannot reach 280 without deleting something the phase does not name.
      Nothing is orphaned — see _Measurements_
- [x] AC8 — zero behaviour change

---

## Verification

| Checklist                  | Result  | Notes                                                                                                                                                                                                                            |
| -------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `checklists/build.md`      | PARTIAL | **Debug only**, `CODE_SIGNING_ALLOWED=NO`, `BUILD SUCCEEDED`, zero compiler warnings. No pre-phase baseline was taken (operator declined), so "zero **new** warnings" rests on the absolute count being zero. Release not built     |
| `checklists/testing.md`    | PASS    | **All 17 harnesses**, per-harness exit codes checked individually, 17 passed / 0 failed. Named gates `window-command-test` and `quicklink-test` both pass                                                                          |
| `checklists/regression.md` | NOT RUN | **Waived by the operator**, who declined further testing. The manual pass below is therefore unexercised                                                                                                                          |
| `checklists/review.md`     | PARTIAL | 12 modified + 1 new file, +72/−81 excluding the new file. `git diff --name-only` audited against both phase lists: `PaletteCoordinator`, `WindowMover`, the three pure `WindowManagement` models, `Raycast*` and the two off-limits scrolling files are all absent. `TinycastApp` and `AppDelegate` **are** present — see _Deviations_. Comment delta +1 |

### Manual verification — NOT PERFORMED

Every item below is from the phase's own checklist and its Definition of Done. All were waived:

- [ ] Every window command from the launcher **and** from its global hotkey
- [ ] Window management **off**, fire a still-registered window-command hotkey → nothing moves
- [ ] Quicklink with an argument; quicklink edit from the palette
- [ ] Settings export → import round-trip
- [ ] Raycast import from **both** the Backup pane and Onboarding
- [ ] Menu-bar items (Open / Clipboard History / Settings) and dock-icon reopen — **new to this phase**,
      since all four of those call sites were requalified

### Measurements

| Fact                                        | Before | After   | Note                                                    |
| ------------------------------------------- | ------ | ------- | ------------------------------------------------------- |
| `AppCore.swift` lines                       | 319    | **290** | −29; AC7 wanted < 280                                   |
| Forwarding methods on `AppCore`             | 4      | **0**   | all four palette forwarders deleted                     |
| Feature actions implemented on `AppCore`    | 1      | **0**   | `runWindowCommand` extracted                            |
| `AppCore.shared` reaches, tree-wide         | 12     | **6**   | AC1 met exactly                                         |
| Coordinators                                | 10     | **11**  | `WindowCommandCoordinator`                              |
| `= .shared` default arguments               | 2      | **0**   | none relocated to `BackupActions`                       |
| Harnesses passing                           | 17/17  | 17/17   | unchanged                                               |

---

## Failed tasks

- **AC7 only**, and it is arithmetic in the phase document rather than work left undone. The line target
  was derived from a −45 estimate against methods totalling ~28 lines.

---

## Issues encountered

- **The phase document contradicts itself on `showPalette`.** Objective 1 and AC2 delete it;
  `TinycastApp.swift` calls it twice and is on the must-NOT-change list. Implementation stopped and the
  operator decided. See _Deviations_.

- **`OnboardingModel` has no environment.** It is a plain `@Observable` class owned by `OnboardingView`,
  so injecting `core` into `BackupActions.importRaycast` meant threading it through
  `OnboardingModel.run()`, which became `run(core:)`. Both call sites are inside the view, which already
  holds `@Environment(AppCore.self)`. This file is on the phase's expected list; the signature change is
  not, but it is the minimum needed to remove the singleton reach the phase does name.

---

## Deviations from the phase document

- **`TinycastApp.swift` and `AppDelegate.swift` were edited, and both are on the must-NOT-change list.**
  This is the one deviation a reviewer must sign off deliberately. The document simultaneously requires
  deleting `showPalette` and forbids touching its only caller. Three options were put to the operator —
  keep the forwarder, delete all the palette forwarders and requalify the four call sites, or amend the
  document — and **option 2 was chosen explicitly.** The four edited call sites now read
  `AppCore.shared.paletteCoordinator.<verb>(…)`.

  The boundary's stated rationale is untouched. Phase 32 protects these two files because "the
  `MenuBarExtra` buttons legitimately reach the singleton; there is no environment in a `Scene`'s menu
  content" — a rule about *how* they reach `AppCore`, not which method they call. Both files still reach
  `AppCore.shared`, the count is still six, and neither gained an `@Environment`.

  The deciding argument was consistency: 41 call sites tree-wide address `paletteCoordinator` directly
  against 5 that went through a forwarder, and deleting only `showPalette` would have left `TinycastApp`
  using two idioms in four adjacent lines. `paletteCoordinator` is already an internal
  `private(set) lazy var`, so the forwarders added no encapsulation — unlike the dialog façade, which
  forwards to a **private** `dialogs` and is therefore retained.

- **`QuicklinkCoordinator.editQuicklink` now calls `paletteCoordinator.showSettings`,** the last
  straggler once the forwarder went. It keeps `core` for the dialog façade and `pendingQuicklinkEdit`,
  exactly as the phase requires.

- **Two documentation files were corrected, with operator approval**, neither on the expected list:
  `docs/window-management.md` (two references to `AppCore.runWindowCommand`, now
  `WindowCommandCoordinator`) and `AGENTS.md` (the `Coordinator` row, 10 → 11).

---

## Follow-up work

| Observation                                                                                                                                                            | Where                                                | Suggested phase                 |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- | ------------------------------- |
| **The manual pass was waived.** Window commands both ways, the feature-off hotkey test, both Raycast paths, and the four newly-requalified menu-bar / reopen call sites   | —                                                    | before release                  |
| `AGENTS.md`'s Architecture bullet and `docs/architecture.md:20-21` still say palette / paste / launch actions are methods on `AppCore` that views call. False since 32   | `AGENTS.md`, `docs/architecture.md`                  | **34** (measurement pass)       |
| `Tools/window-command-test.swift`'s header comment cites pre-phase-29 `Tinycast/Core/WindowManagement/` paths. Harmless — `docs/development.md` carries the correct ones | `Tools/window-command-test.swift`                    | **34**                          |
| `pendingQuicklinkEdit` is still observable state homeless on `AppCore`. Deliberately untouched this phase; wants a `State`-suffixed owner                                | `App/AppCore.swift`                                  | undecided — needs a design call |
| AC7's line target is unreachable as written; the document's −45 estimate does not match the methods it names                                                             | `docs/refactor/phases/32b-…md`                       | historical record, leave stale  |
| `checklists/regression.md:146` still lists phase 30 in its _Clean install_ set — carried from 30, 31 and 32, still open                                                  | `docs/refactor/checklists/regression.md`             | fix alongside the next phase    |

---

## Rollback notes

- **Revert command:** `git revert <sha>`, then `xcodegen generate`
- **Is a plain revert sufficient?** Yes, with the regenerate. Unlike phase 32 this commit **adds a
  file**, so `project.pbxproj` is in the diff and the project must be regenerated after reverting.
- **Storage impact:** none. No `UserDefaults` key, SQLite column, persisted path, exported format or
  raw value is touched. `SettingsBackup`'s **wire format is unchanged** — only the Swift signatures of
  `gather` / `apply` moved, so an export written before this commit imports after it.
- **Dependent phases that must also be reverted:** none.

---

## Blockers for the next phase

**None.** Phase 33 (`SettingsBackup` completeness harness) depends on 16 and is explicitly required to
run *after* this phase, because 33 freezes `gather` / `apply` and writes a harness against them. Both
now have their final shape — `gather(from core: AppCore)` and `apply(to core: AppCore)`, no default
arguments — so 33 can be written against them directly.

---

## Sign-off

- [x] Objectives 1–3 all met, objective 1 exceeded
- [x] Seven of eight acceptance criteria met; **AC7 (line count) not met at 290**
- [ ] All four checklists passed — **two.** `testing.md` PASS (all 17); `build.md` Debug only, no
      baseline; `regression.md` waived; `review.md` limited to the diff and the two boundary audits
- [x] All 17 harnesses run and passing
- [x] `git diff --name-only` audited against both phase lists
- [ ] Manual verification checklist — **not done**, waived by the operator
- [x] The must-NOT-change deviation was raised before implementing and decided explicitly
- [x] `ROADMAP.md` status table updated
- [x] Follow-ups recorded above, not fixed in this phase
