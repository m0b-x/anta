---
name: drift-migrations
description: Workflow for Drift SQLite schema changes, migrations, the DatabaseLifecycle singleton reset contract, and backup compatibility in ANTA. USE FOR - adding/altering tables or columns, writing migrations, changing DAOs, adding a DB-backed singleton service, multi-database switching behavior, or extending backup/restore. Load together with anta-context.
---

# Drift Schema Changes & Database Lifecycle

## Golden rules

- **Never reset or wipe user storage** to fix schema drift — always write a migration. Migrations must be idempotent (guard with `PRAGMA table_info(...)` / `CREATE TABLE IF NOT EXISTS`, matching existing v13–v15 patterns).
- Never hand-edit `lib/database/database.g.dart` — after any table/DAO/migration/annotation change run:
  ```powershell
  dart run build_runner build --delete-conflicting-outputs
  dart analyze lib
  ```
  (`tool\release\release.cmd gen` wraps the build_runner call, plus gen-l10n.)
- Preserve CRDT metadata on folder/note/chunk tables (`hlcTimestamp`, `deviceId`, `version`, `isDeleted`, `deletedAt`) and soft-delete semantics. Reorders are transactional and preserve user positions.
- Keep FTS/app-level search indexes in sync on create/update/delete/move.
- Prefer avoiding a migration when the data can ride an existing JSON payload (precedent: recurrence `interval` inside `rule_payload`) or be derived/rebuilt from note content (precedent: planned `TagIndex`).

- **A step is frozen at the shape it shipped with.** Never let an old step call a definition that follows the live schema (a `DatabaseIndexes` helper, `m.createTable`, a DAO) once that definition can name a column or table a *later* step adds. v31 called `createCalendarDeltaIndexes()`; v37 widened that index with `status`; every upgrade from v30 or older then failed with `no such column: status` (found 2026-09-20, together with the same trap in v10 → `is_deleted`). Only the **newest** step defining an index shares the helper with `createAllIndexes()`; every older step touching that name carries its own frozen `CREATE INDEX`, and the newer step drops and recreates. Changing an index or table shape means freezing the older callers in the same change.
- **Steps are atomic, and still idempotent.** Drift does not wrap `onUpgrade` in a transaction and stamps `user_version` only after the whole chain. `DatabaseMigrations.runMigrations` runs each step in its own transaction with `PRAGMA user_version = <step>`, so a failure rolls back that step alone and the next launch resumes there. Keep guarding every `ALTER` (`PRAGMA table_info`) regardless — half-upgraded databases from older builds exist — and never put a statement in a step that cannot run inside a transaction (`VACUUM`, `PRAGMA journal_mode`). A data step that is its own inverse needs a marker, not just a version (v18 checks for the column v19 adds).
- **`test/database/upgrade_chain_test.dart` guards the whole chain**: oldest reconstructible shape → every step one at a time → column and index parity with a fresh install → a re-run → a real v30 file reopened through the production connection. Run it after any migration or index change. If a new column lands on one of the four original tables it needs nothing; the oldest shape is derived by dropping everything not in its frozen column lists.
- **Every index must be created on BOTH paths.** `DatabaseIndexes.createAllIndexes()` runs from `onCreate` (fresh installs); migrations run on upgraders. An index defined only inside a migration leaves every *fresh* install slower than an upgraded one — `idx_folders_position` / `idx_notes_position` were exactly that for years, so new users scanned-and-sorted the folder content page's primary query until **v25** repaired it. Define the index once as a public method on `DatabaseIndexes`, call it from `createAllIndexes()`, and have the migration call the same method. `test/database/schema_parity_test.dart` scrapes `lib/database/**` for `CREATE INDEX`/`CREATE TABLE` names and fails if a fresh database lacks any of them, so this cannot regress silently.

## Connection pragmas

`configureSqliteConnection` in `lib/database/database.dart` is the `setup:` callback for every connection: **WAL**, `synchronous = NORMAL`, `temp_store = MEMORY`, `cache_size = -4000`. Measured on a real file, 200 individually-committed inserts (the auto-save shape) went **561 ms → 28 ms**; the app previously ran on stock SQLite defaults with no `setup:` at all.

- It must stay a **top-level function** — `createInBackground` sends it to the database isolate, which a capturing closure cannot survive.
- `synchronous = NORMAL` is safe **only because of WAL**, which is the pairing SQLite documents. App crash loses nothing; a power cut can roll back recent transactions but cannot corrupt. Do not raise it back to `FULL` without measuring what it costs (~5× on small writes).
- WAL means `-wal` / `-shm` sidecars. `DatabaseManager.renameDatabase` / `deleteDatabase` already move and remove them; any new code that touches the database file directly must too. The size shown on `DatabaseSettingsPage` adds the `-wal` size for the same reason.
- `test/database/connection_pragmas_test.dart` asserts all four. Dropping the `setup:` callback would otherwise compile and pass everything else.

## Database tests

`NativeDatabase.memory()` works under `flutter test` with no extra setup, so the real schema, migrations and DAOs are all testable. `test/database/support/db_test_support.dart` provides `openTestDatabase()`, `queryPlan()`, `explainCaptured()` and a `StatementCounter` interceptor.

- **`EXPLAIN QUERY PLAN` guards** (`query_plan_test.dart`) — the deterministic half of performance testing. Assert `USING INDEX <name>` and the absence of `USE TEMP B-TREE FOR ORDER BY`. Matters here because several indexes are **partial** (`WHERE is_deleted = 0`) or **expression** (`COALESCE(parent_id, '')`, `LOWER(TRIM(name))`) indexes, which stop being usable if a query's expression drifts even slightly — with no visible symptom until a user has thousands of rows. Statements are captured from the DAO as it really ran, so the tests can't assert about SQL the app doesn't issue.
- **Statement-count guards** (`query_count_test.dart`) — catch query-in-a-loop. This is what found the reorder path issuing a `SELECT` **and** an `UPDATE` per row (100 statements for 50 notes) purely to read `version` so it could write `version + 1`; SQL does that arithmetic itself.
- **Volume benchmark** (`volume_benchmark_test.dart`) — tagged `benchmark`, skipped by default via `dart_test.yaml`. Run with `flutter test --tags benchmark --run-skipped`. **Do not add wall-clock assertions to the normal suite**: the numbers move with background load (a 5000-row sort measured *faster* than the same 500-row sort across runs), so any threshold loose enough to be stable catches nothing. Assert catastrophe-only ceilings and read the printed table for signal.

## Full change set for a new persisted field/table

1. Table definition in `lib/database/tables/` + migration step in the database class (bump `schemaVersion`).
2. DAO methods in `lib/database/daos/` (transactions, soft deletes where applicable).
3. Repository + service wiring; invalidate repository caches on mutation.
4. Model in `lib/models/` (`Equatable`, `copyWith` with `clearX` bools for nullable fields, JSON keys from `lib/constants/json_keys.dart`).
5. **Backup**: extend `BackupService` export/import so old backups still import (missing fields get defaults — precedent: holiday rows missing `profile` import as `'generic'`).
6. **Import/export archives** if the entity is shareable: paired `createX` / `importX` methods (never widen `createX` with timestamp params); bump `ImportExportService.archiveVersion` AND accept the previous version in `_assertSupportedManifest`.
7. build_runner + analyze.

## DatabaseLifecycle contract (multi-database safety)

The app switches between local databases (`DatabaseManager`). Every DB-backed singleton (`late AppDatabase _db` or cached DB-derived state) MUST follow `lib/database/database_lifecycle.dart`:

1. Expose `static void reset()` that nulls `_instance` and cancels timers/streams it owns.
2. Register `DatabaseLifecycle.registerResetHandler(reset)` inside the `getInstance()` first-time-init block, **after** `_instance` is fully constructed.
3. If the service publishes into a separate static cache (pattern: `PublicHolidayService` → `PublicHolidays._cache`), `reset()` must clear that cache too.

```dart
static Future<MyService> getInstance() async {
  if (_instance == null) {
    _instance = MyService._();
    _instance!._db = await AppDatabase.getInstance();
    await _instance!._load();
    DatabaseLifecycle.registerResetHandler(reset);
  }
  return _instance!;
}

static void reset() { _instance = null; }
```

Handlers fire once per `notifyDatabaseSwitching()` and the registry self-clears — re-registration happens naturally on the next `getInstance()`. Anti-patterns: a `late AppDatabase _db` singleton without reset+registration (latent crash after switch); static caches with no owning `reset()`; registering from a constructor that runs more than once.

Services already on the contract: `CounterService`, `CalendarEventService`, `CategoryService`, `PublicHolidayService`, `MarkdownBarService`, `SettingsService`, `DevOptionsService`, `BackupService`, `NotePositionService`. New singletons must join.

## Settings

New settings go through `UserSettingsDao` → `SettingsService` with a named key in `SettingsKeys` (+ default constant). Never scatter raw string keys or raw `SharedPreferences`.
