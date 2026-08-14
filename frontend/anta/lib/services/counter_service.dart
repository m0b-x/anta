import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

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

  /// Set of dirty counter IDs whose global value needs flushing.
  final Set<String> _dirtyGlobalValues = {};

  /// Set of dirty noteIds whose per-note values need flushing.
  final Set<String> _dirtyNoteValues = {};

  Timer? _flushTimer;
  static const _flushDelay = Duration(milliseconds: 300);

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
    }
    return _instance!;
  }

  static void reset() {
    _instance?._flushTimer?.cancel();
    _instance = null;
  }

  List<Counter> get counters => List.unmodifiable(_counters);

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
    _flushTimer = Timer(_flushDelay, _flushDirty);
  }

  Future<void> _flushDirty() async {
    final globalIds = Set<String>.from(_dirtyGlobalValues);
    final noteIds = Set<String>.from(_dirtyNoteValues);
    _dirtyGlobalValues.clear();
    _dirtyNoteValues.clear();

    try {
      final futures = <Future>[];
      for (final cid in globalIds) {
        final val = _globalValues[cid];
        if (val != null) {
          futures.add(_dao.upsertValue(cid, '', val));
        }
      }
      for (final nid in noteIds) {
        final noteMap = _noteValuesCache[nid];
        if (noteMap == null) continue;
        for (final entry in noteMap.entries) {
          futures.add(_dao.upsertValue(entry.key, nid, entry.value));
        }
      }
      if (futures.isNotEmpty) await Future.wait(futures);
    } catch (e) {
      debugPrint('[CounterService] Flush error: $e');
    }
  }

  /// Forces all pending writes to disk. Should be called on app pause/close.
  Future<void> flush() async {
    _flushTimer?.cancel();
    await _flushDirty();
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

    await Future.wait([
      _dao.insertCounter(_counterToCompanion(counter, _counters.length - 1)),
      _dao.upsertValue(id, '', startValue),
    ]);
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
    for (final cache in _noteValuesCache.values) {
      cache.remove(counterId);
    }
    await Future.wait([
      _dao.deleteCounter(counterId),
      _dao.deleteCounterValues(counterId),
    ]);
  }

  Future<void> deleteNoteValue(String counterId, String noteId) async {
    _noteValuesCache[noteId]?.remove(counterId);
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
    _dirtyGlobalValues.add(counterId);
    _scheduleDirtyFlush();
    return next;
  }

  Future<void> resetGlobal(String counterId) async {
    final counter = _counterIndex[counterId];
    if (counter == null) throw StateError('Counter not found: $counterId');
    _globalValues[counterId] = counter.startValue;
    _dirtyGlobalValues.add(counterId);
    _scheduleDirtyFlush();
  }

  Future<int> decrementGlobal(String counterId) async {
    final counter = _counterIndex[counterId];
    if (counter == null) throw StateError('Counter not found: $counterId');
    final current = _globalValues[counterId] ?? counter.startValue;
    final next = current - counter.step;
    _globalValues[counterId] = next;
    _dirtyGlobalValues.add(counterId);
    _scheduleDirtyFlush();
    return next;
  }

  Future<void> setGlobalValue(String counterId, int value) async {
    if (!_counterIndex.containsKey(counterId)) return;
    _globalValues[counterId] = value;
    _dirtyGlobalValues.add(counterId);
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
    _dirtyNoteValues.add(noteId);
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
    _dirtyNoteValues.add(noteId);
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
    _dirtyNoteValues.add(noteId);
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
    _dirtyNoteValues.add(noteId);
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

  Future<Map<String, dynamic>> exportData() async {
    await flush();
    final allValues = await _dao.getAllValues();
    final noteValuesMap = <String, Map<String, int>>{};
    final noteValueExtras = <String, Map<String, dynamic>>{};
    for (final row in allValues) {
      if (row.noteId.isEmpty) continue;
      noteValuesMap.putIfAbsent(row.noteId, () => {})[row.counterId] =
          row.value;
      if (row.isPinned || row.position != 0) {
        noteValueExtras['${row.counterId}::${row.noteId}'] = {
          'isPinned': row.isPinned,
          'position': row.position,
        };
      }
    }
    return {
      'counters': jsonEncode(_counters.map((c) => c.toJson()).toList()),
      'globalValues': jsonEncode(_globalValues),
      'noteValues': jsonEncode(noteValuesMap),
      'noteValueExtras': jsonEncode(noteValueExtras),
    };
  }

  Future<void> importData(Map<String, dynamic> data) async {
    await _dao.deleteAll();
    _noteValuesCache.clear();
    _dirtyGlobalValues.clear();
    _dirtyNoteValues.clear();
    _flushTimer?.cancel();

    final countersRaw = data['counters'] as String?;
    if (countersRaw != null) {
      try {
        final List<dynamic> decoded = jsonDecode(countersRaw);
        final imported = decoded
            .map((j) => Counter.fromJson(j as Map<String, dynamic>))
            .toList();
        await Future.wait([
          for (var i = 0; i < imported.length; i++)
            _dao.insertCounter(_counterToCompanion(imported[i], i)),
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
            _dao.upsertValue(entry.key, '', entry.value as int),
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
              _dao.upsertValue(valEntry.key, noteId, valEntry.value as int),
            );
          }
        }
        await Future.wait(futures);
      } catch (e) {
        debugPrint('[CounterService] Import note values error: $e');
      }
    }

    final extrasRaw = data['noteValueExtras'] as String?;
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
    await Future.wait([
      _dao.setCounterPinned(counterId, newPinned),
      _dao.updatePositions(positions),
    ]);
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
