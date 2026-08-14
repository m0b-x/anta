import 'dart:async';

import '../models/folder.dart' as model;
import 'folder_search_service.dart' show normalizeForSearch;
import 'folder_storage_service.dart';

/// Fast in-memory folder-name index for the folder picker dialog's search.
///
/// Keeps a single normalized-name list (sorted) and a parallel folder list.
/// Search performs:
///   1. binary-search prefix match (case + diacritic insensitive) — O(log n)
///   2. substring fallback for queries >= 2 chars — O(n)
///
/// At a few thousand folders this is comfortably sub-millisecond per keystroke.
/// Rebuilds when the underlying folder set changes (subscription on
/// [FolderStorageService.changes]).
class FolderNameIndex {
  final FolderStorageService _folderService;

  List<model.Folder> _folders = [];
  // Parallel arrays — _normalized[i] is the normalized name of _folders[i],
  // sorted ascending so we can binary-search.
  List<_IndexedEntry> _entries = [];

  bool _isBuilt = false;
  Future<void>? _buildFuture;
  StreamSubscription<dynamic>? _invalidationSub;

  FolderNameIndex({required FolderStorageService folderService})
    : _folderService = folderService {
    // Any folder change invalidates the index lazily — we mark dirty and
    // rebuild on next search rather than on every event.
    _invalidationSub = _folderService.changes.listen((_) => _markDirty());
  }

  bool get isBuilt => _isBuilt;
  int get folderCount => _folders.length;

  void _markDirty() {
    _isBuilt = false;
    _buildFuture = null;
  }

  /// Eagerly build the index. Optional — [search] auto-builds.
  Future<void> ensureBuilt() {
    if (_isBuilt) return Future.value();
    return _buildFuture ??= _build();
  }

  Future<void> _build() async {
    final folders = await _folderService.loadAllFolders();
    final entries =
        folders
            .map(
              (f) => _IndexedEntry(
                folder: f,
                normalizedName: normalizeForSearch(f.name),
              ),
            )
            .toList()
          ..sort((a, b) => a.normalizedName.compareTo(b.normalizedName));

    _folders = folders;
    _entries = entries;
    _isBuilt = true;
    _buildFuture = null;
  }

  /// Search by [query]. Returns matches in their original sort order
  /// (alphabetical, case + diacritic insensitive). Excludes folders whose
  /// id is in [excludeIds]. Returns at most [limit] results.
  Future<List<model.Folder>> search(
    String query, {
    Set<String> excludeIds = const {},
    int limit = 50,
  }) async {
    await ensureBuilt();

    final normalized = normalizeForSearch(query.trim());
    if (normalized.isEmpty) return const [];

    final results = <model.Folder>[];
    final seen = <String>{};

    // Prefix matches via binary search.
    final start = _lowerBound(normalized);
    for (int i = start; i < _entries.length; i++) {
      final entry = _entries[i];
      if (!entry.normalizedName.startsWith(normalized)) break;
      if (excludeIds.contains(entry.folder.id)) continue;
      if (seen.add(entry.folder.id)) {
        results.add(entry.folder);
        if (results.length >= limit) return results;
      }
    }

    // Substring fallback (skip prefix matches we already added).
    if (normalized.length >= 2) {
      for (final entry in _entries) {
        if (results.length >= limit) break;
        if (seen.contains(entry.folder.id)) continue;
        if (excludeIds.contains(entry.folder.id)) continue;
        if (entry.normalizedName.contains(normalized)) {
          seen.add(entry.folder.id);
          results.add(entry.folder);
        }
      }
    }

    return results;
  }

  int _lowerBound(String target) {
    int lo = 0;
    int hi = _entries.length;
    while (lo < hi) {
      final mid = lo + (hi - lo) ~/ 2;
      if (_entries[mid].normalizedName.compareTo(target) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void dispose() {
    _invalidationSub?.cancel();
  }
}

class _IndexedEntry {
  final model.Folder folder;
  final String normalizedName;

  const _IndexedEntry({required this.folder, required this.normalizedName});
}
