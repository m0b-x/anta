import 'package:drift/drift.dart' show UpdateKind, Variable;
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../database/crdt/crdt_write.dart';
import '../../database/crdt/synced_tables.dart';
import '../../database/daos/sync_dao.dart';
import '../../database/database.dart';
import '../../database/database_lifecycle.dart';
import '../../models/sync_binding.dart';
import '../settings_service.dart';
import 'sync_gateway.dart';
import 'sync_suspension.dart';

/// Which space this database syncs with, and the floor its initial merge
/// settles against (D15): the one place a database is bound or unbound.
class SyncBindingService {
  static SyncBindingService? _instance;

  final AppDatabase _db;
  final SettingsService _settings;

  SyncBindingService._(this._db, this._settings);

  /// A service outside the singleton and the [DatabaseLifecycle] registry,
  /// so one test can hold one per in-memory database — the two devices of a
  /// sync test. Never for app code. [settings] must read and write [_db]: the
  /// binding keys live in the settings table, so a service paired with
  /// another database's settings would bind that database instead of this
  /// one. `SettingsService` exposes no handle to compare, so this holds by
  /// construction only.
  @visibleForTesting
  SyncBindingService.detached(this._db, this._settings);

  static Future<SyncBindingService> getInstance() async {
    final existing = _instance;
    if (existing != null) return existing;
    final db = await AppDatabase.getInstance();
    final settings = await SettingsService.getInstance();
    return _instance ?? _register(SyncBindingService._(db, settings));
  }

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup. Exists so tests can
  /// exercise the real DAOs against `NativeDatabase.memory()`; never use it in
  /// app code — the singleton is what the [DatabaseLifecycle] reset contract
  /// is built on.
  @visibleForTesting
  static SyncBindingService forTesting(
    AppDatabase db,
    SettingsService settings,
  ) {
    return _instance ?? _register(SyncBindingService._(db, settings));
  }

  static SyncBindingService _register(SyncBindingService service) {
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the singleton, so a switched database never answers with the
  /// previous one's binding. Invoked by [DatabaseLifecycle].
  static void reset() {
    _instance = null;
  }

  Future<SyncBinding?> read() => _settings.getSyncBinding();

  Future<String?> bindFloor() => _db.syncDao.getValue(SyncDao.keyBindFloor);

  /// Stores the clock as `bind_floor`, after storing it as `last_hlc`: every
  /// stamp this device has minted is at or below it and every later one is
  /// above it, so an edit made after the unbind wins at the next bind.
  ///
  /// The clock, never the highest row stamp: a merge stores a remote stamp
  /// verbatim while the clock holds back one too far ahead, so a row can
  /// carry a stamp above the clock. A floor that high would let the space win
  /// every edit made after the unbind; the held row instead meets its remote
  /// twin as an equal. Overwrites, unlike the clock: a later unbind sets the
  /// floor of the next bind.
  Future<void> writeBindFloor() async {
    await _db.persistClock();
    final clock = await _db.syncDao.getValue(SyncDao.keyLastHlc);
    if (clock == null || clock.isEmpty) return;
    await _db.syncDao.setValue(SyncDao.keyBindFloor, clock);
  }

  /// Attaches this database to [space] for [accountUid], in one transaction
  /// so a failure anywhere leaves it unbound (record §3.6):
  ///
  /// - the binding stored;
  /// - every unowned row of the seventeen queued tables owned by
  ///   [accountUid], the owner the rules require (readiness D17) —
  ///   `content_chunks` travel inside their note and stay unowned;
  /// - every row re-queued at its own stamp, so each one is either uploaded
  ///   or settled against the space by the initial merge;
  /// - the pull cursors and `pull_seen` marks deleted, so the first pull
  ///   reads the whole space;
  /// - `bind_merge_pending` set, the floor rule's switch;
  /// - the floor written only when none exists: a never-bound database floors
  ///   now, a restored or unbound one keeps the floor written then, below
  ///   which its rows are older than the space's (D15).
  ///
  /// Refused while [SyncSuspension] holds: a restore is rewriting the rows
  /// this would queue. Refused while a binding exists: a direct rebind would
  /// leave the first account's rows owned by it, unqueued and foreign to the
  /// new space (readiness D17) — [unbind] floors and clears the queue first
  /// (S3a review F1).
  Future<void> bind({
    required SyncSpaceRef space,
    required String accountUid,
  }) async {
    if (SyncSuspension.isSuspended) {
      throw StateError(
        'Cannot bind while sync is suspended: a restore or import is '
        'rewriting this database.',
      );
    }
    if (await read() != null) {
      throw StateError(
        'Cannot bind while this database is bound: stop syncing first.',
      );
    }
    await _db.transaction(() async {
      await _settings.setSyncBinding(
        SyncBinding(
          spaceId: space.spaceId,
          ownerUid: space.ownerUid,
          accountUid: accountUid,
          boundAt: DateTime.now().toUtc(),
        ),
      );
      for (final synced in syncedTables) {
        if (synced.travelsWithParent) continue;
        await _db.customUpdate(
          'UPDATE ${synced.name} SET owner_id = ? WHERE owner_id IS NULL',
          variables: [Variable<String>(accountUid)],
          updates: {
            _db.allTables.firstWhere((t) => t.actualTableName == synced.name),
          },
          updateKind: UpdateKind.update,
        );
      }
      await _db.syncOutboxDao.requeueAll(boundUid: accountUid);
      await _deletePullState();
      await _db.syncDao.setValue(SyncDao.keyBindMergePending, '1');
      if (await bindFloor() == null) await writeBindFloor();
    });
  }

  /// Leaves the space: the binding is cleared, the unsent queue dropped — it
  /// described changes for a space this database no longer syncs with — the
  /// pull state deleted, so a rebind pulls from the beginning, and the floor
  /// written, so a later bind lets the space win every row this database
  /// held at this moment. One transaction, so no half-unbound state survives
  /// a crash.
  Future<void> unbind() {
    return _db.transaction(() async {
      await _settings.setSyncBinding(null);
      await _db.syncOutboxDao.clear();
      await _deletePullState();
      await writeBindFloor();
    });
  }

  /// The cursors, the `pull_seen` marks, the initial-merge switch, and the
  /// quota pause and last-run times — they describe the previous space (F7).
  Future<void> _deletePullState() async {
    await _db.syncDao.deleteByPrefix(SyncDao.pullCursorPrefix);
    await _db.syncDao.deleteByPrefix(SyncDao.pullSeenPrefix);
    await _db.syncDao.deleteValue(SyncDao.keyBindMergePending);
    await _db.syncDao.deleteValue(SyncDao.keyQuotaPausedAt);
    await _db.syncDao.deleteValue(SyncDao.keyLastPullAt);
    await _db.syncDao.deleteValue(SyncDao.keyLastPushAt);
  }
}
