import 'package:drift/drift.dart' show UpdateKind, Variable;
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../../database/crdt/crdt_write.dart';
import '../../database/crdt/synced_tables.dart';
import '../../database/daos/sync_dao.dart';
import '../../database/database.dart';
import '../../database/database_lifecycle.dart';
import '../../models/sync_binding.dart';
import '../database_manager.dart';
import '../settings_service.dart';
import 'sync_gateway.dart';
import 'sync_space_registry.dart';
import 'sync_suspension.dart';

/// Why [SyncBindingService.bind] refused, for the caller to word (review
/// R39): the message stays the debug text.
enum SyncBindRefusalReason {
  /// A restore or import is rewriting this database.
  suspended,

  /// The database is bound already: stop syncing first.
  alreadyBound,

  /// Another database of this install holds the space —
  /// [SyncBindRefusal.holderDatabase] names it.
  spaceHeldByAnotherDatabase,
}

class SyncBindRefusal implements Exception {
  final SyncBindRefusalReason reason;
  final String message;

  /// For [SyncBindRefusalReason.spaceHeldByAnotherDatabase]: the database
  /// that holds the space, as the Databases page lists it.
  final String? holderDatabase;

  const SyncBindRefusal(this.reason, this.message, {this.holderDatabase});

  @override
  String toString() =>
      'SyncBindRefusal(${reason.name}'
      '${holderDatabase == null ? '' : ': $holderDatabase'}): $message';
}

/// Which space this database syncs with, and the floor its initial merge
/// settles against (D15): the one place a database is bound or unbound.
class SyncBindingService {
  static SyncBindingService? _instance;

  final AppDatabase _db;
  final SettingsService _settings;

  /// The install-wide registry this database's claim is kept in, under
  /// [_databaseName]; null on a test's detached service that has none.
  final SyncSpaceRegistry? _registry;

  /// Asked at each registry write rather than kept from the build: Android
  /// can rename the open file, and the claim must land under the name it has
  /// now (review BA-M6). Null once this service no longer speaks for the
  /// active database, so a stale one writes no claim.
  final String? Function() _databaseName;

  SyncBindingService._(
    this._db,
    this._settings, {
    SyncSpaceRegistry? registry,
    required String? Function() databaseName,
  }) : _registry = registry,
       _databaseName = databaseName;

  /// A service outside the singleton and the [DatabaseLifecycle] registry,
  /// so one test can hold one per in-memory database — the two devices of a
  /// sync test. Never for app code. [settings] must read and write [_db]: the
  /// binding keys live in the settings table, so a service paired with
  /// another database's settings would bind that database instead of this
  /// one. `SettingsService` exposes no handle to compare, so this holds by
  /// construction only. With [registry], binds claim and unbinds release
  /// [databaseName] there, as the app's service does.
  @visibleForTesting
  SyncBindingService.detached(
    this._db,
    this._settings, {
    SyncSpaceRegistry? registry,
    String? databaseName,
  }) : _registry = registry,
       _databaseName = (() => databaseName);

  /// The service over the active database, built once per database.
  ///
  /// A database switch landing between its awaits makes it start over once,
  /// as `SyncEngine._build` does (S4b-1 review L10, A1c review R36): the
  /// database it awaited first is the one being closed, and registering a
  /// service over it would both hand every later caller — the engine built
  /// for the *new* database included — a service bound to the closed one and
  /// put [reset] in the registry the switch has already emptied. A second
  /// switch inside the retry throws rather than register anything.
  ///
  /// Each build squares the binding with the install registry first
  /// ([_healClaim]).
  static Future<SyncBindingService> getInstance() => _build(mayRetry: true);

  static Future<SyncBindingService> _build({required bool mayRetry}) async {
    final existing = _instance;
    if (existing != null) return existing;
    final generation = DatabaseLifecycle.generation;
    final db = await AppDatabase.getInstance();
    final settings = await SettingsService.getInstance();
    final databases = await DatabaseManager.getInstance();
    // The active name is the open database's: `getInstance` above has just
    // switched to it, a rename keeps it, and a switch since ends the
    // generation this service speaks for.
    final service = SyncBindingService._(
      db,
      settings,
      registry: databases.spaceRegistry,
      databaseName: () => DatabaseLifecycle.generation == generation
          ? databases.getActiveDatabaseName()
          : null,
    );
    await service._healClaim();
    final raced = _instance;
    if (raced != null) return raced;
    if (DatabaseLifecycle.generation != generation) {
      if (mayRetry) return _build(mayRetry: false);
      throw StateError('the database switched while the binding was built');
    }
    return _register(service);
  }

  /// A bound database whose claim is missing (review BA-H1): a kill between
  /// the bind's commit and its claim, a registry write that failed, a bound
  /// database moved in from another install — or a raw copy of a bound
  /// database (the Databases page's import, onboarding's restore from file),
  /// which carries the binding and the same `device_id` into the same space.
  /// When no other database of this install holds the space, this one claims
  /// it and keeps syncing; when another one does, this one is the copy and is
  /// unbound, as Stop syncing would. Skipped while [SyncSuspension] holds: a
  /// restore unbinds on its own. Logged, never thrown — the binding must
  /// still be readable.
  Future<void> _healClaim() async {
    if (SyncSuspension.isSuspended) return;
    final registry = _registry;
    final name = _databaseName();
    if (registry == null || name == null) return;
    try {
      final binding = await read();
      if (binding == null) return;
      final space = SyncSpaceRef(
        ownerUid: binding.ownerUid,
        spaceId: binding.spaceId,
      );
      final holder = await registry.holderOf(space, except: name);
      if (holder == null) {
        final claim = SyncSpaceClaim(space: space, databaseName: name);
        if (!registry.claims().contains(claim)) {
          await registry.claim(space, name);
        }
        return;
      }
      debugPrint(
        '[SyncBindingService] "$name" is bound to the space "$holder" '
        'holds — a copy of it: unbound',
      );
      await unbind();
    } catch (e, st) {
      debugPrint('[SyncBindingService] claim not healed: $e\n$st');
    }
  }

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup. Exists so tests can
  /// exercise the real DAOs against `NativeDatabase.memory()`; never use it in
  /// app code — the singleton is what the [DatabaseLifecycle] reset contract
  /// is built on.
  @visibleForTesting
  static SyncBindingService forTesting(
    AppDatabase db,
    SettingsService settings, {
    SyncSpaceRegistry? registry,
    String? databaseName,
  }) {
    return _instance ??
        _register(
          SyncBindingService._(
            db,
            settings,
            registry: registry,
            databaseName: () => databaseName,
          ),
        );
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
  /// (S3a review F1). Refused while another database of this install holds
  /// [space] (review BA-L4). Every refusal throws [SyncBindRefusal].
  ///
  /// Once committed, this database claims [space] in the install registry.
  /// `SyncSpaceService` checks the holder before it creates anything; the
  /// check here keeps any other caller from binding a held space.
  Future<void> bind({
    required SyncSpaceRef space,
    required String accountUid,
  }) async {
    await _db.transaction(() async {
      // The refusals inside the transaction, before the first write: two
      // binds started together would otherwise both pass a check made
      // outside it and both run, the second overwriting the first binding
      // and re-queueing every row again (A1c review R38).
      if (SyncSuspension.isSuspended) {
        throw const SyncBindRefusal(
          SyncBindRefusalReason.suspended,
          'Cannot bind while sync is suspended: a restore or import is '
          'rewriting this database.',
        );
      }
      if (await read() != null) {
        throw const SyncBindRefusal(
          SyncBindRefusalReason.alreadyBound,
          'Cannot bind while this database is bound: stop syncing first.',
        );
      }
      final holder = await _holderOf(space);
      if (holder != null) {
        throw SyncBindRefusal(
          SyncBindRefusalReason.spaceHeldByAnotherDatabase,
          'Cannot bind while another database of this install holds the '
          'space: stop syncing it first.',
          holderDatabase: holder,
        );
      }
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
    await _updateRegistry((registry, name) => registry.claim(space, name));
  }

  /// Leaves the space: the binding is cleared, the unsent queue dropped — it
  /// described changes for a space this database no longer syncs with — the
  /// pull state deleted, so a rebind pulls from the beginning, and the floor
  /// written, so a later bind lets the space win every row this database
  /// held at this moment. One transaction, so no half-unbound state survives
  /// a crash.
  ///
  /// Once committed, this database's claim in the install registry is
  /// released — here rather than in the callers, so "Stop syncing" and the
  /// restore's unbind (`BackupService.importFromJson`) both release it.
  Future<void> unbind() async {
    await _db.transaction(() async {
      await _settings.setSyncBinding(null);
      await _db.syncOutboxDao.clear();
      await _deletePullState();
      await writeBindFloor();
    });
    await _updateRegistry((registry, name) => registry.release(name));
  }

  /// After the transaction has committed, never inside it: the registry is
  /// `SharedPreferences`, which a rollback cannot undo. A failure is logged,
  /// not thrown — the binding has already changed, and a restore must go on
  /// to clear its queue and write its floor.
  Future<void> _updateRegistry(
    Future<void> Function(SyncSpaceRegistry registry, String databaseName)
    update,
  ) async {
    final registry = _registry;
    final name = _databaseName();
    if (registry == null || name == null) return;
    try {
      await update(registry, name);
    } catch (e, st) {
      debugPrint('[SyncBindingService] registry update failed: $e\n$st');
    }
  }

  /// The other database of this install holding [space]; this database's own
  /// claim is never in its way. Null without a registry.
  Future<String?> _holderOf(SyncSpaceRef space) async {
    final registry = _registry;
    if (registry == null) return null;
    return registry.holderOf(space, except: _databaseName());
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
