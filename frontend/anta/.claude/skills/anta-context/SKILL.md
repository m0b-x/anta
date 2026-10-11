---
name: anta-context
description: The map of the ANTA Flutter app for the areas that have no skill of their own - the folder and note browser, counters, settings pages, auto-save, backup and multi-database, import/export, navigation and launch restore, search, sync and accounts, permissions - with the entry points and the on-demand reference files that hold each area's facts. Load for any change in those areas, for a plan that spans areas, or when you need to find where something lives. CLAUDE.md already carries the architecture and the rules; this skill adds the where and the per-area invariants. Load the area skill instead (or as well) for the calendar, the markdown engine, the database, strings and UI work.
---

# ANTA map

CLAUDE.md is in your context: the architecture flow, the non-negotiable rules, the commands, the OS you are on. This skill is the "where": the entry points per area and the reference files that hold each area's facts. Read a reference only for the part the task needs; `overview.md` holds the product framing when a decision needs it.

## Entry points per area

- **Folder/note browser**: `lib/pages/optimized_folder_content_page.dart` — nested folders, pagination, sorting, manual reorder, swipe actions, move history, selection bar. Its rows are the browser's content rows (`lib/widgets/content_rows.dart`, the `ui-language` skill).
- **Note editor**: `lib/pages/optimized_note_editor_page.dart` with six page-owned controllers under `lib/controllers/` — `EditorSettingsController`, `NoteEditorPositionController`, `NoteSaveCoordinator`, `EditorEditTracker` (paste reflow, Enter list continuation, `runGuarded` for programmatic inserts), `NoteEditorStatsTracker`, `EditorRenderController` — plain classes and `ChangeNotifier`s, never a BLoC on the typing path; the wrapper's tap/Tab/ghost rules are the pure `EditorInputPolicy` in `lib/utils/`. Rendering rules: the `markdown-engine` skill.
- **Toolbar and shortcuts**: `lib/widgets/markdown_toolbar.dart`; `markdown_settings_page.dart`, `shortcut_editor_page.dart`, `note_bar_assignment_page.dart`. Counter bindings on a shortcut: `CustomMarkdownShortcut.counters` (max 2) with `{c1}` / `{c2}` tokens expanded by `ShortcutApplier`; keep the legacy `counterId` populated when `insertType == 'counter'`.
- **Counters**: `lib/services/counter_service.dart` (cache, debounced writes, pinning, ordering), `counter_management_page.dart`, `counter_per_note_page.dart`. Global counter values use `noteId == ''` in `counter_values`; respect `scope`, `isPinned` and ordering.
- **Auto-save**: `lib/services/auto_save_service.dart` — debounce, interval saves, lifecycle flushes, retries; the page's `NoteSaveCoordinator` owns early create and duplicate titles.
- **Backup**: `lib/services/backup_service.dart` — versioned JSON; every new persisted field defaults when absent so old backups keep importing.
- **Import/export**: `lib/services/import_export_service.dart`; UI only through `ImportExportBloc`; exports through `shareExport`; `createX` stamps now, `importX` preserves; an archive version bump accepts the previous version — `references/import-export.md`.
- **Multi-database**: `lib/services/database_manager.dart`; every DB-backed singleton follows the `DatabaseLifecycle` reset contract (the `drift-migrations` skill).
- **Navigation and launch restore**: a persisted stack of `NavDestination`s (`lib/models/nav_destination.dart`) recorded by `NavigationHistoryObserver` / `NavigationHistoryService` off the route stamps `AppNavigator` puts in `RouteSettings.arguments`, replayed by `AppNavigator.restoreLastLocation()` from `main.dart`. Keep the existence checks — never navigate to a deleted folder or note — and never await a push during replay. The whole design: `references/navigation.md`.
- **Keyboard inset**: `KeyboardInsetGuard` (mounted once by `MaterialApp.builder`, above the navigator) and `WindowInsetsResync`; read the inset through `MediaQuery` only — `View.of(context)` bypasses the guard — and never add a per-page stale-inset gate.
- **Search**: SQLite FTS plus the app-level index (`lib/services/` search services); `SearchBloc` keeps a pending query so a stale debounced keystroke cannot overwrite a newer one.
- **Settings**: `SettingsService` + `SettingsKeys`; every settings page speaks the settings kit (`SettingsSectionList` / `SettingsSectionData` / `SettingsEntry` under `SettingsAppBar`), so restyling it is one app-wide decision (`docs/ui-language-adoption-roadmap.md`), never a change to one page.
- **Sync and accounts** (Phase 01, identity and pairing): `references/sync-and-accounts.md`; the roadmap and phase docs in `docs/cloud-sync-*.md`.
- **Permissions** (notifications, alarms, the Android 13+ flow): `references/permissions.md`.
- **Theme**: explicit `AppTheme` + `SurfaceRoles` (a seed cannot reproduce the approved palette); folder icons are `primary`, the mock carries one accent — guarded by `test/constants/app_theme_test.dart`.

## Good defaults for a new tracking feature

Prefer note markdown content, a counter or a setting over a new table; a new table or column is a migration plus backup and import/export coverage plus a DAO test. Every new service or bloc ships with a focused suite against fakes. A new screen speaks one of the four idioms of the `ui-language` skill.

## References

| File | Holds | Read when |
| --- | --- | --- |
| `references/overview.md` | product purpose, core workflows, the rules as first written, stack, architecture shape, error handling, good defaults | a decision needs the product framing or the original wording of a rule |
| `references/feature-areas.md` | the browser, editor, search bar, toolbar, settings pages, counters, auto-save, backup, import/export and database manager described in detail | working inside one of those areas |
| `references/navigation.md` | the navigation and launch-restore design (stack, observer, replay, the launch-race seal) | any change to routes, restore, the drawer or the back behaviour |
| `references/import-export.md` | the import/export pipeline rules | archives, sharing, importing |
| `references/sync-and-accounts.md` | identity, pairing, the sync gateway seams | anything under the sync bloc or services |
| `references/permissions.md` | the permission system and its Android rules | notification or alarm permission work |
| `references/docs-index.md` | one line per design record in `docs/` | looking for the record of a past decision |

The calendar's facts live under `calendar-events/references/`, the markdown engine's under `markdown-engine/references/`, persistence under `drift-migrations/references/`, the QA harness under `qa-emulator/references/`, the UI language under `ui-language/references/`.
