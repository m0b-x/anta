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
each is reversible in one line.

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

- **Phase 2 — a practice note and "Try it" editors.** A sandbox
  `CodeEditor` over an in-memory note, with the calendar's coach frame:
  write a heading, make a list, nest an item, tick a task, add a money
  line. The equivalent of the practice calendar; the most valuable page
  and the most expensive. Owner's call after the content has been used.
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
- **App bugs the reviews surfaced, outside this change (owner's call):**
  the General page's "Auto-save notes" switch and its interval slider are
  read by nothing (`getAutoSaveEnabled` / `getAutoSaveInterval` only from
  `settings_page.dart`; the editor's `AutoSaveService` is built with fixed
  5 s / 30 s) — the guide stopped naming them; "Confirm before delete" has
  no reader outside its page either; the bare-`$!` "no target" chip text is
  the hardcoded English `' no target '`
  (`line_based_markdown_builder.dart` ~1534), so a German or Romanian
  reader of a bare `$!` with no target above sees English — it needs a key
  threaded through `MoneyErrorMessages`.
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
- **The Romanian word for a #tag**: the editor's search zone label
  (`editorZoneSearchTag`, "Caută eticheta") uses *etichetă*, the colour
  label's word; the guide says *tag*. One of the two should move — the
  owner's call, since Romanian readers meet both.
- **`11_hub_guide.txt`**: its header's reasoning for the search-first way
  in (the calendar row used to be the hub list's last) is weaker now; the
  steps still pass because "calendar works" matches no new row.
- **Calendar suite gaps behind the extraction** (code review 6): the glyph
  rule in query mode, the search section order and the full read-row
  keyword set are not pinned by `calendar_guide_page_test.dart`; the
  extraction was verified by reading. The shared `_scrollTo` helper in the
  guide suites ends in `ensureVisible` without a pump and can tap stale
  layout (§6.2).

## 8. Must not change

The calendar guide's ids, slugs, strings, enum order, flows and tests; the
`calendar-guide-*` id family; the settings kit and `form_rows.dart` (no new
primitive); the placeholder rule — never retype a label into guide text;
`NavDestinationKind` members are appended, never renamed or reordered; the
drawer row's id `drawer-how-to` and the settings hub's
`settings-hub-row-calendarGuide`; `SimpleMarkdownPreview`'s contract; the
`onboardingHowToHint` string (now true). A new row gets a slug, an icon and
the three languages in one change.
