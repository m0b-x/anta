# Day Rail Markers — Implementation Roadmap

**Status: implemented (2026-08-30). Phases 1–5 all shipped; this file is now
the design record.** Running behaviour is the **v34 addendum** in
`docs/calendar-events-feature.md` and the v34 calendar bullet in
`COPILOT_CONTEXT.md` — read those first; this file carries the *why*.
Verified at ship time: `dart analyze lib` clean, `flutter gen-l10n` clean with
`untranslated.txt` empty, full `flutter test` green.

Every decision below was final at planning time; the "if you disagree"
scaffolding of the review draft is gone. Each phase is written as a
self-contained brief for an implementing agent (assignments in the phase
headers). All file/line claims were verified against the working tree on
2026-08-30; corrections from that verification are folded in and marked
*(verified)* where the draft had them wrong.

**Deviations from the plan as written** (both in phase 3, both geometric):

1. **The rail lane sits at x = 5, not 4.** D4 read the tint edge stripe as
   ending at x = 3, but that `Positioned(left: 0, width: 3)` lives *inside*
   the tinted container's `margin: EdgeInsets.all(1.5)`, so it really ends at
   4.5 and `left: 4` would have clipped it. `CalendarDayCell.railLeft` is the
   named constant, and a widget test pins both the offset and the clearance.
2. **Lane width is style-dependent** (`CalendarDayRail.railWidth`: 3 for
   `line`, 5 for `dot`), not a flat 3. A `Positioned` hands down tight
   constraints, so D5's 5px circle and D6's 1px hollow missed outline cannot
   both fit in a 3px lane. Only the **right** edge differs; the left edge is
   fixed regardless of style or of the stripe's presence, which is the thing
   D4's stability argument actually protects.

**Correction (2026-08-31): D4's gutter budget was wrong, and so was the
"nothing collides" claim this deviation originally carried.** The measured
grid cell is 51.43 x 62 at 360dp and 45.71 x 62 at 320dp. The 34px chip is
`Align(topCenter)`-centred, so its box starts at 8.71 (360dp) / 5.86 (320dp),
and the chip is a *circle* whose leftmost point sits exactly on that box edge
at y = 21 -- squarely inside the band the rail occupies. Two things D4 missed:

- The budget assumed the tint stripe ends at x = 3, leaving 3+1+3 in 7px. The
  stripe actually ends at 4.5, so the real gutter is 4.5 -> 8.71 = **4.2px**
  at 360dp. A 3px `line` lane at x = 5 fits with 0.71px to spare; the 5px
  `dot` lane reaches x = 10 and overlaps the filled today/selected chip by
  ~1.3px.
- At 320dp the gutter is 4.5 -> 5.86 = **1.4px**, so *both* styles overlap.

Accepted rather than fixed: every lever that removes the overlap (shrinking
the dot, moving the lane, insetting or shrinking the day-number chip) either
costs the hollow-missed affordance its room or moves the day number the whole
grid aligns to. The overlap is confined to the one or two cells per screen
that draw a filled chip. `calendar_day_rail_test.dart` pins the real numbers
at both widths so the wrong arithmetic cannot be re-derived from this file.

Superseded text, kept so the mistake is legible: "Cost: in `dot` style the lane's
   bounding box reaches x = 10 against a 34px chip whose box starts at ~8.5 in
   a ~51px cell — the chip is a circle, so nothing collides in the vertical
   band the rail occupies, but it is the one place the 7px gutter budget is
   exceeded."

**The other collision D4 never considered: the bottom marker strip.** The
strip is built in table_calendar's `markerBuilder` — a *sibling* subtree
painted after the cell — and insets only `CalendarDayBars.defaultHorizontalInset`
(6) from the cell edge, which is **inside** the rail's lane (5 → 8 for `line`,
5 → 10 for `dot`). It therefore painted over 2 of the line lane's 3px, and 4 of
the dot lane's 5px, along the whole bottom segment. Fixed by giving
`CalendarDayCell` a `railBottomInset` that the grid and the settings preview
fill with `4 + CalendarDayBars.stripHeight(...)`, so the rail stops above the
strip instead of under it. Rail height goes 54 → ~38, which still fits the
5-dot maximum (37px). A widget test pins both the clearance and the fact that
the lane really does overlap the strip's horizontal span.

**Two more corrections from the same 2026-08-31 review:**

3. The `line` overflow affordance shipped laying out at **0px wide** — a
   childless `DecoratedBox` under `Center`'s loose constraints takes
   `constraints.smallest`, and the inner `SizedBox` set only `height`. So
   `line` style silently dropped its "there are more" signal entirely. The
   37-test rail suite missed it because every assertion read
   `BoxDecoration`, never a laid-out `RenderBox`.
4. D7's "`max - 1` marks plus a neutral one" is now suppressed when only
   **one** slot fits. The marker strip's `+N` chip can stand alone because it
   draws a number; the rail's affordance cannot, so at one slot it replaced
   the day's top commitment with strictly less information. One slot now
   draws the top mark and the count rides the semantics label.
5. **D6's "faded *and* hollow" for a missed dot is now hollow *instead of*
   faded.** The two cues multiply: a 1px ring already carries roughly a fifth
   of a filled 5px disc's ink, and on an adjacent-month day
   `outsideAlpha × missedEventAlpha` = 0.35 × 0.35 = **0.12** alpha on that
   hairline — the missed commitment did not read as dimmed, it disappeared,
   while the kept mark beside it stayed legible. One strong cue per style:
   `dot` gets the shape, `line` (which has no shape to spare) keeps the alpha
   fade. Missed state is on the semantics label either way, so colour was
   never the only carrier.

**Known and accepted, not defects:** the rail wraps its marks in a
`LayoutBuilder`, so with the rail on every visible cell defers one subtree
build to layout — capacity depends on a height the three call sites compute
differently, and adapting is worth that for an opt-in channel; if the rail ever
becomes a default, thread the height down from `_rowHeight`. `DayRailResolver.
resolve` is a third verbatim copy of the dedup-plus-stable-sort in
`DayBarsResolver`/`DaySummaryResolver` (reuse obligation 4 asked for the copy);
a tie-break fix now has to land in three places. And the editor's Auto/Always/
Never control is shown for every recurring event even though the rail is off by
default, so the choice usually cannot take effect — gating it would mean
reading calendar appearance from the editor sheet, a dependency it does not
have today.

Also worth knowing: the editor's "Always" segment shares its English string
with the retroactive-scope chip (`recurrenceScopeAlways`) a section above, so
tests must scope their finders to the rail's own `SegmentedButton`.

Related running behaviour: `docs/presence-tracking-roadmap.md` (v26 presence),
`docs/calendar-events-feature.md`, the calendar bullets in
`COPILOT_CONTEXT.md`.

---

## The problem

`CalendarAppearance.eventTint` is implemented by `EventCellTintProvider` in
`lib/services/cell_tint_resolver.dart`. It picks **exactly one** event per day
(the top by `EventAgenda.compareWithinDay`) and washes the cell with that
event's colour at `CalendarColors.eventTintAlphaByPriority[priority]`. That is
deliberate and stays: averaging a day's colours "yields a hue that belongs to
no event on it".

The gap: a day with one presence-tracked event reads perfectly; a day with
three reads as one. Recurring commitments (gym, physio, language class) are
precisely the events that stack on the same day and whose *presence* the user
wants to scan across a month.

The fix is a second channel that is multi-source by construction: a **vertical
rail on the left edge of the day cell**, next to the fasting tab that already
lives there.

## What already occupies the left edge (verified)

- `DayCellTint` (`lib/models/day_cell_tint.dart`) models at most one wash plus
  at most one edge stripe.
- The edge stripe is `Positioned(left: 0, top: 4, bottom: 4, width: 3)` at
  `lib/widgets/calendar_day_cell.dart:196-207`, inside a `Stack` that starts at
  line 193. It is already claimed: `CellTintResolver` hands it to the tint
  runner-up when `CalendarTintConflict.both` is set. The "fasting vertical tab"
  is that stripe.
- `showWeekNumbers` renders as a sibling gutter **left of the whole `Table`**
  inside table_calendar (`Row([weekNumbers, Expanded(Table)])`) — no per-cell
  collision is possible.
- The tinted `Container` (and its `Stack`) is built **only** when
  `wash != null || edge != null`; otherwise `CalendarDayCell.build` returns a
  bare `Align` (lines 174-177, guard at 182). The rail needs its own wrapper
  `Stack`, applied outside that logic.

---

## Decisions (final)

### D1 — General provider chain, not a presence-specific widget

A `DayRailProvider` chain mirroring `DayBarProvider` and `CellTintProvider`,
with the same documented purity contract ("called for every visible cell on
every rebuild; no I/O, no BLoC access, no allocation beyond need" — copy the
wording from `lib/services/day_bars_resolver.dart:16-20`). Ship exactly one
provider, `EventDayRailProvider`. Do **not** pre-build a fasting rail provider.

### D2 — Membership: nullable per-event `showInDayRail`, NULL = auto

```
inRail(event) = event.rule is! OneTimeRecurrence
             && (event.showInDayRail ?? event.tracksPresence)
```

- `NULL` (default) — auto: presence-tracked recurring events are in, nothing
  else. No existing event changes behaviour; no backfill.
- `true` — force in (recurring events only; the recurrence guard is part of
  the predicate, so a one-time event can never enter the rail).
- `false` — force out.

Note `EventPresence.appliesTo(e)` is literally
`e.tracksPresence && e.rule is! OneTimeRecurrence`
(`lib/constants/event_presence.dart:52-53`), so the predicate above equals
`showInDayRail == null ? appliesTo(e) : (showInDayRail && e.rule is! OneTimeRecurrence)`.

Schema: **v34**, `ALTER TABLE calendar_events ADD COLUMN show_in_day_rail
INTEGER;` — nullable, no default. **This is the schema's first nullable bool**
*(verified: no `boolean().nullable()` exists anywhere in
`lib/database/tables/`)* — that is acceptable and intended; tri-state is the
feature. Declaration: `BoolColumn get showInDayRail => boolean().nullable()();`
following `colorValue`'s nullable pattern
(`IntColumn get colorValue => integer().nullable()();`, documented "NULL = use
the category color" in the same table).

**Scope cut: event templates do NOT get the column.** Template-created events
default to NULL = auto, which is correct. This also avoids churning the exact
key-set assertion in `test/database/schema_parity_test.dart:231-257` (the
template DDL test asserts exact equality; the `calendar_events` test at
371-430 uses `containsAll` and tolerates additions).

### D3 — The rail is a separate concept; `DayCellTint` is untouched

The tint edge means "a second tint source applies here and lost the wash"; a
rail mark means "this commitment is on this day, and here is whether you kept
it". Merging them destroys the attribution `CalendarTintConflict` protects.

New files:

- `lib/models/day_rail_mark.dart` — `DayRailMark { key, color, priority,
  missed, semanticLabel }` = `DayBar` (`lib/models/day_bar.dart`) plus one
  `bool missed` field, same names, all in `props`.
- `lib/services/day_rail_resolver.dart` — membership predicate, provider
  interface, `EventDayRailProvider`, `DayRailResolver`.
- `lib/widgets/calendar_day_rail.dart` — the painter.

`CellTintResolver`, `DayCellTint` and the fasting tab are untouched.
`test/services/cell_tint_resolver_test.dart` must still pass without edits.

### D4 — Geometry: 7px left gutter, two fixed lanes

- Lane 0, `left: 0, width: 3` — the tint edge stripe. **Unchanged.**
- Lane 1, `left: 4, width: 3` — the rail. `top: 4, bottom: 4`, matching the
  stripe (~44px usable at the 52px minimum row height).

Both lanes sit at fixed x whether or not the other is present — a rail that
slid left when fasting is absent would shift under the user across months, and
CLAUDE.md names stable layouts a hard requirement. Budget: the day-number chip
is 34px (`CalendarDayCell.chipSize`), `Align(topCenter)`-centred; at the
narrowest plausible cell (~48px) each side has exactly 7px clear. 3+1+3 fits.

**Structural note (verified, do not skip):** the rail cannot join the tint
`Stack` (it only exists when tinted). `CalendarDayCell.build` gets a new
*outer* wrapper: when `railMarks.isNotEmpty`, wrap the current result in
`Stack([current, Positioned(left: 4, top: 4, bottom: 4, width: 3,
child: CalendarDayRail(...))])`; when empty, return the current result
untouched, so the untinted no-rail cell stays the single bare `Align` it is
today.

### D5 — Styles: `DayRailStyle { none, line, dot }`, default `none`

- `line` — `n` stacked vertical segments, each
  `(railHeight - (n-1)*gap) / n` tall, 3px wide, 1.5px radius, 2px gap.
- `dot` — stacked 5px circles, 3px gap, vertically centred. The only style
  where `missed` renders as hollow (D6).
- `none` — rail off; the grid is byte-for-byte today's.

The enum lives in `lib/models/calendar_appearance.dart` with the same
`fromName` fallback every enum there uses. Default `none` is final — every
comparable option (`eventTint`, `highlightWeekends`, `showWeekNumbers`) is
opt-in. **No first-run nudge, no conditional default** (open question 3 of the
draft: resolved as "no departure from convention"). The settings description
must say plainly this is the answer to "several tracked events on one day".

### D6 — Marks encode missed/kept, honouring `CalendarMissedDisplay`

- `faded` — mark drawn at `CalendarColors.missedEventAlpha` (0.35); in `dot`
  style additionally hollow (1px outline, transparent fill).
- `hidden` — the mark is not emitted, **at the top of the provider's per-event
  loop, before any add** — the same order `EventDayBarProvider.barsFor`
  implements (`day_bars_resolver.dart:129-148`), so a hidden miss never
  consumes a rail slot.

Missed state also goes into the semantic label (D11) — a new ARB key with a
`{title}` placeholder, because *(verified)* no existing key covers "X, missed"
composition (`eventPresenceMissed` = "Missed" is a bare word used by the
editor/day-panel, and bar semantics today don't encode missed at all).

Cost: two static map probes per event (`EventPresence.appliesTo`,
`EventPresence.isMissed` — both verified to be probe-only, no allocation).

### D7 — Cap: `maxDayRailMarks` setting, default 3, range 1–5, neutral overflow mark

- Own setting, not shared with `maxDayBars` (different geometry, capacity,
  content). Note the existing `maxDayBars` slider runs 1–6; the rail slider
  runs 1–5 — capacity is real: at 44px, `dot` fits 5 (5px + 3px gap).
- The resolver does **not** cap; the widget caps (same division of labour as
  `DayBarsResolver`, documented at `day_bars_resolver.dart:211-214`).
  `CalendarDayRail` additionally clamps the visible count against its measured
  height at paint time so a short row never overflows.
- Overflow: when `marks.length > maxDayRailMarks`, render
  `maxDayRailMarks - 1` marks plus a neutral `onSurfaceVariant` last mark — a
  half-height segment for `line`, a smaller hollow dot for `dot`. The exact
  `+N` goes into the semantics label only.

### D8 — A rail event is excluded from the bottom bar strip — but only while the rail renders

Final decision on the draft's open question 1: **exclude.** Each channel means
one thing (rail = recurring commitments and whether you kept them; bars =
everything else today), and it frees `maxDayBars` slots that tracked events
currently burn — the second face of the same complaint.

Implementation: `EventDayBarProvider` gains `final bool railActive` (default
`false`, so the change is inert until wired) and skips events for which
`eventInDayRail(event)` is true — using the **same shared predicate function**
the rail provider uses, imported from `day_rail_resolver.dart`, never
duplicated. `railActive` is threaded through `DayBarsResolver.defaults`
alongside the existing `missedDisplay` parameter and comes from
`appearance.dayRailStyle != DayRailStyle.none`. When the rail is off, bars are
exactly today's — turning the rail off never silently drops events from the
grid.

### D9 — Ordering: `EventAgenda.compareWithinDay`, never re-sort

`CalendarBloc.eventsForDay` returns the list pre-sorted
(`lib/bloc/calendar/calendar_bloc.dart:238`, documented at 228-232: consumers
"can trust it arrives pre-sorted"). The rail provider iterates in arrival
order exactly as `EventDayBarProvider` does, and `DayRailResolver.resolve`
copies `DayBarsResolver.resolve`'s body (`day_bars_resolver.dart:236-255`):
`putIfAbsent`-by-key dedup, then a stable sort by priority with the
**insertion-index tie-break** — the `event:<uuid>` key-sort scramble that
motivated it is documented in `EventDayBarProvider`. Consequence: the mark
that survives the cap is the same event that wins the wash.

### D10 — Perf: a third memo in the existing generation scheme

Verified facts the draft had wrong, now the actual spec:

- `calendar_page.dart:186-187` holds `_barsOutputCache` and
  `_tintOutputCache`; both are cleared in `_syncResolverOutputCache`
  (lines 227-248) whenever the `_outputGeneration` **record** (declared
  213-225) changes. That record already contains `presenceRevision`, read from
  `state.presenceRevision` — a counter `CalendarBloc` bumps on every presence
  mark/clear (`calendar_bloc.dart:708, 731`). `EventPresence.revision` is
  **not** involved in page-cache invalidation and must not be added; marking a
  day missed already regenerates correctly through the state counter.
- Bars and tint are resolved in **different callbacks**: tint in
  `_buildDayCell` (1160-1163, `bloc` is a parameter there), bars in
  `markerBuilder` (1355-1382, events from `eventLoader`). The rail renders
  inside the cell, so it resolves in `_buildDayCell`, beside the tint lookup:
  `railOutputCache[key] ??= railResolver.resolve(day, bloc.eventsForDay(day))`.

Changes: add `Map<DateTime, List<DayRailMark>> _railOutputCache`, clear it
with the other two, and add a `railResolver` identity field to the
`_outputGeneration` record. Memoize the resolver like `_resolverFor`
(`calendar_page.dart:156-166`) — and note `_resolverFor`'s memo key must grow
`railActive`, since D8 changes the bars resolver's construction. Rail *style*
and *max* are paint-side widget parameters, not resolver inputs — changing
them must not invalidate the mark caches.

Per-cell cost target: one pass over the day's events, two static map probes
each, one list allocation only when the day has marks.

### D11 — Accessibility: one merged node per channel per cell

The draft wanted one node covering both channels; *(verified)* that is not
structurally possible — `CalendarDayBars` is built in table_calendar's
`markerBuilder` and the cell in `cellBuilder`, separate subtrees. Final
decision: **the rail carries exactly one merged `Semantics` node of its own**,
mirroring `CalendarDayBars`' `labelled()` pattern
(`calendar_day_bars.dart:145-154`): one `Semantics(container: true, label: …)`
wrapping `ExcludeSemantics(child: strip)`. Never a node per mark. The label
joins each visible mark's `semanticLabel` (which already embeds ", missed" via
the D6 ARB key — colour is never the only carrier) and appends `+N` on
overflow. A day therefore announces at most two marker nodes (rail, bars),
each meaningful — the 5.6 problem was per-sliver *unlabelled* nodes, not
labelled merged ones.

Test: `test/widgets/calendar_day_rail_semantics_test.dart` mirroring
`test/widgets/calendar_day_bars_semantics_test.dart`, asserting exactly one
node per cell with the composed label.

### D12 — Where the settings and controls live

- `lib/pages/calendar_settings_page.dart` — rail style selector
  (`SegmentedButton`, copy the markerStyle entry at 490-527) and the max
  slider (`SliderSettingRow`, copy 528-552), placed with the marker options,
  not the tint options. The live preview is `_AppearancePreview`
  (1036-1178) — it composes cells **by hand** (it does not call the
  resolvers), so it must be extended manually to paint the rail, or the
  settings page lies about the change. `_resetToDefaults` (~984-996) needs
  lines for both new keys.
- `lib/widgets/event_editor_sheet.dart` — a three-way `SegmentedButton`
  (Auto / Always / Never) for `showInDayRail`, immediately after the presence
  `SwitchListTile` (1936-1947) and **inside the same
  `_ruleHasManyOccurrences` gate** (line 1934) — the predicate excludes
  one-time events, so the control must too. Copy the
  `SegmentedButton<_DescriptionScope>` pattern at 1426-1454 (compact density,
  no selected icon, hint `Text` below).
- Settings keys `calendar_day_rail_style` and `calendar_max_day_rail_marks`
  via `SettingsKeys` + `SettingsService`. *(Verified correction:)* calendar
  appearance keys do **not** round-trip through JSON backup today —
  `BackupService._exportSettings` (`backup_service.dart:175-216`) is a
  hardcoded 27-literal allowlist with zero `calendar_*` entries. Do **not**
  add the new keys there in this feature; matching the existing behaviour is
  correct, and the missing-calendar-keys gap is a separate pre-existing issue
  (note it in phase 5's doc update, do not fix it here).

---

## Reuse obligations

Each is a place where a naive implementation duplicates solved work.

1. **Contrast outlining.** `CalendarDayBars` carries
   `_minContrastRatio` (static const, 1.6), `_luminanceOf` (static, memoized
   in `_luminanceCache` capped at 64), `_contrastRatio` (static, takes two
   resolved luminances), and `outlineFor` — *(verified)* a **build-local
   closure** over `surfaceLum` and `outlineColor`, not a method. This logic
   was retuned 2026-08-23 after a luminance *delta* outlined six of twelve
   marker colours in dark mode and none in light. Phase 3 extracts it to
   `lib/utils/marker_contrast.dart` (spec in the phase brief) and rewrites
   `CalendarDayBars` to call it. Never copy it; never reinvent with a delta.
2. **Fading.** Copy the `_fade` alpha-multiply
   (`color.withValues(alpha: color.a * opacity)` with an `opacity == 1.0`
   fast path) and take an `opacity` parameter. `Opacity` widgets were
   explicitly rejected: one offscreen layer per outside day, 22–26 per page.
   `CalendarDayCell` already knows `isOutside` and `outsideAlpha` (0.35).
3. **Missed handling.** Reuse `CalendarMissedDisplay`
   (`calendar_appearance.dart:47-64`); no rail-specific missed setting.
   Filter `hidden` before anything else, per D6.
4. **Resolver shape.** `DayRailResolver.resolve` =
   `DayBarsResolver.resolve` with the type changed — same dedup, same stable
   sort, same insertion-index tie-break, same "resolver does not cap; the
   widget caps".
5. **Model shape.** `DayRailMark` = `DayBar` + `missed`, identical field
   names, so the provider tests share fixture builders (the
   `day_bars_resolver_test.dart` style: a local `event(...)` closure builder,
   real `AppLocalizationsEn`, `setUp/tearDown(EventPresence.resetCache)` —
   no mocks).
6. **Row height.** `_rowHeight` (`calendar_page.dart:1095-1102`) is
   unchanged — the rail is vertical. Capacity depends on it, so
   `CalendarDayRail` takes its available height (LayoutBuilder or the
   Positioned's implicit bounds) and clamps the visible count.
7. **Call sites.** `CalendarDayCell` has exactly three call sites, none
   `const`: `calendar_page.dart:1164`, `calendar_settings_page.dart:1110`,
   `calendar_date_picker_sheet.dart:429`. All new parameters must be
   **optional with defaults** (`railMarks = const []`,
   `railStyle = DayRailStyle.none`) so the picker and preview stay correct
   untouched. *(Verified correction: the date picker passes no `tint:` at all
   and `CellTintResolver.none` has zero call sites — its doc comment is
   stale; don't imitate it.)*
8. **Tint untouched.** If `test/services/cell_tint_resolver_test.dart` needs
   edits, D3 has been violated.

---

## Phased plan — agent briefs

Phases land independently and in order; each leaves the suite green. Phases
1, 2 and 4 are Sonnet-sized (mechanical, strong precedents to copy). Phase 3
is the Opus phase — it touches the hot paint path, the memo scheme and a
refactor of an existing widget. Every agent loads `anta-context` first, plus
the skill named in its phase.

### Phase 1 — data (Sonnet; skills: `drift-migrations`)

1. `lib/database/tables/calendar_events_table.dart`: add
   `BoolColumn get showInDayRail => boolean().nullable()();`.
2. `lib/database/migrations/database_schema.dart`: `currentVersion` 33 → 34,
   add the `v34...` constant following the existing naming.
3. `lib/database/migrations/database_migrations.dart`: `_migrateV33ToV34`
   copying `_migrateV25ToV26`'s shape exactly (lines 851-876): read
   `PRAGMA table_info(calendar_events)` into a `Set<String>`, then if
   `show_in_day_rail` is absent,
   `customStatement('ALTER TABLE calendar_events ADD COLUMN show_in_day_rail INTEGER')`
   — nullable, **no** `NOT NULL DEFAULT`. Register a
   `Migration(fromVersion: 33, toVersion: 34, ...)` in `_migrations`. No
   backfill.
4. `lib/models/calendar_event.dart`: `final bool? showInDayRail;` — ctor
   (default null), `copyWith` with a `clearShowInDayRail` flag (copy the
   `clearColorValue` pattern), `props` entry, row↔model mapping wherever the
   existing fields map.
5. `lib/services/calendar_event_service.dart`: export
   `'showInDayRail': row.showInDayRail` beside `tracksPresence` (~line 232);
   import
   `showInDayRail: map['showInDayRail'] is bool ? Value(map['showInDayRail'] as bool) : const Value.absent()`
   beside the `tracksPresence` parse (~line 328) — absent means NULL means
   auto, so a v33 archive imports as before. `ImportExportService.
   archiveVersion` stays **1** (verified: v26/v28 additive columns never
   bumped it; the check only rejects newer-than-known).
6. `test/database/schema_parity_test.dart`: add `show_in_day_rail` to the
   `containsAll` list in the calendar_events test (371-430) with a
   `notnull == 0`, `dflt_value == null` assertion pair, following the v28
   precedent at 396-404. Do **not** touch the template DDL test.
7. Do NOT touch `calendar_event_templates`, `EventTemplate`, or the template
   editor (D2 scope cut).
8. Run `dart run build_runner build --delete-conflicting-outputs`, then
   `dart analyze lib`, then `flutter test test/database/`.

### Phase 2 — resolution (Sonnet; skills: `calendar-events`)

1. `lib/models/day_rail_mark.dart`: `DayRailMark` extends `Equatable` —
   `String key, Color color, int priority, bool missed, String
   semanticLabel`, const ctor, all in `props`. Copy `lib/models/day_bar.dart`
   verbatim and add the field.
2. `lib/services/day_rail_resolver.dart`:
   - Top-level `bool eventInDayRail(CalendarEvent event)` implementing D2's
     predicate. This is the **single** membership definition.
   - `abstract interface class DayRailProvider { Iterable<DayRailMark>
     marksFor(DateTime day, List<CalendarEvent> events); }` with the purity
     contract comment copied from `day_bars_resolver.dart:16-20`.
   - `EventDayRailProvider({this.missedDisplay = faded, required
     AppLocalizations l10n})` (or store the composed strings — follow how
     `DayBarsResolver.defaults(AppLocalizations l10n, …)` at
     `day_bars_resolver.dart:221-234` hands l10n to providers): per event, in
     arrival order — skip unless `eventInDayRail`; probe
     `EventPresence.isMissed(event.id, day)`; if missed and `hidden`,
     `continue` before adding; emit `DayRailMark(key: 'event:${event.id}',
     color: <same colour resolution as EventDayBarProvider>, priority:
     event.priority, missed: missed, semanticLabel: missed ?
     l10n.calendarRailMarkMissedLabel(event.title) : event.title)`. The ARB
     key is added in this phase (see step 5).
   - `DayRailResolver({required providers})` + `factory
     DayRailResolver.defaults(AppLocalizations l10n, {missedDisplay})` wiring
     the one provider; `resolve` copied from
     `DayBarsResolver.resolve` (236-255) with types changed, comments
     included (the stable-sort/tie-break rationale).
3. `lib/services/day_bars_resolver.dart`: `EventDayBarProvider` gains
   `final bool railActive` (const ctor, default `false`); at the top of the
   per-event loop: `if (railActive && eventInDayRail(event)) continue;`.
   `DayBarsResolver.defaults` gains `bool railActive = false` and threads it.
4. Tests:
   - `test/services/day_rail_resolver_test.dart` — fixture style copied from
     `day_bars_resolver_test.dart` (local `event(...)` builder, fixed
     `DateTime.utc` day, `AppLocalizationsEn`,
     `setUp/tearDown(EventPresence.resetCache)`). Cover: auto membership
     (tracksPresence recurring in, one-time out, non-tracked out); force
     in/out via `showInDayRail` including `true` on a one-time event staying
     out; missed flag set from `EventPresence`; `hidden` filtering before
     anything; dedup by key; priority order with insertion tie-break; missed
     semantic label composition.
   - Extend `test/services/day_bars_resolver_test.dart`: with
     `railActive: true` a rail event vanishes from bars and a non-rail event
     stays; with `railActive: false` (default) output is unchanged.
5. l10n for the one key this phase needs:
   `calendarRailMarkMissedLabel` = `"{title}, missed"` (with placeholder
   metadata) in `app_en.arb`, `app_de.arb`, `app_ro.arb` **together**, then
   `flutter gen-l10n`, check `untranslated.txt`. Load the `l10n` skill for
   copy style.
6. `dart analyze lib`; `flutter test test/services/`.

### Phase 3 — paint and wiring (Opus; skills: `calendar-events`)

1. **Extract the contrast helper** to `lib/utils/marker_contrast.dart`:
   move `_minContrastRatio`, the capped `_luminanceCache` + `_luminanceOf`,
   and `_contrastRatio` out of `lib/widgets/calendar_day_bars.dart`
   (lines 71-94) into, e.g., a `MarkerContrast` static utility exposing
   `double luminanceOf(Color)` and
   `Border? outlineFor(Color color, {required double surfaceLuminance,
   required Color outlineColor})` (the current `outlineFor` is a build-local
   closure at 115-129 — lift its body, parameterising what it closed over).
   Rewrite `CalendarDayBars.build` to call it. **Behaviour-preserving
   refactor: `flutter test test/widgets/` must pass before the rail is
   added.** Keep the 1.6 ratio and the ratio formula
   `(hi + .05)/(lo + .05)` exactly — no deltas.
2. `DayRailStyle { none, line, dot }` in
   `lib/models/calendar_appearance.dart` with the standard `fromName`
   fallback (default `none`). (The `CalendarAppearance` *fields* come in
   phase 4; the enum lives here now because the widget needs it.)
3. `lib/widgets/calendar_day_rail.dart`: stateless;
   `{required List<DayRailMark> marks, required DayRailStyle style, required
   int maxMarks, double opacity = 1.0, required CalendarMissedDisplay
   missedDisplay is NOT needed}` (hidden marks were filtered by the
   provider; the widget only fades). Geometry per D5/D7: `LayoutBuilder` for
   height, clamp visible count to what fits, overflow slot per D7, missed
   rendering per D6 (`missedEventAlpha` multiply; hollow in `dot`), `_fade`
   pattern for `opacity`, outlines via `MarkerContrast` with the same
   surface-luminance inputs `CalendarDayBars` uses. Semantics per D11: one
   `Semantics(container: true, label: joined)` over
   `ExcludeSemantics(child: strip)`; `+N` in the label only. Build with
   plain `Container`s/`BoxDecoration` like `CalendarDayBars` — no
   `CustomPainter`, no `Opacity`.
4. `lib/widgets/calendar_day_cell.dart`: new optional params
   `List<DayRailMark> railMarks = const []`, `DayRailStyle railStyle =
   DayRailStyle.none`, `int maxRailMarks = 3`. Per D4's structural note: only
   when `railMarks.isNotEmpty && railStyle != none`, wrap the existing result
   in the outer `Stack` with `Positioned(left: 4, top: 4, bottom: 4,
   width: 3)`. Pass `opacity: isOutside ? outsideAlpha : 1.0` down. The
   other two call sites compile untouched.
5. `lib/pages/calendar_page.dart`:
   - `_railOutputCache` beside lines 186-187; cleared with the others in
     `_syncResolverOutputCache`; `railResolver` identity added to the
     `_outputGeneration` record (213-225).
   - A memoized `_railResolverFor(l10n, missedDisplay)` next to
     `_resolverFor` (156-166); `_resolverFor`'s memo key and
     `DayBarsResolver.defaults` call gain `railActive:
     appearance.dayRailStyle != DayRailStyle.none` (until phase 4 adds the
     appearance field, hardwire `false` behind a local; phase 4 flips it —
     or coordinate to land 3+4 together, see below).
   - `_buildDayCell` (1142-1176): resolve
     `railOutputCache[key] ??= railStyle == none ? const [] :
     railResolver.resolve(day, bloc.eventsForDay(day))` beside the tint
     lookup and pass marks/style/max into `CalendarDayCell`.
6. Widget tests: `test/widgets/calendar_day_rail_test.dart` — both styles,
   the cap + overflow mark, height clamping, missed fading/hollow,
   outside-day opacity, empty-marks builds nothing; and
   `test/widgets/calendar_day_rail_semantics_test.dart` per D11 (mirror
   `calendar_day_bars_semantics_test.dart`, assert exactly one node and the
   composed "title, missed … +N" label).
7. `dart analyze lib`; `flutter test`.

### Phase 4 — settings, editor UI, l10n (Sonnet; skills: `l10n`)

1. `CalendarAppearance` (`lib/models/calendar_appearance.dart`): fields
   `dayRailStyle` (default `none`) and `maxDayRailMarks` (default 3) — ctor,
   `copyWith`, `props` (now 13 entries).
2. `lib/constants/settings_keys.dart`: `calendarDayRailStyle =
   'calendar_day_rail_style'`, `calendarMaxDayRailMarks =
   'calendar_max_day_rail_marks'`, plus defaults in the
   `// Default values for calendar` block (~line 338).
3. `lib/services/settings_service.dart` — all of *(verified list)*: add both
   keys to `_calendarAppearanceKeys` (1025-1037), decode them in
   `_decodeCalendarAppearance` (with `DayRailStyle.fromName` and an int
   clamp 1–5), and add `setCalendarDayRailStyle` / `setCalendarMaxDayRailMarks`
   setters following the existing ones. (`_calendarPageKeys` spreads the
   appearance list — no separate change.)
4. `lib/pages/calendar_settings_page.dart`: the two `SettingsEntry` rows per
   D12 (copy 490-527 and 528-552; slider `min: 1, max: 5, divisions: 4`);
   extend `_AppearancePreview` to paint the rail on its sample cells by
   passing marks/style/max into its `CalendarDayCell`s (it composes by hand —
   give the "overflowing" sample cell 4 marks so the overflow affordance
   previews); `_resetToDefaults` lines for both keys. Flip the phase-3
   hardwired `railActive` to read `appearance.dayRailStyle`.
5. `lib/widgets/event_editor_sheet.dart`: `bool? _showInDayRail` state,
   seeded from the event (~line 470 pattern), saved in all four save paths
   (1183/1218/1251/1270 region) — persist NULL when the segmented control
   says Auto, i.e. use the `clearShowInDayRail` copyWith flag. The three-way
   `SegmentedButton` (Auto / Always / Never) after the presence tile inside
   the `_ruleHasManyOccurrences` gate, copying 1426-1454's pattern, with a
   one-line hint `Text` explaining Auto follows presence tracking.
6. ARB keys ×3 + `flutter gen-l10n` + `untranslated.txt` check: rail style
   title/desc + per-option labels (None/Lines/Dots), max-marks title/desc
   (plural-aware like `calendarMaxDayBarsDesc`), the editor control title,
   hint, and the three segment labels. Copy style per the `l10n` skill.
7. `dart analyze lib`; full `flutter test`.

Sequencing note: phase 3 step 5 references an appearance field phase 4
creates. Either land 3 with `railActive`/style hardwired off (rail invisible
but fully tested at widget level) and let 4 light it up, or run 3 and 4 as one
agent session. Both are acceptable; do not reorder 4 before 3.

### Phase 5 — docs (rides with phase 4's session)

Update `docs/calendar-events-feature.md` (schema v34 addendum + the rail as a
render surface), `docs/presence-tracking-roadmap.md` (pointer: presence now
has a second render surface), the calendar bullets in `COPILOT_CONTEXT.md`
(third provider chain, third memo, the D8 bar-exclusion rule), and note the
pre-existing gap that `BackupService._exportSettings` covers no `calendar_*`
keys (D12). Flip this file's status header to implemented.

## Verification (whole feature)

`dart analyze lib` clean; `dart run build_runner build
--delete-conflicting-outputs` after phase 1; `flutter gen-l10n` clean after
phases 2 and 4; full `flutter test` green after each phase; a manual pass
(`flutter run -d windows` minimum, Android preferred) on a day carrying 1, 3
and 6 rail-eligible events, in both styles, both themes, `eventTint` on and
off, `CalendarMissedDisplay` both values, and the settings preview + date
picker sheet unchanged when the rail is `none`.
