---
name: ui-mock
description: How to produce a design mock for any ANTA screen, sheet, panel, row or component - exactly ONE mock by default, drawn on the app's own UI language and tokens, delivered as one HTML artifact page (360-wide phone frame, light and dark) or as an ASCII sketch when the question is structure. Load whenever the owner asks for a mock, a study, a canvas, a board, a design page, a visual proposal, "show me how it would look", or a redesign idea, even without the word "mock". Variants (A/B/C) only when the owner explicitly asks for several. Load together with ui-language; ui-revamp when the mock starts a rework.
---

# One mock, on the language

## Why one

The 2026-09 canvases ran to 29 boards for one sheet and cost more than the implementation they preceded, and the owner chose the recommended direction almost every time. One mock that follows the language is cheaper to draw, faster to judge and closer to what ships. The debate happens in words — lettered options, one line each, the recommended one first — not in parallel boards. The owner decided this on 2026-10-11: one mock unless they ask for more.

## Before drawing anything

1. **Settle the idiom** with `ui-language` ("Which idiom a surface takes"): grouped form rows, the browser's content rows, the settings kit, or a takeover page. The idiom fixes most of the layout; the mock only has to show the rest.
2. **Read the surface as it is** — the widget file, its tests, the rows it already uses — and the tokens it reads (`FormMetrics`, `RowMetrics`, `AppBarMetrics`, `SurfaceRoles`, `AppTheme`). The mock uses those numbers by their constant names, never invented ones.
3. **If the open question is structure** — which rows, in what order, what moves into a sub-sheet — answer it with an ASCII sketch in the reply first. It costs nothing and often ends the discussion without a page.

## The principles that decide a design when there is no mock to compare

These stand in for the variants that are no longer drawn. When two layouts are otherwise equal:

- Fewer taps to capture wins; the app is used mid-workout, one-handed, on a 360-wide phone.
- Reuse an existing row type before inventing one; one new primitive per rework at most, and it lands in `lib/widgets/form_rows.dart`, not inside one screen.
- Hierarchy comes from spacing and type, not boxes, lines or shadows beyond the sheet's own. One accent (`primary`), tonal surfaces, no gradients.
- Nothing moves under the finger: constant-height rows, captions that change text not geometry, disabled instead of hidden.
- Advanced controls go one level down (a sub-sheet or a menu), never into a longer form.
- Labels are two or three words; a sentence is a caption, and a caption is rare.
- Dark mode and text scale 2.0 are designed, not checked afterwards; 48 dp targets everywhere.
- Material 3 is the base; the app's language is the dialect; a trend that fits neither does not enter.

## The mock itself

- One HTML page, published as an artifact (the `artifact-design` skill applies); title `<Surface> mock`.
- One board: the surface at 360 × 780, light and dark side by side. A second row only for a state the surface must get right — keyboard up, empty, error, text scale 2.0.
- Colours are the hex values of `lib/constants/app_theme.dart` (both schemes), metrics the named constants, copy real English (de/ro are checked at implementation).
- Under the board, two short lists: **Decisions** — every open question as lettered options, the recommended one first with one line of why — and **Must not change** — the persisted fields, callbacks and guards the surface carries today.
- A component mock (a row, a chip, a badge) is an ASCII sketch or a ten-line HTML snippet in the reply, not a page.

## When variants are allowed

Only when the owner writes "show me two options" / "three directions" or names the alternatives. Then at most three, on the same page, each differing from the recommended one in a single axis, the recommendation marked. Never variants of a variant, never a second page.

## After the owner answers

The answers become `D`-numbered decisions in the design record (`ui-revamp` §1), with the mock's URL beside them. Do not redraw the mock per answer; redraw once when the record is written, if the answers changed the board at all.

## Cost rules

- The main thread or an `implementer` agent draws the mock; never `fable-max`, never a review agent on a mock — the owner is the reviewer.
- Draw after the idiom and the facts are settled, so the page is drawn once.
