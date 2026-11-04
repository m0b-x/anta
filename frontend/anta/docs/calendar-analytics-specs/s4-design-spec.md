# S4 — report cards I: the designer's spec (2026-11-04, Opus 5.5)

The renders are real: they were made with Roboto and MaterialIcons from a `git archive HEAD` snapshot, because the main tree did not compile while it was being edited (`_lookahead` missing in `calendar_report_service.dart`, and `int?` → `int` at `calendar_report_builder.dart:605`). The current page is HEAD's real `ReportBand` + `ReportBody` on the `report_body_test` October fixture, with a missed one-off added to Missed the way S2a folds it. The proposed cards are the real primitives (`FormMeterRow`'s geometry, `FormPickerRow`, `FormActionRow.disclosure`, `FormRowGroup`, `FormSectionLabel`, `FormCaption`, `ReportTotalsCard`, `AgendaPeriodNav`). The new strings are drafts I wrote, measured in en/de/ro.

Matrix: light and dark; 1.0, 1.3 and 2.0 linear; en, de and ro; 360 × 780 and 412 × 915. Renders and `measurements.txt` are in `…\dc8c4538-…\s4_renders\`. Tolerance is ±1 dp unless a test pins a value.

## 1. Diagnosis

- **The current page reads right and stays as it is** (`current_*.png`). The order is bar, band, Totals, Categories, Over time, Missed, then the footer. Measured: nav 52 / 64 / 146; Totals 197 (four tiles) / 475 de 1.3 / 675 at 2.0; header 66 / 77.4 / 104; child rows 62 / 67.4 / 94. These match §4.8.
- **A missed one-off beside a routine reads right** (`crop_missed_light.png`). The "Other · 1 missed" group holds the "Dentist · Fri 9 · 09:00 · 30 min" row with the same presence button as Gym's missed day. Nothing to change.
- **FormMeterRow's caption cannot carry a goal's read-back.** It is a one-line slot that shrinks to fit. "31 h of 40 · 9 h left this week" needs 170 dp against 181 dp beside a trailing cluster at 360 en 1.0, and wraps at 1.3. §10 requires "wraps to a second line at 2.0 and never clips". A caption that wraps by value would make the first card change height on a refold.
- **A trailing streak slot breaks names mid-word.** With a reserved "× 88" slot plus the glyph beside the label, the built-in "Measurement" (186 dp) breaks at en 1.3 (label room 173 dp). At de 2.0, "Fitnessstu|dio" and "Lebensmitt|el" broke (`crop_goals_de20.png`, first pass). This rule protects names from mid-word breaks (`compactLeadingTextScale`'s own doc).
- **Insights repeat the goal rows.** "Friends · 23 days since the last, the limit is 14" sits right under "Friends · 23 days · limit 14" (`crop_top_dark.png`). Decision L of the record says "never a sentence a tile already says".
- **The glyph-row shape spreads insights apart.** It puts a sentence caption below the pair: 76 dp rows with a loose gap. The leading-box shape gives 62 dp with tight lines (`crop_ins_due_light.png` before / `crop_top_dark.png` after).
- **The lead's band subtitle is too long.** "31 events · 2 goals on pace · 1 behind" fits 0.92 at 360 en 1.0, 0.47 at en 2.0 and 0.35 at ro 2.0. With "3 missed" kept it is 0.71 / 0.37 / 0.30. Today's subtitle fits 1.00 / 0.86.
- **"incl. 6 h counted as" cannot sit in the Hours tile.** "+1.2 h · incl. 6 h counted as" is 161 dp against a 131.5 dp half tile at 360 en 1.0, and the tile's detail slot is one line with an ellipsis.
- **The model does not hold the rows "n more ▾" would show.** `CalendarReport.dueSoon` is capped at 6 and `dueSoonMore` is only a count.
- **The model has no "profiled" flag.** Auto resolves a primary for every category: unprofiled Gym gets Attendance, a timed one gets Hours. The header cannot "lead with the primary" for every category without changing the unprofiled page.
- **Working days apply to every report.** `workingDays` is resolved for every span, so an ungated caption segment would change every month report. Walkthrough 1 and walkthrough 7 ("nothing changes but A1") forbid that.

## 2. The spec

### 2.1 Body order and slivers (`ReportBody`)

Past and current tense: [GOALS label → Goals card] → 18 → [INSIGHTS → card] → 18 → [DUE SOON → card] → 18 → TOTALS → Totals card → caption → … the rest as today.

- Each new card is `[SizedBox(groupGap 18) unless first, FormSectionLabel, SliverToBoxAdapter(RepaintBoundary(card))]`. Each card is a `FormRowGroup(trailingGap: false)` of rows in `FormRowShell` corners, the footer's pattern.
- The Totals label gets a leading `groupGap` only when a card stands above it. Unprofiled, nothing is inserted: the sliver list and the first pixel match today's.
- Every card is absent without content (H).
- Future tense: Goals (with the future states), then Due soon (Expiries and Bills only, §6.8), then Totals. No Insights card in a plan.
- Section labels are plain `FormSectionLabel`, with no `headingLevel` (W of §4.8).

### 2.2 Goals card — one row per `ReportGoal`, in the model's order

| Element | Proposed |
|---|---|
| Primitive | `FormMeterRow` plus three additive fields in `form_rows.dart`; defaults keep today's behaviour (decision A) |
| Leading | `EventAvatar(category icon, category colour)` in the 40 box. From `RowMetrics.compactLeadingTextScale` (1.6) up: new field `compactLeading` = `FormGlyph(category icon, color: category colour)` in a `FormMetrics.glyphSize` (22) box, divider indent `FormMetrics.dividerIndentGlyph` (52); otherwise `dividerIndentTitle` (70) |
| Label line | category name, 15 / 20 w500 `onSurface`, `Expanded`, maxLines 2 with ellipsis. Then new field `labelTrailing`: `FormMetrics.gap` (14) followed by the **state glyph**, `FormTrailingGlyph` (20) centred in a `scale(labelLineHeight)` box |
| Caption | the caption role, 13 / 18 `onSurfaceVariant`, full text width. New field `captionLines`: null keeps today's one-line shrink slot; a number gives a wrapping `Text(maxLines: n, ellipsis)` |
| Row min height | `twoLinePadding.vertical + scale(20) + scale(18) × captionLines + meterGap 6 + meterHeight 4`, content centred vertically: a template's spare line reads as padding, never as a hole (`crop_goals_light.png`) |
| Meter | `fraction` = value / target clamped to 0–1. Gap goals use `daysSince / limit` (0 when null). A past multi-period span uses met periods / closed periods. Fill = category colour in every state (C); track `rowDivider` |
| Streak | the caption's last segment, "4 in a row" (`reportGoalStreak`), when `streak > 0` and the kind is periodic (B) |
| Tap | Categories group (G) |
| Semantics | one node, `button` when tappable, `identifier: report-goal-<categoryId>`. Label: "{category}, {caption with ", " for " · "}, {state word}, {streak spoken}", e.g. "Gym, 2 of 3, one more by Sunday, on pace, 4 weeks in a row" |

**`captionLines` is decided by templates, never by the value (D).** Lay out every state sentence the goal's kind can show, with every figure written as 8s at the target's digit count, plus one digit for the met / over states. Hours carry the locale's decimal ("88.8 h"); a streak segment is "88 in a row"; the period-end word is the real one, which is constant per goal: the week-start's last weekday, "30 Nov" for a month, "31 Dec" for a year. Lines = the most any of them wraps to at the caption width. Measure with `DefaultTextStyle.of(context).style` merged with the caption style, as `ReportTotalsCard._measureFit` does. A bare `TextStyle` measures in the box font: my first pass did and got every width wrong ×2. Cache the result per (width, scaler, locale, goal).

**Read-back (en; counts bound to their words with a no-break space, W):**

| Kind | Current period state | Caption |
|---|---|---|
| at least | onPace / behind / notDue | "2 of 3 · one more by Sunday" (`reportOfTotal` + `reportGoalMoreBy`); a day period: "one more today" |
| at least | met (period not over) | "3 of 3 · done for the week" (`reportGoalDone`, select day / week / month / year) |
| at most (any measure) | onPace / behind / notDue | "31 h of 40 · 9 h left"; "… left this week" only when the span's unit differs from the goal's period (E) |
| at most / budget | over | "44 h of 40 · 4 h over" / "1,340 of 1,200 · 140 over" |
| max gap | within / due / overdue | "23 days · limit 14" (`reportGoalGap`); "None yet · limit 14" when `daysSince` is null |
| any | a closed single period (past span) | "3 of 3 · Met" / "2 of 3 · Missed" for at least; "38 h of 40 · Within" / "44 h of 40 · Over" for at most / budget (one word, K) |
| any | a past span of several periods | "3 of 4 weeks met" (`reportGoalPeriodsMet`) (F) |
| any | future (plan) | "2 of 3 planned" (`reportGoalPlanned`) |

- In a current span holding several periods, the caption reads the period that contains today.
- Hours use `ReportLabels.hours` (B of §4.8). Money uses the ledger's display formatter. Count, attendance and tasks figures are bare counts.

**State glyphs** (never colour alone; the shape and the spoken word carry the state):

| States | Icon | Colour role | Spoken (`reportGoalState*`) |
|---|---|---|---|
| met | `Icons.check_circle_rounded` | `primary` | "met" |
| onPace, gap within | `Icons.timelapse_rounded` | `onSurfaceVariant` | "on pace" / "within the limit" |
| behind, gap due | `Icons.hourglass_bottom_rounded` | `onSurfaceVariant` | "behind" / "due soon" |
| over, missed, gap overdue | `Icons.error_outline_rounded` | `onSurface` | "over" / "missed" / "past the limit" |
| notDue, future | `Icons.radio_button_unchecked_rounded` | `onSurfaceVariant` | "not started" / "planned" |

Contrast on `rowGroup`, from §4.8's token measurements: `primary` 6.12 / 9.56, `onSurfaceVariant` 8.88 / 9.56, `onSurface` above both. Every state indicator is ≥ 3:1.

Measured goal rows at 360, rows with 1 / 2 / 3 caption lines:

| Scale | 1 line | 2 lines | 3 lines |
|---|---|---|---|
| 1.0 | 66 | 84 | — |
| 1.3 | 77.4 | 100.8 | — |
| 2.0 (compact leading) | 104 | 140 | 176 |

- Five goals: 370 dp en 1.0 (four rows of 66, the budget row 84 because its template is 248.8 dp against 246 dp); 424 de 1.0; 502.6 en / de 1.3; 722 en / 830 de / 830 ro 2.0. At 412: 352 dp at 1.0, 686 at de 2.0.
- No name broke mid-word: every built-in category word fits the label room at every cell (212 dp at 1.0 and 1.3, 230 dp at 2.0 compact).
- No `takeException` in any cell.

### 2.3 Insights card — top `AnalyticsMetrics.insightsOnPage` (3) after the page filter (H)

| Element | Proposed |
|---|---|
| Primitive | `FormPickerRow(leading: SizedBox.square(rowLeadingSize, Center(FormGlyph(icon, color))), label: subject, caption: detail, captionMaxLines: ReportMetrics.insightCaptionMaxLines (new, 4), singleLine: true, showChevron: false, onTap, semanticsLabel, identifier)`. This is the routine aggregate's shape, with text at x 70 like every report row (I) |
| Subject / detail | the model supplies both: subject = category name, "#tag" or the rule's noun ("Bills", "Next trip"); detail = the sentence without the subject ("23 days since the last, the limit is 14"). S2b's `ReportInsight` gains `subject` and `detail`; the page never splits a string |
| Severity glyph | 3 `Icons.error_outline_rounded` `onSurface` "Needs attention"; 2 `Icons.flag_outlined` `onSurfaceVariant` "Worth a look"; 1 `Icons.lightbulb_outline_rounded` `onSurfaceVariant` "Worth knowing"; 0 `Icons.info_outline_rounded` `onSurfaceVariant` "For information" (J) |
| Tap | to the target: a category group as in G; a card → scroll its label to the top; the overview's list on the days → `onShowAsList` with that span and category |
| Semantics | one node, button, "{severity word}. {subject}, {detail}", `identifier: report-insight-<n>` (n = 0, 1, 2 by rank; ranking is deterministic, §6.7) |
| Heights | 62 / 74 (1 / 2 caption lines) at 1.0; 67 / 90 at 1.3; 130 / 166 at 2.0. Height follows the sentence, so this card is anchored on refold (R) |

### 2.4 Due soon card — the model's order, first `AnalyticsMetrics.dueSoonRows` (6)

| Element | Proposed |
|---|---|
| Row | `FormPickerRow(leading: 40 box + FormGlyph(state icon), label: event title, caption: phrase, captionMaxLines: 1, singleLine: true, showChevron: false)` (K). 62 / 67 / 94 at every locale (measured), the dated rows' extents |
| Glyphs | overdue `Icons.error_outline_rounded` `onSurface`; due `Icons.hourglass_bottom_rounded` `onSurfaceVariant`; unmarked `Icons.radio_button_unchecked_rounded` `onSurface`; upcoming `Icons.schedule_rounded` `onSurfaceVariant` |
| Phrase (en, sentence case) | gap overdue "Overdue 32 days"; gap due "Due in 18 days"; Expiry ahead "Expires in 42 days"; Expiry passed "Expired 3 days ago"; unmarked "1 Nov · not marked"; upcoming "1 Dec · in 12 days". The day uses `DateFormat.MMMd` of the locale |
| "n more ▾" | `FormActionRow.disclosure(expand_more_rounded, reportGroupMore(n), expanded: false)` → expands in place; "Show less ▴" (`expand_less_rounded`, `reportGroupLess`) folds back with §4.8 S's scroll compensation through `onShrink` / `EndSlackSliver`. 48 / 48 / 52 |
| Fold state | per visit, as the groups' folds (`ReportGroupFolds` gains one flag) |
| Tap | the event's detail sheet through `EventSheetsFlow` on the row's `day`; a gap row on `day − limit`, its last kept day (M) |
| Semantics | row: button, "{title}, {phrase}", `report-due-<eventId>-<yyyy-MM-dd>`. Disclosure: `report-due-more`, expanded flag, `reportGroupMoreSpoken(n, l10n.reportSectionDueSoon)` / `reportGroupLessSpoken(…)` |

The phrase cuts at de / ro 2.0 ("seit 32 Tagen überf…" with my draft German), the accepted §4.8 risk for dated rows. Copy rule for the translators: the number comes first and the phrase stays ≤ 20 characters ("32 Tage überfällig").

### 2.5 Touches to the existing cards

| Element | Current | Proposed |
|---|---|---|
| Categories header caption (N) | "14 · 13.2 h · 2 missed" | Profiled categories only ("profiled" = effective kind ≠ custom or a measure set; new `ReportMeasures.profiled`): "{primary} · {count}[ · n missed]". count: today's facts unchanged; hours "31 h · 12"; events "6 events · 14"; attendance "8 of 10 attended · 12"; cancelled "3 cancelled · 8"; tasks "9 of 12 tasks · 5"; money "1,800 · 1" (spent; "+1,800" when only received); last seen "23 days ago · 4" / "today" / "yesterday"; lead time "booked 3 days ahead · 4"; timing "usually at 18:00 · 8"; days until "in 12 days · 2". Spoken: "Work, 31 hours, 12 events, 1 missed". Meter stays count over the card's largest count, so mixed units stay comparable. Geometry unchanged (66 / 77.4 / 104 measured) |
| Totals caption (O, P) | "To 30 October · against September 2026 · 2 skipped · 2 ahead" | appends "22 working days · 1 public holiday" (holidays omitted at 0) and "Hours incl. 6 h counted as" when `nominalMinutes > 0`. Measured 62 / 100 / 224 dp (3 / 5 / 12 lines) with every segment; it already wraps and sits below the card. In a plan the caption appears holding only the working-days segments |
| Hours tile | spoken "Hours, 8.5 hours, …" | appends ", including 6 hours counted as" (`reportCountedAsSpoken`); drawn tile unchanged |
| Band subtitle (Q) | "31 events · 3 missed" | with goals, current tense: "31 events · 2 of 3 goals on pace" (on pace = met + onPace + notDue + gap within); past: "31 events · 2 of 3 goals met"; replaces the missed segment; none in a plan. Drawn only when the template "888 events · N of N goals on pace" (N = goals.length) fits the subtitle box without shrinking below the 1.0 size (natural width ≤ box × scale); otherwise today's subtitle. Fits measured: en 1.0 1.00 (185.9 / 208), de 1.0 1.00 (207.5), en 1.3 0.86, en 2.0 0.56, de 2.0 0.50 — all kept. ro 1.0 0.79 and ro 2.0 0.39 fall back unless ro is translated shorter. `AgendaPeriodNav` gains two additive fields, `compactSubtitle` and `subtitleTemplate`; the nav owns the box, so it decides |
| Missed with one-offs (T) | as built | unchanged: no "not done" tail |

### 2.6 Refold anchoring (R, new; follows §4.8 S)

Insights and Due soon can change height on a refold, for example a presence mark in Missed clears an insight or an unmarked Bill. When the viewport's top is below the Totals label's old top:

1. Record the label's scroll offset before the refold.
2. Once the new report has laid out, `jumpTo(pixels + newOffset − oldOffset)`, clamped.

Nothing below Totals then moves under the finger. The Goals card needs no anchor: its row count comes from the profiles and its line counts from the templates.

### 2.7 Constants and files

- `ReportMetrics.insightCaptionMaxLines` = 4: the only new number. Every other value is an existing `FormMetrics` / `RowMetrics` / `AnalyticsMetrics` name.
- The template digit and the streak template go in `ReportMetrics` as plain values (`goalTemplateDigit = '8'`, `goalTemplateStreak = 88`).
- Widgets: `lib/widgets/report_analytics_cards.dart` holds `ReportGoalsCard`, `ReportInsightsCard` and `ReportDueSoonCard` (V).
- Words: in `ReportLabels` (`goalCaption`, `goalSpoken`, `goalTemplates`, `dueCaption`, `dueSpoken`, `insightSpoken`, plus the extended `subtitle`, `caption`, `groupFacts`, `groupSpoken` and `tileSemantics`). It stays free of widgets.
- `form_rows_test` gains these cases for `FormMeterRow`'s three fields:
  - `captionLines` wraps and keeps its minimum height;
  - `labelTrailing` keeps one node;
  - `compactLeading` takes over from 1.6 and moves the divider to 52;
  - the defaults are unchanged, so the existing pins hold.

### 2.8 Model asks (to S2a's builder and S2b)

1. `ReportMeasures.profiled`.
2. `dueSoon` holds every row; the page caps it and derives "n more" (L).
3. The service resolves `workingDays` / `publicHolidays` only for a calendar month or year whose scope holds a work, meeting or leave kind; the page draws them when > 0.
4. `ReportInsight` carries `ruleId`, `subject`, `detail`, `severity`, `categoryId?`, `tagKey?` and a target.

### 2.9 New strings (en; de and ro are the implementer's)

**Section labels**

| Key | en |
|---|---|
| `reportSectionGoals` | "Goals" |
| `reportSectionInsights` | "Insights" |
| `reportSectionDueSoon` | "Due soon" |

**Goals card**

| Key | en |
|---|---|
| `reportGoalMoreBy` | "{count, plural, =1{one more by {day}} other{{count} more by {day}}}" |
| `reportGoalMoreToday` | "{count, plural, =1{one more today} other{{count} more today}}" |
| `reportGoalDone` | "{period, select, day{done for today} week{done for the week} month{done for the month} year{done for the year} other{done}}" |
| `reportGoalLeft` | "{amount} left" |
| `reportGoalLeftIn` | "{amount} left {period, select, day{today} week{this week} month{this month} year{this year} other{}}" |
| `reportGoalOver` | "{amount} over" |
| `reportGoalMet` / `reportGoalMissed` / `reportGoalWithin` / `reportGoalOverWord` | "Met" / "Missed" / "Within" / "Over" |
| `reportGoalPeriodsMet` | "{met} of {total} {period, select, day{days} week{weeks} month{months} year{years} other{}} met" (plural-aware per ARB) |
| `reportGoalPlanned` | "{value} of {target} planned" |
| `reportGoalGap` | "{days, plural, one{1 day} other{{days} days}} · limit {limit}" |
| `reportGoalGapNone` | "None yet · limit {limit}" |
| `reportGoalStreak` | "{count} in a row" |
| `reportGoalStreakSpoken` | "{count} {period, select, …weeks…} in a row" |
| `reportGoalStateMet`, `…OnPace`, `…Behind`, `…Over`, `…Missed`, `…NotStarted`, `…Planned`, `…Within`, `…DueSoon`, `…PastLimit` | the spoken words above |

**Band subtitle**

| Key | en |
|---|---|
| `reportGoalsOnPace` | "{onPace} of {total, plural, one{1 goal} other{{total} goals}} on pace" |
| `reportGoalsMet` | "{met} of {total, plural, one{1 goal} other{{total} goals}} met" |

**Insights card**

| Key | en |
|---|---|
| `reportInsightAttention` | "Needs attention" |
| `reportInsightNotable` | "Worth a look" |
| `reportInsightObservation` | "Worth knowing" |
| `reportInsightInfo` | "For information" |

**Due soon card**

| Key | en |
|---|---|
| `reportDueOverdue` | "Overdue {count, plural, one{1 day} other{{count} days}}" |
| `reportDueIn` | "Due in {count, plural, one{1 day} other{{count} days}}" |
| `reportDueExpires` | "Expires in {…}" |
| `reportDueExpired` | "Expired {…} ago" |
| `reportDueUnmarked` | "{day} · not marked" |
| `reportDueUpcoming` | "{day} · in {…}" |

**Categories headers**

| Key | en |
|---|---|
| `reportLastSeenAgo` | "{count, plural, =0{today} =1{yesterday} other{{count} days ago}}" |
| `reportCancelledCount` | "{count, plural, one{1 cancelled} other{{count} cancelled}}" |
| `reportLeadTime` | "booked {count, plural, one{1 day} other{{count} days}} ahead" |
| `reportDaysUntil` | "{count, plural, =0{today} =1{tomorrow} other{in {count} days}}" |

**Totals**

| Key | en |
|---|---|
| `reportWorkingDays` | "{count, plural, one{1 working day} other{{count} working days}}" |
| `reportPublicHolidays` | "{count, plural, one{1 public holiday} other{{count} public holidays}}" |
| `reportCaptionCountedAs` | "Hours incl. {hours} counted as" |
| `reportCountedAsSpoken` | "including {hours} counted as" |

Reused as they are: `reportOfTotal`, `reportEventCount`, `reportAttendedOf`, `reportTasksOf`, `reportTrendUsualAt`, `reportGroupMore` / `Less` / `MoreSpoken` / `LessSpoken`, `dayListMissedCount`.

## 3. What stays, and why

- `ReportTotalsCard` geometry (98 / 118 / 168 tiles, the column rule) stays.
- The group header and child rows stay as they are: 66 / 77.4 / 104 and 62 / 67.4 / 94, measured. Only a profiled header's caption text changes.
- Also unchanged: `AgendaPeriodNav`'s heights and id pattern, the chart, Missed / Ahead / footer, the 0.35 fade outside Missed, and `EventAvatar`.
- `FormMeterRow` defaults stay, so the report's current pins stay green.
- An unprofiled calendar inserts no sliver and changes no string: no goals, insights or due rows; `profiled` false everywhere; working days not resolved; `nominalMinutes` 0. Its page is pixel-identical (the S4 golden pins it, at the guide's stage too).

## 4. Risks

- **First screen.** Five goals take 370 dp at 360 en 1.0, so Totals moves below the fold on a 780 dp phone when goals and insights exist. This is intended by the card order, but the owner should see it on a device.
- **2.0.** Goals 722–830 dp; Insights 410–446 dp; due phrases cut at de / ro 2.0 (semantics carry the full phrase). The 20 dp state glyphs do not scale with text: standard Material, but small beside 30 px names.
- **Band.** The goals summary falls back to today's subtitle in ro at 360 unless the translation is shorter. The fit is 0.50 at de 2.0, the floor of the rule.
- **German.** Drafts only: real de / ro may change the template line counts. The count is measured at runtime, so geometry follows the language, never the value.
- **Dark.** All roles are tokens. The meter tints keep §4.8's low-contrast cases (decorative; the words carry the numbers).
- **Semantics.** Not checked: TalkBack phrasing of the goal label, and whether "Worth a look" / "Worth knowing" read naturally.
- **Keyboard.** The page has no field, so the keyboard is not involved.
- **Refold.** The anchor in R is new code on the scroll path. Test both a mark from Missed and a due row's sheet returning.

## 5. Decisions taken by default (each reversible)

- **A.** Goal rows are `FormMeterRow` plus three additive fields (`captionLines`, `labelTrailing`, `compactLeading`). Not a new primitive.
- **B.** The streak is the caption's last segment, "4 in a row", not a trailing "× 4": a reserved slot broke "Measurement" at en 1.3 and German names at 2.0. *Alt:* trailing "× 4" below 1.6 only.
- **C.** The state glyph sits at the end of the label line. The meter is the category colour in every state. No `error` red anywhere: decision K's "pace, not scolding". *Alt:* `error` on over / overdue.
- **D.** Caption lines per row come from the widest state sentence written in 8s, never from the value. Content is centred in the minimum height.
- **E.** "this week" is said only when the span's unit differs from the goal's period.
- **F.** A current multi-period span reads the period with today; a past one reads "3 of 4 weeks met".
- **G.** A goal tap scrolls its Categories header to the top and opens it. Past the seven-group cap it opens the More categories sheet. With no group it is a read row with no tap.
- **H.** The page's Insights drop G1–G3 and D1–D4 when the Goals or Due soon card already shows that subject. The digest is unchanged. This amends walkthrough 2's "Insights drops G1 and shows G3". *Alt:* keep the duplicates.
- **I.** Insight rows use the leading-box glyph shape: subject label, detail caption of at most 4 lines. The model supplies `subject` and `detail`.
- **J.** Severity glyphs: `error_outline` / `flag_outlined` / `lightbulb_outline` / `info_outline`.
- **K.** Due rows use the routine-aggregate shape with a one-line phrase, cut at de / ro 2.0. *Alt:* two template-decided lines.
- **L.** "n more ▾" expands in place, which needs the model to hold every due row. *Alt:* open the overview list.
- **M.** A due row opens the detail sheet on its day; a gap row opens on its last kept day.
- **N.** The header leads with the primary for profiled categories only. The meter stays scaled by count.
- **O.** The counted-as footnote goes in the Totals caption ("Hours incl. 6 h counted as") and in the tile's spoken label.
- **P.** Working days show for a calendar month or year whose scope holds work, meeting or leave, also in a plan. *Alt:* every month and year (breaks walkthrough 1).
- **Q.** The band reads "31 events · 2 of 3 goals on pace" in place of the missed count, under a no-shrink-below-1.0 template rule. *Alt:* the lead's "· 2 goals on pace · 1 behind" appended.
- **R.** After a refold, the page is anchored on the Totals label.
- **S.** Ids: `report-goal-<categoryId>`, `report-insight-<n>`, `report-due-<eventId>-<yyyy-MM-dd>`, `report-due-more`.
- **T.** Missed one-offs are unchanged, with no "not done" tail.
- **U.** Labels are Goals · Insights · Due soon, with no `headingLevel`.
- **V.** One file for the three cards.
- **W.** Every count is bound to its word with a no-break space in the goal and due captions.
- **X.** The Insights card stays absent until S2b ships.

## 6. For the design-reviewer, after S4

**States to render:**
- Goals in every state: met, onPace, behind, over, closed Met / Missed / Within / Over, notDue, future, gap within / due / overdue / never.
- A weekly goal in a month view, and a 4-week past span.
- Streak 0 and > 0.
- Three insights; one; none.
- Due soon with 4 rows, with 8 rows (collapsed and expanded, then "Show less" under the finger), and in a plan.
- A profiled header for each primary.
- The Totals caption with working days and counted-as, in a plan and in a week (no working days).
- The band with goals in en / de / ro at 360, the fallback included.
- A refold from a Missed mark while scrolled past Due soon.
- The unprofiled page against the golden, and the guide's stage pinned.

**Matrix:** 1.0, 1.3, 2.0 (plus the AOSP 200 % curve) × light and dark × en, de, ro × 360 × 780 and 412 × 915.

**Assert with `getRect`, ±1 dp:**
- goal row 66 / 84 at 1.0, 77.4 / 100.8 at 1.3, 104 / 140 / 176 at 2.0;
- insight row 62 / 74, 67 / 90, 130 / 166;
- due row 62 / 67 / 94; due "n more" ≥ 48;
- header 66 / 77.4 / 104; Totals unchanged;
- no `takeException`; no category word broken mid-word;
- one `Scrollable`;
- the spoken labels and the ids above.

**Not measured:** the built page, ink and pressed states, TalkBack, real de / ro copy, ro diacritic coverage, the anchor's timing. These need a `qa screenshot` and an accessibility dump on `emulator-5556`.
