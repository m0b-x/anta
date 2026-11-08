import 'package:flutter_test/flutter_test.dart';

import 'package:drift/drift.dart' hide isNull, isNotNull;

import 'package:anta/database/chunking/chunk_hasher.dart';
import 'package:anta/database/chunking/content_chunker.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/daos/content_chunk_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/utils/compression_utils.dart';

import '../support/scale_fixtures.dart';
import 'support/db_test_support.dart';

/// Guards the chunk cuts against splitting a surrogate pair.
///
/// Every stored chunk crosses UTF-8 (SQLite binds text that way; a chunk over
/// [ContentChunkDao.compressionThreshold] is gzip'd that way too), and UTF-8
/// writes a lone surrogate as U+FFFD: an emoji whose two halves land in two
/// chunks is corrupted on save, again on a remote apply, and its chunk never
/// compares equal again, so every save rewrites it
/// (`docs/scalability-roadmap.md` §5.1 S2).
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  const emoji = '\u{1F3CB}';

  /// About 25,000 code units of ASCII, Romanian and German text with
  /// [emoji] placed so its high surrogate sits at each offset in [highAt].
  String body(List<int> highAt) {
    const filler = 'Antrenament greu, încă o serie ș ț â; Übung größer. ';
    final buffer = StringBuffer();
    var i = 0;
    for (final offset in highAt) {
      while (buffer.length < offset) {
        buffer.write(filler[i++ % filler.length]);
      }
      buffer.write(emoji);
    }
    while (buffer.length < 25000) {
      buffer.write(filler[i++ % filler.length]);
    }
    final text = buffer.toString();
    for (final offset in highAt) {
      expect(text.codeUnitAt(offset), 0xD83C, reason: 'the fixture layout');
    }
    return text;
  }

  /// The pairs straddle the legacy fixed 10,000-unit cuts; the second layout puts
  /// the second pair across the cut that follows a stepped-back first chunk.
  final layouts = <String, List<int>>{
    'pairs across 9,999/10,000 and 19,999/20,000': [9999, 19999],
    'pairs across 9,999/10,000 and 19,998/19,999': [9999, 19998],
  };

  Future<String> seedNoteId() async {
    final folder = await db.folderDao.createFolder(name: 'Training');
    final note = await db.noteDao.createNote(folderId: folder.id, title: 'A');
    return note.id;
  }

  Future<bool> write(String noteId, String content) {
    return db.transaction(
      () => db.contentChunkDao.writeChunks(
        noteId: noteId,
        content: content,
        hlc: db.newStamp().hlc,
      ),
    );
  }

  bool isHigh(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
  bool isLow(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  for (final MapEntry(key: name, value: highAt) in layouts.entries) {
    group(name, () {
      test('writeChunks round-trips the body unit for unit', () async {
        final noteId = await seedNoteId();
        final text = body(highAt);

        await write(noteId, text);

        expect(await db.contentChunkDao.loadContent(noteId), text);
      });

      test('replaceChunks round-trips the body unit for unit', () async {
        final noteId = await seedNoteId();
        final text = body(highAt);

        await db.contentChunkDao.replaceChunks(
          noteId: noteId,
          content: text,
          hlc: db.newStamp().hlc,
          deviceId: 'remote',
          version: 2,
        );

        expect(await db.contentChunkDao.loadContent(noteId), text);
      });

      test('no stored chunk ends inside a surrogate pair', () async {
        final noteId = await seedNoteId();

        await write(noteId, body(highAt));

        final chunks = await db.contentChunkDao.getChunksForNote(noteId);
        expect(chunks.any((c) => c.isCompressed), isTrue);
        for (final chunk in chunks) {
          final raw = chunk.isCompressed
              ? CompressionUtils.decompressFromBase64(chunk.content)
              : chunk.content;
          expect(raw.length, lessThanOrEqualTo(ContentChunker.maxCodeUnits));
          expect(
            isHigh(raw.codeUnitAt(raw.length - 1)),
            isFalse,
            reason: '${chunk.id} ends with a lone high surrogate',
          );
          expect(
            isLow(raw.codeUnitAt(0)),
            isFalse,
            reason: '${chunk.id} starts with a lone low surrogate',
          );
          expect(
            raw.contains('\u{FFFD}'),
            isFalse,
            reason: '${chunk.id} was compressed with half a pair',
          );
        }
      });

      test('writing the same body again changes nothing', () async {
        final noteId = await seedNoteId();
        final text = body(highAt);
        await write(noteId, text);

        expect(await write(noteId, text), isFalse);
      });
    });
  }

  /// Content-defined chunks with a per-chunk hash (§5.2 S4).
  group('hashed chunks', () {
    Future<List<ContentChunk>> rows(String noteId) =>
        db.contentChunkDao.getChunksForNote(noteId);

    String textOf(ContentChunk chunk) => chunk.isCompressed
        ? CompressionUtils.decompressFromBase64(chunk.content)
        : chunk.content;

    /// [text] stored the way builds before v46 stored it: fixed 10,000-unit
    /// slices under their positional ids, with no hash, each stepped back
    /// before a high surrogate as S2's cut does.
    Future<void> writeLegacy(String noteId, String text) async {
      final stamp = db.newStamp();
      var start = 0;
      for (var i = 0; start < text.length; i++) {
        var end = start + 10000 > text.length ? text.length : start + 10000;
        if (end < text.length && isHigh(text.codeUnitAt(end - 1))) end--;
        final slice = text.substring(start, end);
        start = end;
        final compress = slice.length > ContentChunkDao.compressionThreshold;
        await db
            .into(db.contentChunks)
            .insert(
              ContentChunksCompanion.insert(
                id: '${noteId}_chunk_$i',
                noteId: noteId,
                chunkIndex: i,
                content: compress
                    ? CompressionUtils.compressToBase64(slice)
                    : slice,
                isCompressed: Value(compress),
                hlcTimestamp: stamp.hlc,
                deviceId: stamp.deviceId,
              ),
            );
      }
    }

    test('every chunk carries the hash of its own text', () async {
      final noteId = await seedNoteId();
      final text = bigBody(100000);

      await write(noteId, text);

      final chunks = await rows(noteId);
      expect(chunks.length, ContentChunker.cut(text).length);
      for (final chunk in chunks) {
        expect(chunk.contentHash, ChunkHasher.hash(textOf(chunk)));
        expect(
          chunk.isCompressed,
          textOf(chunk).length > ContentChunkDao.compressionThreshold,
        );
      }
      expect(await db.contentChunkDao.loadContent(noteId), text);
    });

    test('an edit keeps every chunk it does not reach, row for row', () async {
      final noteId = await seedNoteId();
      final text = bigBody(100000);
      await write(noteId, text);
      final before = await rows(noteId);

      final edited = editInMiddle(text);
      expect(await write(noteId, edited), isTrue);

      final after = await rows(noteId);
      final kept = {for (final c in before) c.id: c};
      final rewritten = after.where((c) => !kept.containsKey(c.id)).toList();
      expect(rewritten.length, inInclusiveRange(1, 2));
      for (final chunk in after.where((c) => kept.containsKey(c.id))) {
        expect(chunk.content, kept[chunk.id]!.content);
        expect(chunk.hlcTimestamp, kept[chunk.id]!.hlcTimestamp);
      }
      expect(
        [for (final c in after) c.chunkIndex],
        [for (var i = 0; i < after.length; i++) i],
      );
      expect(await db.contentChunkDao.loadContent(noteId), edited);
    });

    test('a body over the isolate threshold is cut off the calling isolate '
        'and reads back the same', () async {
      final noteId = await seedNoteId();
      final text = bigBody(BodyCut.isolateThreshold * 3);

      await write(noteId, text);
      final edited = '${text.substring(0, 100)}x${text.substring(100)}';
      await write(noteId, edited);

      expect(await db.contentChunkDao.loadContent(noteId), edited);
    });

    test('replaceChunks writes only the changed chunks, under the note\'s '
        'stamps', () async {
      final noteId = await seedNoteId();
      final text = bigBody(100000);
      await write(noteId, text);
      final before = {for (final c in await rows(noteId)) c.id};
      final edited = '${text.substring(0, 100)}x${text.substring(100)}';
      final hlc = db.newStamp().hlc;

      final count = await db.contentChunkDao.replaceChunks(
        noteId: noteId,
        content: edited,
        hlc: hlc,
        deviceId: 'remote',
        version: 4,
      );

      final after = await rows(noteId);
      expect(count, after.length);
      final written = after.where((c) => !before.contains(c.id)).toList();
      expect(written.length, inInclusiveRange(1, 2));
      for (final chunk in written) {
        expect(chunk.hlcTimestamp, hlc);
        expect(chunk.deviceId, 'remote');
        expect(chunk.version, 4);
      }
      expect(await db.contentChunkDao.loadContent(noteId), edited);
    });

    group('legacy fixed slices', () {
      test('load as they always did', () async {
        final noteId = await seedNoteId();
        final text = bigBody(35000);
        await writeLegacy(noteId, text);

        expect(await db.contentChunkDao.loadContent(noteId), text);
      });

      test('the same text is re-cut with hashes, as no change, once', () async {
        final noteId = await seedNoteId();
        final text = bigBody(35000);
        await writeLegacy(noteId, text);

        expect(await write(noteId, text), isFalse);

        final chunks = await rows(noteId);
        expect(chunks.every((c) => c.contentHash != null), isTrue);
        expect(chunks.any((c) => c.id.contains('_chunk_')), isFalse);
        expect(await db.contentChunkDao.loadContent(noteId), text);
        final plan = await db.contentChunkDao.planWrite(
          noteId,
          BodyCut.inline(text),
        );
        expect(plan.plan.isEmpty, isTrue);
      });

      test('a changed text is re-cut whole and counts as a change', () async {
        final noteId = await seedNoteId();
        final text = bigBody(35000);
        await writeLegacy(noteId, text);

        expect(await write(noteId, '${text}x'), isTrue);

        expect(await db.contentChunkDao.loadContent(noteId), '${text}x');
        final chunks = await rows(noteId);
        expect(chunks.every((c) => c.contentHash != null), isTrue);
      });

      test('a slice that no longer decodes counts as changed, so the note '
          'can be saved again', () async {
        final noteId = await seedNoteId();
        final stamp = db.newStamp();
        await db
            .into(db.contentChunks)
            .insert(
              ContentChunksCompanion.insert(
                id: '${noteId}_chunk_0',
                noteId: noteId,
                chunkIndex: 0,
                content: 'not base64 at all!',
                isCompressed: const Value(true),
                hlcTimestamp: stamp.hlc,
                deviceId: stamp.deviceId,
              ),
            );

        final saved = await db.noteDao.updateNote(id: noteId, content: 'new');

        expect(saved, isNot(null));
        expect(await db.contentChunkDao.loadContent(noteId), 'new');
        expect(await rows(noteId), hasLength(1));
      });

      test('a prepared body whose rows changed since is compared again '
          'inside the write', () async {
        final noteId = await seedNoteId();
        final text = bigBody(35000);
        await writeLegacy(noteId, text);
        final prepared = await db.contentChunkDao.prepareBody(noteId, text);

        await (db.update(
          db.contentChunks,
        )..where((c) => c.id.equals('${noteId}_chunk_0'))).write(
          ContentChunksCompanion(
            content: const Value('rewritten elsewhere'),
            isCompressed: const Value(false),
            hlcTimestamp: Value(db.newStamp().hlc),
          ),
        );

        final write = await db.contentChunkDao.planWrite(
          noteId,
          prepared.cut,
          prepared: prepared,
        );
        expect(write.textChanged, isTrue);
        await db.contentChunkDao.applyWrite(
          write,
          hlc: db.newStamp().hlc,
          deviceId: db.deviceId,
          version: 1,
        );
        expect(await db.contentChunkDao.loadContent(noteId), text);
      });
    });

    test(
      'an unchanged save corrects a stale chunk count without a stamp',
      () async {
        final folder = await db.folderDao.createFolder(name: 'Log');
        final text = bigBody(35000);
        final note = await db.noteDao.createNote(
          folderId: folder.id,
          title: 'A',
          content: text,
        );
        await (db.update(db.notes)..where((n) => n.id.equals(note.id))).write(
          const NotesCompanion(chunkCount: Value(99)),
        );

        final saved = await db.noteDao.updateNote(id: note.id, content: text);

        expect(saved!.chunkCount, (await rows(note.id)).length);
        expect(saved.hlcTimestamp, note.hlcTimestamp);
        expect(saved.version, note.version);
      },
    );
  });
}
