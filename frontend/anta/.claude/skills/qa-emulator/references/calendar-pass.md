# Calendar pass

Reference, not rules — moved verbatim from the qa-emulator SKILL.md on 2026-10-11. Read only the part the task needs.

## The calendar pass (2026-09-26)

One command is a device pass of the calendar, against a seed that puts every
calendar state around today:

```bash
./tool/qa/qa fleet pass calendar                                      # since 2026-10-23: 26 flows, a reseed and the prelude before each, sharded over the fleet — ≈ 4.5 min wall, one report
./tool/qa/qa pass calendar -d emulator-5556                           # the same on one device (≈ 10 min)
./tool/qa/qa pass calendar --only 03_dates -d emulator-5558           # one flow, reseeded, after the prelude
./tool/qa/qa pass --summary build/qa/pass/<dir>/report.json           # reprint the table of any report

./tool/qa/qa relaunch --fresh --seed tool/qa/fixtures/calendar.json   # the hand-driven way: ≈ 4 s on the owner's emulator; `qa fleet install --build` after a lib change
./tool/qa/qa flows calendar                                           # the old runner: one seed for all flows, the prelude once, no report
```

`tool/qa/flows/calendar/_suite.txt` names the fixture, `reseed=flow` and
`shard=yes`; `_prelude.txt` opens the calendar from the drawer (`id:nav-menu`
→ `id:drawer-calendar` → `id:calendar-add-event`) and ends with `tap
id:panel-mode-day --settle 2000` to ride out the bottom panel's mode restore
(an app race, `traps.md`); `_labels.txt` lists the seeded content the flows
may still target by text. Every flow starts on the calendar page and leaves
it anywhere — the next flow gets a fresh seed. `test/qa/flows_lint_test.dart`
keeps every control target an `id:`.

`tool/qa/fixtures/calendar.json` is written with **relative dates** —
`"startDateMs": "{{today-28}}"`, `"dayMs": "{{today+7}}"` — that the tool
resolves against the run's clock before pushing (`(63 placeholders
resolved)` in the push line); the resolved copy lands in
`build/qa/seed_resolved.json`, the fixture in the repo is never edited. It
seeds a weekly session with presence marks, a skipped day and a per-day
description, a daily walk carrying five alerts (the cap), six pinned dates,
a yearly birthday with a custom colour, a workdays event that assumes
absence, an ended one-time event, an event in a hidden category, a template,
a saved filter, a custom holiday, a suppressed German built-in (Christmas
Day on `{{today+60}}`, for the removed-holidays sheet), one custom colour
(#3F51B5, for the palette and the swatch menu), the German holiday profile
and Orthodox fasting. `test/qa/calendar_fixture_test.dart` pins that every
piece imports and occurs where the flows expect it. `--setting key=value` (repeatable)
overrides a settings key in the seed before it is pushed — `--setting
locale=de --setting theme_mode=dark` is the matrix at launch.

The flows live in `tool/qa/flows/calendar/*.txt`, one per checklist item
(open, new event, editor sub-sheets and the dirty guard, the Dates sheet,
the alert cap, the overview page, the accessibility matrix, the detail sheet,
the header's view menu and ⋮, then one per surface each tier of the
language adoption rebuilt — `ls tool/qa/flows/calendar/` names them), each
ending in `expect`s, a `shot` and `errors`. **A flow is updated in the same slice that
changes its screen**, and the last slice of a calendar rework runs
`flows calendar` (the `ui-revamp` gate). Every flow starts and ends on the
calendar page except `00_open`, which starts at the root — so a full pass
starts from a fresh launch. `21_removed_holidays` consumes the seed (it
restores the suppressed holiday, which cannot be removed again from the
day panel), so a lone re-run of it needs `relaunch --fresh --seed` first.
`29_categories_page` (2026-10-31, rewritten with the categories rework's S2 for
the page on content rows: Strength archived through its ⋮ and read under the
`category-section-archived` header before the seeded Archive, restored through
the same item, dragged onto Other by a 900 ms long press and back with the
order asserted by `expect --ordered` — a drag never leaves In use, a drop
across the sections is refused — deleted through its ⋮ and the confirm, a
category created through the FAB and found by its typed name after the page's
own scroll-and-flash) consumes the seed too: it deletes Strength, so a lone
re-run needs `relaunch --fresh --seed` first.

Placeholders work in step files too: `tap "{{longdate+1}}"` taps tomorrow's
day cell by the label the grid gives it.

| Placeholder | Value |
| --- | --- |
| `{{today}}`, `{{today+N}}` | UTC midnight of that day, epoch ms (`startDateMs`, `dayMs`) |
| `{{now}}` | this instant, epoch ms (`createdAtMs`) |
| `{{day+N}}` | `yyyy-MM-dd` |
| `{{longdate+N}}` | `Sunday, September 27, 2026` — the English label a month-grid day cell carries |
| `{{weekday+N}}`, `{{year+N}}`, `{{month+N}}`, `{{dom+N}}` | that day's ISO weekday / year / month / day of month |
| `{{minute+N}}`, `{{minuteday+N}}` | N counts **minutes** here: the minute of the day N minutes from now (`startMinute`), and UTC midnight of the local day that minute falls on, epoch ms (`startDateMs`, `dayMs`). Written as a pair they put an event N minutes ahead of the run — it starts when the clock turns to that minute, so N−1 to N minutes on — and stay right across midnight; `tool/qa/fixtures/alerts.json` is built on them |

A numeric placeholder written as a JSON string (`"{{today+3}}"`) sheds its
quotes on resolution, so a fixture is valid JSON before and after.

**`set` is the matrix without a rebuild or a relaunch:**

```bash
./tool/qa/qa set theme=dark locale=de text-scale=2.0   # any subset; the agent's `set` op
./tool/qa/qa set text-scale=off locale=system theme=system
```

Locale and theme go through the app's own settings bloc (they persist like a
tap in Settings would); the text scale is a QA-only override
(`QaOverrides.textScale`, mounted by `MaterialApp.builder` in a QA build;
`--define ANTA_QA_TEXT_SCALE=2.0` seeds it at launch). `agent info` and
`doctor` print `scale=2.0` while one is imposed. In German the ids still
resolve — that is what they are for.

**Calendar targets** (`lib/constants/semantics_ids.dart`): the editor's rows
(`event-title`, `event-category`, `event-look`, `event-date`, `event-dates`,
`event-add-date`, `event-all-day`, `event-starts`, `event-ends`,
`event-repeat`, `event-priority`, `event-linked-note`, `event-alert-add`, and the description field `event-description`),
its chrome (`event-close`, `event-save`, `event-save-as-template`,
`event-delete`) and its scrolling body (`event-form`); the sub-sheets' Done
(`repeat-done`, `look-done`); the Dates sheet (`date-picker-save`,
`date-picker-cancel`); the detail sheet (`event-detail-edit`, `event-detail-close`, and since 2026-09-26 `event-detail-description`, `event-detail-present`, `event-detail-missed`, `event-detail-skip`, `event-detail-add-date`, `event-detail-dates`, `event-detail-note`); the header (2026-09-26): the title's view menu `calendar-view-menu` with its rows `calendar-view-calendar`, `calendar-overview-open`, `calendar-format-month` / `-two-weeks` / `-week`, and the ⋮ `calendar-more` with `calendar-alerts-open`, `calendar-export`, `calendar-settings-open` — the same ids on the overview; since Tier 1 of the language adoption (2026-09-27): the Upcoming panel's tune button `agenda-filter-open` and the agenda filters sheet's `agenda-filter-*` rows (`-period`, `-follow`, `-events`, `-categories`, `-priority`, `-holidays`, `-fasting`, `-event-rows`, `-fasting-rows`, `-holiday-rows`, `-reset`, `-close`, `-apply`, the body `agenda-filter-sheet`, and one id per menu item such as `agenda-filter-period-90` / `agenda-filter-events-none`), the Dates sheet's `date-picker-today`, the month/year picker's `month-year-close` / `-apply` / `-today` / `-typed`, the description sheet's `description-close` / `-done`, the template picker's `template-pick-close` / `-blank` / `template-pick-<id>`, the icon picker's `icon-pick-close` / `-search`, the sound sheet's `sound-close` / `-inherit` / `-phone-default` / `-from-phone`; since Tier 3 (2026-10-03): the day list's `day-list-*` (its nav `day-list-nav-*`) and each summary card's `agenda-card-days-<key>`, the category editor's `category-editor-*`, the swatch strip's `swatch-row` / `-default` / `-add` / `-manage` and `swatch-menu-*`, both fasting sheets' `fasting-*` (a date's remove `fasting-skip-remove-{{day+N}}`), `removed-holidays-close` and `holiday-restore-<nameKey>-{{day+N}}`, the palette's `palette-*` (a row `palette-row-<rrggbb>`), the colour picker's `color-picker-close` / `-select`, `color-mode-square` / `-wheel`, `color-hex`, `color-copy-hex` — the full list in `calendar-ui`; and **a day-panel row by its event id**
(`event-row-<eventId>`, e.g. `id:event-row-qa-cal-lift` for the seed's
weekly session). A title is never a safe target on the calendar page:
every marked day cell's marker label carries the titles of its events, so
`tap "Morning walk"` is ambiguous twelve ways.

Calendar traps, seen 2026-09-26 unless dated:

- **`scroll-to` swipes inside the first scrollable in the tree**, which in
  the editor is the header strip — eight swipes and nothing moves. Pass
  `--in id:event-form` for anything below the fold (`scroll-to
  id:event-priority --in id:event-form`), and scroll before an `--absent`
  check so absence means gone, not off-screen.
- **`scroll-to` on the agent path settles until no frame is scheduled**
  before each dump (2026-10-03; `_flingSettleMs`, 2500 ms at most, returned
  the moment the frames stop). It used to wait 150 ms after the swipe op's
  own settle of at most 500 ms, and a fling under iOS physics outlived it:
  the row a flow found ended at the viewport's edge and the next tap's
  pointer-down stopped the list instead of pressing the row (`15_templates`
  on the iPhone 17 Pro simulator). The converse of the `--absent` rule
  holds too: a row a previous step scrolled past is absent to `expect`
  until it is scrolled back (`scroll-to id:template-name --up` on that
  874 dp screen).
- **A settings page's section header wins the exact label pass**
  (2026-10-03): on Calendar settings "Categories" and "Appearance" are
  section headers as well as row titles, and on the appearance page
  "Colors" matches four nodes and the page has a "Search settings" field of
  its own. Tap a row by its own second line ("Create and customize event
  categories", "Subtle tint · After holidays", "of your own"), and wait for
  the appearance page by "Today highlight".
- **The overlay bar sits 80 dp above the screen's bottom for its 2 s**
  (2026-10-03): over a one-row sheet that is the header, so a ✕ tapped
  while "Holiday restored" shows hits the bar — `21_removed_holidays` waits
  for the bar to go (`wait "Holiday restored" --gone`) first.
- **Day cells are label-only.** `table_calendar` wraps each cell with
  excluded semantics, so an id inside the cell never reaches the tree; tap a
  day by `"{{longdate+N}}"`.
- **`MenuAnchor` items expose no semantics nodes** — the trap as seen on the
  priority and day-rail menus on 2026-09-26: the menu draws, `dump --all`
  shows only the scrim. Closed on the app side 2026-09-27 (`FormMenuRow` is
  a popup route of radio items with ids — `09_filters.txt` and
  `10_agenda_filters.txt` pick items by id); the trap stays here for any
  `MenuAnchor` that reappears.
- **`relaunch` starts the installed build**, without anything hot-reloaded
  since the last `qa run`; after a lib change, `qa run --fresh --seed …` is
  the honest path (about a minute). **`restart` after `attach` lost the
  agent** once (`no isolate exposes ext.flutter.driver`) — `qa run` again.
- The `[qa] seed:` line counts folders and notes only; the calendar entities
  import silently. A grid with fasting tints but no events after a seed
  means the events were skipped — check the push line said `placeholders
  resolved`.
