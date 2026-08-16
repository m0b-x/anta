# Cloud Sync Phase 02 — Calendar Sync, Ownership, Consent

**Status: planned.** Migration **v27** (renumbered 2026-08-16: v26 went to
presence tracking — `docs/presence-tracking-roadmap.md` — whose
`calendar_event_absences` table ships CRDT-shaped from birth). Depends on
Phase 01. Symbol names below are targets from the migration plan — re-verify
each against the code when this phase starts.

## Goal

Both partners' calendars merge on both phones; deletes propagate as
tombstones; a partner's edits to your events obey your standing consent
toggle.

## Migration v27 (`calendar_events` + `calendar_event_absences`)

Add, guarded with `PRAGMA table_info` per the v13–v15 precedent:

| Column | Why |
| --- | --- |
| `owner_id` TEXT NULL | Whose event it is. NULL until first sign-in backfills the local uid — the migration cannot know it. |
| `hlc_timestamp`, `device_id`, `version` | Merge ordering, matching the notes/folders convention exactly. |
| `is_deleted`, `deleted_at` | Tombstones. Without them a delete never propagates — the other device pushes the row back forever. |

`calendar_event_absences` (v26) already carries `hlc_timestamp`,
`device_id`, `version`, `is_deleted`, `deleted_at` with live tombstone
semantics — here it needs only `owner_id`, added alongside the events
column.

Run `dart run build_runner build --delete-conflicting-outputs`; extend
`test/database/` schema-parity for v27 (create-vs-migrate).

## Tombstone conversion — three hard-write paths

`calendar_events` has no soft delete today. Convert to HLC-stamped
tombstones: `CalendarEventDao.deleteById`, `deleteAll`, and
`CategoryService`'s category-reassign path; add `is_deleted = 0` filtering to
`CalendarEventDao.getAll()`. Any missed path re-materialises deleted events
on the partner's device.

## Sync machinery

- **`SyncGateway` interface + `FirestoreSyncGateway`** — Firestore never
  leaks into the service layer; a fake gateway makes merge rules unit-testable.
- **`CalendarSyncService`**: push after the DAO upsert; pull through a
  snapshot listener; merge = HLC string comparison (the zero-padded hex
  encoding makes lexicographic order agree with `compareTo`).
- **Call `HybridLogicalClock.receive()` on every pulled row** — a device with
  a lagging wall clock otherwise loses every conflict.
- **Pull must invalidate both caches**: reload the `CalendarEventService`
  in-memory cache *and* trigger `CalendarBloc`'s day-cache invalidation
  (`_invalidateDayCache`), or the UI keeps serving stale expansions.
- Document shape mirrors `CalendarEventService.exportData()` plus the sync
  columns; dates stay epoch-ms ints (see roadmap: the `_dateOnlyUtc` lesson).

## Ownership and consent

- Backfill `owner_id` = local uid on first sign-in after migration.
- Standing per-owner `allowPartnerEdit` flag on `pairs/{pairId}.permissions`,
  enforced in security rules (write allowed when `ownerId == uid()` or the
  owner consented), surfaced as a toggle on the Sharing page.
- Owner colour on day-panel and agenda rows; an "editing X's event" banner in
  `event_editor_sheet.dart`.

## Ripples

- `BackupService`: include the new columns; absent keys take column defaults
  (v19 precedent) so old backups import unchanged.
- **`docs/calendar-events-feature.md` lines ~28–38 still promise "no
  meetings, no invites, no sync" and "no account, no cloud"** (verified
  2026-08-16) — rewrite that framing in this phase.
- Per-occurrence descriptions (`calendar_event_occurrences`) stay
  device-local; only the template description syncs.
- `calendar_event_absences` (presence marks) is the deliberate opposite: it
  **does** sync. Wire `keyLastEventAbsenceHlc = 'last_event_absence_hlc'` on
  `SyncDao`, plus `getAbsencesSince`/`mergeAbsence` in the
  `NoteDao.getNotesSince`/`mergeNote` shape. A pulled absence republishes
  the `EventPresence` facade and bumps `occurrenceRevision` — never the
  day cache (presence is render-only).
- All new strings en/de/ro; `flutter gen-l10n`.

## Done when

Create/edit/delete on either phone converges on both within seconds online
and after reconnect; tombstoned events never resurrect; the consent toggle
blocks partner edits at the rules layer, not just the UI.
