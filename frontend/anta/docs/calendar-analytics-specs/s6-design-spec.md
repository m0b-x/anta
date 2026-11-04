# S6 — Year in review and the period preset: the designer's spec (2026-11-04, Opus 5.5)

The renders are real: Roboto and MaterialIcons from a `git archive HEAD` snapshot (deleted after the run), pixel ratio 2. The current page is HEAD's `ReportBand` + `ReportBody` folded by the real builder over a full-year fixture: 2025 seen from 30 Oct 2026; six categories (Gym tracked Tue/Thu with five missed days, Morning run tracked Sat, Work weekdays 8 h, Friends ten one-offs, Travel with Cluj (3 days) and Sibiu (6 days), Car two services); two weekly goals and one gap goal; Balance with last year. The proposed cards are built in the scratch test from HEAD primitives: `FormRowGroup`, `FormSectionLabel`, `FormActionRow.disclosure`, `ReportTotalsCard`, `EventAvatar` and `FormGlyph`. The row is a scratch copy of `FormMeterRow` carrying S4's `captionLines` / `compactLeading` / `labelTrailing` and the two fields below; the strip painter is a scratch painter that follows this spec. The period menu is HEAD's `showFormMenu`, with the eleventh row added. The strings are my drafts, measured in en / de / ro. Matrix: light and dark; 1.0, 1.3 and 2.0 linear; en / de / ro; 360 × 780 and 412 × 915; the past year (2025) and the current year (2026, Nov–Dec still ahead). Renders, crops and `measurements.txt` are in `…\scratchpad\s6_renders\`. Tolerance is ±1 dp unless a test pins a value. S4's and S5's §1–§2 apply unchanged (slivers, labels, row shapes, glyph rules, template lines, the ramp, the tick); this spec extends them.

## 1. Diagnosis

- **The year page today reads as a long month** (`current_light_1.0_en.png`). Order: band "2025 · 426 events · 5 missed", Totals, Categories (Work 261 · 2088 h with "257 more", Gym, Morning run, Friends, Travel, Car), Over time with 12 month columns and the J F M … D axis, Missed, footer. Nothing on it answers the questions a year review asks: when did it peak, how long did a streak run, when did a thing start and stop. Nothing is broken; the cards are simply missing.
- **"Last year" is the missing preset.** The menu has This year but no Last year, although Last week and Last month exist (`report_period_choice.dart`). With an eleventh row the menu is 496 dp. It opens under the title and fits without scrolling in every cell: top 104 / bottom 600 at en 1.0, 118–614 at 1.3, 154–650 at en 2.0, 154–706 at de 2.0, where two labels wrap (`crop_menus.png`). It does not flip side, so S5 A's 620 dp problem does not recur.
- **Goals met would repeat the Goals card.** On a past year, S4's Goals card already reads "41 of 52 weeks met" (S4 F) with a streak. A separate Goals met card would show the same sentence a second time below Totals, which S4 H forbids. On the current year, S4 reads this week's pace, and the year's tally is what is missing.
- **A Firsts and lasts card would repeat the Months card's names.** It is one 62 dp row per category under the same six names that head the strips. That costs 6 × 62 + label ≈ 430 dp at 1.0 and ≈ 620 at 2.0, for one line of dates. Those dates are the strip's two ends: they read best as the strip row's caption (`crop_year_1.0_both.png`).
- **"First 2 Jan · last 30 Dec" wraps at 2.0; the range "Jan 2 – Dec 30" does not.** Tested both. The worded form went to two caption lines in every locale at 2.0: the strip row was 152 dp and the card 966. The range form stays on one line: 116 dp rows, a 750 dp card (`crop_records_months_20_en.png`).
- **By area would duplicate Balance.** S5's Balance card already shows hours by life area for every span, the year included. A second "By area" card in the year block would be the same rows twice. What the year adds is last year's value, and S5 K's tick idiom carries it onto the meter (`crop_balance_1.0.png`).
- **Top tags is S5's By tag card over the year.** It is unchanged and already in the order. Its "last seen" fact takes S5's cross-month form ("last 24 Oct").
- **Records rows on `FormPickerRow` cut at 2.0.** With `singleLine` and a one-line caption, "Most social month", "Geselligster Mo…" and "Höchste Ausgab…" were cut, along with five captions at de 2.0 and eight strings at ro 2.0 (`measurements.txt`, first run). On `FormMeterRow` with no meter, S4's compact leading (22 dp glyph from 1.6), a two-line label and a reserved two-line caption from 1.6, nothing is cut in any cell (`crop_records_20_ro.png`). That is also Balance's shape: a glyph in the 40 box, read-only.
- **A month strip of 12 tiles fits the text column at every width.** The pitch is 20.67 dp at 360 / 1.0, 22.17 at 2.0 (compact leading), and 25.0 / 26.5 at 412. Twelve narrow month names fit their columns at 1.0 and 1.3. At 2.0 the widest ("M", 22.9 dp) exceeds the pitch, so the axis thins to every second month (J M M J S N), the When card's rule.
- **The S5 ramp reads on a strip** in both themes (`crop_year_1.0_both.png`). Re-validated with dataviz's `validateOrdinal`: PASS. Step 1 against `rowGroup` is 2.18 / 3.46:1; step 1 against the empty tile is 1.77 / 2.61:1. A steady routine saturates (Gym is mostly step 4, July and August step 3), which is the honest picture under linear steps (S5 D). Sparse categories read as single dark tiles (Travel: May and September).
- **The current year needs a "not yet" tile.** November and December in 2026 are neither zero nor data. A 1 dp `outlineVariant` outline with no fill reads as ahead in both themes (`crop_months_2026.png`): 1.62 / 1.74:1 against the ground, against 1.23 / 1.33 for the zero tile's `rowDivider` fill.

## 2. The spec

### 2.1 When the year block draws, and the body order

- **Whole year.** `report.year != null`. The model sets it when the span runs exactly 1 Jan – 31 Dec of one year, whatever the period type: This year, Last year, a paged year, or a Custom range equal to one. It also requires tense ≠ future. A plan year draws no year card (A).
- **Order.** Goals → Insights → Due soon → Totals + caption → **[Records → Months]** → Categories → By tag → Over time → When → Balance → Missed → Ahead → footer. Each year card is S4's `[SizedBox(groupGap 18), FormSectionLabel, SliverToBoxAdapter(RepaintBoundary(card))]`, placed after the Totals caption.
- **Absent without content.** Records is absent with no record. Months is absent with no category kept in the year.
- **Not a year span.** No sliver is inserted. Every month and week page, the October golden and the guide's stage stay pixel-identical.
- **On a year span the other cards are S4/S5's,** with two year readings:
  - the Goals card's year caption (§2.4);
  - Balance's last-year tick, which applies to any span with Compare: Same period last year (§2.5).

### 2.2 Records card (`ReportRecordsCard`, new file `lib/widgets/report_year_cards.dart`)

| Element | Proposed |
|---|---|
| Label | `FormSectionLabel(reportSectionRecords)` "Records" |
| Rows | `FormMeterRow` with `fraction: null` (no meter) and `onTap: null` (read rows). `FormRowGroup(trailingGap: false)`. In the model's order, first `ReportMetrics.yearRecordRows` (6) |
| Leading | `FormGlyph(kind icon, color: onSurfaceVariant)` centred in the 40 box. From `RowMetrics.compactLeadingTextScale` (1.6): S4's `compactLeading` = the same glyph in a 22 box, divider indent 52 (otherwise 70) |
| Label | the record's name, 15 / 20 w500 `onSurface`, maxLines 2 with ellipsis. The names are constants, so line count changes by locale and scale only |
| Caption | "{subject} · {value}", the caption role. S4's `captionLines` = **1 below 1.6, 2 from 1.6** (`ReportMetrics.yearRecordCaptionLinesCompact`), ellipsis past it. Content is centred in the reserved height (S4 D). Counts are bound to their words with a no-break space (S4 W) |
| "n more ▾" | `FormActionRow.disclosure(expand_more_rounded, reportGroupMore(n), expanded: false)`. It expands in place, and "Show less ▴" folds back with §4.8 S's compensation (S4's Due soon pattern). The fold state is one more `ReportGroupFolds` flag, kept for the visit |
| Semantics | one node per row, not a button. Label `reportRecordSpoken`: "Busiest month: June, 31 events". Id per kind (§2.7) |

**Kinds, in this order** (the model's; a kind is absent when its source is):

| Kind | Glyph | Name (en) | Subject | Value | Source |
|---|---|---|---|---|---|
| busiest month | `calendar_view_month_rounded` | Busiest month | `DateFormat.MMMM` | `reportEventCount` "31 events" | kept occurrences per month |
| busiest week | `view_week_rounded` | Busiest week | the week's span as the band writes it ("Jun 16 – 22") | `reportEventCount` | weeks on the week start whose start lies in the year |
| most social month | `people_rounded` | Most social month | `MMMM` | `reportTagCount(kind: social)` "6 evenings" | Social-kind categories only |
| biggest spend | `payments_rounded` | Biggest spend | `MMMM` | the ledger's display formatter, spent | categories with money |
| longest trip | `luggage_rounded` | Longest trip | the event's title | `reportTagDays` "6 days" | Trip-kind one-offs; days inside the year |
| longest streak (per tracked routine) | `done_all_rounded` | Longest streak | the event's title | `reportGoalStreak` "14 in a row" | `PresenceStats.longestStreak` over the year, ≥ `AnalyticsMetrics.recordStreakMin` (3), longest first |
| longest gap (per gap-target category) | `hourglass_empty_rounded` | Longest gap | the category's name | `reportTagDays` "212 days" | days between two kept days inside the year, longest first |

- The glyph names the field, never the value.
- `people_rounded` and `payments_rounded` are `CalendarIcons.areaIcon`'s People and Money (S5 F).
- The roadmap's "longest period streak" is not a record: the Goals card carries it per goal (§2.4, B).

**Measured at 360**, with six rows plus "3 more":

| Scale | Row | Disclosure | Card (en / de) | Card (ro) |
|---|---|---|---|---|
| 1.0 | 62 (the two-line minimum) | 48 | 426 | 426 |
| 1.3 | 67.4 | 48 | 458.4 | 458.4 |
| 2.0 | 130 (two reserved caption lines) | 52 | 838 | 1,038 (five ro names wrap to 2 lines: rows 170) |

At 412 the card is 426 at 1.0 and 838 at de 2.0. No label and no caption is cut in any cell (`RenderParagraph.didExceedMaxLines` false throughout).

### 2.3 Months card (`ReportMonthsCard`, same file)

| Element | Proposed |
|---|---|
| Label | `FormSectionLabel(reportSectionMonths)` "Months" |
| Rows | an **axis row**, then one **strip row** per category in the Categories card's order. The first `ReportMetrics.maxCategoryRows` (7) show, then "n more ▾" / "Show less ▴" in place (`FormActionRow.disclosure`, its own `ReportGroupFolds` flag, kept for the visit) (C) |
| Strip row | `FormMeterRow(leading: EventAvatar(icon, colour), label: category name, caption: span, captionLines: template, fraction: null, chart: ReportYearStrip(...), onTap: → its Categories group (S4 G))`. S4's `compactLeading` applies from 1.6 |
| Caption (D) | the kept span, `reportYearSpan` "{first} – {last}", each day as `DateFormat.MMMd(locale)`: "Jan 2 – Dec 30", "2. Jan. – 30. Dez.", "2 ian. – 30 dec.". One kept day: the day alone. The current year: the last kept day so far. `captionLines` comes from the template "{28 + the locale's widest MMM} – {same}" (S4 D) |
| `chart` (new `FormMeterRow` field, E) | a widget in the meter's place, after `meterGap` (6), at the text column's width; `fraction` must be null when it is set |
| Strip geometry | pitch = (W + `ReportMetrics.columnGap` 2) / 12; tile = pitch − 2 wide × `ReportMetrics.yearTileHeight` (16) tall; radius `ReportMetrics.whenCellRadius` (2). One `CustomPainter` (`ReportYearStripPainter`), behind the row's own repaint |
| Tile fill | value 0 → `rowDivider` (S5's empty cell). value > 0 → `Color.lerp(rowGroup, primary, ReportMetrics.whenRamp[step − 1])` with step = `ceil(4 × value / peak).clamp(1, 4)`, where peak is the strip's own maximum (units differ per category). A month after today's month in the current year → no fill, a 1 dp `outlineVariant` stroke inset 0.5 (F). Today's month draws its value so far |
| Value | the month's **primary** in its own unit (`measures[id].primary`): minutes for Hours, cents for Money, a count for the rest. The model folds it (§2.8) |
| Axis row | a `FormDividedRow` (divider indent 70, or 52 from 1.6). Its text column sits at the strips' x (16 + 40 + 14, or 16 + 22 + 14 from 1.6), end 12. Vertical padding `ReportMetrics.yearAxisPadding` (6). One caption line (13 / 18 `onSurfaceVariant`), each name centred on its tile. Names follow the trend's rule: `DateFormat.MMM` when every name fits pitch − `axisLabelMinGap` (4), else `MMMMM`; then every step-th month, with the smallest step in `ReportMetrics.yearAxisSteps` [1, 2, 3] where step × pitch ≥ widest + 4. `ExcludeSemantics` |
| Semantics | the strip row is one node, a button: "Gym, from 2 January to 30 December. By month: January 9, February 8, …, December 8." (`reportYearMonthsSpoken`). Values carry the primary's spoken unit, as Categories' `groupSpoken` does ("31 hours"). Id `report-year-months-<categoryId>`. The tiles are `ExcludeSemantics`; the spoken list is the table twin |

**Measured** (geometry from `measurements.txt`):

| Width, scale | W | pitch | tile | axis | step | strip row | card (axis + 6) |
|---|---|---|---|---|---|---|---|
| 360, 1.0 (en/de/ro) | 246 | 20.67 | 18.67 × 16 | 30 | 1 | 78 | 504 |
| 360, 1.3 (en/de/ro) | 246 | 20.67 | 18.67 × 16 | 35.4 | 1 | 89.4 | 577.8 |
| 360, 2.0 (en/de/ro) | 264 | 22.17 | 20.17 × 16 | 48 | 2 | 116 | 750 |
| 412, 1.0 | 298 | 25.0 | 23 × 16 | 30 | 1 | 78 | 504 |
| 412, 2.0 de | 316 | 26.5 | 24.5 × 16 | 48 | 2 | 116 | 750 |

- With 8 or more categories the card adds one strip row per category up to 7, then the disclosure (48 / 48 / 52).
- At 2.0 every locale's span caption stays on one line.

**Contrast** (tokens; ramp re-run through dataviz `validateOrdinal`, PASS in both themes):

| Theme | steps | vs `rowGroup` | step 1 vs empty | empty vs ground | ahead outline vs ground |
|---|---|---|---|---|---|
| light | `#B3A4D2 #9987C2 #7F6BB3 #6750A4` | 2.18 · 3.03 · 4.29 · 6.12 | 1.77 | 1.23 | 1.62 |
| dark | `#796E93 #9688B7 #B4A3DC #D0BCFF` | 3.46 · 5.05 · 7.15 · 9.56 | 2.61 | 1.33 | 1.74 |

The tiles are texture. The caption, the axis, the spoken list and the Categories rows carry the facts, which is S5's answer to the light step-1 WARN.

### 2.4 The Goals card on a whole year (S4's card, year reading)

| Element | S4 | On a whole-year span |
|---|---|---|
| Caption, periodic goal with a period shorter than the year | current: the period with today; past: "3 of 4 weeks met" | "41 of 52 weeks met · longest streak 11" (`reportGoalPeriodsMet` + new `reportGoalLongestStreak`). Met and the total count **closed** periods only; the current year's open period is in neither |
| Streak segment | "4 in a row" (the current run) | "longest streak 11", the longest run of met periods inside the year; absent at 0 |
| Meter | value / target | met / closed |
| State glyph | S4's table | unchanged: the current period's state in the current year, the last period's in a past year |
| Year-period goal, gap goal | — | S4's captions unchanged ("14 of 25 days · 11 left", "23 days · limit 14") |
| `captionLines` | S4 D | the template "88 of 88 weeks met · longest streak 88" with the goal's real period word |
| Spoken | S4 | "Gym, 41 of 52 weeks met, longest streak 11 weeks, met" |
| Id | `report-goal-<categoryId>` | unchanged |

**Measured** (two tally rows and one gap row):

| Scale | en | de | ro |
|---|---|---|---|
| 1.0 | 200 (66 + 66 + 66) | 236 (84 + 84 + 66) | 236 |
| 1.3 | 281 | 281 | 281 |
| 2.0 | 386 (140 + 140 + 104) | 458 (176 + 176 + 104) | 530 (212 + 212 + 104, 4 caption lines) |

The ro draft "41 din 52 de săptămâni atinse · cea mai lungă serie 11" is long: see the translator rule in §2.9.

### 2.5 Balance with last year (S5's card; the "By area" of §6.12)

| Element | S5 | With Compare: Same period last year (any span, the year included) |
|---|---|---|
| Rows | this span's areas, largest first | the union of both spans' areas, ordered by this span's minutes, then last span's |
| Meter scale | minutes / largest area | minutes / max over **both** spans (a tick never clips) |
| `marker` (new `FormMeterRow` field, E) | — | last span's share. A `FormMetrics.meterMarkerWidth` (2) × (meterHeight + 2 × `meterMarkerOverhang` 3) = 10 dp bar in `onSurfaceVariant`, centred on the meter, x clamped inside the track. Under it a `meterMarkerRing` (1) dp band in `rowGroup`. This is S5 K's tick turned upright; it overhangs into the meter gap and the bottom padding, so the row's height is unchanged |
| Caption | "38 h · 67 %" | "1,720 h · last year 1,650 h" (`reportBalanceLastYear` replaces the share). `captionLines` from the template "8,888 h · last year 8,888 h" (S4 D) |
| Spoken | "Work, 38 hours, 67 percent of the hours" | "Work, 1,720 hours, last year 1,650 hours" (`reportBalanceLastYearSpoken`) |
| Contrast | — | tick vs `rowGroup` 8.88 / 9.56. The tick vs `primary` is 1.45 / 1.00, so the ring is load-bearing in dark (S5 K) |

Measured: four rows take 267 dp at 1.0 (unchanged), 312.6 at ro 1.3, and 563 at de 2.0, where the template wraps to 2 lines and rows are 140 (419 without last year).

### 2.6 The period preset: Last year

| Element | Proposed |
|---|---|
| Enum | `ReportPeriodChoice.lastYear`, between `thisYear` and `last12Months`. `periodFor` = `step(OverviewPeriodChoice.thisYear, -1)`, the relative rows' rule. At the calendar's first year it is This year, and This year answers `checkedFor` first |
| Row | `FormMenuItem(label: reportPeriodLastYear "Last year", icon: Icons.today_rounded (This year's glyph, as the week and month rows share theirs), identifier: report-period-last-year)` |
| Kept period | the bloc's `_keptOf` maps `lastYear` → `thisYear`, as Last week / month map to their This rows: the report reopens on This year, and nothing new is persisted |
| Menu | 11 rows, 496 dp (452 today). Opens under the title at 104 (en 1.0, no status bar in the render); bottom 600 / 614 / 650 at en 1.0 / 1.3 / 2.0, 706 at de 2.0 (552 dp, "Letzte 12 Monate" and "Eigener Zeitraum…" wrap). Never scrolls and never flips at 360 × 780. With a 24 dp status bar the deepest is 730 |
| Band | unchanged: "2025", ◄ ► step years, Today returns to This year |

### 2.7 Ids

| Element | Id |
|---|---|
| Last year row | `report-period-last-year` (`SemanticsIds.reportPeriodLastYear`) |
| Record rows | `report-year-record-busiest-month`, `-busiest-week`, `-social-month`, `-money-month`, `-longest-trip`, `-streak-<eventId>`, `-gap-<categoryId>` |
| Records disclosure | `report-year-records-more` |
| Strip rows | `report-year-months-<categoryId>` |
| Months disclosure | `report-year-months-more` |
| Goals, Balance | S4's `report-goal-<categoryId>` and S5's `report-balance-<area>`, unchanged |

`report-year-area-*`, `report-year-firsts-*` and `report-year-goal-*` are not minted under the defaults. They belong to the alternatives in B, D and G.

`tool/qa/flows/calendar/` gains one flow: open the period menu, pick Last year, expand Records, tap a strip row, and land on its Categories group.

### 2.8 Model asks (to S2b-ii)

1. **`CalendarReport.year: ReportYear?`** — set only on a whole calendar year with tense ≠ future (§2.1). It is folded from the one 366-day fold; nothing new is scanned.
2. **`ReportYear`** holds:
   - `records: List<ReportRecord>` — every record, in §2.2's order; the page caps it;
   - `months: Map<String, List<int>>` — 12 values per category in its primary's unit, keyed like `categories`;
   - `spans: Map<String, (DateTime first, DateTime last)>` — kept days, to today;
   - `goalTallies: Map<String, ReportGoalTally(met, closed, longestStreak)>` — periodic goals shorter than a year.
3. **`ReportRecord`** holds:
   - `kind`: `busiestMonth · busiestWeek · socialMonth · moneyMonth · longestTrip · longestStreak · longestGap`;
   - `categoryId?` and `eventId?`;
   - `value` (int, in the kind's unit);
   - `start` (DateTime) and `end?`.

   Ties go to the earliest. The streak threshold is `AnalyticsMetrics.recordStreakMin` (3).
4. **`CalendarReport.balanceLastYear: Map<LifeArea, int>?`** — filled when Compare: Same period last year is chosen, from the same second fold S5's `ReportTrend.lastYear` reads.

### 2.9 New strings (en; de and ro are the implementer's, measured in drafts)

**Period preset**

| Key | en |
|---|---|
| `reportPeriodLastYear` | "Last year" |

**Section labels**

| Key | en |
|---|---|
| `reportSectionRecords` | "Records" |
| `reportSectionMonths` | "Months" |

**Record names**

| Key | en |
|---|---|
| `reportRecordBusiestMonth` | "Busiest month" |
| `reportRecordBusiestWeek` | "Busiest week" |
| `reportRecordSocialMonth` | "Most social month" |
| `reportRecordMoneyMonth` | "Biggest spend" |
| `reportRecordLongestTrip` | "Longest trip" |
| `reportRecordLongestStreak` | "Longest streak" |
| `reportRecordLongestGap` | "Longest gap" |

**Record captions and spoken labels**

| Key | en |
|---|---|
| `reportRecordCaption` | "{subject} · {value}" |
| `reportRecordSpoken` | "{record}: {subject}, {value}" |

**Months card**

| Key | en |
|---|---|
| `reportYearSpan` | "{first} – {last}" |
| `reportYearSpanSpoken` | "from {first} to {last}" (days as `DateFormat.MMMMd`) |
| `reportYearDaySpoken` | "on {day}" |
| `reportYearMonthsSpoken` | "{category}, {span}. By month: {months}." |
| `reportYearMonthValue` | "{month} {value}" |

**Goals and Balance**

| Key | en |
|---|---|
| `reportGoalLongestStreak` | "longest streak {count}" |
| `reportGoalLongestStreakSpoken` | "{period, select, day{longest streak {count, plural, =1{1 day} other{{count} days}}} week{longest streak {count, plural, =1{1 week} other{{count} weeks}}} month{longest streak {count, plural, =1{1 month} other{{count} months}}} other{longest streak {count}}}" |
| `reportBalanceLastYear` | "last year {hours}" |
| `reportBalanceLastYearSpoken` | "{area}, {hours}, last year {lastHours}" |

- Reused: `reportEventCount`, `reportTagCount`, `reportTagDays`, `reportGoalStreak`, `reportGoalPeriodsMet`, `reportGroupMore` / `Less` / `MoreSpoken` / `LessSpoken`, `reportSectionTotals`, the ledger formatter, and `DateFormat.MMMM` / `MMMd` / `MMM` / `MMMMM`.
- Counts are bound with a no-break space (S4 W).
- Translator rule: record names ≤ 18 characters (de drafts: "Stärkster Monat", "Stärkste Woche", "Geselligster Monat", "Höchste Ausgaben", "Längste Reise", "Längste Serie", "Längste Lücke"; ro drafts ran 19–24 and wrapped at 2.0, so prefer "Luna de vârf", "Săptămâna de vârf", "Serie maximă", "Pauză maximă", "Călătorie maximă", "Cheltuieli maxime", "Luna cea mai socială"). Keep `reportGoalLongestStreak` short in ro ("serie maximă {count}"): the draft took the goal row to 4 lines at 2.0.

### 2.10 Constants and files

| Constant | Value | Why |
|---|---|---|
| `ReportMetrics.yearRecordRows` | 6 | records before "n more" |
| `ReportMetrics.yearRecordCaptionLinesCompact` | 2 | the reserved caption lines from 1.6 |
| `ReportMetrics.yearTileHeight` | 16 | a strip tile's height, When's 1.0 cell height |
| `ReportMetrics.yearAxisPadding` | 6 | the axis row's top and bottom |
| `ReportMetrics.yearAxisSteps` | `[1, 2, 3]` | the axis thinning steps |
| `FormMetrics.meterMarkerWidth` | 2 | the marker's width |
| `FormMetrics.meterMarkerRing` | 1 | the ring around the marker |
| `FormMetrics.meterMarkerOverhang` | 3 | how far the marker overhangs the meter |
| `AnalyticsMetrics.recordStreakMin` | 3 | the shortest streak that counts as a record |

- **Reused constants:** `columnGap` 2, `whenCellRadius` 2, `whenRamp`, `axisLabelMinGap` 4, `maxCategoryRows` 7, `groupGap`, `meterGap`, `compactLeadingTextScale`.
- **`form_rows.dart`:** `FormMeterRow` gains `chart` and `marker` (additive; the defaults keep every pin). `form_rows_test` gains these cases:
  - `chart` takes the meter's place at the text width;
  - `marker` keeps the row height and stays inside the track at 0 and 1;
  - `fraction` and `chart` together assert.
- **`report_year_cards.dart`** (new): `ReportRecordsCard`, `ReportMonthsCard`, `_MonthAxisRow` and `ReportYearStripPainter`. Its suite re-measures the ramp's step 1 against `rowGroup` (≥ 2:1) and against the empty tile, in both schemes. This mirrors `month_dot_matrix_test`'s contrast pins, which §12.1 names.
- **Elsewhere:**
  - `report_body.dart` inserts the slivers after the Totals caption;
  - `report_period_choice.dart` gets the enum value;
  - `calendar_report_page.dart` gets the icon and id;
  - `calendar_report_bloc.dart` maps `_keptOf`;
  - `ReportBand.choiceLabel` gets the label;
  - `ReportLabels` gets `recordCaption`, `recordSpoken`, `yearSpan`, `yearSpanTemplate`, `yearMonthsSpoken`, `goalYearCaption`, `goalYearTemplate` and `balanceLastYear`, and stays free of widgets.
- No new primitive.

## 3. What stays, and why

- **The period menu's ten rows, their order, ids and glyphs.** The eleventh row is inserted, so nothing moves above This year.
- **S4 and S5 geometry unchanged:**
  - Totals tiles (98 / 118 / 168) and their column rule;
  - Categories header 66 / 77.4 / 104 and dated rows 62 / 67 / 94;
  - Over time (its 12-month axis is the Months axis's precedent);
  - When, By tag, Missed, Ahead, the footer with Compare, the band.
- **Unprofiled and non-year identity.** Month and week pages insert nothing, so the October golden and the guide's stage stay pinned. A year page gains Records and Months on any calendar, profiled or not, as decision N intends.
- **S4's Goals card stays the one place goals are read.** On a year it reads the year. Firsts and lasts live on the strips, and By area is Balance. That is two new cards instead of five, with no fact said twice.

## 4. Risks

- **Height.**
  - At 360 en 1.0 the year block adds ≈ 1,034 dp: Records 426 + Months 504 + two labels and gaps.
  - At 2.0 it adds 838 + 750 + 2 × (18 + label) ≈ 1,700 dp in en / de, and ≈ 1,900 in ro with the drafts.
  - It sits below Totals, so the first screen is unchanged: on a goals calendar at 360 × 780, the Records label starts near y 620.
  - The page is long on a year by nature. The owner should see it on a device.
- **Refold.** The year cards change row count when a refold adds or removes a record or a strip (a streak reaching 3, a category's first kept day). Rows never change height at runtime: the lines come from templates and reserved lines. S4 R anchors only on the Totals label, so a reader below Months would see the rows under them move. Decision H extends R.
- **Text scale.** The axis thins to every second month at 2.0, and ro record names wrap to two lines. Both are accepted; the spoken labels carry the facts. Under the AOSP 200 % curve the caption is ~26 px against linear 2.0's 26: no change expected, but not rendered.
- **German and Romanian** are drafts. Line counts follow the shipped words at runtime; see the translator rules in §2.9.
- **Dark.** All values are tokens and lerps of tokens. The tick's ring is load-bearing (1.00:1 without it). The ahead outline (1.74:1) and the zero tile (1.33:1) are deliberately faint non-data.
- **Semantics.** The months list is twelve items per strip; it is complete but long under TalkBack. Not heard on a device.
- **Keyboard:** not involved. The page has no field.
- **Model.** Asks 1–4 are prerequisites. `PresenceStats.longestStreak` is per event, so "per routine" means per tracked event.

## 5. Decisions taken by default (each reversible)

- **A. The year block draws on any span that is exactly one calendar year, past or current, never in a plan.** *Alt:* past years only (the current year's strips show "ahead" tiles).
- **B. No Goals met card: on a year, S4's Goals card reads the year's tally ("41 of 52 weeks met · longest streak 11", meter met / closed).** A separate card repeated S4 F on past years. *Alt:* a Goals met card after Months, one `FormMeterRow` per periodic goal (avatar, name, the same caption and meter), ids `report-year-goal-<categoryId>`, with the Goals card keeping S4's reading.
- **C. Months shows the Categories card's first 7, then "n more ▾" in place.** *Alt:* "n more categories ›" opening the More categories sheet (that sheet has no strips).
- **D. Firsts and lasts is the strip row's caption, as a range "Jan 2 – Dec 30".** *Alt 1:* the worded "First 2 Jan · last 30 Dec" on the strip: 152 dp rows and a 966 dp card at 2.0. *Alt 2:* its own card of `FormPickerRow`s (avatar, name, "First Jan 2 · last Dec 30"), 62 / 67 / 94, ids `report-year-firsts-<categoryId>`, about +430 dp at 1.0.
- **E. Two additive `FormMeterRow` fields, `chart` and `marker`.** This is not a new primitive. *Alt:* a report-only row widget (it would copy the row's geometry).
- **F. Strips use S5's `primary` ramp with linear steps per strip; empty months are `rowDivider`; months still ahead are a hollow `outlineVariant` outline.** *Alt:* the category's colour (unvalidated per palette entry; pale built-ins such as `0xFFFFA000` would need `MonthDotMatrix`'s hairline rule).
- **G. By area is S5's Balance, with last year as an upright tick and "· last year 1,650 h" replacing the share.** It applies to any span with Compare: last year. *Alt:* a year-only By area card in the year block with ids `report-year-area-<area>`, Balance absent on a year.
- **H. S4 R's anchor becomes the nearest section label above the viewport's top** (Totals, Records, Months, Categories…), so a year refold never moves what is under the finger. *Alt:* S4's Totals anchor only.
- **I. Records are read rows (no tap).** *Alt:* busiest month / week opening that month or week's report.
- **J. Records cap at 6 with "n more ▾" in place; streak and gap records are per event / category, longest first, a streak only from 3.** *Alt:* the four `groupPreviewRows`.
- **K. The record row's label is the record's name; the caption leads with its subject.** *Alt:* the subject as the label ("June" / "Busiest month · 31 events"). That puts the value first, but the label would change at runtime.
- **L. Record glyphs** as in §2.2 (`done_all` for a streak, `hourglass_empty` for a gap, `luggage` for a trip). *Alt:* `local_fire_department` for a streak (gamified; withheld, per "pace, not scolding").
- **M. Last year sits after This year, with This year's glyph, and reopens as This year.** No Next year row: a plan year has no year cards. *Alt:* also Next year.
- **N. The axis row is at the top of the Months card**, the month grid's weekday-header precedent. *Alt:* under the last strip, the trend's x-axis position.

## 6. For the design-reviewer, after S6

**States to render:**
- Last year and This year (with November–December ahead); a Custom range equal to a year (cards drawn); a 366-day Custom range that is not one year (no cards); a plan year (no cards).
- Records with 1 row, 6 rows, and 9 rows (collapsed, expanded, then "Show less" under the finger).
- Months with 1, 7 and 9 categories, one category with a single kept day, a Money primary, and an Hours primary.
- The Goals card on a past year and on the current year, plus a yearly and a gap goal.
- Balance with and without Compare: last year, with an area present only last year.
- The menu with Last year checked, and at the calendar's first year.

**Matrix:** 1.0, 1.3, 2.0 (plus the AOSP 200 % curve) × light and dark × en, de, ro × 360 × 780 and 412 × 915.

**Assert with `getRect`, ±1 dp:**
- the menu is 496 dp at en 1.0, never scrolls, opens under the title; ten rows' ids unchanged;
- Records: row 62 / 67.4 / 130; disclosure 48 / 48 / 52; card 426 / 458.4 / 838 (en, de), 1,038 (ro drafts);
- Months: axis 30 / 35.4 / 48; strip row 78 / 89.4 / 116; card with 6 strips 504 / 577.8 / 750; tile 18.67 × 16 at 360 1.0, 20.17 × 16 at 2.0, 23 × 16 at 412 1.0; axis step 1 / 1 / 2;
- Goals year rows: 66 / 84 at 1.0, 100.8 at 1.3, 140 / 176 at 2.0;
- Balance with last year: 267 at 1.0, 563 at de 2.0;
- no `takeException`, no `didExceedMaxLines` in a record row, one `Scrollable`;
- the ids and spoken labels above; the month and week pages pixel-identical to their goldens; the guide's stage pinned.

**Not measured** (needs `qa screenshot` and an accessibility dump on `emulator-5556`):
- the built page;
- the menu with a real status bar and the deepest row near the 3-button bar at de 2.0;
- ink on the strip rows;
- TalkBack's reading of the twelve-month list;
- real de / ro copy, ro diacritics;
- the extended refold anchor's timing.
