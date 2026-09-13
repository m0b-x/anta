import 'package:drift/drift.dart';
import '../../models/item_label.dart';
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

    // Every sort ends on `id`. Without it the order of rows sharing a sort
    // key is whatever SQLite happens to produce, and it need not be the same
    // between two `LIMIT/OFFSET` reads — so a note could be served on page 1
    // and again on page 2 (a duplicate `ValueKey` in the list) while another
    // was served on neither. `updated_at` is stored to the second, so a
    // folder filled in one second is entirely made of such ties.
    switch (sortField) {
      case NoteSortField.title:
        query.orderBy([
          (n) => OrderingTerm(expression: n.title, mode: orderMode),
          (n) => OrderingTerm(expression: n.id),
        ]);
      case NoteSortField.createdAt:
        query.orderBy([
          (n) => OrderingTerm(expression: n.createdAt, mode: orderMode),
          (n) => OrderingTerm(expression: n.id),
        ]);
      case NoteSortField.updatedAt:
        query.orderBy([
          (n) => OrderingTerm(expression: n.updatedAt, mode: orderMode),
          (n) => OrderingTerm(expression: n.id),
        ]);
      case NoteSortField.position:
        query.orderBy([
          (n) => OrderingTerm(expression: n.position, mode: orderMode),
          (n) => OrderingTerm(expression: n.id),
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
    ItemLabel label = ItemLabel.none,
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
      label: Value(label.storageValue),
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
    ItemLabel label = ItemLabel.none,
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
      label: Value(label.storageValue),
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

  /// Writes the colour label of one note.
  ///
  /// Shaped on [updateNotePosition] — read the row, stamp a fresh HLC, write
  /// `version + 1` — and refuses a tombstone the way [updateNote] does: a
  /// label picked from a sheet that outlived the note would otherwise
  /// resurrect it on the next merge.
  ///
  /// `updated_at` is deliberately **not** touched, unlike every other write
  /// here: a label says something *about* the note and edits nothing in it,
  /// so labelling an old note must not carry it to the top of the
  /// "last updated" sort or stamp its row "Today". The HLC and version still
  /// move, which is all the merge needs to carry the label across devices.
  ///
  /// Writing the label a note already has is a no-op — no HLC, no version —
  /// so the row does not travel on the next sync for nothing.
  ///
  /// The FTS index is untouched on purpose: it holds title and preview, and a
  /// label is neither.
  Future<Note?> updateNoteLabel({
    required String id,
    required ItemLabel label,
  }) async {
    final existing = await getNoteById(id);
    if (existing == null || existing.isDeleted) return null;
    if (existing.label == label.storageValue) return existing;

    final hlc = db.generateHlc();

    await (update(notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        label: Value(label.storageValue),
        hlcTimestamp: Value(hlc),
        deviceId: Value(db.deviceId),
        version: Value(existing.version + 1),
      ),
    );
    return getNoteById(id);
  }

  /// Labels a whole selection in **one** statement, the way
  /// [softDeleteNotesWithChunks] tombstones one: SQLite does the
  /// `version + 1` arithmetic itself, so the statement count does not move
  /// with the size of the selection.
  ///
  /// Returns how many rows actually changed. Tombstones and rows already
  /// carrying [label] are skipped by the `WHERE` clause rather than by a
  /// pre-read, so a selection that is mostly that colour already costs one
  /// statement and touches only the rows whose colour moves. `updated_at` is
  /// left alone for the reason [updateNoteLabel] gives.
  Future<int> updateLabelForNotes({
    required List<String> ids,
    required ItemLabel label,
  }) async {
    if (ids.isEmpty) return 0;
    final unique = ids.toSet().toList(growable: false);
    final placeholders = List.filled(unique.length, '?').join(', ');
    final hlc = db.generateHlc();

    return customUpdate(
      'UPDATE notes SET label = ?, hlc_timestamp = ?, '
      'device_id = ?, version = version + 1 '
      'WHERE id IN ($placeholders) AND is_deleted = 0 AND label <> ?',
      variables: [
        Variable<int>(label.storageValue),
        Variable<String>(hlc),
        Variable<String>(db.deviceId),
        for (final id in unique) Variable<String>(id),
        Variable<int>(label.storageValue),
      ],
      updates: {notes},
    );
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

  /// Mirrors `Notes.title`'s `withLength(max: 500)` — the cap Drift enforces
  /// in Dart, in UTF-16 code units, on every insert and update, so a longer
  /// title cannot be stored and cannot be matched.
  ///
  /// Duplicated as a literal rather than read off the table because the cap
  /// is not readable at runtime: `withLength` compiles to a verification
  /// closure on the generated column, and recovering the bound would mean
  /// probing that closure with candidate strings. `query_count_test.dart`
  /// holds the two together instead — a 500-unit title still queries, a
  /// 501-unit one does not.
  static const int _maxTitleLength = 500;

  /// Every live note whose trimmed title equals [title], across all folders.
  /// Backs the wiki-link resolver, where `[[note]]` names a note without
  /// saying where it lives. Indexed by `idx_notes_ltitle`.
  ///
  /// Unordered on purpose: an `ORDER BY` would cost a temp B-tree that the
  /// partial expression index cannot supply, and the caller ranks the handful
  /// of rows this returns in Dart.
  ///
  /// The parameter is folded by SQLite's `LOWER`, not Dart's, so both sides of
  /// the comparison fold exactly the same set of letters and a title always
  /// matches its own spelling. SQLite's `LOWER` is ASCII-only, so `Șold` finds
  /// `Șold` but `șold` does not — and that is a property of the SQLite build
  /// `sqlite3_flutter_libs` bundles rather than of SQL. An ICU-enabled build
  /// folds `Ș` to `ș`, and this match would widen without a line of Dart
  /// changing, which is what makes the claim checkable.
  ///
  /// [noteTitleExistsInFolder] lowers its parameter in Dart instead, so the
  /// two **disagree**: a note titled `Șold` is not reported there as a
  /// duplicate of `Șold`, both can therefore exist in one folder, and a
  /// `[[Șold]]` link picks between them by the resolver's recency-then-id
  /// rule. Pre-existing behaviour, deliberately left alone and pinned in
  /// `test/database/note_title_lookup_test.dart`.
  ///
  /// Trimming is asymmetric for a related reason. The stored side is trimmed
  /// by SQLite's `TRIM`, which strips U+0020 and nothing else; the link side
  /// by Dart's `String.trim`, which strips all Unicode white space. No write
  /// path trims a title — [createNote], [importNote] and [updateNote] store
  /// what they are handed, and only the rename dialog trims before calling —
  /// so a stored `'Leg Day\t'` keeps its tab and no `[[Leg Day]]` can reach
  /// it. The lenient side is the *link* on purpose: a sloppily typed link
  /// should still find a cleanly stored title.
  Future<List<Note>> getNotesByTitle(String title) async {
    final normalized = title.trim();
    if (normalized.isEmpty) return const [];
    // Longer than the column can hold, so no stored title can equal it and
    // the round trip is pure cost. A `[[…]]` can carry a whole pasted
    // paragraph, which is how an over-long title reaches this at all.
    if (normalized.length > _maxTitleLength) return const [];

    final rows = await db
        .customSelect(
          'SELECT * FROM notes '
          'WHERE LOWER(TRIM(title)) = LOWER(?1) '
          'AND is_deleted = 0',
          variables: [Variable<String>(normalized)],
          readsFrom: {notes},
        )
        .get();
    return [for (final row in rows) notes.map(row.data)];
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
            label: row.read<int>('label'),
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
          label: Value(remote.label),
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
          label: Value(remote.label),
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
    q.orderBy([
      (n) => OrderingTerm.desc(n.updatedAt),
      (n) => OrderingTerm(expression: n.id),
    ]);
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

  /// Tombstones a whole selection in one transaction: one FTS delete, one
  /// chunk update, one note update, however many notes were picked.
  ///
  /// The per-note path reads each row to write `version + 1`; here SQLite does
  /// that arithmetic itself, the same way [setNotePositions] does, so the
  /// statement count does not move with the size of the selection.
  Future<void> softDeleteNotesWithChunks(List<String> noteIds) async {
    if (noteIds.isEmpty) return;
    final ids = noteIds.toSet().toList(growable: false);
    final placeholders = List.filled(ids.length, '?').join(', ');
    final idVariables = [for (final id in ids) Variable<String>(id)];
    final now = DateTime.now();
    final hlc = db.generateHlc();

    await transaction(() async {
      await db.customStatement(
        'DELETE FROM notes_fts WHERE rowid IN '
        '(SELECT rowid FROM notes WHERE id IN ($placeholders))',
        ids,
      );
      await db.contentChunkDao.softDeleteChunksForNotes(ids);
      await customUpdate(
        'UPDATE notes SET is_deleted = 1, deleted_at = ?, updated_at = ?, '
        'hlc_timestamp = ?, device_id = ?, version = version + 1 '
        'WHERE id IN ($placeholders) AND is_deleted = 0',
        variables: [
          Variable<DateTime>(now),
          Variable<DateTime>(now),
          Variable<String>(hlc),
          Variable<String>(db.deviceId),
          ...idVariables,
        ],
        updates: {notes},
      );
    });
  }
}

enum NoteSortField { title, createdAt, updatedAt, position }
