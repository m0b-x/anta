import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../database/daos/sync_dao.dart';
import '../../database/database.dart';
import '../../database/database_lifecycle.dart';
import '../../models/app_user.dart';
import 'sync_binding_service.dart';
import 'sync_status.dart';

/// Reads [SyncStatus] from this database: the outbox, the binding, the
/// stored push time and the clock's own reports.
class SyncStatusService implements SyncStatusReader {
  static SyncStatusService? _instance;

  final AppDatabase _db;
  final SyncBindingService _binding;

  SyncStatusService._(this._db, this._binding);

  /// A service outside the singleton and the [DatabaseLifecycle] registry,
  /// so one test can hold one per in-memory database. Never for app code.
  @visibleForTesting
  SyncStatusService.detached(this._db, this._binding);

  /// The service over the active database, built once per database.
  ///
  /// Starts over once when a database switch lands between its awaits, for
  /// the reason [SyncBindingService.getInstance] does (A1c review R36): a
  /// reader registered over the closed database would answer every later
  /// caller with the previous database's queue, and its [reset] would sit in
  /// a registry the switch has already emptied.
  static Future<SyncStatusService> getInstance() => _build(mayRetry: true);

  static Future<SyncStatusService> _build({required bool mayRetry}) async {
    final existing = _instance;
    if (existing != null) return existing;
    final generation = DatabaseLifecycle.generation;
    final db = await AppDatabase.getInstance();
    final binding = await SyncBindingService.getInstance();
    final raced = _instance;
    if (raced != null) return raced;
    if (DatabaseLifecycle.generation != generation) {
      if (mayRetry) return _build(mayRetry: false);
      throw StateError('the database switched while the status was built');
    }
    return _register(SyncStatusService._(db, binding));
  }

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup. Exists so tests can
  /// exercise the real DAOs against `NativeDatabase.memory()`; never use it in
  /// app code — the singleton is what the [DatabaseLifecycle] reset contract
  /// is built on.
  @visibleForTesting
  static SyncStatusService forTesting(
    AppDatabase db,
    SyncBindingService binding,
  ) {
    return _instance ?? _register(SyncStatusService._(db, binding));
  }

  static SyncStatusService _register(SyncStatusService service) {
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the singleton, so a switched database never reports the previous
  /// one's queue. Invoked by [DatabaseLifecycle].
  static void reset() {
    _instance = null;
  }

  /// Only the pauses the stored state decides are set here; the engine's
  /// own — quota, access, an outdated app — come from its stream (D19).
  /// Signed out is not a mismatch: there is no account to sync as, and
  /// signing back in as the bound one resumes.
  @override
  Future<SyncStatus> read({AppUser? user}) async {
    final binding = await _binding.read();
    final uid = user?.uid;
    final ahead = _db.clockSeedAhead;
    return SyncStatus(
      pendingCount: await _db.syncOutboxDao.count(),
      lastPushAt: await _instantAt(SyncDao.keyLastPushAt),
      lastPullAt: await _instantAt(SyncDao.keyLastPullAt),
      pause: binding == null
          ? SyncPause.none
          : uid == null
          ? SyncPause.signedOut
          : uid != binding.accountUid
          ? SyncPause.accountMismatch
          : SyncPause.none,
      clockAhead: ahead > AppDatabase.clockMaxDrift ? ahead : Duration.zero,
      clampedRemotes: _db.clockClampedRemotes,
      binding: binding,
    );
  }

  /// A stored epoch-milliseconds instant, null until first written.
  Future<DateTime?> _instantAt(String key) async {
    final ms = int.tryParse(await _db.syncDao.getValue(key) ?? '');
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
}
