import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../../constants/app_constants.dart';
import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../database.dart';
import '../tables/content_chunks_table.dart';
import '../chunking/body_cut.dart';
import '../chunking/chunk_hasher.dart';
import '../chunking/chunk_planner.dart';
import '../../utils/compression_utils.dart';

export '../chunking/body_cut.dart' show BodyCut;

part 'content_chunk_dao.g.dart';

@DriftAccessor(tables: [ContentChunks])
class ContentChunkDao extends DatabaseAccessor<AppDatabase>
    with _$ContentChunkDaoMixin {
  /// A chunk longer than this many code units is stored gzip'd and base64'd.
  static const int compressionThreshold = 5000;

  /// How many chunk texts were encoded on this isolate's behalf, so a test
  /// can pin a path that must not encode — inside a pull page's
  /// transaction, above all — as [BodyCut.cutCount] pins the cut.
  @visibleForTesting
  static int encodeCount = 0;

  ContentChunkDao(super.db);

  Future<List<ContentChunk>> getChunksForNote(String noteId) {
    return (select(contentChunks)
          ..where((c) => c.noteId.equals(noteId) & c.isDeleted.equals(false))
          ..orderBy([(c) => OrderingTerm.asc(c.chunkIndex)]))
        .get();
  }

  /// The note's live chunk hashes in body order — its manifest on the wire;
  /// a null is a legacy slice no save has re-cut yet.
  Future<List<String?>> hashesOf(String noteId) async => [
    for (final row in await _liveRows(noteId)) row.chunk.hash,
  ];

  /// One live row per hash in [hashes] — the one stamped last where several
  /// notes hold the same text — for the push of the chunk documents: a hash
  /// no live row holds any more is absent.
  Future<List<ContentChunk>> newestByHashes(List<String> hashes) async {
    final rows = await CrdtMerge.loadInChunks(
      hashes,
      (chunk) =>
          (select(contentChunks)..where(
                (c) =>
                    c.contentHash.isIn(chunk) &
                    const CustomExpression<bool>('is_deleted = 0'),
              ))
              .get(),
    );
    final newest = <String, ContentChunk>{};
    for (final row in rows) {
      final kept = newest[row.contentHash!];
      if (kept == null || row.hlcTimestamp.compareTo(kept.hlcTimestamp) > 0) {
        newest[row.contentHash!] = row;
      }
    }
    return newest.values.toList();
  }

  /// The text of each hash in [hashes] that any live row on this device
  /// holds, whichever note it belongs to — what a pulled manifest's body is
  /// assembled from until its missing chunks can be fetched.
  Future<Map<String, String>> textsByHash(Iterable<String> hashes) async {
    final texts = <String, String>{};
    for (final row in await newestByHashes(hashes.toSet().toList())) {
      texts[row.contentHash!] = textOf(row);
    }
    return texts;
  }

  /// [row]'s text, decompressed when it is stored gzip'd.
  static String textOf(ContentChunk row) => row.isCompressed
      ? CompressionUtils.decompressFromBase64(row.content)
      : row.content;

  /// The [ChunkHasher] hash of the body [rows] hold in body order — a
  /// note's manifest `bodyHash` — decompressed and hashed off this isolate
  /// once [units], the body's length, passes [BodyCut.isolateThreshold].
  /// Meant for rows one statement read, with no transaction open: one
  /// statement is consistent on its own, and while a transaction runs the
  /// executor is exclusive, so the browser would wait behind the whole body.
  static Future<String> bodyHashOf(
    List<ContentChunk> rows, {
    required int units,
  }) async {
    bodyHashCount++;
    final stored = [for (final row in rows) (row.content, row.isCompressed)];
    if (units <= BodyCut.isolateThreshold) return _bodyHash(stored);
    return _bodyHashOffThread(stored);
  }

  /// How many bodies [bodyHashOf] hashed on this isolate's behalf, so a
  /// test can pin that none is hashed while a transaction is open.
  @visibleForTesting
  static int bodyHashCount = 0;

  /// Not async, so the closure the isolate receives captures [stored] alone.
  static Future<String> _bodyHashOffThread(List<(String, bool)> stored) =>
      Isolate.run(() => _bodyHash(stored));

  static String _bodyHash(List<(String, bool)> stored) => ChunkHasher.hash(
    [
      for (final (text, compressed) in stored)
        compressed ? CompressionUtils.decompressFromBase64(text) : text,
    ].join(),
  );

  /// Re-cuts a note still stored as legacy fixed slices under its own
  /// [hlc], as an unchanged save does, so every chunk has a hash its
  /// manifest can name; the new chunks are queued at that stamp. The text is
  /// read, cut and every chunk encoded before the transaction, which writes
  /// only if the rows are still the ones read: the cutover re-cuts every
  /// pre-v46 note this way in a row, and an encode inside would hold the
  /// database for each body's gzip. Returns whether the note was re-cut:
  /// false for a note already hashed, a text that no longer decodes, or rows
  /// a save rewrote meanwhile.
  Future<bool> hashLegacy(
    String noteId, {
    required String hlc,
    required String deviceId,
  }) async {
    final before = await _liveRows(noteId);
    if (ChunkPlanner.isHashedRun([for (final row in before) row.chunk])) {
      return false;
    }
    final text = await _legacyText(noteId);
    if (text == null) return false;
    // A re-cut replaces every legacy row, so every chunk is an insert: none
    // counts as held.
    final [(cut, chunks)] = await BodyCut.ofEach([
      text,
    ], _encoderFor(const [<String>{}]));
    encodeCount += chunks.length;
    final ready = EncodedBody._(text, cut, chunks);
    return transaction(() async {
      final rows = await _liveRows(noteId);
      if (!listEquals(_signature(rows), _signature(before))) return false;
      final write = await planWrite(noteId, cut, compareLegacy: false);
      await applyWrite(
        write,
        hlc: hlc,
        deviceId: deviceId,
        version: 1,
        ready: ready,
      );
      // The note's count of its chunks follows the re-cut; its stamp does
      // not, since the text is the same.
      await customUpdate(
        'UPDATE notes SET chunk_count = ? WHERE id = ?',
        variables: [Variable<int>(write.chunkCount), Variable<String>(noteId)],
        updates: {db.notes},
        updateKind: UpdateKind.update,
      );
      return true;
    });
  }

  Future<String> loadContent(String noteId) async {
    final chunks = await getChunksForNote(noteId);

    if (chunks.isEmpty) return '';

    final buffer = StringBuffer();
    for (final chunk in chunks) {
      if (chunk.isCompressed) {
        buffer.write(CompressionUtils.decompressFromBase64(chunk.content));
      } else {
        buffer.write(chunk.content);
      }
    }

    return buffer.toString();
  }

  /// Content for many notes in a single statement, keyed by note id.
  ///
  /// The calendar's money ledger resolves every linked note at once, and one
  /// [loadContent] per note turned an event edit into an N-statement fan-out.
  ///
  /// Four details are load-bearing:
  ///
  ///  - the map is **pre-seeded with `''`** for every requested id. A note with
  ///    no chunks returns no rows, but [loadContent] answers `''` for it, and a
  ///    caller that only walks the returned rows would silently drop that note.
  ///  - `note_id` leads the ORDER BY. With it the plan is a `SEARCH` on
  ///    `idx_content_chunks_note`; without it SQLite adds a temp B-tree.
  ///  - the tombstone filter is a literal, as every chunk read spells it. The
  ///    index is full since v47, so the plan no longer hangs on that spelling.
  ///  - compression is decided per chunk, never per note: the compression
  ///    threshold and the chunk size are independent, so one note legitimately
  ///    mixes compressed and plain chunks.
  ///  - a note whose chunks fail to decode is **dropped from the map**, so an
  ///    absent key means "unreadable" while a `''` value means "no content".
  ///    Callers need that distinction: [loadContent] throws for a corrupt note,
  ///    and the money ledger relies on catching that to skip the one bad note
  ///    rather than zeroing it. Batching without this turned a single
  ///    undecodable chunk into a total failure of every note in the batch.
  Future<Map<String, String>> loadContentForNotes(List<String> noteIds) async {
    final result = <String, String>{for (final id in noteIds) id: ''};
    if (result.isEmpty) return result;

    final rows =
        await (select(contentChunks)
              ..where(
                (c) =>
                    c.noteId.isIn(result.keys.toList()) &
                    const CustomExpression<bool>('is_deleted = 0'),
              )
              ..orderBy([
                (c) => OrderingTerm.asc(c.noteId),
                (c) => OrderingTerm.asc(c.chunkIndex),
              ]))
            .get();

    final buffers = <String, StringBuffer>{};
    final unreadable = <String>{};
    for (final chunk in rows) {
      if (unreadable.contains(chunk.noteId)) continue;
      try {
        (buffers[chunk.noteId] ??= StringBuffer()).write(
          chunk.isCompressed
              ? CompressionUtils.decompressFromBase64(chunk.content)
              : chunk.content,
        );
      } catch (e) {
        debugPrint(
          '[ContentChunkDao] Chunk decode error for ${chunk.noteId}: $e',
        );
        unreadable.add(chunk.noteId);
        buffers.remove(chunk.noteId);
      }
    }
    for (final entry in buffers.entries) {
      result[entry.key] = entry.value.toString();
    }
    for (final noteId in unreadable) {
      result.remove(noteId);
    }
    return result;
  }

  /// Writes [content] over the note's stored chunks, every written chunk
  /// stamped with [hlc], and returns whether the text changed. [cut] is
  /// [content]'s, when the caller cut it already.
  ///
  /// Queues only the new chunks ([applyWrite]): a body is written only
  /// through `NoteDao`, which stamps and queues the owning note — its
  /// manifest — in the same transaction.
  Future<bool> writeChunks({
    required String noteId,
    required String content,
    required String hlc,
    BodyCut? cut,
  }) async {
    final write = await planWrite(noteId, cut ?? await BodyCut.of(content));
    await applyWrite(write, hlc: hlc, deviceId: db.deviceId, version: 1);
    return write.textChanged;
  }

  /// Cuts [content] and, when the note still holds legacy fixed slices,
  /// reads their text and encodes every new chunk — all before the caller's
  /// transaction, so a note's first save after v46 does not hold the
  /// database while it decompresses and gzips the whole body.
  /// [planWrite] uses the result only if the rows are still the ones read
  /// here; otherwise it reads them again inside the transaction. That check
  /// compares ids, indices, hashes and stamps, so it holds only while every
  /// write that changes a chunk row also changes its HLC.
  Future<PreparedBody> prepareBody(String noteId, String content) async {
    final cut = await BodyCut.of(content);
    final rows = await _liveRows(noteId);
    if (ChunkPlanner.isHashedRun([for (final row in rows) row.chunk])) {
      return PreparedBody._(cut);
    }
    final legacyText = await _legacyText(noteId);
    final encoded = await _encodeAll([
      for (var i = 0; i < cut.length; i++) cut.chunkText(i),
    ]);
    return PreparedBody._(
      cut,
      rows: _signature(rows),
      legacyText: legacyText,
      encoded: encoded,
    );
  }

  /// What storing [cut] over the note's live chunks takes, read by hash:
  /// no stored chunk is loaded or decompressed, except once for a note still
  /// holding legacy fixed slices, whose text is compared through
  /// [loadContent] so an unchanged body is re-cut without counting as an
  /// edit. A legacy text that no longer decodes counts as changed, so the
  /// re-cut replaces it and the note can be saved again.
  ///
  /// [prepared], from [prepareBody] for this [cut], spares that comparison
  /// and the encoding while the rows are unchanged since. [compareLegacy]
  /// false skips the comparison where the answer is not needed — a remote
  /// body is stored whatever it holds.
  Future<ChunkWrite> planWrite(
    String noteId,
    BodyCut cut, {
    bool compareLegacy = true,
    PreparedBody? prepared,
  }) async {
    final rows = await _liveRows(noteId);
    final plan = ChunkPlanner.plan(cut.hashes, [
      for (final row in rows) row.chunk,
    ]);
    if (!plan.recut) {
      return ChunkWrite._(noteId, cut, plan, textChanged: !plan.isEmpty);
    }
    final reuse =
        prepared != null &&
        identical(prepared.cut, cut) &&
        prepared._rows != null &&
        listEquals(prepared._rows, _signature(rows));
    final bool textChanged;
    if (reuse) {
      textChanged = prepared._legacyText != cut.text;
    } else {
      textChanged = !compareLegacy || await _legacyText(noteId) != cut.text;
    }
    return ChunkWrite._(
      noteId,
      cut,
      plan,
      textChanged: textChanged,
      encoded: reuse ? prepared._encoded : null,
    );
  }

  /// The note's live rows in `chunk_index` order, with the stamp that tells
  /// a row rewritten in place apart.
  Future<List<({StoredChunk chunk, String hlc})>> _liveRows(
    String noteId,
  ) async {
    final rows =
        await (selectOnly(contentChunks)
              ..addColumns([
                contentChunks.id,
                contentChunks.chunkIndex,
                contentChunks.contentHash,
                contentChunks.hlcTimestamp,
              ])
              ..where(
                contentChunks.noteId.equals(noteId) &
                    const CustomExpression<bool>('is_deleted = 0'),
              )
              ..orderBy([OrderingTerm.asc(contentChunks.chunkIndex)]))
            .get();
    return [
      for (final row in rows)
        (
          chunk: StoredChunk(
            id: row.read(contentChunks.id)!,
            index: row.read(contentChunks.chunkIndex)!,
            hash: row.read(contentChunks.contentHash),
          ),
          hlc: row.read(contentChunks.hlcTimestamp)!,
        ),
    ];
  }

  static List<String> _signature(
    List<({StoredChunk chunk, String hlc})> rows,
  ) => [
    for (final row in rows)
      '${row.chunk.id}|${row.chunk.index}|${row.chunk.hash}|${row.hlc}',
  ];

  /// The stored text, or null when a chunk no longer decodes.
  Future<String?> _legacyText(String noteId) async {
    try {
      return await loadContent(noteId);
    } catch (e) {
      debugPrint('[ContentChunkDao] Chunk decode error for $noteId: $e');
      return null;
    }
  }

  /// Carries out [write]'s plan, its inserted chunks stamped with [hlc],
  /// [deviceId] and [version]; the chunks it keeps keep their own stamps.
  /// Every statement goes through Drift, one batch, so the write is atomic
  /// and each kind of statement runs prepared once.
  ///
  /// An inserted hash no live row held before — none of a note owned by no
  /// account or by this note's owner — is queued at [hlc]: every such hash
  /// is then in the space or on its way there — the bind and the wire
  /// cutover queue all of them — so a text already held,
  /// a copied note or an unchanged chunk re-cut, costs no write. Nor does a
  /// hash among [inSpace], the chunks a pulled manifest named: the space
  /// holds them already, as it held them before it held the manifest
  /// (scalability record S6b).
  ///
  /// A hash whose last live row this write deletes has its entry retired in
  /// the same batch: no manifest can name it any more, and an offline run of
  /// saves would otherwise leave one dead entry per save for the next push to
  /// load and throw away.
  ///
  /// [ready] holds chunks [encodeBodies] encoded for this cut ahead of the
  /// transaction; an insert it left out is encoded here.
  Future<void> applyWrite(
    ChunkWrite write, {
    required String hlc,
    required String deviceId,
    required int version,
    Set<String> inSpace = const {},
    EncodedBody? ready,
  }) async {
    final plan = write.plan;
    if (plan.isEmpty) return;
    final cut = write.cut;
    final List<String?>? prepared =
        write._encoded ??
        (ready != null && identical(ready.cut, cut) ? ready._encoded : null);
    final late = [
      for (final index in plan.inserts)
        if (prepared?[index] == null) index,
    ];
    final lateTexts = late.isEmpty
        ? const <String>[]
        : await _encodeAll([for (final index in late) cut.chunkText(index)]);
    final lateByIndex = {
      for (final (i, index) in late.indexed) index: lateTexts[i],
    };
    final encoded = [
      for (final index in plan.inserts) prepared?[index] ?? lateByIndex[index]!,
    ];
    final inserted = {
      for (final index in plan.inserts)
        if (!inSpace.contains(cut.hashes[index])) cut.hashes[index],
    };
    final fresh = inserted.difference(
      await _heldForOwnerOf(write.noteId, inserted.toList()),
    );
    final orphaned = await _orphanedBy(plan.deleteIds, cut.hashes.toSet());
    await batch((b) {
      db.queueChunksIn(b, fresh, hlc);
      db.retireChunksIn(b, orphaned);
      if (plan.deleteIds.isNotEmpty) {
        b.deleteWhere(contentChunks, (c) => c.id.isIn(plan.deleteIds));
      }
      if (plan.shift != 0) {
        b.update(
          contentChunks,
          ContentChunksCompanion.custom(
            chunkIndex: contentChunks.chunkIndex + Constant(plan.shift),
          ),
          where: (c) =>
              c.noteId.equals(write.noteId) &
              c.chunkIndex.isBiggerOrEqualValue(plan.shiftFrom) &
              const CustomExpression<bool>('is_deleted = 0'),
        );
      }
      for (final (id, index) in plan.moves) {
        b.update(
          contentChunks,
          ContentChunksCompanion(chunkIndex: Value(index)),
          where: (c) => c.id.equals(id),
        );
      }
      if (plan.inserts.isNotEmpty) {
        b.insertAll(contentChunks, [
          for (final (i, index) in plan.inserts.indexed)
            ContentChunksCompanion.insert(
              id: db.generateId(),
              noteId: write.noteId,
              chunkIndex: index,
              content: encoded[i],
              isCompressed: Value(_compresses(cut, index)),
              contentHash: Value(cut.hashes[index]),
              hlcTimestamp: hlc,
              deviceId: deviceId,
              version: Value(version),
              isDeleted: const Value(false),
            ),
        ]);
      }
    });
  }

  /// The hashes only the rows under [deleteIds] hold, none of [kept] among
  /// them: once those rows go, no live row names them.
  Future<Set<String>> _orphanedBy(
    List<String> deleteIds,
    Set<String> kept,
  ) async {
    if (deleteIds.isEmpty) return const {};
    final hash = contentChunks.contentHash;
    final doomed = selectOnly(contentChunks, distinct: true)
      ..addColumns([hash])
      ..where(contentChunks.id.isIn(deleteIds) & hash.isNotNull());
    final candidates = {
      for (final row in await doomed.get()) row.read(hash)!,
    }.difference(kept);
    if (candidates.isEmpty) return const {};
    final others = selectOnly(contentChunks, distinct: true)
      ..addColumns([hash])
      ..where(
        hash.isIn(candidates) &
            contentChunks.id.isNotIn(deleteIds) &
            const CustomExpression<bool>('is_deleted = 0'),
      );
    return candidates.difference({
      for (final row in await others.get()) row.read(hash)!,
    });
  }

  /// The hashes among [hashes] some live row already holds, any note's.
  Future<Set<String>> heldHashes(List<String> hashes) async {
    final held = await CrdtMerge.loadInChunks(hashes, (chunk) async {
      final query = selectOnly(contentChunks, distinct: true)
        ..addColumns([contentChunks.contentHash])
        ..where(
          contentChunks.contentHash.isIn(chunk) &
              const CustomExpression<bool>('is_deleted = 0'),
        );
      return [
        for (final row in await query.get())
          row.read(contentChunks.contentHash)!,
      ];
    });
    return held.toSet();
  }

  /// The notes whose live rows hold each hash among [hashes] — the notes a
  /// held-back chunk belongs to on the Sync page; a hash no live row holds
  /// is absent.
  Future<Map<String, Set<String>>> noteIdsByHash(List<String> hashes) async {
    final rows = await CrdtMerge.loadInChunks(hashes, (chunk) async {
      final query = selectOnly(contentChunks, distinct: true)
        ..addColumns([contentChunks.contentHash, contentChunks.noteId])
        ..where(
          contentChunks.contentHash.isIn(chunk) &
              const CustomExpression<bool>('is_deleted = 0'),
        );
      return [
        for (final row in await query.get())
          (
            row.read(contentChunks.contentHash)!,
            row.read(contentChunks.noteId)!,
          ),
      ];
    });
    final notes = <String, Set<String>>{};
    for (final (hash, noteId) in rows) {
      notes.putIfAbsent(hash, () => {}).add(noteId);
    }
    return notes;
  }

  /// The hashes among [hashes] a live row holds for a note no account owns
  /// or whose owner is note [noteId]'s: the chunks that are in the space, or
  /// queued for it, as far as [noteId]'s write can tell. A row only another
  /// account's note holds was never pushed (D16), so it does not count.
  Future<Set<String>> _heldForOwnerOf(
    String noteId,
    List<String> hashes,
  ) async {
    final held = await CrdtMerge.loadInChunks(hashes, (chunk) async {
      final rows = await customSelect(
        'SELECT DISTINCT c.content_hash AS hash FROM content_chunks c '
        'JOIN notes n ON n.id = c.note_id '
        'WHERE c.is_deleted = 0 AND c.content_hash IN '
        '(${List.filled(chunk.length, '?').join(', ')}) '
        'AND (n.owner_id IS NULL OR n.owner_id IS '
        '(SELECT owner_id FROM notes WHERE id = ?))',
        variables: [
          for (final hash in chunk) Variable<String>(hash),
          Variable<String>(noteId),
        ],
        readsFrom: {contentChunks, db.notes},
      ).get();
      return [for (final row in rows) row.read<String>('hash')];
    });
    return held.toSet();
  }

  /// The hashes among [hashes] a live row holds for a note no account owns
  /// or [ownerUid] does: the chunks that account may push. A chunk row has
  /// no owner of its own, so its note's decides (D16).
  Future<Set<String>> hashesOwnedBy(
    List<String> hashes,
    String ownerUid,
  ) async {
    final owned = await CrdtMerge.loadInChunks(hashes, (chunk) async {
      final rows = await customSelect(
        'SELECT DISTINCT c.content_hash AS hash FROM content_chunks c '
        'JOIN notes n ON n.id = c.note_id '
        'WHERE c.is_deleted = 0 AND c.content_hash IN '
        '(${List.filled(chunk.length, '?').join(', ')}) '
        'AND (n.owner_id IS NULL OR n.owner_id = ?)',
        variables: [
          for (final hash in chunk) Variable<String>(hash),
          Variable<String>(ownerUid),
        ],
        readsFrom: {contentChunks, db.notes},
      ).get();
      return [for (final row in rows) row.read<String>('hash')];
    });
    return owned.toSet();
  }

  static bool _compresses(BodyCut cut, int index) {
    final start = index == 0 ? 0 : cut.ends[index - 1];
    return cut.ends[index] - start > compressionThreshold;
  }

  /// [texts] as stored: gzip'd and base64'd above [compressionThreshold],
  /// plain below. Off this isolate once they add up past
  /// [BodyCut.isolateThreshold], as the cut is.
  static Future<List<String>> _encodeAll(List<String> texts) async {
    encodeCount += texts.length;
    var units = 0;
    for (final text in texts) {
      units += text.length;
    }
    if (units <= BodyCut.isolateThreshold) return _encode(texts);
    return _encodeOffThread(texts);
  }

  /// Not async, so the closure the isolate receives captures [texts] alone.
  static Future<List<String>> _encodeOffThread(List<String> texts) =>
      Isolate.run(() => _encode(texts));

  static List<String> _encode(List<String> texts) => [
    for (final text in texts) _encodeOne(text),
  ];

  static String _encodeOne(String text) => text.length > compressionThreshold
      ? CompressionUtils.compressToBase64(text)
      : text;

  /// Cuts each remote body of [bodies] and encodes the chunks its note's
  /// live rows do not already hold ([EncodedBody]) — every body in one
  /// isolate hop above [BodyCut.isolateThreshold] — ahead of a pull page's
  /// transaction, so its merges store them with SQL alone and the browser's
  /// queries do not wait behind the page's CPU work. A chunk the merge
  /// inserts that was held when this read the rows is encoded by the merge.
  Future<List<EncodedBody>> encodeBodies(
    List<({String noteId, String text})> bodies,
  ) async {
    if (bodies.isEmpty) return const [];
    final rows = await CrdtMerge.loadInChunks(
      [for (final body in bodies) body.noteId],
      (chunk) =>
          (selectOnly(contentChunks)
                ..addColumns([contentChunks.noteId, contentChunks.contentHash])
                ..where(
                  contentChunks.noteId.isIn(chunk) &
                      const CustomExpression<bool>('is_deleted = 0'),
                ))
              .get(),
    );
    final heldBy = <String, Set<String>>{};
    for (final row in rows) {
      final hash = row.read(contentChunks.contentHash);
      if (hash == null) continue;
      heldBy.putIfAbsent(row.read(contentChunks.noteId)!, () => {}).add(hash);
    }
    final made = await BodyCut.ofEach(
      [for (final body in bodies) body.text],
      _encoderFor([
        for (final body in bodies) heldBy[body.noteId] ?? const <String>{},
      ]),
    );
    final encoded = <EncodedBody>[];
    for (final (i, (cut, chunks)) in made.indexed) {
      encodeCount += chunks.nonNulls.length;
      encoded.add(EncodedBody._(bodies[i].text, cut, chunks));
    }
    return encoded;
  }

  /// Static, so the closure an isolate may receive captures [held] alone,
  /// never this DAO.
  static List<String?> Function(BodyCut, int) _encoderFor(
    List<Set<String>> held,
  ) =>
      (cut, index) => [
        for (var i = 0; i < cut.length; i++)
          held[index].contains(cut.hashes[i])
              ? null
              : _encodeOne(cut.chunkText(i)),
      ];

  /// Deletes the chunk rows of notes being tombstoned, one statement per
  /// [AppConstants.sqlIdBatch] notes so a cascade of any size stays under
  /// SQLite's variable limit. Hard, not soft (D13): a deleted note no longer
  /// keeps its whole body. The note row keeps its tombstone and its stamp,
  /// which is all a merge reads. Nothing is lost to sync and nothing is
  /// queued: the space keeps every chunk document, so a bound note revived
  /// elsewhere fetches its body again, and an entry left for a hash no row
  /// holds any more is retired by the push.
  Future<void> deleteChunksForNotes(List<String> noteIds) async {
    for (var i = 0; i < noteIds.length; i += AppConstants.sqlIdBatch) {
      final batch = noteIds.sublist(
        i,
        math.min(i + AppConstants.sqlIdBatch, noteIds.length),
      );
      await (delete(contentChunks)..where((c) => c.noteId.isIn(batch))).go();
    }
  }

  /// Stores [content] as a remote note's body through the same plan as
  /// [writeChunks], so the receiving device writes only the chunks that
  /// changed; the chunks it writes carry the note's stamps. Returns how
  /// many chunks the body is stored as. A chunk no live row held before is
  /// queued ([applyWrite]): a body that arrived whole in a legacy document
  /// may name chunks the space never held — unless it is among [inSpace].
  /// [ready], from [encodeBodies], carries [cut] with its chunks encoded.
  Future<int> replaceChunks({
    required String noteId,
    required String content,
    required String hlc,
    required String deviceId,
    required int version,
    BodyCut? cut,
    Set<String> inSpace = const {},
    EncodedBody? ready,
  }) async {
    final write = await planWrite(
      noteId,
      cut ?? ready?.cut ?? await BodyCut.of(content),
      compareLegacy: false,
    );
    await applyWrite(
      write,
      hlc: hlc,
      deviceId: deviceId,
      version: version,
      inSpace: inSpace,
      ready: ready,
    );
    return write.chunkCount;
  }

  Future<ContentStats> getContentStats(String noteId) async {
    final chunks = await getChunksForNote(noteId);

    int compressedSize = 0;
    int compressedChunks = 0;

    for (final chunk in chunks) {
      compressedSize += chunk.content.length;
      if (chunk.isCompressed) {
        compressedChunks++;
      }
    }

    final content = await loadContent(noteId);

    return ContentStats(
      noteId: noteId,
      totalSize: content.length,
      compressedSize: compressedSize,
      chunkCount: chunks.length,
      compressedChunkCount: compressedChunks,
    );
  }
}

/// A body write planned by [ContentChunkDao.planWrite] and not yet applied:
/// the caller learns whether the text changed before choosing the stamp the
/// chunks it writes carry.
final class ChunkWrite {
  ChunkWrite._(
    this.noteId,
    this.cut,
    this.plan, {
    required this.textChanged,
    List<String>? encoded,
  }) : _encoded = encoded;

  /// The note whose chunks [plan] rewrites.
  final String noteId;

  /// The body being stored, cut and hashed.
  final BodyCut cut;

  /// The row operations that store [cut] over the rows read when planning.
  final ChunkPlan plan;

  /// Whether the stored text differs from [cut]'s. False while [plan] still
  /// has rows to write only when legacy slices are re-cut around the same
  /// text.
  final bool textChanged;

  /// Every chunk of [cut] as stored, by index, when [ContentChunkDao.prepareBody]
  /// encoded them ahead of the transaction.
  final List<String>? _encoded;

  /// How many chunks the body is stored as once [plan] is applied.
  int get chunkCount => cut.length;
}

/// A body cut, and for a note still in legacy fixed slices its stored text
/// and every new chunk encoded, by [ContentChunkDao.prepareBody] ahead of a
/// write's transaction.
final class PreparedBody {
  PreparedBody._(
    this.cut, {
    List<String>? rows,
    String? legacyText,
    List<String>? encoded,
  }) : _rows = rows,
       _legacyText = legacyText,
       _encoded = encoded;

  /// The body, cut and hashed.
  final BodyCut cut;

  /// The legacy rows read, to tell whether they changed before the write;
  /// null when the note held none.
  final List<String>? _rows;

  /// Their text, or null when a chunk no longer decodes.
  final String? _legacyText;

  final List<String>? _encoded;
}

/// A remote body cut, with the chunks its merge is expected to insert
/// already encoded, by [ContentChunkDao.encodeBodies] ahead of a pull page's
/// transaction.
final class EncodedBody {
  EncodedBody._(this.source, this.cut, this._encoded);

  /// The text as it was handed in, before [BodyCut.wellFormed]: what a merge
  /// checks is the body it stores before it takes [cut].
  final String source;

  /// The body, cut and hashed.
  final BodyCut cut;

  /// Each chunk of [cut] as stored, by index; null for a chunk the note held
  /// when the rows were read, which the merge keeps rather than inserts.
  final List<String?> _encoded;
}

class ContentStats {
  final String noteId;
  final int totalSize;
  final int compressedSize;
  final int chunkCount;
  final int compressedChunkCount;

  const ContentStats({
    required this.noteId,
    required this.totalSize,
    required this.compressedSize,
    required this.chunkCount,
    required this.compressedChunkCount,
  });

  double get compressionRatio =>
      totalSize > 0 ? compressedSize / totalSize : 1.0;
}
