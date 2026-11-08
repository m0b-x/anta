import '../services/move_history_service.dart'
    show MoveHistoryEntry, retainUndoUnits;

/// Pluggable storage backend for move history entries. The default
/// implementation is in-memory (volatile across app restarts), but a future
/// SQLite-backed implementation can be dropped in via DI without touching
/// callers.
///
/// Implementations are expected to be ordered most-recent-first.
abstract class MoveHistoryStore {
  /// Load all entries on startup (returned in most-recent-first order).
  /// In-memory implementations may return an empty list.
  Future<List<MoveHistoryEntry>> loadAll();

  Future<void> add(MoveHistoryEntry entry);

  /// [add] for a whole batch at once; [entries] are newest first.
  Future<void> addAll(List<MoveHistoryEntry> entries);

  /// Marks every entry in [entryIds] undone, in one pass over the store.
  Future<void> markAllUndone(Set<String> entryIds);

  /// Remove the oldest undo units beyond [maxUnits], and older units while
  /// the entries would pass [maxEntries] — whole units only, by
  /// [retainUndoUnits], so a stored batch is never left half undoable.
  Future<void> trim({required int maxUnits, required int maxEntries});

  Future<void> clear();
}

/// Default volatile, in-memory store. History is lost on app restart.
class InMemoryMoveHistoryStore implements MoveHistoryStore {
  final List<MoveHistoryEntry> _entries = [];

  @override
  Future<List<MoveHistoryEntry>> loadAll() async => List.of(_entries);

  @override
  Future<void> add(MoveHistoryEntry entry) async {
    _entries.insert(0, entry);
  }

  @override
  Future<void> addAll(List<MoveHistoryEntry> entries) async {
    _entries.insertAll(0, entries);
  }

  @override
  Future<void> markAllUndone(Set<String> entryIds) async {
    for (var i = 0; i < _entries.length; i++) {
      if (entryIds.contains(_entries[i].id)) {
        _entries[i] = _entries[i].copyWith(isUndone: true);
      }
    }
  }

  @override
  Future<void> trim({required int maxUnits, required int maxEntries}) async {
    final kept = retainUndoUnits(
      _entries,
      maxUnits: maxUnits,
      maxEntries: maxEntries,
    );
    _entries
      ..clear()
      ..addAll(kept);
  }

  @override
  Future<void> clear() async {
    _entries.clear();
  }
}
