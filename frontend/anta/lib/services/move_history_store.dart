import '../services/move_history_service.dart' show MoveHistoryEntry;

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

  Future<void> markUndone(String entryId);

  /// Remove the oldest entries beyond [maxSize].
  Future<void> trim(int maxSize);

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
  Future<void> markUndone(String entryId) async {
    final index = _entries.indexWhere((e) => e.id == entryId);
    if (index == -1) return;
    _entries[index] = _entries[index].copyWith(isUndone: true);
  }

  @override
  Future<void> trim(int maxSize) async {
    if (_entries.length > maxSize) {
      _entries.removeRange(maxSize, _entries.length);
    }
  }

  @override
  Future<void> clear() async {
    _entries.clear();
  }
}
