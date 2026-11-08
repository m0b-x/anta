import 'dart:async';

import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import 'move_history_store.dart';

enum MoveItemType { folder, note }

class MoveHistoryEntry {
  final String id;
  final MoveItemType itemType;
  final String itemId;
  final String itemName;
  final String? sourceParentId;
  final String? sourceParentName;
  final String? targetParentId;
  final String? targetParentName;
  final DateTime timestamp;
  final bool isUndone;

  /// Identifies a batch operation. All entries created together (selection-mode
  /// move, drag-drop on a folder) share the same id, allowing one Undo action
  /// to revert the whole group atomically.
  final String? batchId;

  const MoveHistoryEntry({
    required this.id,
    required this.itemType,
    required this.itemId,
    required this.itemName,
    required this.sourceParentId,
    required this.sourceParentName,
    required this.targetParentId,
    required this.targetParentName,
    required this.timestamp,
    this.isUndone = false,
    this.batchId,
  });

  MoveHistoryEntry copyWith({bool? isUndone}) {
    return MoveHistoryEntry(
      id: id,
      itemType: itemType,
      itemId: itemId,
      itemName: itemName,
      sourceParentId: sourceParentId,
      sourceParentName: sourceParentName,
      targetParentId: targetParentId,
      targetParentName: targetParentName,
      timestamp: timestamp,
      isUndone: isUndone ?? this.isUndone,
      batchId: batchId,
    );
  }
}

/// One item of a batch handed to [MoveHistoryService.addMoves]: what moved
/// and where from; the destination and the batch are shared.
typedef MoveHistoryItem = ({
  MoveItemType itemType,
  String itemId,
  String itemName,
  String? sourceParentId,
  String? sourceParentName,
});

/// The entries of [newestFirst] that the history keeps: the newest
/// [maxUnits] undo units — a batch is one unit (its [MoveHistoryEntry.batchId]),
/// any other entry is a unit of its own — whole, dropping older units whole
/// while the total would pass [maxEntries].
///
/// Cutting by entries used to keep a 25-item batch's last 20 rows, so its
/// Undo restored 20 and said it had restored the move. The newest unit is
/// kept whole even past [maxEntries]: its Undo is the one on screen.
List<MoveHistoryEntry> retainUndoUnits(
  List<MoveHistoryEntry> newestFirst, {
  required int maxUnits,
  required int maxEntries,
}) {
  final sizes = <String, int>{};
  for (final entry in newestFirst) {
    final unit = entry.batchId ?? entry.id;
    sizes[unit] = (sizes[unit] ?? 0) + 1;
  }
  final kept = <String>{};
  var total = 0;
  for (final MapEntry(key: unit, value: size) in sizes.entries) {
    if (kept.length == maxUnits) break;
    if (kept.isNotEmpty && total + size > maxEntries) break;
    kept.add(unit);
    total += size;
  }
  return [
    for (final entry in newestFirst)
      if (kept.contains(entry.batchId ?? entry.id)) entry,
  ];
}

/// Tracks recent move operations and exposes them to the UI for undo.
///
/// The service itself is in-memory but writes through a [MoveHistoryStore],
/// so persistence can be added later by swapping in a different store
/// implementation without touching any callers.
class MoveHistoryService {
  static const _maxUnits = AppConstants.moveHistoryMaxUnits;
  static const _maxEntries = AppConstants.moveHistoryMaxEntries;
  static const _uuid = Uuid();

  final MoveHistoryStore _store;
  final List<MoveHistoryEntry> _history = [];
  final StreamController<int> _changesController =
      StreamController<int>.broadcast();

  MoveHistoryService({MoveHistoryStore? store})
    : _store = store ?? InMemoryMoveHistoryStore() {
    unawaited(_hydrate());
  }

  Future<void> _hydrate() async {
    final loaded = await _store.loadAll();
    if (loaded.isEmpty) return;
    _history
      ..clear()
      ..addAll(loaded);
    _trimHistory();
    _changesController.add(undoableCount);
  }

  /// Snapshot of every entry, newest first.
  List<MoveHistoryEntry> get history => List.unmodifiable(_history);

  /// Number of entries that have NOT been undone yet — items, not units, so
  /// one 25-item batch counts 25.
  int get undoableCount => _history.where((e) => !e.isUndone).length;

  /// Stream that fires every time the history mutates. Emits the new
  /// [undoableCount] so UI badges can update without re-reading the whole list.
  Stream<int> get changes => _changesController.stream;

  bool isEntryUndone(String id) {
    final idx = _history.indexWhere((e) => e.id == id);
    if (idx == -1) return false;
    return _history[idx].isUndone;
  }

  /// Append a new move entry. Returns the id of the created entry so callers
  /// can pair it with a snackbar's Undo button.
  String addMove({
    required MoveItemType itemType,
    required String itemId,
    required String itemName,
    required String? sourceParentId,
    required String? sourceParentName,
    required String? targetParentId,
    required String? targetParentName,
    String? batchId,
  }) {
    final entry = MoveHistoryEntry(
      id: _uuid.v4(),
      itemType: itemType,
      itemId: itemId,
      itemName: itemName,
      sourceParentId: sourceParentId,
      sourceParentName: sourceParentName,
      targetParentId: targetParentId,
      targetParentName: targetParentName,
      timestamp: DateTime.now(),
      batchId: batchId,
    );
    _history.insert(0, entry);
    _trimHistory();
    unawaited(_store.add(entry));
    unawaited(_store.trim(maxUnits: _maxUnits, maxEntries: _maxEntries));
    _changesController.add(undoableCount);
    return entry.id;
  }

  /// Records a whole batch as one undo unit sharing [batchId], trimmed and
  /// announced once rather than once per item. Entries land in the order
  /// [addMove] called once per item would leave them.
  void addMoves(
    List<MoveHistoryItem> items, {
    required String? targetParentId,
    required String? targetParentName,
    required String batchId,
  }) {
    if (items.isEmpty) return;
    final now = DateTime.now();
    // Built once, newest first, and put in front in one step: inserting each
    // at index 0 made a large batch quadratic.
    final entries = [
      for (final item in items.reversed)
        MoveHistoryEntry(
          id: _uuid.v4(),
          itemType: item.itemType,
          itemId: item.itemId,
          itemName: item.itemName,
          sourceParentId: item.sourceParentId,
          sourceParentName: item.sourceParentName,
          targetParentId: targetParentId,
          targetParentName: targetParentName,
          timestamp: now,
          batchId: batchId,
        ),
    ];
    _history.insertAll(0, entries);
    unawaited(_store.addAll(entries));
    _trimHistory();
    unawaited(_store.trim(maxUnits: _maxUnits, maxEntries: _maxEntries));
    _changesController.add(undoableCount);
  }

  /// Marks the one entry [id] undone, as its own snackbar's Undo restored it.
  void markUndone(String id) => markAllUndone([id]);

  /// Marks every entry in [ids] undone and announces it once — one pass over
  /// the history against a set, however many entries a unit holds.
  void markAllUndone(Iterable<String> ids) {
    final wanted = ids.toSet();
    var changed = false;
    for (var i = 0; i < _history.length; i++) {
      if (!wanted.contains(_history[i].id)) continue;
      _history[i] = _history[i].copyWith(isUndone: true);
      changed = true;
    }
    if (!changed) return;
    unawaited(_store.markAllUndone(wanted));
    _changesController.add(undoableCount);
  }

  void clearHistory() {
    _history.clear();
    unawaited(_store.clear());
    _changesController.add(0);
  }

  void _trimHistory() {
    final kept = retainUndoUnits(
      _history,
      maxUnits: _maxUnits,
      maxEntries: _maxEntries,
    );
    if (kept.length == _history.length) return;
    _history
      ..clear()
      ..addAll(kept);
  }

  void dispose() {
    _changesController.close();
  }
}
