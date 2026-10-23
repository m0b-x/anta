import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../database/crdt/crdt_write.dart';
import '../../database/daos/sync_dao.dart';
import '../../database/database.dart';
import '../../database/database_lifecycle.dart';
import '../../models/sync_binding.dart';
import '../settings_service.dart';

/// Which space this database syncs with, and the floor its initial merge
/// settles against (D15). There is no `bind` yet: binding is Phase 02's flow;
/// this phase can only read a binding and undo one.
class SyncBindingService {
  static SyncBindingService? _instance;

  final AppDatabase _db;
  final SettingsService _settings;

  SyncBindingService._(this._db, this._settings);

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

  /// Leaves the space: the binding is cleared, the unsent queue dropped — it
  /// described changes for a space this database no longer syncs with — and
  /// the floor written, so a later bind lets the space win every row this
  /// database held at this moment. One transaction, so no half-unbound state
  /// survives a crash.
  Future<void> unbind() {
    return _db.transaction(() async {
      await _settings.setSyncBinding(null);
      await _db.syncOutboxDao.clear();
      await writeBindFloor();
    });
  }
}
