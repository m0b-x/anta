import 'dart:async';
import '../database/database.dart';
import '../database/daos/note_dao.dart';
import '../database/daos/content_chunk_dao.dart';
import '../models/note_metadata.dart';
import '../constants/app_constants.dart';
import '../models/note_change.dart';
import '../utils/lru_cache.dart';

export '../models/note_change.dart';

class NoteRepository {
  final AppDatabase _db;

  late final LruCache<String, Note> _noteCache;
  late final LruCache<String, String> _contentCache;
  final Map<String?, List<Note>> _folderNotesCache = {};
  final Map<String?, int> _countCache = {};

  static const Duration _cacheExpiry = AppConstants.cacheExpiry;

  DateTime? _lastCacheClean;

  /// Stream controller for note changes (reactive updates)
  final _noteChangesController = StreamController<NoteChange>.broadcast();

  /// Stream of all note changes for reactive UI updates
  Stream<NoteChange> get noteChanges => _noteChangesController.stream;

  /// Stream of changes filtered by folder.
  /// For `moved` events, both the source and target folder receive the event
  /// so subscribers on either side can refresh.
  Stream<NoteChange> noteChangesForFolder(String? folderId) {
    return _noteChangesController.stream.where((change) {
      if (change.folderId == folderId) return true;
      if (change.type == NoteChangeType.moved &&
          change.sourceFolderId == folderId) {
        return true;
      }
      return false;
    });
  }

  NoteRepository({required AppDatabase database}) : _db = database {
    _noteCache = LruCache<String, Note>(maxSize: AppConstants.maxNoteCacheSize);
    _contentCache = LruCache<String, String>(
      maxSize: AppConstants.maxContentCacheSize,
    );
  }

  NoteDao get _noteDao => _db.noteDao;
  ContentChunkDao get _chunkDao => _db.contentChunkDao;

  Future<List<Note>> getNotesByIds(List<String> ids) {
    return _noteDao.getNotesByIds(ids);
  }

  Future<Note?> getNoteById(String id, {bool forceRefresh = false}) async {
    _cleanCacheIfNeeded();

    if (!forceRefresh) {
      final cached = _noteCache.get(id);
      if (cached != null) return cached;
    }

    final note = await _noteDao.getNoteById(id);
    if (note != null) {
      _noteCache.put(id, note);
    }
    return note;
  }

  Future<List<Note>> getNotesByFolder(
    String? folderId, {
    bool forceRefresh = false,
  }) async {
    _cleanCacheIfNeeded();

    if (!forceRefresh && _folderNotesCache.containsKey(folderId)) {
      return _folderNotesCache[folderId]!;
    }

    final notes = await _noteDao.getNotesByFolder(folderId);
    _folderNotesCache[folderId] = notes;

    for (final note in notes) {
      _noteCache.put(note.id, note);
    }

    return notes;
  }

  Future<int> getNoteCount(
    String? folderId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _countCache.containsKey(folderId)) {
      return _countCache[folderId]!;
    }

    final count = await _noteDao.getNoteCount(folderId);
    _countCache[folderId] = count;
    return count;
  }

  Future<List<Note>> getNotesPaginated({
    String? folderId,
    required int limit,
    required int offset,
    required NoteSortField sortField,
    required bool ascending,
  }) async {
    final notes = await _noteDao.getNotesPaginated(
      folderId: folderId,
      limit: limit,
      offset: offset,
      sortField: sortField,
      ascending: ascending,
    );

    for (final note in notes) {
      _noteCache.put(note.id, note);
    }

    return notes;
  }

  Future<String> loadContent(String noteId, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _contentCache.get(noteId);
      if (cached != null) return cached;
    }

    final content = await _chunkDao.loadContent(noteId);
    _contentCache.put(noteId, content);

    return content;
  }

  void preloadContent(List<String> noteIds) {
    for (final noteId in noteIds) {
      if (!_contentCache.containsKey(noteId)) {
        _chunkDao.loadContent(noteId).then((content) {
          _contentCache.put(noteId, content);
        });
      }
    }
  }

  bool isContentCached(String noteId) => _contentCache.containsKey(noteId);

  Future<Note> createNote({
    required String folderId,
    required String title,
    required String content,
    required String preview,
    required int contentLength,
    required int chunkCount,
    required bool isCompressed,
  }) async {
    final note = await _noteDao.createNote(
      folderId: folderId,
      title: title,
      preview: preview,
      contentLength: contentLength,
      chunkCount: chunkCount,
      isCompressed: isCompressed,
    );

    await _chunkDao.saveContent(noteId: note.id, content: content);

    _noteCache.put(note.id, note);
    _contentCache.put(note.id, content);
    _invalidateFolderCache(folderId);

    // Emit change event for reactive updates
    _noteChangesController.add(
      NoteChange(
        type: NoteChangeType.created,
        noteId: note.id,
        folderId: folderId,
        note: note,
      ),
    );

    return note;
  }

  /// Repository-level wrapper around [NoteDao.importNote] that mirrors
  /// the cache-and-broadcast bookkeeping done by [createNote]. Kept
  /// distinct so the import path can preserve the originating
  /// timestamps without polluting the normal create surface.
  Future<Note> importNote({
    required String folderId,
    required String title,
    required String content,
    required String preview,
    required int contentLength,
    required int chunkCount,
    required bool isCompressed,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final note = await _noteDao.importNote(
      folderId: folderId,
      title: title,
      preview: preview,
      contentLength: contentLength,
      chunkCount: chunkCount,
      isCompressed: isCompressed,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    await _chunkDao.saveContent(noteId: note.id, content: content);

    _noteCache.put(note.id, note);
    _contentCache.put(note.id, content);
    _invalidateFolderCache(folderId);

    _noteChangesController.add(
      NoteChange(
        type: NoteChangeType.created,
        noteId: note.id,
        folderId: folderId,
        note: note,
      ),
    );

    return note;
  }

  Future<Note?> updateNote({
    required String id,
    String? title,
    String? preview,
    int? contentLength,
    int? chunkCount,
    bool? isCompressed,
    String? content,
  }) async {
    if (content != null) {
      await _chunkDao.saveContent(noteId: id, content: content);
      _contentCache.put(id, content);
    }

    final note = await _noteDao.updateNote(
      id: id,
      title: title,
      preview: preview,
      contentLength: contentLength,
      chunkCount: chunkCount,
      isCompressed: isCompressed,
    );

    if (note != null) {
      _noteCache.put(id, note);
      _invalidateFolderCache(note.folderId);

      // Emit change event for reactive updates
      _noteChangesController.add(
        NoteChange(
          type: NoteChangeType.updated,
          noteId: id,
          folderId: note.folderId,
          note: note,
        ),
      );
    }

    return note;
  }

  Future<void> deleteNote(String noteId) async {
    final note = await getNoteById(noteId);

    await _noteDao.softDeleteNoteWithChunks(noteId);

    _noteCache.remove(noteId);
    _contentCache.remove(noteId);
    if (note != null) {
      _invalidateFolderCache(note.folderId);

      // Emit change event for reactive updates
      _noteChangesController.add(
        NoteChange(
          type: NoteChangeType.deleted,
          noteId: noteId,
          folderId: note.folderId,
        ),
      );
    }
  }

  Future<Note?> moveNote({
    required String noteId,
    required String targetFolderId,
  }) async {
    final existing = await getNoteById(noteId);
    final sourceFolderId = existing?.folderId;

    final note = await _noteDao.moveNote(
      id: noteId,
      targetFolderId: targetFolderId,
    );

    if (note != null) {
      _noteCache.put(noteId, note);
      _invalidateFolderCache(sourceFolderId);
      _invalidateFolderCache(targetFolderId);

      _noteChangesController.add(
        NoteChange(
          type: NoteChangeType.moved,
          noteId: noteId,
          folderId: targetFolderId,
          sourceFolderId: sourceFolderId,
          note: note,
        ),
      );
    }

    return note;
  }

  /// Reorder notes within a folder
  Future<void> reorderNotes({
    required String folderId,
    required List<String> orderedIds,
  }) async {
    await _noteDao.reorderNotes(folderId: folderId, orderedIds: orderedIds);
    _invalidateFolderCache(folderId);

    // Emit change events for all reordered notes
    for (final noteId in orderedIds) {
      final note = await getNoteById(noteId, forceRefresh: true);
      if (note != null) {
        _noteChangesController.add(
          NoteChange(
            type: NoteChangeType.updated,
            noteId: noteId,
            folderId: folderId,
            note: note,
          ),
        );
      }
    }
  }

  /// Write explicit positions for a set of notes. Used by the mixed reorder
  /// service to assign global (folder + note interleaved) positions.
  Future<void> setNotePositions({
    required String folderId,
    required Map<String, int> positionByNoteId,
  }) async {
    if (positionByNoteId.isEmpty) return;
    await _noteDao.setNotePositions(positionByNoteId);
    _invalidateFolderCache(folderId);
    for (final noteId in positionByNoteId.keys) {
      final note = await getNoteById(noteId, forceRefresh: true);
      if (note != null) {
        _noteChangesController.add(
          NoteChange(
            type: NoteChangeType.updated,
            noteId: noteId,
            folderId: folderId,
            note: note,
          ),
        );
      }
    }
  }

  Future<List<Note>> searchNotes(String query, {String? folderId}) async {
    return _noteDao.searchNotes(query, folderId: folderId);
  }

  Future<List<Note>> fullTextSearch(
    String query, {
    String? folderId,
    int limit = 50,
  }) async {
    return _noteDao.fullTextSearch(query, folderId: folderId, limit: limit);
  }

  Future<int> searchNotesCount(String query, {String? folderId}) {
    return _noteDao.searchNotesCount(query, folderId: folderId);
  }

  /// Indexed uniqueness check. Always hits the database (no cache) because
  /// `_folderNotesCache` may be stale relative to a concurrent write, and
  /// the cost is a single indexed `LIMIT 1` lookup.
  Future<bool> noteTitleExistsInFolder({
    required String folderId,
    required String title,
    String? excludeId,
  }) {
    return _noteDao.noteTitleExistsInFolder(
      folderId: folderId,
      title: title,
      excludeId: excludeId,
    );
  }

  Future<List<Note>> searchNotesPaginated(
    String query, {
    String? folderId,
    required int limit,
    required int offset,
  }) {
    return _noteDao.searchNotesPaginated(
      query,
      folderId: folderId,
      limit: limit,
      offset: offset,
    );
  }

  Stream<List<Note>> watchNotesByFolder(String? folderId) {
    return _noteDao.watchNotesByFolder(folderId).map((notes) {
      for (final note in notes) {
        _noteCache.put(note.id, note);
      }
      _folderNotesCache[folderId] = notes;
      return notes;
    });
  }

  Stream<Note?> watchNoteById(String id) {
    return _noteDao.watchNoteById(id).map((note) {
      if (note != null) {
        _noteCache.put(note.id, note);
      }
      return note;
    });
  }

  Future<List<Note>> getNotesSince(String hlcTimestamp) {
    return _noteDao.getNotesSince(hlcTimestamp);
  }

  Future<void> mergeNote(Note remote) async {
    await _noteDao.mergeNote(remote);
    _noteCache.remove(remote.id);
    _invalidateFolderCache(remote.folderId);
  }

  void _invalidateFolderCache(String? folderId) {
    _folderNotesCache.remove(folderId);
    _countCache.remove(folderId);
  }

  void invalidateAll() {
    _noteCache.clear();
    _contentCache.clear();
    _folderNotesCache.clear();
    _countCache.clear();
  }

  void _cleanCacheIfNeeded() {
    final now = DateTime.now();
    if (_lastCacheClean == null ||
        now.difference(_lastCacheClean!) > _cacheExpiry) {
      _folderNotesCache.clear();
      _countCache.clear();
      _lastCacheClean = now;
    }
  }

  NoteMetadata noteToMetadata(Note note) {
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

  /// Dispose resources
  void dispose() {
    _noteChangesController.close();
  }
}
