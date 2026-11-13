import '../database/database.dart';
import '../database/daos/note_dao.dart';
import '../database/daos/shared_row_dao.dart' show SharedRowException;
import '../repositories/note_repository.dart';
import '../models/item_label.dart';
import '../models/movable_item.dart';
import '../models/note_metadata.dart';
import '../utils/compression_utils.dart';
import '../constants/app_constants.dart';
import 'duplicate_name_exception.dart';

/// The orderings the browser offers for a folder's notes.
///
/// **Append only.** A folder persists its choice as the member's `name` in
/// `folders.noteSortOrder`, and an older build that meets a name it does not
/// know falls back to the default rather than failing — so a member may be
/// added to the end, but never renamed, reordered or removed.
enum NotesSortOrder {
  updatedDesc,
  updatedAsc,
  createdDesc,
  createdAsc,
  titleAsc,
  titleDesc,
  positionAsc,
  positionDesc,

  /// Labelled notes first in palette order, unlabelled last. There is no
  /// descending twin — reversing a palette answers no question.
  labelAsc,
}

/// A note was to be filed into a folder that is missing or deleted
/// ([NoteStorageService.copyToMine]): refused before anything is written,
/// where a create would have stored a note no folder shows.
final class FolderGoneException implements Exception {
  final String folderId;

  const FolderGoneException(this.folderId);

  @override
  String toString() => 'FolderGoneException: $folderId is gone';
}

class NoteStorageService {
  static const int defaultPageSize = AppConstants.defaultPageSize;

  final NoteRepository _repository;
  bool _isInitialized = false;

  NoteStorageService({required NoteRepository repository})
    : _repository = repository;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
  }

  /// [ownOnly] leaves out the notes the partner shares — Recent, which is
  /// "what I worked on" (share surfaces D17); All notes and search keep
  /// them, flagged [NoteMetadata.fromPartner]. A database that holds no
  /// shared row reads exactly what it read without it.
  Future<PaginatedNotes> loadNotesPaginated({
    String? folderId,
    int page = 1,
    int pageSize = defaultPageSize,
    NotesSortOrder sortOrder = NotesSortOrder.updatedDesc,
    bool ownOnly = false,
  }) async {
    await initialize();

    final shares = await _shares();
    final notOwnedBy = ownOnly ? shares.owner : null;
    final totalCount = await _repository.getNoteCount(
      folderId,
      notOwnedBy: notOwnedBy,
    );
    final totalPages = (totalCount / pageSize).ceil().clamp(
      1,
      double.maxFinite.toInt(),
    );
    final offset = (page - 1) * pageSize;

    final (sortField, ascending) = _mapSortOrder(sortOrder);

    final notes = await _repository.getNotesPaginated(
      folderId: folderId,
      limit: pageSize,
      offset: offset,
      sortField: sortField,
      ascending: ascending,
      notOwnedBy: notOwnedBy,
    );

    final metadata = [for (final note in notes) metadataOf(note, shares)];

    return PaginatedNotes(
      notes: metadata,
      currentPage: page,
      totalPages: totalPages,
      totalCount: totalCount,
      hasMore: page < totalPages,
    );
  }

  Future<List<NoteMetadata>> loadAllMetadataForFolder(String folderId) async {
    await initialize();
    final notes = await _repository.getNotesByFolder(folderId);
    return _toMetadataList(notes);
  }

  /// How many live notes a folder holds, or — with a null [folderId] — how
  /// many the whole database holds. The null case is what the root browser's
  /// "All notes" row counts, and it is the same statement the paginated load
  /// already issues for its total, not a new one.
  Future<int> getNoteCount(String? folderId) async {
    await initialize();
    return _repository.getNoteCount(folderId);
  }

  /// The note's metadata alone, freshly read — the folder it lives in now,
  /// its stored title and timestamps. The editor's own menu needs those for
  /// a move or an export, and it must not pay for the content to get them.
  ///
  /// A tombstone reads as null: `getNoteById` does not filter `is_deleted`,
  /// so an editor still mounted over a note deleted elsewhere would otherwise
  /// be handed a live-looking row — its menu rows (label, move, export) have
  /// to say "note not found" rather than open on a write the DAO refuses
  /// silently, and the search index's stale-note refresh has to drop it.
  Future<NoteMetadata?> getNoteMetadata(String noteId) async {
    await initialize();
    final note = await _repository.getNoteById(noteId, forceRefresh: true);
    if (note == null || note.isDeleted) return null;
    return _toMetadata(note);
  }

  Future<LazyNote?> loadNoteWithContent(String noteId) async {
    await initialize();

    final note = await _repository.getNoteById(noteId);
    if (note == null) return null;

    final content = await _repository.loadContent(noteId);

    return LazyNote(
      metadata: await _toMetadata(note),
      content: content,
      isContentLoaded: true,
    );
  }

  Future<String> loadNoteContent(String noteId) async {
    await initialize();
    return _repository.loadContent(noteId);
  }

  Future<NoteMetadata> createNote({
    required String folderId,
    required String title,
    required String content,
    ItemLabel label = ItemLabel.none,
  }) async {
    await initialize();

    // Per-folder title uniqueness backstop. Empty titles are exempt so
    // newly-created "Untitled" notes can coexist (the editor saves them
    // empty until the user types a title).
    if (title.trim().isNotEmpty &&
        await noteTitleExistsInFolder(folderId: folderId, title: title)) {
      throw DuplicateNameException(
        kind: DuplicateNameKind.note,
        name: title.trim(),
        parentId: folderId,
      );
    }

    final shouldCompress = CompressionUtils.shouldCompress(content);
    final preview = NoteMetadata.generatePreview(content);

    final note = await _repository.createNote(
      folderId: folderId,
      title: title,
      content: content,
      preview: preview,
      contentLength: content.length,
      isCompressed: shouldCompress,
      label: label,
    );

    return _toMetadata(note);
  }

  /// Service-level entry point for the import pipeline. Performs the same
  /// uniqueness check as [createNote] but routes through
  /// [NoteRepository.importNote] so the originating `createdAt` and
  /// `updatedAt` from the source archive are preserved.
  Future<NoteMetadata> importNote({
    required String folderId,
    required String title,
    required String content,
    required DateTime createdAt,
    required DateTime updatedAt,
    ItemLabel label = ItemLabel.none,
  }) async {
    await initialize();

    if (title.trim().isNotEmpty &&
        await noteTitleExistsInFolder(folderId: folderId, title: title)) {
      throw DuplicateNameException(
        kind: DuplicateNameKind.note,
        name: title.trim(),
        parentId: folderId,
      );
    }

    final shouldCompress = CompressionUtils.shouldCompress(content);
    final preview = NoteMetadata.generatePreview(content);

    final note = await _repository.importNote(
      folderId: folderId,
      title: title,
      content: content,
      preview: preview,
      contentLength: content.length,
      isCompressed: shouldCompress,
      label: label,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    return _toMetadata(note);
  }

  /// Writes a note's title and body. Null means the write was refused — the
  /// note is gone, or it is a tombstone — and the caller has to treat the
  /// text as still unsaved: `OptimizedNoteBloc` turns it into a
  /// [NoteWriteRefusedException] for the editor (record §3.9, M2).
  ///
  /// A save does not change where the note lies, so the answer keeps the
  /// share flags of [current] — the metadata the caller holds — and,
  /// without one, those of the census held now. Only a census dropped since
  /// (a share act, a sync run that touched folders) is read, once: a save
  /// never answers "not shared" for a note that is.
  Future<NoteMetadata?> updateNote({
    required String noteId,
    String? title,
    String? content,
    NoteMetadata? current,
  }) async {
    await initialize();

    final existingNote = await _repository.getNoteById(noteId);
    // Tombstones come back from `getNoteById` too. The DAO refuses to write
    // a tombstone (its row and its body commit together, or neither does),
    // but refusing here first spares an auto-save flushing after a delete
    // the title backstop below and the repository round-trip.
    if (existingNote == null || existingNote.isDeleted) return null;

    // Title-uniqueness backstop. Only run when the title is actually
    // changing to a non-empty value; otherwise saving an unchanged title
    // would needlessly query siblings on every keystroke from the editor.
    if (title != null &&
        title.trim().isNotEmpty &&
        title.trim().toLowerCase() != existingNote.title.trim().toLowerCase()) {
      if (await noteTitleExistsInFolder(
        folderId: existingNote.folderId,
        title: title,
        excludeId: noteId,
      )) {
        throw DuplicateNameException(
          kind: DuplicateNameKind.note,
          name: title.trim(),
          parentId: existingNote.folderId,
        );
      }
    }

    String? newPreview;
    int? newContentLength;
    bool? newIsCompressed;

    // The chunk count is the DAO's, from the chunks it stores the body as.
    if (content != null) {
      newPreview = NoteMetadata.generatePreview(content);
      newContentLength = content.length;
      newIsCompressed = CompressionUtils.shouldCompress(content);
    }

    final updatedNote = await _repository.updateNote(
      id: noteId,
      title: title,
      preview: newPreview,
      contentLength: newContentLength,
      isCompressed: newIsCompressed,
      content: content,
    );

    if (updatedNote == null) return null;
    if (current != null && current.id == noteId) {
      return metadataOf(updatedNote, ShareSnapshot.nothing).copyWith(
        fromPartner: current.fromPartner,
        sharedThroughFolderId: current.sharedThroughFolderId,
      );
    }
    return metadataOf(
      updatedNote,
      _repository.shareCensus.known ?? await _shares(),
    );
  }

  /// Writes one note's colour label. Returns the refreshed metadata, or null
  /// when the note is gone or tombstoned; throws `SharedRowException` for a
  /// partner's.
  Future<NoteMetadata?> setNoteLabel(String noteId, ItemLabel label) async {
    await initialize();
    await ensureOwn([noteId]);
    final note = await _repository.setLabel(noteId: noteId, label: label);
    return note == null ? null : _toMetadata(note);
  }

  /// Labels a whole selection as one unit — one statement, one reload —
  /// rather than one write per picked row. Returns how many rows changed;
  /// throws `SharedRowException`, writing nothing, when one is a partner's.
  Future<int> setLabelForNotes(List<String> noteIds, ItemLabel label) async {
    if (noteIds.isEmpty) return 0;
    await initialize();
    await ensureOwn(noteIds);
    return _repository.setLabelForMany(noteIds: noteIds, label: label);
  }

  /// The colours at least one live note carries, in palette order, so the
  /// search surface can offer a chip per label that exists instead of all
  /// seven.
  ///
  /// [folderIds] is a whole subtree: `null` looks everywhere, an empty set
  /// matches nothing.
  Future<List<ItemLabel>> labelsInUse({Set<String>? folderIds}) async {
    await initialize();
    return _repository.labelsInUse(folderIds: folderIds);
  }

  /// The notes wearing one of [labels], newest first and capped at [limit],
  /// together with how many there are in all.
  ///
  /// This is what a colour filter with nothing typed lists. It reads the
  /// colour out of SQLite rather than out of a page held in memory, so the
  /// cap counts rows the user will actually see and a labelled note older
  /// than the cap's worth of newer ones is still found.
  ///
  /// [folderIds] is a whole subtree, as everywhere else; an empty [labels] is
  /// a programming error, since no colour is the absence of this question
  /// rather than a version of it.
  Future<LabelledNotes> labelledNotes({
    required Set<ItemLabel> labels,
    Set<String>? folderIds,
    required int limit,
  }) async {
    await initialize();
    if (labels.isEmpty) return LabelledNotes.empty;

    final notes = await _repository.labelledNotes(
      labels: labels,
      folderIds: folderIds,
      limit: limit,
    );
    final total = await _repository.countLabelledNotes(
      labels: labels,
      folderIds: folderIds,
    );

    return LabelledNotes(notes: await _toMetadataList(notes), total: total);
  }

  /// Throws `SharedRowException` for a partner's note.
  Future<void> deleteNote(String noteId) async {
    await initialize();
    await ensureOwn([noteId]);
    await _repository.deleteNote(noteId);
  }

  /// Returns true if a non-deleted note titled [title] (case-insensitive,
  /// trimmed) already exists inside [folderId]. Empty / whitespace-only
  /// titles are never reported as duplicates so that "Untitled" notes can
  /// coexist freely. [excludeId] is honored for rename flows.
  ///
  /// Backed by the `idx_notes_folder_ltitle` expression index, so this is
  /// an O(log n) lookup regardless of sibling count.
  Future<bool> noteTitleExistsInFolder({
    required String folderId,
    required String title,
    String? excludeId,
  }) async {
    await initialize();
    return _repository.noteTitleExistsInFolder(
      folderId: folderId,
      title: title,
      excludeId: excludeId,
    );
  }

  /// Resolves the note a `[[title]]` wiki link points at, or null when
  /// nothing matches.
  ///
  /// The match is an **exact** title match — trimmed on both sides and
  /// case-insensitive for ASCII letters, because SQLite's `LOWER` folds no
  /// others (so `Șold` resolves `Șold` but not `șold`). Tombstones are
  /// excluded: a deleted note reads as missing rather than opening a ghost.
  ///
  /// "Trimmed on both sides" is two different trims. The stored title is
  /// trimmed by SQLite's `TRIM`, which strips U+0020 and nothing else; [title]
  /// is trimmed by Dart, which strips all Unicode white space. No write path
  /// trims a title on the way in — [createNote], [importNote] and [updateNote]
  /// store what they are handed, and only the rename dialog trims before
  /// calling — so a note saved as `'Leg Day\t'` keeps its tab and no
  /// `[[Leg Day]]` reaches it. The lenient half is the link on purpose: a
  /// sloppily typed link should still find a cleanly stored title.
  ///
  /// Titles are only unique within a folder, so several notes can answer.
  /// [preferFolderId] wins first — a link written inside a folder means the
  /// neighbour of that name — and within either group the most recently
  /// updated note wins, with the smaller id breaking a tie so the same link
  /// always opens the same note. Recency is only accurate to the second:
  /// Drift stores a `DateTime` as unix seconds, so two namesakes edited
  /// inside the same second tie and fall through to the id rule.
  ///
  /// A link resolves on its own side (share surfaces §6.13): one written in
  /// a note or event of mine among my notes, one in the partner's
  /// ([fromPartner]) among the partner's — a link to a note I was not given
  /// leads nowhere, and a link of mine never opens hers.
  Future<NoteMetadata?> resolveNoteByTitle(
    String title, {
    String? preferFolderId,
    bool fromPartner = false,
  }) async {
    await initialize();
    final found = await _repository.getNotesByTitle(title);
    if (found.isEmpty) return null;
    final shares = await _shares();
    final matches = [
      for (final note in found)
        if (shares.isPartner(note.ownerId) == fromPartner) note,
    ];
    if (matches.isEmpty) return null;

    final preferred = preferFolderId == null
        ? const <Note>[]
        : [
            for (final note in matches)
              if (note.folderId == preferFolderId) note,
          ];
    final pool = preferred.isNotEmpty ? preferred : matches;

    var best = pool.first;
    for (final note in pool.skip(1)) {
      final newer = note.updatedAt.compareTo(best.updatedAt);
      if (newer > 0 || (newer == 0 && note.id.compareTo(best.id) < 0)) {
        best = note;
      }
    }
    return metadataOf(best, shares);
  }

  Future<PaginatedNotes> loadNotePickerPage({
    String query = '',
    int page = 1,
    int pageSize = AppConstants.notePickerPageSize,
  }) async {
    await initialize();

    if (query.isEmpty) {
      return loadNotesPaginated(
        page: page,
        pageSize: pageSize,
        sortOrder: NotesSortOrder.updatedDesc,
      );
    }

    final totalCount = await _repository.searchNotesCount(query);
    final totalPages = (totalCount / pageSize).ceil().clamp(
      1,
      double.maxFinite.toInt(),
    );
    final offset = (page - 1) * pageSize;
    final notes = await _repository.searchNotesPaginated(
      query,
      limit: pageSize,
      offset: offset,
    );

    return PaginatedNotes(
      notes: await _toMetadataList(notes),
      currentPage: page,
      totalPages: totalPages,
      totalCount: totalCount,
      hasMore: page < totalPages,
    );
  }

  Future<List<NoteMetadata>> searchNotes(
    String query, {
    String? folderId,
  }) async {
    await initialize();
    final notes = await _repository.searchNotes(query, folderId: folderId);
    return _toMetadataList(notes);
  }

  /// The share facts held for this database, read once when none are
  /// ([ShareCensus]) — for a reader that maps its own rows through
  /// [metadataOf], such as the search.
  Future<ShareSnapshot> shareSnapshot() => _shares();

  /// Every time the share facts may have changed — a share act, a merge,
  /// the shared reader, a rebind ([ShareCensus.forgotten]).
  Stream<void> get shareFactsChanged => _repository.shareCensus.forgotten;

  /// [note] as the surfaces read it, flagged against [shares]: whether it is
  /// the partner's, and which folder's mark shares it when it is the
  /// person's own.
  NoteMetadata metadataOf(Note note, ShareSnapshot shares) =>
      _repository.noteToMetadata(note, shares);

  Future<ShareSnapshot> _shares() => _repository.shareCensus.read();

  Future<NoteMetadata> _toMetadata(Note note) async =>
      metadataOf(note, await _shares());

  /// [notes] mapped against one read of the census for all.
  Future<List<NoteMetadata>> _toMetadataList(Iterable<Note> notes) async {
    final shares = await _shares();
    return [for (final note in notes) metadataOf(note, shares)];
  }

  /// Throws [SharedRowException] when one of [ids] is a note the partner
  /// shares — before a write the fences would turn into nothing while this
  /// service answered "done", and before an export (share surfaces D19).
  /// Asks the shared rows only when the database holds some, by the owner
  /// the census holds: one keyed statement.
  Future<void> ensureOwn(List<String> ids) async {
    final owner = (await _shares()).owner;
    if (owner == null) return;
    final theirs = await _repository.partnersAmong(ids, owner);
    if (theirs.isNotEmpty) throw SharedRowException('notes', theirs.first);
  }

  /// [ensureOwn] for the folder a note is filed into.
  Future<void> _ensureOwnFolder(String folderId) async {
    final owner = (await _shares()).owner;
    if (owner == null) return;
    final theirs = await _repository.partnersAmongFolders([folderId], owner);
    if (theirs.isNotEmpty) throw SharedRowException('folders', folderId);
  }

  /// "Copy to my notes" (share surfaces §6.13): a new note of the person's
  /// own in [targetFolderId] holding [noteId]'s title and whole text — a
  /// create, never an import: a new id stamped now by this device, no
  /// label, no mark. It follows the source no longer. Any note may be
  /// copied, the person's own too: a copy asks nothing of whose the source
  /// is, and the partner's is the case the editor offers it for.
  ///
  /// Returns the copy, or null when the source is gone — its title and text
  /// read together ([NoteRepository.readWhole]), so a source removed
  /// between them is gone rather than copied empty. Throws, with nothing
  /// written: `SharedRowException` for a [targetFolderId] the partner
  /// shares, [FolderGoneException] for one that is missing or deleted, and
  /// `DuplicateNameException` when the folder holds that title already.
  Future<NoteMetadata?> copyToMine(String noteId, String targetFolderId) async {
    await initialize();
    // Before the title check: a folder of the partner's, or one that is
    // gone, is no place for a note of the person's own, whatever it holds.
    if (!await _repository.isLiveFolder(targetFolderId)) {
      throw FolderGoneException(targetFolderId);
    }
    await _ensureOwnFolder(targetFolderId);
    final source = await _repository.readWhole(noteId);
    if (source == null) return null;
    return createNote(
      folderId: targetFolderId,
      title: source.title,
      content: source.content,
    );
  }

  (NoteSortField, bool) _mapSortOrder(NotesSortOrder sortOrder) {
    switch (sortOrder) {
      case NotesSortOrder.updatedDesc:
        return (NoteSortField.updatedAt, false);
      case NotesSortOrder.updatedAsc:
        return (NoteSortField.updatedAt, true);
      case NotesSortOrder.createdDesc:
        return (NoteSortField.createdAt, false);
      case NotesSortOrder.createdAsc:
        return (NoteSortField.createdAt, true);
      case NotesSortOrder.titleAsc:
        return (NoteSortField.title, true);
      case NotesSortOrder.titleDesc:
        return (NoteSortField.title, false);
      case NotesSortOrder.positionAsc:
        return (NoteSortField.position, true);
      case NotesSortOrder.positionDesc:
        return (NoteSortField.position, false);
      case NotesSortOrder.labelAsc:
        return (NoteSortField.label, true);
    }
  }

  /// One bulk tombstone under one HLC: emptying a folder is one user act.
  /// Throws `SharedRowException` for a folder of the partner's, whose notes
  /// are theirs.
  Future<void> deleteNotesInFolder(String folderId) async {
    await initialize();
    final notes = await _repository.getNotesByFolder(folderId);
    final ids = [for (final note in notes) note.id];
    await ensureOwn(ids);
    await _repository.deleteNotes(ids);
  }

  /// Throws `SharedRowException` for a partner's note or a partner's
  /// [targetFolderId] (`NoteDao.moveNote`). The returned note carries
  /// [NoteMetadata.sharedThroughFolderId] as it landed; the move's own
  /// snackbar reads [moveNotes]' result.
  Future<NoteMetadata?> moveNote({
    required String noteId,
    required String targetFolderId,
  }) async {
    await initialize();
    // Title-uniqueness backstop at the destination folder. Empty titles
    // are exempt to allow "Untitled" notes to be moved freely.
    final existing = await _repository.getNoteById(noteId);
    if (existing != null &&
        existing.folderId != targetFolderId &&
        existing.title.trim().isNotEmpty) {
      if (await noteTitleExistsInFolder(
        folderId: targetFolderId,
        title: existing.title,
        excludeId: noteId,
      )) {
        throw DuplicateNameException(
          kind: DuplicateNameKind.note,
          name: existing.title.trim(),
          parentId: targetFolderId,
        );
      }
    }
    final note = await _repository.moveNote(
      noteId: noteId,
      targetFolderId: targetFolderId,
    );
    if (note != null && existing != null) {
      await _owePokeForMove(await _shares(), {
        noteId: existing.folderId,
      }, targetFolderId);
    }
    return note != null ? _toMetadata(note) : null;
  }

  /// After a move the census says took notes into or out of a shared folder,
  /// the partner's phone is owed a poke for each pair
  /// (`docs/cloud-shared-freshness.md` §7): a note that left a share sends a
  /// document that names no pair. One statement then, none for a move that
  /// changed no note's sharing — an account that never shared pays nothing.
  Future<void> _owePokeForMove(
    ShareSnapshot shares,
    Map<String, String?> moved,
    String targetFolderId,
  ) async {
    final into = shares.sharedThrough(targetFolderId);
    final roots = <String>{};
    for (final source in moved.values) {
      final from = source == null ? null : shares.sharedThrough(source);
      if (from == into) continue;
      roots.addAll([?from, ?into]);
    }
    if (roots.isEmpty) return;
    await _repository.oweSharePokesForFolders(roots);
  }

  /// Moves a whole selection in one transaction. Unlike [moveNote], a title
  /// clash is not thrown: it is one item's outcome among the others, in
  /// [BulkMoveResult.duplicates]. [BulkMoveResult.shareChanges] says which
  /// notes came to lie in a shared folder or left one — read off the census,
  /// which a note's move does not change. Throws `SharedRowException`,
  /// moving nothing, for a partner's note or a partner's [targetFolderId].
  Future<BulkMoveResult> moveNotes({
    required List<String> noteIds,
    required String targetFolderId,
  }) async {
    await initialize();
    final shares = await _shares();
    if (shares.owner != null) {
      await ensureOwn(noteIds);
      // The target too: a note filed into the partner's folder is stopped
      // by the fences, and the move would still count it as moved.
      await _ensureOwnFolder(targetFolderId);
    }
    final result = await _repository.moveNotes(
      noteIds: noteIds,
      targetFolderId: targetFolderId,
    );
    final into = shares.sharedThrough(targetFolderId);
    final changes = <String, MoveShareChange>{
      for (final MapEntry(key: id, value: source) in result.moved.entries)
        id: ?moveShareChange(
          source == null ? null : shares.sharedThrough(source),
          into,
        ),
    };
    if (changes.isEmpty) return result;
    await _owePokeForMove(shares, {
      for (final id in changes.keys) id: result.moved[id],
    }, targetFolderId);
    return result.withShareChanges(changes);
  }

  Stream<NoteChange> get changes => _repository.noteChanges;

  Stream<NoteChange> changesForFolder(String? folderId) =>
      _repository.noteChangesForFolder(folderId);

  Stream<List<NoteMetadata>> watchNotesByFolder(String? folderId) {
    return _repository.watchNotesByFolder(folderId).asyncMap(_toMetadataList);
  }

  void invalidateCache() {
    _repository.invalidateAll();
  }

  void dispose() {}

  /// Tombstones a whole selection in one transaction, so a bulk delete is one
  /// unit of work rather than one per picked row. Throws
  /// `SharedRowException`, deleting nothing, when one is a partner's.
  Future<void> deleteNotes(List<String> noteIds) async {
    await initialize();
    await ensureOwn(noteIds);
    await _repository.deleteNotes(noteIds);
  }

  /// Warms the content cache for rows about to be opened. Exposed here so the
  /// browser page can ask through its bloc instead of reaching into
  /// [NoteRepository] itself.
  void preloadContent(List<String> noteIds) {
    _repository.preloadContent(noteIds);
  }
}
