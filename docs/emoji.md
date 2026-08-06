# Emoji picker

A palette sub-screen (reached like Clipboard / Calculator History) presenting a searchable emoji grid.

## Layout

- `Features/Emoji/Model/` — the **Foundation-only** catalog + geometry (no AppKit / SwiftUI imports):
  - `EmojiCatalog.swift` — the catalog model (groups, names, keywords).
  - `EmojiGridGeometry.swift` — pure grid-layout math (columns, item sizing).
  - `EmojiData.generated.swift` — the emoji dataset.
  - `EmojiIndex.swift` — search index over the catalog.
  - `FrequentEmojiStore.swift` — persisted most-recently / frequently used emoji.
- `Features/Emoji/EmojiGridView.swift` — the SwiftUI grid view.

## Rendering

Two structural decisions in `EmojiGridView` are load-bearing, and both are about the ~2,000 cells the
grid can realize.

**Interaction lives on the row, never the cell.** Tap, double-tap, right-click and hover are attached
once per `EmojiSectionGrid` row. A fast scroll realizes every cell, and per-cell interaction
machinery — notably the `NSView`-backed right-click catcher — costs roughly **100 MB** at that scale,
which lazy containers never release. Per-row keeps it bounded to the handful of visible rows, so the
cell view stays pure content: no gestures, no overlays, no hover tracking. Hover is resolved by
mapping the pointer's x to a column, which is exact because cells split the row width evenly with
zero spacing; the empty trailing slots of a partial last row resolve to nil.

**Rows sit directly under the outer `LazyVStack`.** A cell nested inside a `LazyVGrid` cannot be
scrolled to until it is realized, which broke keyboard scrolling on key-hold. Keeping rows as the
`ScrollViewReader`'s targets means any row can be reached even while off-screen. Row IDs are
section-namespaced, because a frequently-used emoji also appears inside its own category. Selecting
into the first row scrolls to the origin rather than the row, so the section header shows too.

## Invariants

- **`EmojiData.generated.swift` is emitted by `node Tools/gen-emoji.js`** (Node 18+ for global
  `fetch`) — **never edit it by hand**. Regenerate and commit instead.
- **`EmojiCatalog.swift` and `EmojiGridGeometry.swift` must stay AppKit/SwiftUI-free**, because the
  `Tools/emoji-test.swift` harness compiles the real sources:

  ```sh
  swiftc Tinycast/Features/Emoji/Model/EmojiCatalog.swift Tinycast/Features/Emoji/Model/EmojiGridGeometry.swift \
    Tinycast/Features/Emoji/Model/EmojiData.generated.swift Tools/emoji-test.swift -o /tmp/emoji-test && /tmp/emoji-test
  ```

- The grid list uses the palette scrollbar (`.thinScrollbar()` + `.hideNativeScrollers()`) and the
  shared `SectionHeader` for group labels — see [ui.md](ui.md).
