# Cloud Sync Phase 03 — Shared Folders

**Status: planned.** Migration **v27**. Depends on Phase 02's gateway and
merge machinery. Symbol names are targets — re-verify at implementation time.

## Goal

A folder marked shared appears on both devices with its whole subtree; notes
edited on either side converge; search finds pulled content; everything else
stays local.

## Migration v27 (`folders`)

- `is_shared` INTEGER DEFAULT 0 — sharing a folder shares its subtree; no
  per-note column.
- `owner_id` TEXT NULL — who shared it, for the same banner treatment as
  events.

Schema-parity tests extend to v27.

## Sync machinery

- `NoteSyncService` pushes folder → note → chunks, reusing Phase 02's
  `SyncGateway`.
- **Chunks are keyed remotely on `(noteId, chunkIndex)`, never the local
  chunk id** — two devices generate different UUIDs for the same index.
- **Conflict granularity is the whole note, not the chunk.** Interleaving
  chunks from two devices produces text that belongs to neither; the note's
  HLC decides, whole-body.
- **Throttle the push — this is the #1 risk in the register.**
  `AutoSaveService` writes constantly; debounce pushes to a few seconds and
  flush on editor blur and on the lifecycle pause that already calls
  `CounterService.flush()` in `main.dart`.
- Pull side must re-run FTS indexing for changed notes, update
  `FolderSearchService`'s app-level index (one shared normalization — see
  COPILOT_CONTEXT "Data And Persistence Rules"), and invalidate both
  `NoteRepository` and `FolderRepository` caches.

## UI

- Folder context menu gains Share/Unshare; shared folders get a badge.
- Owner banner on notes inside a partner-shared folder.
- Strings en/de/ro.

## Import/export

Archives strip `isShared` on import so an imported folder always lands
local — bump `ImportExportService.archiveVersion` only if the manifest
schema actually changes.

## Done when

Marking a folder shared syncs its subtree both ways; a mid-workout edit on
one phone lands on the other without blowing the write quota (verify with
Firestore usage console after a heavy editing session); search on the
receiving device finds pulled notes; unshared content never leaves the
device.
