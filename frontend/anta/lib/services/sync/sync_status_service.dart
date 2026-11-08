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
      pause: SyncPause.forAccount(binding, uid),
      clockAhead: ahead > AppDatabase.clockMaxDrift ? ahead : Duration.zero,
      clampedRemotes: _db.clockClampedRemotes,
      binding: binding,
      unboundAsCopyOf: await _db.syncDao.getValue(SyncDao.keyHealUnboundFrom),
      quotaPausedAt: await _instantAt(SyncDao.keyQuotaPausedAt),
    );
  }

  /// The rows [parks] hold back, as the Sync page lists them (scalability
  /// record S7, the D14 promise): one item per row, under the strongest of
  /// its parks' reasons ([SyncHeldReason]'s order) — a row parked by its
  /// pull and its push is one row, and a chunk's park is its notes', every
  /// note holding that text, since the chunk is part of each body. Notes are
  /// named by their titles and folders by their names, tombstones included,
  /// and a row this device holds no copy of goes unnamed; notes come first
  /// by name, then folders by name, then the other kinds in [SyncHeldKind]'s
  /// order, oldest park first. The name sort is `toLowerCase().compareTo`,
  /// so a name opening on "ș" or "ä" sorts after "z".
  Future<List<SyncHeldItem>> heldBack(List<SyncParkedRow> parks) async {
    if (parks.isEmpty) return const [];
    final rows = <(String, String), ({SyncHeldReason reason, String stamp})>{};
    void hold(String table, String rowKey, SyncParkedRow park) {
      final kept = rows[(table, rowKey)];
      rows[(table, rowKey)] = kept == null
          ? (reason: park.reason, stamp: park.stamp)
          : (
              reason: park.reason.index < kept.reason.index
                  ? park.reason
                  : kept.reason,
              stamp: park.stamp.compareTo(kept.stamp) < 0
                  ? park.stamp
                  : kept.stamp,
            );
    }

    final holders = await _db.contentChunkDao.noteIdsByHash([
      for (final park in parks)
        if (park.table == _chunksTable) park.rowKey,
    ]);
    for (final park in parks) {
      if (park.table != _chunksTable) {
        hold(park.table, park.rowKey, park);
        continue;
      }
      // A chunk no live note holds any more is left out: its entry is
      // retired at the next push, and its park dropped at the next start.
      for (final noteId in holders[park.rowKey] ?? const <String>{}) {
        hold(_notesTable, noteId, park);
      }
    }

    final keysByTable = <String, List<String>>{};
    for (final (table, rowKey) in rows.keys) {
      keysByTable.putIfAbsent(table, () => []).add(rowKey);
    }
    final names = <(String, String), String>{};
    final deleted = <(String, String)>{};
    for (final MapEntry(key: table, value: keys) in keysByTable.entries) {
      switch (table) {
        case _notesTable:
          for (final note in await _db.noteDao.getByIdsIncludingDeleted(keys)) {
            names[(table, note.id)] = note.title.trim();
            if (note.isDeleted) deleted.add((table, note.id));
          }
        case _foldersTable:
          for (final folder in await _db.folderDao.getByIdsIncludingDeleted(
            keys,
          )) {
            names[(table, folder.id)] = folder.name.trim();
            if (folder.isDeleted) deleted.add((table, folder.id));
          }
        default:
          for (final key in await _db.syncOutboxDao.tombstonedKeys(
            table,
            keys,
          )) {
            deleted.add((table, key));
          }
      }
    }

    final items = [
      for (final MapEntry(key: (table, rowKey), :value) in rows.entries)
        (
          item: SyncHeldItem(
            table: table,
            rowKey: rowKey,
            kind: SyncHeldKind.ofTable(table),
            name: names[(table, rowKey)],
            deleted: deleted.contains((table, rowKey)),
            reason: value.reason,
          ),
          stamp: value.stamp,
        ),
    ];
    items.sort((x, y) {
      final kind = x.item.kind.index.compareTo(y.item.kind.index);
      if (kind != 0) return kind;
      if (x.item.kind == SyncHeldKind.note ||
          x.item.kind == SyncHeldKind.folder) {
        final name = (x.item.name ?? '').toLowerCase().compareTo(
          (y.item.name ?? '').toLowerCase(),
        );
        if (name != 0) return name;
      }
      return x.stamp.compareTo(y.stamp);
    });
    return [for (final entry in items) entry.item];
  }

  static const String _notesTable = 'notes';
  static const String _foldersTable = 'folders';
  static const String _chunksTable = 'content_chunks';

  /// A stored epoch-milliseconds instant, null until first written.
  Future<DateTime?> _instantAt(String key) async {
    final ms = int.tryParse(await _db.syncDao.getValue(key) ?? '');
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
}
