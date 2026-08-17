# Cloud Sync Phase 02 — Calendar Sync, Ownership, Consent

**Status: planned.** Migration **v29** (renumbered three times, 2026-08-16:
v26 went to presence tracking — `docs/presence-tracking-roadmap.md`; v27 to
calendar cloud readiness — `docs/calendar-cloud-readiness-roadmap.md` —
which gave `calendar_events` its five CRDT columns, stamped writes and
tombstoned single-deletes; v28 to description scope —
`docs/description-scope-roadmap.md` — which made per-occurrence
descriptions a per-event flag and gave `calendar_event_occurrences` the
same CRDT treatment). Depends on Phase 01. Symbol names below are targets
from the migration plan — re-verify each against the code when this phase
starts.

## Goal

Both partners' calendars merge on both phones; deletes propagate as
tombstones; a partner's edits to your events obey your standing consent
toggle.

## Migration v29 (`owner_id` only)

Add, guarded with `PRAGMA table_info` per the v13–v15 precedent:

| Column | Why |
| --- | --- |
| `owner_id` TEXT NULL on `calendar_events`, `calendar_event_absences` **and** `calendar_event_occurrences` | Whose row it is. NULL until first sign-in backfills the local uid — the migration cannot know it. |

Everything else already shipped: `calendar_event_absences` has carried the
five CRDT columns since v26, `calendar_events` since v27 (`DEFAULT ''`
identity with a real backfill, stamped writes, tombstoned single-deletes,
`is_deleted = 0` filtering behind a partial index), and
`calendar_event_occurrences` since v28 (same shape; "reset this day" is a
tombstone, the event-delete cascade tombstones all three tables together).

Run `dart run build_runner build --delete-conflicting-outputs`; extend
`test/database/` schema-parity for v29 (create-vs-migrate).

## Tombstone conversion — done in v27, one decision left

Shipped by `docs/calendar-cloud-readiness-roadmap.md`: single-event delete
is `softDeleteById` (HLC-stamped tombstone, absences bulk-tombstoned in the
same transaction), `reassignCategory` stamps (shared HLC, `version + 1`,
skips tombstones), `getAll()` filters `is_deleted = 0`, and `upsert` writes
`is_deleted = false` on its update branch so a pushed remote row can never
land invisible on a local tombstone.

What this phase still owes: **`deleteAll`** (the "Delete all events" wipe)
is still hard — with transport live, a hard local wipe resurrects from the
partner device, so this phase must either tombstone it or scope the wipe to
local-only with explicit UX. `importData`'s wipe stays hard **forever** (a
tombstoning wipe + id-reusing restore is the documented resurrection trap).

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
- Per-occurrence descriptions sync too (decision reversed in v28: per-day
  text is user data on par with absence marks, and the per-event
  `per_occurrence_descriptions` flag travels with the event document).
  Wire `keyLastEventOccurrenceHlc = 'last_event_occurrence_hlc'` on
  `SyncDao`, plus `getOccurrencesSince`/`mergeOccurrence` in the
  `NoteDao.getNotesSince`/`mergeNote` shape. A pulled occurrence
  republishes the `OccurrenceDescriptions` facade and bumps
  `occurrenceRevision` — never the day cache.
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
