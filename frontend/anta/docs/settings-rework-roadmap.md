# Settings rework — design record (2026-10-30)

**Status: IN PROGRESS** — the build started 2026-10-31 in the interleaved
session §1 describes (the merged eleven-step order; the Report record reads
COMMITTED, `350973b8`); the step reached is kept in §7.1's last line.
Proposed 2026-10-30 after the categories brainstorm
(`docs/calendar-categories-roadmap.md`). The owner asked for one accessible
settings page with proper navigation between the pages, a fasting page and
an alert-settings page "with good design", the whole settings area designed
so "the user can have more things", the how-to's included, and research
good enough to release on. No mock: the owner delegated every decision
("I will go with trust"), so §3 holds the recommended option as a
D-numbered, delegated decision, and the standard the owner set is
"bug-free, low-risk". The research: a read-only inventory of twenty
settings surfaces (§2.2), a read-only Opus defect review with 26 findings
S1–S26 (§2.3), the still-open items of the 2026-10-29 newcomer review
(§2.4) and the how-to's as they are today (§2.5). The build runs in a
separate session (§1), after the Report record reads COMMITTED.
Session memory: `settings-rework-2026-10-30`.

Contents: §1 How to run this · §2 Why (§2.1 the ask, §2.2 the inventory,
§2.3 the defects, §2.4 the newcomer review's open items, §2.5 the how-to's)
· §3 Decisions D1–D14 · §4 The spec (§4.1 the drawer, §4.2 the hub, §4.3
the navigation contract, §4.4 the kit, §4.5 alert settings, §4.6 fasting,
§4.7 calendar settings after the moves, §4.8 the how-to's, §4.9 the fixes
by page, §4.10 copy) · §5 Behaviour · §6 Facts from the tree · §7 Slices ·
§8 Definition of done · §9 Deferred.

## 1. How to run this

The prompt for the implementing session (Opus 5.5 at `high`; this record was
written on Fable 5.1 and that session ends here):

> Load `anta-context`, `ui-language`, `l10n`, `verify`, `delegation` and
> `flutter-principles`; add `calendar-events` for S3–S5 and S7. Open
> `docs/settings-rework-roadmap.md`: read §3, §5 and §6 whole, then only the
> slice you are on in §7 and its part of §4. If `git log` says the status
> line is stale, correct it first. Do not start before
> `docs/calendar-report-roadmap.md` reads COMMITTED and
> `docs/calendar-categories-roadmap.md` has at least its S1 committed: all
> three write the drawer, `semantics_ids.dart` and the ARBs. Before S2, grep
> every `SettingsKeys` read in `lib/main.dart`, `lib/core/di/injection.dart`
> and `lib/services/database_manager.dart` and list the keys read before the
> UI exists in §6 (the review did not reach them). Run the slices in order,
> one `implementer` and one `reviewer` per slice; the `design-reviewer`
> checks S1, S2, S3 and S4 after their code review; the `qa-runner` runs the
> `settings` flow suite after S2 and the full matrix at the end of S7. The
> whole `flutter test` runs one at a time, from the lead. Every slice is
> independently shippable: never leave a slice half-built across sessions.
> Do not commit; at every slice boundary report the number of uncommitted
> files and a ready-to-run commit (paths and message). Record each slice's
> as-built notes in §7.1 and anything cut in §9.

**Running both reworks in one session (the owner's ask, 2026-10-30).** The
categories record and this one run interleaved, one slice at a time, one
`implementer` and one `reviewer` per slice, never two writers in the tree
at once. The merged order, each step gated before the next: (1) both
safety nets — this record's S0 and the categories record's S0, test and
flow files only; (2) categories S1 **without its drawer and ⋮ entries**,
which fold into step 4 (the non-visual fixes: the orphan resolve, the
default category, the picker title, the name clamp, the glyph); (3) this
record's S1, the kit; (4) this record's S2, the hub, the drawer and the
contract, with the Categories drawer row and the calendar ⋮ item from the
categories record's A1 built here, since this slice owns the drawer; (5)
categories S2, the page, after its `designer` spec; (6) categories S3, the
delete sheet, Sort confirm and the editor guard; (7) this record's S3,
alert settings, whose Categories row opens the reworked page; (8) S4,
fasting; (9) S5, Calendar settings and App settings; (10) S6, the rest of
the pages; (11) categories S4 and this record's S7 together — the guide's
lessons, the three how-to doors, the device pass over everything, the docs.
Both records' status lines are kept at every boundary; a session that stops
mid-way stops at a boundary and says which step is next.

The owner's standard for this rework is "bug-free, low-risk". The record
turns that into five rules the implementing session keeps: **relocate,
don't rewrite** (a page that moves keeps its row builders); **the kit's API
is frozen** (its restyle is one file, pages do not change for it);
**destructive paths are pinned before they are touched** (S0 writes the
test, the later slice edits under it); **navigation has a contract test**
(every drawer row → its page → back, and every restorable kind); **strings
are additive** (an old key is removed only after its last caller is gone).

## 2. Why

### 2.1 The ask

The owner liked the simple drawer on the categories mock and asked for the
settings behind it to match: one place to reach every setting, pages that
return where they came from, fasting and alerts each on a page of their own
with good design, the how-to's reachable, and room to add more later. The
settings area today is fourteen surfaces in three idioms, reached through
three different back behaviours, with nine pages the launch restore cannot
bring back and a search that never crosses a page.

### 2.2 The inventory (read-only, 2026-10-30)

KIT = `SettingsSectionList` under `SettingsAppBar`; HR = hand-rolled
(`ListTile`, `Card`, slivers); kind = `NavDestinationKind`; reopen =
`reopensDrawerOnPop`. Line numbers are from 2026-10-30.

| Page | Lines | Idiom | Reached from | Kind / reopen | Suite |
| --- | --- | --- | --- | --- | --- |
| App settings `settings_page.dart` | 906 | KIT (6 sections) | drawer `:213` via `_openSettingsPage` | `settings` / true | `settings_page_test` (6, incl. de 2.0), golden |
| Calendar settings `calendar_settings_page.dart` | 1611 | KIT (7 sections: holidays, appearance, filtering, categories, fasting, events, alerts) | drawer `:149` (pop+push); calendar / overview / report ⋮ | `calendarSettings` / false | golden, large-text, delete-all, slider-draft |
| Calendar appearance `calendar_appearance_page.dart` | 952 | KIT (6) | calendar settings `:576` (awaited) | `calendarAppearance` / false | `calendar_appearance_page_test` (12, en) |
| Categories `calendar_categories_page.dart` | 675 | HR | calendar settings `:639` | `calendarCategories` / false | own suite (the categories record) |
| Event templates `event_templates_page.dart` | 194 | HR | calendar settings `:798` | `eventTemplates` / false | indirect |
| Markdown shortcuts `markdown_settings_page.dart` | 2588 | HR slivers, own search field | drawer `:172`; editor `:3553` | **none** | `markdown_settings_page_test` |
| Shortcut editor `shortcut_editor_page.dart` | 2029 | HR form | markdown settings `:570/:592` | none (transient) | behaviour test only |
| Markdown colours `markdown_colors_page.dart` | 377 | HR | markdown settings `:1216` | **none** | `markdown_colors_page_test` |
| Per-note bar `note_bar_assignment_page.dart` | 285 | HR | markdown settings `:898` | **none** | none |
| Per-note currency `note_money_currency_page.dart` | 299 | HR | markdown settings `:1546` | **none** | none |
| Vocabularies + editor | 232 + 230 | HR | markdown settings `:1358` | `vocabularies` (never recorded, S26) / none | `vocabularies_page_test` / none |
| Counters `counter_management_page.dart` | 577 | HR | drawer `:191`; editor `:3290` | `counterManagement` / true | none |
| Counter per note `counter_per_note_page.dart` | 510 | HR | counters `:440/:524` | **none** | own suite |
| Databases `database_settings_page.dart` | 1086 | HR (4 `Card`s), 14 dialogs | drawer `:222` | `databaseSettings` / true | **none** |
| Sharing `sync_settings_page.dart` | 483 | KIT in part + 10 `ListTile` | drawer `:206`; avatar `:445` | `syncSettings` / true | **none** |
| Developer options `developer_options_page.dart` | 322 | KIT compact | drawer `:263` when unlocked | **none** | none |
| Permissions `permissions_page.dart` | 327 | KIT (3) | drawer `:480`; calendar settings `:1085/:1224`; the prompt; the guide | `permissions` / false (live `popsToDrawer: true`) | `permissions_page_test` (9, en) |
| Alerts hub `alerts_page.dart` | 1374 | `FormRowGroup` + `Card`s | drawer `:159`; three ⋮; the platform | `alerts` / false | `alerts_page_test` (45), golden |
| Language · Theme · About | in `app_drawer.dart:587-663` | `AppDialogs.radioSelect` / `choose`; stock `showAboutDialog` | drawer | not restorable | none |
| Onboarding `onboarding_page.dart` | 228 | HR, no bar | launch gate `main.dart:820` | — | **none** |

The kit: `settings_section_list.dart` (`SettingsEntry` title · description ·
keywords · builder · identifier; `SettingsSectionData` icon · title · entries
· intro · id; `SettingsSectionList` sections · query · header · footer ·
style standard/compact · collapsedSections · onToggleSection),
`settings_search_field.dart` (nine callers), `slider_setting_row.dart`
(350 ms debounce), `settings_search.dart` (diacritic-folded AND over title,
description and keywords; per page only). Collapse state is persisted by
section id (`settings_service.dart:1506-1529`). `SettingsAppBar`
(`unified_app_bars.dart:431`) paints the gradient and, with `popsToDrawer`,
pops with `SettingsResult.openDrawer` — only from its arrow.

`SettingsKeys` holds 212 constants; four have no caller in `lib`
(`markdownShortcuts`, `customShortcuts`, `maxRecentEventColors`,
`defaultCalendarUpcomingPriorities`). Fasting lives in the calendar settings
fasting section (`:640-770`: four tradition switches, a "look" row per
enabled tradition opening `FastingStyleSheet` live, the Orthodox great-fasts
switch, "My practice" opening `FastingScheduleSheet` live), in the
appearance page's tint-conflict row (`:419`) and in the two filter sheets'
fasting layer. Alert settings live in the calendar settings alerts section
(`:856-1060`: permissions row, default timed / all-day, sound, snooze
5–25, notice lead 0–1440 min, silence after 1–30, test alarm); the ring
volume floor is a constant (`alert_constants.dart:205`); the hub holds no
setting but the digest switches. Restore replays fourteen kinds
(`app_navigator.dart:1092-1126`).

### 2.3 The defects (read-only Opus review, 2026-10-30)

CONFIRMED = settled by quoted code; PLAUSIBLE = needs a render or a run.
Severity 4 = data loss or a stranded user, 3 = a wrong result the user cannot
explain, 2 = a visible inconsistency or an accessibility failure, 1 = a nit.
"Fix" is the slice of §7 or §9.

| Id | Sev | Finding | Where | Fix |
| --- | --- | --- | --- | --- |
| S1 | 4 | Calendar settings "Reset to defaults" wipes user-entered fasting data (the schedule's up to 2 × 200 hand-picked dates, the traditions, the per-tradition looks), resets the holiday profile and restores every removed holiday, under the app-wide "reset all settings" confirm that is not destructive-styled and names none of it; the appearance page is not reset. CONFIRMED | `calendar_settings_page.dart:1250-1256`, `:1328-1345` | S5 (D7: the reset goes) |
| S2 | 4 | "Share database" copies only the main `.db` while the connection runs in WAL (`database.dart:407`), so the shared backup can lack recent writes; the page's own comment says so. CONFIRMED (code) | `database_settings_page.dart:951-987`, `:60-64` | S6 |
| S3 | 4 | Onboarding is a non-scrolling centred `Column`; at de 2.0 on 360 × 780 its content (~930 px) exceeds the screen, so "Restore from backup" is likely off-screen on first launch. PLAUSIBLE | `onboarding_page.dart:30-80` | S6 |
| S4 | 3 | A share failure pops the Database page itself: the loading dialog is popped at `:974`, then the catch pops again at `:980`. CONFIRMED | `database_settings_page.dart:973-981` | S6 |
| S5 | 3 | Unbounded `trailing:` widgets remain, the pattern that blanked Calendar settings in German at 2.0: the permission tile's `TextButton` / `Text`, four `TextButton`s on Sharing, a five-segment `SegmentedButton` on markdown settings `:1333`, the week-start `DropdownButton` on appearance `:741`, plus `:1487`, `:1507`, `:2119` and `vocabularies_page.dart:172`. The calendar case is fixed by `_YieldingTile` (`:1415-1570`). PLAUSIBLE | as listed | S1 hoists the tile; S5 / S6 convert |
| S6 | 3 | Back differs by how you leave or arrive: only the bar's arrow reports `openDrawer`, system back never does (no settings page has a `PopScope`); Permissions reopens the drawer live but not restored; Counters restored from the editor raises the drawer over the editor. CONFIRMED | `unified_app_bars.dart:484-489`, `app_navigator.dart:986-1004`, `:1112` | S2 (D3) |
| S7 | 3 | Switching the active database persists the new name before the "Restart required" dialog, with no confirm and no way back. PLAUSIBLE | `database_settings_page.dart:787-811` | S6 |
| S8 | 3 | "Delete all data" and "Delete all events": one confirm each, no export offer, `tombstoneAll()` without try/catch, a literal `Colors.green`. CONFIRMED | `database_settings_page.dart:1039-1083`, `calendar_settings_page.dart:1260-1288` | S5 / S6 |
| S9 | 3 | Onboarding's import bypasses `ImportExportBloc` and concatenates a count into a string. CONFIRMED | `onboarding_page.dart` `_importBackup`, `:215-216` | §9 (the bloc), S6 (the plural) |
| S10 | 2 | The settings search field is a fixed 40 dp box (text clips at 2.0), its hint is 3.05:1 in light, its clear ✕ is a bare 32 dp `GestureDetector` with no label. CONFIRMED | `settings_search_field.dart:54-93` | S1 |
| S11 | 2 | Kit sliders announce a percentage, not the value (no `semanticFormatterCallback`). CONFIRMED | `settings_page.dart:776-801`, `slider_setting_row.dart:113-121` | S1 |
| S12 | 2 | `SliderSettingRow` cancels its 350 ms commit timer in `dispose`, so a keyboard or TalkBack change made within 350 ms of leaving is lost. PLAUSIBLE | `slider_setting_row.dart:68-71` | S1 |
| S13 | 2 | The app settings reset calls `setState` before its `mounted` check after ~20 awaits, and a throw in `LabelAppearanceService.setStyle` leaves stale values with no error (`async void`); `RestoreLocationMode.everything` is a literal default. CONFIRMED | `settings_page.dart:830-905` | S5 |
| S14 | 2 | Controls hidden instead of disabled, invisible to search while hidden: the auto-save interval, the fasting look rows, the great-fasts switch, My practice, the tint-conflict row. CONFIRMED | `settings_page.dart:477-479`, `calendar_settings_page.dart:676-751`, `calendar_appearance_page.dart:396-398` | S4 / S5 |
| S15 | 2 | Drawer inconsistencies: two rows pop-and-push, seven reopen the drawer, two dialogs reopen nothing; `toSettings`, `toDatabaseSettings`, `toSyncSettings` never dedupe (a settings page can be pushed over itself); Permissions wears the ←│☰ pair under Calendar settings, which hides its own. CONFIRMED | `app_drawer.dart:146-283`, `app_navigator.dart:854-866` | S2 |
| S16 | 2 | About and the version are literals (`'ANTA v1.0.0'`, `'1.0.0'`, `'2026 ANTA'`) that will drift at the release bump; About is the stock dialog with the gym icon. CONFIRMED | `app_drawer.dart:277`, `:579`, `:591-594`; `pubspec.yaml:19` | S2 |
| S17 | 2 | No semantics ids on fifteen settings pages, on six drawer rows; `settingsAppearance` sits on the Theme dialog row. CONFIRMED | as listed | S2 and each page's slice |
| S18 | 2 | `PopupMenuButton(tooltip: '')` leaves two menu buttons unnamed. CONFIRMED | `note_bar_assignment_page.dart:201`, `note_money_currency_page.dart:201` | S6 |
| S19 | 2 | Calendar settings and the appearance page share one fold set; a restored `[calendarSettings, calendarAppearance]` stack leaves the parent stale and its next toggle overwrites the child's folds. CONFIRMED | `calendar_settings_page.dart:68-72`, `:221-227`, `:575-577` | S5 |
| S20 | 2 | Idiom violations by count: `Card` on eleven settings surfaces, `PopupMenuButton` / `showMenu` on seven, raw `showDialog` + `AlertDialog` twice in markdown settings, FABs on seven, the hub mixing a `FormRowGroup` with `Card` rows. CONFIRMED | as listed | S1 (the kit's cards), the rest §9 per page |
| S21 | 2 | The tint-conflict `SegmentedButton` lacks the word-fit measure `settings_page._choiceRow` has, so German breaks mid-word at 2.0. PLAUSIBLE | `calendar_appearance_page.dart:412` vs `settings_page.dart:687-750` | S1 (hoisted) · S5 |
| S22 | 1 | Database page literals: `'Unknown'`, `'Error loading path'`, `'B'/'KB'/'MB'`, a hand-built date; a `setState` in a catch with no `mounted` check. CONFIRMED | `database_settings_page.dart:87-104`, `:345` | S6 |
| S23 | 1 | `'${v}s'` on app settings; a subtitle literal on markdown colours; the drawer's 11/700/0.9 labels and 100 ms delay. CONFIRMED | `settings_page.dart:489`, `markdown_colors_page.dart:298`, `app_drawer.dart:64`, `:85-101` | S5 / S2 |
| S24 | 1 | Developer options are stored under a raw `'dev_options'` key through the DAO, outside `SettingsService`. CONFIRMED | `dev_options_service.dart` | §9 |
| S25 | 1 | Settings pages tie their drawer edge-drag to `getFolderSwipeEnabled`, a browser setting. | `settings_page.dart:170` | S2 (moot: settings pages lose the drawer) |
| S26 | 1 | `NavDestinationKind.vocabularies` is never recorded because its parent (markdown settings) is unstamped. CONFIRMED | `navigation_history_service.dart:186-193` | S2 |

The review did not reach: a line-level pass of the shortcut editor, the
vocabulary editor, vocabularies, event templates, markdown colours and
counter-per-note; the alerts hub's row internals; focus order; 48 dp per
control; the list of keys read at bootstrap; whether `SettingsService`
setters notify listeners. Nothing ran (no `flutter test`, no render): S3,
S5, S10, S12 and S21 need the de 2.0 widget tests S0 and S1 add.

### 2.4 The newcomer review's open items (2026-10-29, still true in the tree)

From `docs/calendar-guide-page.md` §3.D–§3.E, re-checked on 2026-10-30. Fixed
since: N93's confirm is now `isDestructive: true` (its scope is S1 above);
N98 is half-fixed (the page title key `calendarSettings` still reads
"Calendar", the drawer row "Calendar settings"). Still open and taken here:
N96 (the drawer promises "Week start" two levels down — the hub's
subtitles tell the truth, §4.2), N98 (title), N99 (the holiday row's
description), N105 ("Dark mode, colors and display" promises what the
Theme dialog does not have), N109–N111 (fasting wording: "Multi-day fasts"
off, months' "None", "Days off"), N118 (three single-row cards on calendar
settings), N119 (the fasting look row says "Appearance", its sheet says
"Orthodox"), N121 / N153 (notice lead in minutes up to 1440), N148 ("Remove
alert" means "no default"), N142 (the empty hub's only button is Add
digest), N150 (category alerts three levels deep — the hub's ⚙ and the
alert settings page's "Categories" row close it). Left in §9 with their
reason: N91 / N92 (holiday profiles by locale and the Romanian January
days), N94 (the fitness built-ins), N97 (settings in the backup allowlist),
N100, N106, N112–N117, N120, N122–N124, N125–N141, N143–N147, N149, N151,
N152, N154–N157.

### 2.5 The how-to's today

One guide exists, the calendar's: a hub (`calendar_guide_page.dart`, a
`SettingsAppBar` over `_HubRow`s and a `SettingsSearchField`) of ten topics
(`CalendarGuideTopic`: screen, events, kinds, alerts, attendance,
categories, finding, setup, fasting, good), each a topic page with read
rows, one coach line per card and a hands-on sandbox, plus the practice
calendar page. It is reachable only from the ⋮ of the calendar, the
overview and the report (`toCalendarGuide`, `app_navigator.dart:596`) and
by restore (`calendarGuide`). Nothing points to it from the drawer, from
any settings page or from onboarding; the fasting and alerts settings sit
next to nothing that explains them. No how-to exists for notes, markdown,
money, counters, backup or sharing (one string, `markdownColorsHowTo`, is
the whole of it). The `setup` topic describes the settings as they are
reached today and will be stale after S2; the guide record's deferred list
already carries the kit's accessibility findings this record fixes in S1.

## 3. Decisions (delegated 2026-10-30)

The owner delegated every decision; each row is the recommended option,
taken, with the alternative it beat and why. An amendment appends; nothing
is rewritten.

| D | Decision | Alternative not taken | Why |
| --- | --- | --- | --- |
| D1 | **The drawer lists places, not settings.** Calendar: Calendar · Overview · Report · Categories · Alerts. Notes: Counters. App: Settings · How to use ANTA · About (the version row keeps the developer unlock). Markdown shortcuts, Sharing, App settings, Databases, Language, Theme, Permissions and Developer options leave the drawer for the hub. | keep every settings row in the drawer, add the hub beside them | the owner liked the drawer "simple"; two ways to the same page from one menu is the confusion S15 names |
| D2 | **One settings hub page** (`SettingsHubPage`, the kit) with sections Calendar · Notes · App · How to, one row per page with a subtitle that names its contents, a search over the rows (title, subtitle, and the page's section titles as keywords) that opens the page, and the permissions attention line on its Permissions row and on the drawer's Settings row. | a cross-page search that opens the page scrolled to the matching section | the deep link needs every page to accept a section id; it is §9, additive, after the hub ships |
| D3 | **One navigation contract.** Back, by arrow or system gesture, returns to the route beneath, always; the reopen-the-drawer mechanism (`SettingsResult.openDrawer`, `popsToDrawer`, `reopensDrawerOnPop`, `DrawerHostRegistry.openTopDrawer` for it) retires; the hub is where the next page is chosen; every `toX` dedupes on the top route's kind; every settings page gets a `NavDestinationKind` and a restore stack `[…, settingsHub, page]` when it was reached from the hub, its live opener otherwise; settings-family pages show the arrow alone (no drawer on them). Deep links (the calendar ⋮, the editor, the hub's ⚙, the prompts) keep returning to their opener. | keep reopening the drawer and add a `PopScope` to make system back match | reopening the drawer only existed because there was no hub; S6 shows three ways it disagrees with itself |
| D4 | **The kit is restyled in place with its API frozen** (settles decision 1 of `docs/ui-language-adoption-roadmap.md`): `pageGround` under `rowGroup` groups at `RowMetrics.groupRadius`, no `Card`, no elevation; the section header is the browser's (11 / 500 uppercase, `headingLevel`), the section icon no longer drawn; entries styled by one `ListTileTheme` / `SwitchListTileTheme` scope (15 / 400 title, 13 caption, 48 / 62 dp rows, `groupInset`); the bar loses its gradient; the search field becomes a 48 dp, scale-aware, AA field with a labelled ✕; `_YieldingTile` and `_choiceRow`'s word-fit become kit members; sliders announce their value and commit on dispose. Pages change nothing for this slice. | migrate each page to `FormRowGroup` rows | fourteen pages rewritten is the opposite of low-risk; the kit is one file and one theme scope |
| D5 | **Alert settings is a page** (`AlertSettingsPage`): the calendar settings alerts section moves there whole, plus a Categories row (the categories page, for category alerts) and a How-it-works row; reached from the hub, from a ⚙ on the Alerts hub's bar, and from a single row left on Calendar settings. | leave alerts inside Calendar settings | N150: three levels deep; the hub and its settings are one subject |
| D6 | **Fasting is a page** (`FastingSettingsPage`): the fasting section moves there whole, its rows disabled rather than hidden while no tradition is on, the wording of N109–N111 / N119, a How-it-works row; reached from the hub and from a single row left on Calendar settings; the two sheets stay as they are (live-apply). | inline the schedule sheet's chips on the page | the sheet's rules (constant height, scope hints, the 200 cap) are tested and used by the guide's lesson; inlining is §9 |
| D7 | **Calendar settings loses its reset.** The page is titled "Calendar settings", its first section "Holidays"; it keeps Holidays, Filtering, Events and one row each to Appearance, Categories, Fasting and Alert settings; the page-level "Reset to defaults" is removed (the appearance page keeps its own). | keep the reset and shrink its scope | after the moves the reset would cover two rows; S1 is a data-loss path and removing it is the one change with no failure mode |
| D8 | **The Databases page keeps its code paths and gets four guarded fixes**: a WAL checkpoint before share through a service method and `shareExport` (S2), `runWithLoading` for the share (S4), a confirm before switching the active database (S7), a `mounted` guard and localized units (S22); every fix under a test pinned in S0. | rewrite the page on the kit | the destructive paths are the riskiest code in the app; they move in §9, one at a time, when a suite exists |
| D9 | **Onboarding scrolls** (S3) and pluralizes (S9's string); its import path stays as it is. | route the import through `ImportExportBloc` now | the bloc assumes an open database; the first-launch path has no suite yet (S0 gives it one), so the move is §9 |
| D10 | **The drawer's rows are plain**: glyph 24 `onSurfaceVariant`, title 15, subtitle 13, group labels 11 / 500 / 0.88, no tinted chips, the header unchanged; the version row reads one `kAppVersion` constant pinned to `pubspec.yaml` by a test; About goes through `AppDialogs` with the app icon. | restyle the header too | the header is a separate decision (master decision 5 stays open for it); the rows are what the owner saw on the mock |
| D11 | **Language and Theme are hub rows** opening the same two dialogs; the Theme subtitle reads "Light, dark or follow the phone" (N105); the `settingsAppearance` id moves with it. | a combined appearance page | two dialogs with three options each do not need a page |
| D12 | **The how-to's get three doors**: a drawer row "How to use ANTA" and a hub section "How to" (both the calendar guide for now, titled by the guide), and a "How it works" row at the end of the Fasting and Alert settings pages that opens the guide topic directly (`toCalendarGuideTopic`, not restorable — its parent is); the guide's `setup` topic is rewritten for the hub. | a guides hub page now | one guide exists; the row and the section are the slots the next guide fills |
| D13 | **Every row a device script must hit gets a `SemanticsIds` entry**, and a `settings` flow suite walks the hub, every page, back and restore. | ids only on the new pages | S17: fifteen pages have none, and the release pass needs them |
| D14 | **Every page without a suite gets a smoke suite** (opens, renders at de 2.0 on 360 × 780 with no overflow, its destructive dialogs cancel safely) before its slice touches it. | suites only for the pages the slices rewrite | the pinned tests are what makes a relocation low-risk |

**Amendment 2026-10-31 (from S0's contract test).** D1, D10 and §4.1 say
"the version row keeps the developer unlock"; the unlock is the taps on the
drawer **header's icon** (`app_drawer.dart:337`, `_handleIconTap`), and no
version row carries a gesture today. S2 keeps the gesture on the header icon
(the header is unchanged under D10) and About gets none; giving that icon a
`SemanticsIds` entry would let the `settings` flow suite reach Developer
options, which S0 had to skip.

## 4. The spec

### 4.1 The drawer

`app_drawer.dart`. Groups and rows, top to bottom (strings in §4.10):

- **Calendar** — Calendar · Overview · Report · Categories (the categories record's row) · Alerts. Each pops the drawer then pushes; back returns beneath.
- **Notes** — Counters.
- **App** — Settings (`Icons.settings_rounded`, subtitle `settingsHubRowDesc`; the permissions attention line replaces the subtitle while a permission is missing, as the old Permissions row did) · How to use ANTA (`Icons.school_rounded`) · About (the version row; the developer unlock taps stay on it; `kAppVersion` from `lib/constants/app_version.dart`, pinned by `app_version_test.dart` reading `pubspec.yaml`).
- Rows are the existing `_buildMenuItem` with the chip removed: a 24 px glyph in `onSurfaceVariant`, title 15 / 400 `onSurface`, subtitle 13 / 400 `onSurfaceVariant`, group labels on `RowMetrics.sectionLabel*`; every row carries an id (`drawerCalendar`, `drawerCalendarOverview`, `drawerCalendarReport`, `drawerCalendarCategories`, `drawerAlerts`, `drawerCounters`, `drawerSettings`, `drawerHowTo`, `drawerAbout`).
- Removed from the drawer: Markdown shortcuts, Sharing, App settings, Databases, Language, Theme, Permissions, Developer options, the avatar badge's push (it opens the hub's Sharing page through `toSyncSettings`). `_openSettingsPage`, `_showLanguageDialog`, `_showThemeDialog` move to the hub.

### 4.2 The settings hub

`lib/pages/settings_hub_page.dart`, `NavDestinationKind.settingsHub`, the kit
(`SettingsSectionList`, `style: standard`, the restyled search field above,
ids `settingsHubSearch`, `settingsHubRow(kind)`):

- **Calendar** — Calendar settings ("Holidays, filtering, events") · Appearance ("Week start, cells, markers, colours") · Categories ("Create, order, archive") · Fasting ("Traditions, your practice") · Alert settings ("Defaults, sound, timing, permissions").
- **Notes** — Editor and markdown ("Shortcuts, toolbar, colours, vocabularies, money") · Counters ("Pinned and per-note counters").
- **App** — General ("Startup, browsing, editor, auto-save") · Language · Theme ("Light, dark or follow the phone") · Databases and backup ("Switch, export, import, delete") · Sharing ("Account and paired devices") · Permissions (the attention line while missing) · Developer options (only while unlocked).
- **How to** — How to use the calendar (the guide hub).
- Each row is a `SettingsEntry` whose builder is a one-line navigation row (title, subtitle, chevron) and whose `keywords` are the page's section titles (l10n), so "snooze" finds Alert settings and "holiday" finds Calendar settings; a match opens the page. The search keeps its field while a query is live and shows the kit's no-matches caption.
- Language and Theme rows open `AppDialogs.radioSelect` / `choose` as today; the hub rebuilds the Theme subtitle's value line after the dialog.

### 4.3 The navigation contract

- `AppNavigator`: every settings `toX` checks the top route's kind and returns when it is already there (the `toPermissions` pattern at `app_navigator.dart:854-866`); new kinds `settingsHub`, `fastingSettings`, `alertSettings`, `markdownSettings`, `markdownColors`, `noteBarAssignment`, `noteMoneyCurrency`, `counterPerNote`, `developerOptions`; `shortcutEditor`, `vocabularyEditor` and the guide topic page stay transient (restored to their parent). Kind names are persisted in the stack blob (`nav_destination.dart:16-18`): a build that reads an unknown name must drop that entry and keep the rest — the implementer verifies the decoder does and adds the test if not.
- The restore stack of a page reached from the hub is `[…, settingsHub, page]`; from a deep link it is the live opener's stack as today. `reopensDrawerOnPop` returns false for every kind and is deleted in S7 with the restore branch that read it.
- `SettingsAppBar` loses `popsToDrawer` and `showMenuButton` defaults to false: a settings-family page draws the arrow; `SettingsResult` is deleted when its last reader goes (`developer_options_page.dart:136-139` "Lock" pops `true` instead and the hub hides the row).
- The contract test (`test/widgets/settings_navigation_contract_test.dart` — S0's file, rewritten in place by S2 so the diff is the proof; the path is this one, not the `test/navigation/` this line first named): for every drawer row, tap → the expected page is top → back → the route beneath is the one the drawer was opened over; for every hub row the same with the hub beneath; for every restorable kind, `restoreLastLocation` rebuilds the expected stack; the deep links (calendar ⋮ → Calendar settings → back lands on the calendar; the editor's counter picker → Counters → back lands on the editor).

### 4.4 The kit

`settings_section_list.dart`, `settings_search_field.dart`,
`slider_setting_row.dart`, `unified_app_bars.dart` only; the pages are not
edited in S1.

- Ground `colorScheme.pageGround`; each section a `DecoratedBox` in `rowGroup` at `RowMetrics.groupRadius`, no `Card`, no elevation, hairlines `rowDivider` indented `dividerIndentPlain`; `groupInset` left and right, `groupGap` between sections; `SettingsSectionStyle.compact` keeps its tighter paddings as named constants.
- Section header: title at `RowMetrics.sectionLabel*` (11 / 500, uppercase, 0.88) in `onSurfaceVariant`, `Semantics(headingLevel: 2)`, the fold chevron and the folded count both bounded (`Expanded` title, the count in a fixed-width `SizedBox` with tabular figures); the `icon` field stays in the API and is no longer drawn (retired in S7 from every call site).
- Entries: the list wraps its entries in `ListTileTheme` (title 15 / 400 `onSurface`, subtitle 13 / 400 `onSurfaceVariant`, `contentPadding` `groupInset` / `rowEndPadding`, `minVerticalPadding` giving 48 one-line and 62 two-line rows) and `SwitchListTileTheme`; descriptions stay where pages pass them, at the caption role.
- `SettingsYieldingTile` (the hoisted `_YieldingTile`) is the kit's row for a bounded trailing; a raw `trailing:` wider than a third of the row is a defect for S5 / S6 to convert. `settingsChoiceRow` (the hoisted `_choiceRow` with its word-fit) is the kit's segmented row; its vertical stacking rule is unchanged.
- `SettingsSearchField`: 48 dp tall at 1.0, height from the text's line height at other scales, hint and glyph `onSurfaceVariant`, the clear ✕ a 48 dp `IconButton` with the `clear` tooltip and `identifier: settingsSearchClear`, the field `identifier` passed by the page.
- `SliderSettingRow` and `settings_page._sliderRow`: `semanticFormatterCallback` naming the value with its unit; a pending draft commits in `dispose`; the title and the slider are one `MergeSemantics` row.
- `SettingsAppBar` paints the standard bar (`pageGround`, `AppBarMetrics`); `UnifiedAppBar.settings`' gradient goes.
- Goldens (`settings`, `calendar settings`, `alerts`) are regenerated once in S1 and reviewed by the `design-reviewer`; `settings_section_fold_test` gains the heading and target assertions; a `meetsGuideline` run (tap targets, text contrast, labelled taps) over the hub and App settings at 1.0 and 2.0.

### 4.5 Alert settings

`lib/pages/alert_settings_page.dart`, `NavDestinationKind.alertSettings`,
the kit, title `alertSettingsTitle` "Alert settings":

- **Defaults** — Timed events · All-day events (the two rows of `calendar_settings_page.dart:881-914` moved verbatim; the sheet's "Remove alert" reads "No default alert", N148; an untouched Done saves nothing — the editor sheet's `initial == null` case).
- **Sound and timing** — Sound (`:915-941`) · Snooze (`:942-969`) · Upcoming notice (`:970-1000`, the caption renders hours from 60 min up: "2 hours before", N121 / N153) · Silence after (`:1001-1028`).
- **Permissions** — the permissions row (`:869-880`, `_permissionsTile`) · Test alarm (`:1029-1060`).
- **Categories** — one row to the categories page ("Alerts per category are set on each category").
- **How it works** — one row opening the guide's alerts topic (D12).
- Reached from the hub, from the Alerts hub's bar (`IconButton` `settings_rounded`, tooltip `alertSettingsTitle`, `identifier: alertsSettingsOpen`, through `toAlertSettings`), and from Calendar settings' single Alerts row (`:856` becomes a navigation row with the defaults as its value line). The `_scheduleTestAlarm` and permission-refresh code moves with the rows unchanged.

### 4.6 Fasting

`lib/pages/fasting_settings_page.dart`, `NavDestinationKind.fastingSettings`,
the kit, title `fastingSettingsTitle` "Fasting":

- **Traditions** — four switch rows (`calendar_settings_page.dart:656-662`), each followed by its "Look on the calendar" row (N119; `:678-684`, disabled at 38 % while its tradition is off, S14) opening `FastingStyleSheet` live, after the palette prewarm (`:140-145`).
- **Orthodox** — Great fasts (`:703-705`, disabled while Orthodox is off) with the N109 caption ("Off: only your weekly fast days, all year").
- **Your practice** — the schedule row (`:729-737`, "My practice" → "Your practice"; the summary `:293-305`) opening `FastingScheduleSheet` live; inside the sheet "Days off" → "Dates I don't fast" (N111) and the months' None keeps the caption "No months kept — fasting stays on" (N110).
- **How it works** — the guide's fasting topic (D12).
- Reached from the hub and from Calendar settings' single Fasting row (the summary as its value). The fasting section's state (`_fastingAppearance`, `_schedule`, their loads at `:128-165`) moves whole; `keeps()`, `encode` / `decode` and the limits are untouched (§5).

### 4.7 Calendar settings after the moves

Title `calendarSettings` → "Calendar settings" (the drawer row key
`calendarSettingsRow` retires once the drawer row is gone); sections:
Holidays (`calendarSection` → "Holidays"; the profile row with the N99
description "Public holidays shown on the calendar; also used by Workdays
repeats"; removed holidays) · Appearance (one row, as today) · Filtering ·
Categories (one row) · Fasting (one row, the summary) · Alert settings (one
row, the defaults) · Events (templates, description limit, delete all with
try/catch and a failure snackbar, S8). The page-level reset and its strings
go (D7). The fold-set clash (S19): the appearance page owns its
`appearance_` ids and the parent re-reads the set on every `didPopNext`
(a `RouteAware` subscription) instead of only after its own push. The
three single-row cards (N118) merge into the navigation rows above.

### 4.8 The how-to's

- The drawer row and the hub section open the guide hub (`toCalendarGuide`); the hub's title stays "How to use the calendar" until a second guide exists, when the row becomes a guides hub (§9).
- `AppNavigator.toCalendarGuideTopic(CalendarGuideTopic)` pushes the topic page directly (the hub is not inserted beneath; back returns to the settings page); not restorable.
- The guide's `setup` topic rewrites its "where the settings are" rows for the hub (drawer → Settings → …), gains a "Fasting" and an "Alert settings" row that say where those pages are, and its coach line names the hub; the `categories-where` row of the categories record is written in the same voice. The lessons' sandboxes are untouched.
- Onboarding's last screen gets one text row "You can open How to use ANTA from the menu at any time" (no new control).

### 4.9 The fixes by page (what each slice edits beyond the moves)

- **App settings** (S5): the reset's `mounted` guard before every `setState` and a try/catch that reports through `CustomSnackbar` (S13); `RestoreLocationMode.everything` from `SettingsKeys` defaults; the auto-save interval row disabled, not hidden (S14); `'${v}s'` through an ARB unit key (S23); ids on its rows (S17).
- **Appearance** (S5): the week-start `DropdownButton` becomes a `SettingsYieldingTile` with a menu (S5); the tint-conflict row disabled, not hidden, and on `settingsChoiceRow` (S14, S21).
- **Databases** (S6): D8's four fixes; the success dialog's `Colors.green` → `colorScheme.primary`; ids; a smoke suite with fakes for `DatabaseManager`, `BackupService` and the share.
- **Sharing** (S6): the four `TextButton` trailings → `SettingsYieldingTile` rows with the action as the row's tap; ids; a smoke suite.
- **Permissions** (S6): the tile's trailing bounded the same way; `showMenuButton: false`.
- **Markdown settings and its sub-pages** (S6): the five-segment trailing → `settingsChoiceRow`; the two `Text` / `Row` trailings bounded; the two bare tooltips named (S18); ids on the bar and the main rows; nothing else moves (its `Card`s and menus are §9).
- **Counters** (S2 only for the kind and ids).
- **Onboarding** (S6): `SingleChildScrollView` + `ConstrainedBox(minHeight)`, the plural, the how-to line, a smoke suite at de 2.0.
- **Developer options** (S2 kind and the Lock change; S6 ids).

### 4.10 Copy (en; de / ro at implementation, every key in all three ARBs)

`settingsHubTitle` "Settings" · `settingsHubRowDesc` "Everything you can
change" · `settingsHubSearchHint` "Search settings" · `settingsSectionCalendar`
/ `Notes` / `App` / `HowTo` ("Calendar", "Notes", "App", "How to") ·
`settingsRowCalendarDesc` "Holidays, filtering, events" ·
`settingsRowAppearanceDesc` "Week start, cells, markers, colours" ·
`settingsRowFastingDesc` "Traditions, your practice" ·
`settingsRowAlertsDesc` "Defaults, sound, timing, permissions" ·
`settingsRowEditor` "Editor and markdown" · `settingsRowEditorDesc`
"Shortcuts, toolbar, colours, vocabularies, money" · `settingsRowCountersDesc`
"Pinned and per-note counters" · `settingsRowGeneral` "General" ·
`settingsRowGeneralDesc` "Startup, browsing, editor, auto-save" ·
`themeSettingsDesc` → "Light, dark or follow the phone" ·
`settingsRowDatabasesDesc` "Switch, export, import, delete" ·
`settingsRowSharingDesc` "Account and paired devices" · `howToUseAnta` "How
to use ANTA" · `howItWorks` "How it works" · `alertSettingsTitle` "Alert
settings" · `alertSettingsCategoriesRow` "Alerts per category" ·
`alertSettingsCategoriesDesc` "Set on each category" · `alertDefaultNone`
"No default alert" · `alertNoticeLeadHours` "{count, plural, =1{1 hour
before} other{{count} hours before}}" · `fastingSettingsTitle` "Fasting" ·
`fastingLookRow` "Look on the calendar" · `fastingGreatFastsOffDesc` "Off:
only your weekly fast days, all year" · `fastingPracticeRow` "Your
practice" · `fastingSkipDatesLabel` "Dates I don't fast" ·
`fastingMonthsNoneCaption` "No months kept — fasting stays on" ·
`calendarSettings` → "Calendar settings" · `calendarSection` → "Holidays" ·
`holidayProfileDesc` "Public holidays shown on the calendar; also used by
Workdays repeats" · `databaseSwitchConfirm` "Switch to {name}? ANTA restarts
on it." · `databaseSizeBytes` / `Kilobytes` / `Megabytes` · `unknownValue`
"Unknown" · `databasePathError` "Could not read the storage path" ·
`onboardingHowToHint` "You can open How to use ANTA from the menu at any
time" · `autoSaveSeconds` "{count} s" · the guide's rewritten `setup` rows.
Retired after their last caller: `calendarSettingsRow`, `calendarSettingsRowDesc`,
the calendar reset's two strings, `resetToDefaultsConfirm` only if no other
page uses it.

## 5. Behaviour

**Must not change**

- Every `SettingsKeys` constant, its default and its storage; no new key is required (the hub has no state of its own; collapsed sections reuse the kit's mechanism with the prefixes `hub_`, `fasting_`, `alerts_`, which must not collide with the shared calendar set).
- The destructive code paths named in §6 under "pinned": the database page's create, import, rename, delete, switch, share, optimize and delete-all; the calendar delete-all; the app reset; the markdown reset / remove / delete-bar; the counters reset / delete; onboarding's import and restore-from-file. They may be wrapped (a confirm before, a loading helper around, a checkpoint before) and never reordered or rewritten; the pinned tests from S0 pass unchanged except where a slice says which assertion it changes and why.
- Fasting: `FastingSchedule.keeps` the one subtraction point; `encode` writing `monthScope: 'allFasts'`; `decode`'s `calendar_fasting_weekdays` seed read-only with `''` ≠ null; `maxExceptionDates` 200; `kFastingTitleMaxLength` 120 and `kFastingDescriptionMaxLength` 500; the two sheets' live-apply contract; the palette prewarm before the style sheet.
- Alerts: seeds ship as `none` (opt-in, the owner's 2026-10-29 answer); the sound sheet's reconcile after a change; the test alarm's permission refresh first; the notice-lead range 0–1440 stored in minutes; the volume floor constant.
- Backup: `'version': 7` and the allowlist as it is (N97 is §9); export stamps, import preserves.
- The launch gate (`main.dart:820`), `setOnboardingCompleted`, `DatabaseManager` import and `setActiveDatabaseName`, the raw `'active_database'` key read before the database opens.
- The persisted stack blob's kind names already in use; the drawer's developer unlock gesture; the permissions prompt flow (`PermissionService`, the prompt dialog, the resume refresh).
- The calendar's panel idiom, the alerts hub's digest group, the guide's lessons and sandboxes, every QA flow under `tool/qa/flows/calendar/` and `alerts/` (updated where a changed screen requires, in the same slice).

**Deliberately changes**

- The drawer's rows (D1, D10); the hub (D2); the navigation contract, the reopen mechanism's retirement, the new kinds, the dedupe, arrow-only settings bars (D3); the kit's look, the search field, the sliders, the bar (D4); the alert and fasting pages and the single rows left behind (D5, D6); Calendar settings' title, first section, merged cards, the reset removed, the fold re-read (D7); the database fixes (D8); onboarding's scroll and plural (D9); Language and Theme as hub rows (D11); the how-to doors and the `setup` topic (D12); ids and flows (D13); suites (D14); the wording of N99, N105, N109–N111, N119, N121 / N153, N148.

## 6. Facts from the tree

Re-grep before editing; lines are from 2026-10-30. The inventory table (§2.2)
holds each page's reach, kind and suite; the defect table (§2.3) each
defect's line. In addition:

- **Bootstrap keys** (the §1 pre-S2 step, grepped 2026-10-31 — the keys read before any settings UI exists, which no slice may rename, re-default or move): `'active_database'`, a raw `SharedPreferences` string read by `DatabaseManager.getActiveDatabaseName()` (`database_manager.dart:13, 43-45`; `main.dart:592`) before the database opens; `SettingsKeys.onboardingCompleted` through `isOnboardingCompleted()` (`main.dart:684`), the launch gate; `SettingsKeys.locale` and `SettingsKeys.themeMode`, read straight off `db.userSettingsDao` by `AppSettingsBloc` (`app_settings_bloc.dart:82-84`) on `LoadAppSettings`, before the first `MaterialApp` frame (`main.dart:757, 789-790`); `SettingsKeys.restoreLocationMode` and `SettingsKeys.lastLocationStack` through `AppNavigator.restoreLastLocation()` (`app_navigator.dart:1069-1073`), after the first frame. `lib/core/di/injection.dart` reads no setting.
- **Corrected by S0's contract test (2026-10-31):** opened from the drawer, the arrow raises the drawer again on **seven** pages — App settings, Databases, Sharing and Counters through `_openSettingsPage`, Permissions through `fromDrawer: true`, Markdown shortcuts and Developer options through `popsToDrawer: true` — and only Calendar settings and Alerts land beneath; a *restored* page raises it for the four `reopensDrawerOnPop` kinds only. An unknown kind name in the stored blob **truncates** the stack at that entry today (`NavDestination` decoding), where §4.3 wants it dropped and the rest kept — S2 changes `decodeStack`. `nav-back` exists only inside `LeadingNavPair`: a bar with `showMenuButton: false` (Calendar settings, Alerts) draws the AppBar's implied arrow with no id.
- Drawer: `app_drawer.dart` `_openSettingsPage` 76-86, group label 88, rows 123-283 (Calendar 123-165, Notes 168-207, App 209-283), avatar push 441-445, permissions row 470-485, `_buildMenuItem` 524, About 587-594, language dialog 611-617, theme dialog 633-638, developer unlock taps ~60-75.
- Navigator: `app_navigator.dart` `SettingsResult` 43, `push` 79-91, `toSettings` 431, `toDatabaseSettings` 423, `toSyncSettings` 439, `toCounterManagement` 460, `toCalendarGuide` 596, `toCalendarSettings` 590, `toAlerts` 622, `toPermissions` 854-866 (the dedupe pattern), `toCalendarCategories` 870, `toCalendarAppearance` 882, `toEventTemplates` 890, `toVocabularies` 898, `toCounterPerNote` 902, `toDeveloperOptions` 909, `toShortcutEditor` 913, `toMarkdownColors` 932, `restoreLastLocation` 960, the reopen branch 986-1004, `_pageFor` 1092-1126; `nav_destination.dart` kinds 19-38, `reopensDrawerOnPop` 48-54, the stamp 103; `navigation_history_service.dart:186-193` records the stamped prefix only.
- Bars: `unified_app_bars.dart` `UnifiedAppBar.settings` 58 and the gradient 79-86 / 117, `SettingsAppBar` 431-446, `_buildLeading` 484-492.
- Kit: `settings_section_list.dart` entry 15-48, section 51-75, style 77, list 91-120, `_SectionCard` 235 (card 347-351, radii 262, headings 285-289, header row 295-304, row text 385-391, id node 401-404); `settings_search_field.dart` 54-93; `slider_setting_row.dart` 23-32, 52, 68-71, 113-121; `settings_search.dart` 65-72, 104-153; collapse persistence `settings_service.dart:1506-1529`; `app_theme.dart:168-172` the scaffold ground.
- Calendar settings: sections 393-1060 (fasting 640-770 with its loads 128-165 and prewarm 140-145; alerts 856-1060; `_permissionsTile` 1067; `_scheduleTestAlarm` 1213; delete-all 1260-1288; the reset 1250-1256 and 1290-1345; `_YieldingTile` 1415-1570); the fold-set comment 68-72 and the re-read 575-577; title 323-326.
- App settings: `_choiceRow` 687-750, `_sliderRow` 776-801, the reset 830-905, auto-save row 477-479, the unit 489, the drawer drag 170.
- Appearance: tint-conflict row 396-398 and 412, week start 731-741 (`:741` the dropdown), reset 886.
- Databases: info 87-104, 345; create / import / rename / switch 561-811 (switch 787-811); share 951-987; delete-all 1039-1083.
- Onboarding: layout 30-80, `_importBackup` / `_restoreFromDatabaseFile`, the plural 215-216; launch gate `main.dart:820`.
- Alerts hub: bar 388-389, body 421-630, digest group 632-700, banners 753-763, rows 776 / 961 / 1102 / 1281, empty state 1339.
- Guide: hub `calendar_guide_page.dart` (search 95, rows 148-168, `_HubRow` 335), topics `calendar_guide_content.dart:133-143`, `setup` rows (grep `setup-`), `calendar_guide_topic_page.dart` 258 lines; restore `app_navigator.dart:1123`.
- Fasting models and sheets: `fasting_schedule.dart` 49-110 (`keeps` 89-110), 173-218 (`encode` / `decode`); `fasting_appearance.dart` 8, 69-107; `fasting_schedule_sheet.dart` 28-45, 211-441; `fasting_style_sheet.dart` 33-51, 146-370; `fasting_calendar.dart:225`.
- Alert settings: `settings_keys.dart` 596-674; `alert_constants.dart:205-236`; `alert_editor_sheet.dart` 68-117; `alert_sound_sheet.dart` 57-72; `alert_permission_check.dart:52`; `permission_service.dart:120`.
- Pinned in S0 (the paths a later slice edits under a test): `database_settings_page.dart` `_createDatabase`, `_importDatabase`, `_renameDatabase`, `_deleteDatabase`, `_switchDatabase`, `_shareDatabase`, `_optimizeDatabase`, `_performDatabaseDeletion` (561-1083); `calendar_settings_page.dart` `_confirmDeleteAllEvents`, `_resetToDefaults` (1260-1380); `settings_page.dart` `_resetToDefaults` (830-905); `markdown_settings_page.dart` reset / remove-custom / delete-bar (259-271, 635-672); `counter_management_page.dart` reset / delete (547-575); `onboarding_page.dart` `_importBackup`, `_restoreFromDatabaseFile`.
- Retire list (deleted when the last reference is gone, grepped): `SettingsResult`, `popsToDrawer`, `reopensDrawerOnPop` and the restore branch that reads it, `DrawerHostRegistry.openTopDrawer` if nothing else calls it, `UnifiedAppBar.settings`' gradient, the kit's drawn section icon, `_YieldingTile` and `_choiceRow` in their pages (moved), the calendar reset and its strings, the drawer's chip decoration and its 100 ms delay, the About literals, `calendarSettingsRow` / `Desc`, the seven drawer rows that moved.

## 7. Slices

Each slice ends with the gate (`verify`): `dart analyze lib test` clean, the
whole `flutter test` once, `flutter gen-l10n` with `untranslated.txt` empty
when an ARB changed, the must-not-change list re-read against the diff, the
pinned suites green. Nothing red carries over; every slice is shippable on
its own.

- **S0 — safety net.** The pinned suites for every path in §6 "pinned" (fakes for `DatabaseManager`, `BackupService`, the share, `SettingsService`); smoke suites at de 2.0 on 360 × 780 for the eight pages without one (D14); the navigation contract test written against today's behaviour (it is rewritten in S2, and the diff is the proof of what changed); a `settings` QA fixture and flow suite (`tool/qa/flows/settings/`: open each drawer settings row, back, restore after relaunch) against today's drawer. No visual change.
- **S1 — the kit.** §4.4 in its four files; goldens regenerated; `settings_section_fold_test` extended; the `meetsGuideline` run; the `design-reviewer` over the hub-to-be's siblings (App settings, Calendar settings, Permissions, Developer options) in light / dark, en / de, 1.0 / 2.0.
- **S2 — the hub, the drawer, the contract.** §4.1, §4.2, §4.3, D10, D11, S16, S17's drawer and hub ids, S26; the contract test rewritten; the `settings` flows updated; the `design-reviewer` over the drawer and the hub.
- **S3 — alert settings.** §4.5, the hub's ⚙, the single row on Calendar settings, the wording; `alert_settings_page_test` (the moved rows' behaviour re-pinned from the calendar settings suites, de 2.0, ids); flow `calendar/16_alert_defaults` and `alerts/00_test_alarm` updated to the new path.
- **S4 — fasting.** §4.6, the single row on Calendar settings, the wording, disabled-not-hidden; `fasting_settings_page_test`; flows `19_fasting_schedule` and `20_fasting_style` updated; the guide's fasting lesson re-checked (its sandbox is untouched).
- **S5 — Calendar settings and App settings.** §4.7 and §4.9's first two bullets; the calendar settings suites updated (the reset's tests become "there is no reset"; the delete-all test gains the failure case); `calendar_settings_golden_test` regenerated.
- **S6 — the rest of the pages.** §4.9's remaining bullets (databases, sharing, permissions, markdown settings and sub-pages, onboarding, developer options), each under its S0 suite; the WAL checkpoint as `DatabaseManager.checkpoint(name)` with a DAO-level test.
- **S7 — the how-to's, the device pass, the docs.** §4.8; `qa-runner`: the `settings` suite, then the calendar and alerts suites, then the matrix (dark, de, 2.0, 360 × 780 and 412 × 915) over the drawer, the hub, every settings page, the two new pages, the guide's `setup` topic; `qa errors` clean. Docs: this record's status line; `docs/ui-language-adoption-roadmap.md` §3 decisions 1 and 5 and its §7 status row; `anta-context/references/` for settings and navigation; `ui-language/references/` for the kit's new members and the arrow-only rule; `calendar-events/references/subsystems.md` for the two pages; `docs/calendar-guide-page.md` for the `setup` change; the retire list grepped to zero.

### 7.1 As built

- **S0, 2026-10-31** (four implementer runs in sequence, one reviewer; step 1 of §1's merged order, beside the categories record's S0). **Pinned suites**: `test/widgets/database_settings_page_test.dart` (19 — create, import of a SQLite file and the refusal of a non-SQLite one, rename with the active name following, delete, switch writing `'active_database'` *before* the restart dialog with no way back (S7, today), share handing the live `.db` path to the share channel, optimize, delete-all emptying the seeded tables, every cancel path; the real `DatabaseManager` over a temp directory with the `path_provider` channel mocked, the exit-app and share channels recorded), `onboarding_page_test.dart` (11 — start fresh with the holiday profile by language, a v7 JSON backup confirmed / cancelled / rejected, a SQLite file restored into `phone_backup` with the restart dialog, an unreadable file), `counter_management_page_test.dart` (5 — reset and delete read from the DAO, tombstones included), `test/pages/markdown_settings_destructive_test.dart` (6 — Reset restores the built-ins and **keeps the customs**, today's behaviour; Remove custom; Delete bar; the store re-read through a fresh service), `settings_page_reset_test.dart` (2 — ten keys back to `SettingsKeys.default*`), `calendar_settings_reset_test.dart` (2 — the reset wipes the fasting schedule, the traditions, the suppressed holidays and the alert values, S1's data loss pinned until S5 removes the reset, while the appearance page's keys survive). **Smoke suites** (D14) for the eight pages: the pages above plus `sync_settings_page_test.dart`, `developer_options_page_test.dart`, `test/pages/note_bar_assignment_page_test.dart`, `note_money_currency_page_test.dart`, `vocabulary_editor_page_test.dart`, all with Roboto loaded; today's defects pinned by name as the state the later slice flips: onboarding overflows 116 dp at de 2.0 on 360 × 780 (S3), the per-note pages' row menus overflow by 94 and 130 px and the databases row menu on "Zu dieser Datenbank wechseln" (S6), Sharing's failed-sign-in title collapses to 0 dp beside its Retry button (S5), developer-options Reset deletes the stored row — unlock flag included — with no confirm, the vocabulary editor drops typed edits on back with no prompt. **Ids** (D13): seven drawer rows (`drawerCalendarSettings`, `drawerMarkdownShortcuts`, `drawerCounters`, `drawerSharing`, `drawerLanguage`, `drawerDeveloperOptions`, `drawerAbout`) and nine bar anchors (`settingsBar*` for App, Calendar, Alerts, Markdown, Counters, Sharing, Databases, Developer, Permissions) through a new `SettingsAppBar.identifier`, whose `_identifiedTitle` keeps the heading and route-naming flags on the labelled node while the bar passes `excludeHeaderSemantics` so `AppBar`'s own flag-only wrapper leaves no unlabelled heading beside it (the reviewer's semantics dump found that second node; the contract test now pins exactly one labelled heading per page); a bar without the menu button draws its implied back arrow itself under `SemanticsIds.navBack`, only where `AppBar` would have drawn one, popping `null` as before. **The contract test** `settings_navigation_contract_test.dart` (50 after the review: the two §4.3 deep links added at the navigator level over a stand-in opener — Calendar settings lands back with no drawer; Counters lands back but still returns `openDrawer`, which the editor ignores) corrected two of §6's facts, now in that section; S6, S15 and S26 confirmed. **The `settings` QA suite** (`tool/qa/flows/settings/`, 13 flows): the drawer, each row's arrow-back and system-back (today's asymmetry), the three dialogs, restore after a bare `relaunch` for the seven stamped pages and the unstamped Markdown shortcuts; every tap is by id, the three dialogs are read by `expect` text because they carry no ids (S2's). **Review** ("ship after fixes", all fifteen applied): the calendar delete-all gained its confirm (tombstones through the DAO, the count re-read) and cancel pins; the app-settings reset pin covers all 21 keys and a survivor; the calendar reset pin seeds every key it asserts (the reset stores the sound as `system:default` where the shipped value is `''` — compared decoded); the optimize pin seeds and deletes ballast past the WAL's auto-checkpoint so the vacuum provably shrinks the file; the databases robot swallows menu overflows only in the known-overflow pin, which names the "Zu dieser Datenbank wechseln" entry; the share's failure path (the page pops itself, S4), a per-note counter reset and the single-shortcut delete are pinned too. **Found for later slices**: onboarding writes `onboarding_completed` into the database being left, not the restored one (S6); errors surface as raw `'$e'`; the counter reset's confirm reads "Save"; the per-note bar page shows a literal `'Untitled'` and searches notes under "bars" wording; a `showMenuButton: true` settings bar over a Scaffold without a drawer draws a lone arrow with no id. The suite grew by 132 tests. **First device pass** (2026-10-31, `anta_qa_2` on emulator-5558 — the owner's emulator held 5556): 11 of 13 green, the bare mid-flow `relaunch`, the 2 s settle before it and `tap id:nav-back` on the implied arrow all held; `00_drawer` and `09_dialogs` went red on `scroll-to` — without `--in`, the harness swipes inside the first scrollable a dump lists, which in the drawer is the header's avatar block, so the list never moved. Fixed by an id on the drawer's list (`SemanticsIds.drawerList`, a `Semantics(identifier:)` around the `ListView`, as the rows carry theirs) and `--in id:drawer-list` on every `scroll-to` in the suite; the two flows' re-run is owed with the next device pass.

## 8. Definition of done

1. Every setting reads and writes the same key with the same default as before (the S0 pins); every destructive action round-trips through its pinned test; the share includes the checkpointed data (a DAO test writes, checkpoints, reads the main file).
2. From the drawer: Settings → any row → back → the hub → back → the page the drawer was opened over; by arrow and by system back alike; the contract test and the `settings` flows prove it on a device.
3. Every restorable kind restores to the right stack after a relaunch (`settings` flows with `relaunch`); an unknown kind name in the blob is dropped, not fatal.
4. Light and dark; en, de, ro; text scale 1.3 and 2.0 on 360 × 780 and 412 × 915 with no clipped label, no mid-word break and no overflow on the drawer, the hub, every settings page, both new pages and onboarding.
5. Every control 48 dp (the search ✕, the handle rows, the hub rows, the sliders' thumbs' rows); every icon button has a tooltip; every slider announces its value; section headers are headings; `meetsGuideline` green on the hub, App settings, Alert settings and Fasting.
6. Nothing hidden where it should be disabled: the auto-save interval, the fasting look rows, the great-fasts switch, the tint-conflict row.
7. Every string in all three ARBs, `untranslated.txt` empty, no literal unit, size or version in a widget.
8. Every drawer row, hub row, settings bar and key control has a `SemanticsIds` entry; the `settings` flow suite walks them all.
9. The eight pages that had no suite have one; the two new pages ship with suites; the kit's suite covers the heading, the target sizes and the slider semantics.
10. Nothing on the retire list is referenced (grep); no number on the kit, the hub, the drawer rows or the two new pages is a literal or comes off `AppSpacing`.
11. The guide's `setup` topic describes the hub; the three how-to doors open it; onboarding's hint line is there.

## 9. Deferred

- **Cross-page search that opens a page at its section** (D2): every kit page accepts an `initialSectionId` that expands and scrolls to the section; the hub's keywords become `(page, sectionId, titles)` triples. Additive; after the hub ships.
- **Inline fasting schedule on the page** (D6): the sheet's chip rows as page groups; needs the sheet's constant-height and scope-hint rules re-specified for a scrolling page, and the guide's fasting lesson keeps using the sheet.
- **Onboarding's import through `ImportExportBloc`** (S9, D9): the bloc assumes an open database and an injected `BackupService`; the first-launch path is pre-DI. Do it when the bloc gains a pre-database mode, under the S0 smoke suite.
- **Databases page on the kit** (S20, D8): one `Card` at a time, each under its pinned test, after S6 proves the fixes.
- **Markdown settings and its sub-pages on the language** (S20): 2.6 k + 2 k lines with their own menus, FABs and dialogs; a rework of its own with its own record.
- **The alerts hub's `Card` rows** (S20) and N142's empty state ("Go to calendar"): the hub is the alert surfaces' territory (`docs/alert-surfaces-redesign-roadmap.md`).
- **Developer options storage** (S24): move `'dev_options'` under `SettingsService` with a one-time read of the old key; needs the `DatabaseLifecycle` reset contract checked.
- **The drawer's header and master decision 5**: untouched here; the plain rows are the owner's call once seen.
- **The newcomer items outside settings** listed in §2.4's last sentence: holiday profiles by locale (N91 / N92, a data decision), the built-ins (N94, the categories record §9), the backup allowlist (N97, a backup-format change the owner must approve), and the alert behaviours N125–N141 (the alert surfaces' records).
- **A guides hub** when a second how-to exists (notes, money, counters, backup); the drawer row and the hub section are its slots.
- **`SettingsService` setters' notification semantics** and the bootstrap key list: the review did not reach them; §1 makes the implementing session list the bootstrap keys before S2.
