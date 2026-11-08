import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/chunking/body_cut.dart';
import 'package:anta/database/chunking/chunk_hasher.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/database.dart';
import 'package:anta/utils/compression_utils.dart';

import '../support/scale_fixtures.dart';
import 'support/db_test_support.dart';

/// Content-defined chunks under a long run of random edits, seeded so a
/// failure replays (`docs/scalability-roadmap.md` §5.2 S4): every write
/// through the planner — local saves, then remote applies — must leave the
/// body byte-identical, the live rows numbered exactly `0..n-1`, each row's
/// hash the hash of its own text, and no row behind.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  const words = [
    'squat', 'bench', 'row', '5x5', 'kg', 'încă', 'größer', 'și', 'tempo', //
    '-', '#', '|', '---', '\n', '\n\n', lifter, 'Kniebeugen', '100', 'x',
  ];

  test(
    '150 random edits, then 30 remote applies, round-trip exactly',
    () async {
      final random = Random(20261108);
      final folder = await db.folderDao.createFolder(name: 'Log');
      final note = await db.noteDao.createNote(folderId: folder.id, title: 'A');

      String words_(int length) {
        final buffer = StringBuffer();
        while (buffer.length < length) {
          buffer
            ..write(words[random.nextInt(words.length)])
            ..write(' ');
        }
        return buffer.toString();
      }

      bool isHigh(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

      /// A random offset in [text] that does not split a surrogate pair.
      int offset(String text) {
        var at = random.nextInt(text.length + 1);
        if (at > 0 && at < text.length && isHigh(text.codeUnitAt(at - 1))) at++;
        return at;
      }

      String edit(String text) {
        if (text.isEmpty) return words_(20000);
        final a = offset(text);
        final b = offset(text);
        final (from, to) = a <= b ? (a, b) : (b, a);
        return switch (random.nextInt(4)) {
          0 when text.length < 600000 =>
            '${text.substring(0, a)}${words_(random.nextInt(4000))}'
                '${text.substring(a)}',
          1 when to - from < 20000 =>
            text.substring(0, from) + text.substring(to),
          2 => _move(text, from, to, offset(text)),
          _ when text.length < 600000 => text + words_(random.nextInt(8000)),
          _ => text.substring(0, from) + text.substring(min(to, from + 5000)),
        };
      }

      Future<void> verify(String text, {required bool hashes}) async {
        expect(await db.contentChunkDao.loadContent(note.id), text);
        final all = await (db.select(
          db.contentChunks,
        )..where((c) => c.noteId.equals(note.id))).get();
        expect(all.where((c) => c.isDeleted), isEmpty, reason: 'a stray row');
        all.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
        expect(
          [for (final c in all) c.chunkIndex],
          [for (var i = 0; i < all.length; i++) i],
        );
        if (!hashes) return;
        for (final chunk in all) {
          final raw = chunk.isCompressed
              ? CompressionUtils.decompressFromBase64(chunk.content)
              : chunk.content;
          expect(chunk.contentHash, ChunkHasher.hash(raw));
        }
      }

      var text = words_(20000);
      for (var i = 0; i < 150; i++) {
        text = edit(text);
        await db.contentChunkDao.writeChunks(
          noteId: note.id,
          content: text,
          hlc: db.newStamp().hlc,
          cut: BodyCut.inline(text),
        );
        await verify(text, hashes: i % 25 == 24);
      }
      for (var i = 0; i < 30; i++) {
        text = edit(text);
        await db.contentChunkDao.replaceChunks(
          noteId: note.id,
          content: text,
          hlc: db.newStamp().hlc,
          deviceId: 'remote',
          version: i + 2,
          cut: BodyCut.inline(text),
        );
        await verify(text, hashes: i % 10 == 9);
      }
    },
  );
}

/// [text] with `text[from, to)` moved to [at], an offset in the original.
String _move(String text, int from, int to, int at) {
  final piece = text.substring(from, to);
  final rest = text.substring(0, from) + text.substring(to);
  final target = at <= from ? at : max(from, at - (to - from));
  return rest.substring(0, target) + piece + rest.substring(target);
}
