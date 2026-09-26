---
name: ui-revamp
description: The process for a UI rework in ANTA that has to ship without regressions - a design record with the owner's decisions, a must-not-change list, slices with a gate after each one, a device pass, an independent review and a definition-of-done checklist. USE FOR - redesigning or restyling a page, sheet, panel or picker; replacing a widget the app already ships; any UI change that spans several surfaces or several hundred lines. Load together with anta-context, verify and the area skill (calendar-events + calendar-ui, or markdown-engine).
---

# UI rework process

The 2026-09-25 event editor redesign shipped clean because it ran this way — [docs/event-editor-redesign-roadmap.md](../../../docs/event-editor-redesign-roadmap.md) is the worked example. The two reworks that followed it skipped the record, and within a day they had re-derived sheet chrome the first one had just made shared. So: no rework without a record, and no slice without the gate.

## 0. Decide with the owner first

UX the owner flags as important is debated before code: argue the options, offer alternatives, then ask the open decisions as **lettered options** (A / B / C, the recommended one first). The owner answers tersely. A delegated decision ("take it from me") means the recommended option stands, and the record says it was delegated.

## 1. Write the design record

One file, `docs/<area>-<topic>-roadmap.md`. A design record is an explicitly requested doc. Sections, in this order:

1. **How to run this** — the hand-off prompt for the implementing session: which skills to load, the slices, the gate, "do not commit".
2. **Why** — the problem in the shipped UI, with evidence (what the owner saw, what the numbers say).
3. **Decisions** — a table `D1 … Dn`: the decision and its reason, owner-attributed and dated. A later amendment appends (`D9 supersedes D3`); nothing is rewritten.
4. **The spec** — geometry and tokens, row types, every screen top to bottom, copy and l10n keys. Numbers are named after the constant they will become.
5. **Behaviour** — *must not change* (every persisted field, callback contract and existing guard, listed) and *deliberately changes*.
6. **Facts from the tree** — `file:line` of every entry point the slices touch, re-grepped before editing. The old widgets to delete are named here.
7. **Slices** — §2 below.
8. **Definition of done** — the regression checklist (§4), as concrete as "a 120-character title wraps and its counter appears from 100".
9. **Deferred** — what was cut, so the next session does not re-argue it.

## 2. Slices

Each slice is one buildable, testable increment with its own tests. Never start the next one with anything red. The order that worked:

1. **Primitives and chrome** — the shared rows, the sheet handle / header / ground, the metrics constants. They live where later surfaces can use them (`lib/widgets/form_rows.dart`, `lib/constants/form_metrics.dart`), never as a copy inside one screen.
2. **Screens** — group by group, each with its sub-sheets. The old widgets may stay below the new ones until nothing references them.
3. **Delete the old UI** — the record names what goes; grep for the last reference before deleting.
4. **Device pass, review, docs** — not optional (§3).

## 3. The gate, after every slice

The `verify` skill's gate: `dart analyze lib` clean (plus `test` when tests changed); the **whole** `flutter test` green, one run at a time; `flutter gen-l10n` run and `untranslated.txt` empty when an ARB changed; the must-not-change list re-read against the diff.

For the last slice, additionally:

- **Device pass** through the `qa-emulator` skill: the area's saved flows first (`qa relaunch --fresh --seed tool/qa/fixtures/calendar.json && qa flows calendar` for the calendar — green before anything else is looked at, and every flow whose screen the slices changed updated in those slices), then the matrix with `qa set theme=dark locale=de text-scale=2.0`, every screen the record draws, both phone sizes (360 × 780 and 412 × 915), screenshots beside the boards, `qa errors` clean.
- **Independent review** by a fresh subagent that has not seen the session's reasoning (`fable-max` when the owner flags the rework as high-stakes): brief it with the record and the diff, ask for confirmed defects only, fix what it confirms, re-run the gate.
- **Docs in the same change**: the area's `docs/*.md` gets an addendum carrying the history and the why; `COPILOT_CONTEXT.md` gets its section updated; the area skill gets the **rule** in one or two lines. Narrative never goes into a skill — a skill is read on every task, a doc when it is needed.

## 4. Definition of done — the generic checklist

Adapt it to the surface; do not shorten it.

1. Create, edit and delete round-trip, and the data written is equal to what the old UI wrote for the same input (compare through the old writer's tests).
2. Every control is reachable one-handed on a 360-wide phone, with 48 dp targets — chips, swatches and weekday cells included.
3. Leaving a dirty form asks first — ✕, back, system back, the barrier and drag; a clean form leaves silently.
4. Light and dark; en, de and ro; text scale 1.3 and 2.0 with no clipped label and no overflow.
5. Keyboard up and down: the bottom-clearance rule holds, nothing shifts, nothing sits under the navigation bar.
6. Nothing moves under the finger: constant-height sub-sheets, captions that change text not geometry, disabled instead of hidden.
7. Every string goes through `AppLocalizations` in all three ARBs; `untranslated.txt` is empty.
8. Semantics: tooltips on icon buttons, one node per row, a `SemanticsIds` entry for anything a device script targets.
9. The widget suites of every surface touched still pass unchanged where behaviour did not change; new behaviour has new tests.

## 5. Report

What shipped; each deviation from the record and why; every review finding and how it was resolved; what could not be verified. Do not commit — the owner reviews and commits.
