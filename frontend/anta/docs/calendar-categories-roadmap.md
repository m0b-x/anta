# Calendar categories — design record (2026-10-30)

**Status: IN PROGRESS** — the build started 2026-10-31 in the interleaved
session the settings record's §1 describes (its merged eleven-step order
governs; this record's S0 is step 1, S1 step 2, S2 step 5, S3 step 6, S4
step 11); the Report record reads COMMITTED (`350973b8`). Proposed
2026-10-30 from a brainstorm ("why is there no category page in the
hamburger menu?") and a read-only investigation of the categories subsystem
(an Opus 5.5 reviewer, 21 findings K1–K21 and 10 app-wide items A1–A10,
§2). Decisions A–H are taken (§3): on 2026-10-31 the owner said every
decision is already taken, so each stands as recommended. The mock:
https://claude.ai/artifact/SGdohQ4zqp3RvA2DCEe93r — the page light and dark
(a row menu open), the delete sheet, German at text scale 2.0, the drawer's
Calendar group and the calendar's ⋮ with the new entries, the decisions and
the must-not-change list under the boards.
Session memory: `calendar-categories-rework-2026-10-30`.

Contents: §1 How to run this · §2 Why (§2.1 the observation, §2.2 the
investigation K1–K21, §2.3 app-wide items A1–A10) · §3 Decisions · §4 The spec
(§4.1 entry points, §4.2 the page, §4.3 the delete sheet, §4.4 the editor,
§4.5 service and model, §4.6 the guide, §4.7 copy) · §5 Behaviour · §6 Facts
from the tree · §7 Slices · §8 Definition of done · §9 Deferred.

## 1. How to run this

The prompt for the implementing session (Opus 5.5 at `high`; this record was
written on Fable 5.1 and that session ends here):

> Load `calendar-events`, `calendar-ui`, `ui-language`, `l10n`, `verify` and
> `delegation`. Open `docs/calendar-categories-roadmap.md`: read §3 (the
> owner's answers, by then D-numbered), §5 and §6 whole, then only the slice
> you are on in §7 and its part of §4. If `git log` says the status line is
> stale, correct it first. Do not start S2 before
> `docs/calendar-report-roadmap.md` reads COMMITTED: both reworks write
> `form_rows.dart`, `semantics_ids.dart` and the three ARBs, and the Report
> groups events by category with the row shapes S2 introduces. S0 and S1 may
> run earlier, in a gap between Report commits, because they touch none of
> those files except the ARBs (three keys) and `semantics_ids.dart` (three
> ids). Run the slices in order, one `implementer` and one `reviewer` per
> slice. The `designer` specifies the page before S2 — it renders the current
> page first and measures "Măsurătoare" (ro) and "Familienbesuch" (de) at
> text scale 2.0 on 360 × 780 — and the `design-reviewer` checks the built
> page after S2 and the sheet after S3. The `qa-runner` runs the device pass
> at the end of S5. The whole `flutter test` runs one at a time, from the
> lead, never beside a QA run. Do not commit; at every slice boundary report
> the number of uncommitted files and a ready-to-run commit (paths and
> message). Record each slice's as-built notes in §7.1 and anything cut in §9.

**Running with the settings rework (the owner's ask, 2026-10-30).** This
record and `docs/settings-rework-roadmap.md` run in one session,
interleaved, one slice at a time; the merged order is in that record's §1.
Two consequences for this record: S1 drops its drawer row and ⋮ item,
which the settings record's S2 builds together with the new drawer (A1
stands; the owner of the drawer file is that slice); and S4, the guide
lesson, runs together with the settings record's S7. Everything else here
is unchanged.

## 2. Why

### 2.1 The owner's observation

The owner felt that "the only way to create categories is when creating an
event". A management page exists (`lib/pages/calendar_categories_page.dart`)
but it is three taps deep under Calendar settings, whose drawer subtitle
("Week start, holidays, appearance") never names it. The Report feature,
built the same day, groups everything by category, which makes categories a
first-class concept the user reasons about, not a settings detail. The owner
asked for: a category page reachable from the hamburger menu, a lesson in
the calendar guide, and "a modern display mode of categories, easy ways to
edit/add/delete and rearrange them", with the focus on quality.

### 2.2 The investigation (2026-10-30; read-only, no runtime proof)

Every finding rests on quoted code or strings; none was reproduced at runtime
because the Report implementer owned the tree. CONFIRMED means the quoted
path settles it; PLAUSIBLE needs a render or a run. Severity: 4 blocks a
user's goal or loses data, 3 a wrong result the user cannot explain, 2 a
visible inconsistency, 1 a nit. "Fix" names the slice of §7.

| Id | Sev | Finding | Where | Fix |
| --- | --- | --- | --- | --- |
| K1 | 4 | Deleting a category does more than its dialog says and none of it can be undone: the dialog counts events only (`app_en.arb:554`, `:533`), while one transaction also tombstones the category's alerts and reassigns its templates (`calendar_category_dao.dart:226-236`); the moved events then inherit Other's category alerts (`event_alerts.dart:157-182`); allowlists naming only the deleted id — overview views, digests, the agenda, the Report scope — list nothing afterwards (`overview_views_table.dart:21-23`); the snackbar is a bare "Category deleted" with no undo (`page:255`). CONFIRMED. | page, DAO | S3 (the delete sheet, C) |
| K2 | 3 | Every new event and template defaults to the built-in `gym` even when Gym is archived (`calendar_event.dart:21`, `event_editor_sheet.dart:771`, `event_template_editor_sheet.dart:176`); there is no default-category setting; the constant's doc comment names it as the reassignment target, which `kFallbackCategoryId` is (`category_service.dart:474`). CONFIRMED. | model, editors | S1 (D) |
| K3 | 3 | "Hide" means two things: the page's eye archives (events still render, count and ring — `effectiveFor` has no `isHidden` check, `event_alerts.dart:157-166`), the funnel's `hiddenCategoryIds` hides events; the guide uses the word for both (`app_en.arb:8474`, `:8545`). A user taps the eye to declutter the grid and nothing changes. CONFIRMED. | page, guide | S2 + S4 (B) |
| K4 | 3 | An event whose category id is unknown draws in the hard-coded grey Other (`calendar_categories.dart:152` `_byId[id] ?? fallback`, the const at `:84-91`), not the user's recoloured Other, while inheriting Other's alerts; Other's row count misses orphans (`calendar_event_dao.dart:262-274`); the stale id survives every edit (`event_editor_sheet.dart:771`). Orphans arise from a sync race (B saves into a category A deleted) or a categories-only restore. CONFIRMED. | cache | S1 |
| K5 | 2 | The page does not speak the UI language: `Card` + `ListTile` (`page:544-548`) where a list page takes the browser's content rows; raw `PopupMenuItem`s with a hand-built row (`:608-664`) where the rule is `FormMenuChoiceItem`; Delete hidden on built-ins (`:647`) against "disabled, never hidden"; literals `EdgeInsets.fromLTRB(12, 12, 12, 8)` (`:391`), `(12, 4, 12, 24)` (`:416`, `:424`), `opacity 0.5` (`:543`), `_bellSize = 24` (`:519`); ids only for `categoryAdd` and `categoryRow(id)`, none for the eye, the ⋮, the menu items, the search field or Sort A–Z, so no device flow can archive, reorder or delete. CONFIRMED. | page | S2 |
| K6 | 2 | At text scale 2.0 on 360 the name column is about 72 dp (handle 24 + 8 + avatar 40 leading; bell 24 + eye 48 + ⋮ 48 trailing) so names break mid-word; the guide's sandbox dropped its subtitle for this reason (`calendar_guide_try_categories.dart:202-204`); the suite asserts only no exception and equal row heights, in English (`calendar_categories_page_test.dart:359-367`, `:633-654`). PLAUSIBLE — probe: pump at `Locale('de')`, `TextScaler.linear(2.0)`, 360 × 780, count the lines of `find.text('Wettkampf')`. | page | S2 (the designer measures) |
| K7 | 2 | The shared drag handle is a 24 dp target (`settings_reorder.dart:28-37`, an `Icon(size: 24)` in a `ReorderableDragStartListener` with no padding); the rule is 48. The long press anywhere on the row (`page:433`) softens it. CONFIRMED. | shared chrome | S2 |
| K8 | 3 | The page is three levels deep and nothing points to it: the only route is Calendar settings → Categories (`calendar_settings_page.dart:621-642`, the one caller of `AppNavigator.toCalendarCategories`); the drawer subtitle omits it (`app_en.arb:3530`); the guide's categories topic has no "where" row, unlike fasting's `fasting-where` (`calendar_guide_content.dart:587-595`). CONFIRMED. | drawer, menu, guide | S1 + S4 (A) |
| K9 | 2 | The guide's practice list differs from the real page: ⋮ with Edit and Delete only (`calendar_guide_try_categories.dart:20`, `:148-170`) against four items; Delete disabled on a built-in against hidden; no confirm (`:113-119`) against a dialog; no handle, count, bell or built-in caption; a bottom action row to create (`:271-276`) against a filled + in the bar; `FormPickerRow` against `ListTile`; the coach line "Tap a category in the list…" (`app_en.arb:8176`) names no list. CONFIRMED. | guide | S4 |
| K10 | 2 | The single-pick category sheet is titled "Type" (`category_picker_sheet.dart:280`, `l10n.eventType`) while the row that opens it says "Category" (`event_editor_sheet.dart:3009`). CONFIRMED. | picker | S1 |
| K11 | 3 | The category editor loses a typed name and drafted alerts with no question: `PopScope(canPop: _written == null)` (`category_editor_sheet.dart:507-511`) lets back, the scrim and a drag discard everything; the suite pins it (`category_editor_sheet_test.dart:373`). The language gives typed-text forms `confirmDiscard` when dirty. CONFIRMED. | editor | S3 |
| K12 | 2 | The 40-character limit can be bypassed from the picker's "Create "…"" path: the query becomes `initialName` (`category_picker_sheet.dart:363-365`), `TextField.maxLength` does not truncate initial text, `_canSave` checks only non-empty (`category_editor_sheet.dart:233-237`), the service does not clamp (`category_service.dart:330`). PLAUSIBLE. | editor | S1 |
| K13 | 2 | Sort A–Z overwrites the manual order with no confirm and no undo, and the result syncs (`page:291-303`). CONFIRMED. | page | S3 (H) |
| K14 | 1 | Delete can report success when nothing was deleted: `deleteCategory` returns void on refusal or no-op (`category_service.dart:468-487`) so `_guarded` returns true and "Category deleted" shows (`page:247-255`); a pull that tombstones the row during the dialog, or a built-in id synced with `isBuiltIn = false` (the decode default, `calendar_categories_binding.dart:64`, which also makes `labelOf` show the raw English name and the editor offer a rename). PLAUSIBLE. | service, sync | S3 (the sheet reads the DAO's bool) · the decode default is §9 |
| K15 | 2 | An archived category's events stay listed but its name is no longer offered to search (`upcoming_agenda_view.dart:397-400`, `calendar_overview_page.dart:668-671`; pinned by `upcoming_agenda_search_test.dart:338-341`). CONFIRMED, deliberate. | agenda, overview | §9 |
| K16 | 2 | An archived category's alerts keep firing (see K3); the page dims its bell with the row and says nothing. CONFIRMED. | alerts | S4 says so (F) |
| K17 | 1 | A restore keeps the archive's `sortOrder` without renumbering (`category_service.dart:564-566`); a built-in missing from the archive is seeded at its catalogue index (`:236`), which can collide with a custom's slot; ties fall to id until the next drag. PLAUSIBLE. | import | §9 |
| K18 | 1 | On a synced device a restore hard-wipes categories without tombstones (`calendar_category_dao.dart:323-327`, "a restore is never a merge"), so peers keep what the restore dropped. PLAUSIBLE, by design. | restore, sync | §9 |
| K19 | 1 | The built-in catalogue is fitness-specific — Gym, Cardio, Rest, Holiday, Competition, Measurement, Mobility, Birthday, Other (`calendar_categories.dart:30-64`) — and cannot be deleted, only archived; "Holiday" collides in name with the public-holidays layer. CONFIRMED. | catalogue | §9 |
| K20 | 1 | A new category appears at the bottom with no scroll and no feedback: `_create` only refreshes (`page:207-211`), the create appends at max + 1 (`category_service.dart:325`). PLAUSIBLE. | page | S2 |
| K21 | 1 | Four glyphs stand for "category": `palette_outlined` on the settings entry (`calendar_settings_page.dart:635`), `category_rounded` on its section and in the guide, `label_outlined` in the event editor (`event_editor_sheet.dart:3007`), `category_outlined` in the digest editor (`digest_editor_sheet.dart:501`). CONFIRMED. | four files | S1 |

Facts the investigation settled, for the spec: every category write stamps
the CRDT fields (create `calendar_category_dao.dart:141-151`, update and
archive `:171-193` with a version bump and a no-op guard, reorder `:343-368`
dense 0..N-1 under one HLC skipping unchanged rows, seed `:63-102`, import
`:116-139`); delete is a soft tombstone (`:249-269`); ids are UUID v4
(`category_service.dart:324`); `sortOrder` and `isHidden` ride in export
(`category_service.dart:500`), import (`:564`) and the sync envelope
(`calendar_categories_binding.dart:46`); the backup is `'version': 7`
(`backup_service.dart:133`) and `isHidden` was added without a bump,
defaulting to visible. Archiving removes a category from the choosing lists
only — the picker, both filter sheets, overview options, the digest editor and
the Report's picker, all through `visiblePlus` — never from the grid, the
agenda, the overview, the Report's totals, alerts or digests; an empty
allowlist means "all, archived included" (`event_agenda.dart:416`).
Built-ins cannot be renamed (`category_editor_sheet.dart:405`) or deleted;
they can be recoloured, re-iconed and archived; their stored name is the
English seed and the localized label is never persisted
(`calendar_categories.dart:203-215`). Category alerts show in the editor's
Alerts group (`category_editor_sheet.dart:564-572`, `:659-667`), as the
page's bell (`page:451-453`, `:575-591`), in the event editor's inherited
rows and in the hub; the picker does not show them.

Test gaps (page suite `test/widgets/calendar_categories_page_test.dart`):
no delete taken through to the reassigned events and the snackbar, no
zero-event dialog, no drag reorder (handle or long press), no row tap opening
the editor, no create refreshing the list, no de/ro at 2.0, no 48 dp target
assertion. Editor suite: no `initialName` over 40. Picker suite: no de/2.0.
Service and DAO: no import density, no unknown id while Other is recoloured,
no stale allowlist after a delete. Device flows: only
`tool/qa/flows/calendar/18_category_editor.txt`; nothing archives, reorders
or deletes.

### 2.3 App-wide items in passing (not in this rework's scope)

- A1 `lib/pages/database_settings_page.dart:977` — `SharePlus.instance.share` from a page (the rule is `shareExport`).
- A2 the same page, `:1000` and `:1061` — `AppDatabase.getInstance()` and `deleteAllData()` from a page (layer bypass).
- A3 `lib/pages/note_bar_assignment_page.dart:37-39`, `lib/pages/note_money_currency_page.dart:41-43` — a page calls `db.noteDao.getAllNotes()` (layer bypass).
- A4 `lib/services/backup_service.dart:311` — `shareBackup` calls `SharePlus` directly.
- A5 `lib/widgets/pairing_sheet.dart:183` — `SharePlus` from a widget (a text share; arguably outside the export rule).
- A6 `lib/services/database_manager.dart:13` — a raw `SharedPreferences` key `'active_database'`, probably needed before the database opens.
- A7 `lib/widgets/app_drawer.dart:146-154` — the Calendar settings row has no `identifier` while its siblings do (fixed in S1).
- A8 `lib/models/calendar_event.dart:19-20` — the stale `kDefaultCategoryId` comment (fixed in S1).
- A9 "Other" is written into the delete strings (`app_en.arb:533`, `:554`) instead of the `eventCategoryOther` placeholder the guide uses (gone with S3).
- A10 `TODO`/`FIXME` over `lib` is clean; no `showDatePicker` / `showTimePicker` outside the sanctioned sheets.

## 3. Decisions

Lettered until the owner answers; the recommended option is first in each.
D-numbers are assigned on answering and nothing here is rewritten afterwards
(an amendment appends). All eight are on the mock.

| | Decision | Options | Answered |
| --- | --- | --- | --- |
| A | Where the page lives | **A1** a drawer row after Overview plus a ⋮ item after Alerts, the settings entry stays — the page is reached from the grid when a category is wrong and from the drawer when setting up · A2 the ⋮ item only · A3 the drawer row only | A1, 2026-10-31 |
| B | Hide becomes Archive | **B1** rename the action, the section and the guide line; archived rows keep their counts and their events stay everywhere — the funnel already owns "hide" · B2 keep "Hide", explain it in the guide only | B1, 2026-10-31 |
| C | Delete | **C1** a sub-sheet with the consequences and a Move-events-to row, Other preselected — it is also the merge · C2 keep the dialog, add the consequences text only · C3 C1 plus a separate "Merge into…" menu item opening the same sheet with the target required | C1, 2026-10-31 |
| D | The default category of a new event | **D1** the first non-archived category in the user's order — the seeded order keeps Gym first, so nothing changes for anyone who never reordered, and the order gains a purpose · D2 a "Default for new events" menu item stored as a setting · D3 keep Gym | D1, 2026-10-31 |
| E | Add | **E1** a FAB bottom right, as the calendar's own add button — thumb reach · E2 an "Add category" action row at the end of the list · E3 keep the app-bar + | E1, 2026-10-31 |
| F | Category alerts on an archived category | **F1** keep firing, as today, and the guide says so in one line — no behaviour change · F2 archiving silences the category's own alerts until restore — a data decision | F1, 2026-10-31 |
| G | The row's alert mark | **G1** "Alerts on" in the caption, no bell — costs nothing at 2.0 · G2 keep the bell as a trailing glyph before ⋮ | G1, 2026-10-31 |
| H | Sort A–Z | **H1** stays in the bar's ⋮ behind a confirm that says the manual order is replaced · H2 remove it · H3 keep it unconfirmed | H1, 2026-10-31 |

Answered 2026-10-31: the owner opened the implementing session with "every
decision is already taken (A–H …); do not reopen them", so each row's
recommended option — the first, in bold — is the decision. The letters stay
the identifiers (the settings record's D1–D14 run in the same session and
D-numbers here would collide); the spec's "under A1 / B1 / C1 / D1 / E1 / F1
/ G1 / H1" branches are the ones built.

Changes that need no decision, because the language or a finding settles
them: K4 (orphans resolve to the stored Other), K5 (content rows, form menu
items, no literals, ids), K7 (a 48 dp handle target in the shared chrome),
K10 (the single picker is titled "Category"), K11 (the editor guards a dirty
draft), K12 (`initialName` clamped to the limit), K14 (the delete path reads
the DAO's bool), K20 (scroll to and flash the new row), K21 (one glyph), A7,
A8, A9.

## 4. The spec

### 4.1 Entry points

- **Drawer** (`app_drawer.dart`, the Calendar group): a fourth `_buildMenuItem` after Overview — `Icons.category_rounded`, title `calendarCategories` ("Categories"), subtitle `calendarCategoriesRowDesc` ("Create, order, archive"), `identifier: SemanticsIds.drawerCalendarCategories`, `onTap` pops the drawer and calls `AppNavigator.toCalendarCategories`, as its three siblings do (none of them awaits the push; `reopensDrawerOnPop` stays false for this kind). The Calendar settings row gains `identifier: SemanticsIds.drawerCalendarSettings` and its subtitle becomes "Categories, week start, holidays". Under A2 the drawer row is skipped; under A3 the ⋮ item is.
- **The calendar's ⋮** (`calendar_header_menus.dart:290-327`): a `FormMenuItemRow` "Categories" with `Icons.category_rounded` as the second item, after Alerts and before Export events, `identifier: SemanticsIds.calendarMenuCategories`, calling `AppNavigator.toCalendarCategories`.
- **Calendar settings** keeps its Categories section; its row glyph becomes `Icons.category_rounded` (K21), as does the event editor's Category row and the digest editor's.

### 4.2 The page

Idiom: the browser's content rows (`ContentRowShell`, `ContentSectionHeader`
on `RowMetrics`), the one a list page of the user's own things speaks. Under
the existing bar from `unified_app_bars.dart` (48 dp toolbar, 17 / 500 title
"Categories", a back arrow, a ⋮ holding Sort A–Z), top to bottom:

- **Search** — the existing `SettingsSearchField` (40 dp), present only when the list holds 12 or more categories, archived included (the picker's own threshold); `identifier: SemanticsIds.categorySearch`. While a query is live the list is the filtered, non-reorderable one, `ReorderLockedHint` shows, handles are disabled in place at 38 %, Move to top is disabled in the row menu and Sort A–Z in the bar's — never omitted.
- **Section "IN USE"** (`ContentSectionHeader`, `categorySectionInUse`) over one group of the non-archived categories in `sortOrder`; **section "ARCHIVED"** (`categorySectionArchived`) over one group of the archived ones, drawn only when there is at least one (a section is content, not a control, so it may be absent). An empty "In use" group never happens: Other cannot be archived while it is the last visible category — the service refuses and the row menu's Archive is disabled on it (a new guard, §5).
- **Row** (`twoLineMinHeight` 62, one `MergeSemantics` node, `identifier: categoryRow(id)`): the shared `ReorderHandle` in a 48 × 48 target at the start (`identifier: categoryRowHandle(id)`, `label:` "Reorder {name}"), then `EventAvatar` (radius 20, the category's icon on its colour at `backgroundAlpha`), `RowMetrics.gap` 14, the texts — the name at `titleFontSize` 15 `onSurface`, under it a caption at `secondLineFontSize` 13 `onSurfaceVariant` built from `categoryEventCount(n)` then " · Built in" (`categoryCaptionBuiltIn`) when `isBuiltIn` then " · Alerts on" (`categoryCaptionAlertsOn`) when the category has at least one category alert (G1; under G2 the bell returns as a 20 px `outline` glyph before the ⋮ and the caption drops the segment) — then the ⋮ as a 48 × 48 `FormTrailingButton` with a 20 px `outline` glyph (`identifier: categoryRowMenu(id)`, tooltip `moreOptions`). The divider between rows starts at the text column. A tap anywhere on the row opens the editor (`CategoryEditorSheet.show(initial:)`); a long press lifts the row, as today. An archived row draws its handle, avatar and texts at `disabledOpacity` 0.38 (never 0.5); its ⋮ stays at full opacity.
- **Row menu** — a popup route of `FormMenuChoiceItem`s through `showFormMenu` anchored on the ⋮ (`FormMenuAlignment.end`): Move to top (`vertical_align_top_rounded`; disabled while a query is live or the row is first in its section) · Edit (`edit_rounded`) · Archive / Restore (`archive_rounded` / `unarchive_rounded`; Archive disabled on Other while it is the last visible category) · Delete… (`delete_rounded`, `color: error`; disabled on a built-in, never missing). Ids `categoryMenuMoveToTop`, `categoryMenuEdit`, `categoryMenuArchive`, `categoryMenuDelete`.
- **Bar menu** — Sort A–Z (`sort_by_alpha_rounded`, `identifier: categorySortAz`), disabled while a query is live; under H1 it opens `AppDialogs.confirm` (title `categorySortConfirmTitle`, message `categorySortConfirmBody`, confirm `sort`) before `_persistOrder`.
- **Add** — under E1 a `FloatingActionButton` (`Icons.add_rounded`, tooltip `createCategory`, `identifier: categoryAdd`) and the list's bottom padding is `AppSpacing.fabClearance`; under E2 a `FormActionRow`-shaped "Add category" row as the last row of the page (the content-row idiom has no action row; the implementer adds `ContentActionRow` to `content_rows.dart` as the rework's one new primitive, and this record names it); under E3 the bar's `IconButton.filledTonal` stays.
- **After a create** (K20): the list re-reads, scrolls the new row into view (`Scrollable.ensureVisible`) and flashes it with `ValueChangeHighlight`.
- **Empty search** keeps the field and shows the existing no-matches caption under the group.
- **Text scale 2.0** (K6): the handle and the ⋮ keep 48 dp; the name column is 360 − 2 · `groupInset` − 48 − 40 − 2 · `gap` − 48 ≈ 164 dp; the name wraps at word boundaries to as many lines as it needs and the caption wraps too; the row's height grows with scale, never at runtime. The designer measures the nine built-in names in de and ro and the two long sample names on the mock, and if any single word exceeds the column the spec says what gives (the avatar to a 22 px tinted glyph at ≥ 2.0 is the fallback, never the handle or the ⋮).
- **Retired on this page**: `Card`, `ListTile`, `PopupMenuButton`, the eye `IconButton`, the bell slot and `_bellSize`, the three `EdgeInsets` literals, `opacity 0.5`, the hand-built menu rows. Every number comes from `RowMetrics` / `FormMetrics` / `AppBarMetrics`.

### 4.3 The delete sheet (C1 / C3)

A sub-sheet of the language, content-tall, unguarded: ✕ (`cancel`) · title
`categoryDeleteSheetTitle` "Delete category" · a `FormHeaderTextButton`
"Delete" in `error`. One group: a read row — the category's `EventAvatar`,
its name, a caption "{n events} · {m alerts} · {k templates}" with zero
segments omitted, computed by a new `CategoryService.deleteImpact(id)` that
counts events (`countByCategory`), category alerts and templates for the
id — then a `FormPickerRow` `drive_file_move_rounded` "Move events to"
(`categoryDeleteMoveTo`) whose value is the target's name, Other preselected,
opening `CategoryPickerSheet.pickSingle(selectedId:)` over the visible
categories minus the one being deleted (`identifier: categoryDeleteTarget`);
disabled in place at 38 % when the count of events and templates is zero.
Under the group a `FormCaption` `categoryDeleteConsequences`: "Its alerts are
removed. Saved views, digests and reports that pick only {name} show nothing
until you pick again." Delete (`identifier: categoryDeleteConfirm`) calls
`deleteCategory(id, reassignTo: target)` — the service gains the parameter,
the DAO's cascade already takes it — and pops `true`; the page shows the
existing snackbar only when the DAO returned true (K14). Under C3 the row
menu gains "Merge into…" (`merge_rounded`) opening the same sheet titled
`categoryMergeSheetTitle` with the Move row required (Delete disabled until a
target other than Other is chosen — or any target; the owner's call under
C3). Under C2 the existing `AppDialogs.confirm` stays and its message gains
the alert and template counts and the consequences sentence through
placeholders, `eventCategoryOther` replacing the literal "Other" (A9).

### 4.4 The editor sheet

Stays the Tier 3 sheet (✕ · title · Save, one group, the name in a
`FormTitleRow`, the Icon row, the swatch strip, the Alerts group). Changes:
it becomes a guarded form — ✕, back, system back, the barrier and drag go
through one `_leave()` that asks `AppDialogs.confirmDiscard` only when the
draft differs from `initial` or, for a create, from empty; a clean sheet
leaves silently; `FormSheetFrame` is used only if its docked-bar shape fits,
otherwise the guard alone (`sheet-chrome.md`). `initialName` is clamped to
`kCategoryNameMaxLength` before it reaches the field (K12). The sheet's test
`"a scrim tap returns null and writes nothing"` is rewritten for a clean
draft and a dirty draft. Archive and Delete stay out of the editor (the row
menu owns them), as the `subsystems.md` rule says.

### 4.5 Service and model

- `CalendarCategories.resolve(id)` → `_byId[id] ?? _byId[kFallbackCategoryId] ?? fallback` (K4), with a test that recolours Other and resolves an unknown id.
- `kDefaultCategoryId` under D1 becomes `CalendarCategories.defaultForNewEvent` — the first non-archived category in `sortOrder`, `other` when every category is archived — read by both editors in place of the constant; the constant's comment is corrected (A8); under D2 a `SettingsKeys.defaultCategoryId` and a row-menu item "Default for new events" (radio-checked on the current); under D3 only the comment changes.
- `CategoryService.deleteCategory(id, {reassignTo})` returns the DAO's bool; `deleteImpact(id)` as in §4.3.
- `setHidden(id, true)` refuses when the category is the last visible one (returns false; the page disables the item first).
- `CategoryPickerSheet` single mode is titled `eventCategory` (K10).
- `ReorderHandle` (`settings_reorder.dart`) wraps its glyph in a 48 × 48 target (`TapTargetPadding` or a `SizedBox` with `Center`) — the one shared-chrome change, which every reorderable list inherits (saved filters, saved views, the colour palette); `form_rows_test.dart` and those sheets' suites assert the size.

### 4.6 The guide

In `calendar_guide_content.dart`, the categories topic gains a read row
`categories-where` after its lead, shaped like `fasting-where`: "Open the
menu (☰) and tap Categories, or tap ⋮ on the calendar, then Categories." The
coach line for hiding becomes "Tap the three dots on a category, then
Archive: it leaves the pickers; its events and alerts stay." (F1; under F2
"…its events stay and its alerts pause."). The delete coach line keeps its
`{other}` placeholder and gains "or choose where its events go". The sandbox
(`calendar_guide_try_categories.dart`) mirrors the real row: handle, avatar,
name, caption, ⋮ with the four items, Delete disabled on a built-in, Archive
moving the row to an Archived section in the sandbox, the add control of E;
it never persists, as today. Its composed captions are re-measured at de 2.0
(the 2026-10-29 lesson: 390–546 px slots).

### 4.7 Copy (en; de / ro at implementation, every key in all three ARBs)

`calendarCategoriesRowDesc` "Create, order, archive" · `calendarSettingsRowDesc`
→ "Categories, week start, holidays" · `categorySectionInUse` "In use" ·
`categorySectionArchived` "Archived" · `categoryArchive` "Archive" ·
`categoryRestore` "Restore" · `categoryCaptionBuiltIn` "Built in" ·
`categoryCaptionAlertsOn` "Alerts on" · `categoryReorderLabel` "Reorder
{name}" · `categoryDeleteSheetTitle` "Delete category" ·
`categoryDeleteMoveTo` "Move events to" · `categoryDeleteImpactAlerts`
"{count, plural, =1{1 alert} other{{count} alerts}}" ·
`categoryDeleteImpactTemplates` "{count, plural, =1{1 template} other{{count}
templates}}" · `categoryDeleteConsequences` "Its alerts are removed. Saved
views, digests and reports that pick only {name} show nothing until you pick
again." · `categorySortConfirmTitle` "Sort categories A–Z?" ·
`categorySortConfirmBody` "Your own order is replaced." · `sort` "Sort" ·
`categoryMergeSheetTitle` "Merge into…" (C3 only) ·
`categoryDefaultForNew` "Default for new events" (D2 only) ·
`calendarGuideCategoriesWhere` and the two reworded coach lines. The old
`hide` / `show` keys stay for their other callers; the delete dialog's two
messages are retired under C1.

## 5. Behaviour

**Must not change**

- The `calendar_categories` table and columns; no migration; the backup stays `'version': 7` with `sortOrder` and `isHidden` in the blob; export copies, import preserves.
- Every write stamps `hlcTimestamp`, `deviceId`, `version`; delete is a soft tombstone; events, templates and alerts are reassigned or tombstoned in one transaction under one stamp (`tombstoneCascade`); the sync envelope of categories (`calendar_categories_binding.dart`).
- `sortOrder` dense 0..N-1 over the full list, archived rows included; unarchiving restores the old position; a reorder writes once under one HLC and skips unchanged rows.
- Built-ins keep their ids, cannot be renamed or deleted, can be recoloured, re-iconed and archived; `kFallbackCategoryId == 'other'`; Other is never deletable.
- `CategoryPickerSheet.pickSingle(selectedId:) → String?` and `pickMulti(selected:) → Set<String>?` over `visiblePlus(initialSelection)`, searchable above 12 rows, never autofocused, "Create category" last; `pickMulti` never collapses empty; every caller owns both halves of its inversion.
- `CategoryEditorSheet.show({initial, initialName}) → CalendarCategory?` writes inside the sheet before the pop; the built-in's name is a read row; the duplicate guard is soft.
- `visiblePlus(keep)` identity-stable when nothing archived is kept; archiving removes a category from the choosing lists only; an empty allowlist means all, archived included, in the agenda, the overview, digests and the Report.
- `SemanticsIds.categoryAdd` and `categoryRow(id)`; `NavDestinationKind.calendarCategories` and its restore; `reopensDrawerOnPop` false for it.
- `tool/qa/flows/calendar/18_category_editor.txt` keeps passing.

**Deliberately changes**

- The page's idiom, rows, menus, numbers, ids and copy (§4.2); "Hide" → "Archive" everywhere a category is archived (B1).
- Delete takes a target and tells the whole impact (C); the service's `deleteCategory` signature gains `reassignTo` and returns the DAO's bool.
- The default category of a new event (D).
- `resolve` falls back to the stored Other before the const (K4).
- The editor guards a dirty draft (K11); `initialName` is clamped (K12).
- The shared `ReorderHandle` grows to a 48 dp target (K7), which every reorderable list inherits.
- Other cannot be archived while it is the last visible category (new guard).
- Sort A–Z confirms (H1).
- The drawer, the ⋮ and the settings subtitle (§4.1); one glyph for "category" (K21).

## 6. Facts from the tree

Re-grep each before editing; the line numbers are from 2026-10-30.

- `lib/pages/calendar_categories_page.dart` (675 lines): `_create` 207, `_edit` 214, delete confirm 234-255, `_CategoryAction` 307-313, bar actions 328-339, body 371, filtered list 414, reorderable list 422-448 (`eventCount` from `_counts`), row widget 500-664 (`Card`/`ListTile` 544-548, bell 575-591, eye 592-598, `PopupMenuButton` 600-664, Delete hidden on built-ins 647).
- `lib/widgets/category_editor_sheet.dart` (692): duplicate guard 192-231, `_canSave` 233-237, Icon row 241-255, write path 395-443, built-in name 405, `PopScope` 507-511, Alerts group 564-572 and 659-667, swatch 680.
- `lib/widgets/category_picker_sheet.dart` (382): `_createCategory` 211, title 280, create row 360-365.
- `lib/services/category_service.dart` (607): seed 236, create 324-330, delete 468-487 (`tombstoneCascade(id, reassignTo: kFallbackCategoryId)` 474), export 500, import 564-566.
- `lib/database/daos/calendar_category_dao.dart`: create 141-151, update/hide 171-193, `tombstoneCascade` 226-236, `_tombstone` 249-269, `deleteAll` 323-327, reorder 343-368.
- `lib/constants/calendar_categories.dart`: seeds 30-64, const fallback 84-91, `resolve` 152, stored names 203-215.
- `lib/models/calendar_event.dart:19-21` `kDefaultCategoryId`; `lib/widgets/event_editor_sheet.dart:771` and `lib/widgets/event_template_editor_sheet.dart:176` read it; `event_editor_sheet.dart:3007-3009` the Category row and its glyph; `lib/widgets/digest_editor_sheet.dart:501` its glyph.
- `lib/widgets/settings_reorder.dart:28-37` `ReorderHandle`.
- `lib/widgets/app_drawer.dart:123-165` the Calendar group (`_buildMenuItem` at 524 is a `ListTile`); `lib/widgets/calendar_header_menus.dart:290-327` the ⋮ items (Alerts 296, Export 306, Guide 317, Settings 326); `lib/pages/calendar_settings_page.dart:621-642` the Categories section (glyph 635); `lib/services/app_navigator.dart:870` `toCalendarCategories`, `:1106` the restore; `lib/models/nav_destination.dart:48-54` `reopensDrawerOnPop`.
- `lib/models/calendar_guide_content.dart:133-143` the topics, `:319-334` the categories coach lines, `:527-551` its read rows, `:587-595` `fasting-where`; `lib/widgets/calendar_guide_try_categories.dart` (282): actions 20, delete 113-119, menu 148-170, subtitle note 202-204, add row 271-276.
- `lib/utils/event_alerts.dart:157-182` `effectiveFor`; `lib/database/tables/overview_views_table.dart:21-23` the stale-allowlist comment; `lib/database/daos/calendar_event_dao.dart:262-274` `countByCategory`; `lib/utils/calendar_categories_binding.dart:46`, `:64` the sync codec.
- Tests: `test/widgets/calendar_categories_page_test.dart`, `test/widgets/category_editor_sheet_test.dart` (scrim test 373), `test/widgets/category_picker_sheet_test.dart`, `test/widgets/category_filter_sheets_test.dart`, `test/widgets/calendar_categories_visibility_test.dart:50-59`, `test/widgets/sheet_bottom_clearance_test.dart:434`, `:870`, `test/widgets/form_rows_test.dart`.
- Strings: `app_en.arb` 497 `eventCategoryOther`, 501-507 `calendarCategories`/`Desc`, 509 `createCategory`, 533 and 554 the delete messages, 566 `categoryEventCount`, 2101/2105 `hide`/`show`, 3526-3532 the drawer settings row, 8104 the guide lead, 8462-8478 the coach lines, 8545 the funnel line.

Retire list: on the page every item named in §4.2's last bullet; the two
delete-dialog messages (C1); `_bellSize`; the eye.

## 7. Slices

Each slice ends with the gate (§3 of `ui-revamp`): `dart analyze lib` (and
`test`), the whole `flutter test` once, `flutter gen-l10n` with
`untranslated.txt` empty when an ARB changed, the must-not-change list re-read
against the diff. Nothing red carries over.

- **S0 — safety net.** A QA flow `tool/qa/flows/calendar/<next>_categories_page.txt` against the current page: open from Calendar settings, archive, restore, reorder by handle, delete a custom with events, create; a seed with two customs in `tool/qa/fixtures/calendar.json` if the existing one has none. Pin tests for what the page does today where §2.2 lists a gap: a delete taken through to the reassigned events and the snackbar, a reorder persisted densely, a row tap opening the editor. No visual change.
- **S1 — entries and the non-visual fixes.** The drawer row and its id, the settings row's id and subtitle, the ⋮ item (A); `resolve` (K4); the default category (D); the picker title (K10); `initialName` clamp (K12); the glyph (K21); the comment (A8). Three ARB keys, three ids. May run in a gap between Report commits.
- **S2 — the page.** The `designer`'s spec first, then the rebuild of §4.2 on content rows, the row menu, Archive naming (B), the handle's target (K7), the add control (E), the alert caption (G), the scroll-and-flash (K20), the last-visible guard, the ids, the suite rewritten (de/ro 2.0, 48 dp targets, the menu items, the sections), the S0 flow updated. The `design-reviewer` after the code review.
- **S3 — delete, sort, the editor guard.** The delete sheet (C) with `deleteImpact` and the service signature, the Sort confirm (H), the editor's leave guard (K11), the delete path reading the DAO's bool (K14); suites for the sheet (joins `sheet_bottom_clearance_test.dart`) and the guard; the flow's delete step updated.
- **S4 — the guide.** The where row, the coach lines, the sandbox parity (§4.6), re-measured at de 2.0.
- **S5 — device pass, review, docs.** `qa-runner`: the calendar flows, then the matrix (dark, de, 2.0, both phone sizes) on the page, the sheet, the drawer and the ⋮; `qa errors` clean. Docs: this record's status line; `calendar-events/references/subsystems.md` § Categories and icons (the page's new rule lines, the delete sheet, the default, the archive wording); `calendar-ui` id catalogue; `ui-language/references/row-primitives.md` for the handle's target and, under E2, the new `ContentActionRow`; `docs/calendar-guide-page.md` for the lesson change.

### 7.1 As built

- **S0, 2026-10-31.** Ids on the current page, named for §4.2 so S2 keeps them: `categoryRowMenu(id)`, `categoryMenuMoveToTop` / `categoryMenuEdit` / `categoryMenuArchive` (today's hide / show item) / `categoryMenuDelete`, `categorySortAz`, plus `categoryRowVisibility(id)` on the eye, which retires with it in S2; the page diff is semantics wrappers only (a `PopupMenuItem` merges its subtree, so a `Semantics(identifier:)` on the item's row is what the merged node carries). Flow `tool/qa/flows/calendar/29_categories_page.txt`: archive and restore read from the row's ⋮ ("Show" / "Hide", the popup's barrier hiding the page's nodes), a reorder by two 900 ms drags asserted with `--ordered`, the delete through `sheet-confirm` on the one-event confirm text, a create found by its typed name; `_labels.txt` gained its two labels. Seven pins in the page suite: every targeted id reachable; a delete read back from both events (`kFallbackCategoryId`) and from the category's tombstone (`isDeleted`, `version` +1, a later stamp); a reorder from a gapped start (`sortOrder` 100) to a dense 0..N-1 with the untouched rows keeping `version` and `hlcTimestamp`; a row tap opening the editor; a create listed; the zero-event message; the archive item writing the flag. Reviewer: "ship after fixes" — all eight applied. No ARB change. Flow 29 ran green on its first device pass (2026-10-31, `anta_qa_2` on emulator-5558, 23.7 s): the barrier hides the page's own Show / Hide nodes while the menu is up, the 900 ms drags beat the long press, the confirm substring and the created row's label both resolve. Found in passing, for S3: the seeded template "Leg day" names `qa-cal-strength`, so after flow 29's delete it points at a deleted category (each flow reseeds, so nothing else sees it) — the delete sheet should say what happens to templates.

## 8. Definition of done

1. Create, edit, archive, restore, reorder and delete round-trip; the rows written equal what the old page wrote for the same input (the DAO suites), and a delete with a chosen target moves every event and template to it, tombstones the category's alerts, and the snackbar appears only on a real delete.
2. Every control is reachable one-handed on 360 × 780 with 48 dp targets: the handle, the ⋮, the FAB (E1), each menu item, the sheet's rows and header buttons; asserted with `getSize` in the suites.
3. The editor asks before discarding a dirty draft on ✕, back, system back, the barrier and drag, and leaves silently when clean; the delete sheet and the row menu never ask.
4. Light and dark; en, de, ro; text scale 1.3 and 2.0 with no clipped label, no overflow and no mid-word break in any built-in name — "Măsurătoare" and "Familienbesuch" (or the longest real sample) pumped at de/ro 2.0 and line-counted.
5. The page's bottom padding clears the FAB (E1) and the navigation bar; the delete sheet is in `sheet_bottom_clearance_test.dart`.
6. Nothing moves under the finger: a live query disables handles, Move to top and Sort in place; an archived row keeps its height; the caption changes text, never geometry; the search field's presence is decided by count at build, not toggled at runtime.
7. Every string in all three ARBs; `untranslated.txt` empty; "Other" never written into a message.
8. Semantics: one node per row with the name, the caption and the handle's label; ids for every control §4.2 names; the row menu's items are `menuItemRadio` nodes; tooltips on every icon button.
9. The four category suites, the visibility suite, the agenda search suite and the form-rows suite pass; the new behaviour has new tests; the saved filters, saved views and palette sheets' suites still pass with the taller handle.
10. Nothing on the retire list is referenced (grep); no literal number on the page; nothing off `AppSpacing` but `fabClearance`.
11. The QA flow for the page passes on `emulator-5556`; `qa errors` clean.

## 9. Deferred

- **K19 the built-in catalogue.** Making built-ins deletable or re-seeding a neutral set is a data decision (ids are stored on every event and in every backup; `isBuiltIn` guards delete and rename). If wanted: a migration that converts a built-in to a custom row keeping its id, and a settings action "Convert to custom". Out of this rework.
- **K15 search by an archived name.** Deliberate today (`upcoming_agenda_search_test.dart:338-341`). If archived events should stay findable by name, the agenda's and the overview's label maps read `all` instead of `visiblePlus(keep)`; two files, two tests.
- **K17 / K18 restore semantics.** Renumbering `sortOrder` on import (`category_service.dart:564-566`) and tombstoning instead of hard-wiping on a synced device (`calendar_category_dao.dart:323-327`) change restore and sync behaviour; they need the owner's yes and belong to the cloud-sync records.
- **K14's sync decode default.** `calendar_categories_binding.dart:64` defaults `isBuiltIn` to false when the envelope lacks it; a built-in synced that way becomes renameable and deletable. Fix: default from the seed's id set. One line plus a codec test; cloud-sync territory.
- **Digest planning with a stale category id** was not traced (`DigestPlanner`); the overview table's comment says a stale allowlist lists nothing. Verify in S3's review.
- **A1–A6** (`SharePlus` and layer bypasses outside the calendar) go to `docs/ui-language-adoption-roadmap.md`'s open items or a code-quality pass; not this rework.
