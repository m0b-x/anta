import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/notes_table.dart';
import '../crdt/hlc.dart';

part 'note_dao.g.dart';

@DriftAccessor(tables: [Notes])
class NoteDao extends DatabaseAccessor<AppDatabase> with _$NoteDaoMixin {
  NoteDao(super.db);

  Future<List<Note>> getAllNotes({bool includeDeleted = false}) {
    final query = select(notes);
    if (!includeDeleted) {
      query.where((n) => n.isDeleted.equals(false));
    }
    return query.get();
  }

  Future<List<Note>> getNotesByFolder(
    String? folderId, {
    bool includeDeleted = false,
  }) {
    final query = select(notes);
    if (folderId != null) {
      query.where((n) => n.folderId.equals(folderId));
    }
    if (!includeDeleted) {
      query.where((n) => n.isDeleted.equals(false));
    }
    return query.get();
  }

  Future<Note?> getNoteById(String id) {
    return (select(notes)..where((n) => n.id.equals(id))).getSingleOrNull();
  }

  Future<List<Note>> getNotesByIds(List<String> ids) {
    if (ids.isEmpty) return Future.value([]);
    return (select(
      notes,
    )..where((n) => n.id.isIn(ids) & n.isDeleted.equals(false))).get();
  }

  Future<int> getNoteCount(
    String? folderId, {
    bool includeDeleted = false,
  }) async {
    final countExp = notes.id.count();
    final query = selectOnly(notes)..addColumns([countExp]);

    if (folderId != null) {
      query.where(notes.folderId.equals(folderId));
    }

    if (!includeDeleted) {
      query.where(notes.isDeleted.equals(false));
    }

    final result = await query.getSingle();
    return result.read(countExp) ?? 0;
  }

  /// Get note count across multiple folders (used for cascade delete preview)
  Future<int> getNoteCountInFolders(
    List<String> folderIds, {
    bool includeDeleted = false,
  }) async {
    if (folderIds.isEmpty) return 0;

    final countExp = notes.id.count();
    final query = selectOnly(notes)..addColumns([countExp]);

    query.where(notes.folderId.isIn(folderIds));

    if (!includeDeleted) {
      query.where(notes.isDeleted.equals(false));
    }

    final result = await query.getSingle();
    return result.read(countExp) ?? 0;
  }

  Future<List<Note>> getNotesPaginated({
    String? folderId,
    required int limit,
    required int offset,
    required NoteSortField sortField,
    required bool ascending,
  }) {
    final query = select(notes);

    if (folderId != null) {
      query.where((n) => n.folderId.equals(folderId));
    }
    query.where((n) => n.isDeleted.equals(false));

    final orderMode = ascending ? OrderingMode.asc : OrderingMode.desc;

    switch (sortField) {
      case NoteSortField.title:
        query.orderBy([
          (n) => OrderingTerm(expression: n.title, mode: orderMode),
        ]);
      case NoteSortField.createdAt:
        query.orderBy([
          (n) => OrderingTerm(expression: n.createdAt, mode: orderMode),
        ]);
      case NoteSortField.updatedAt:
        query.orderBy([
          (n) => OrderingTerm(expression: n.updatedAt, mode: orderMode),
        ]);
      case NoteSortField.position:
        query.orderBy([
          (n) => OrderingTerm(expression: n.position, mode: orderMode),
        ]);
    }

    query.limit(limit, offset: offset);
    return query.get();
  }

  Future<Note> insertNote(NotesCompanion note) async {
    await into(notes).insert(note);
    return (select(
      notes,
    )..where((n) => n.id.equals(note.id.value))).getSingle();
  }

  Future<Note> createNote({
    required String folderId,
    required String title,
    String preview = '',
    int contentLength = 0,
    int chunkCount = 0,
    bool isCompressed = false,
  }) async {
    final now = DateTime.now();
    final id = db.generateId();
    final hlc = db.generateHlc();

    // Get the next position for this folder
    final maxPosQuery = selectOnly(notes)..addColumns([notes.position.max()]);
    maxPosQuery.where(notes.folderId.equals(folderId));
    maxPosQuery.where(notes.isDeleted.equals(false));
    final maxPosResult = await maxPosQuery.getSingle();
    final maxPos = maxPosResult.read(notes.position.max()) ?? -1;

    final companion = NotesCompanion(
      id: Value(id),
      folderId: Value(folderId),
      title: Value(title),
      preview: Value(preview),
      contentLength: Value(contentLength),
      chunkCount: Value(chunkCount),
      isCompressed: Value(isCompressed),
      position: Value(maxPos + 1),
      createdAt: Value(now),
      updatedAt: Value(now),
      hlcTimestamp: Value(hlc),
      deviceId: Value(db.deviceId),
      version: const Value(1),
      isDeleted: const Value(false),
    );

    final note = await insertNote(companion);

    // Add to FTS index
    await _addToFtsIndex(id, title, preview);

    return note;
  }

  /// Insert a note while preserving externally-provided audit fields.
  /// Used by the import pipeline so a round-tripped note keeps the
  /// `createdAt` and `updatedAt` it carried in its source archive.
  Future<Note> importNote({
    required String folderId,
    required String title,
    String preview = '',
    int contentLength = 0,
    int chunkCount = 0,
    bool isCompressed = false,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final id = db.generateId();
    final hlc = db.generateHlc();

    final maxPosQuery = selectOnly(notes)..addColumns([notes.position.max()]);
    maxPosQuery.where(notes.folderId.equals(folderId));
    maxPosQuery.where(notes.isDeleted.equals(false));
    final maxPosResult = await maxPosQuery.getSingle();
    final maxPos = maxPosResult.read(notes.position.max()) ?? -1;

    final companion = NotesCompanion(
      id: Value(id),
      folderId: Value(folderId),
      title: Value(title),
      preview: Value(preview),
      contentLength: Value(contentLength),
      chunkCount: Value(chunkCount),
      isCompressed: Value(isCompressed),
      position: Value(maxPos + 1),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      hlcTimestamp: Value(hlc),
      deviceId: Value(db.deviceId),
      version: const Value(1),
      isDeleted: const Value(false),
    );

    final note = await insertNote(companion);
    await _addToFtsIndex(id, title, preview);
    return note;
  }

  Future<Note?> updateNote({
    required String id,
    String? title,
    String? preview,
    int? contentLength,
    int? chunkCount,
    bool? isCompressed,
  }) async {
    final existing = await getNoteById(id);
    if (existing == null) return null;
    // `getNoteById` does not filter tombstones, and an editor's auto-save
    // can flush after the note was deleted from under it. Writing here
    // would stamp the tombstone with a fresh HLC and version and resurrect
    // it on the next merge.
    if (existing.isDeleted) return null;

    final now = DateTime.now();
    final hlc = db.generateHlc();

    final companion = NotesCompanion(
      title: title != null ? Value(title) : const Value.absent(),
      preview: preview != null ? Value(preview) : const Value.absent(),
      contentLength: contentLength != null
          ? Value(contentLength)
          : const Value.absent(),
      chunkCount: chunkCount != null ? Value(chunkCount) : const Value.absent(),
      isCompressed: isCompressed != null
          ? Value(isCompressed)
          : const Value.absent(),
      updatedAt: Value(now),
      hlcTimestamp: Value(hlc),
      deviceId: Value(db.deviceId),
      version: Value(existing.version + 1),
    );

    await (update(notes)..where((n) => n.id.equals(id))).write(companion);

    // Update FTS index with new values
    await _updateFtsIndex(
      id,
      title ?? existing.title,
      preview ?? existing.preview,
    );

    return getNoteById(id);
  }

  /// Add a note to the FTS index
  Future<void> _addToFtsIndex(
    String noteId,
    String title,
    String preview,
  ) async {
    // Get rowid for the note
    final result = await db
        .customSelect(
          'SELECT rowid FROM notes WHERE id = ?',
          variables: [Variable.withString(noteId)],
        )
        .getSingleOrNull();

    if (result != null) {
      final rowid = result.read<int>('rowid');
      await db.customStatement(
        'INSERT INTO notes_fts(rowid, title, preview) VALUES (?, ?, ?)',
        [rowid, title, preview],
      );
    }
  }

  /// Update a note in the FTS index
  Future<void> _updateFtsIndex(
    String noteId,
    String title,
    String preview,
  ) async {
    final result = await db
        .customSelect(
          'SELECT rowid FROM notes WHERE id = ?',
          variables: [Variable.withString(noteId)],
        )
        .getSingleOrNull();

    if (result != null) {
      final rowid = result.read<int>('rowid');
      // FTS5 uses INSERT OR REPLACE semantics with rowid
      await db.customStatement(
        'INSERT OR REPLACE INTO notes_fts(rowid, title, preview) VALUES (?, ?, ?)',
        [rowid, title, preview],
      );
    }
  }

  /// Remove a note from the FTS index
  Future<void> _removeFromFtsIndex(String noteId) async {
    final result = await db
        .customSelect(
          'SELECT rowid FROM notes WHERE id = ?',
          variables: [Variable.withString(noteId)],
        )
        .getSingleOrNull();

    if (result != null) {
      final rowid = result.read<int>('rowid');
      await db.customStatement('DELETE FROM notes_fts WHERE rowid = ?', [
        rowid,
      ]);
    }
  }

  Future<void> softDeleteNote(String id) async {
    final now = DateTime.now();
    final hlc = db.generateHlc();

    final existing = await getNoteById(id);
    if (existing == null) return;

    // Remove from FTS index before soft delete
    await _removeFromFtsIndex(id);

    await (update(notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
        updatedAt: Value(now),
        hlcTimestamp: Value(hlc),
        deviceId: Value(db.deviceId),
        version: Value(existing.version + 1),
      ),
    );
  }

  Future<void> hardDeleteNote(String id) async {
    // Remove from FTS index before hard delete
    await _removeFromFtsIndex(id);
    await (delete(notes)..where((n) => n.id.equals(id))).go();
  }

  /// Update the position of a note
  Future<Note?> updateNotePosition({
    required String id,
    required int newPosition,
  }) async {
    final existing = await getNoteById(id);
    if (existing == null) return null;

    final now = DateTime.now();
    final hlc = db.generateHlc();

    await (update(notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        position: Value(newPosition),
        updatedAt: Value(now),
        hlcTimestamp: Value(hlc),
        deviceId: Value(db.deviceId),
        version: Value(existing.version + 1),
      ),
    );
    return getNoteById(id);
  }

  /// Reorder notes within a folder
  Future<void> reorderNotes({
    required String folderId,
    required List<String> orderedIds,
  }) async {
    final positions = {
      for (var i = 0; i < orderedIds.length; i++) orderedIds[i]: i,
    };
    await setNotePositions(positions);
  }

  /// Write explicit positions for a set of notes. Used by the mixed reorder
  /// service to assign global (folder + note interleaved) positions.
  /// Bumps `version` in SQL rather than reading each row to compute
  /// `version + 1`, which halves the statements a reorder issues (a drag of 50
  /// notes was a SELECT **and** an UPDATE per note). A missing id updates zero
  /// rows, which is the same outcome the previous existence check produced.
  Future<void> setNotePositions(Map<String, int> positionByNoteId) async {
    if (positionByNoteId.isEmpty) return;
    final now = DateTime.now();
    final hlc = db.generateHlc();

    await transaction(() async {
      for (final entry in positionByNoteId.entries) {
        await customUpdate(
          'UPDATE notes SET position = ?, updated_at = ?, hlc_timestamp = ?, '
          'device_id = ?, version = version + 1 WHERE id = ?',
          variables: [
            Variable<int>(entry.value),
            Variable<DateTime>(now),
            Variable<String>(hlc),
            Variable<String>(db.deviceId),
            Variable<String>(entry.key),
          ],
          updates: {notes},
        );
      }
    });
  }

  Future<void> deleteNotesInFolder(String folderId) async {
    final notesInFolder = await getNotesByFolder(folderId);
    for (final note in notesInFolder) {
      await softDeleteNote(note.id);
    }
  }

  /// Returns true if a non-deleted note with the same case-insensitive,
  /// trimmed [title] already exists in [folderId]. Indexed by
  /// `idx_notes_folder_ltitle`. [excludeId] is honored for rename flows
  /// so a note isn't reported as a duplicate of itself. Empty/whitespace
  /// titles are never reported as duplicates so multiple "Untitled" notes
  /// can coexist.
  Future<bool> noteTitleExistsInFolder({
    required String folderId,
    required String title,
    String? excludeId,
  }) async {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    // Empty-string sentinel for excludeId — note ids are non-empty UUIDs,
    // so `id <> ''` is always true. This avoids nullable Variable bindings
    // (List<Variable<Object>> doesn't accept Variable<String?>).
    final result = await db
        .customSelect(
          'SELECT 1 FROM notes '
          'WHERE folder_id = ?1 '
          'AND LOWER(TRIM(title)) = ?2 '
          'AND is_deleted = 0 '
          'AND id <> ?3 '
          'LIMIT 1',
          variables: [
            Variable<String>(folderId),
            Variable<String>(normalized),
            Variable<String>(excludeId ?? ''),
          ],
          readsFrom: {notes},
        )
        .getSingleOrNull();
    return result != null;
  }

  Future<List<Note>> searchNotes(String query, {String? folderId}) async {
    final searchQuery = '%${query.toLowerCase()}%';

    var selectQuery = select(notes);
    selectQuery.where(
      (n) =>
          n.isDeleted.equals(false) &
          (n.title.lower().like(searchQuery) |
              n.preview.lower().like(searchQuery)),
    );

    if (folderId != null) {
      selectQuery.where((n) => n.folderId.equals(folderId));
    }

    selectQuery.orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);

    return selectQuery.get();
  }

  Future<List<Note>> fullTextSearch(
    String query, {
    String? folderId,
    int limit = 50,
  }) async {
    final results = await db
        .customSelect(
          '''
      SELECT notes.* FROM notes 
      INNER JOIN notes_fts ON notes.rowid = notes_fts.rowid 
      WHERE notes_fts MATCH ? AND notes.is_deleted = 0
      ${folderId != null ? 'AND notes.folder_id = ?' : ''}
      ORDER BY rank
      LIMIT ?
      ''',
          variables: [
            Variable.withString(query),
            if (folderId != null) Variable.withString(folderId),
            Variable.withInt(limit),
          ],
          readsFrom: {notes},
        )
        .get();

    return results
        .map(
          (row) => Note(
            id: row.read<String>('id'),
            folderId: row.read<String>('folder_id'),
            title: row.read<String>('title'),
            preview: row.read<String>('preview'),
            contentLength: row.read<int>('content_length'),
            chunkCount: row.read<int>('chunk_count'),
            isCompressed: row.read<bool>('is_compressed'),
            createdAt: row.read<DateTime>('created_at'),
            updatedAt: row.read<DateTime>('updated_at'),
            hlcTimestamp: row.read<String>('hlc_timestamp'),
            deviceId: row.read<String>('device_id'),
            version: row.read<int>('version'),
            isDeleted: row.read<bool>('is_deleted'),
            deletedAt: row.readNullable<DateTime>('deleted_at'),
            position: row.read<int>('position'),
          ),
        )
        .toList();
  }

  Future<List<Note>> getNotesSince(String hlcTimestamp) {
    return (select(
      notes,
    )..where((n) => n.hlcTimestamp.isBiggerThanValue(hlcTimestamp))).get();
  }

  Future<void> mergeNote(Note remote) async {
    final local = await getNoteById(remote.id);

    if (local == null) {
      await into(notes).insert(
        NotesCompanion(
          id: Value(remote.id),
          folderId: Value(remote.folderId),
          title: Value(remote.title),
          preview: Value(remote.preview),
          contentLength: Value(remote.contentLength),
          chunkCount: Value(remote.chunkCount),
          isCompressed: Value(remote.isCompressed),
          createdAt: Value(remote.createdAt),
          updatedAt: Value(remote.updatedAt),
          hlcTimestamp: Value(remote.hlcTimestamp),
          deviceId: Value(remote.deviceId),
          version: Value(remote.version),
          isDeleted: Value(remote.isDeleted),
          deletedAt: Value(remote.deletedAt),
        ),
      );
      return;
    }

    final localHlc = HlcTimestamp.parse(local.hlcTimestamp);
    final remoteHlc = HlcTimestamp.parse(remote.hlcTimestamp);

    if (remoteHlc > localHlc) {
      await (update(notes)..where((n) => n.id.equals(remote.id))).write(
        NotesCompanion(
          folderId: Value(remote.folderId),
          title: Value(remote.title),
          preview: Value(remote.preview),
          contentLength: Value(remote.contentLength),
          chunkCount: Value(remote.chunkCount),
          isCompressed: Value(remote.isCompressed),
          updatedAt: Value(remote.updatedAt),
          hlcTimestamp: Value(remote.hlcTimestamp),
          deviceId: Value(remote.deviceId),
          version: Value(remote.version),
          isDeleted: Value(remote.isDeleted),
          deletedAt: Value(remote.deletedAt),
        ),
      );
      db.hlc.update(remoteHlc);
    }
  }

  Future<int> searchNotesCount(String query, {String? folderId}) async {
    final searchQuery = '%${query.toLowerCase()}%';
    final countExp = notes.id.count();
    final q = selectOnly(notes)..addColumns([countExp]);
    q.where(notes.isDeleted.equals(false));
    q.where(
      notes.title.lower().like(searchQuery) |
          notes.preview.lower().like(searchQuery),
    );
    if (folderId != null) {
      q.where(notes.folderId.equals(folderId));
    }
    final result = await q.getSingle();
    return result.read(countExp) ?? 0;
  }

  Future<List<Note>> searchNotesPaginated(
    String query, {
    String? folderId,
    required int limit,
    required int offset,
  }) {
    final searchQuery = '%${query.toLowerCase()}%';
    final q = select(notes);
    q.where(
      (n) =>
          n.isDeleted.equals(false) &
          (n.title.lower().like(searchQuery) |
              n.preview.lower().like(searchQuery)),
    );
    if (folderId != null) {
      q.where((n) => n.folderId.equals(folderId));
    }
    q.orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);
    q.limit(limit, offset: offset);
    return q.get();
  }

  Stream<List<Note>> watchNotesByFolder(String? folderId) {
    final query = select(notes);
    if (folderId != null) {
      query.where((n) => n.folderId.equals(folderId));
    }
    query.where((n) => n.isDeleted.equals(false));
    query.orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);
    return query.watch();
  }

  Stream<Note?> watchNoteById(String id) {
    return (select(notes)..where((n) => n.id.equals(id))).watchSingleOrNull();
  }

  Future<Note?> moveNote({
    required String id,
    required String targetFolderId,
  }) async {
    return transaction(() async {
      final existing = await getNoteById(id);
      if (existing == null || existing.isDeleted) return null;

      final targetFolder = await db.folderDao.getFolderById(targetFolderId);
      if (targetFolder == null || targetFolder.isDeleted) return null;

      if (existing.folderId == targetFolderId) return existing;

      final now = DateTime.now();
      final hlc = db.generateHlc();

      final maxPosQuery = selectOnly(notes)..addColumns([notes.position.max()]);
      maxPosQuery.where(notes.folderId.equals(targetFolderId));
      maxPosQuery.where(notes.isDeleted.equals(false));
      final maxPosResult = await maxPosQuery.getSingle();
      final maxPos = maxPosResult.read(notes.position.max()) ?? -1;

      await (update(notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(
          folderId: Value(targetFolderId),
          position: Value(maxPos + 1),
          updatedAt: Value(now),
          hlcTimestamp: Value(hlc),
          deviceId: Value(db.deviceId),
          version: Value(existing.version + 1),
        ),
      );

      return getNoteById(id);
    });
  }

  Future<void> softDeleteNoteWithChunks(String noteId) async {
    await transaction(() async {
      await db.contentChunkDao.softDeleteChunksForNote(noteId);
      await softDeleteNote(noteId);
    });
  }
}

enum NoteSortField { title, createdAt, updatedAt, position }
