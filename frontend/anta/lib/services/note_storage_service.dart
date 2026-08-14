import '../database/database.dart';
import '../database/daos/note_dao.dart';
import '../database/daos/content_chunk_dao.dart';
import '../repositories/note_repository.dart';
import '../models/note_metadata.dart';
import '../utils/compression_utils.dart';
import '../constants/app_constants.dart';
import 'duplicate_name_exception.dart';

enum NotesSortOrder {
  updatedDesc,
  updatedAsc,
  createdDesc,
  createdAsc,
  titleAsc,
  titleDesc,
  positionAsc,
  positionDesc,
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

  Future<PaginatedNotes> loadNotesPaginated({
    String? folderId,
    int page = 1,
    int pageSize = defaultPageSize,
    NotesSortOrder sortOrder = NotesSortOrder.updatedDesc,
  }) async {
    await initialize();

    final totalCount = await _repository.getNoteCount(folderId);
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
    );

    final metadata = notes.map(_noteToMetadata).toList();

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
    return notes.map(_noteToMetadata).toList();
  }

  Future<int> getNoteCount(String folderId) async {
    await initialize();
    return _repository.getNoteCount(folderId);
  }

  Future<LazyNote?> loadNoteWithContent(String noteId) async {
    await initialize();

    final note = await _repository.getNoteById(noteId);
    if (note == null) return null;

    final content = await _repository.loadContent(noteId);

    return LazyNote(
      metadata: _noteToMetadata(note),
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
    final chunkCount = (content.length / ContentChunkDao.defaultChunkSize)
        .ceil()
        .clamp(1, double.maxFinite.toInt());

    final note = await _repository.createNote(
      folderId: folderId,
      title: title,
      content: content,
      preview: preview,
      contentLength: content.length,
      chunkCount: chunkCount,
      isCompressed: shouldCompress,
    );

    return _noteToMetadata(note);
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
    final chunkCount = (content.length / ContentChunkDao.defaultChunkSize)
        .ceil()
        .clamp(1, double.maxFinite.toInt());

    final note = await _repository.importNote(
      folderId: folderId,
      title: title,
      content: content,
      preview: preview,
      contentLength: content.length,
      chunkCount: chunkCount,
      isCompressed: shouldCompress,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    return _noteToMetadata(note);
  }

  Future<NoteMetadata?> updateNote({
    required String noteId,
    String? title,
    String? content,
  }) async {
    await initialize();

    final existingNote = await _repository.getNoteById(noteId);
    if (existingNote == null) return null;

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
    int? newChunkCount;
    bool? newIsCompressed;

    if (content != null) {
      newPreview = NoteMetadata.generatePreview(content);
      newContentLength = content.length;
      newChunkCount = (content.length / ContentChunkDao.defaultChunkSize)
          .ceil()
          .clamp(1, double.maxFinite.toInt());
      newIsCompressed = CompressionUtils.shouldCompress(content);
    }

    final updatedNote = await _repository.updateNote(
      id: noteId,
      title: title,
      preview: newPreview,
      contentLength: newContentLength,
      chunkCount: newChunkCount,
      isCompressed: newIsCompressed,
      content: content,
    );

    return updatedNote != null ? _noteToMetadata(updatedNote) : null;
  }

  Future<void> deleteNote(String noteId) async {
    await initialize();
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
      notes: notes.map(_noteToMetadata).toList(),
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
    return notes.map(_noteToMetadata).toList();
  }

  Future<List<NoteMetadata>> fullTextSearch(
    String query, {
    String? folderId,
  }) async {
    await initialize();
    try {
      final notes = await _repository.fullTextSearch(query, folderId: folderId);
      return notes.map(_noteToMetadata).toList();
    } catch (_) {
      return searchNotes(query, folderId: folderId);
    }
  }

  NoteMetadata _noteToMetadata(Note note) {
    return NoteMetadata(
      id: note.id,
      folderId: note.folderId,
      title: note.title,
      preview: note.preview,
      contentLength: note.contentLength,
      chunkCount: note.chunkCount,
      isCompressed: note.isCompressed,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      position: note.position,
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
    }
  }

  Future<void> deleteNotesInFolder(String folderId) async {
    await initialize();
    final notes = await _repository.getNotesByFolder(folderId);
    for (final note in notes) {
      await _repository.deleteNote(note.id);
    }
  }

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
    return note != null ? _noteToMetadata(note) : null;
  }

  Stream<NoteChange> get changes => _repository.noteChanges;

  Stream<NoteChange> changesForFolder(String? folderId) =>
      _repository.noteChangesForFolder(folderId);

  /// Reorder notes within a folder
  Future<void> reorderNotes({
    required String folderId,
    required List<String> orderedIds,
  }) async {
    await initialize();
    await _repository.reorderNotes(folderId: folderId, orderedIds: orderedIds);
  }

  Stream<List<NoteMetadata>> watchNotesByFolder(String? folderId) {
    return _repository
        .watchNotesByFolder(folderId)
        .map((notes) => notes.map(_noteToMetadata).toList());
  }

  void invalidateCache() {
    _repository.invalidateAll();
  }

  void dispose() {}
}
