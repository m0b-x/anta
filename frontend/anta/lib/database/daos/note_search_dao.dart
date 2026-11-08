import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../constants/search_constants.dart';
import '../../models/item_label.dart';
import '../database.dart';
import '../migrations/database_indexes.dart';

/// A live note the body index has not caught up with: never indexed, or
/// written since with a title or body the index does not hold.
class StaleBodyNote {
  /// The note's rowid, which keys its FTS row and its ledger row.
  final int rowid;
  final String id;
  final String title;

  /// The stamp the note carried when probed; the write is refused if it
  /// carries another by then.
  final String hlc;

  /// What the note costs a page, as stored on the row.
  final int contentLength;

  const StaleBodyNote({
    required this.rowid,
    required this.id,
    required this.title,
    required this.hlc,
    required this.contentLength,
  });
}

/// One note's search projection, tagged with the stamp it was read at so the
/// write can refuse it when the note has moved on since.
class BodyProjection {
  /// The note's rowid, the FTS row the projection replaces.
  final int rowid;

  /// The note's id, checked beside [rowid] so a renumbered rowid can never
  /// receive another note's text.
  final String id;

  /// The stamp the title and body were read at.
  final String hlc;

  /// `searchProjection` of the title and body: the `body` column.
  final String text;

  /// `titleProjection` of the title: the `title` column.
  final String title;

  /// `tagProjection` of the body: the `tags` column.
  final String tags;

  /// The note's chunks could not be decoded, so [text] holds its title
  /// alone. Its ledger is settled with a mark no fingerprint equals, so the
  /// next stamp the note carries — a repair is a write or a merge — has it
  /// read again rather than touched.
  final bool bodyUnreadable;

  const BodyProjection({
    required this.rowid,
    required this.id,
    required this.hlc,
    required this.text,
    required this.title,
    required this.tags,
    this.bodyUnreadable = false,
  });
}

/// What [NoteSearchDao.probeCapability] learned about the FTS table.
enum BodyIndexCapability {
  /// The table answers a query.
  usable,

  /// The table is missing, or this SQLite cannot use it (no trigram
  /// tokenizer, no FTS5, a plain table holding the name): worth one attempt
  /// to create it, then settled for the database.
  unsupported,

  /// The query failed for another reason — worth asking again later.
  unknown,
}

/// Owns the device-local body index (**v48**, `docs/scalability-roadmap.md`
/// §5.5 S11; its title and tags columns **v50**, S12): `note_body_fts`, a
/// contentless FTS5 trigram table holding one projection per note under the
/// note's rowid, and `note_search_ledger`, which says which stamp each
/// projection was made at.
///
/// Raw SQL over two tables Drift does not model: both are derived from the
/// notes and their chunks, never synced, never backed up as data, and
/// rebuilt from scratch by deleting them. Every write goes through
/// `customUpdate`/`customInsert`, never `customStatement`, so the statement
/// counters the query-count pins rely on see them.
///
/// Staleness is keyed on `notes.hlc_timestamp`, which every title and body
/// write already moves in its own transaction, so no write path carries an
/// indexing hook. The fingerprint tells a body change from a label, move or
/// reorder stamp, which [touchUnchanged] settles without re-projecting.
class NoteSearchDao {
  final AppDatabase _db;

  NoteSearchDao(this._db);

  /// What a note's projection depends on, besides its stamp: the title, and
  /// its live chunks in reading order — each by its content hash, or by its
  /// stamp for a legacy chunk that has none. The order matters: the chunk
  /// planner keeps a moved chunk's stamp, so a body whose blocks were only
  /// swapped keeps every stamp and count, yet joins new words at the seams.
  /// Spelled once so the write and the touch can never disagree about it.
  static const String _fingerprint =
      "n.title || x'1f' || n.content_length || x'1f' || n.chunk_count || "
      "x'1f' || COALESCE((SELECT group_concat("
      "COALESCE(c.content_hash, c.hlc_timestamp), ',' ORDER BY c.chunk_index) "
      'FROM content_chunks c WHERE c.note_id = n.id AND c.is_deleted = 0), '
      "'')";

  /// The ledger fingerprint of a note settled without its body
  /// ([BodyProjection.bodyUnreadable]). No [_fingerprint] equals it — that
  /// one always holds the title's separator.
  static const String _unreadableMark = "'unreadable'";

  /// The ledger rows whose note is gone, tombstoned, or whose rowid now
  /// belongs to another note (a `VACUUM` may renumber a table without an
  /// INTEGER PRIMARY KEY).
  static const String _orphans =
      'SELECT l.note_rowid FROM note_search_ledger l '
      'LEFT JOIN notes n ON n.rowid = l.note_rowid '
      'WHERE n.rowid IS NULL OR n.is_deleted = 1 OR n.id IS NOT l.note_id';

  /// The live notes the index lacks or holds at another stamp.
  static const String _staleWhere =
      'FROM notes n LEFT JOIN note_search_ledger l ON l.note_rowid = n.rowid '
      'WHERE n.is_deleted = 0 AND (l.note_rowid IS NULL '
      'OR l.note_id IS NOT n.id OR l.indexed_hlc IS NOT n.hlc_timestamp)';

  /// Whether the FTS table exists in this shape and this SQLite can query
  /// it. Unsupported where the v48 or v50 step could not create it (no
  /// trigram tokenizer), for a table carried in a `.db` to a SQLite that
  /// cannot read it, and for the v48 one-column table a refused v50 drop
  /// left behind — the probe names the `title` column for that; any other
  /// failure is logged and answered as unknown, so it is asked again.
  Future<BodyIndexCapability> probeCapability() async {
    try {
      await _db
          .customSelect(
            'SELECT rowid FROM note_body_fts WHERE note_body_fts MATCH ? LIMIT 1',
            variables: [const Variable<String>('title : "abc"')],
          )
          .get();
      return BodyIndexCapability.usable;
    } catch (e) {
      final message = e.toString();
      const unsupported = [
        'no such table',
        'no such tokenizer',
        'no such module',
        'unable to use function MATCH',
        'no such column',
      ];
      if (unsupported.any(message.contains)) {
        return BodyIndexCapability.unsupported;
      }
      debugPrint('[NoteSearchDao] body index probe failed: $e');
      return BodyIndexCapability.unknown;
    }
  }

  /// Creates the two tables where they are missing — a database whose v48
  /// or v50 step ran on a SQLite without the trigram tokenizer, opened by
  /// one that has it — and recreates an FTS table of another shape, with an
  /// empty ledger so every note is projected into it again. Swallows a
  /// refusal, as the steps do.
  Future<void> createTables() async {
    var dropped = false;
    if (await _hasOtherShape()) {
      try {
        await _db.customStatement('DROP TABLE note_body_fts');
        dropped = true;
      } catch (e) {
        debugPrint('[NoteSearchDao] body index not dropped: $e');
      }
    }
    await DatabaseIndexes(_db).createBodySearchTables();
    if (dropped) await _db.customStatement('DELETE FROM note_search_ledger');
  }

  /// Whether `note_body_fts` is an FTS5 table without the v50 `tags`
  /// column — the v48 shape. Read from its stored DDL, which needs no
  /// tokenizer, so a table this SQLite cannot open is left as it is.
  Future<bool> _hasOtherShape() async {
    final row = await _db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE name = 'note_body_fts'",
        )
        .getSingleOrNull();
    final ddl = row?.read<String?>('sql')?.toLowerCase();
    return ddl != null && ddl.contains('fts5(') && !ddl.contains('tags');
  }

  /// Whether any live note moved since it was indexed, or any indexed note
  /// is gone — the one statement a search pays when nothing changed.
  Future<bool> hasPendingWork() async {
    final row = await _db
        .customSelect(
          'SELECT EXISTS (SELECT 1 $_staleWhere) '
          'OR EXISTS ($_orphans) AS pending',
        )
        .getSingle();
    return row.read<int>('pending') != 0;
  }

  /// Drops the projections of the [_orphans]. Returns how many it dropped.
  Future<int> removeOrphans() {
    const orphans = _orphans;
    return _db.transaction(() async {
      await _db.customUpdate(
        'DELETE FROM note_body_fts WHERE rowid IN ($orphans)',
      );
      return _db.customUpdate(
        'DELETE FROM note_search_ledger WHERE note_rowid IN ($orphans)',
      );
    });
  }

  /// Advances the ledger of every note whose stamp moved while its title and
  /// body stayed put — a label, a move, a reorder — in one statement and
  /// without reading a body. Returns how many notes it settled.
  Future<int> touchUnchanged() {
    return _db.customUpdate(
      'UPDATE note_search_ledger SET indexed_hlc = '
      '(SELECT n.hlc_timestamp FROM notes n '
      'WHERE n.rowid = note_search_ledger.note_rowid) '
      'WHERE note_rowid IN (SELECT l.note_rowid FROM note_search_ledger l '
      'JOIN notes n ON n.rowid = l.note_rowid '
      'WHERE n.is_deleted = 0 AND n.id = l.note_id '
      'AND l.indexed_hlc IS NOT n.hlc_timestamp '
      'AND l.fingerprint = $_fingerprint)',
    );
  }

  /// Every live note the index lacks or holds at an older stamp, newest
  /// edit first so a backfill makes recent notes searchable soonest. No
  /// bodies: the caller pages these by [StaleBodyNote.contentLength].
  Future<List<StaleBodyNote>> staleNotes() async {
    final rows = await _db
        .customSelect(
          'SELECT n.rowid AS rid, n.id, n.title, n.hlc_timestamp, '
          'n.content_length $_staleWhere '
          'ORDER BY n.updated_at DESC, n.id',
        )
        .get();
    return [
      for (final row in rows)
        StaleBodyNote(
          rowid: row.read<int>('rid'),
          id: row.read<String>('id'),
          title: row.read<String>('title'),
          hlc: row.read<String>('hlc_timestamp'),
          contentLength: row.read<int>('content_length'),
        ),
    ];
  }

  /// Stores [projections] in one transaction, each only while its note still
  /// carries the stamp it was read at: the ledger row is written first by a
  /// compare-and-set on `hlc_timestamp`, and the FTS row is replaced only
  /// when that landed. A note edited during the page keeps its old ledger
  /// and is picked up by the next drain. Returns how many were stored.
  Future<int> writeProjections(List<BodyProjection> projections) {
    if (projections.isEmpty) return Future.value(0);
    return _db.transaction(() async {
      var written = 0;
      for (final projection in projections) {
        final claimed = await _db.customUpdate(
          'INSERT OR REPLACE INTO note_search_ledger '
          '(note_rowid, note_id, indexed_hlc, fingerprint) '
          'SELECT n.rowid, n.id, n.hlc_timestamp, '
          '${projection.bodyUnreadable ? _unreadableMark : _fingerprint} '
          'FROM notes n '
          'WHERE n.rowid = ? AND n.id = ? AND n.hlc_timestamp = ? '
          'AND n.is_deleted = 0',
          variables: [
            Variable<int>(projection.rowid),
            Variable<String>(projection.id),
            Variable<String>(projection.hlc),
          ],
        );
        if (claimed == 0) continue;
        await _db.customUpdate(
          'DELETE FROM note_body_fts WHERE rowid = ?',
          variables: [Variable<int>(projection.rowid)],
        );
        await _db.customInsert(
          'INSERT INTO note_body_fts (rowid, title, body, tags) '
          'VALUES (?, ?, ?, ?)',
          variables: [
            Variable<int>(projection.rowid),
            Variable<String>(projection.title),
            Variable<String>(projection.text),
            Variable<String>(projection.tags),
          ],
        );
        written++;
      }
      return written;
    });
  }

  /// The live notes whose projection matches [match] (an FTS5 expression
  /// over the trigram table), with the folder and colour filters applied in
  /// the same statement. [folderIds] null searches everywhere; [labels]
  /// empty is no colour filter.
  Future<List<Note>> matching(
    String match, {
    Set<String>? folderIds,
    Set<ItemLabel> labels = const {},
  }) {
    return _notes(
      'SELECT n.* FROM note_body_fts f JOIN notes n ON n.rowid = f.rowid '
      'WHERE note_body_fts MATCH ? AND n.is_deleted = 0',
      [Variable<String>(match)],
      folderIds: folderIds,
      labels: labels,
    );
  }

  /// The quick search's hits: the live notes whose projection matches
  /// [match], best first by `bm25()` — weighted per column by
  /// [SearchConstants.quickTitleWeight] and its siblings — then newest
  /// first, then by id, cut to [limit] in the same statement. Each with its
  /// bm25 score (lower is better). The quick search runs it twice, once
  /// with a title-only [match], so its title hits are never cut behind a
  /// body that repeats the word.
  ///
  /// Joined through the ledger by rowid **and** id, so a projection whose
  /// rowid a `VACUUM` gave to another note is never that note's hit: the
  /// quick search reads no body to confirm one.
  Future<List<({Note note, double score})>> quickMatching(
    String match, {
    Set<String>? folderIds,
    Set<ItemLabel> labels = const {},
    required int limit,
  }) async {
    final rows = await _rows(
      'SELECT n.*, bm25(note_body_fts, ${SearchConstants.quickTitleWeight}, '
      '${SearchConstants.quickBodyWeight}, ${SearchConstants.quickTagWeight}) '
      'AS quick_score '
      'FROM note_body_fts f JOIN notes n ON n.rowid = f.rowid '
      'JOIN note_search_ledger l ON l.note_rowid = f.rowid AND l.note_id = n.id '
      'WHERE note_body_fts MATCH ? AND n.is_deleted = 0',
      [Variable<String>(match)],
      folderIds: folderIds,
      labels: labels,
      tail: ' ORDER BY quick_score, n.updated_at DESC, n.id LIMIT ?',
      trailing: [Variable<int>(limit)],
    );
    return [
      for (final row in rows)
        (note: _db.notes.map(row.data), score: row.read<double>('quick_score')),
    ];
  }

  /// Every live note under the same filters as [matching] — the candidate
  /// set when this database has no FTS table to narrow it.
  Future<List<Note>> liveNotes({
    Set<String>? folderIds,
    Set<ItemLabel> labels = const {},
  }) {
    return _notes(
      'SELECT n.* FROM notes n WHERE n.is_deleted = 0',
      const [],
      folderIds: folderIds,
      labels: labels,
    );
  }

  /// Folds the drain's writes back into the main file once a backfill ends,
  /// without waiting on readers: a passive checkpoint never blocks.
  Future<void> checkpoint() async {
    await _db.customSelect('PRAGMA wal_checkpoint(PASSIVE)').get();
  }

  Future<List<Note>> _notes(
    String select,
    List<Variable<Object>> leading, {
    Set<String>? folderIds,
    required Set<ItemLabel> labels,
  }) async {
    final rows = await _rows(
      select,
      leading,
      folderIds: folderIds,
      labels: labels,
    );
    return [for (final row in rows) _db.notes.map(row.data)];
  }

  /// [select] with the folder and colour filters appended, then [tail] and
  /// its [trailing] variables.
  Future<List<QueryRow>> _rows(
    String select,
    List<Variable<Object>> leading, {
    Set<String>? folderIds,
    required Set<ItemLabel> labels,
    String tail = '',
    List<Variable<Object>> trailing = const [],
  }) {
    final buffer = StringBuffer(select);
    final variables = <Variable<Object>>[...leading];
    if (folderIds != null) {
      buffer.write(
        ' AND n.folder_id IN (${List.filled(folderIds.length, '?').join(', ')})',
      );
      variables.addAll([for (final id in folderIds) Variable<String>(id)]);
    }
    if (labels.isNotEmpty) {
      // A stored value outside the palette reads as no colour in Dart
      // (`ItemLabel.fromStorage`), so it filters as no colour here too.
      buffer.write(
        ' AND (CASE WHEN n.label BETWEEN 0 AND ${ItemLabel.values.length - 1} '
        'THEN n.label ELSE ${ItemLabel.none.storageValue} END) '
        'IN (${List.filled(labels.length, '?').join(', ')})',
      );
      variables.addAll([
        for (final label in labels) Variable<int>(label.storageValue),
      ]);
    }
    buffer.write(tail);
    variables.addAll(trailing);
    return _db
        .customSelect(
          buffer.toString(),
          variables: variables,
          readsFrom: {_db.notes},
        )
        .get();
  }
}
