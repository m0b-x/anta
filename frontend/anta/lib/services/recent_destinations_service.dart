import 'dart:async';

/// Tracks recently used move destinations (folder ids) so the folder picker
/// can surface them as quick-pick chips/list. Most-recent-first, deduplicated,
/// capped at [maxSize].
///
/// Storage is in-memory by design (mirrors [MoveHistoryService]); a future
/// implementation can persist to SQLite without changing the public API.
class RecentDestinationsService {
  static const int _maxSize = 8;

  /// `null` means "root". We keep nullable ids so root can also be a recent.
  final List<String?> _recents = [];
  final _changesController = StreamController<List<String?>>.broadcast();

  Stream<List<String?>> get changes => _changesController.stream;

  /// Most-recent-first list of destination ids (null = root).
  List<String?> get recents => List.unmodifiable(_recents);

  /// Record [folderId] (or null for root) as the most recent destination.
  void record(String? folderId) {
    _recents.removeWhere((id) => id == folderId);
    _recents.insert(0, folderId);
    if (_recents.length > _maxSize) {
      _recents.removeRange(_maxSize, _recents.length);
    }
    _emit();
  }

  /// Drop a destination — call when a folder is deleted.
  void forget(String folderId) {
    final removed = _recents.remove(folderId);
    if (removed) _emit();
  }

  void clear() {
    if (_recents.isEmpty) return;
    _recents.clear();
    _emit();
  }

  void _emit() {
    if (_changesController.isClosed) return;
    _changesController.add(recents);
  }

  void dispose() {
    _changesController.close();
  }
}
