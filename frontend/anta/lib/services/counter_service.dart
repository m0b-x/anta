import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:uuid/uuid.dart';

import '../constants/json_keys.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../database/daos/counter_dao.dart';
import '../models/counter.dart';

export '../database/database.dart' show CounterValueRow;

/// Manages counter definitions and their values.
///
/// In-memory caches mirror the DB so reads are synchronous and cheap.
/// Writes are debounced (300 ms) so rapid tapping coalesces into a single DB
/// write while the in-memory state updates immediately.
class CounterService {
  static CounterService? _instance;
  late AppDatabase _db;
  late CounterDao _dao;

  // ---------------------------------------------------------------------------
  // In-memory caches
  // ---------------------------------------------------------------------------

  /// Ordered list of counter definitions.
  List<Counter> _counters = [];

  /// O(1) lookup by counter id.
  Map<String, Counter> _counterIndex = {};

  /// Global values for all counters. Key = counterId.
  Map<String, int> _globalValues = {};

  /// Per-note values cache. Key = noteId, value = { counterId: value }.
  /// Populated lazily on first access per note; avoids repeated DB reads.
  final Map<String, Map<String, int>> _noteValuesCache = {};

  // ---------------------------------------------------------------------------
  // Debounce infrastructure
  // ---------------------------------------------------------------------------

  /// The global values changed since their last flush, by counter id.
  final Map<String, _PendingCount> _dirtyGlobalValues = {};

  /// The per-note values changed since their last flush, by
  /// `(counterId, noteId)`. Pairs, not whole notes: a note's other counters
  /// did not change, and writing them would stamp every one as a change once
  /// devices merge.
  final Map<(String, String), _PendingCount> _dirtyNoteValues = {};

  Timer? _flushTimer;
  static const _flushDelay = Duration(milliseconds: 300);

  /// The tail of the flush / reload queue: a reload that read the table
  /// before a flush wrote it would otherwise put the older value back in
  /// memory after the flush updated it.
  Future<void> _serial = Future.value();

  /// Shared by every instance, as `VocabularyService._changes` is, so a
  /// subscription outlives the singleton a database switch replaces (A1b
  /// review R22).
  static final StreamController<void> _changes =
      StreamController<void>.broadcast();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  CounterService._();

  static Future<CounterService> getInstance() async {
    if (_instance == null) {
      _instance = CounterService._();
      _instance!._db = await AppDatabase.getInstance();
      _instance!._dao = _instance!._db.counterDao;
      await _instance!._load();
      DatabaseLifecycle.registerResetHandler(reset);
      // A page still showing the values of the database before a switch hears
      // that another instance answers now.
      _changes.add(null);
    }
    return _instance!;
  }

  /// The loaded singleton, or null before the first [getInstance] and after a
  /// [reset] — so a listener that outlives a database switch can re-resolve
  /// the instance that took its place without forcing one into existence
  /// (A1b review R22).
  static CounterService? get instanceOrNull => _instance;

  /// A service over [db] for tests, the `CategoryService.forTesting` seam: the
  /// real flush and DAO against an in-memory database. Not the singleton and
  /// never registered with `DatabaseLifecycle`.
  ///
  /// [changes] is static, so one of these and the singleton — or two of these
  /// — emit into the same stream: a test that builds both calls [reset] in
  /// its tear-down, or a bloc over one hears the other's reload.
  @visibleForTesting
  static Future<CounterService> forTesting(AppDatabase db) async {
    final service = CounterService._();
    service._db = db;
    service._dao = db.counterDao;
    await service._load();
    return service;
  }

  static void reset() {
    _instance?._flushTimer?.cancel();
    _instance = null;
  }

  List<Counter> get counters => List.unmodifiable(_counters);

  /// Fires after the cache was re-read wholesale — [reload] after a sync
  /// pull, [importData] after a restore — so a counter bloc already showing
  /// values rebuilds them; the service's own writes do not fire it, their
  /// callers already hold the new value.
  Stream<void> get changes => _changes.stream;

  /// Re-reads both tables after rows arrived beneath the service — a sync
  /// page. The taps not flushed yet are applied again over the values read,
  /// as deltas, and stay pending: flushing them as the absolute number shown
  /// before the page would stamp that stale number over the merged one on
  /// every device (record §3.5, S3c review H1).
  Future<void> reload() async {
    await _serialized(_reloadLocked);
    _changes.add(null);
  }

  /// [reload]'s body, already inside the [_serialized] queue — the flush's
  /// own recovery path calls it from within its turn, where re-entering the
  /// queue would wait on itself.
  Future<void> _reloadLocked() async {
    await _load();
    _dirtyNoteValues.removeWhere(
      (pair, _) => !_counterIndex.containsKey(pair.$1),
    );
    for (final MapEntry(key: id, value: pending)
        in _dirtyGlobalValues.entries.toList()) {
      final counter = _counterIndex[id];
      if (counter == null) {
        _dirtyGlobalValues.remove(id);
        continue;
      }
      _globalValues[id] = pending.over(_globalValues[id] ?? counter.startValue);
    }
  }

  Future<void> _serialized(Future<void> Function() body) {
    final run = _serial.then((_) => body());
    _serial = run.catchError((Object _) {});
    return run;
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    final results = await Future.wait([
      _dao.getAllCounters(),
      _dao.getValuesForNote(''),
    ]);
    _counters = (results[0] as List<CounterRow>).map(_rowToCounter).toList();
    _rebuildIndex();
    _globalValues = results[1] as Map<String, int>;
    _noteValuesCache.clear();
  }

  void _rebuildIndex() {
    _counterIndex = {for (final c in _counters) c.id: c};
  }

  // ---------------------------------------------------------------------------
  // Debounced flushing
  // ---------------------------------------------------------------------------

  void _scheduleDirtyFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(
      _flushDelay,
      () => unawaited(_serialized(_flushDirty)),
    );
  }

  /// A tap or a decrement: [delta] on top of whatever the value is when it
  /// is written.
  void _recordDelta<K>(Map<K, _PendingCount> dirty, K key, int delta) {
    dirty.putIfAbsent(key, _PendingCount.new).delta += delta;
  }

  /// A set or a reset: [value] replaces the stored number and the taps before
  /// it.
  void _recordAbsolute<K>(Map<K, _PendingCount> dirty, K key, int value) {
    dirty.putIfAbsent(key, _PendingCount.new)
      ..absolute = value
      ..delta = 0;
  }

  /// Writes each pending change over the value the table holds now, not the
  /// one memory last read: a sync page may have merged another device's count
  /// since, and the taps belong on top of it. Memory then shows what was
  /// written plus any tap made while the write ran.
  Future<void> _flushDirty() async {
    final pending = <(String, String), _PendingCount>{
      for (final MapEntry(key: id, value: change)
          in _dirtyGlobalValues.entries)
        (id, ''): change,
      ..._dirtyNoteValues,
    };
    _dirtyGlobalValues.clear();
    _dirtyNoteValues.clear();
    if (pending.isEmpty) return;

    try {
      final written = <(String, String), int>{};
      await _db.transaction(() async {
        for (final MapEntry(key: (cid, nid), value: change)
            in pending.entries) {
          final counter = _counterIndex[cid];
          if (counter == null) {
            // Every path that drops a counter from the index clears its dirty
            // entries too, so this is defensive — and silent, which is why a
            // future path that rebuilt the index alone would lose taps with
            // no trace (A1b review R28).
            debugPrint('[CounterService] Flush dropped $cid/$nid: no counter');
            continue;
          }
          final stored = await _dao.getValue(cid, nid) ?? counter.startValue;
          final value = change.over(stored);
          await _dao.upsertValue(cid, nid, value);
          written[(cid, nid)] = value;
        }
      });
      for (final MapEntry(key: (cid, nid), value: value) in written.entries) {
        if (nid.isEmpty) {
          _globalValues[cid] = _dirtyGlobalValues[cid]?.over(value) ?? value;
        } else if (_noteValuesCache[nid] case final cache?) {
          cache[cid] = _dirtyNoteValues[(cid, nid)]?.over(value) ?? value;
        }
      }
    } catch (e) {
      debugPrint('[CounterService] Flush error: $e');
      if (_abortsTransaction(e)) {
        // The rollback itself failed, so the writes may be durable: putting
        // [pending] back would apply the same taps a second time. The table
        // is read again instead, and the taps made while the write ran are
        // re-applied over what it holds (A1b review R26).
        await _reloadLocked();
        _changes.add(null);
        // The taps made while the write ran are dirty again after the reload,
        // and the timer that would have written them is cancelled — as on the
        // branch below, they wait for a tap that may never come (A6 review
        // R108).
        _scheduleDirtyFlush();
        return;
      }
      // The transaction rolled back, so nothing in [pending] was written:
      // put it back under any tap made while it ran, for the next flush.
      for (final MapEntry(key: (cid, nid), value: change) in pending.entries) {
        if (nid.isEmpty) {
          _dirtyGlobalValues[cid] = change.then(_dirtyGlobalValues[cid]);
        } else {
          _dirtyNoteValues[(cid, nid)] = change.then(
            _dirtyNoteValues[(cid, nid)],
          );
        }
      }
      // [flush] already cancelled the timer and the debounce fired its own,
      // so without this the restored delta waits for the next tap and a
      // process death takes it (A1b review R21).
      _scheduleDirtyFlush();
    }
  }

  /// Forces all pending writes to disk. Should be called on app pause/close.
  Future<void> flush() async {
    _flushTimer?.cancel();
    await _serialized(_flushDirty);
  }

  // ---------------------------------------------------------------------------
  // Counter definitions
  // ---------------------------------------------------------------------------

  Future<String> addCounter({
    required String name,
    int startValue = 1,
    int step = 1,
    CounterScope scope = CounterScope.global,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    final counter = Counter(
      id: id,
      name: name.trim().isEmpty ? 'Counter' : name.trim(),
      startValue: startValue,
      step: step,
      scope: scope,
      createdAt: now,
    );
    _counters.add(counter);
    _counterIndex[id] = counter;
    _globalValues[id] = startValue;

    await _dao.insertCounterWithValue(
      _counterToCompanion(counter, _counters.length - 1),
      startValue,
    );
    return id;
  }

  Future<void> updateCounter(Counter updated) async {
    final index = _counters.indexWhere((c) => c.id == updated.id);
    if (index < 0) return;
    _counters[index] = updated;
    _counterIndex[updated.id] = updated;
    await _dao.updateCounter(_counterToCompanion(updated, index));
  }

  Future<void> reorderCounters(int oldIndex, int newIndex) async {
    final counter = _counters.removeAt(oldIndex);
    _counters.insert(newIndex, counter);
    _rebuildIndex();

    final positions = <String, int>{};
    for (var i = 0; i < _counters.length; i++) {
      positions[_counters[i].id] = i;
    }
    await _dao.updatePositions(positions);
  }

  Future<void> deleteCounter(String counterId) async {
    _counters.removeWhere((c) => c.id == counterId);
    _counterIndex.remove(counterId);
    _globalValues.remove(counterId);
    _dirtyGlobalValues.remove(counterId);
    _dirtyNoteValues.removeWhere((pair, _) => pair.$1 == counterId);
    for (final cache in _noteValuesCache.values) {
      cache.remove(counterId);
    }
    await _dao.deleteCounter(counterId);
  }

  Future<void> deleteNoteValue(String counterId, String noteId) async {
    _noteValuesCache[noteId]?.remove(counterId);
    // A pending tap is written over the stored value, and would bring the
    // deleted one back.
    _dirtyNoteValues.remove((counterId, noteId));
    await _dao.deleteValue(counterId, noteId);
  }

  // ---------------------------------------------------------------------------
  // Global values
  // ---------------------------------------------------------------------------

  int getGlobalValue(String counterId) {
    final counter = _counterIndex[counterId];
    if (counter == null) throw StateError('Counter not found: $counterId');
    return _globalValues[counterId] ?? counter.startValue;
  }

  Future<int> incrementGlobal(String counterId) async {
    final counter = _counterIndex[counterId];
    if (counter == null) throw StateError('Counter not found: $counterId');
    final current = _globalValues[counterId] ?? counter.startValue;
    final next = current + counter.step;
    _globalValues[counterId] = next;
    _recordDelta(_dirtyGlobalValues, counterId, counter.step);
    _scheduleDirtyFlush();
    return next;
  }

  /// A Reset is recorded even when memory already shows the start value: in
  /// the window between a pull's page committing and its reload, memory still
  /// holds the pre-merge number, and an early return there would drop the
  /// Reset and let the reload put the merged count back (A1b review R24).
  ///
  /// The table, not memory, is what says there is nothing to reset: no value
  /// row means every device reads the counter at its start value already, so
  /// recording the Reset would write a row and an outbox entry where an
  /// unbound database had neither (A6 review R117). A merged page has
  /// committed its row by the time memory goes stale, so R24's window stays
  /// closed — and the look is taken inside the flush queue, or a flush in
  /// flight with the first tap for this counter would still be writing the
  /// row this read answers for.
  Future<void> resetGlobal(String counterId) async {
    final counter = _counterIndex[counterId];
    if (counter == null) throw StateError('Counter not found: $counterId');
    _globalValues[counterId] = counter.startValue;
    await _serialized(() async {
      if (!_dirtyGlobalValues.containsKey(counterId) &&
          !await _hasStoredGlobalValue(counterId)) {
        return;
      }
      _recordAbsolute(_dirtyGlobalValues, counterId, counter.startValue);
      _scheduleDirtyFlush();
    });
  }

  /// Whether the table holds a live global value row for [counterId]. A read
  /// that failed answers true: a Reset recorded for nothing is one write the
  /// DAO suppresses, a Reset dropped is gone.
  Future<bool> _hasStoredGlobalValue(String counterId) async {
    try {
      return await _dao.getValue(counterId, '') != null;
    } catch (e) {
      debugPrint('[CounterService] Reset read failed: $e');
      return true;
    }
  }

  Future<int> decrementGlobal(String counterId) async {
    final counter = _counterIndex[counterId];
    if (counter == null) throw StateError('Counter not found: $counterId');
    final current = _globalValues[counterId] ?? counter.startValue;
    final next = current - counter.step;
    _globalValues[counterId] = next;
    _recordDelta(_dirtyGlobalValues, counterId, -counter.step);
    _scheduleDirtyFlush();
    return next;
  }

  Future<void> setGlobalValue(String counterId, int value) async {
    if (!_counterIndex.containsKey(counterId)) return;
    _globalValues[counterId] = value;
    _recordAbsolute(_dirtyGlobalValues, counterId, value);
    _scheduleDirtyFlush();
  }

  // ---------------------------------------------------------------------------
  // Per-note values
  // ---------------------------------------------------------------------------

  Future<Map<String, int>> getNoteValues(String noteId) async {
    if (_noteValuesCache.containsKey(noteId)) {
      return _noteValuesCache[noteId]!;
    }
    final fromDb = await _dao.getValuesForNote(noteId);
    // A reload dropped this note's cache while its taps were still pending.
    for (final MapEntry(key: (cid, nid), value: pending)
        in _dirtyNoteValues.entries) {
      final counter = _counterIndex[cid];
      if (nid != noteId || counter == null) continue;
      fromDb[cid] = pending.over(fromDb[cid] ?? counter.startValue);
    }
    _noteValuesCache[noteId] = fromDb;
    return fromDb;
  }

  Future<int> getValueForNote(String counterId, String noteId) async {
    final counter = _counterIndex[counterId];
    if (counter == null) throw StateError('Counter not found: $counterId');
    if (counter.scope == CounterScope.global) {
      return getGlobalValue(counterId);
    }
    final noteValues = await getNoteValues(noteId);
    return noteValues[counterId] ?? counter.startValue;
  }

  Future<int> increment(String counterId, {String? noteId}) async {
    final counter = _counterIndex[counterId];
    if (counter == null) throw StateError('Counter not found: $counterId');

    if (counter.scope == CounterScope.global) {
      return incrementGlobal(counterId);
    }
    if (noteId == null) return counter.startValue;

    final noteValues = await getNoteValues(noteId);
    final current = noteValues[counterId] ?? counter.startValue;
    final next = current + counter.step;
    noteValues[counterId] = next;
    _recordDelta(_dirtyNoteValues, (counterId, noteId), counter.step);
    _scheduleDirtyFlush();
    return next;
  }

  Future<int> decrementForNote(String counterId, String noteId) async {
    final counter = _counterIndex[counterId];
    if (counter == null) throw StateError('Counter not found: $counterId');

    if (counter.scope == CounterScope.global) {
      return decrementGlobal(counterId);
    }

    final noteValues = await getNoteValues(noteId);
    final current = noteValues[counterId] ?? counter.startValue;
    final next = current - counter.step;
    noteValues[counterId] = next;
    _recordDelta(_dirtyNoteValues, (counterId, noteId), -counter.step);
    _scheduleDirtyFlush();
    return next;
  }

  Future<void> setValueForNote(
    String counterId,
    int value, {
    String? noteId,
  }) async {
    final counter = getCounterById(counterId);
    if (counter == null) return;

    if (counter.scope == CounterScope.global || noteId == null) {
      await setGlobalValue(counterId, value);
      return;
    }

    final noteValues = await getNoteValues(noteId);
    noteValues[counterId] = value;
    _recordAbsolute(_dirtyNoteValues, (counterId, noteId), value);
    _scheduleDirtyFlush();
  }

  Future<void> resetForNote(String counterId, String noteId) async {
    final counter = _counterIndex[counterId];
    if (counter == null) throw StateError('Counter not found: $counterId');

    if (counter.scope == CounterScope.global) {
      await resetGlobal(counterId);
      return;
    }

    final noteValues = await getNoteValues(noteId);
    noteValues[counterId] = counter.startValue;
    _recordAbsolute(
      _dirtyNoteValues,
      (counterId, noteId),
      counter.startValue,
    );
    _scheduleDirtyFlush();
  }

  // ---------------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------------

  Counter? getCounterById(String counterId) => _counterIndex[counterId];

  Future<Map<String, int>> getAllNoteValuesForCounter(String counterId) async {
    return _dao.getValuesForCounter(counterId);
  }

  // ---------------------------------------------------------------------------
  // Backup export / import
  // ---------------------------------------------------------------------------

  /// Values are written only under live counters: a value merged from
  /// another device under a counter tombstoned there is kept in the table for
  /// the merge, but in a backup it would be an orphan no restore can show.
  ///
  /// Everything is read from the database after [flush], never from the
  /// cache: a counter a sync merged but the service has not reloaded yet is
  /// in the table, not in memory (S3a review F6).
  Future<Map<String, dynamic>> exportData() async {
    await flush();
    final liveCounters = await _dao.getAllCounters();
    final liveIds = {for (final row in liveCounters) row.id};
    final allValues = await _dao.getAllValues();
    final globalValues = <String, int>{};
    final noteValuesMap = <String, Map<String, int>>{};
    final noteValueExtras = <String, Map<String, dynamic>>{};
    for (final row in allValues) {
      if (!liveIds.contains(row.counterId)) continue;
      // A value's ownership rides its extras entry, global values included
      // under an empty note id: the value maps hold bare ints an older
      // importer casts, and its extras loop reads only the keys it knows.
      if (row.ownerId != null) {
        noteValueExtras['${row.counterId}::${row.noteId}'] = {
          'ownerId': row.ownerId,
        };
      }
      if (row.noteId.isEmpty) {
        globalValues[row.counterId] = row.value;
        continue;
      }
      noteValuesMap.putIfAbsent(row.noteId, () => {})[row.counterId] =
          row.value;
      if (row.isPinned || row.position != 0) {
        noteValueExtras.putIfAbsent('${row.counterId}::${row.noteId}', () => {})
          ..['isPinned'] = row.isPinned
          ..['position'] = row.position;
      }
    }
    return {
      'counters': jsonEncode([
        for (final row in liveCounters)
          {
            ..._rowToCounter(row).toJson(),
            if (row.ownerId != null) 'ownerId': row.ownerId,
          },
      ]),
      'globalValues': jsonEncode(globalValues),
      'noteValues': jsonEncode(noteValuesMap),
      'noteValueExtras': jsonEncode(noteValueExtras),
    };
  }

  /// Runs inside the flush queue: a `_flushDirty` that had already copied its
  /// pending changes and was awaiting its transaction would otherwise write
  /// them after the restore's `deleteAll` and inserts, resurrecting a value
  /// row the backup never carried (A1b review R25).
  Future<void> importData(Map<String, dynamic> data) async {
    await _serialized(() => _importData(data));
    _changes.add(null);
  }

  Future<void> _importData(Map<String, dynamic> data) async {
    await _dao.deleteAll();
    _noteValuesCache.clear();
    _dirtyGlobalValues.clear();
    _dirtyNoteValues.clear();
    _flushTimer?.cancel();

    final extrasRaw = data['noteValueExtras'] as String?;
    final valueOwners = <String, String>{};
    if (extrasRaw != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(extrasRaw);
        for (final entry in decoded.entries) {
          final ownerId = JsonKeys.ownerIdOf(
            entry.value as Map<String, dynamic>,
          );
          if (ownerId != null) valueOwners[entry.key] = ownerId;
        }
      } catch (e) {
        debugPrint('[CounterService] Import value owners error: $e');
      }
    }

    final countersRaw = data['counters'] as String?;
    if (countersRaw != null) {
      try {
        final List<dynamic> decoded = jsonDecode(countersRaw);
        final maps = decoded.cast<Map<String, dynamic>>();
        await Future.wait([
          for (var i = 0; i < maps.length; i++)
            _dao.insertCounter(
              _counterToCompanion(
                Counter.fromJson(maps[i]),
                i,
              ).copyWith(ownerId: Value(JsonKeys.ownerIdOf(maps[i]))),
            ),
        ]);
      } catch (e) {
        debugPrint('[CounterService] Import counters error: $e');
      }
    }

    final valuesRaw = data['globalValues'] as String?;
    if (valuesRaw != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(valuesRaw);
        await Future.wait([
          for (final entry in decoded.entries)
            _dao.upsertValue(
              entry.key,
              '',
              entry.value as int,
              ownerId: valueOwners['${entry.key}::'],
            ),
        ]);
      } catch (e) {
        debugPrint('[CounterService] Import global values error: $e');
      }
    }

    final noteValuesRaw = data['noteValues'] as String?;
    if (noteValuesRaw != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(noteValuesRaw);
        final futures = <Future>[];
        for (final noteEntry in decoded.entries) {
          final noteId = noteEntry.key;
          final values = noteEntry.value as Map<String, dynamic>;
          for (final valEntry in values.entries) {
            futures.add(
              _dao.upsertValue(
                valEntry.key,
                noteId,
                valEntry.value as int,
                ownerId: valueOwners['${valEntry.key}::$noteId'],
              ),
            );
          }
        }
        await Future.wait(futures);
      } catch (e) {
        debugPrint('[CounterService] Import note values error: $e');
      }
    }

    if (extrasRaw != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(extrasRaw);
        final futures = <Future>[];
        for (final entry in decoded.entries) {
          final parts = entry.key.split('::');
          if (parts.length != 2) continue;
          final counterId = parts[0];
          final noteId = parts[1];
          final extra = entry.value as Map<String, dynamic>;
          final isPinned = extra['isPinned'] as bool? ?? false;
          final position = extra['position'] as int? ?? 0;
          if (isPinned) {
            futures.add(_dao.setNoteValuePinned(counterId, noteId, true));
          }
          if (position != 0) {
            futures.add(
              _dao.updateNoteValuePositions(counterId, {noteId: position}),
            );
          }
        }
        await Future.wait(futures);
      } catch (e) {
        debugPrint('[CounterService] Import note value extras error: $e');
      }
    }

    await _load();
  }

  // ---------------------------------------------------------------------------
  // Pin
  // ---------------------------------------------------------------------------

  Future<void> toggleCounterPin(String counterId) async {
    final index = _counters.indexWhere((c) => c.id == counterId);
    if (index < 0) return;
    final counter = _counters[index];
    final newPinned = !counter.isPinned;
    _counters[index] = counter.copyWith(isPinned: newPinned);
    _counters.sort(_counterSortComparator);
    _rebuildIndex();
    final positions = <String, int>{};
    for (var i = 0; i < _counters.length; i++) {
      positions[_counters[i].id] = i;
    }
    await _dao.setCounterPinned(counterId, newPinned, positions: positions);
  }

  Future<void> toggleNoteValuePin(
    String counterId,
    String noteId,
    bool pinned,
  ) async {
    await _dao.setNoteValuePinned(counterId, noteId, pinned);
  }

  Future<void> reorderNoteValues(
    String counterId,
    Map<String, int> positions,
  ) async {
    await _dao.updateNoteValuePositions(counterId, positions);
  }

  Future<List<CounterValueRow>> getOrderedNoteValuesForCounter(
    String counterId,
  ) {
    return _dao.getValuesForCounterOrdered(counterId);
  }

  static int _counterSortComparator(Counter a, Counter b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    return 0;
  }

  // ---------------------------------------------------------------------------
  // Row ↔ Model mapping
  // ---------------------------------------------------------------------------

  static Counter _rowToCounter(CounterRow row) {
    return Counter(
      id: row.id,
      name: row.name,
      startValue: row.startValue,
      step: row.step,
      scope: CounterScope.values.firstWhere(
        (s) => s.name == row.scope,
        orElse: () => CounterScope.global,
      ),
      isPinned: row.isPinned,
      createdAt: row.createdAt,
    );
  }

  static CountersCompanion _counterToCompanion(Counter c, int position) {
    return CountersCompanion(
      id: Value(c.id),
      name: Value(c.name),
      startValue: Value(c.startValue),
      step: Value(c.step),
      scope: Value(c.scope.name),
      position: Value(position),
      isPinned: Value(c.isPinned),
      createdAt: Value(c.createdAt),
    );
  }
}

/// The SQLite primary result codes that leave no transaction to roll back —
/// a full disk, an I/O error, a corrupt file.
const Set<int> _sqliteAbortingCodes = {
  10, // SQLITE_IOERR
  11, // SQLITE_CORRUPT
  13, // SQLITE_FULL
};

/// Whether [error] took SQLite's whole transaction with it: the savepoint is
/// gone, so what the flush wrote before the throw may be durable and must not
/// be written a second time. The unwrap is part of it — the database runs in a
/// background isolate, which hands a SQLite error over wrapped.
///
/// An allow-list, unlike the pull's `_abortsTransaction` (record §3.5, S3d
/// review H1), which answers true for everything but a constraint violation.
/// It can: its caller rethrows and the page is pulled again at the same
/// cursor. This one's caller throws the taps away, and `SQLITE_BUSY`,
/// `SQLITE_LOCKED` and `SQLITE_READONLY` all roll back cleanly with nothing
/// written — a tap lost to a database another connection held is strictly
/// worse than writing it twice (A6 review R107).
bool _abortsTransaction(Object error) {
  var cause = error;
  while (cause is DriftRemoteException) {
    cause = cause.remoteCause;
  }
  return cause is CouldNotRollBackException ||
      (cause is SqliteException &&
          _sqliteAbortingCodes.contains(cause.resultCode));
}

/// A value's change since its last flush: the taps as a [delta], so a count
/// another device merged meanwhile keeps them on top; a set or a reset as an
/// [absolute] the later taps add to.
class _PendingCount {
  int? absolute;
  int delta = 0;

  int over(int base) => (absolute ?? base) + delta;

  /// This change followed by [later]: a later set or reset replaces it, later
  /// taps add to it.
  _PendingCount then(_PendingCount? later) {
    if (later == null) return this;
    if (later.absolute != null) return later;
    return _PendingCount()
      ..absolute = absolute
      ..delta = delta + later.delta;
  }
}
