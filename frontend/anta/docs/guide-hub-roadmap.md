# The guide hub: How to use ANTA → calendar, notes, the app (2026-11-08)

**Status: IMPLEMENTED 2026-11-08/09, UNCOMMITTED pending the owner — the
strings (en/de/ro, 245 keys) and this record by the Fable 5.1 lead; slice 0
(structure + app book) and slice 1 (the notes book) by Opus 5.5
implementers; three read-only reviews (structure, content, design) and a
language review (de/ro), their findings fixed (§6.3–§6.4); built in a
detached worktree and applied to `main` as one patch. Gate: `dart analyze
lib test` clean, `flutter gen-l10n` with `untranslated.txt` `{}`, the whole
suite green (the line is in §6.5), the settings device pass per §6.5.** The owner asked (2026-11-08) for
the drawer's "How to use ANTA" row to open a page of categories instead of
the calendar guide alone — "How to use Calendar", "Learn Notes" (its own
markdown, the editor, the bar, settings, common markdown, the money ledger,
autocomplete) — and said to add whatever a beginner needs. The owner's
five open calls were answered with the defaults in §2 (D1, D3, D4, D13);
each is reversible in one line. Phase 2 (§9, 2026-11-09) added the "Try
it" editors; **Phase 3 (§10, 2026-11-11) — the app's bar on every notes
card and the "Your own shortcuts" page — is BUILT and UNCOMMITTED.**

## Contents

- §0 How to run this
- §1 The ask, and what exists
- §2 Decisions D1–D16
- §3 The books and their pages — the content catalogue
- §4 The example row
- §5 Ids, routes, flows, tests
- §6 Slices and the gate
- §7 Deferred
- §8 Must not change
- §9 Phase 2 — the "Try it" editors and the four fixes (2026-11-09)
- §10 Phase 3 — the bar on the stage and "Your own shortcuts" (2026-11-11)

## 0. How to run this

- Lead: Fable 5.1 (content, decisions, briefs, the whole-suite gate).
  Builders: `implementer` (Opus 5.5) — slice 0 and slice 1 in sequence, one
  each; one `reviewer` over the whole diff; one `qa-runner` for `qa pass
  settings` and `qa pass calendar` on `emulator-5556`.
- The tree is the detached worktree
  `C:\Users\mobx3\AppData\Local\Temp\anta-wt-guide` (at `d9f34776`); the
  ARBs there already carry every key of §3 (merged by the lead with a
  script that kept CRLF; `flutter gen-l10n` run; `untranslated.txt` `{}`).
  Nothing is edited in the main tree until the owner says so; then
  `git diff --binary` from the worktree, `git apply --3way` on `main`, one
  `dart analyze lib`, one whole `flutter test`.
- Read this record by section: an implementer reads §2–§6, a reviewer
  §2, §5 and §8.

## 1. The ask, and what exists

The drawer's "How to use ANTA" (`howToUseAnta`, id `drawer-how-to`) opens
`CalendarGuidePage` directly (subtitle `calendarGuideTitle`). The welcome
screen already promises "You can open How to use ANTA from the menu at any
time" (`onboardingHowToHint`), so the general name was promised while the
content was calendar-only. The calendar guide (`docs/calendar-guide-page.md`)
is a settings-kit hub: search over every page's rows, "Start here" and
"How do I…" cards, two practice lessons, eleven topic pages with read rows
and "Try it" cards. Its machinery — `CalendarGuideTopic`,
`CalendarGuideRow`, `calendarGuideReadEntry`, `GuideMetrics`, the glyph
rule, slug-keyed ids — is what the new guides stand on.

## 2. Decisions D1–D16

- **D1 — Three guides under one hub.** The drawer row keeps its name and
  opens a new `GuideHubPage` ("How to use ANTA"): an intro line, one search
  field, one card ("Guides") with three rows — the calendar guide
  (`calendarGuideTitle`, the existing hub, untouched), "Notes and the
  editor" (`guideBookNotesTitle`) and "Backup, sync and settings"
  (`guideBookAppTitle`). The third book is the lead's addition for a
  beginner: deleting is final and the phone is the only copy until it is
  not, so backup and sync need a home. The drawer subtitle becomes
  `howToUseAntaDesc`. The calendar's ⋮ menus and the settings hub's
  calendar row keep their direct route to the calendar hub, so a calendar
  reader pays no extra tap.
- **D2 — The search reaches every page of every guide.** With a query the
  top hub shows one section per page across all three books — the two
  practice lessons, the eleven calendar topics, the notes and app topics —
  each section the page's row and its matching read rows, exactly the
  calendar hub's `_searchSections` shape. This is what makes the extra
  level cheap: someone who knows a word never picks a category.
- **D3 — A book's hub has the calendar hub's shape.** `SettingsAppBar(book
  title)` · `SettingsSearchField` (`calendarGuideSearchHint`) · intro ·
  "Start here" / "How do I…" cards (`calendarGuideStartHere`,
  `calendarGuideHowDoI`). Notes — Start here: Folders and notes, Writing a
  note, Nothing gets lost; How do I…: Markdown basics, Lists and nesting,
  ANTA's own markdown, The money ledger, The bar, Autocomplete, Counters,
  Where the settings are. App — Start here: The main menu, Settings worth
  knowing; How do I…: Backup and restore, Sync between phones.
- **D4 — Read rows and example rows, no interactivity yet.** A topic page
  is the calendar topic page without cards: bar titled with the book,
  heading, lead, one "How it works" card (`calendarGuideHowItWorks`) whose
  entries are read rows (`CalendarGuideReadRow`, unchanged) and example
  rows (§4) in the authored order. The practice note and "Try it" editors
  are phase 2 (§7): the content ships first.
- **D5 — The guide quotes the app, braces travel as placeholders.** Every
  label a sentence names is an ARB placeholder filled with the app's own
  string, as the calendar guide does (its D5). Example sources that need
  `{`/`}` — the colour and the ghost examples — carry `{open}` / `{close}`
  placeholders filled with the literal braces in Dart, because a literal
  brace would be read as an ICU argument. Example sources are localised
  (the words change, the syntax does not), so a German reader sees a German
  workout.
- **D6 — Keys.** `guideHub*`, `guideBook*`, `guideExample*` for the hub and
  the row chrome; `notesGuide*` and `appGuide*` for the books, in the form
  `<book>GuidePage<Topic>` / `…Caption`, `<book>Guide<Topic>Lead`,
  `<book>Guide<Row>Title` / `…Body`, `notesGuideEx<Name>Source` /
  `…Caption`. Four existing calendar keys are reused for shared words
  (start here, how do I, how it works, the search hint).
  `test/l10n/calendar_guide_placeholders_test.dart` grows to every prefix:
  `calendarGuide`, `guideHub`, `guideBook`, `notesGuide`, `appGuide`.
- **D7 — No rename of the calendar types.** `CalendarGuideTopic`,
  `CalendarGuideRow`, `CalendarGuidePage`, the `calendar-guide-*` ids and
  the device flow stay; a rename would churn 8,000 lines for a word. The
  hub body is extracted from `CalendarGuidePage` into one shared widget,
  `GuideHubList` (`lib/widgets/guide_hub_list.dart`): sections of
  `GuideHubItem`s (slug, icon, title, caption, keywords, read rows for the
  search, identifier, `open(context)`), the `_HubRow`, the glyph rule
  measured over every item's title, the hub/search section builders.
  `CalendarGuidePage`, the two book hubs and the top hub are thin pages
  over it; the calendar hub's tests pin that its behaviour did not move.
- **D8 — Ids.** Top hub: `guide-hub` (the list), `guide-hub-book-<book>`
  (a category row). A book: `guide-<book>` (the hub list),
  `guide-<book>-page-<slug>` (a hub row), `guide-<book>-topic-<slug>` (a
  topic page's list), `guide-<book>-<slug>` (a read row),
  `guide-<book>-example-<slug>` (an example row). Book slugs: `notes`,
  `app`. Calendar ids unchanged.
- **D9 — Routes.** `NavDestinationKind.guideHub`, `notesGuide`, `appGuide`
  appended (names are persisted; append only). `AppNavigator.toGuideHub`,
  `toGuideBook(book)` — stamped pushes with an `_isOnTop` guard like
  `toCalendarGuide` — and `toGuideTopic(book, topic)`, unstamped like the
  calendar's topic page. The restore switch rebuilds the three pages.
- **D10 — Entry points.** Drawer: `drawer-how-to` → the top hub. Settings
  hub › How to: the calendar row stays (`settings-hub-row-calendarGuide`,
  three flows wait on it), and gains `settings-hub-row-notesGuide` and
  `settings-hub-row-appGuide`, each with the book's caption as description
  and its page titles as keywords.
- **D11 — Flows.** `settings/01_drawer_places.txt`: the drawer row now
  lands on `guide-hub`, back returns to the folder root. New
  `settings/20_guide_books.txt` (20: `14_` was taken by the notes-family
  restore flow): hub → notes row → `guide-notes` → its first page →
  `guide-notes-topic-basics` → back to the hub, then the same through the
  app row, `guide-app` and the backup page, back ×3 to the root. The hub's
  search is covered by the widget suites, not the flow (the guide's search
  field carries no id, like the calendar hub's). `11_hub_guide` and
  `13_restore_calendar_family` unchanged; `calendar/26_guide` enters by the
  ⋮ and is unchanged.
- **D12 — Suites.** `test/widgets/guide_hub_page_test.dart` (three rows,
  ids, each row pushes its page and back returns, the search across books
  — a calendar word, a notes word, an app word, each under its page's name
  — de 2.0 on 360 no overflow / no clipped text) and
  `test/widgets/guide_book_page_test.dart` (both books: every hub row,
  every topic's heading, lead and rows by id, read rows are not buttons,
  every example row shows its source and a rendered preview, the quoted
  labels match the live labels in en/de/ro for two topics per book, de and
  ro at 2.0 on 360 × 780 and 412 × 915 in both themes without overflow or
  clipped text). The calendar suites stay green unchanged except the
  placeholders test's prefix list.
- **D13 — Counters have a page; the settings have a page.** Counters are a
  drawer row of their own, so they get a page in the notes book rather than
  a row; "Where the settings are" lists what each settings page holds,
  because the owner named settings in the list.
- **D14 — The example renders through the app's own preview.**
  `SimpleMarkdownPreview` (the pipeline the event description and the
  shortcut editor use) draws the "You get" half, so the guide cannot drift
  from the renderer and follows the theme, the money config and the colour
  palette. The editor page's own conceal-on-the-caret-line is explained in
  words ("You see the result as you type") rather than faked.
- **D15 — Honest rows.** Deleting is described as final with no bin (there
  is none); tables as "lightly" (monospace with tinted pipes, no grid);
  autosave as "a few seconds" and "every half minute" (5 s debounce, 30 s
  interval) without numbers in the sentence that could drift; the "Open
  ANTA now and then" kind of caveat does not apply here.
- **D16 — No new primitive, no new metric scale.** The example row's own
  numbers (source font size, the eyebrow labels, the block padding and
  radius) join `GuideMetrics`, each with its reason; everything else reads
  `FormMetrics` / `RowMetrics` and the settings kit.

## 3. The books and their pages — the content catalogue

Slugs are frozen (ids are built on them). Icons are the Material glyph
nearest the idea; a row that names an app control uses the app's icon for
it. Titles here are the English; the bodies are in the ARBs under the keys
named.

### 3.1 The top hub (`GuideHubPage`)

Title `howToUseAnta`; intro `guideHubIntro`; card `guideHubSectionGuides`;
rows (book slug → title / caption / icon): `calendar` →
`calendarGuideTitle` / `guideBookCalendarCaption` /
`Icons.calendar_month_rounded` (opens `AppNavigator.toCalendarGuide`);
`notes` → `guideBookNotesTitle` / `guideBookNotesCaption` /
`Icons.edit_note_rounded`; `app` → `guideBookAppTitle` /
`guideBookAppCaption` / `Icons.phone_android_rounded`.

### 3.2 Notes and the editor (`NotesGuideTopic`, intro `notesGuideIntro`)

Keys follow `notesGuidePage<Topic>` / `notesGuidePage<Topic>Caption` /
`notesGuide<Topic>Lead`; row keys `notesGuide<Row>Title` / `…Body`; example
keys `notesGuideEx<Name>Source` / `…Caption`. Placeholders are listed per
row as the l10n getter's arguments, in order.

| Topic slug · icon | Entries in order (slug · icon · key stem · placeholders) |
| --- | --- |
| `basics` · `Icons.folder_rounded` — Folders and notes | `basics-create` · `Icons.note_add_rounded` · BasicsCreate · body(newNote) · `basics-folders` · `Icons.create_new_folder_rounded` · BasicsFolders · body(newFolder) · `basics-saved` · `Icons.save_rounded` · BasicsSaved · body(saveStatusSaved) · `basics-reopen` · `Icons.history_rounded` · BasicsReopen · `basics-menu` · `Icons.more_vert_rounded` · BasicsMenu · body(renameFolder, moveToFolder, sortBy, shareFolder, importNoteOrFolder, select) · `basics-hold` · `Icons.touch_app_rounded` · BasicsHold · body(moveSelected, labelSelected, shareSelected, deleteSelected) · `basics-sort` · `Icons.sort_rounded` · BasicsSort · body(sortNotes, sortByCustom) · `basics-labels` · `Icons.label_rounded` · BasicsLabels · body(labelAction, sortByLabel) · `basics-delete` · `Icons.delete_outline_rounded` · BasicsDelete · body(guideBookAppTitle) · `basics-search` · `Icons.search_rounded` · BasicsSearch · `basics-all` · `Icons.notes_rounded` · BasicsAll · body(allNotes, recent) |
| `editor` · `Icons.edit_rounded` — Writing a note | `editor-live` · `Icons.visibility_rounded` · EditorLive · `editor-bar` · `Icons.keyboard_rounded` · EditorBar · body(headers, bulletList, checkbox) · `editor-undo` · `Icons.undo_rounded` · EditorUndo · `editor-title` · `Icons.title_rounded` · EditorTitle · `editor-menu` · `Icons.more_vert_rounded` · EditorMenu · body(shareNote, moveToFolder, labelAction, openFolder, deleteNote) · `editor-find` · `Icons.find_in_page_rounded` · EditorFind · `editor-font` · `Icons.text_increase_rounded` · EditorFont · body(decreaseFontSize, increaseFontSize) · `editor-tap` · `Icons.check_box_rounded` · EditorTap |
| `markdown` · `Icons.text_fields_rounded` — Markdown basics | examples `heading` ExHeading · `emphasis` ExEmphasis · `list` ExList · `numbered` ExNumbered · `task` ExTask (caption: checkbox) · `quote` ExQuote · `link` ExLink; then read row `markdown-table` · `Icons.table_chart_rounded` · MarkdownTable · body(shortcutTable) |
| `lists` · `Icons.format_list_bulleted_rounded` — Lists and nesting | example `nested` ExNested; read rows `lists-enter` · `Icons.keyboard_return_rounded` · ListsEnter · `lists-nest` · `Icons.format_indent_increase_rounded` · ListsNest · `lists-cap` · `Icons.vertical_align_center_rounded` · ListsCap · `lists-task` · `Icons.check_box_rounded` · ListsTask |
| `own` · `Icons.auto_awesome_rounded` — ANTA's own markdown | examples `tag` ExTag · `callout` ExCallout · `colour` ExColour (source: open, close; caption: markdownColorsTitle) · `ghost` ExGhost (source: open, close; caption: shortcutGhostText) · `wiki` ExWiki; read row `own-date` · `Icons.today_rounded` · OwnDate · body(currentDate) |
| `money` · `Icons.payments_rounded` — The money ledger | examples `money-basic` ExMoneyBasic · `money-months` ExMoneyMonths · `money-target` ExMoneyTarget; read rows `money-tap` · `Icons.touch_app_rounded` · MoneyTap · `money-more` · `Icons.calculate_rounded` · MoneyMore · `money-settings` · `Icons.settings_rounded` · MoneySettings · body(settingsRowEditor, moneySection, moneyLedgerEnabledLabel) · `money-calendar` · `Icons.calendar_month_rounded` · MoneyCalendar · `money-buttons` · `Icons.attach_money_rounded` · MoneyButtons · body(shortcutMoneyAdd, shortcutMoneySubtract, shortcutMoneyStart, shortcutMoneyTotal, shortcutMoneyChange, shortcutMoneyTarget) |
| `bar` · `Icons.dashboard_customize_rounded` — The bar (lead: settingsRowEditor) | `bar-shortcuts` · `Icons.flash_on_rounded` · BarShortcuts · body(shortcuts) · `bar-own` · `Icons.add_circle_outline_rounded` · BarOwn · body(shortcuts) · `bar-utility` · `Icons.build_rounded` · BarUtility · body(utilityButtons) · `bar-reorder` · `Icons.swap_horiz_rounded` · BarReorder · body(reorderShortcuts) · `bar-profiles` · `Icons.view_carousel_rounded` · BarProfiles · body(manageBarProfiles, switchBar, perNoteBarAssignment) · `bar-layout` · `Icons.view_agenda_rounded` · BarLayout · body(splitToolbar, pinUndoRedo) |
| `autocomplete` · `Icons.playlist_add_check_rounded` — Autocomplete | `auto-lists` · `Icons.list_alt_rounded` · AutoLists · body(settingsRowEditor, vocabularySection, manageVocabularies) · `auto-trigger` · `Icons.alternate_email_rounded` · AutoTrigger · body(vocabularyTriggerLabel) · `auto-scope` · `Icons.filter_list_rounded` · AutoScope · `auto-ghost` · `Icons.touch_app_rounded` · AutoGhost · body(open, close) · `auto-ignore` · `Icons.do_not_disturb_alt_rounded` · AutoIgnore · body(vocabularySuggestionsLabel) |
| `counters` · `Icons.pin_rounded` — Counters | `counters-make` · `Icons.add_rounded` · CountersMake · body(counterSettings, addCounter) · `counters-note` · `Icons.edit_note_rounded` · CountersNote · body(counterInsertTooltip) · `counters-scope` · `Icons.note_rounded` · CountersScope · body(counterScope, counterScopeGlobalDesc, counterScopePerNoteDesc) · `counters-pin` · `Icons.push_pin_rounded` · CountersPin · body(pinCounter) · `counters-shortcut` · `Icons.flash_on_rounded` · CountersShortcut · body(shortcuts, counterBindingsTitle) |
| `settings` · `Icons.tune_rounded` — Where the settings are (lead: settingsHubTitle) | `settings-general` · `Icons.settings_rounded` · SettingsGeneral · title(settingsRowGeneral) body(settingsRowGeneralDesc) · `settings-editor` · `Icons.edit_rounded` · SettingsEditor · title(settingsRowEditor) · `settings-counters` · `Icons.pin_rounded` · SettingsCounters · title(counterSettings) · `settings-look` · `Icons.dark_mode_rounded` · SettingsLook · title(settingsRowTheme, languageSettings) body(themeSettingsDesc) · `settings-pernote` · `Icons.note_rounded` · SettingsPerNote |
| `safe` · `Icons.shield_rounded` — Nothing gets lost | `safe-autosave` · `Icons.save_rounded` · SafeAutosave · `safe-status` · `Icons.info_outline_rounded` · SafeStatus · body(saveStatusSaved, saveStatusSaving, saveStatusUnsaved, saveStatusError) · `safe-event` · `Icons.event_rounded` · SafeEvent · body(eventLinkedNote) · `safe-backup` · `Icons.backup_rounded` · SafeBackup · body(guideBookAppTitle) · `safe-share` · `Icons.ios_share_rounded` · SafeShare · body(shareNote) |

Hub order: Start here — `basics`, `editor`, `safe`; How do I… — `markdown`,
`lists`, `own`, `money`, `bar`, `autocomplete`, `counters`, `settings`. The
enum is declared in that reading order; the hub's two sections pick from it
as the calendar hub's `_startHere` does.

### 3.3 Backup, sync and settings (`AppGuideTopic`, intro `appGuideIntro`)

| Topic slug · icon | Entries in order |
| --- | --- |
| `menu` · `Icons.menu_rounded` — The main menu | `menu-account` · `Icons.account_circle_rounded` · MenuAccount · body(drawerAccountNotSyncing) · `menu-calendar` · `Icons.calendar_month_rounded` · MenuCalendar · title(calendar) body(calendar, calendarOverview, reportTitle, calendarCategories, alertsTitle, calendarGuideTitle) · `menu-notes` · `Icons.pin_rounded` · MenuNotes · title(notes) body(counterSettings) · `menu-app` · `Icons.settings_rounded` · MenuApp · title(appGroupLabel) body(settingsHubTitle, howToUseAnta, about) · `menu-back` · `Icons.arrow_back_rounded` · MenuBack |
| `settings` · `Icons.tune_rounded` — Settings worth knowing (lead: settingsHubTitle) | `settings-theme` · `Icons.dark_mode_rounded` · SettingsTheme · title(settingsRowTheme) body(themeSettingsDesc) · `settings-language` · `Icons.language_rounded` · SettingsLanguage · title(languageSettings) · `settings-permissions` · `Icons.lock_open_rounded` · SettingsPermissions · title(permissionsTitle) body(settingsHubTitle) · `settings-startup` · `Icons.restore_rounded` · SettingsStartup · body(settingsRowGeneral, startupSection, restoreLocation) · `settings-search` · `Icons.search_rounded` · SettingsSearch · body(settingsHubTitle, autoSaveSection, languageSettings) |
| `backup` · `Icons.backup_rounded` — Backup and restore | `backup-folder` · `Icons.folder_zip_rounded` · BackupFolder · body(shareFolder) · `backup-selection` · `Icons.checklist_rounded` · BackupSelection · body(shareSelected) · `backup-import` · `Icons.file_download_rounded` · BackupImport · body(importNoteOrFolder) · `backup-database` · `Icons.storage_rounded` · BackupDatabase · body(settingsRowDatabases, settingsHubTitle, shareDatabase, importDatabase) · `backup-switch` · `Icons.swap_horiz_rounded` · BackupSwitch · `backup-firstrun` · `Icons.restore_rounded` · BackupFirstRun · body(restoreFromBackup) |
| `sync` · `Icons.sync_rounded` — Sync between phones | `sync-signin` · `Icons.login_rounded` · SyncSignIn · body(sharingSettings, settingsHubTitle, signInWithGoogle) · `sync-on` · `Icons.cloud_upload_rounded` · SyncOn · body(syncThisDatabase, syncThisDatabaseDesc) · `sync-status` · `Icons.cloud_done_rounded` · SyncStatus · body(syncUpToDate, syncOffline, syncNow) · `sync-other` · `Icons.devices_rounded` · SyncOther · body(syncThisDatabase) · `sync-conflict` · `Icons.call_split_rounded` · SyncConflict · `sync-stop` · `Icons.logout_rounded` · SyncStop · body(syncStop, signOut) |

Hub order: Start here — `menu`, `settings`; How do I… — `backup`, `sync`.
The app book's `settings` slug and the notes book's `settings` slug never
meet: ids carry the book.

### 3.4 Facts the text rests on (verified 2026-11-08)

No trash or restore for a deleted note (confirm-then-delete, "cannot be
undone"); long-press enters selection, the bar offers Move · Label · Share ·
Delete (`selection_action_bar.dart`); folders and notes both carry an
`ItemLabel` drawn as a stripe; the root folder's smart rows are All notes and
Recent; the browser's search button is `SemanticsIds.searchOpen`; the
editor's bar has search, the ⋮ and a tappable title; find/replace is
`NoteSearchBar`; font size moves only by the bar's two utility buttons (no
settings row); the live editor conceals markers off the caret line; Enter
continues bullets, numbers (incremented) and tasks (`- [ ] `), and ends a
list on an empty item (`MarkdownListUtils`); Space on an empty item, the
caret-line swipe and the indent/outdent utilities all go through
`ListIndentAction` with a one-level cap; `[text](url)` taps `launchUrl`;
callout tokens: note/info, tip/hint, important, warning/attention, caution,
success/check/done, pr, example, question/faq/help, danger/error, bug, todo,
quote/cite, abstract/summary/tldr, failure/fail/missing, unknown → note;
table rows render monospace with tinted pipes; the money grammar and its
calendar surfaces per `docs/money-ledger-feature.md`; the counter utility
opens a picker that increments and inserts the value; counter scope global
vs per note, pins sort first; shortcuts can bind counters; the default
utility set is undo, redo, indent, outdent, paste, A−, A+, share, switch bar
(shown with 2+ profiles), counter, top, bottom, reorder, settings; reorder
enters an in-bar drag mode; Switch Bar opens `BarSwitcherSheet` with a note
override; autocomplete per `docs/vocabulary-autocomplete-feature.md`;
auto-save 5 s debounce / 30 s interval / retries, status word in the bar;
wiki miss shows `wikiLinkNoteNotFound` only; share note picks a format
(md/json/txt) then shares; folder ⋮: Rename · Move · Sort by · Share folder
· Import · Select · Move history · Delete · Settings; Databases page:
Create New · Import · Optimize · Share · Switch (restarts) · Rename ·
Delete; Sync & sharing: Account (Google), Pairing (left out of the guide,
§7), Sync (Sync this database, status, Sync now, Stop syncing); the second
device picks a space to download into a new database (`syncPicker*`);
conflicts file a copy; the drawer's account row shows the user and the last
sync.

## 4. The example row

`GuideExampleRow` (`lib/widgets/guide_example_row.dart`), a kit entry like
`calendarGuideReadEntry`:

- Two stacked blocks inside the row's padding, each with an eyebrow label in
  the kit's caption style, uppercase like the section headers:
  `guideExampleTyped` ("You type") over the source, `guideExampleShown`
  ("You get") over the preview.
- The source block: the markdown as typed, monospace
  (`GuideMetrics.exampleSourceFontSize` 13, `FontFeature.tabularFigures`
  not needed), `onSurfaceVariant` on `surfaceContainerHighest` with
  `GuideMetrics.exampleRadius` 8 and `GuideMetrics.examplePadding` 12 —
  the shortcut editor's preview box look (`shortcut_editor_page.dart`
  ~1965). Newlines preserved; never selectable text (nothing to do with it).
- The preview block: `SimpleMarkdownPreview(data: source, fontSize:
  GuideMetrics.paragraphFontSize, padding: EdgeInsets.zero, scrollable:
  false, moneyConfig: <the page's>, colorPalette: <the page's>)` with every
  tap callback null, so the spans are inert. Same box chrome, surface
  `surfaceContainerLow`.
- The topic page reads the money config and the colour palette once in
  `initState` the way the editor does (`optimized_note_editor_page.dart`
  ~885–910: `settings.getMoneyConfig(...)` and the palette getter), starting
  from `MoneyDisplayConfig(enabled: true)` and
  `MarkdownColorPalette.presets` until they land; a read that throws leaves
  the defaults. The ledger examples must render as a ledger even when the
  user has the ledger off: the config passed is the user's currency and
  start balance with `enabled` forced true.
- Semantics: `MergeSemantics` over the row, identifier
  `guide-<book>-example-<slug>`; the eyebrow labels are read, the source is
  read as text, the preview's own semantics stand.
- Search: an example is found by its caption and its source, which feed
  its page's hub row (`GuideHubItem.keywords`); the hub's results show the
  page row and the matching read rows, never a preview — an example is
  read on its page.
- Every example in §3 has a caption.

## 5. Ids, routes, flows, tests

See D8, D9, D11, D12. `SemanticsIds` gains `guideHub`, `guideHubBook(book)`,
`guideBook(book)`, `guideBookPage(book, slug)`, `guideBookTopic(book, slug)`,
`guideBookRow(book, slug)`, `guideBookExample(book, slug)`, each with a `///`
on who targets it. The settings hub rows use the existing
`SemanticsIds.settingsHubRow('notesGuide')` / `('appGuide')`.

## 6. Slices and the gate

- **Slice 0 — structure + the app book.** `GuideBook` enum
  (`lib/models/guide_book.dart`: slug, icon, title, caption; `topics`),
  `GuideTopic` interface and `GuideEntry` (sealed: read row / example) in
  `lib/models/guide_content.dart`; `AppGuideTopic` complete;
  `NotesGuideTopic` declared with every topic's slug, icon, title, caption,
  lead, and the entries of `basics` only; `GuideHubList` extracted;
  `GuideHubPage`, `GuideBookPage(book)`, `GuideTopicPage(book, topic)`,
  `GuideExampleRow`, `GuideMetrics` additions; `CalendarGuidePage` rebuilt
  over `GuideHubList`; `NavDestinationKind` + `AppNavigator` + restore;
  drawer; settings hub rows; `SemanticsIds`; flows (D11); suites (D12,
  with the notes book's `basics` page and the app book covered); the
  placeholders test prefixes. Gate: `dart analyze lib test`, the suites
  the slice touches, `flutter gen-l10n` unchanged (`untranslated.txt` `{}`).
- **Slice 1 — the notes book's entries.** `NotesGuideTopic.entries` for
  `editor`, `markdown`, `lists`, `own`, `money`, `bar`, `autocomplete`,
  `counters`, `settings`, `safe` from §3.2, and the book-page suite extended
  to every notes topic (rows by id, examples render, de/ro 2.0 both sizes,
  live labels for `money` and `bar`).
- **Review** — one `reviewer` over the whole worktree diff against §2, §5,
  §8; a fix pass by the slice-1 implementer; the lead runs the whole suite.
- **Device pass** — `qa-runner`: `qa pass settings -d emulator-5556` and
  `qa pass calendar -d emulator-5556` after `qa fleet install --build`.
- **Land** — on the owner's word: the patch onto `main`, analyze, whole
  suite, the skills' references (`anta-context/references/navigation.md`
  gains the three destination kinds; `calendar-events/SKILL.md`'s guide
  line points here for the hub), this record's status line.

### 6.1 As built — slice 0 (2026-11-08, Opus 5.5 implementer)

Analyze clean; twelve suites green one file at a time (`guide_hub_page`
+8, `guide_book_page` +42, `calendar_guide_page` +29 unchanged,
`calendar_guide_topic_page` +47, `settings_hub_page` +44,
`settings_navigation_contract` +123, `nav_destination` +22, `app_drawer`
+46, `calendar_guide_placeholders` +3, `flows_lint` +29,
`app_navigator_restore` +10, `navigation_history_service` +17). The
implementer's defaults, kept:

- **A.** The glyph rule measures the titles of the mode being shown — the
  sections' items in hub mode, `searchItems` in query mode — so the top
  hub's three book rows are not measured against every topic title; for
  the calendar hub both sets are the same and nothing moved.
- **B.** `GuideHubItem` carries an optional `rowIdentifier` (slug → id), so
  a notes or app read row in the top hub's results keeps its
  `guide-<book>-<slug>` id.
- **C.** Examples reach the search through their page row's keywords only
  (§4 as amended above).
- **D.** A book's search order is "Start here" then "How do I…" — the
  sections flattened.
- **E.** The example's caption is the kit's title in the paragraph style
  (the search highlight reaches it); the eyebrow labels are the kit's
  caption style with the section-label letter spacing, uppercase, spoken as
  written.
- **F.** `calendarGuideReadEntry` took an optional `identifier`
  (default today's) rather than a second row primitive.
- **G.** `GuideMetrics` gained `searchFieldPadding`, `exampleRowPadding`,
  `exampleSourceFontSize` 13, `exampleRadius` 8, `examplePadding` 12,
  `exampleLabelGap`, `exampleBlockGap`.
- **H.** `test/widgets/settings_navigation_contract_test.dart`'s
  "`values.last == reportSettings`" became "reportSettings directly after
  fastingSettings" (its own form for fastingSettings), since three kinds
  were appended after it.

### 6.2 As built — slice 1 (2026-11-08, Opus 5.5 implementer)

Every notes topic filled per §3.2; `guide_book_page_test` +71 (every
entry of every notes page by id, read rows not buttons, examples show their
source and a preview, six live-label cases for `money` and `bar` in en/de/ro,
the 2.0 loop over every entry, the "tildes" search case finding only the
`markdown` row); `guide_hub_page_test` +8 after one test-only fix — a
`pumpAndSettle` after `_scrollTo` in "a search hit's page row opens that
book's page", because the new content pushed the app book's backup row to
the edge of the built area and `scrollUntilVisible` ends in
`ensureVisible` without a pump, so the tap read stale layout. Analyze clean.
The example test finds a source as a plain `Text` equal to the source
(the preview is a `Text.rich`). Open: the `_scrollTo` helper's missing pump
is a pattern the calendar suites share; fix it in one place when it bites
again.

### 6.3 The reviews (2026-11-08) and the fix pass

Three read-only passes over the worktree: a `reviewer` on the structure
(no must-not-change breach; twelve low findings), a `reviewer` on the
content (three sentences that told a beginner something false, six more
imprecise), a `design-reviewer` (no blocker; the example row's alignment,
caption colour, eyebrow size, source wrapping and block edge).

**Content, corrected in the ARBs by the lead (en/de/ro, 21 keys):**

- `$!` with an amount *declares* a target and shows the target; a bare `$!`
  shows what is left since the declaration (`markdown_money_syntax.dart`
  49–62). The example became `$= 500 · $! 300 · $- 120 · $!` and the
  caption says so; `docs/money-ledger-feature.md`'s `$!` row, which the
  lead had followed, is corrected in the fix pass.
- The ledger is **off by default** (`SettingsKeys.defaultMoneyLedgerEnabled
  = false`): the money page's lead now says to switch on
  “Enable money ledger” first (three new placeholders on
  `notesGuideMoneyLead`), and the settings row says it is "still off".
- The first screen (the root) has **no New Note** button and a reduced ⋮
  (`optimized_folder_content_page.dart` 1260–1272): the basics lead, the
  create row and the menu row say to open a folder first and what the root's
  ⋮ holds.
- Split toolbar is two side-by-side strips, not two rows; the drawer's
  account row exists only when signed in (and opens Sync & sharing); the
  settings hub's search matches section titles, not every setting; the
  General row no longer names the auto-save settings (see §7); "Reopen last
  screen" is a three-way choice; Enter on an empty *nested* item outdents
  it (only an outermost one ends the list); the find bar's replace field
  sits behind its options menu; `$=` rows show no grey balance and `$$` is
  a coloured chip; the calendar guide is under "How to use ANTA", not in
  the menu's Calendar group; "close the menu and you are in your folders"
  was dropped; the callout caption lists the words without brackets so the
  line never breaks inside `[!…]`.

**Verified true by the content review (file:line in its report):** every
list behaviour (continuation, increment, task boxes, Space-to-nest, the
caret-line swipe, the one-level cap, the • ◦ ▪ glyphs), every tap in the
editor, duplicate titles, the font buttons, auto-save timing and words,
`$?`, `$*`/`$/`, money on the calendar, per-note currency, the preset
colour names, the inline grammar in the preview, Switch Bar with 2+
profiles, pin undo/redo, the reorder mode, Add Counter's fields, the
counter button, autocomplete, the General and Editor settings sections, the
drawer's groups, the red Settings row, the hub's pages. Not reached by it:
the de/ro wording, the sync and backup rows (they rest on §3.4), and a
dozen smaller claims listed in its report.

**Code and design, fixed in the fix pass (Opus 5.5 implementer):** the
example row gains the read row's glyph column so both kinds of row share
one text edge (`GuideMetrics.readRowPadding` / `readRowGlyphGap`, used by
`CalendarGuideReadRow` too); its caption is `onSurfaceVariant` like a read
paragraph; the eyebrows take the section label's size and weight; the "You
get" block gets a hairline `outlineVariant` border (1.05:1 against the card
was a hole in dark); the source block stops soft-wrapping and scrolls
sideways at large scale, so a typed line stays one line; the
`exampleRadius`/`examplePadding` reasons are honest; the top hub's book
rows drop keywords nothing reads; `GuideBookPage` refuses the calendar
book; the settings hub rows read `book.icon`; stale `14_guide_books`
mentions and the shot name become 20; `11_hub_guide`'s header stops
calling the calendar row the hub's last. Tests added: the restore of
`notesGuide` / `appGuide` lands on the right book; the topic page forces the
ledger on with the user's symbol; the hub and a topic page join
`settings_kit_guidelines_test`.

### 6.4 The language review (2026-11-08) and the fix pass as built

A fourth read-only pass compared every German and Romanian string with its
English. Taken (34 de, 41 ro values, patched by the lead): the ghost
example names the list exactly (`{{übungen}}` / `{{exerciții}}`), because a
placeholder finds its list by exact normalised name or an English plural
(`vocabularies.dart` 121–123) — the English `{{exercise}}` → Exercises
works, the German and Romanian singulars did not; German says
*Schlagwort* for a #tag (the app's word; "Tag" is also "day"),
*Startguthaben*, *Kassenbuch* for the monthly ledger, *Sync* in the app
caption, *Trefferzahl* for the find bar's count; Romanian says *sumarul*
(the app's Overview), *sold inițial*, *per notiță*, *copie de rezervă*,
*conține* instead of the calque *ține*, *fiecare notiță* where "o singură
notiță" read as "only one note"; the emphasis examples take natural word
order; a dozen grammar and register fixes each (its Q1–Q22). Kept against
its advice: Romanian keeps *tag* — the editor's own search label says
*eticheta*, which is also the colour label's word; §7 flags the label.

The fix pass as built (Opus 5.5): items A–F of §6.3 all landed; the
caption rides the entry's `description` slot with `title: ''` (the kit
tolerates it; search still reaches caption and source); the source block is
`Semantics(label: source)` over an `ExcludeSemantics` horizontal scroll
view; the example glyph is the read row's `Icon` (IconTheme 24, `primary`);
the border is the default 1 dp; the eyebrow is the kit's section-label type
(`labelSmall` + `RowMetrics.sectionLabel*`). Suites after the pass:
`guide_book_page` +74 (a shared-text-edge case, the ledger-forced-on case
with `€`, the new target source), `guide_hub_page` +8,
`settings_kit_guidelines` +64 (the hub and the markdown topic added; one
existing dark-de-2.0 hub case now scrolls back to its two rows, which the
two new How-to rows had pushed out of the built range),
`settings_navigation_contract` +124 (the restore of `notesGuide` /
`appGuide` lands on the right book), `calendar_guide_page` +29,
`calendar_guide_topic_page` +47, `flows_lint` +29, `settings_hub_page` +44.

### 6.5 The gate (2026-11-09)

In the worktree at `d9f34776` + this change: `dart analyze lib test` clean;
`flutter gen-l10n`, `untranslated.txt` `{}`; `flutter test` `+15000 ~17`,
all passed (a first run across the session's end showed two reds that pass
alone: `counter_pn_test`'s older-build envelope case, a known load flake,
and `reminder_word_test`, which caught the one guide string that said
"reminders" for the alert umbrella — now "alerts"). Applied to `main` at
`bb4b9df2` with `git apply --3way`: `dart analyze lib test` clean,
`flutter gen-l10n` a no-op, `flutter test` `+15002 ~17` all passed. Device
pass (`qa-runner`, 2026-11-09, `emulator-5556`, APK built from this tree):
`qa pass settings` 21 / 21 green (`01_drawer_places`, `11_hub_guide`,
`13_restore_calendar_family`, the new `20_guide_books` among them);
`qa pass calendar --only 26_guide --only 27_guide_lessons` 2 / 2 green.

## 7. Deferred

- **Phase 2 — the "Try it" editors: §9 (2026-11-09).** Four cards, each a
  real editor over an in-memory seed, on the markdown, lists, own and
  money pages. Still deferred from it: a practice-note *page* with the
  bar and the title (D17 says why the cards came first).
- **Pairing** is not described: the Sync & sharing page's Pairing section
  links two accounts and says "Linked. Nothing is shared yet." — the guide
  waits for shared folders.
- **Entry points from the editor**: a "How the editor works" row in
  Settings › Editor and markdown, and in the note's ⋮ — the settings page
  keeps its own idiom (folds) and the ⋮ has a rule about ending with
  Settings; both are a small slice when wanted.
- **The notes example of a table** is a read row (D15) until the editor
  draws a grid.
- **`calendarGuideNotesBody`** ("The rest of ANTA") on the calendar's Good
  to know page could point at the notes book by name; left as is so the
  calendar guide's strings do not change in this change.
- **App bugs the reviews surfaced — fixed in §9 (D23–D25, 2026-11-09):**
  the General page's "Auto-save notes" switch and its interval slider were
  read by nothing; "Confirm before delete" had no reader outside its page;
  the bare-`$!` "no target" chip text was hardcoded English.
- **Renderer limits the guide shows at 2.0 (design review 4, 5):** in the
  money preview at de 2.0 the grey `= balance` wraps onto its own line, and
  the ghost placeholders (~2.8:1 light) and the running balance (~3.3:1)
  sit under 4.5:1 on `surfaceContainerLow` — app-wide `LineMarkdownStyle`
  values, left as they are so the guide keeps rendering what a note renders
  (D14); the owner decides whether the renderer should keep `= amount`
  together and lift the dim inks.
- **Device bucket (design review):** TalkBack phrasing of `#`, `•`, `☐`,
  `☑`, `┃`, `Σ`, `Δ`, `◎` inside the example previews; glyph coverage of
  `◎`, `┃`, the callout's icon and `⋮` on a Pixel (the emoji-font trap);
  the real Droid Sans Mono width of the de 2.0 sources; Android 14
  non-linear 200 % scaling of the 13 px eyebrow and source text; the preview
  block's edge in dark; list previews' real heights at de 2.0.
- **The Romanian word for a #tag** — settled in §9 (D26): the editor's
  search zone and the report say *tag*; *etichetă* is the colour label's
  word alone.
- **Editor inks under 4.5:1, now taught by the stage** (design review of
  the cards): `EditorSpanEmitter.dimAlpha` 0.45 puts the dimmed markers and
  the ghost placeholders at 2.78:1 light / 3.76:1 dark on `pageGround`
  (the list-nesting record's "dim-marker contrast" item, same token); the
  light money inks measure 3.84–4.46:1 (`moneyPositive` `#2E7D32` 4.46 on
  the ground, 3.84 on its 0.12 chip tint; negative 4.08 on the chip;
  neutral 4.09) in `lib/constants/markdown_constants.dart` ~221. Both are
  the note editor's own values; lifting them is an app-wide decision. The
  guide's own `GuideTextContrastGuideline` cannot see re_editor's painted
  lines, so only a token test would pin them.
- **The full-bleed stage at 1.0** (design review): B1 chose full bleed at
  every scale so the editor keeps 328 of 360 dp and its text starts under
  the coach line; the calendar cards go full-bleed only from 1.3, and at
  1.0 the notes card reads as a coach strip over a page-coloured band
  joined by hairlines. The alternative is the inset patch
  (`stageFullBleed => false`) with the editor padding reduced so the text x
  stays 32 dp. A taste call; the owner decides.
- **After the keyboard reveal the coach line sits flush under the bar**
  (design review, severity 1): alignment 0.0, inherited from the finding
  card; a few dp of air would need the reveal to aim below the list's top.
- **The Try-it stage passes no `onFormatShortcut`** (review of B1 + B2,
  finding 7): on desktop Ctrl+B / Ctrl+I do nothing in a card, because the
  editor page's handler runs the bar's shortcut inserter. A card could pass
  a minimal toggler; small when wanted.
- **The editor's inline tap zones are under 48 dp** (B2's guideline run):
  a typed `#pr` publishes "Search tag: #pr" over about 32 × 25 dp, in the
  note editor as on the stage. WCAG 2.5.8 exempts inline targets, which is
  why the guide suite lets them off by name; whether the wrapper should pad
  its zones is the owner's call.
- **The fork's selection detector has no `excludeFromSemantics`**
  (`packages/re_editor/lib/src/_code_selection.dart` ~292, found by B1's
  guideline run): every editor — the note editor included — publishes its
  whole box as an unlabelled tap/long-press node beside the text field's.
  One line in the owned fork plus a check of
  `modern_editor_wrapper_semantics_test`; the owner's call, since it changes
  the real editor's semantics tree.
- **`11_hub_guide.txt`**: its header's reasoning for the search-first way
  in (the calendar row used to be the hub list's last) is weaker now; the
  steps still pass because "calendar works" matches no new row.
- **Calendar suite gaps behind the extraction** (code review 6): the glyph
  rule in query mode, the search section order and the full read-row
  keyword set are not pinned by `calendar_guide_page_test.dart`; the
  extraction was verified by reading. The shared `_scrollTo` helper in the
  guide suites ends in `ensureVisible` without a pump and can tap stale
  layout (§6.2).

- **Phase 3's leftovers (§10, 2026-11-11).** *The owner's calls:* the bar
  stands above the note on a card, unlike the app (D29) — the alternative
  is under it, real to look at and under the keyboard on small phones;
  the coach names a button by its label only, and an inline glyph before
  the name (the bar's own icon in the sentence) would make "Money +"'s
  piggy bank findable without a long press — about fifty lines in the
  card's line builder; the static "You type / You get" rows stay (D14);
  the `bar`, `autocomplete` and `counters` pages are still read only — a
  card for autocomplete can run on the stage's bar
  (`MarkdownBar.suggestions` over an in-memory list), one for reordering
  needs the bar's panel, which grows; a row that opens the real Editor
  and markdown page from the shortcuts page (the settings kit has
  navigating rows; the guide has none that leave it). *Accepted from the
  review:* the bar's Undo after a nest, or Bullet List on a nested item,
  credits `outdent`, and Bullet List on the empty item credits `end` —
  each does bring the item out or end the list, and §9.2's rules were
  left as they are (A2); `write` is credited at the first character, so
  the line moves on to the press while she is still typing (A5); on `own`
  a colour pressed without moving off the blank lands inside it and
  stays dim, the line having said to move (A6); the `_gone` return after
  the press's await has no test (D2). *Device bucket:* the real keyboard
  over a card with the bar above the note; the star, the dumbbell and the
  money glyphs on a Pixel; the bar's sideways scroll inside the page's
  list; TalkBack's order through bar, field and editor.

## 8. Must not change

The calendar guide's ids, slugs, strings, enum order, flows and tests; the
`calendar-guide-*` id family; the settings kit and `form_rows.dart` (no new
primitive); the placeholder rule — never retype a label into guide text;
`NavDestinationKind` members are appended, never renamed or reordered; the
drawer row's id `drawer-how-to` and the settings hub's
`settings-hub-row-calendarGuide`; `SimpleMarkdownPreview`'s contract; the
`onboardingHowToHint` string (now true). A new row gets a slug, an icon and
the three languages in one change.

## 9. Phase 2 — the "Try it" editors and the four fixes (2026-11-09)

**Status: BUILT 2026-11-09, UNCOMMITTED pending the owner — planned by the
Fable 5.1 lead (strings en/de/ro, 24 keys plus 10 edits); slices A, B1, B2
and three fix passes by Opus 5.5 implementers; one code review per slice
and one design review of the cards, their findings fixed or recorded
(§9.6, §7); gate green on `main` and `qa pass settings` 21 / 21 with three
card probes (§9.6); left to the owner's phone: the real keyboard lift.** The owner, shown §7's list, said: fix the app bugs the reviews
found, and build the most useful interactive widgets for the guide. Phase
1's content stands unchanged; this section is read on its own by the
implementers (§9.1–§9.4) and the reviewers (§9.1, §9.4, §8).

### 9.1 Decisions D17–D26

- **D17 — Four cards, one stage.** The notes book gets a "Try it" card on
  `markdown`, `lists`, `own` and `money`: the real live-rendering editor
  (`ModernEditorWrapper` over a `ListAwarePasteController`, an
  `EditorRenderController` and an `EditorEditTracker`, exactly as
  `optimized_note_editor_page.dart` wires them) over an in-memory seed. So
  every path the book describes works in the card for free — Enter
  continues a list, Space on an empty item and the swipe nest it, a tap
  ticks a box, `$` lines fold — rather than a model of the editor that
  would drift from it. No practice-note *page* yet (§7): a card on the page
  where a mark is read teaches it in place, and the chrome a stage cannot
  show (the bar, the title, the ⋮) stays in words. The `editor`, `basics`
  and `safe` pages keep read rows only for that reason.
- **D18 — A step is read off the document, never off a tap.** Each step
  carries a check over the lines (`GuideEditorStep.done`), run on every
  text change through the grammar modules — `MarkdownLineShape.headingAt`,
  `MarkdownListSyntax.parse` / `isListLine` / `indentLevel`,
  `MarkdownInlineGrammar.tokenize` (with the card's palette),
  `GhostText.findGhosts`, `MarkdownMoneySyntax.parse` — never a scanner of
  the guide's own (the markdown-engine rule: one grammar per syntax). The
  coach's done set is sticky, so an edit undone later does not un-teach a
  step. A check that only means something after another step
  (`lists-outdent` after `lists-nest`) reads `hasDone` and is otherwise the
  same shape. The seeds satisfy no step, which a test pins.
- **D19 — A tap that would leave the note is a report.** Tag, wiki link,
  web link and money-chip taps reach the wrapper's callbacks as in a note;
  in a card they `say` what a note would do (`notesGuideReport*`, the
  D47/D49 rule) and never quote the typed text, so each report has one
  length and the coach slot one height. The checkbox tap is the one tap
  that acts, because the editor acts on it itself.
- **D20 — The stage is the editor at its default size, not hers.** Font
  `EditorSettings.defaults.editorFontSize` with `followsTextScale: true`,
  height `GuideMetrics.editorStageLines` (6) lines of
  `MarkdownConstants.lineHeight` at the current text scale plus the stage
  padding — fixed from the first frame, scrolling inside when a lesson runs
  past six lines. Her money config (ledger forced on, as §4) and her palette
  arrive asynchronously through `applyMoneyConfig` / `applyPalette` and a
  repaint, never a remount (the editor page's own rule, ~2946). Haptics
  follow the wrapper's default.
- **D21 — The card is the calendar's.** `calendarGuideTrySection` and
  `CalendarGuideTryCard` draw it, their id family parameterised and
  defaulting to the calendar's: `guide-notes-try-<slug>`,
  `guide-notes-try-<slug>-caption`, `guide-notes-try-<slug>-editor` for the
  stage's editor; back and skip keep `try-<slug>-step-back` /
  `try-<slug>-skip-step` (the four slugs collide with no calendar card's).
  Section title `calendarGuideTryIt`, closing line `calendarGuideCoachDone`:
  "Nothing here was real" is as true of a sandbox note.
- **D22 — The keyboard.** The finding card's once-per-focus reveal
  (`_CaptionAboveKeyboard`) becomes a shared widget of the card file; an
  editor card brings its coach line and stage above the IME when the editor
  takes focus, so the line that says what to type is never under the
  keyboard.
- **D23 — Auto-save obeys its switch and slider.** Off: no debounce and no
  half-minute sweep; the note is still written when the page is left, when
  the app pauses, and by a new note's early create — the writes that keep
  the no-lost-text bar — and the status reads unsaved honestly meanwhile.
  The slider's N is the debounce (N s after the last change); the 30 s
  sweep stays. Both are read into `EditorSettings` with the rest of the
  bundle, so `didPopNext`'s reload picks up a change made in Settings behind
  an open editor. `autoSaveIntervalDesc` now says what the slider does, and
  `autoSaveDesc` what off still writes. Two edges settled by the slice-A
  review: off, a forced flush (pause, preview toggle, `didPushNext`) that
  fails keeps its three retry rungs but has no 30 s sweep behind them — the
  error dot stays until the next exit or pause flush, which is what "no
  background writes" means, so D23 wins over §9.4's retry line there; and a
  forced flush that was *held* (a remote merge in progress) or only partly
  written still re-arms the N-second debounce while off, because the
  lifecycle asked for that write and the hold was transient. The stored
  interval is clamped to the slider's 1–30 s (named constants), so an
  imported row of `0` cannot write on every keystroke.
- **D24 — "Confirm before delete" gates every note and folder delete:** the
  rows' menus, the editor's ⋮ Delete, the browser's Delete selected. Off,
  the delete runs at once (a soft delete; there is no bin, D15 stands).
  Calendar, counter and database deletes keep their dialogs: the setting's
  own text names notes and folders.
- **D25 — The bare `$!` chip speaks the language.** `moneyNoTarget` is
  threaded as `MoneyErrorMessages.noTarget` beside the seven messages; the
  English fallback moves next to `MarkdownMoneySyntax.errorMessage`. All
  three surfaces that draw the chip read it: the preview
  (`line_based_markdown_builder.dart`), the live editor's money row
  (`markdown_editor_money_row.dart`, through the money config the span
  builder holds) and the money detail sheet (`money_detail_sheet.dart`,
  through its `AppLocalizations`) — the slice-A review found the last two
  still hardcoded.
- **D24a — Five delete sites, not four.** The open folder's own "Delete
  folder" in the browser's overflow (`_deleteCurrentFolder`) is a note/folder
  delete too and is gated like the others (slice-A review finding 1).
- **D26 — Romanian says *tag*.** `editorZoneSearchTag(Named)` and the
  report's `reportSectionTags` / `reportTag*` move from *etichetă* to *tag*
  ("Caută tagul", "După tag", "tagul {name}", "taguri"), so *etichetă* is
  the colour label's word alone; the guide already said *tag*. German keeps
  *Schlagwort*.

### 9.2 The cards — content catalogue

Keys: seed `notesGuideSeed<Page>`, coach lines `notesGuideCoach<Page><Step>`
(the `own` ghost and colour lines take `open` / `close`), reports
`notesGuideReport<Kind>`. Actions are frozen like slugs.

| Page · card slug | Seed | Steps (action · line key · done when) | Reports |
| --- | --- | --- | --- |
| `markdown` · `markdown` | `notesGuideSeedMarkdown` | `heading` · MarkdownHeading · any line `headingAt != null` · `bold` · MarkdownBold · any `InlineEmphasis` of kind `bold` or `boldItalic` · `list` · MarkdownList · any `parse(line)?.kind == bullet` · `task` · MarkdownTask · any task item with `checked` | link, tag, wiki, money (whatever she types) |
| `lists` · `lists` | `notesGuideSeedLists` | `enter` · ListsEnter · more list lines than the seed's four · `nest` · ListsNest · any list line with `indentLevel >= 1` · `outdent` · ListsOutdent · the document before this change had a list line with `indentLevel >= 1` and this one has none (the transition itself, so a skipped `nest` cannot stand in for one — review finding 3) · `end` · ListsEnd · a blank line directly after a list line and not directly before one (the list ended, rather than a line opened above an item — review finding 2) | same four |
| `own` · `own` | `notesGuideSeedOwn` | `tag` · OwnTag · any `InlineTag` · `ghost` · OwnGhost · any ghost run · `colour` · OwnColour · any `InlineColor`, or an `InlineEmphasis` with a `tintSpec` · `wiki` · OwnWiki · any `InlineWikiLink` | same four |
| `money` · `money` | `notesGuideSeedMoney` | `spend` · MoneySpend · two or more `subtract` lines · `add` · MoneyAdd · an `add` line · `total` · MoneyTotal · a `total` line | same four |

Every card's `reports(l10n)` lists all four reports: a card cannot know
what she will type, and the slot is sized once per locale.

A check reads the document as the stage draws it (D18): a line inside a
code fence, a `%%` comment or front matter — `EditorRenderController.
blockStateAt` / `lineInFence` — is handed to the checks as blank, so `# x`
typed inside a fence credits no heading (review finding 1). The document
also carries the lines as they stood before the change (for `outdent`) and
one shared tokenization per line, computed lazily, so a card with several
inline checks tokenizes each line once per change (review finding 8).

### 9.3 Files

- `lib/models/guide_content.dart` — `GuideEditorStep extends
  GuideCoachStep` with `done(List<String> lines, bool Function(String)
  hasDone)`; `GuideEditorCard(spec, seed)`; `GuideTopic.editorCards`
  (`const []` for the app book).
- `lib/models/notes_guide_tries.dart` — the four cards: specs, seeds, the
  checks as named functions over the grammar modules; pure, tested alone.
- `lib/widgets/guide_try_editor.dart` — `GuideEditorDemo extends
  GuideCardDemo`: owns the controller, the render controller, the edit
  tracker, the focus and scroll controllers, an unused
  `ReEditorSearchController` (the wrapper requires one); seeds with
  `loadText`; listens to the controller and runs the checks; `buildStage`
  returns the sized `ModernEditorWrapper` under
  `SemanticsIds.guideBookTryEditor`; `adoptRenderConfig(money, palette)`.
- `lib/pages/guide_topic_page.dart` — owns the demos as
  `CalendarGuideTopicPage` does (create in `initState`, candidates per
  locale in `didChangeDependencies`, dispose), hands them the money config
  and palette it already loads, lists the Try sections before "How it
  works".
- `lib/constants/semantics_ids.dart` — `guideBookTry`, `guideBookTryCaption`,
  `guideBookTryEditor`; `lib/constants/guide_metrics.dart` —
  `editorStageLines`.
- `lib/widgets/calendar_guide_try_card.dart` — optional `identifier` /
  `captionIdentifier` on the section and the card; the shared keyboard
  reveal (D22).
- Fixes: `lib/services/auto_save_service.dart`,
  `lib/controllers/note_save_coordinator.dart`,
  `lib/models/editor_settings.dart`,
  `lib/controllers/editor_settings_controller.dart`,
  `lib/services/settings_service.dart` (`getEditorSettings`),
  `lib/pages/optimized_note_editor_page.dart`, `lib/widgets/folder_row.dart`,
  `lib/widgets/note_row.dart`, `lib/pages/optimized_folder_content_page.dart`,
  `lib/utils/money_display_config.dart`,
  `lib/utils/markdown_money_syntax.dart`,
  `lib/utils/line_based_markdown_builder.dart`.

### 9.4 Must not change (in addition to §8)

`AutoSaveService`'s exit, pause, retry and hold contracts (`saveBeforeExit`,
`saveOnLifecyclePause`, `SaveHeld`, `SaveRefused`); the early create;
`MoneyErrorMessages` value equality; the calendar cards' ids and suites;
the wrapper's tap and swipe policies; the one-grammar rule; the example rows
and the read rows of every page.

### 9.5 Slices and the gate

- **Slice A — the four fixes** (D23–D26; strings already in the ARBs): one
  `implementer`, in a detached worktree beside B1. Tests:
  `auto_save_service_test.dart` (off: no debounce, no sweep, exit flush
  writes; on again with pending changes: a write after the new debounce;
  interval 12: a write at 12 s, not 5), `editor_settings_controller_test.dart`
  (the two fields), `note_save_coordinator_test.dart` (the forward), a
  builder case for the `$!` chip in German, the delete gate where a harness
  exists.
- **Slice B1 — the stage and the markdown card** (D17–D22, §9.2 row 1,
  §9.3): one `implementer` on `main`. Tests: the checks alone
  (`test/models/notes_guide_tries_test.dart`, seeds satisfy nothing), the
  card on the page (`test/widgets/guide_try_editor_test.dart`: seed shown,
  typing advances the coach, a box tap ticks and completes, ids, de/ro 2.0
  on both phone sizes, the guide guideline matchers of
  `calendar_guide_try_cards_test.dart`), `guide_book_page_test.dart` still
  green.
- **Slice B2 — the lists, own and money cards** (§9.2 rows 2–4): one
  `implementer` after B1; a case per card in the two suites; `20_guide_books`
  gains the markdown page's card (`expect id:guide-notes-try-markdown`, a
  shot).
- **Reviews:** one `reviewer` over slice A; one `reviewer` and one
  `design-reviewer` over B1 + B2 together. **Device pass:** `qa-runner`,
  `qa pass settings -d emulator-5556` after `qa fleet install --build`.
- **Gate** per slice: `dart analyze lib test`, the whole suite, `flutter
  gen-l10n` a no-op. **Land:** on the owner's word.

### 9.6 As built

**Slice B1 (2026-11-09, Opus 5.5 implementer, on `main`).** As §9.3, with
these choices (lettered by the implementer, kept by the lead):

- (a) The page seeds each demo from `didChangeDependencies` before the first
  frame; `seed` runs once, so a language change keeps her text (D20).
- (b) The stage is full-bleed (`stageFullBleed => true`) with the editor's
  own padding `EdgeInsets.symmetric(horizontal: GuideMetrics.cardInset)`, so
  the text starts under the coach line at every scale; height
  `scaledFontSize(defaults.editorFontSize) × MarkdownConstants.lineHeight ×
  GuideMetrics.editorStageLines`, inside the existing `GuideStageSlot`, which
  hands a drag past the editor's end on to the page.
- (c) `paintGround: false`: the stage already paints the page ground.
- (d) Checks take one `GuideEditorDocument(lines, hasDone, palette)`, so the
  bold check reads the card's palette; they run on text changes only, never
  on caret moves; an edit that passes no step takes a standing report down.
- The finding card's `_CaptionAboveKeyboard` became the public
  `GuideCaptionAboveKeyboard` in the card file (`firstMatch` → optional
  `last`); the finding card's suite is unchanged.
- `GuideTopicPage` gained a `didUpdateWidget` path that rebuilds the demos
  when the topic changes: only `guide_book_page_test` pumps topics into one
  state, the app pushes a page per topic.
- Two accessibility offenders the editor brings to the kit guideline suite
  were pinned by name in `settings_kit_guidelines_test.dart`: the re_editor
  fork's touch-selection `GestureDetector`
  (`packages/re_editor/lib/src/_code_selection.dart` ~292, no
  `excludeFromSemantics`) publishes the editor's box as an unlabelled
  tap/long-press node — the real note editor has the same node, so it is the
  owner's call and is in §7; and the wrapper's 18 dp scroll rail at 2.0 —
  B2 drops the rail on the stage (`showScrollIndicator: false`) and the pin.
- Gate in B1's run: `dart analyze lib test` clean; whole suite
  `+15023 ~17 -2`, the two reds being `report_labels_test` and
  `report_group_stack_test` pinning the Romanian *etichetă* that D26 moved
  (slice A updates them); `gen-l10n` a no-op. Not verified on a device: IME
  typing, the drag hand-off, the keyboard lift.

**Slice B2 (2026-11-09, Opus 5.5 implementer, on `main`).** The `lists`,
`own` and `money` cards as §9.2, eleven named checks over the grammar
modules (`notesGuideHasMoreItems`, `…NestedItem`, `…Outdented` (reads
`hasDone('nest')`), `…EndedList`; `…Tag`, `…Ghost` (through `GhostText`,
not the tokenizer's ghost token — (c)), `…Colour`, `…WikiLink`; `…Spends`,
`…Income`, `…Total`). The swipe direction was confirmed in code
(`ModernEditorWrapper._onLineSwipe` → `ListIndentAction.tryApply(outdent:
!toRight)`): right nests, left outdents, as the lines say. The stage drops
its scroll rail (`showScrollIndicator: false`) and B1's pin for it. Choices:
(a) the shared `GuideTapTargetGuideline` gained a fourth named exception —
a labelled node under 48 dp wholly inside a `CodeEditor`'s box, the editor's
inline tap zones (a typed `#pr` publishes "Search tag: #pr" over 32 × 25 dp),
cited to WCAG 2.5.8's inline exception; the same zones are under 48 dp in
the note editor itself, which is outside this change (§7); (b) `enter`
compares with a constant seed count of four, pinned by the seeds test; (d)
the lists walk nests and outdents through real swipe gestures. Suites:
`notes_guide_tries_test` +23, `guide_try_editor_test` +44 (all four pages:
ids, seed, walks to the closing line, matchers in both themes at 360 and
412, de/ro at 2.0), `flows_lint_test` +29; whole suite `+15067 ~17 -2` with
the same two Romanian pins as the only reds. `20_guide_books.txt` opens the
markdown page and expects `guide-notes-try-markdown` with a shot.

**Code review of B1 + B2 (2026-11-09, Opus 5.5 reviewer, read-only).** No
data loss, crash or stuck state; fifteen findings, all PLAUSIBLE except the
line endings (CONFIRMED). Fixed in the fix pass below: (1) the checks read
each line without block context, so `# x` inside a fence credited a heading
(§9.2's new paragraph); (2) `end` passed for a blank line opened *above* an
item (Enter at column 0 of `- Squat`); (3) `outdent` passed on the next
keystroke after a *skipped* `nest`, because `GuideCoach.hasDone` counts
skips — both rules rewritten in §9.2; (4) the demo's `_reportStands` flag
mirrored the coach's state and went stale (a Skip clears the coach's report
but not the flag), and an edit under a read-back line did not snap back to
the live line (D70) — replaced by `changed()` when `reading || hasReport`;
(5) the notes hub's search did not index the coach lines as the calendar
hub does (D58); (6) the stage's money error text kept the language the page
opened in; (8) the own card tokenized the document up to four times per
change — one lazy tokenization per line on the document; (9) the seed test
pinned the `enter` constant in one direction; (10) the report test called
the callbacks directly, no real tap; (11) untested: a language change, the
remount after a scroll, `adoptRenderConfig` not remounting; (12) both
guideline exceptions were broader than their comments; (13) eight new or
moved files were LF in a CRLF tree; (14) comments cited §9.6's letters
without naming the record, five public members without `///`; (15)
`GuideEditorCard.steps` silently dropped a step of the wrong type. Left as
found, recorded in §7: (7) the stage passes no `onFormatShortcut`, so
desktop Ctrl+B / Ctrl+I do nothing in a card (the real page's handler
pulls in the bar's inserter), and the editor's inline tap zones are under
48 dp in the note editor itself. Sound: the lifecycle (every owned object
disposed once; the `didUpdateWidget` swap moves listeners in each widget's
own `didUpdateWidget`), the wiring against the editor page, every done-when
rule as §9.2 then read, the ids (no collision with the calendar's slugs),
the fixed stage height, the verbatim move of the keyboard reveal.

**Fix pass (2026-11-09, Opus 5.5 implementer, on `main`).** All eight items:
`GuideEditorDocument` carries `previousLines`, a lazily memoised per-line
`inlineTokens` (one `tokenize` per line, ghost runs passed in, walking link
text, emphasis content and colour insides outermost first) and
`blankBlocks`; the demo blanks lines through `EditorRenderController.
lineInFence`, whose role covers fence delimiters and bodies, `%%` comments
and front matter (`blockStateAt` walks a segment per call and is for
pastes). `outdent` is the nested → flat transition, `end` requires the next
line absent or not a list line. `_reportStands` is gone; `GuideCardDemo`
gained protected `hasReport` over an additive `GuideCoach.hasReport`, and a
non-step edit calls `changed()` only when `reading || hasReport`. The book
hub indexes the coach lines. On a locale change the topic page rebuilds the
money config's `errorMessages` and re-adopts it. `GuideEditorCard` asserts
every step carries a check; `notesGuideListsSeedItems` is
`@visibleForTesting` and the en/de/ro seeds are pinned at exactly four
items. The inline-zone exception also requires the node narrower than the
editor's box; the kit suite's selection-detector pin matches the editor's
box exactly (intersected with the list's viewport, since the walk scrolls
the editor across its edges). Comments name the record; `///` on the new
members; nine working-copy files normalised to CRLF (the eight plus
`calendar_guide_coach.dart`). New cases: fenced heading / `#pr` / `$-` /
`- [x]`, a `%%` comment and front matter credit nothing; the one-tokenize
memo; Enter at column 0 opens no `end`; a flat list after a skipped `nest`
is no `outdent`; a non-step edit snaps a read-back line to the live one; a
real tap on a typed `#pr` shows the tag report; de → ro keeps the text and
the same `CodeEditor` State while the slot's candidates turn Romanian;
"nests" (a word only the lists card's coach says) finds the lists page in
the hub's search. Gate: analyze clean; the eight named suites `+616`;
whole suite `+15080 ~17 -2` (the two Romanian pins); `gen-l10n` a no-op.
`previousLines` is `const []` for the first evaluation (the seeds are flat,
so no check notices).

**Slice A as built (2026-11-09, Opus 5.5 implementer, worktree
`anta-wt-fixes`).** 19 files, +621/−58, handed over as a patch (l10n, docs
and the plugin registrants `pub get` regenerated excluded) and applied to
`main` with `git apply --3way`, every hunk clean. `AutoSaveService` gained
`enabled` and `configure`; `NoteSaveCoordinator.configureAutoSave`;
`EditorSettings.autoSaveEnabled` / `autoSaveIntervalSeconds` read in
`getEditorSettings`; the editor page applies them with the bundle; the four
delete sites read `getConfirmDelete`; `MoneyErrorMessages.noTarget` with
`MarkdownMoneySyntax.noTargetLabel` as the fallback; the two Romanian test
pins updated; new cases in `auto_save_service_test`,
`editor_settings_controller_test`, `note_save_coordinator_test`,
`line_based_markdown_builder_test`, `optimized_folder_content_page_test`,
`optimized_note_editor_page_test`. The implementer's own whole-suite run in
the worktree hung (one `flutter_tester` alive 58 min on a 4–7 min suite —
the background-suite trap); the lead killed it and cut the patch. The
read-only review of the slice (§9.6 below) ran in the worktree.

**Code review of slice A (2026-11-09, Opus 5.5 reviewer, read-only, in the
worktree).** Twelve findings. Fixed in the slice-A fix pass: (1) a fifth
delete site, the browser's own "Delete folder" (`_deleteCurrentFolder`),
still always asked — D24a; (2) the `$!` chip stayed English in the live
editor's money row and in the money detail sheet — D25 now names all three
surfaces; (5) `configure` while staying off cancelled the recovery timer a
held flush had armed; (6) a second tap on Delete selected during the
settings read dispatched twice; (8) a stored interval outside 1–30 was not
clamped; (11) the 30 s and 5 s defaults were literals beside existing
constants, one `///` missing; (12) tests that would pass with the page
wiring reverted — the editor-page probes, the ⋮ Delete off case, a spy on
the folder count, `copyWith` pins. Settled in the record, no code: (3) off,
a failed forced flush keeps its three rungs and no sweep (D23's edge); (4)
a held or partial forced flush still re-arms the debounce while off (D23's
second edge); (7) the on path now reads the setting before the dialog (two
existing tests gained a settle); (9) a settings read that throws leaves
auto-save on; (10) the `anta-context` reference's auto-save line is updated
by the lead with this record. Sound: `AutoSaveService` against HEAD
(`forceSave`, `_performSave`, hold, refusal, retry, baseline, `dispose`,
`hasAnyPendingChanges` unchanged), every `configure` transition, the early
create and both flushes under off (pinned), the bundle fields in
`copyWith` / `props` / `getEditorSettings`, the page wiring on first load
and on `didPopNext`, the four gates' `mounted` guards, `MoneyErrorMessages`
equality, the Romanian pins.

**Design review of the four cards (2026-11-09, Opus 5.5 design-reviewer,
read-only, on `main`).** Rendered in both themes, en/de/ro, 1.0/1.3/2.0,
360 × 780 and 412 × 915, every coach state and the keyboard up. The spec
holds: stage height 148.8 / 193.44 / 297.6 dp, constant across all 32
configurations and every state; the coach slot fixed across every line
(the four reports and the closing line included), clamped at 1.3 (D66);
the editor's text and the coach line start at one x (32 dp, B1 (b)); back
and skip 48 dp, skip disabled not hidden at the end; read-back inks as D90;
seed text 14.85 / 14.35, checked-task text 4.56 / 6.07, the unchecked box
4.29 / 5.76; no overflow at de/ro 2.0 on either phone. One real defect,
severity 3, CONFIRMED: at de 2.0 on 360 × 780 the keyboard reveal scrolled
the coach line off the screen (slot top −101 dp) because `_reveal` fitted
the whole six-line field under the line instead of one line of it — the
visual fix pass gives the reveal a `lastExtent`. Severity 1, fixed in the
same pass: a sixth line clipped by 1.2 / 2.4 dp because the fork rounds
each line (25 / 32 / 50 dp) and the stage multiplied the unrounded height;
a comment that cited WCAG 2.5.8's inline exception for a task box; the kit
suite's notes case covering one topic and the guide suite's matchers
running at 1.0 only. Left to the owner (§7): the dimmed markers and ghost
placeholders at `dimAlpha` 0.45 measure 2.78:1 light / 3.76:1 dark on the
stage ground and the light money inks 3.84–4.46:1 — app-wide tokens the
stage now teaches; the full-bleed stage at 1.0 reads as a coach strip over
a page-coloured band (the calendar cards go full-bleed only from 1.3); the
reveal leaves the coach line flush under the bar (inherited from the
finding card); `GuideTextContrastGuideline` cannot see re_editor's painted
text, so only a token test could pin the editor's inks. Not seen: the
editor's glyphs in real Roboto (`FontConstants.editorFontFamily` is null,
so the editor stays in the test font) — the device bucket has them.

**Visual fix pass (2026-11-09, Opus 5.5 implementer, on `main`).**
`GuideCaptionAboveKeyboard` gained an optional `lastExtent` (asserted
exclusive with `last`): `_reveal` fits the caption plus that much of the
field's top — the editor passes one rounded line plus
`GuideMetrics.stagePadding` — and the finding card's call is unchanged
(`rect` null). The stage is sized from the fork's rule — the line height is
`TextPainter.preferredLineHeight` of the editor's style
(`packages/re_editor/lib/src/_code_field.dart` ~1804), which the text
engine rounds to the nearest whole pixel (24.8 → 25, 49.6 → 50) — so six
plain lines fit exactly (`(scaledFontSize × lineHeight).roundToDouble() ×
6`; checked at device pixel ratio 1 only, the device bucket has the rest).
The guideline comment names the real reason the inline zones are let off.
The kit suite's notes case loops over all four card topics (8 cells, ~2 s);
the guide suite gained a 2.0 cell (`own`, de, light, 360) for the tap-target
and label guidelines idle and after `#pr` is typed. New cases: de 2.0 on
360 × 780 with a 320 dp inset keeps the coach slot and the stage's hairline
at or below the list's top and the first line above the keyboard (red with
`lastExtent` null: slot top −101); six plain lines in the lists card, the
sixth unclipped and `maxScrollExtent == 0` (red without rounding: 276.2
against 275.0). Gate: analyze clean; the five named suites `+559`;
`gen-l10n` a no-op.

**Slice A fix pass (2026-11-09, Opus 5.5 implementer, worktree; the
increment cut as the unstaged diff over the staged slice and applied to
`main` with `git apply --3way`, clean).** `_deleteCurrentFolder` gated like
the row (D24a; off: no loading dialog, no count, no dialog, pop as before);
the live editor's chip reads `config.errorMessages?.noTarget` (an
`EditorMoneyTotalSpan` placeholder — the line's code units are unchanged,
pinned at exactly two) and the detail sheet `l10n.moneyNoTarget` (D25);
`configure` cancels timers only on the on → off change, so a held flush's
re-armed write survives a delay change while off; `_deletingSelected`
guards a second tap during the settings read (proven: two taps, one
dispatch); `SettingsKeys.autoSaveIntervalMinSeconds` / `MaxSeconds` (1 /
30) feed the slider and the coordinator's clamp (0 → 1 s, 99 → 30 s), and
the lead added the same clamp where the General page loads the stored
value into the slider (an imported `0` would have tripped the `Slider`
assertion); the sweep default is `AppConstants.autoSaveInterval`, the
debounce default `SettingsKeys.defaultAutoSaveInterval`. New cases: off at
open and off behind a pushed route (the `didPopNext` reload) write nothing
after 35 s; ⋮ Delete with confirm off dispatches at once and pops; the
folder-row off case counts zero `getNoteCountForDeletion` calls through a
counting storage fake; `copyWith` carries both fields; "kein Ziel" in the
editor chip. Suites in the worktree: `auto_save_service_test` +60,
`note_save_coordinator_test` +61, `editor_settings_controller_test` +19,
`markdown_editor_span_builder_units_test` +436,
`line_based_markdown_builder_test` +97, `optimized_folder_content_page_test`
+125, `optimized_note_editor_page_test` +138, `settings_page_golden_test`
+3. No money detail sheet suite exists, so the sheet's chip has no test.

**Gate on `main` (2026-11-09, the lead, foreground).** After A + B1 + B2 +
the B fix pass + strings: `dart analyze lib test` "No issues found!";
`flutter test` `04:14 +15102 ~17: All other tests passed!`. After the
slice-A fix pass, the visual fix pass and the slider clamp: `dart analyze
lib test` "No issues found!"; `flutter test` `04:08 +15121 ~17: All other
tests passed!` (17 skipped, no red); `flutter gen-l10n` a no-op with
`untranslated.txt` `{}`. 47 paths changed outside `lib/l10n/` (43 tracked
plus the four new files), uncommitted.

**Device pass (2026-11-09, `qa-runner`, Sonnet 5.5, `emulator-5556`, APK
built from this tree).** `qa pass settings` 21 / 21 green in 299 s
(`20_guide_books` reached the markdown card and took
`20_guide_notes_markdown_try`; `01_drawer_places`, `11_hub_guide` green);
report `build/qa/pass/settings_20261109_205737_152_emulator-5556/`. Probes
through the harness verbs (shots under `build/qa/shots/`): on the markdown
card a tap focuses the editor without the page moving, typing `# ` before
"Leg day" renders the heading with a dim `#` and moves the coach line to
the bold step; on the lists card a 200 px right swipe on "Squat" nests it
and a left swipe brings it back, neither taken by the page scroll — the
coach line stayed on the Enter instruction, which is D18's done set at
work (the line names the first step not yet done; the nest and the outdent
were credited silently and the line jumped straight to `end` once Enter was
pressed); Enter after "Back" then Enter on the empty bullet ended the list
with the closing line, five lines inside the stage, hairline visible,
nothing clipped, no emoji-font glyph. Semantics order: caption, back, skip,
editor; inside the editor the id node, the fork's unlabelled `click,long`
detector (§7) and the text field. Not verifiable in the driver build (it
never raises the soft keyboard): the real IME lift (D22) and the caret
above a real keyboard — the owner's phone. Noticed: the harness's field echo
shows a leading zero-width character after typing, likely the fork's input
sentinel, not new to this change.

## 10. Phase 3 — the bar on the stage and "Your own shortcuts" (2026-11-11)

**Status: BUILT 2026-11-11, UNCOMMITTED pending the owner — planned and
built by the Fable 5.2 lead (the owner: "use Fable more than normal"; Opus,
Sonnet and Haiku allowances nearly spent that day, so no implementer was
briefed); one read-only review (`reviewer` on Fable), its findings fixed or
recorded (§10.6, §7); gate green on `main` and `qa pass settings` 21 / 21
(§10.6); left to the owner's phone: the real keyboard over a card.** The
owner, reading the notes book: there is no page for adding
your own markdown — the custom shortcuts, "a big feature" — and the
markdown pages "feel very few interactive"; improve the ones that can be
better. Phase 1's rows and Phase 2's cards stand; this section adds to
them. An implementer reads §10.1–§10.4, a reviewer §10.1, §10.4, §9.4, §8.

### 10.1 The review (what was found)

- **The cards were typing drills.** Every step asked for symbols typed on a
  phone keyboard — `#`, `**`, `- [ ]`, `{{` `}}`, `{red:` — two or three
  keyboard layers deep, while the app's answer to exactly that, the bar,
  was missing from the stage (D17 left "the chrome a stage cannot show" in
  words). The lead line said "Type them, or let the bar do it" over an
  editor with no bar.
- **Custom shortcuts had one row** (`bar-own`, two sentences) for the
  feature that makes the bar the owner's: text before and after, the three
  kinds, the date format and offset, repeats, counter tokens, categories.
- **Two sentences were not true.** `bar-shortcuts` said a shortcut's text
  can be changed in the list — only a custom one can, a built-in one can
  only be hidden — and it and `bar-own` quoted `shortcuts` ("Shortcuts",
  the ratio line's word) for a section the page titles `markdownShortcuts`.
- **The bar ships buttons no page names:** inline code, code block and the
  rule on the markdown page; `$^` and `$~` on the money page.
- **An app bug on the way:** `ShortcutEditorPage._save` rebuilt the
  shortcut without its `category`, so editing a custom shortcut dropped it
  out of its group.
- Left as they are: the read-only pages (`basics`, `editor`, `safe`,
  `settings`), the example rows' static "You type / You get" (D14 — an
  editor per example cannot shrink-wrap, and the stage is where she acts),
  the calendar and app books.

### 10.2 Decisions D27–D38

- **D27 — The stage gets the bar.** A notes card's stage is the editor
  over the app's own `MarkdownBar` — the widget, not a model of it — with
  the card's buttons: built-ins picked by id from
  `DefaultMarkdownShortcuts.shortcuts` in the shipped order and shown
  whatever their stored visibility (the money buttons ship hidden), and
  the utility buttons a lesson uses (undo and redo everywhere; indent and
  outdent on `lists`). No split, no settings, no reorder, no paste, no
  font buttons. A press takes the note editor's path: focus first, then
  `MarkdownShortcutInserter` for the ghost and colour slots, else
  `ShortcutApplier.resolve` and one guarded, revocable write
  (`optimized_note_editor_page.dart` `_handleShortcut` is the model;
  the two event sheets mirror it the same way). The H button opens its
  menu of levels on a tap, as in a note, with the caret line's level
  checked: the stage passes `currentHeadingLevel`.
- **D28 — The coach leads with the bar.** Where a button writes the mark,
  the line names the button by the app's own label (a placeholder, D5) and
  says what it wrote; a mark with no button (a tag, a wiki link) stays
  typed. D18 is unchanged — a step is read off the document — so a press,
  a typed mark and a paste still count alike, and every Phase 2 walk-through
  test still passes by typing. Each line says where the caret goes first
  ("Tap “Leg day”, then…"), because a press writes at the caret.
- **D29 — The bar leads the stage.** The stage is flush (`stageFlush`):
  the bar at its top edge, right under the coach line that names its
  buttons, then the stage's air, the maker field where a card has one, the
  six-line editor and the air under it. Above the note, not under it as in
  the app: there the keyboard holds the bar in view, while a bar under six
  lines sat under the keyboard on a 360 × 780 phone from 1.3 up (and on
  the shortcuts card at 1.0), so every step after the first tap began with
  a scroll (review A4; the first build had it at the bottom). Now the
  coach line, the bar and her first line share the screen with the
  keyboard up (pinned in German at 1.3). One row in the card's order
  (`splitEnabled: false`, `pinUndoRedo: false` — a lesson's buttons lead
  and the row scrolls sideways past them, as the real bar does). The bar
  stands on the stage's ground over a hairline, not on its own `surface`:
  in light that surface is the card's, and a white bar read as the card's
  edge rather than the note's (seen in the real-font render); in dark the
  two were already one tone. The card's height grows by the bar's row
  once, on every notes card; nothing moves afterwards.
- **D30 — The caret starts at the end of the seed,** so a press before any
  tap lands where a line would be added, never at the top of the note. The
  money seed gains a last empty line for that.
- **D31 — A step is done when its mark is drawn.** The colour step needs
  coloured text, not the empty slot the button leaves (`{red:{{  }}}`
  draws a dim blank) — nor that slot wrapped in a second colour by a
  second press, whose inner markers are chrome, not text (review A1). A
  bare `$- ` is no money line, so the spend still waits for its amount,
  and a money row the ledger draws as an error (an amount past the digit
  limit) is no spend and no income (review A7). The ghost and the total
  are drawn by the press.
- **D32 — "Your own shortcuts" is a page** (`shortcuts`, after `bar`,
  icon `Icons.smart_button_rounded`): what a shortcut is, a card, ten read
  rows that walk the New Shortcut page by its own labels, two recipes.
  `bar-own` stays as the pointer to it.
- **D33 — Its card runs real shortcuts.** The bar holds three
  `CustomMarkdownShortcut`s the guide builds in the page's language and
  the real applier runs: **Set** (a checkbox line with the set's number
  from a `{c1}` counter token and two `{{blanks}}`, ending in a line
  break), **Today** (the `date` kind: `## `, the date, a line break) and
  **hers** (a star). The counter is the demo's own, in memory, starting
  at 1; nothing is read from or written to her counters.
- **D34 — She makes one in the card.** Between the bar and the editor the
  stage shows one field with the New Shortcut page's own label,
  `markdownStart`; her button writes exactly that text at the caret. Above
  the note: the keyboard's reveal keeps the coach line and the focused
  field together only when nothing tall stands between them (D22). Two steps: `write` (the
  field is not empty) and `press` (her button wrote it). The press is the
  lesson, so `press` reads a count the stage keeps, not the document — the
  one step that is a tap (D18's exception, as the checkbox tap is D19's).
  An empty button says so (`notesGuideReportEmptyButton`).
- **D35 — Recipes are example rows with their own eyebrows.** A
  `GuideExampleEntry` may name its two labels; a recipe shows
  `markdownStart` over "One tap writes".
- **D36 — The missing rows.** `markdown-code` (inline code, code block,
  rule), `money-back` (`$^`, `$~`), and the two `bar` sentences corrected;
  the notes book's hub caption names the new page.
- **D37 — Editing a shortcut keeps its category** (`_save` carries
  `widget.shortcut?.category`).
- **D38 — No new primitive.** The stage's field is the shortcut editor's
  outlined `TextField`; the bar is the bar; the card chrome is unchanged.
  New numbers join `GuideMetrics`.

### 10.3 The cards and the page — content catalogue

Keys as §9.2. A changed coach line keeps its key and its action; the
placeholders are the button labels, in order.

| Card | Bar in drawn order (ids without `default_`) · utilities | Steps (action · line key (placeholders) · done when) |
| --- | --- | --- |
| `markdown` | checkbox, bullet_list, numbered_list, bold, italic, header, strikethrough, highlight, quote, link · undo, redo | `heading` · MarkdownHeading(headers) — the button opens the level menu, the line says to pick one · as §9.2 · `bold` · MarkdownBold(bold) · as §9.2 · `list` · MarkdownList(bulletList) · as §9.2 · `task` · MarkdownTask(checkbox) · as §9.2 |
| `lists` | checkbox, bullet_list, numbered_list · indent, outdent, undo, redo | `enter` · unchanged · `nest` · ListsNest(indentLine) · as §9.2 · `outdent` · ListsOutdent(outdentLine) · as §9.2 · `end` · unchanged |
| `own` | callout, date, ghost, color_text, color_highlight · undo, redo | `tag` · unchanged · `ghost` · OwnGhost(shortcutGhostText) · as §9.2 · `colour` · OwnColour(shortcutColorText) · a colour run or tinted highlight whose inside holds text outside any ghost and outside any colour run nested in it (D31) · `wiki` · OwnWiki, reworded for a line of its own |
| `money` | money, money_subtract, money_set, money_total, money_delta, money_target · undo, redo | `spend` · MoneySpend(shortcutMoneySubtract) · as §9.2, error rows left out (D31) · `add` · MoneyAdd(shortcutMoneyAdd) · the same · `total` · MoneyTotal(shortcutMoneyTotal) · the same |
| `shortcuts` (new) | Set, Today, hers (D33) · undo, redo · the `markdownStart` field | seed `notesGuideSeedShortcuts` · `line` · ShortcutsLine(set label), which sends the caret to the empty line first · a task item holding a ghost · `count` · ShortcutsCount(set label) · two task items · `date` · ShortcutsDate(today label) · a heading line · `write` · ShortcutsWrite(markdownStart) · the field is not blank · `press` · ShortcutsPress(her label) · her button wrote its text |

The `shortcuts` page (`NotesGuideTopic.shortcuts`, keys
`notesGuidePageShortcuts` / `…Caption`, `notesGuideShortcutsLead`): rows
`shortcuts-make` · `Icons.add_circle_outline_rounded` · ShortcutsMake ·
body(settingsRowEditor, newShortcut, save) · `shortcuts-text` ·
`Icons.text_fields_rounded` · ShortcutsText · body(markdownStart,
markdownEnd) · `shortcuts-kinds` · `Icons.category_rounded` ·
ShortcutsKinds · body(insertType, wrapSelectedText, insertCurrentDate,
insertCounter, beforeDate, afterDate) · `shortcuts-preview` · `Icons.visibility_rounded` ·
ShortcutsPreview · body(preview) · `shortcuts-blanks` ·
`Icons.data_object_rounded` · ShortcutsBlanks · body(open, close) ·
`shortcuts-repeat` · `Icons.repeat_rounded` · ShortcutsRepeat ·
body(advancedOptions, repeatSettings, incrementDateOnRepeat) ·
`shortcuts-date` · `Icons.event_rounded` · ShortcutsDate ·
body(dateOffset, advancedOptions) · `shortcuts-counters` ·
`Icons.pin_rounded` · ShortcutsCounters · body(counterBindingsTitle,
advancedOptions, open, close) · `shortcuts-tidy` · `Icons.visibility_off_rounded` · ShortcutsTidy
· body(setCategory) · `shortcuts-bars` · `Icons.view_carousel_rounded` ·
ShortcutsBars · body(manageBarProfiles); recipes `recipe-set`
ExRecipeSet (source: open, close) · `recipe-label` ExRecipeLabel (source:
open, close), eyebrows `markdownStart` / `notesGuideRecipeShown`.

Facts the text rests on (verified 2026-11-11 in
`shortcut_editor_page.dart`, `markdown_settings_page.dart`,
`shortcut_applier.dart`): the Editor and markdown page's + is a floating
button and a new shortcut is appended to the edited bar's list; fields in
order — icon, label, insert type (wrap / date / counter), the date
format list, the advanced switch (date offset, repeat with separator,
wrapper text and a date step per copy, counter bindings with `{c1}` /
`{c2}`), start, end, preview; for the date kind the two text fields are
labelled `beforeDate` / `afterDate` and switching to it clears both; a
wrap writes start + selection + end and leaves the caret after it (a
plain symmetric pair such as `**` toggles instead); each `{cN}` expansion
mutates its counter once; the list hides (eye), drags (handle or long
press), sets a category (⋮) and, for a custom shortcut only, edits and
deletes (⋮); category chips are toggles that filter the list, several at
once; shortcuts are stored per bar profile. `$^ N` shows the change across the
last N balance-changing entries and `$~ N` across the last N `$=`
checkpoints; neither changes the balance.

### 10.4 Files and must not change

- `lib/models/guide_content.dart` — `GuideEditorCard.bar` /
  `utilities` / `maker`; `GuideEditorDocument.makerText` / `ownPresses`;
  `GuideExampleEntry.typedLabel` / `shownLabel`.
- `lib/models/notes_guide_tries.dart` — the bars, the reworded steps, the
  `shortcuts` card and its checks, the stricter colour check.
- `lib/widgets/guide_try_editor.dart` — the bar, the press path, the
  in-memory counter, the maker field.
- `lib/models/notes_guide_content.dart`, `lib/widgets/guide_example_row.dart`,
  `lib/constants/guide_metrics.dart`, `lib/constants/semantics_ids.dart`,
  `lib/pages/shortcut_editor_page.dart` (D37), the three ARBs.
- Must not change, beyond §8 and §9.4: `MarkdownBar`, `ShortcutApplier`,
  `MarkdownShortcutInserter` and the editor page (the stage is one more
  host, never a reason to change them); the done-when rules of §9.2 except
  the colour's and the money rows' error state (D31); slugs, actions and
  ids already frozen; the calendar cards'
  chrome (`CalendarGuideTryCard` is not edited); the six-line stage and its
  `guide-notes-try-<slug>-editor` box; `CustomMarkdownShortcut`'s JSON.

### 10.5 Slices and the gate

1. The bar on the four cards (D27–D31) and their lines.
2. The `shortcuts` page and its card (D32–D35).
3. The rows and the fix (D36, D37).

Gate per slice: `dart analyze lib test`, the guide suites; at the end the
whole suite once in the foreground, `flutter gen-l10n` a no-op with
`untranslated.txt` `{}`, one `reviewer` over the whole diff, `qa pass
settings`. Land on the owner's word.

### 10.6 As built

**The build (2026-11-11, the Fable 5.2 lead, on `main`).** As §10.2–§10.4;
no new file under `lib/`. `GuideEditorDemo` gained the bar (`_buildBar`:
the real `MarkdownBar`, `showBackground: false` on the stage ground, one
unpinned row, `utilityConfigs` from the card), the press path
(`_onShortcut`, mirrored on the editor page's `_handleShortcut`), the
arrows (`_shiftIndent` → `ListIndentAction.apply`), the heading reader, a
`ValueNotifier<(bool, bool)>` for undo and redo so the bar is rebuilt when
one of them flips and never per keystroke, the counters map, the maker
field with its own `GuideCaptionAboveKeyboard`, and `_runChecks` split
from `_onTextChanged` so the field's changes run the checks too. One trap
on the way: `ModernEditorWrapper` reports a programmatic write through
`onTextChanged` synchronously, so the own-button press is counted before
its write — counted after, the checks had already read the note without
it. Strings: 43 new keys and 17 edited ones in en/de/ro. The look was
judged from a real-font render (light, dark, German at 2.0, the whole
shortcuts page): it is what moved the bar off its own white surface.

**Code review (2026-11-11, `reviewer` on Fable 5.2, read-only).** No data
loss, crash, leak or must-not-change violation; the press path, the
history notifier, the dispose order, the labels (every coach placeholder
is the getter the button's tooltip uses) and the facts of §10.3 held.
Fixed in the same session: (A1) two presses of a colour button credited
the colour step, the nested run's markers counting as text — the check now
leaves a nested colour run to answer for itself; (A3) the shortcuts card's
first line did not say where the caret goes, and a press with the caret
in "Leg day" wrote mid-line, credited nothing and used up Set 1 — the line
now sends her to the empty line; (A4) the bar under the editor could sit
under the keyboard — D29 was rewritten, the bar leads the stage; (A7) the
money checks counted error rows; (B1) the category chips "show one group
at a time" — they are toggles, the text says "filter it by group"; (B2)
Counter Bindings was not placed under Advanced Options; (B3) the date
kind's two fields are `beforeDate` / `afterDate`, now named; (B4) the
colour line's word read as an adverb in German and Romanian, now quoted in
all three; (B5) a German accusative; (B6) the + is the page's, not the
list header's; (B7) "lists" had fallen out of the book's caption; (C1–C5)
this record's status, the heading menu being a tap, two orders in §10.3's
table, the bar's ground, a doc comment; (D1) the star's glyph is pinned;
(E1) the own press runs the checks once; (E2) `seed()` resets the history
notifier; (E3) the two example ids are constants. Recorded, not changed
(§7): A2, A5, A6, D2.

**Gate on `main` (2026-11-11, the lead, foreground).** Before the review:
`dart analyze lib test` "No issues found!", `flutter test` `+15687 ~17:
All other tests passed!`. After the fix pass: `dart analyze lib test` "No
issues found!"; the eight guide suites `+353`; `flutter test` `+15691 ~17:
All other tests passed!`; `flutter gen-l10n` a no-op with
`untranslated.txt` `{}`. 22 tracked paths changed, no new file, every one
CRLF. New cases: the bar's buttons in the shipped order with undo and none
of the rest; the caret at the seed's end; the markdown, lists, own and
money walks on the bar alone; one press is one undo; a language change
renames the buttons in place; the keyboard up in German at 1.3 on 360 ×
780 keeps the coach line, the bar and her first line in view; the
shortcuts card's layout, its walk (Set 1, Set 2, a dated heading, the
empty-button report, her text, her press), her text typed by hand is no
press, a mid-line press credits nothing, the keyboard under her field;
the colour slot and its nested forms, error rows, the two example
shortcuts in three languages, every bar's ids; the recipes' eyebrows; the
category kept on save.

**Device pass (2026-11-11, `qa-runner` on Fable 5.2, `emulator-5556`, APK
built from this tree at `a71e3c69` + dirty).** `qa pass settings` 21 / 21
green in 291 s, no rerun; `20_guide_books` ran its 43 steps — the
markdown card's bar, the scroll to the shortcuts row, the shortcuts card,
its field and its bar — and its `errors` step was clean; report
`build/qa/pass/settings_20261111_172817_471_emulator-5556/`. One probe
through the harness: two taps on "Set" (by label, inside
`guide-notes-try-shortcuts-bar`) wrote "Set 1: weight kg × reps" and
"Set 2: …" as checkbox lines with dim blanks under "Leg day", the caret on
the empty line below, the coach on the Today step, Undo enabled and Redo
not, nothing in the logs. Seen by the lead in the two flow shots and the
probe's: the bar under the coach line on the stage's ground between two
hairlines, eight of the markdown card's ten buttons in view on a Pixel 9
Pro with the fade at the right edge, the `markdownStart` field between
bar and editor, the dumbbell, calendar and star drawn as glyphs. Not
verifiable in the driver build, as in Phase 2: the real keyboard's lift.
