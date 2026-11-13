import 'dart:async';

import '../database/database.dart';
import '../models/folder.dart' show FolderShare;

/// What the rows of folders and notes are flagged against
/// (`docs/cloud-share-surfaces-roadmap.md` §6.1): whose a row is and which
/// folder's mark shares it, answered from memory for every row of a load.
class ShareSnapshot {
  const ShareSnapshot(this.owner, this._outermost);

  static const ShareSnapshot nothing = ShareSnapshot(null, {});

  /// The account whose shared rows this database holds, or null for none.
  final String? owner;

  /// Every live folder of the person's own that a mark shares, to the
  /// folder carrying the outermost mark at or above it.
  final Map<String, String> _outermost;

  /// No shared row and no mark: every row is private and the person's own.
  bool get isEmpty => owner == null && _outermost.isEmpty;

  /// Whether a row carrying [ownerId] is the partner's.
  bool isPartner(String? ownerId) => owner != null && ownerId == owner;

  /// How the folder [id] of the person's own is shared.
  FolderShare folderShare(String id) => switch (_outermost[id]) {
    null => FolderShare.none,
    final root when root == id => FolderShare.byMark,
    final root => FolderShare.through(root),
  };

  /// The folder whose mark shares a note lying in [folderId], or null.
  String? sharedThrough(String folderId) => _outermost[folderId];
}

/// The share facts of one database, read whole once and then held: a load
/// of folders or notes flags each row from memory instead of asking per
/// row. One per [AppDatabase] — a database switch starts a new one — and
/// reached by both repositories through [of].
///
/// A database that holds no mark and no shared row keeps that answer
/// through every write of the person's own ([forgetIfShared]): no create,
/// rename, move or delete can bring a mark or a partner's row. Only a share
/// act, a merge, the shared reader and a rebind can, and each [forget]s.
class ShareCensus {
  ShareCensus._(this._db);

  static final Expando<ShareCensus> _censuses = Expando('ShareCensus');

  static ShareCensus of(AppDatabase db) => _censuses[db] ??= ShareCensus._(db);

  final AppDatabase _db;
  ShareSnapshot? _known;
  Future<ShareSnapshot>? _reading;

  /// Bumped by [forget], so a read that began before it is handed to its
  /// caller but never kept.
  int _generation = 0;

  /// The snapshot held now, or null before the first read and after a
  /// [forget]: for a caller that must not await, such as a save.
  ShareSnapshot? get known => _known;

  /// The snapshot, read once — one statement — when none is held.
  Future<ShareSnapshot> read() {
    final known = _known;
    if (known != null) return Future.value(known);
    return _reading ??= _load(_generation);
  }

  Future<ShareSnapshot> _load(int generation) async {
    try {
      final census = await _db.folderDao.shareCensus();
      final snapshot = census.owner == null && census.outermost.isEmpty
          ? ShareSnapshot.nothing
          : ShareSnapshot(census.owner, Map.unmodifiable(census.outermost));
      if (generation == _generation) _known = snapshot;
      return snapshot;
    } finally {
      if (generation == _generation) _reading = null;
    }
  }

  /// Told on every [forget]: for a surface that shows a share fact of a row
  /// it holds — the note editor's sign — and re-reads it then. Asynchronous,
  /// so a listener never runs inside the write that forgot.
  final StreamController<void> _forgotten = StreamController<void>.broadcast();

  Stream<void> get forgotten => _forgotten.stream;

  /// Drops what is held: marks or shared rows may have changed.
  void forget() {
    _generation++;
    _known = null;
    _reading = null;
    _forgotten.add(null);
  }

  /// After a write of the person's own folders: a held "nothing shared"
  /// stays true, anything else may name folders that moved or went.
  void forgetIfShared() {
    if (_known?.isEmpty ?? false) return;
    forget();
  }
}
