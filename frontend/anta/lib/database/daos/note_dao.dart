import 'package:drift/drift.dart';
import '../../constants/app_constants.dart';
import '../../models/item_label.dart';
import '../../models/note_metadata.dart';
import '../../models/movable_item.dart';
import '../../utils/compression_utils.dart';
import '../../utils/position_plan.dart';
import '../database.dart';
import '../tables/notes_table.dart';
import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../crdt/merge_outcome.dart';
import 'content_chunk_dao.dart';
import 'folder_dao.dart';
import 'sync_dao.dart';

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
      // Labelled notes first, in palette order, unlabelled last — the user
      // sorted by colour to see the coloured ones, so `none` (0) sorts to the
      // bottom rather than to the top its storage value would give it. There
      // is no descending variant (reversing a palette is not a question
      // anyone asks), so `ascending` is deliberately not consulted here.
      case NoteSortField.label:
        query.orderBy([
          (n) => OrderingTerm(expression: _unlabelledLast),
          (n) => OrderingTerm(expression: n.label),
          (n) => OrderingTerm(expression: n.updatedAt, mode: OrderingMode.desc),
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

  /// Creates a note, and writes its body when [content] is given, under one
  /// stamp: a note and its body are one document (D14), so they are one
  /// write and one outbox entry. [ownerId] is for a backup restore, whose
  /// copy keeps the archived ownership under its fresh id (D16). With
  /// [content], [chunkCount] is ignored: the row stores the number of chunks
  /// the body is cut into.
  ///
  /// The body is cut before the transaction, but above 64 K code units its
  /// chunks are still gzip'd on another isolate while the transaction is
  /// open: a new note — like a remote insert — has no stored rows to plan
  /// against before it exists, and a create is one write the user waits on
  /// anyway, not the typing path.
  Future<Note> createNote({
    required String folderId,
    required String title,
    String preview = '',
    int contentLength = 0,
    int chunkCount = 0,
    bool isCompressed = false,
    ItemLabel label = ItemLabel.none,
    String? content,
    String? ownerId,
  }) async {
    final cut = content == null ? null : await BodyCut.of(content);
    return transaction(() async {
      // By name, where every other write of a shared row does nothing: the
      // insert would be skipped, and this would answer with a note that
      // does not exist.
      if (folderId.isNotEmpty) {
        await db.sharedRowDao.ensureOwn('folders', folderId);
      }
      final now = DateTime.now();
      final id = db.generateId();
      final stamp = await db.stampLocal(notes, id);

      // Get the next position for this folder
      final maxPosQuery = selectOnly(notes)..addColumns([notes.position.max()]);
      maxPosQuery.where(notes.folderId.equals(folderId));
      maxPosQuery.where(notes.isDeleted.equals(false));
      final maxPosResult = await maxPosQuery.getSingle();
      final maxPos = maxPosResult.read(notes.position.max());

      final companion = NotesCompanion(
        id: Value(id),
        folderId: Value(folderId),
        title: Value(title),
        preview: Value(preview),
        contentLength: Value(contentLength),
        chunkCount: Value(cut?.length ?? chunkCount),
        isCompressed: Value(isCompressed),
        label: Value(label.storageValue),
        position: Value(nextPosition(maxPos)),
        createdAt: Value(now),
        updatedAt: Value(now),
        ownerId: Value(ownerId),
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: const Value(1),
        isDeleted: const Value(false),
      );

      final note = await insertNote(companion);

      if (cut != null) {
        await db.contentChunkDao.writeChunks(
          noteId: id,
          content: cut.text,
          hlc: stamp.hlc,
          cut: cut,
        );
      }

      return note;
    });
  }

  /// Insert a note while preserving externally-provided audit fields.
  /// Used by the import pipeline so a round-tripped note keeps the
  /// `createdAt` and `updatedAt` it carried in its source archive. Identity
  /// is stamped fresh and the note is queued: an imported note is a new
  /// local row. [content] as in [createNote]. [ownerId] is for a backup
  /// restore, whose copy keeps the archived ownership under its fresh id
  /// (D16).
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
    String? content,
    String? ownerId,
  }) async {
    final cut = content == null ? null : await BodyCut.of(content);
    return transaction(() async {
      // As [createNote]: the insert would be turned into nothing and the
      // read-back below would fail with no word of why.
      if (folderId.isNotEmpty) {
        await db.sharedRowDao.ensureOwn('folders', folderId);
      }
      final id = db.generateId();
      final stamp = await db.stampLocal(notes, id);

      final maxPosQuery = selectOnly(notes)..addColumns([notes.position.max()]);
      maxPosQuery.where(notes.folderId.equals(folderId));
      maxPosQuery.where(notes.isDeleted.equals(false));
      final maxPosResult = await maxPosQuery.getSingle();
      final maxPos = maxPosResult.read(notes.position.max());

      final companion = NotesCompanion(
        id: Value(id),
        folderId: Value(folderId),
        title: Value(title),
        preview: Value(preview),
        contentLength: Value(contentLength),
        chunkCount: Value(cut?.length ?? chunkCount),
        isCompressed: Value(isCompressed),
        label: Value(label.storageValue),
        position: Value(nextPosition(maxPos)),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
        ownerId: Value(ownerId),
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: const Value(1),
        isDeleted: const Value(false),
      );

      final note = await insertNote(companion);
      if (cut != null) {
        await db.contentChunkDao.writeChunks(
          noteId: id,
          content: cut.text,
          hlc: stamp.hlc,
          cut: cut,
        );
      }
      return note;
    });
  }

  /// Writes a note's metadata and, when [content] is given, its body, under
  /// one stamp and one outbox entry — the auto-save path, so a heavy editing
  /// day coalesces to one queued row per note however often it saves. With
  /// [content], [chunkCount] is ignored: the row stores the number of chunks
  /// the body is cut into.
  ///
  /// A save that changes neither the text nor a column is no edit: nothing
  /// is stamped or queued, since a fresh HLC on a row nobody edited would
  /// beat a real edit made elsewhere, and the push would carry the whole
  /// body for nothing. Legacy fixed slices holding the same text are still
  /// re-cut then, under the note's own stamp, and a stale `chunk_count` is
  /// corrected, also unstamped.
  ///
  /// The body is cut — and a legacy note's text read and its chunks encoded
  /// — before the transaction, so it holds only the writes; the transaction
  /// re-reads the rows and redoes that work only if they changed meanwhile.
  /// Two saves of one note fired without awaiting the first could therefore
  /// commit in either order; every caller serialises its saves.
  Future<Note?> updateNote({
    required String id,
    String? title,
    String? preview,
    int? contentLength,
    int? chunkCount,
    bool? isCompressed,
    String? content,
  }) async {
    final prepared = content == null
        ? null
        : await db.contentChunkDao.prepareBody(id, content);
    return transaction(() async {
      final existing = await getNoteById(id);
      if (existing == null) return null;
      // `getNoteById` does not filter tombstones, and an editor's auto-save
      // can flush after the note was deleted from under it. Writing here
      // would stamp the tombstone with a fresh HLC and version and resurrect
      // it on the next merge.
      if (existing.isDeleted) return null;
      // A note another account shares with this one is not saved here, and
      // must say so: an auto-save answered with the old note would read as
      // text that was kept.
      await db.sharedRowDao.ensureOwnRow('notes', id, existing.ownerId);

      final write = prepared == null
          ? null
          : await db.contentChunkDao.planWrite(
              id,
              prepared.cut,
              prepared: prepared,
            );
      final nextChunkCount = write?.chunkCount ?? chunkCount;
      final edited =
          (write?.textChanged ?? false) ||
          (title != null && title != existing.title) ||
          (preview != null && preview != existing.preview) ||
          (contentLength != null && contentLength != existing.contentLength) ||
          (isCompressed != null && isCompressed != existing.isCompressed) ||
          (write == null &&
              chunkCount != null &&
              chunkCount != existing.chunkCount);
      if (!edited) {
        if (write == null) return existing;
        if (!write.plan.isEmpty) {
          await db.contentChunkDao.applyWrite(
            write,
            hlc: existing.hlcTimestamp,
            deviceId: existing.deviceId,
            version: 1,
          );
        }
        if (write.chunkCount == existing.chunkCount) return existing;
        await (update(notes)..where((n) => n.id.equals(id))).write(
          NotesCompanion(chunkCount: Value(write.chunkCount)),
        );
        return getNoteById(id);
      }

      final now = DateTime.now();
      final stamp = await db.stampLocal(notes, id);

      if (write != null) {
        await db.contentChunkDao.applyWrite(
          write,
          hlc: stamp.hlc,
          deviceId: stamp.deviceId,
          version: 1,
        );
      }

      final companion = NotesCompanion(
        title: title != null ? Value(title) : const Value.absent(),
        preview: preview != null ? Value(preview) : const Value.absent(),
        contentLength: contentLength != null
            ? Value(contentLength)
            : const Value.absent(),
        chunkCount: nextChunkCount != null
            ? Value(nextChunkCount)
            : const Value.absent(),
        isCompressed: isCompressed != null
            ? Value(isCompressed)
            : const Value.absent(),
        updatedAt: Value(now),
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: Value(existing.version + 1),
      );

      await (update(notes)..where((n) => n.id.equals(id))).write(companion);

      return getNoteById(id);
    });
  }

  /// A missing or already-tombstoned note writes nothing: a repeat would
  /// churn the version a merge orders by.
  Future<void> softDeleteNote(String id) {
    return transaction(() async {
      final existing = await getNoteById(id);
      if (existing == null || existing.isDeleted) return;
      final stamp = await db.stampLocal(notes, id, op: OutboxOp.tombstone);
      await _tombstone(existing, stamp);
    });
  }

  Future<void> _tombstone(Note existing, CrdtStamp stamp) async {
    final now = DateTime.now();

    await db.contentChunkDao.deleteChunksForNotes([existing.id]);

    await (update(notes)..where((n) => n.id.equals(existing.id))).write(
      NotesCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
        updatedAt: Value(now),
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: Value(existing.version + 1),
      ),
    );
    await db.counterDao.tombstoneValuesOfDeletedNotes(
      stamp,
      now,
      noteId: existing.id,
    );
  }

  Future<void> hardDeleteNote(String id) async {
    await (delete(notes)..where((n) => n.id.equals(id))).go();
  }

  /// Update the position of a note
  Future<Note?> updateNotePosition({
    required String id,
    required int newPosition,
  }) {
    return transaction(() async {
      final existing = await getNoteById(id);
      if (existing == null) return null;

      final now = DateTime.now();
      final stamp = await db.stampLocal(
        notes,
        id,
        op: OutboxOp.forRow(isDeleted: existing.isDeleted),
      );

      await (update(notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(
          position: Value(newPosition),
          updatedAt: Value(now),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
      return getNoteById(id);
    });
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
  Future<Note?> updateNoteLabel({
    required String id,
    required ItemLabel label,
  }) {
    return transaction(() async {
      final existing = await getNoteById(id);
      if (existing == null || existing.isDeleted) return null;
      if (existing.label == label.storageValue) return existing;

      final stamp = await db.stampLocal(notes, id);

      await (update(notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(
          label: Value(label.storageValue),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
      return getNoteById(id);
    });
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

    return transaction(() async {
      final stamp = db.newStamp();
      final changed = await customWriteReturning(
        'UPDATE notes SET label = ?, hlc_timestamp = ?, '
        'device_id = ?, version = version + 1 '
        'WHERE id IN ($placeholders) AND is_deleted = 0 AND label <> ? '
        'RETURNING id',
        variables: [
          Variable<int>(label.storageValue),
          Variable<String>(stamp.hlc),
          Variable<String>(stamp.deviceId),
          for (final id in unique) Variable<String>(id),
          Variable<int>(label.storageValue),
        ],
        updates: {notes},
        updateKind: UpdateKind.update,
      );
      await db.enqueueMany(notes, [
        for (final row in changed) row.read<String>('id'),
      ], stamp.hlc);
      return changed.length;
    });
  }

  /// Every colour a live note actually carries, in palette order.
  ///
  /// One `SELECT DISTINCT` however many notes exist — the search surface's
  /// label chips offer exactly this set, so the query runs on the path that
  /// opens search and must not grow with the library. The folder scope rides
  /// in the same statement as an `IN (…)` rather than being applied over a
  /// page in memory, because the chips have to be right even when the scoped
  /// subtree holds more notes than one page.
  ///
  /// [folderIds] is a whole subtree, the way a search filter's folder set is:
  /// `null` looks everywhere, and an **empty** set matches nothing, which is
  /// what a scope pointing at a folder that has since been deleted must do.
  /// Values this build does not know — a column written by a newer one — are
  /// dropped rather than offered as a chip that could draw nothing.
  Future<List<ItemLabel>> labelsInUse({Set<String>? folderIds}) async {
    if (folderIds != null && folderIds.isEmpty) return const [];

    final variables = <Variable<Object>>[];
    final buffer = StringBuffer(
      'SELECT DISTINCT label FROM notes WHERE is_deleted = 0 AND label != 0',
    );
    if (folderIds != null) {
      final ids = folderIds.toList(growable: false);
      buffer.write(
        ' AND folder_id IN (${List.filled(ids.length, '?').join(', ')})',
      );
      for (final id in ids) {
        variables.add(Variable<String>(id));
      }
    }

    final rows = await customSelect(
      buffer.toString(),
      variables: variables,
      readsFrom: {notes},
    ).get();

    return ItemLabel.inPaletteOrder({
      for (final row in rows) ItemLabel.fromStorage(row.read<int>('label')),
    });
  }

  /// Every live note wearing one of [labels], newest first, capped at [limit].
  ///
  /// The search surface's label-only listing — "everything red", with nothing
  /// typed — reads this rather than filtering a page in memory. Paging the
  /// newest 300 notes and keeping the coloured ones read six rows for every
  /// one it could show, and still missed a red note older than those 300
  /// entirely; the colour belongs in the `WHERE` clause, where the cap can
  /// mean what it says.
  ///
  /// Ordered `updated_at DESC, id` for the reason [getNotesPaginated] gives:
  /// `updated_at` is stored to the second, so without the id tiebreak two
  /// reads need not agree about rows sharing a timestamp.
  ///
  /// [folderIds] is a whole subtree, the way a search filter's folder set is:
  /// `null` looks everywhere, and an **empty** set matches nothing without
  /// issuing a statement at all. An empty [labels] is a programming error —
  /// "no colour" is not a filter this answers, it is the absence of one, and
  /// the caller has a recents list for that.
  Future<List<Note>> labelledNotes({
    required Set<ItemLabel> labels,
    Set<String>? folderIds,
    required int limit,
  }) async {
    assert(labels.isNotEmpty, 'labelledNotes needs at least one colour');
    if (labels.isEmpty) return const [];
    if (folderIds != null && folderIds.isEmpty) return const [];

    final variables = <Variable<Object>>[];
    final buffer = StringBuffer('SELECT * FROM notes WHERE is_deleted = 0');
    _writeLabelledWhere(buffer, variables, labels, folderIds);
    buffer.write(' ORDER BY updated_at DESC, id LIMIT ?');
    variables.add(Variable<int>(limit));

    final rows = await customSelect(
      buffer.toString(),
      variables: variables,
      readsFrom: {notes},
    ).get();
    return [for (final row in rows) notes.map(row.data)];
  }

  /// How many live notes wear one of [labels] — the total the label-only
  /// listing's header counts, which is not the same as how many rows it
  /// shows: the listing is capped and the count is not.
  ///
  /// Same `WHERE` clause as [labelledNotes], and the same rules for
  /// [folderIds] and an empty [labels].
  Future<int> countLabelledNotes({
    required Set<ItemLabel> labels,
    Set<String>? folderIds,
  }) async {
    assert(labels.isNotEmpty, 'countLabelledNotes needs at least one colour');
    if (labels.isEmpty) return 0;
    if (folderIds != null && folderIds.isEmpty) return 0;

    final variables = <Variable<Object>>[];
    final buffer = StringBuffer(
      'SELECT COUNT(*) AS c FROM notes WHERE is_deleted = 0',
    );
    _writeLabelledWhere(buffer, variables, labels, folderIds);

    final row = await customSelect(
      buffer.toString(),
      variables: variables,
      readsFrom: {notes},
    ).getSingle();
    return row.read<int>('c');
  }

  /// The `label IN (…)` and optional `folder_id IN (…)` terms both label
  /// queries share, so the listing and the count it is captioned with can
  /// never disagree about which rows they are about.
  void _writeLabelledWhere(
    StringBuffer buffer,
    List<Variable<Object>> variables,
    Set<ItemLabel> labels,
    Set<String>? folderIds,
  ) {
    final labelValues = labels.toList(growable: false);
    buffer.write(
      ' AND label IN (${List.filled(labelValues.length, '?').join(', ')})',
    );
    for (final label in labelValues) {
      variables.add(Variable<int>(label.storageValue));
    }

    if (folderIds != null) {
      final ids = folderIds.toList(growable: false);
      buffer.write(
        ' AND folder_id IN (${List.filled(ids.length, '?').join(', ')})',
      );
      for (final id in ids) {
        variables.add(Variable<String>(id));
      }
    }
  }

  /// Writes the custom order a drag left in [folderId]'s notes, returning the
  /// ids whose position changed.
  ///
  /// [loadedOrder] is what the page showed, which is often only the first
  /// pages of the folder: the whole group is read and planned in this one
  /// transaction ([spliceLoadedOrder], [planGappedPositions]), so only the
  /// rows the drag actually moved are written — one, for one drag in a
  /// gapped folder — and no write can land between the read and the plan.
  /// [descending] is the folder's custom direction: `positionDesc` reads the
  /// group highest first. Each moved row gets one shared stamp and an outbox
  /// entry; `updated_at` is left alone, since a new place in the list is not
  /// an edit and must not reshuffle a Modified sort.
  Future<List<String>> applyOrder({
    required String folderId,
    required List<String> loadedOrder,
    required bool descending,
    bool windowAtTop = false,
  }) async {
    if (loadedOrder.isEmpty) return const [];

    return transaction(() async {
      final direction = descending ? 'DESC' : 'ASC';
      final rows = await customSelect(
        'SELECT id, position FROM notes '
        'WHERE folder_id = ? AND is_deleted = 0 '
        'ORDER BY position $direction, id',
        variables: [Variable<String>(folderId)],
        readsFrom: {notes},
      ).get();
      final current = <PositionedId>[
        for (final row in rows)
          (id: row.read<String>('id'), position: row.read<int>('position')),
      ];
      final changes = planGappedPositions(
        current: current,
        order: spliceLoadedOrder(
          displayOrder: [for (final row in current) row.id],
          loadedOrder: loadedOrder,
          windowAtTop: windowAtTop,
        ),
        descending: descending,
      );
      if (changes.isEmpty) return const <String>[];

      final stamp = db.newStamp();
      await batch((b) {
        for (final MapEntry(key: id, value: position) in changes.entries) {
          b.update(
            notes,
            NotesCompanion.custom(
              position: Variable<int>(position),
              hlcTimestamp: Variable<String>(stamp.hlc),
              deviceId: Variable<String>(stamp.deviceId),
              version: notes.version + const Constant(1),
            ),
            where: (n) => n.id.equals(id) & n.isDeleted.equals(false),
          );
        }
      });
      final moved = changes.keys.toList(growable: false);
      await db.enqueueMany(notes, moved, stamp.hlc);
      return moved;
    });
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

  Future<List<Note>> getNotesSince(String hlcTimestamp) {
    return (select(
      notes,
    )..where((n) => n.hlcTimestamp.isBiggerThanValue(hlcTimestamp))).get();
  }

  /// The rows under [ids], tombstones included: the sync push sends the
  /// tombstone a delete queued, so it reads past the live-row filter.
  Future<List<Note>> getByIdsIncludingDeleted(List<String> ids) {
    return CrdtMerge.loadInChunks(
      ids,
      (chunk) => (select(notes)..where((n) => n.id.isIn(chunk))).get(),
    );
  }

  /// Merges one remote note document — the row and its whole body, which
  /// travel as one (D14) — on the contract of [CrdtMerge.mergeRemoteRow],
  /// keeping the chunks and the search index in step with whichever side
  /// wins.
  ///
  /// A live remote that is inserted or wins replaces the chunks with
  /// [content], and the row's preview, length, chunk count and compression
  /// flag are derived from that text as `NoteStorageService.createNote`
  /// derives them — never taken from the wire, so they cannot disagree with
  /// the body. A tombstone carries no data: over a local row it writes the
  /// stamps, the deletion and the owner and keeps the data columns; over a
  /// live one it also deletes the chunk rows, as a local delete does (D13).
  ///
  /// When the remote is strictly newer than a live local note whose change
  /// was still unpushed and whose text differs, the outcome carries that row
  /// and its text as the loser, for the engine's conflict copy (D3). Never for
  /// a local row at or below [floor], whichever side is newer: a rebind's
  /// `requeueAll` queued every row, so a pending entry there is no unpushed
  /// change, and a restore-then-rebind would file one copy per note (S3a
  /// review F2).
  ///
  /// Nor for a local row whose stamp is its `note_seen` value, whatever the
  /// outbox says, and its text is then never read: that version is another
  /// device's, accepted from the space, so nothing of it can be lost. The
  /// run that cuts over to the chunked wire queues every live note
  /// (`SyncOutboxDao.requeueBodies`) and reads every one again, so without
  /// this each note another device edited since this one's last pull would
  /// file its already-synced text as a copy. `seen` is recorded at
  /// acceptance, so no writer has to remember it, and a local edit moves
  /// the stamp off it. A row with no `seen` keeps the rule above.
  ///
  /// The other direction is [_keptOver]'s: a remote older than the local
  /// note, live or deleted, may be another device's edit that ours
  /// overwrites everywhere, and its text is then the loser
  /// ([MergeOutcome.loserIncoming]). Every version from another device that
  /// lands here raises `note_seen` to its stamp, which that rule reads.
  ///
  /// A live remote in another folder reports the folder the note left
  /// ([MergeOutcome.moved]), so the browser refreshes that list too.
  ///
  /// The index is `content=notes`, so an entry is removed while the row still
  /// holds the text it was indexed from and added back after the write; a
  /// tombstone has no entry to remove.
  ///
  /// A body this merge wrote rides back on [MergeOutcome.mergedContent]: the
  /// announcement that follows the page must carry what was stored here, not
  /// a re-read a local save landing in between would answer with (R4).
  ///
  /// [inSpace] are the chunk hashes the remote's manifest named, which the
  /// stored chunks never queue: the space holds them (scalability record
  /// S6b). A body that came whole, in a legacy document, names none.
  ///
  /// [ready] is [content] cut and encoded before the caller's transaction
  /// ([ContentChunkDao.encodeBodies]): a pull page's merges then store it
  /// with SQL alone. Taken only for the very text it was made from.
  ///
  /// [localBody] is the local note's text read before the caller's
  /// transaction, with the stamp the row carried then, for the conflict
  /// check above to compare without decompressing the body inside the
  /// transaction. Taken only while the row still carries that stamp: every
  /// write that changes the text moves it, so another stamp means a save
  /// landed in between, and the text is read again here.
  ///
  /// [shared] merges a note another account shares with this one
  /// (`docs/cloud-sharing-foundations.md` §5): the owner's copy wins
  /// whatever the stamps say ([floor] is then [CrdtMerge.everyStamp], under
  /// which no local text is ever the loser), the note is never re-filed —
  /// a re-file is a stamped write of this device's own — and no `note_seen`
  /// is kept for a note this device never writes.
  Future<MergeOutcome> mergeNoteDocument(
    Note remote,
    String? content, {
    String? floor,
    Set<String> inSpace = const {},
    EncodedBody? ready,
    ({String hlc, String text})? localBody,
    bool shared = false,
  }) {
    assert(!shared || floor == CrdtMerge.everyStamp);
    final body = remote.isDeleted ? null : content ?? '';
    final encoded = ready != null && identical(ready.source, body)
        ? ready
        : null;

    // The body is cut only by a merge that stores it: a pull hands every
    // note it reads to this merge — the echo of this device's own push
    // among them — and most are kept or unchanged.
    Future<(Note, BodyCut?)> mergedRow() async {
      if (body == null) return (remote, null);
      final cut = encoded?.cut ?? await BodyCut.of(body);
      return (_withBody(remote, cut), cut);
    }

    return transaction(() async {
      final local = await getNoteById(remote.id);
      final merge = await CrdtMerge.mergeRemoteRow(
        db,
        table: notes,
        rowKey: remote.id,
        remoteHlc: remote.hlcTimestamp,
        localHlc: local?.hlcTimestamp,
        floor: floor,
        insert: () async {
          final (merged, cut) = await mergedRow();
          await into(notes).insert(merged);
          if (cut != null) {
            await _indexMergedBody(merged, cut, inSpace, encoded);
          }
        },
        overwrite: (applied) async {
          var outcome = applied;
          if (!local!.isDeleted) {
            if (applied.localHadPendingPush &&
                remote.hlcTimestamp.compareTo(local.hlcTimestamp) > 0 &&
                (floor == null || local.hlcTimestamp.compareTo(floor) > 0) &&
                await db.syncDao.getValue(SyncDao.keyNoteSeen(local.id)) !=
                    local.hlcTimestamp) {
              final text = localBody?.hlc == local.hlcTimestamp
                  ? localBody!.text
                  : await db.contentChunkDao.loadContent(local.id);
              if (text != (body ?? '')) {
                outcome = MergeOutcome(
                  applied.result,
                  localHadPendingPush: true,
                  loser: local,
                  loserContent: text,
                );
              }
            }
            if (body == null) {
              await db.contentChunkDao.deleteChunksForNotes([remote.id]);
            }
          }
          if (body == null) {
            await (update(notes)..where((n) => n.id.equals(remote.id))).write(
              NotesCompanion(
                hlcTimestamp: Value(remote.hlcTimestamp),
                deviceId: Value(remote.deviceId),
                version: Value(remote.version),
                isDeleted: const Value(true),
                deletedAt: Value(remote.deletedAt),
                updatedAt: CrdtMerge.tombstoneUpdatedAt(remote.deletedAt),
                ownerId: Value(remote.ownerId),
              ),
            );
          } else {
            final (merged, cut) = await mergedRow();
            await update(notes).replace(merged);
            await _indexMergedBody(merged, cut!, inSpace, encoded);
            if (local.folderId != remote.folderId) {
              outcome = outcome.movedFrom(local.folderId);
            }
          }
          return outcome;
        },
      );
      // Before anything that weighs this device's copy: a shared note's is
      // never a side of a conflict, and nothing about it is stamped here.
      if (shared) {
        return body == null ||
                merge.result == MergeResult.keptLocal ||
                merge.result == MergeResult.unchanged
            ? merge
            : merge.withMergedContent(body);
      }
      if (merge.result == MergeResult.keptLocal) {
        return _keptOver(local!, remote, body, floor: floor);
      }
      if ((merge.result == MergeResult.applied ||
              (merge.result == MergeResult.inserted && body != null)) &&
          remote.deviceId != db.deviceId) {
        // Accepted another device's version: whatever this device writes
        // over it later — one note or a bulk write — is made on top of it,
        // so a re-delivery of it is no lost text ([_keptOver]). Not for a
        // tombstone inserted here: the row keeps that foreign stamp, which
        // [_keptOver] reads as seen, and a key per deleted note would never
        // be removed.
        await db.syncDao.raiseValue(
          SyncDao.keyNoteSeen(remote.id),
          remote.hlcTimestamp,
        );
      }
      if (body == null) return merge;
      switch (merge.result) {
        case MergeResult.keptLocal || MergeResult.unchanged:
          return merge;
        case MergeResult.inserted || MergeResult.applied:
          final outcome = merge.withMergedContent(body);
          final refiled = await _refileUnderLiveAncestor(
            remote.id,
            folderId: remote.folderId,
            hlc: remote.hlcTimestamp,
            version: remote.version,
            committed: false,
          );
          if (!refiled || outcome.moved) return outcome;
          return outcome.movedFrom(remote.folderId);
      }
    });
  }

  /// The [MergeResult.keptLocal] of [remote] over the [local] note, with the
  /// remote's [body] as the loser when that text would otherwise be lost
  /// (scalability record S8, D4 A).
  ///
  /// Two devices edit one note offline and the older edit is pushed first:
  /// here the newer local edit keeps it out and is re-queued, and the device
  /// that wrote it takes ours over its own already-pushed row with no
  /// unpushed entry to copy — so this is the one place its text survives.
  /// The same holds for a newer local delete, whose tombstone would take the
  /// remote's edit with it; the comparison of bodies means nothing there, as
  /// the chunks are gone, so the stamp alone decides.
  ///
  /// It is filed once per version: `note_seen` holds the highest stamp of
  /// another device's version this device accepted ([mergeNoteDocument]) or
  /// kept out (here, a tombstone too). So the settled-overlap re-read that
  /// re-delivers a version after our re-push, and a version this device
  /// accepted and then wrote over — one note or a bulk write — file nothing.
  /// A local row still carrying a foreign stamp counts as seen too: a note
  /// accepted before this rule existed has no `note_seen` yet. Our own echo
  /// never files, and nothing changes at or below [floor], whose rule
  /// stands. A third device whose clock runs behind the second's can still
  /// lose text here (D4 B, `baseHlc` on the wire, is that fix).
  ///
  /// Bodies differing only in trailing whitespace are the same text. The
  /// copy takes the remote's title and label and the local row's folder,
  /// which this device holds — the remote's may not have arrived; a deleted
  /// one is resolved to its nearest live ancestor where the copy is filed.
  Future<MergeOutcome> _keptOver(
    Note local,
    Note remote,
    String? body, {
    String? floor,
  }) async {
    const kept = MergeOutcome(MergeResult.keptLocal);
    if (remote.deviceId == db.deviceId) return kept;
    if (floor != null && local.hlcTimestamp.compareTo(floor) <= 0) return kept;
    final key = SyncDao.keyNoteSeen(local.id);
    final stored = await db.syncDao.getValue(key) ?? '';
    final seen =
        local.deviceId != db.deviceId &&
            local.hlcTimestamp.compareTo(stored) > 0
        ? local.hlcTimestamp
        : stored;
    if (remote.hlcTimestamp.compareTo(seen) <= 0) return kept;
    var outcome = kept;
    if (body != null) {
      final lost =
          local.isDeleted ||
          (await db.contentChunkDao.loadContent(local.id)).trimRight() !=
              body.trimRight();
      if (lost) {
        outcome = MergeOutcome(
          MergeResult.keptLocal,
          loser: local.copyWith(title: remote.title, label: remote.label),
          loserContent: body,
          loserIncoming: true,
        );
      }
    }
    if (remote.hlcTimestamp.compareTo(stored) > 0) {
      await db.syncDao.raiseValue(key, remote.hlcTimestamp);
    }
    return outcome;
  }

  /// Re-files every live note whose folder is a tombstone here and that
  /// [_refileUnderLiveAncestor] would have re-filed had it merged now, and
  /// returns each moved note with the folder it left. The engine runs it once
  /// a pull has reached the end of every table it set out to pull.
  ///
  /// The merge-time repair is one chance, taken where the live note arrives,
  /// and two notes never get it: the one this device edited itself after
  /// another deleted its folder — it merges the folder's tombstone, and the
  /// note's own tombstone loses to the edit, so no live note ever arrives —
  /// and one merged while the bind's initial merge was pending, where the
  /// repair stands back (A7 review R130). Both would stay findable only by
  /// search until someone edited them (P review PR5).
  ///
  /// The candidates are read before any transaction opens, so a pull with
  /// nothing to repair costs this one query and writes nothing; they are
  /// read again inside it, where a save that landed in between is seen. The
  /// query excludes everything while the initial merge is pending, as the
  /// repair would.
  Future<List<({String id, String folderId})>>
  refileNotesUnderDeletedFolders() async {
    if ((await _strandedNotes()).isEmpty) return const [];
    return transaction(() async {
      final moved = <({String id, String folderId})>[];
      for (final row in await _strandedNotes()) {
        final id = row.read<String>('id');
        final folderId = row.read<String>('folder_id');
        final refiled = await _refileUnderLiveAncestor(
          id,
          folderId: folderId,
          hlc: row.read<String>('hlc_timestamp'),
          version: row.read<int>('version'),
          committed: true,
        );
        if (refiled) moved.add((id: id, folderId: folderId));
      }
      return moved;
    });
  }

  /// The live notes under a tombstoned folder that [_refileUnderLiveAncestor]'s
  /// rule accepts, as SQL: the folders drive the join, so the notes are
  /// reached through a live-notes index on `folder_id` rather than scanned.
  Future<List<QueryRow>> _strandedNotes() {
    return db
        .customSelect(
          'SELECT n.id, n.folder_id, n.hlc_timestamp, n.version '
          'FROM folders f CROSS JOIN notes n '
          'ON n.folder_id = f.id AND n.is_deleted = 0 '
          'WHERE f.is_deleted = 1 '
          'AND n.hlc_timestamp > f.hlc_timestamp '
          'AND NOT EXISTS (SELECT 1 FROM sync_metadata WHERE key = ?1)',
          variables: [Variable<String>(SyncDao.keyBindMergePending)],
          readsFrom: {db.folders, notes, db.syncMetadata},
        )
        .get();
  }

  /// Re-files the live note [noteId] when its folder [folderId] is a
  /// tombstone here that the note was not deleted with, and returns whether
  /// it did. [hlc] and [version] are the note's as it stands: the merged
  /// remote's at merge time, the stored row's for the sweep ([committed]).
  ///
  /// One device deleted the folder, tombstoning its notes with it; another
  /// edited a note in it at a newer stamp. The edit wins its row, the merge
  /// never cascades (record §3.4), and every live list filters tombstones, so
  /// the note would be live and findable only by search. It takes the
  /// folder's nearest live ancestor, the root (`''`) when every ancestor is a
  /// tombstone — the rules of `FolderDao`'s parent repair (R64): a chain that
  /// runs into a folder this device has not received, or past
  /// [FolderDao.maxFolderDepth], stands, since an unknown folder is not a
  /// deleted one.
  ///
  /// Only a note whose stamp is above the folder tombstone's: an edit made
  /// after the delete, which wins against the cascade's tombstone anyway. A
  /// re-file stamps the note above everything it outranks, so a note stamped
  /// below the delete would be resurrected over its own tombstone (P review
  /// PR1): the deleting device's cascade stamps the folder and every note it
  /// held with one HLC, and its drain sends `folders` before `notes`, so a
  /// listener pulling between two batches meets the folder's tombstone and a
  /// live envelope of a note whose tombstone is still to come.
  ///
  /// Nothing else re-files, because nothing else can tell such a note from a
  /// stranded one (P fix pass PF-H1). "This device wrote the tombstone" was
  /// the other test, and `device_id` is no proof: a rename, a sort or a
  /// position written to a tombstone used to re-stamp it with this device's
  /// id; an old cascade (Dec 2025) left notes live under this device's own
  /// tombstones; two devices can delete one folder; a restore drops a queued
  /// cascade. Each turned a delete into a resurrection on every device.
  ///
  /// Accepted in exchange: a note moved into a folder while another device
  /// deleted it stays under the tombstone, findable by search, until it is
  /// edited or moved. Otherwise the note stands and its tombstone, when one
  /// lands, applies.
  ///
  /// Never while the bind's initial merge is pending, for the folder
  /// repair's reason: the local folders are still the pre-bind ones, and one
  /// whose live envelope is later in the same pull reads here as a tombstone
  /// (A7 review R130).
  ///
  /// Reads the folders table directly, never a repository cache: this runs
  /// inside a transaction that can still roll back (S4a review L11).
  Future<bool> _refileUnderLiveAncestor(
    String noteId, {
    required String folderId,
    required String hlc,
    required int version,
    required bool committed,
  }) async {
    final rows = await db
        .customSelect(
          'WITH RECURSIVE up(id, parent_id, is_deleted, hlc_timestamp, '
          '  depth) AS ('
          '  SELECT id, parent_id, is_deleted, hlc_timestamp, 0 '
          '  FROM folders WHERE id = ?1 '
          '  UNION ALL '
          '  SELECT f.id, f.parent_id, f.is_deleted, f.hlc_timestamp, '
          '  up.depth + 1 '
          '  FROM folders f JOIN up ON f.id = up.parent_id '
          '  WHERE up.depth < ${FolderDao.maxFolderDepth}'
          ') SELECT id, parent_id, is_deleted, hlc_timestamp '
          'FROM up ORDER BY depth',
          variables: [Variable<String>(folderId)],
          readsFrom: {db.folders},
        )
        .get();
    if (rows.isEmpty || rows.first.read<int>('is_deleted') == 0) return false;
    if (hlc.compareTo(rows.first.read<String>('hlc_timestamp')) <= 0) {
      return false;
    }
    String? liveAncestor;
    var reachedRoot = false;
    for (final row in rows) {
      if (row.read<int>('is_deleted') == 0) {
        liveAncestor = row.read<String>('id');
        break;
      }
      reachedRoot = row.read<String?>('parent_id') == null;
    }
    if (liveAncestor == null && !reachedRoot) return false;
    if (await db.syncDao.getValue(SyncDao.keyBindMergePending) != null) {
      return false;
    }
    // Raised to the note first, so the repair outranks the write it repairs
    // and the space converges on it rather than denying the push (R131). A
    // merged remote is raised to with the drift guard kept: the page can
    // still roll back with nothing stored behind the raise (R157). A stored
    // row is adopted, as the puller adopts a committed page (R98): its stamp
    // is already on this database, and a guarded raise could leave the clock
    // below it.
    if (committed) {
      CrdtMerge.advanceClock(db, hlc);
    } else {
      CrdtMerge.advanceClockInTransaction(db, hlc);
    }
    final stamp = await db.stampLocal(notes, noteId);
    await (update(notes)..where((n) => n.id.equals(noteId))).write(
      NotesCompanion(
        folderId: Value(liveAncestor ?? ''),
        updatedAt: Value(DateTime.now()),
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: Value(version + 1),
      ),
    );
    return true;
  }

  /// [note] with the columns that describe its body derived from [body]: the
  /// chunk count is the number of chunks [_indexMergedBody] stores it as.
  Note _withBody(Note note, BodyCut body) {
    return note.copyWith(
      preview: NoteMetadata.generatePreview(body.text),
      contentLength: body.text.length,
      chunkCount: body.length,
      isCompressed: CompressionUtils.shouldCompress(body.text),
    );
  }

  /// Stores [body] as [note]'s chunks. A local tombstone revived here has no
  /// chunk rows to clear: every tombstone path deletes them, and v47 purged
  /// the ones earlier builds kept. [inSpace] names the hashes the manifest
  /// the body came from already holds, so the write queues none of them.
  /// [ready] carries [body]'s chunks encoded ahead of the transaction.
  Future<void> _indexMergedBody(
    Note note,
    BodyCut body,
    Set<String> inSpace,
    EncodedBody? ready,
  ) async {
    await db.contentChunkDao.replaceChunks(
      noteId: note.id,
      content: body.text,
      hlc: note.hlcTimestamp,
      deviceId: note.deviceId,
      version: note.version,
      cut: body,
      inSpace: inSpace,
      ready: ready,
    );
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
      // Neither a shared note nor into a shared folder: the write would be
      // turned into nothing, and the note answered as if it had moved.
      await db.sharedRowDao.ensureOwnRow('notes', id, existing.ownerId);
      await db.sharedRowDao.ensureOwnRow(
        'folders',
        targetFolderId,
        targetFolder.ownerId,
      );

      final now = DateTime.now();
      final stamp = await db.stampLocal(notes, id);

      final maxPosQuery = selectOnly(notes)..addColumns([notes.position.max()]);
      maxPosQuery.where(notes.folderId.equals(targetFolderId));
      maxPosQuery.where(notes.isDeleted.equals(false));
      final maxPosResult = await maxPosQuery.getSingle();
      final maxPos = maxPosResult.read(notes.position.max());

      await (update(notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(
          folderId: Value(targetFolderId),
          position: Value(nextPosition(maxPos)),
          updatedAt: Value(now),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );

      return getNoteById(id);
    });
  }

  /// Moves a whole selection of notes into [targetFolderId] in one
  /// transaction, under one HLC: one user act, a fixed number of statements
  /// however many notes were picked.
  ///
  /// The title rule [noteTitleExistsInFolder] enforces for one note holds per
  /// item here: a note whose title the target already holds, or one an
  /// earlier note of [ids] claims, is reported in
  /// [BulkMoveResult.duplicates] and stays where it is; the rest move. Empty
  /// titles are exempt, as there. Moved notes append after the target's
  /// last position in the order given, as [moveNote] appends one.
  Future<BulkMoveResult> moveNotes(
    List<String> ids,
    String targetFolderId,
  ) async {
    final unique = ids.toSet().toList(growable: false);
    if (unique.isEmpty) return BulkMoveResult.empty;
    final now = DateTime.now();

    return transaction(() async {
      final target = await db.folderDao.getFolderById(targetFolderId);
      if (target == null || target.isDeleted) return BulkMoveResult.empty;

      final found = <String, BulkMoveCandidate>{};
      for (final chunk in bulkMoveChunks(unique)) {
        final rows = await customSelect(
          'SELECT id, folder_id, title, LOWER(TRIM(title)) AS sql_key '
          'FROM notes WHERE id IN (${List.filled(chunk.length, '?').join(', ')}) '
          'AND is_deleted = 0',
          variables: [for (final id in chunk) Variable<String>(id)],
          readsFrom: {notes},
        ).get();
        for (final row in rows) {
          found[row.read<String>('id')] = (
            parentId: row.read<String>('folder_id'),
            name: row.read<String>('title'),
            sqlKey: row.read<String>('sql_key'),
          );
        }
      }
      // The movers' names folded in Dart, looked up the way the single-note
      // check binds its key, so the batch refuses exactly what one move would.
      final keys = {
        for (final row in found.values)
          if (row.parentId != targetFolderId) ?bulkMoveNameKey(row.name),
      }.toList();
      final taken = <String>{};
      for (final chunk in bulkMoveChunks(keys)) {
        final rows = await customSelect(
          'SELECT DISTINCT LOWER(TRIM(title)) AS sql_key FROM notes '
          'WHERE folder_id = ? AND is_deleted = 0 AND LOWER(TRIM(title)) IN '
          '(${List.filled(chunk.length, '?').join(', ')})',
          variables: [
            Variable<String>(targetFolderId),
            for (final key in chunk) Variable<String>(key),
          ],
          readsFrom: {notes},
        ).get();
        taken.addAll([for (final row in rows) row.read<String>('sql_key')]);
      }
      final plan = planBulkMove(
        ids: unique,
        found: found,
        target: targetFolderId,
        taken: taken,
      );
      final moved = plan.moved;
      if (moved.isEmpty) return plan;

      final maxPosQuery = selectOnly(notes)..addColumns([notes.position.max()]);
      maxPosQuery.where(notes.folderId.equals(targetFolderId));
      maxPosQuery.where(notes.isDeleted.equals(false));
      var last = (await maxPosQuery.getSingle()).read(notes.position.max());

      final stamp = db.newStamp();
      await batch((b) {
        for (final id in moved.keys) {
          b.update(
            notes,
            NotesCompanion.custom(
              folderId: Variable<String>(targetFolderId),
              position: Variable<int>(last = nextPosition(last)),
              updatedAt: Variable<DateTime>(now),
              hlcTimestamp: Variable<String>(stamp.hlc),
              deviceId: Variable<String>(stamp.deviceId),
              version: notes.version + const Constant(1),
            ),
            where: (n) => n.id.equals(id),
          );
        }
      });
      await db.enqueueMany(notes, moved.keys, stamp.hlc);
      return plan;
    });
  }

  /// Tombstones a note and deletes its body's chunks: one user act. A missing
  /// or already-tombstoned note writes nothing.
  Future<void> softDeleteNoteWithChunks(String noteId) {
    return transaction(() async {
      final existing = await getNoteById(noteId);
      if (existing == null || existing.isDeleted) return;
      final stamp = await db.stampLocal(notes, noteId, op: OutboxOp.tombstone);
      await _tombstone(existing, stamp);
    });
  }

  /// Tombstones a whole selection in one transaction — the note update, the
  /// chunk deletes (one per id batch), one tombstone of their counter values
  /// — however many notes were picked.
  ///
  /// The per-note path reads each row to write `version + 1`; here SQLite does
  /// that arithmetic itself, the same way [applyOrder] does, so the
  /// statement count does not move with the size of the selection below one
  /// id batch — above it, one `UPDATE` per [AppConstants.sqlIdBatch] ids,
  /// because SQLite binds at most 32,766 variables and "select all" in a
  /// large folder is a real selection. Only the notes still live are
  /// touched: a repeat would churn the version a merge orders by.
  Future<void> softDeleteNotesWithChunks(List<String> noteIds) async {
    if (noteIds.isEmpty) return;
    final ids = noteIds.toSet().toList(growable: false);
    final now = DateTime.now();

    await transaction(() async {
      final stamp = db.newStamp();
      final tombstoned = <String>[];
      for (var i = 0; i < ids.length; i += AppConstants.sqlIdBatch) {
        final end = i + AppConstants.sqlIdBatch;
        final batch = ids.sublist(i, end > ids.length ? ids.length : end);
        final rows = await customWriteReturning(
          'UPDATE notes SET is_deleted = 1, deleted_at = ?, updated_at = ?, '
          'hlc_timestamp = ?, device_id = ?, version = version + 1 '
          'WHERE id IN (${List.filled(batch.length, '?').join(', ')}) '
          'AND is_deleted = 0 RETURNING id',
          variables: [
            Variable<DateTime>(now),
            Variable<DateTime>(now),
            Variable<String>(stamp.hlc),
            Variable<String>(stamp.deviceId),
            for (final id in batch) Variable<String>(id),
          ],
          updates: {notes},
          updateKind: UpdateKind.update,
        );
        tombstoned.addAll([for (final row in rows) row.read<String>('id')]);
      }
      if (tombstoned.isEmpty) return;
      await db.contentChunkDao.deleteChunksForNotes(tombstoned);
      await db.counterDao.tombstoneValuesOfDeletedNotes(stamp, now);
      await db.enqueueMany(
        notes,
        tombstoned,
        stamp.hlc,
        op: OutboxOp.tombstone,
      );
    });
  }
}

enum NoteSortField { title, createdAt, updatedAt, position, label }

/// Sorts unlabelled rows (`label = 0`, [ItemLabel.none]) after labelled ones
/// while leaving the labelled rows in palette order.
///
/// Spelled as raw SQL because it is an *ordering expression*, not a column:
/// no index can supply it, so `NoteSortField.label` sorts in a temp B-tree by
/// design and an index on `(folder_id, label, …)` would buy nothing.
const _unlabelledLast = CustomExpression<int>(
  'CASE WHEN label = 0 THEN 1 ELSE 0 END',
);
