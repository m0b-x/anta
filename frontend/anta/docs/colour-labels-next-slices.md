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
- **Label from the editor** (Slice 2, committed `0984341`): one shared
  `showLabelPickerSheet` behind both the bulk action and a new **Label** row
  in the editor's menu (between Move and Share, absent until the note has an
  id). The row reads the colour fresh from storage and dispatches only on a
  changed pick; a note deleted elsewhere now reads as "not found" there, as
  it does for Move and Share.
- **Sort by label** (Slice 3, done 2026-09-13, uncommitted): `labelAsc` on
  both sort enums — labelled first in palette order, unlabelled last, then
  newest first (notes) or by name (folders), always ending on `id`. A row in
  each sort sheet; both sheets now scroll so seven rows fit a 360×640 phone.
  No index: the plan matches the existing per-folder sorts.
- **Filter by label in search** (Slice 4, done 2026-09-13, uncommitted): a
  dot chip per colour in use after the scope chips (at the root too, only
  when something is labelled, present from the first frame), multi-select
  OR, filtering whatever pass is showing; with nothing typed the chips list
  "everything red" newest first through their own indexed query, headed by
  the colour names and the true count. A chip tapped mid-keystroke filters
  the text on screen; closing search drops the colours, coming back from a
  note keeps them.
- **Both follow-ups** (done 2026-09-13, uncommitted): light-mode yellow and
  orange darkened to clear 3:1, pinned by a contrast test; bulk label, move
  and delete no longer flash the browser or lose the scroll offset — the
  folder bloc reloads in place and both blocs coalesce a burst of change
  events into one reload.

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
deviations. Owed on the phone: open a note → ⋮ → Label, pick a colour, go
back, and check the row shows it with no list jump.

## Slice 3 — Sort by label (roadmap Slice B) — DONE 2026-09-13

Shipped as listed above; the roadmap's Slice B "Shipped" block has the query
plans and the reasons there is no index.

## Slice 4 — Filter by label in search (roadmap Slice A) — DONE 2026-09-13

Shipped as listed above; the roadmap's Slice A "Shipped" block records the
deviations (own DAO query for the listing, the pending-keystroke rule, the
open/refresh split, the primed root row, the ringed selected chip).

## Slice 5 — Named labels — DROPPED 2026-09-13

The owner decided the feature is complete without names. The roadmap keeps
the Slice D text as the record.

## Follow-ups from the 2026-09-12 review — DONE 2026-09-13

Both shipped with Slices 3 and 4 (see "Done so far"); the roadmap's §2
"Known and left" entries say exactly what changed.

## What is owed now

1. **Commit** Slices 3 + 4 and the two follow-ups (everything uncommitted on
   `0984341`; the full suite is green).
2. **Phone pass** (Android, light and dark):
   - sort sheet: seven rows, scrolls, Label row reachable one-handed;
     choosing it groups the coloured notes first in palette order;
   - search in a folder with colours in use: the chip row keeps its height
     with the keyboard up, scrolls past seven dots, a selected dot wears the
     purple ring; tap a dot with the field empty → the list is headed
     "Red · N notes" and shows path · date rows; type a letter → narrows;
     tap a chip while typing fast → the text is kept;
   - root: open search, the dot row is there on the very first frame (no
     jump under the field); close search, reopen: the colours are cleared;
     open a note from a result, label it from ⋮, come back: its chip is
     offered and the filter you had is still applied;
   - selection mode → Label / Move / Delete on a list scrolled past the first
     page: no spinner, no jump, the list stays where it was;
   - light mode: yellow and orange dots and stripes read on the row surface.
3. **Follow-ups worth their own change** (not label-specific): the four
   older folder sorts have no `id` tiebreak (the label sort is the only one
   that does); a `SheetDragHandle` widget for the five verbatim 40×4 handles;
   `optimized_folder_content_page_test.dart` is order-dependent (its last
   group seeds rows earlier counts assert on).

## Not planned

- A pin (sort to top) — separate decision.
- A root "Labels" smart row — Slice 4's empty query + chip is the same list.
- Multiple labels per item, custom hues, tinted rows or folder glyphs, a
  coloured title in the editor — rejected by the design decisions.
