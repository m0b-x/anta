---
name: gym-notes-context
description: Load project context before any change in the ANTA Flutter app (Dart package `anta`). Covers product purpose, architecture flow, non-negotiable rules, style rules, and which validation commands to run. USE FOR - implementing or changing folders, notes, the editor, markdown shortcuts, the money ledger, counters, search, backup/restore, settings, navigation, import/export, or any feature work in this repo. Load the more specific skills (calendar-events, markdown-engine, drift-migrations, l10n) on top of this one when the task touches those areas.
---

# ANTA Context

ANTA is an **offline-first Flutter app for tracking the things you keep coming back to** — training sessions, spending, appointments, and the notes around them. Folders and markdown notes are the substrate; the money ledger, the calendar, and counters are built on top of them.

It started as a training log, and that origin still sets the bar: capture must be fast and reliable in the middle of something else — no lost text, no layout shifts, minimal taps. When two designs are otherwise equal, pick the one that survives one-handed use.

The Dart package is `anta` and the app id is `com.alexzamfir.anta`. Two names look like stale branding and are **not**: the `frontend/gym_notes_track_app/` directory, and the on-disk `gym_notes` database directory (`database_manager.dart`, `database.dart`) that holds every install's `.db` files and `device_id`. Never rename either.

## 1. Read the canonical context first

Read [COPILOT_CONTEXT.md](../../../COPILOT_CONTEXT.md) before planning or editing. It is the source of truth for product purpose, stack, architecture, feature areas, persistence rules, UX direction, and error handling. Do not restate it to the user; follow it.

## 2. Architecture flow (never bypass layers)

```
Page/Widget -> BLoC -> Service -> Repository -> DAO -> Drift database
```

- BLoCs (`lib/bloc/`) stay thin: route events, manage loading/error state, delegate to services. States/events are sealed + `Equatable` where that is the local pattern.
- Services (`lib/services/`) own workflows (note storage, counters, settings, backup, auto-save, import/export, calendar events...).
- Repositories (`lib/repositories/`) provide cached/reactive access over DAOs — invalidate caches after create/update/delete/move/reorder.
- DAOs (`lib/database/daos/`) own SQL/Drift, transactions, soft deletes, FTS, migrations.
- Constants live in `lib/constants/` — use existing spacing/text/icon/settings-key/JSON-key constants, never magic values.
- DI is `get_it` via `lib/core/di/injection.dart`.

## 3. Non-negotiable rules

- Every user-visible string goes through `AppLocalizations` — update `lib/l10n/app_en.arb`, `app_de.arb`, `app_ro.arb` together, then run `flutter gen-l10n` (see the `l10n` skill).
- Never hand-edit generated files (`lib/database/database.g.dart`, generated localization Dart files).
- Drift schema changes require a migration + `dart run build_runner build --delete-conflicting-outputs` (see the `drift-migrations` skill). Never reset user storage.
- **No code comments, no new tests, no new markdown docs unless explicitly requested.**
- Preserve data semantics: soft deletes, CRDT fields (`hlcTimestamp`, `deviceId`, `version`, `isDeleted`), positions, sort preferences, pinned counters, backup format compatibility.
- Settings go through `SettingsService` + `SettingsKeys` — never raw `SharedPreferences` keys.
- UI: Material 3, compact, touch-friendly, stable layouts (no layout shift in editor/toolbar/counters/lists), light/dark/system themes.
- No new state-management, persistence, or navigation patterns without a strong reason.

## 4. Feature-area pointers

- Folder/note browser: `lib/pages/optimized_folder_content_page.dart`.
- Note editor: `lib/pages/optimized_note_editor_page.dart` (re_editor, toolbar, preview, auto-save — see the `markdown-engine` skill).
- Counters: `lib/services/counter_service.dart`, `counter_management_page.dart`, `counter_per_note_page.dart`. Global counter values use `noteId == ''` in `counter_values`. Shortcut counter bindings: `CustomMarkdownShortcut.counters` (max 2) with `{c1}`/`{c2}` tokens expanded by `ShortcutApplier`.
- Auto-save: `lib/services/auto_save_service.dart` — be careful with debounce, interval saves, lifecycle flushes, retries.
- Backup: `lib/services/backup_service.dart` — versioned JSON; keep old backups importable when adding persisted fields.
- Import/export: UI only through `ImportExportBloc`; `createX` stamps timestamps to now, `importX` preserves caller timestamps; archive schema bumps require bumping `ImportExportService.archiveVersion` and accepting the previous version in `_assertSupportedManifest`; exports go through `shareExport` (temp-file cleanup) — never call `SharePlus` directly from pages/blocs.
- Multi-database: `lib/services/database_manager.dart`. Any DB-backed singleton must follow the `DatabaseLifecycle` reset contract (see the `drift-migrations` skill).
- Last-location restore: `AppNavigator.restoreLastLocation()` from `main.dart`; keep existence checks — never navigate to a deleted folder/note.
- Local editor fork: `packages/re_editor/` — preserve its perf optimizations (2-slot `asString` cache, bounded LRU paragraph cache, binary-search lookups, 50 ms highlight debounce, `cloneShallowDirty()` contract).

## 5. Validation (PowerShell on Windows)

Run only what the change requires:

| Change type | Commands |
| --- | --- |
| UI-only Dart change | `dart analyze lib` |
| ARB / l10n change | `flutter gen-l10n`, then `dart analyze lib` |
| Drift table / DAO / migration | `dart run build_runner build --delete-conflicting-outputs`, then `dart analyze lib` |
| Code covered by `test/` (e.g. money syntax) | `flutter test` (single file: `flutter test <path>`; single case: `--plain-name "<substring>"`) |
| Manual run | `flutter run` |

Helper scripts: `.\build_release.bat arm64`, `.\install_to_device.bat arm64`, `.\generate_drift.bat`.

## 6. When to ask vs act

Act without asking when the request is concrete and matches existing patterns. Ask only when a change would break persisted-data backward compatibility, change backup format semantics, or introduce a new architectural pattern.
