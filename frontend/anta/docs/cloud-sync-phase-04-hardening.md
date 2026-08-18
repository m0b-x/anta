# Cloud Sync Phase 04 — Hardening

**Status: planned.** No schema change. The phase where sync earns trust.

## Scenario matrix to survive

- Offline → reconnect with edits queued on both sides.
- Airplane-mode edits to the same event/note on both devices.
- Delete on one side, edit on the other (tombstone wins per HLC).
- Unpair → re-pair (fresh `pairId`, no data resurrection).
- Delete-then-reshare a folder.

Phase 01 already discharges the pairing half of two of these: unpair
tombstones the pair rather than deleting it, re-pairing always mints a fresh
`pairId`, and reconciliation on sign-in/resume converges a uid that ended up
in two active pairs. What is left for this phase is what happens to the
**data** across those transitions — that content under an ended pair stops
flowing, and that a re-pair does not resurrect it.

## Known integration hazards

- **Backup restore versus sync.** Restoring a backup over synced data
  re-pushes everything as "new". Suspend sync during restore, reconcile once
  afterwards. `BackupService` and the sync services need an explicit
  suspend/resume seam.
- **Database switching mid-sync.** Tear down snapshot listeners in the
  `DatabaseLifecycle.notifyDatabaseSwitching()` sweep; rebind on the next
  `getInstance()`. Pairing state is already per-database and already on the
  reset contract (Phase 01), and reconciliation re-runs after a switch; the
  *data* listeners must follow the same path.
- **Silent failure is the worst outcome for a trust feature.** A sync status
  indicator (last synced / pending / error) on the Sharing page, and real
  error surfacing through the existing snackbar pattern — never swallowed
  exceptions.

## Tests

- `test/database/`: schema parity for v26/v27 (create-vs-migrate), statement
  counts on the new sync-touched query paths.
- Merge-rules suite against the fake `SyncGateway`: HLC ordering, tombstone
  precedence, `receive()` clock advancement, whole-note granularity.
- Extend `test/bloc/sync_bloc_test.dart`'s fake-service pattern to the sync
  status states.

## Done when

You stop finding new ways to break it — the matrix above passes repeatedly,
and every failure the app can detect is visible to the user.
