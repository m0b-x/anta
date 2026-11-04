# S5 — report cards II: the designer's spec (2026-11-04, Opus 5.5)

> **As built (2026-11-04)** — the record's §12.2 S5 note carries the build, the reviews and decisions BK–BV. Where the build differs from the text below: §2.2's templates follow the row's own fact kind and digit counts in 8s (not a fixed 888), measured bold-aware with the widest name; the tags are per-tag cards with the group gap, so the closed card is 384 dp, and the headers beside the fold chevron measure 66 / 77.4 / 140; §2.3's caption writes the hours in the calendar's own time format ("6:00 PM–7:00 PM", bound); §2.5's "against October 2025" holds for a whole month only — a month so far names its counted days (D28) — the trend with ticks at de 2.0 is 342 dp, and the de / ro Compare row stacks at 1.0 (footer 201 / 213 / 333); §2.6's words shipped as `tagWords`, `tagTemplates(widest:)`, `whenWords(weekStart:)`, `balanceWords(percent:)`, `shares`, `compareName` and `caption(beside:)`, and `ReportTotalsCard` takes a `tileIdentifier` callback; the disclosures speak "tag ana"; the refold anchor is the nearest section label above the viewport (S6's H, brought forward).

The renders are real. They use Roboto and MaterialIcons from a `git archive HEAD` snapshot, rendered at pixel ratio 2, because the main tree is being edited. HEAD has no `ReportTag` / `ReportWhen` / `balance`. The existing parts are HEAD's own: the `ReportGroupStack` Categories group, `ReportTotalsCard`, `ReportBand`, `FormMeterRow`, `FormMenuRow`, `FormActionRow`, `FormRowGroup`, `FormSectionLabel` and `showMenu` with `FormMenuChoiceItem` / `formMenuPosition`. The proposed cards are built from those primitives in the scratch test, using fixture data written to the model's fields:
- the heatmap painter and the trend's last-year marks are scratch painters that follow this spec;
- the tag rows' `captionLines` is a scratch copy of S4's field.

The strings are my drafts, measured in en / de / ro. The matrix: light and dark; 1.0, 1.3 and 2.0 linear; en / de / ro; 360 and 412 wide (600 for Compare). Renders and `measurements.txt` are in `…\scratchpad\s5_renders\`. The ramp check is in `…\scratchpad\s5_tools\ramp.mjs`; it runs dataviz's `validateOrdinal` and `contrast`. Tolerance is ±1 dp unless a test pins a value. S4's §1–§2 still apply (slivers, labels, row shapes, glyph rules); this spec adds to them.

## 1. Diagnosis

- **Compare with cannot go in the period menu.** Today's menu has 10 rows. It is 452 dp tall, opens under the title (top 128) and fits at 1.0 and 2.0 (`menu_light_1.0_en_today.png`, `menu_light_2.0_en_today.png`). Adding a divider, a "COMPARE WITH" label and 3 rows makes it 620 dp. It then flips above the title, covers the band (top 32), and still scrolls 12 dp at 360 × 780 1.0. It scrolls 30 dp at 1.3 and 189 dp at de 2.0, where the whole compare section is scrolled out of sight (`crop_menus.png`). The menu would also need two radio groups and a new non-interactive label entry, neither of which `showFormMenu` has. This breaks the 'advanced controls one level down' rule and 'nothing moves under the finger' (the menu changes side).
- **A tag header cannot carry four facts on one shrinking line.** I first drew the tag header as the Categories group header, with `FormMeterRow`'s one-line shrink slot. "2 Reisen · 5 Tage · zuletzt Mo. 12" shrank to 0.53 at de 2.0, and en 2.0 shrank to 0.62 (`crop_de20.png`, `measurements.txt` "SHRUNK"). The roadmap's own examples carry two facts each ("6 evenings · last Fri 24", "2 trips · 5 days", "3 services · 1,240"). With two facts and S4's `captionLines` template rule, nothing shrinks (`crop_tags_proposed.png`).
- **An open-by-default tag card is too tall.** The groups' fold rule is "absent is open". With one tag open plus its rows, the card is 617 dp at 1.0 and 905 dp at 2.0 (`tail_light_1.0_en.png`). Closed headers, four of them, followed by "4 more", take 316 dp at 1.0.
- **Square heatmap cells cannot hold seven weekday labels.** At 360 the grid's column pitch is 10.9 dp at 1.0 and 9.8 dp at 2.0, while a caption line is 18 dp at 1.0 and 36 dp at 2.0. With square cells the labels thin to Mon / Fri at 2.0. "Mon" also clips at the card's top, and the grid is 69 dp tall (`crop_square_20.png`). Rows taller than wide, capped at twice the column pitch, show all seven labels at 1.0 and Mon / Wed / Fri / Sun from 1.3 up (`crop_when_balance_both.png`, `crop_de20.png`).
- **An outline behind the columns hides last year wherever this year is higher.** In the 12-month render it hides 4 of 10 months (`crop_trend_lastyear.png`, the lower card). A 2 dp tick on top of each column, with a 1 dp `rowGroup` ring, reads in both cases and in both themes (`crop_tick.png`). The ring is load-bearing: the dark `onSurfaceVariant` tick against the dark `primary` column measures 1.00:1.
- **A four-step ramp straight from `primary` fails light.** Steps at 25 / 50 / 75 / 100 % of `primary` over `rowGroup` put the lightest step at 1.44:1 on light, under the ordinal 2:1 floor. Steps at 50 / 67 / 84 / 100 % pass in both themes (§2.3).
- **The model counts Sleep in When.** `_fillWhen` takes every timed kept sample. A nightly 23:00–07:00 Sleep fills a third of the grid every week and would always be the "busiest" hour. Balance already excludes Sleep (model ask 1).
- **Balance reads right as specified** (`crop_when_balance_both.png`): four 66 dp `FormMeterRow`s with the area glyph in the 40 box and the meter in `primary`. Nothing to change beyond the caption (§2.4).
- **A second Totals card stays aligned only with the same tiles.** At 600 dp, two cards with the same tile set stay row-aligned at 1.0 (217 / 217 dp) and at de 1.3 (499 / 499 dp, one column each; `crop_totals_600_de13.png`). D15 lets the tiles follow the selection, so a view with no tracked category would drop Attended and break the alignment.

## 2. The spec

### 2.1 Body order and slivers

The order is Categories → **By tag** → Over time → **When** → **Balance** → Missed → Ahead → **Compare row + footer**. Each new card follows S4's pattern: `[SizedBox(groupGap 18), FormSectionLabel, SliverToBoxAdapter(RepaintBoundary(card))]`. The exception is By tag: its tags are slivers in the page's one scroll (§2.2).

| Card | Drawn when | Absent otherwise |
|---|---|---|
| By tag | `report.tags.isNotEmpty` | a calendar without `#` words inserts nothing |
| When | `report.when?.busiestWeekday != null` (model: ≥ `AnalyticsMetrics.whenMinTimedSamples` 10) | — |
| Balance | `report.balance.length >= AnalyticsMetrics.balanceMinAreas` (2) | an unprofiled calendar is all Custom, `countsHours` false, so there is no area |
| Compare row | `period != null && report != null`, like the footer | — |

- **Tenses.** In a plan the model leaves When empty (no kept days). By tag and Balance follow the model's content.
- **Unprofiled identity.** A calendar with no tags, fewer than 10 timed days and no profiles inserts no S5 card. The one exception is the Compare row, which adds 48 dp to the footer card (decision A). The report_body_test October fixture has 9 timed kept days (8 Gym, 1 Dentist), so When stays absent and its goldens hold apart from the footer row. The guide's stage passes `onCompare: null`, so the row is not drawn there (decision A): the stage stays pixel-identical. This breaks the body's usual rule that a null callback draws its control disabled. The reason is that the stage has no compare to offer, so a dimmed row would only teach a dead control.

### 2.2 By tag card

| Element | Proposed |
|---|---|
| Label | `FormSectionLabel(reportSectionTags)` "By tag" |
| Shape | the Categories group's shape: one `SliverList` per tag inside a `ReportGroupStack` keyed `ReportCard.tags` (new enum value), so "Show less" keeps §4.8 S's scroll compensation and `onShrink` |
| Tags shown | the first `ReportMetrics.groupPreviewRows` (4) of `report.tags` (the model's order, ≤ `AnalyticsMetrics.tagRows` 8). Then `FormActionRow.disclosure(expand_more_rounded, reportGroupMore(n))` expands **in place** to all of them, and "Show less ▴" (`reportGroupLess`) folds back. It is drawn only when tags > 4 |
| Fold default | **closed**. `ReportGroupFolds.isOpen` defaults to false for `ReportCard.tags` and stays true for the other cards. One more flag holds the card's "n more". Folds are per visit (X) |
| Header | `FormMeterRow(leading: EventAvatar(icon, colour of tag.categoryIds.first), label: '#' + tag.label, caption: facts, captionLines: template lines (S4's field), fraction: tag.count / largest shown tag's count, meterColor: that category's colour, trailing: AnimatedRotation(FormTrailingGlyph(expand_more_rounded)), expanded: open, onTap: toggle)` |
| Facts (two, never more) | First the count, with the noun from the kind of `categoryIds.first`. Then one fact per kind: **Trip** → `events` "2 trips" + days "5 days" (`count`); **Maintenance, Bill** → `count` "3 services" + money (`spentCents − receivedCents` through the ledger's display formatter; "+1,240" when only received; dropped at 0, which falls back to last seen); **everything else** → `count` + last seen ("last Fri 24", "today", "yesterday"; the day as the dated rows write it, with the month when the span crosses months; dropped when `lastSeenDay` is null) |
| Nouns (B) | social "evenings", trip "trips", maintenance "services", workout "sessions", every other kind and Custom "times" ("once" at 1) |
| `captionLines` | S4's rule D: the lines the row's own template takes at the caption width. The template is the count written as 888 with the same noun, then the row's second fact as a template: "last {widest weekday} 28[ {MMM}]", "888 days", or "8,888" through the formatter. The value never decides. Content is centred in the minimum height, so a spare line reads as padding |
| Open tag rows | the Categories dated rows, unchanged: `AgendaDayListRowBuilder.entryRow`, `avatars: false`, one-line caption from `ReportLabels.rowSubtitle`. The first 4 show, then "n more ▾" / "Show less ▴", and "Show as list" past `maxListRows`. Tapping a row opens the detail sheet on its day (`onDatedTap`) |
| Semantics | Header: one node, button, `expanded`, label "tag ana, 6 evenings, last Saturday 24 October" (`reportTagSpoken`). '#' is read as "tag", never as "number sign". Rows and disclosures use the Categories patterns |

Measured at 360. Tag header rows are 66 dp at 1.0 in every locale. At 1.3 they are 77.4, or 100.8 for the long "last …" template in de or in a cross-month span. At 2.0 they are 140, 104 (ro maintenance) or 176 (de cross-month). The closed card (4 + "n more") is:

| Scale | en | de | ro |
|---|---|---|---|
| 1.0 | 316 | 316 | 316 |
| 1.3 | 361.6 (408.4 cross-month) | 408.4 | — |
| 2.0 | 616 | 616 (688 dark cross-month) | 580 |

At 412 de 2.0 it is 580. Dated rows under an open tag are 62 / 67 / 94, and the disclosure is 48 / 48 / 52. No caption shrinks, no paragraph is cut, and `takeException` is null in every cell.

### 2.3 When card (`ReportWhenChart`, new file `lib/widgets/report_when_chart.dart`, the trend's sibling)

| Element | Proposed |
|---|---|
| Card | the trend's: `Material(card, rowGroup, groupRadius)`, padding `chartPaddingHorizontal` 16 / `chartPaddingVertical` 12. There is no top row: no legend (one series, so dataviz says none) and no peak |
| Grid | 7 rows from the week start × 24 hour columns, one `CustomPainter`, behind its own `RepaintBoundary` |
| Label column | the widest of the seven `DateFormat.E(locale)` names, measured as `Text` draws them (`DefaultTextStyle` merged, bold-text aware, like the trend's axis), + `ReportMetrics.whenLabelGap` 8 |
| Column pitch | `(width − labelColumn) / 24`. Cell width = pitch − `ReportMetrics.columnGap` (2) |
| Row pitch | `clamp(scaledCaptionLine, pitch, ReportMetrics.whenRowAspectMax (2.0) × pitch)`. Cell height = row pitch − 2. Cell radius `ReportMetrics.whenCellRadius` 2 |
| Weekday labels | caption style (13 / 18, `onSurfaceVariant`), one line, centred on the row's cell. Every `ceil(scaledLine / rowPitch)`-th row from row 0: all seven at 1.0; Mon / Wed / Fri / Sun from 1.3 up (for a Monday start) |
| Hour labels | under the grid after `axisGap` 4, one caption line, each centred on its column. The step is the smallest of `ReportMetrics.whenHourSteps` [3, 6, 12] where step × pitch ≥ widest label + `axisLabelMinGap` 4. 24-hour: "0 3 6 … 21" at 1.0 / 1.3, "0 6 12 18" at 2.0. 12-hour: `DateFormat.j` hour-only ("6 AM"), step 6 at 1.0, 12 at 2.0 |
| Ramp (C, D) | empty cell = `rowDivider` (the meter's track). A filled cell = `Color.lerp(rowGroup, primary, t)` with t = `ReportMetrics.whenRamp` [0.5, 0.67, 0.84, 1.0], at step `ceil(4 × minutes / peakCell)` clamped to 1–4. These are linear steps of the peak cell, computed from the tokens, never hex |
| Caption | after `chartCaptionGap` 12, caption style, wrapping: "Busiest: Tuesday · 18:00–19:00" (`reportWhenBusiest`). The weekday is `DateFormat.EEEE` of `busiestWeekday`; the hours are `busiestHour` to +1 h in the calendar's time format (`use24Hour`) |
| Semantics | one node, `identifier: report-when`, label "When. Busiest day Tuesday, busiest hour 18:00 to 19:00, over 34 timed days." (`reportWhenSpoken`). The cells are `ExcludeSemantics`. The Categories rows are its table twin |

**Ramp, measured** (`ramp.mjs`; validateOrdinal PASS in both themes; monotone, ΔL ≥ 0.06, hue spread ≤ 6°):

| Theme | steps | vs `rowGroup` | step 1 vs empty track |
|---|---|---|---|
| light (`#FEF7FF`, primary `#6750A4`) | `#B3A4D2 #9987C2 #7F6BB3 #6750A4` | 2.18 · 3.03 · 4.29 · 6.12 | 1.77 |
| dark (`#211F26`, primary `#D0BCFF`) | `#796E93 #9688B7 #B4A3DC #D0BCFF` | 3.46 · 5.05 · 7.15 · 9.56 | 2.61 |

The cells are a texture, not text. Words carry the facts (the caption, the spoken label, the Categories rows), and that answers the light step-1 WARN that dataviz requires a relief channel for.

**Measured** (geometry from `measurements.txt`):

| Width, scale, locale | label column | pitch | cell | row pitch | labels | hour step | card |
|---|---|---|---|---|---|---|---|
| 360, 1.0 en | 34.7 | 10.89 | 8.89 × 16 | 18 | every row | 3 | 202 (grid 126) |
| 360, 1.3 en | 42.5 | 10.56 | — | 21.13 | every other | 3 | 234.3 |
| 360, 1.3 de | — | — | — | — | — | — | 239.9 |
| 360, 1.3 ro | — | — | — | — | — | — | 231.6 |
| 360, 2.0 en | 60.6 | 9.81 | — | 19.61 | every other | 6 | 285.3 (the caption wraps to 2 lines) |
| 360, 2.0 de | — | — | — | — | — | — | 293.8 |
| 360, 2.0 ro | 67.6 | — | — | — | — | — | 281.2 |
| 412, 1.0 | — | 13.05 | 11.05 × 16 | — | — | — | 202 |
| 412, 2.0 de | — | — | — | 25.16 | — | — | 324.2 |

### 2.4 Balance card

| Element | Proposed |
|---|---|
| Label | `FormSectionLabel(reportSectionBalance)` "Balance" |
| Rows | one `FormMeterRow` per `report.balance` entry, **by minutes, largest first** (ties in `LifeArea` order) (E). `FormRowGroup(trailingGap: false)` |
| Leading | `FormGlyph(areaIcon, color: onSurfaceVariant)` centred in the 40 box (text at x 70 like every report row). The new map is `CalendarIcons.areaIcon(LifeArea)`: health `monitor_heart_rounded`, work `work_rounded`, money `payments_rounded`, people `people_rounded`, home `home_rounded`, leisure `beach_access_rounded`, other `category_rounded` (F) |
| Label / caption | `lifeArea<Name>` (S3's strings) · "38 h · 67 %": `ReportLabels.hours` + the share of the shown total, through `NumberFormat.percentPattern(locale)`. One-line shrink slot (default `captionLines`): the facts are short; no shrink was measured at de 2.0 |
| Meter | minutes / largest area's minutes; fill `primary` (areas have no colour); track `rowDivider` |
| Tap | none, `onTap: null` (a read row) |
| Semantics | one node, `report-balance-<area>`, label "Work, 38 hours, 67 percent of the hours" (`reportBalanceSpoken`) |

Measured: rows 66 / 77.4 / 104 in every locale. Four areas take 267 / 312.6 / 419 dp at 360 and at 412.

### 2.5 Compare with

| Element | Proposed |
|---|---|
| Where (A) | **The footer card's first row**, not the period menu (§1). It is a `FormMenuRow<ReportCompare>(glyph: compare_arrows_rounded, label: reportCompareWith "Compare with", value: the choice's name, menuWidth: FormMetrics.menuWidth, identifier: report-compare)` above Show as list / Share / Send. The period menu is unchanged |
| Menu items | "Previous period" (`history_rounded`, `report-compare-previous`) · "Same period last year" (`event_repeat_rounded`, `report-compare-last-year`) · one item per saved `OverviewView` in its stored order, with its name and `bookmark_border_rounded` (`report-compare-view-<viewId>`). With no saved views there is one disabled item "No saved views" (`report-compare-none`), disabled and never hidden. A view's name opens nothing further: one tap (G) |
| Disabled | "Same period last year" is disabled (38 %) when the shifted span starts before `years.first` |
| State (H) | per visit, kept by the page beside the folds. It starts at Previous. A deleted view falls back to Previous |
| Row value | "Previous period" / "Same period last year" / the view's name; one line, ellipsis. At 2.0 the primitive stacks the value under the label (`crop_footer_20.png`) |
| Footer heights | 195 / 213 / 293 dp with the row (+48 at 1.0) |

**What each choice draws:**

| Choice | Totals | Caption | Over time |
|---|---|---|---|
| Previous | today's | today's | today's |
| Same period last year | the tiles' deltas read `compared` | names its span through the existing `comparisonName`: "To 30 October · against October 2025" | each bucket gains a last-year tick (below) |
| A saved view, < 600 dp | stacked: `FormSectionLabel(reportSectionTotals)` → card, then `groupGap` 18 → `FormSectionLabel(view.name)` → the view's card. **No deltas on either card**; the two columns are the comparison (I) | one, under the second card: "To 30 October · beside Work / Life" (`reportCaptionBeside`) | unchanged |
| A saved view, ≥ 600 dp | side by side in a `Row`, each `Expanded`, `groupGap` 18 between, each with its own label above its card | under both | unchanged |

- **The view's card uses the page's tile set and order (J).** A tile the view lacks shows its dash value, so the rows of the two cards align (217 / 217; 499 / 499).
- The view card's tiles carry `report-view-tile-<tile>`: `ReportTotalsCard` gains an `idPrefix`, so the page's `report-tile-*` stay unique.
- The 600 dp rule reads the body's width, not the screen's.

**The last-year tick (K).**
- It is drawn after the columns, at the bucket's last-year happened count, as wide as the column.
- First a 4 dp band in `rowGroup` (the ring), then a 2 dp band in `onSurfaceVariant` centred in it.
- When last year is 0 there is no tick.
- The plot's peak becomes max(this year's columns, last year's counts), so a tick never clips; the peak label shows that number.
- Legend: a third item, "Last year" (`reportLegendLastYear`), whose swatch is a 2 dp `onSurfaceVariant` bar across `labelDotSize`. The legend row then draws whenever ticks exist.
- The spoken label appends "; same period last year, 41 events" (`reportTrendLastYearSpoken`).
- Contrast: the tick against `rowGroup` is 8.88 / 9.56. On a column the ring separates it (`primary` against the ring is 6.12 / 9.56).
- Measured: card 178 dp at 1.0 and 270 dp at de 2.0, today's geometry.

### 2.6 Constants and files

| Constant | Value | Why |
|---|---|---|
| `ReportMetrics.whenLabelGap` | 8 | weekday names to the grid |
| `ReportMetrics.whenCellRadius` | 2 | — |
| `ReportMetrics.whenRowAspectMax` | 2.0 | a row's height, at most twice a column's |
| `ReportMetrics.whenHourSteps` | `[3, 6, 12]` | — |
| `ReportMetrics.whenRamp` | `[0.5, 0.67, 0.84, 1.0]` | the validated steps; its doc cites §2.3's table |
| `ReportMetrics.trendLastYearTick` | 2 | — |
| `ReportMetrics.trendLastYearRing` | 1 | — |

- Reused: `columnGap` 2 (the cell gap), `axisGap`, `axisLabelMinGap`, `chartCaptionGap`, `groupPreviewRows` 4, `AnalyticsMetrics.whenMinTimedSamples`, `balanceMinAreas`, `tagRows`.
- Widgets:
  - `report_when_chart.dart` (new);
  - By tag's rows next to the group rows in `report_category_group.dart`;
  - Balance in S4's `report_analytics_cards.dart`;
  - the Compare row in `report_body.dart`'s `_buildFooter`;
  - the trend's tick in `report_trend_chart.dart` (`_TrendPainter` gains `lastYear`).
- Words go in `ReportLabels`: `tagFacts`, `tagTemplate`, `tagSpoken`, `whenCaption`, `whenSpoken`, `balanceFacts`, `balanceSpoken`, `compareName`, and `trendWords` extended. It stays free of widgets.
- No new primitive. `FormMeterRow.captionLines` is S4's. `CalendarIcons.areaIcon` is a map, not a widget.

### 2.7 Model asks

1. When leaves out Sleep-kind samples, as Balance does.
2. `ReportTag` gains `kind: CategoryKind`, the effective kind of `categoryIds.first`, so the page picks the noun without a profile lookup.
3. `ReportTrend.lastYear: List<int>?`: happened counts per bucket index of the span shifted one year, only when `ReportCompare.lastYear` is chosen.
4. `CalendarReport.compared` (S2b) folds the view's selection over the same span with the page's tile set (J).

### 2.8 New strings (en; de and ro are the implementer's, measured in drafts)

**Section labels**

| Key | en |
|---|---|
| `reportSectionTags` | "By tag" |
| `reportSectionWhen` | "When" |
| `reportSectionBalance` | "Balance" |

**By tag**

| Key | en |
|---|---|
| `reportTagCount` | "{kind, select, social{{count, plural, =1{1 evening} other{{count} evenings}}} trip{{count, plural, =1{1 trip} other{{count} trips}}} maintenance{{count, plural, =1{1 service} other{{count} services}}} workout{{count, plural, =1{1 session} other{{count} sessions}}} other{{count, plural, =1{once} other{{count} times}}}}" |
| `reportTagDays` | "{count, plural, =1{1 day} other{{count} days}}" |
| `reportTagLastSeen` | "{when, select, today{today} yesterday{yesterday} other{last {day}}}" |
| `reportTagSpoken` | "tag {name}, {facts}" |

**When**

| Key | en |
|---|---|
| `reportWhenBusiest` | "Busiest: {weekday} · {hours}" |
| `reportWhenSpoken` | "When. Busiest day {weekday}, busiest hour {hours}, over {count, plural, =1{1 timed day} other{{count} timed days}}." |

**Balance**

| Key | en |
|---|---|
| `reportBalanceSpoken` | "{area}, {hours}, {percent} of the hours" |

**Compare**

| Key | en |
|---|---|
| `reportCompareWith` | "Compare with" |
| `reportComparePrevious` | "Previous period" |
| `reportCompareLastYear` | "Same period last year" |
| `reportCompareNoViews` | "No saved views" |
| `reportCaptionBeside` | "beside {view}" |
| `reportLegendLastYear` | "Last year" |
| `reportTrendLastYearSpoken` | "same period last year, {count, plural, =1{1 event} other{{count} events}}" |

- Counts are bound to their words with a no-break space (S4 W).
- Reused: `lifeArea<Name>` (S3), `reportGroupMore` / `Less` / `MoreSpoken` / `LessSpoken`, `reportSectionTotals`, the caption's "against {name}".
- Translator rule: keep the de / ro tag nouns ≤ 10 characters ("Abende", "Reisen", "Wartungen", "Einheiten"; "seri", "călătorii", "revizii", "ședințe"). The `captionLines` template measures whatever ships.

### 2.9 Ids

| Element | Id |
|---|---|
| Tag header | `report-tag-<key>` |
| Its disclosure | `report-tag-more-<key>` |
| Its "Show as list" | `report-tag-list-<key>` |
| Its dated rows | `report-tag-row-<key>-<eventId>-<yyyy-MM-dd>` (a tag's row can also be a Categories row) |
| The card's "n more" | `report-tags-more` |
| When | `report-when` |
| Balance rows | `report-balance-<area>` |
| Compare row | `report-compare` |
| Compare items | `report-compare-previous`, `-last-year`, `-view-<viewId>`, `-none` |
| The view's tiles | `report-view-tile-<tile>` |

Each new id lands in `SemanticsIds` in the same change, and `tool/qa/flows/calendar/` gains a report flow: open a tag, pick Same period last year, pick a view.

## 3. What stays, and why

- The period menu stays 10 rows, 452 dp, in every locale and scale. Its ids are unchanged.
- Today's geometry stays:
  - Categories / Missed / Ahead groups: header 66 / 77.4 / 104, rows 62 / 67 / 94;
  - `ReportTotalsCard`'s tiles and column rule;
  - the trend's plot (80 dp), axis, caption and colours;
  - the footer's three actions;
  - `AgendaPeriodNav`.
- The fold rule "absent is open" stays for every card except tags.
- S4's cards and anchors are untouched. By tag sits under Categories, so S4's Totals-label anchor (R) already covers its refolds above the reader.

## 4. Risks

- **Height at the clamp.**
  - On a profiled, tagged page the three cards add about 785 dp at 360 en 1.0: tags 316 + When 202 + Balance 267 + three labels and gaps.
  - At de 2.0 they add 616 + 294 + 419 ≈ 1,400 dp. All of it sits below Categories, so the first screen is unchanged.
  - A saved-view compare at 360 doubles Totals: 434 dp at 1.0, 1,418 at de 2.0. The owner should see this on a device.
- **Text scale.** Weekday labels thin to every other row from 1.3 up. The 12-hour axis drops to "12 AM · 12 PM" at 2.0. Tag rows reach 176 dp at de 2.0 in a cross-month span. These are accepted; the caption and the spoken label carry the facts.
- **German and Romanian** are drafts. The tag-noun lengths decide the 1.3 line counts, and the runtime template follows them.
- **Dark.** All values are tokens and lerps of tokens. The ramp is validated against the dark ground; the tick needs its ring.
- **Unprofiled identity** depends on the When threshold. Any calendar with ≥ 10 timed kept days gains When, which is intended by the roadmap but is a visible change on a plain calendar (walkthrough 1 should say so). The Compare row changes every page's footer by 48 dp (A).
- **Semantics** are unheard: "tag ana", and the When sentence read by TalkBack.
- **Keyboard** is not involved: the page has no field.
- **Model** asks 1–4 are prerequisites, and ask 1 is a builder change.

## 5. Decisions taken by default (each reversible)

- **A. Compare with is the footer card's first row, and the period menu is unchanged.** The section version made the menu 620 dp; it flips over the band and scrolls the whole section out of sight at de 2.0. *Alt:* the menu section (needs a two-group `showFormMenu` and a label entry). *Alt 2:* its own one-row card above the footer. Unprofiled pages gain the 48 dp row. *Alt:* draw it only when a saved view exists or `years` reaches back a year.
- **B. Tag nouns:** evenings / trips / services / sessions, else "times" ("once"). Two facts per tag. *Alt:* the roadmap's "occurrences" as the generic noun; or every fact on one shrinking line.
- **C. The ramp is 50 / 67 / 84 / 100 % of `primary` over `rowGroup`, and empty cells are `rowDivider`.** *Alt:* 25 / 50 / 75 / 100 (fails light, 1.44:1).
- **D. Cells step linearly by the peak cell.** *Alt:* quartiles of the non-empty cells (always four levels, less honest about magnitude).
- **E. Balance is ordered by hours, largest first.** *Alt:* `LifeArea` order (stable across steps).
- **F. Area glyphs** as in §2.4, held in `CalendarIcons.areaIcon`.
- **G. Saved views are listed in the compare menu itself.** *Alt:* "A saved view…" opening the views sheet in pick mode.
- **H. The compare choice lasts for the visit.** *Alt:* a `SettingsKeys` value.
- **I. A view compare drops the deltas on both cards.** *Alt:* keep the page card's deltas against the previous period.
- **J. The view's card takes the page's tile set.** *Alt:* its own (D15), which breaks row alignment.
- **K. Last year is a column-wide tick on top with a ring.** *Alt:* the record's outline behind the columns, which hides any month where this year is higher.
- **L. When's rows are taller than wide, at most 2:1, with weekday labels thinned past that.** *Alt:* square cells (Mon / Fri only at 2.0, "Mon" clipped).
- **M. When has no legend and no peak figure.** *Alt:* a "Less ▪▪▪▪ More" row.
- **N. The When caption names the two marginals ("Busiest: Tuesday · 18:00–19:00") as the model computes them.** *Alt:* the single busiest cell, which needs a model field.
- **O. By tag opens closed, 4 shown, "n more" in place.** *Alt:* all 8 tags shown.
- **P. Tag headers carry a meter (count over the largest tag) in the first category's colour.** *Alt:* no meter (62 dp rows, like Missed headers).

## 6. For the design-reviewer, after S5

**States to render:**
- By tag closed, one tag open with > 4 rows (expanded, then "Show less" under the finger), 8 tags with "4 more" expanded, a Trip tag, a Maintenance tag with money, a tag in a plan, and a tag in a cross-month span.
- When at 9 and 10 timed days, a Sunday week start, the 12-hour clock, and Sleep present (absent from the grid).
- Balance with 1 area (absent), 2 areas and 6 areas.
- Compare: each of the three choices; no saved views; last year before `years.first`; a deleted view.
- A view at 360 and at 600 dp; the trend with ticks in a month (31 day columns) and in a year.
- The unprofiled page against the golden (footer row aside), and the guide's stage pinned.

**Matrix:** 1.0, 1.3, 2.0 (plus the AOSP 200 % curve) × light and dark × en, de, ro × 360 × 780 and 412 × 915, and 600 for Compare.

**Assert with `getRect`, ±1 dp:**
- tag header 66 at 1.0;
- 77.4 / 100.8 at 1.3;
- 104 / 140 / 176 at 2.0;
- the closed card 316 at 1.0;
- When card 202 / 234.3 / 285.3 (en 360), with the cell 8.89 × 16 and the row pitch 18 at 1.0;
- Balance rows 66 / 77.4 / 104;
- the footer with Compare 195 / 213 / 293;
- the period menu 452 and unchanged;
- no caption shrinks in a tag header;
- no `takeException`;
- one `Scrollable`;
- the ids and the spoken labels above.

**Not measured** (needs `qa screenshot` and an accessibility dump on `emulator-5556`):
- the built page;
- ink;
- TalkBack phrasing;
- real de / ro copy;
- ro diacritics;
- the compare menu opening above the footer near the bottom inset;
- a real 600 dp device (a tablet AVD or desktop).
