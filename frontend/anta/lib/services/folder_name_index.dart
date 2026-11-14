import 'dart:async';

import '../models/folder.dart' as model;
import '../models/folder_change.dart';
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
/// [FolderStorageService.changes]) and when the share facts its folders are
/// flagged with may have ([FolderStorageService.shareFactsChanged]): the
/// share pick refuses a folder by its flag.
class FolderNameIndex {
  final FolderStorageService _folderService;

  List<model.Folder> _folders = [];
  // Parallel arrays — _normalized[i] is the normalized name of _folders[i],
  // sorted ascending so we can binary-search.
  List<_IndexedEntry> _entries = [];

  bool _isBuilt = false;
  Future<void>? _buildFuture;

  /// The repository binding ([FolderStorageService.repositoryBindings]) the
  /// published entries were read under: entries of another are dirty at
  /// once, before the rebind's mark-dirty is delivered.
  int _builtBinding = -1;

  /// Bumped by every mark-dirty: a build that read before it neither
  /// publishes nor counts as built.
  int _generation = 0;

  /// What the newest build read, published or not: the answer of a search
  /// whose build and the one after it were both overtaken. Stamped with
  /// the index generation its build began under, so a build finishing late
  /// never puts an older read back, and with the repository binding it was
  /// read under, so it is never served — nor kept — once the repository
  /// reads another database. The database generation cannot stand in: it
  /// moves when a switch begins, before the repository is rebound.
  List<_IndexedEntry> _lastRead = const [];
  int _lastReadBuild = -1;
  int _lastReadBinding = -1;
  StreamSubscription<dynamic>? _invalidationSub;
  StreamSubscription<void>? _shareFactsSub;

  FolderNameIndex({required FolderStorageService folderService})
    : _folderService = folderService {
    // Any folder change invalidates the index lazily — we mark dirty and
    // rebuild on next search rather than on every event. A colour label
    // changes no name, so it is the one event that does not.
    _invalidationSub = _folderService.changes.listen((change) {
      if (change.type != FolderChangeType.labelled) _markDirty();
    });
    // A census forget comes with every own folder write while anything is
    // shared, with every pairing write, and with a database switch;
    // marking dirty is free, and only the next search reads again.
    _shareFactsSub = _folderService.shareFactsChanged.listen(
      (_) => _markDirty(),
    );
  }

  bool get isBuilt => _isBuilt;
  int get folderCount => _folders.length;

  /// Empties the index as well: after a database switch what it holds is
  /// another database's names, which no search may return.
  void _markDirty() {
    if (_lastReadBinding != _folderService.repositoryBindings) {
      _lastRead = const [];
      _lastReadBinding = -1;
    }
    _generation++;
    _isBuilt = false;
    _buildFuture = null;
    _folders = [];
    _entries = [];
  }

  /// Eagerly build the index. Optional — [search] auto-builds.
  Future<void> ensureBuilt() {
    if (_isBuilt && _builtBinding != _folderService.repositoryBindings) {
      _markDirty();
    }
    if (_isBuilt) return Future.value();
    return _buildFuture ??= _build();
  }

  Future<void> _build() async {
    final generation = _generation;
    final binding = _folderService.repositoryBindings;
    final folders = await _folderService.loadAllFolders();
    // Read from a database the repository has left since: neither published
    // nor kept, and the index is dirty now, whenever the rebind's own
    // mark-dirty arrives.
    if (binding != _folderService.repositoryBindings) {
      if (generation == _generation) _markDirty();
      return;
    }
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
    if (generation >= _lastReadBuild) {
      _lastRead = entries;
      _lastReadBuild = generation;
      _lastReadBinding = binding;
    }
    if (generation != _generation) return;

    _folders = folders;
    _entries = entries;
    _builtBinding = binding;
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
    // A build overtaken by a mark-dirty published nothing: read once more.
    // Overtaken again, the search answers from what that build read rather
    // than chase the marks — never from the emptied index, which would say
    // "no folders" for this keystroke. A read of a database the repository
    // has left since is not served: this keystroke answers empty, the next
    // reads.
    if (!_isBuilt) await ensureBuilt();
    // The binding taken here, where the entries are chosen: a rebind can
    // run after `ensureBuilt` returned, before its mark-dirty is delivered.
    final binding = _folderService.repositoryBindings;
    final entries = _isBuilt && _builtBinding == binding
        ? _entries
        : _lastReadBinding == binding
        ? _lastRead
        : const <_IndexedEntry>[];

    final normalized = normalizeForSearch(query.trim());
    if (normalized.isEmpty) return const [];

    final results = <model.Folder>[];
    final seen = <String>{};

    // Prefix matches via binary search.
    final start = _lowerBound(entries, normalized);
    for (int i = start; i < entries.length; i++) {
      final entry = entries[i];
      if (!entry.normalizedName.startsWith(normalized)) break;
      if (excludeIds.contains(entry.folder.id)) continue;
      if (seen.add(entry.folder.id)) {
        results.add(entry.folder);
        if (results.length >= limit) return results;
      }
    }

    // Substring fallback (skip prefix matches we already added).
    if (normalized.length >= 2) {
      for (final entry in entries) {
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

  int _lowerBound(List<_IndexedEntry> entries, String target) {
    int lo = 0;
    int hi = entries.length;
    while (lo < hi) {
      final mid = lo + (hi - lo) ~/ 2;
      if (entries[mid].normalizedName.compareTo(target) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void dispose() {
    _invalidationSub?.cancel();
    _shareFactsSub?.cancel();
  }
}

class _IndexedEntry {
  final model.Folder folder;
  final String normalizedName;

  const _IndexedEntry({required this.folder, required this.normalizedName});
}
