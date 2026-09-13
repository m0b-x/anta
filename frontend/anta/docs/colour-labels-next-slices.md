# Colour Labels — What Is Left, Slice by Slice

Plain checklist for the sessions after 2026-09-12. The long version, with
file/line facts and paste-ready agent prompts, is `colour-labels-roadmap.md`;
this page only says what to build and in which order. Slices here are
numbered; the roadmap's lettered slices map as noted, and the *studies*
A/B/C/D on the design page are placements, not slices.

## Done so far

- **Labels themselves** (committed `4b525b9`): one colour per note or folder,
  seven fixed hues, `label` column on both tables (schema v39), assign from
  the row's long-press sheet or in bulk from selection mode, carried by
  backups, archives and sync merges.
- **Two rendering styles, chosen in Settings → Browsing → "Label style"**
  (committed `d6025a2`): *Dot* (Study A, default) draws a 10 dp circle at the row's
  trailing edge; *Edge stripe* (Study D) draws a 3 dp bar on the row's
  leading edge, inset 8 dp top and bottom, rounded on its right. One
  `ValueNotifier` (`LabelAppearance.style`) drives every labelled row, so a
  change repaints the browser under the settings page; the value is primed
  before the first frame, re-primed after a database switch and after a
  backup restore, and rides in backups.
- **Label from the editor** (Slice 2, done and reviewed 2026-09-13,
  uncommitted): one shared `showLabelPickerSheet` behind both the bulk
  action and a new **Label** row in the editor's menu (between Move and
  Share, absent until the note has an id). The row reads the colour fresh
  from storage and dispatches only on a changed pick; a note deleted
  elsewhere now reads as "not found" there, as it does for Move and Share.

## Slice 1 — Commit and see it on a phone

1. Commit the stripe style on its own (all the `label_style` / `LabelAppearance`
   / `ContentRowShell.edgeStripe` files, the two new tests, the doc edits).
2. Android device pass, both styles, light and dark:
   - long-press a note: the swatch strip fits the width with no overflow
     stripe; pick a colour; the dot or stripe appears with no list jump;
   - stripe style: the bar is clipped cleanly by the 14 dp corner on the
     first and last row of a group, sits above the selected tint, and never
     touches the text; yellow reads on both surfaces;
   - flip the setting with the browser open underneath: rows repaint on
     return, no flash to the dot;
   - selection mode → Label → the sheet clears the gesture bar; the pick
     applies to notes and folders together;
   - TalkBack reads "<Colour> label" on the dot and on the stripe;
   - kill and relaunch: labels and the chosen style persist; backup export →
     import into a fresh database: both survive.

## Slice 2 — Label from the editor (roadmap Slice C) — DONE 2026-09-13

Shipped as listed above; the roadmap's Slice C "Shipped" block records the
deviations. Owed: commit it, then on the phone open a note → ⋮ → Label, pick
a colour, go back, and check the row shows it with no list jump.

## Slice 3 — Sort by label (roadmap Slice B)

- Append `labelAsc` to both sort enums (labelled first in palette order,
  unlabelled last, then by date, still ending on `id`).
- One new row in each sort sheet, plus the case in the menu's sort label.
- Add a partial index **only** if the query plan shows a temp b-tree that the
  existing per-folder sorts avoid; then both creation paths, schema v40,
  parity and plan tests.
- Tests: ordering and page boundaries, sheet persists `labelAsc` to the
  folder, menu label reads "Label".

## Slice 4 — Filter by label in search (roadmap Slice A)

- `SearchState.labels` (multi-select, OR) and `labelsInUse` (one `SELECT
  DISTINCT`), event `SearchLabelsChanged`.
- The chips row becomes one fixed-height horizontal scroller: the two scope
  chips, a divider, then a dot chip per colour in use (shown at the root
  too, only when something is labelled).
- A selected label filters the current pass and makes the empty query list
  the labelled notes; clearing the last label with no query returns to
  recents. `quickSearch` lifts its empty-query early return only when a label
  filter is present.
- A results header naming the selected colours with a count.
- Tests: bloc transitions incl. the stale-pass guard, service filter, chip row
  height at 360 dp with seven colours, root visibility.

## Slice 5 — Named labels (roadmap Slice D, optional)

- One JSON settings key `label_names` (colour → name), in the backup
  allow-list.
- Fold names into the existing `LabelAppearanceService` / `LabelAppearance`
  facade (do not add a second service), so dot semantics, stripe semantics,
  swatch tooltips, Slice 3's sort row and Slice 4's chips pick names up with
  no further edits.
- A "Labels" settings page: seven rows, dot + text field, 24 characters,
  clearing restores the default name.
- Tests: service round-trip and reset, backup round-trip, tooltip/semantics
  read the name and revert.

## Follow-up worth its own slice (found in the 2026-09-12 review)

- **Bulk actions flash the browser list.** Leaving selection drops the
  page's optimistic list, and the folder bloc's refresh passes through a
  loading state, so bulk label, move and delete can show the spinner for a
  frame and lose the scroll offset; the same refresh snaps a paginated
  folder list back to page one. Fix: make the folder bloc reload in place
  the way the note bloc already does. Not label-specific, so not in the
  slices above.
- **Light-mode yellow and orange** are below the 3:1 graphics-contrast
  floor as a 3 dp stripe (dark mode is fine). Judge on the phone; darkening
  the two light-mode hex values in `AppColors` is a one-line change.

## Not planned

- A pin (sort to top) — separate decision.
- A root "Labels" smart row — Slice 4's empty query + chip is the same list.
- Multiple labels per item, custom hues, tinted rows or folder glyphs, a
  coloured title in the editor — rejected by the design decisions.
