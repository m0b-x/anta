# Day Rail Markers — Post-Ship Review (2026-08-31)

**Status: all findings fixed or explicitly accepted. Suite green at 1582
tests / 2 skipped.** The feature itself is described in
[day-rail-markers-roadmap.md](day-rail-markers-roadmap.md) (design record, now
carrying corrections) and in the v34 addendum of
[calendar-events-feature.md](calendar-events-feature.md) (running behaviour).
This file is the *review* record: what was actually wrong with the shipped
implementation, how each thing was found, what changed, and what is still open.

Read this before touching `CalendarDayRail`, `CalendarDayCell`'s chip geometry,
or the three provider chains — several of the roadmap's stated justifications
turned out to be arithmetically wrong, and this is where the real numbers live.

---

## How the defects were found

Worth recording, because the ordinary methods missed all of them.

- **`dart analyze` and a 37-test rail suite were both green over an invisible
  widget.** Every rail test read `BoxDecoration` and none read a laid-out
  `RenderBox`. A decoration is not a mark.
- **Rendering the widget to a PNG and looking at it** found the two collisions
  (chip and marker strip) and the vanishing missed dot in one pass. The
  technique: pump the cells into a `RepaintBoundary`, `toImage(pixelRatio: 6-8)`
  inside `tester.runAsync`, write the PNG, open it. Note the test font renders
  glyphs as fixed-width black boxes, so **text width in these renders is not
  representative** — "28" measures ~28px where a real font gives ~16px.
- **Measuring the real grid** rather than reasoning about it. A throwaway widget
  test pumping `CalendarPage` at a set `physicalSize` gives the true cell box:
  **51.43 × 62 at 360dp, 45.71 × 62 at 320dp, 58.86 at 412dp.** Most of the
  roadmap's geometry errors come from having assumed instead of measured.

---

## Defects found and fixed

### 1. The `line` overflow affordance laid out 0px wide — invisible

`Center` hands down *loose* constraints, and a childless `DecoratedBox` under
loose constraints takes `constraints.smallest`. The inner `SizedBox` set only
`height`, so the affordance measured **3px tall × 0px wide**. `line` style
therefore dropped its "there are more here" signal entirely whenever a day
exceeded the cap — the exact failure the rail suite's own header claimed to
guard.

Fixed with an explicit `width: lineWidth`; regression test asserts the
affordance's laid-out `RenderBox`, in both styles.

### 2. The bottom marker strip painted over the rail

The strip is **not part of the day cell** — table_calendar builds it in
`markerBuilder`, a sibling subtree painted *after* `cellBuilder` — and it insets
only `CalendarDayBars.defaultHorizontalInset` (6) from the cell edge, which is
inside the rail's lane (5 → 8 for `line`, 5 → 10 for `dot`). It overdrew 2 of
the line lane's 3px and 4 of the dot lane's 5px along the whole bottom segment.

Nothing in the roadmap considered this collision; D4 only ever reasoned about
the day-number chip.

Fixed by having the cell take the rail's height from its caller
(`CalendarDayCell.railHeight`), with the grid and the settings preview both
passing `rowHeight - 8 - stripHeight`. Rail height goes 54 → ~38, which still
fits the 5-dot maximum (37px), so no capacity is lost.

### 3. Missed dots vanished on adjacent-month days

D6 asked for missed marks to be *faded* **and**, in `dot` style, *hollow*. The
two cues multiply: on an outside-month cell
`outsideAlpha × missedEventAlpha` = 0.35 × 0.35 = **0.12 alpha on a 1px
hairline**, while the kept mark beside it stayed a filled disc at 0.35. The
missed commitment did not read as dimmed — it disappeared.

Changed to **hollow instead of faded** in `dot` style; `line`, which has no
shape cue to spare, keeps the alpha fade. One strong cue per style. Missed state
is on the semantics label either way, so colour was never the only carrier.

### 4. A cap of 1 rendered nothing but a neutral blob

D7's "`max - 1` marks plus a neutral one" degenerates at the slider's minimum:
one slot, several marks, and the user saw a grey blob instead of the day's top
commitment. The marker strip's `+N` chip can stand alone because it draws a
number; the rail's affordance draws nothing, so alone it carries strictly less
information than the mark it displaced. The same case arises from the height
clamp on a short row, so raising the slider's minimum would not have fixed it.

One slot now draws the top mark; the count rides the semantics label.

### 5. `_resetToDefaults` bypassed `SettingsKeys`

It read `defaults.dayRailStyle` / `defaults.maxDayRailMarks` — the *model's*
field initializers — while the adjacent `maxDayBars` line exists precisely to
route the one duplicated default through `SettingsKeys`. Change a key default
and Reset would silently write the old value while a fresh install read the new
one.

### 6. The settings preview never showed a missed mark at the smallest cap

Introduced by fix 4: the preview's missed sample sat at index 1, which stops
being drawn once only one slot exists. Moved to index 0, so hollow-vs-filled
previews at every cap.

### 7. Two doc comments asserted things that were false

- `_railResolverFor` promised rail style/max never invalidate
  `_railOutputCache`. With `eventTint` on, both fields are in
  `CalendarAppearance.props`, so `CellTintResolver.defaults` reallocates, the
  generation record changes, and **all three caches clear**. Harmless (one extra
  recompute on a settings return) but not an invariant to build on.
- `CalendarDayRail` claimed to be "cheap by construction, like
  `CalendarDayBars`" while being the only one of the two with a per-cell
  `LayoutBuilder`.

### 8. The capacity string was not plural-aware

`"Show up to 1 rail marks per day."` Now ICU plural in en/de/ro, with `few` for
Romanian. (`calendarMaxDayBarsDesc` has the same flaw and was left alone —
pre-existing, and outside this feature.)

---

## Design decisions changed from the roadmap

### D4's gutter budget was wrong, and so was the "nothing collides" claim

D4 reasoned: *"the chip is 34px, `Align(topCenter)`-centred; at the narrowest
plausible cell (~48px) each side has exactly 7px clear. 3+1+3 fits."* Two errors:

1. It assumed the tint edge stripe ends at **x = 3**. That `Positioned(left: 0,
   width: 3)` lives inside the tinted container's `margin: EdgeInsets.all(1.5)`,
   so it really ends at **4.5**. The real gutter at 360dp is 4.5 → 8.71 =
   **4.2px**, not 7.
2. It measured against the chip's **bounding box**, but the chip is a *circle*
   whose leftmost point sits exactly on that box edge at y = 21 — squarely in
   the vertical band the rail occupies. A phase-3 deviation note claimed "the
   chip is a circle, so nothing collides"; the opposite is true.

Measured consequence before the fix: the `dot` lane (to x = 10) overlapped the
filled today/selected chip by ~1.3px at 360dp, and at 320dp (gutter 4.5 → 5.86 =
1.4px) *both* styles overlapped.

**Resolution: the decoration yields, not the day number.**
`CalendarDayCell.railChipSize = 30` applies whenever the rail is on. Rejected
alternatives, and why:

| Option | Rejected because |
| --- | --- |
| Inset/shift the day number right | The whole grid and its weekday header align to that number; it also risks overflow on narrow cells. |
| Paint the rail *under* the cell | On a 320dp cell the today circle would occlude ~80% of a dot. |
| Shrink the dot to 4px | Buys ~1px, still overlaps at 320dp, and costs the hollow-missed ring its room. |

Three properties make the shrink safe:
- Applied **per style, never per cell** — a chip that shrank only on days with
  marks would make today's circle a different size from yesterday's.
- `chipZoneHeight` stays `4 + chipSize + 2`, so the row height and the whole
  grid are unaffected.
- The smaller chip is re-centred (`top: 4 + (chipSize - diameter) / 2`), so the
  **digit does not move** — pinned by a test.

At 360dp and up both lanes now clear the filled chip. Below ~340dp `dot` still
overlaps: clearing it needs a ~26px circle, which stops reading as a day chip.

### D11's `LayoutBuilder` removed; the rail is told its height

Capacity depends on the lane's height, and the rail measured it back with a
`LayoutBuilder` — a deferred subtree build on every visible cell of a grid tuned
over five perf phases, to learn a number the grid had already computed.
`CalendarDayRail` now takes `height`, and `CalendarDayCell` positions it with
`Positioned(top: 4, height: railHeight)` — one number rather than two that could
disagree. Verified in the real grid: `LayoutBuilder` descendants inside the rail
= **0**, rail height = 38 = 62 − 8 − 16.

The trade is real: the height is now *believed*, not measured, so a caller that
sizes the box differently from what it passes gets silently wrong capacity where
the `LayoutBuilder` was self-correcting.

### Reuse obligation 4 reversed: the chain algorithm is extracted

The roadmap asked for `DayRailResolver.resolve` to be a **copy** of
`DayBarsResolver.resolve`. That produced three byte-identical implementations
(bars, rail, summary) differing only in element type, so a fix to the ordering
rule had to land in three places or the grid, the rail and the day panel would
disagree about the same day — the exact divergence `eventInDayRail` was factored
out to prevent on the membership side.

Now: `ChainItem` (`lib/models/chain_item.dart`) exposes `key` + `priority`;
`resolveChain` (`lib/services/resolver_chain.dart`) is the one implementation of
dedup-first-provider-wins plus the stable priority sort with the
insertion-index tie-break. All three resolvers are a single line.

**Found while doing it: `DaySummaryResolver.resolve` had no unit coverage at
all** — only a bloc-sort test and a memo test — so the extraction was landing on
an untested surface. `test/services/resolver_chain_test.dart` (8 tests) now
stands behind all three.

### The editor control is gated on the rail being on

`showInDayRail`'s Auto/Always/Never control was shown for every recurring event
even though `dayRailStyle` defaults to `none`, so on a stock install it steered a
channel that painted nothing anywhere in the app. Its own comment rejected
offering a no-op, then applied that reasoning to only one of the two gates.

`_dayRailEnabled` is read in `_loadSheetSettings` alongside the palette and
description limit. A stored override **survives** the rail being switched off —
hiding the control must not reset what it controls; there is a test for that.

---

## Test-suite lessons worth keeping

- **Assert geometry, not decoration.** The 0px affordance passed 37 tests.
  Where a widget's whole job is to be visible, assert the `RenderBox`.
- **Assert combinations, not just axes.** Missed-with-opacity-1.0 and
  opacity-with-not-missed were both covered; their product — the one that
  multiplied two fades into invisibility — was not.
- **Pin measured numbers, not derived ones.** The chip-clearance tests read the
  rendered rects at real device widths rather than recomputing the arithmetic
  the design record got wrong.

---

## Still open

Nothing here is a defect in the feature; each is a documented trade or a known
piece of residue.

### Accepted design trade-offs

- **`dot` overlaps the today/selected chip below ~340dp.** Clearing it needs a
  ~26px circle. 360dp and up is clean. Pinned by a test so the numbers cannot be
  re-derived wrong.
- **Large system text has less headroom.** The day number is an unclipped `Text`
  in a fixed-diameter `Container`; 34 → 30 moves the point where a two-digit day
  outgrows its circle from roughly textScale 2.1 to ~1.9 (real font). It
  overflows rather than clips, so it bleeds into the neighbouring cell.
  Pre-existing shape, marginally worse. A `FittedBox` or explicit clip would fix
  it if it ever matters.
- **The editor's rail control pops in.** `_dayRailEnabled` starts `false` and
  arrives from an async settings read, so it is absent for the first frames and
  then appears, shifting what is below it. Matches how the sheet already loads
  the palette and description limit, but CLAUDE.md names stable layouts a hard
  rule, so this is a trade rather than a free win.

### Cheap cleanups — done

- **`stripHeight` was computed twice per cell.** `_railHeight` called
  `_rowHeight` (which computes it) and then computed it again — ~84 redundant
  calls per grid rebuild, on the exact path removing the `LayoutBuilder` was
  meant to lighten. `_CalendarTable.build` now derives the strip once and hands
  `railHeight` to `_buildDayCell`; `_rowHeightFor` / `_railHeightFor` are pure
  functions of it, so neither can recompute behind the other's back.
- **`CalendarDayCell.railHeight` no longer defaults to 38.** It is `double?`,
  `null` meaning "this cell draws no rail" — what the date picker leaves it at.
  Marks *with* no height now trip an assert, because the rail sizes itself from
  that number instead of measuring, so the failure is a wrong mark count rather
  than a crash. `defaultRailHeight` survives only as the release-mode fallback.
  Covered by "marks without a height are a loud caller bug".

### Cheap cleanups — deliberately not done

- **`resolveChain` allocates one `MappedListIterable` (plus its iterator) per
  call** where the old inline loops allocated none. Two small objects per cache
  miss, i.e. ~84 per full grid regeneration. Removing them costs more than they
  do:
  - a shared abstract base class (`ChainResolver<P, T>` with a `contributionOf`
    hook) would be allocation-free, but re-couples via inheritance the three
    resolvers this extraction just decoupled, and turns a plainly testable
    top-level function into a class hierarchy;
  - splitting the helper into `addChainItems` + `orderChain` is allocation-free
    and cheap, but leaves two calls that must happen in the right order — a
    worse API for the same three call sites.

  Neither is worth two objects per cache miss. Revisit only if a chain ever runs
  un-memoized.
- **`ChainItem` widens three models' public surface.** `key`/`priority` on
  `DayBar`, `DayRailMark` and `DaySummaryEntry` are now interface members;
  nothing enforces that a future implementor means the same thing by them.

### The drift "multiple databases" warning — a false positive, left alone

`calendar_page_jump_test`, `calendar_keyboard_collapse_test` and
`calendar_grid_output_memo_test` each opened **two** in-memory databases per test
(the second only to build repositories for `ImportExportBloc`) and closed
**neither**. That was a real leak and is fixed: one database, shared, closed in
`tearDown`.

The warning still prints, and this part is **not** a bug:

- the settings database is `openTestDatabase()` → `NativeDatabase.memory()`;
- the app's singleton is `CalendarEventService.getInstance()` →
  `AppDatabase.getInstance()` → `_openConnection(activeName)`, an **on-disk**
  file under the test's temp dir.

Drift warns whenever the generated class is constructed twice in a process, but
its stated danger — *"when these two databases use the same QueryExecutor"* —
does not apply: different executors, no shared state, no corruption risk. It is
structural to `SettingsService.forTesting` in page-level widget tests, not to
these three files.

Muting it would take `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true`
in a shared test bootstrap — one line, but it would also silence a future case
where the warning *is* real. Recommendation: leave it. Making it genuinely
single-instance means settings sharing the app singleton, which costs per-test
isolation.

### Needs a human: formatter churn

Running `dart format lib test` reformatted **24 files unrelated to this work**
(vocabulary, category picker, timeline, several test suites) — the newer Dart
formatter over older-formatted code. They are still uncommitted. The revert is a
`git checkout --` over those paths; it was blocked by the permission classifier
during the session, so it needs running by hand. Everything else in the working
tree is this feature.

---

## Files this feature touches

**New:** `lib/models/day_rail_mark.dart`, `lib/models/chain_item.dart`,
`lib/services/day_rail_resolver.dart`, `lib/services/resolver_chain.dart`,
`lib/utils/marker_contrast.dart`, `lib/widgets/calendar_day_rail.dart`, plus
`test/services/{day_rail_resolver,resolver_chain}_test.dart` and
`test/widgets/{calendar_day_rail,calendar_day_rail_semantics,event_editor_day_rail}_test.dart`.

**Changed:** the `calendar_events` table + v34 migration, `CalendarEvent`,
`CalendarEventService`, `CalendarAppearance`, `SettingsKeys`, `SettingsService`,
`DayBarsResolver`, `DaySummaryResolver`, `DayBar`, `DaySummaryEntry`,
`CalendarDayBars`, `CalendarDayCell`, `CalendarPage`, `CalendarSettingsPage`,
`EventEditorSheet`, the three ARB files.

## Verification

```powershell
dart analyze lib          # clean
flutter gen-l10n          # untranslated.txt is {}
flutter test              # 1582 pass, 2 skipped (benchmarks)
```

Still not done: a manual pass on a device. The roadmap's checklist — a day
carrying 1, 3 and 6 rail-eligible events, both styles, both themes, `eventTint`
on and off, both `CalendarMissedDisplay` values, and the settings preview and
date-picker sheet unchanged when the rail is `none` — has only been exercised
through widget tests and rendered PNGs.
