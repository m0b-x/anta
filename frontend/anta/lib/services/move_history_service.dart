import 'dart:async';

import 'package:uuid/uuid.dart';

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

/// Tracks recent move operations and exposes them to the UI for undo.
///
/// The service itself is in-memory but writes through a [MoveHistoryStore],
/// so persistence can be added later by swapping in a different store
/// implementation without touching any callers.
class MoveHistoryService {
  static const _maxHistorySize = 20;
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

  /// Number of entries that have NOT been undone yet.
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
    unawaited(_store.trim(_maxHistorySize));
    _changesController.add(undoableCount);
    return entry.id;
  }

  void markUndone(String id) {
    final idx = _history.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    _history[idx] = _history[idx].copyWith(isUndone: true);
    unawaited(_store.markUndone(id));
    _changesController.add(undoableCount);
  }

  void clearHistory() {
    _history.clear();
    unawaited(_store.clear());
    _changesController.add(0);
  }

  /// All entry ids belonging to [batchId], in the same order they were added.
  /// Returns an empty list if no such batch exists.
  List<String> entryIdsInBatch(String batchId) {
    return _history
        .where((e) => e.batchId == batchId)
        .map((e) => e.id)
        .toList(growable: false);
  }

  void _trimHistory() {
    if (_history.length > _maxHistorySize) {
      _history.removeRange(_maxHistorySize, _history.length);
    }
  }

  void dispose() {
    _changesController.close();
  }
}
