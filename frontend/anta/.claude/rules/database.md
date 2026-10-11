---
paths:
  - "lib/database/**"
  - "lib/repositories/**"
  - "lib/services/database_manager.dart"
  - "lib/services/backup_service.dart"
  - "lib/services/import_export_service.dart"
---
# Persistence — loads when the database, a repository, backup or import/export is touched

- A schema change is a migration appended to the upgrade chain, then `dart run build_runner build --delete-conflicting-outputs`. Never reset user storage, never renumber an existing step.
- Keep the data semantics: soft deletes (`isDeleted`), the CRDT fields (`hlcTimestamp`, `deviceId`, `version`), positions and sort preferences, pinned counters; global counter values use `noteId == ''`.
- A DB-backed singleton follows the `DatabaseLifecycle` reset contract — multi-database switching must leave no stale state.
- Backups and archives stay importable: a new persisted field defaults when absent; bumping `ImportExportService.archiveVersion` means accepting the previous version too. `createX` stamps timestamps to now, `importX` preserves the caller's.
- `test/database/` pins query plans, statement counts, create-vs-migrate parity and the whole upgrade chain — run it after any DAO or migration change (`flutter test test/database`).
- Load the `drift-migrations` skill for the full change set, the connection pragmas and the lifecycle contract.
