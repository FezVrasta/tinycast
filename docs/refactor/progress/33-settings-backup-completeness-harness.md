# Phase 33 — `SettingsBackup` completeness harness

---

## Status

| Field                         | Value                                            |
| ----------------------------- | ------------------------------------------------ |
| **Status**                    | Complete                                         |
| **Started**                   | 2026-08-07                                       |
| **Completed**                 | 2026-08-07                                       |
| **Operator**                  | abue-ammar                                       |
| **Branch**                    | `refactor/33-settings-backup-completeness-harness` |
| **Commit**                    | single commit on the branch                      |
| **Claude conversations used** | 1                                                |
| **Actual effort**             | ~40 min vs. estimate of M (2–4 h)                |

---

## Completed tasks

- [x] Objective 1 — `Tools/settings-backup-test.swift` asserts every `AppSettings` key is either
      carried by `SettingsBackup.SettingsData` or listed as a deliberate exclusion. 9 assertions
- [x] Objective 2 — the exclusion set exists with a reason per entry, and the harness rejects a reason
      that only echoes the key name
- [x] Objective 3 — registered in `docs/development.md`, `AGENTS.md`, `checklists/testing.md` **and**
      `.github/workflows/ci.yml`. See _Deviations_
- [x] The mirror stayed hand-written. No `Mirror`, no macro, no codegen, no "backup everything" default
- [x] Scratch-key proof performed in both directions, then reverted

## Acceptance criteria

- [x] AC1 — compiles standalone with `swiftc -swift-version 6`, Foundation only, against two real
      shipped sources (`AppSettingsKey.swift`, `SettingsBackupCoverage.swift`)
- [x] AC2 — verified by adding `case scratchProbe`: output was
      `FAIL  every AppSettings key is backed up or deliberately excluded — scratchProbe`, exit 1.
      Reverted and the file confirmed byte-identical
- [x] AC3 — met in **two** forms. `mirrored`'s values are typed `AppSettingsKey`, so a field naming a
      non-existent key is a *compile* error (`type 'AppSettingsKey' has no member 'noSuchKey'`) rather
      than a harness failure — strictly stronger. The string-keyed exclusion table is checked at
      runtime; a deliberate `"snippetsEnabledd"` typo produced 3 FAILs and exit 1
- [x] AC4 — `deliberatelyExcluded` holds `snippetsEnabled` with the phase document's verbatim reason
- [x] AC5 — **at source level.** `SettingsBackup.swift`'s entire diff is one comment line; `gather` and
      `apply` are untouched. All 25 key names *and* raw values were diffed against `HEAD` and are
      identical — the only entry not carried over is `showInMenuBar`, which belongs to `SettingsKey`
      (untouched) and never lived in the extracted enum. The **runtime** export comparison was not run;
      see _Verification_
- [x] AC6 — registered in all three named places, plus `ci.yml`
- [x] AC7 — all harnesses pass, but the count is **18, not 19** — see _Deviations_

---

## Verification

| Checklist                  | Result  | Notes                                                                                                                                                                                              |
| -------------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `checklists/build.md`      | PASS    | Debug, `CODE_SIGNING_ALLOWED=NO`. Warning baseline measured **on-branch before any edit**: 0 → 0. `xcodegen generate` idempotent (+8 pbxproj lines, the two new sources only, unchanged on re-run) |
| `checklists/testing.md`    | PASS    | All **18** harnesses, run from a freshly extracted `docs/development.md` fence under `set -euo pipefail`, exit 0. `palette-selection-test` 111,684 unchanged                                       |
| `checklists/regression.md` | NOT RUN | **Operator waived further testing.** Cost is bounded here — see below                                                                                                                              |
| `checklists/review.md`     | NOT RUN | Waived with the above                                                                                                                                                                              |

The regression waiver costs less on this phase than on most. The phase is additive: a harness, an enum
extraction proven token-identical, and one comment. What it leaves unobserved is the phase's own manual
list — export before/after byte-identity, the import round-trip and summary counts, and the
enable-snippets → export → disable → import → **stays off** check. Each is argued from source rather
than observed: `SettingsData` has no `snippetsEnabled` field (unchanged in this diff), and the harness
now asserts that it cannot gain one silently.

### Measurements

| Metric                  | Before | After | Δ         |
| ----------------------- | ------ | ----- | --------- |
| `Tools/` harnesses      | 17     | 18    | +1        |
| Harnesses run by CI     | 15     | 16    | +1        |
| `AppSettings.swift`     | 257    | 245   | −12       |
| Comment lines added     | —      | 10    | 0 stacked |

`AppSettings.swift` is 12 lines shorter because the 26-line `Key` enum left and a `typealias` plus some
re-wrapping came back. Its logic was proven unchanged mechanically: undoing the `Key.x` →
`Key.x.rawValue` rename and stripping whitespace makes the two revisions **identical**.

---

## Failed tasks

| What                                            | Why it failed                                                                                                                             | Decision                                              |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| Put the coverage tables in `SettingsBackup.swift` | That file cannot compile standalone — its `@MainActor` extension needs 13 symbols including `AppCore`                                     | Re-planned into a Foundation-only sibling file        |
| `AppSettingsKey.x.rawValue` at every call site   | Pushed 28 lines of `AppSettings.swift` past 100 columns, turning a mechanical rename into a re-wrapping diff                              | Re-planned as `private typealias Key = AppSettingsKey` |
| Tie the tables to `SettingsData` via `CodingKeys` | Would close the last symmetry gap, but makes a *forgotten* case silently drop a field from the export — a data-loss hazard for a doc gap | Dropped, recorded as a known residual gap             |

---

## Issues encountered

- **The phase document's central assumption is false.** It offers "compile `SettingsBackup.swift` and
  compare the two static lists" as the preferred approach. `SettingsBackup.swift` needs `AppCore`,
  `HotKeyAction`, `KeyShortcut` and ten more symbols; stubbing them faithfully would be ~200 lines that
  must track `AppCore`'s API forever — exactly the fragility the harness exists to remove. Probed with
  `swiftc -typecheck` before designing around it rather than after.
- **`SettingsKeys` was not a usable name.** `SettingsKey` already exists *and is referenced inside
  `gather`/`apply`*, which the phase forbids touching, so it could not be renamed out of the way.
  `SettingsKey` / `SettingsKeys` in different files is precisely the trap this phase fights.
- **`CaseIterable` rather than 25 `static let`s.** The phase says "25 string constants", which implies a
  hand-written `all` array — and a key added but omitted from `all` would pass the harness vacuously.
  Every raw value is still spelled out, so renaming a case cannot rename a persisted key.
- The harness's failure output names the offending key inline (`— scratchProbe`) rather than only the
  rule, because a completeness harness that says "something is missing" costs the next reader a bisect.

---

## Deviations from the phase document

- **Coverage tables live in `Features/Backup/Model/SettingsBackupCoverage.swift`**, not in
  `SettingsBackup.swift` as the Expected-files table says. Forced — see _Issues_. `SettingsBackup.swift`
  gains a one-line pointer so an editor of `SettingsData` finds the table.
- **`AppSettingsKey`, not `SettingsKeys`** — name collision with the untouchable `SettingsKey`.
- **`.github/workflows/ci.yml` is a fourth registration site**, which the phase does not name. Phases 27
  and 29 both established that a harness missing from CI is a silent hole.
- **"All 19 harnesses" is off by one.** There were **17**; this phase makes **18**. `testing.md`'s
  existing "17 (18 from phase 19 onward)" carried the same error. The count line was rewritten to the
  true number rather than propagating it.
- `externallySourced` was added beyond the spec: `launchAtLogin` and `showInMenuBar` are `SettingsData`
  fields with no `AppSettings` key behind them, and without naming them the table reads as incomplete.
  The harness asserts they really have no key, so the claim cannot go stale.

---

## Follow-up work

| Observation                                                                                              | Where                          | Suggested phase |
| -------------------------------------------------------------------------------------------------------- | ------------------------------ | --------------- |
| CI never ran `volume-test` or `palette-selection-test` — 15 of 17 before this phase, 16 of 18 after      | `.github/workflows/ci.yml`     | standalone      |
| The harness never sees `SettingsData` itself, so a second field for an already-covered key would slip by | `SettingsBackupCoverage.swift` | —               |
| 2 stacked comment blocks and 10 comment lines over 100 chars, all pre-existing                           | `AppSettings.swift`            | 34              |
| 1 stacked block and 7 over-100 comment lines, all pre-existing                                           | `SettingsBackup.swift`         | 34              |

---

## Rollback notes

- **Revert command:** `git revert <sha>`
- **Is a plain revert sufficient?** Yes. Additive — one harness, one enum extraction, one static table.
- **Dependent phases that must also be reverted:** none. Phase 34 depends on 33 but only for sequencing.
- **Data risk on revert:** none. No persisted key string changed, so a settings file written before,
  during or after this phase reads identically.

---

## Sign-off

- [x] All acceptance criteria met
- [ ] All four checklists passed — **build and testing only; regression and review waived by the operator**
- [x] `ROADMAP.md` status table updated
- [x] Follow-ups recorded above, not fixed in this phase
- [ ] Merged to `main`
- [x] **Stopped.** Next phase is a separate session.
