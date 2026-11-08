@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/utils/compression_utils.dart';

import '../services/sync/support/sync_pair.dart';
import '../support/scale_fixtures.dart';

/// Timings for one large note — opened, saved after a one-character edit,
/// and applied on another device — at the sizes the scalability roadmap
/// fixes (`docs/scalability-roadmap.md` §2.1, §5.1 S3).
///
/// **Tagged `benchmark` and excluded from the default run**, for the reasons
/// `volume_benchmark_test.dart` gives; the counts these timings explain are
/// pinned in the default suite (`note_body_write_budget_test.dart`,
/// `sync_note_apply_budget_test.dart`). Run it alone:
///
/// ```powershell
/// flutter test --tags benchmark --run-skipped --concurrency=1 test/database/big_note_benchmark_test.dart
/// ```
///
/// Each size runs on an in-memory database and on a file opened the way the
/// app opens one: on its own isolate with `configureSqliteConnection`. The
/// remote apply goes through `SyncPair`, whose "file" column opens both
/// devices the same way — files on background isolates with the production
/// pragmas. The assertions are catastrophe-only.
void main() {
  const sizes = [100000, 300000, 900000, 3000000, 5000000];

  for (final onFile in [false, true]) {
    final storage = onFile ? 'file' : 'memory';

    group('a large note on $storage', () {
      for (final size in sizes) {
        test('$size code units', () async {
          final body = bigBody(size);
          final local = await _open(onFile);
          final ({int create, int open, int save}) times;
          try {
            times = await _local(local.db, body);
          } finally {
            await local.db.close();
            await local.dir?.delete(recursive: true);
          }
          final remote = await _remoteApply(body, background: onFile);
          final apply = remote.micros;
          // ignore: avoid_print
          print(
            '  $storage ${'$size'.padLeft(7)}  '
            'create ${_ms(times.create)}  open ${_ms(times.open)}  '
            'save ${_ms(times.save)}  apply ${_ms(apply)}  '
            'first sync ${_ms(remote.first)}  '
            'edit pushed ${remote.pushedDocs} docs / ${remote.pushedBytes} B, '
            'read ${remote.chunksRead} chunks',
          );
          for (final elapsed in [times.open, times.save, apply]) {
            expect(elapsed, lessThan(120000000));
          }
        });
      }
    });
  }
}

String _ms(int micros) =>
    '${(micros / 1000).toStringAsFixed(1)} ms'.padLeft(10);

/// A database the way the app opens its own — on a file, on a background
/// isolate, with the production pragmas — or in memory.
Future<({AppDatabase db, Directory? dir})> _open(bool onFile) async {
  if (!onFile) {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    return (db: db, dir: null);
  }
  final dir = await Directory.systemTemp.createTemp('anta_big_note_');
  final db = AppDatabase.forTesting(
    NativeDatabase.createInBackground(
      File('${dir.path}/app.sqlite'),
      setup: configureSqliteConnection,
    ),
  );
  await db.customSelect('SELECT 1').get();
  return (db: db, dir: dir);
}

/// The note created, then opened and saved: best of three for each, every
/// save a fresh one-character edit near the top, written with the arguments
/// `NoteStorageService.updateNote` derives — the auto-save path's call.
Future<({int create, int open, int save})> _local(
  AppDatabase db,
  String body,
) async {
  final folder = await db.folderDao.createFolder(name: 'Log');
  final create = Stopwatch()..start();
  final note = await db.noteDao.createNote(
    folderId: folder.id,
    title: 'Training log',
    preview: NoteMetadata.generatePreview(body),
    content: body,
  );
  create.stop();

  var open = 1 << 62;
  for (var i = 0; i < 3; i++) {
    final sw = Stopwatch()..start();
    await db.contentChunkDao.loadContent(note.id);
    sw.stop();
    if (sw.elapsedMicroseconds < open) open = sw.elapsedMicroseconds;
  }

  var save = 1 << 62;
  var text = body;
  for (var i = 0; i < 3; i++) {
    text = editNearTop(text);
    final sw = Stopwatch()..start();
    await db.noteDao.updateNote(
      id: note.id,
      title: note.title,
      preview: NoteMetadata.generatePreview(text),
      contentLength: text.length,
      isCompressed: CompressionUtils.shouldCompress(text),
      content: text,
    );
    sw.stop();
    if (sw.elapsedMicroseconds < save) save = sw.elapsedMicroseconds;
  }
  expect(await db.contentChunkDao.loadContent(note.id), text);
  return (create: create.elapsedMicroseconds, open: open, save: save);
}

/// Device B's sync of a one-character save device A made, best of three,
/// with B's first sync of the whole note and what the last save cost on the
/// wire: the documents and bytes A pushed, the chunk documents B read.
///
/// A's push carries the note as a manifest and its chunks, over as many
/// parts as they take (scalability record S6), and B reads the chunks it
/// lacks by hash before the page merges (S6b).
Future<
  ({int micros, int first, int pushedDocs, int pushedBytes, int chunksRead})
>
_remoteApply(String body, {required bool background}) async {
  final pair = await SyncPair.open(
    background: background,
    setup: background ? configureSqliteConnection : null,
  );
  try {
    final folder = await pair.a.db.folderDao.createFolder(name: 'Log');
    final note = await writeNote(
      pair.a,
      folderId: folder.id,
      title: 'Training log',
      body: body,
    );
    await pair.a.syncFiringSpacing();
    final firstSync = Stopwatch()..start();
    await pair.b.sync();
    firstSync.stop();

    var best = 1 << 62;
    var text = body;
    late SyncRunReport pushed;
    var read = 0;
    for (var i = 0; i < 3; i++) {
      text = editNearTop(text);
      await editNote(pair.a, note.id, text);
      (pushed, _) = await pair.a.syncFiringSpacing();
      final reads = pair.gateway.rowReadKeys.length;
      final sw = Stopwatch()..start();
      final report = await pair.b.sync();
      sw.stop();
      expect(report.pulledRows, 1);
      read = pair.gateway.rowReadKeys
          .skip(reads)
          .fold(0, (sum, keys) => sum + keys.length);
      if (sw.elapsedMicroseconds < best) best = sw.elapsedMicroseconds;
    }
    expect(await pair.b.db.contentChunkDao.loadContent(note.id), text);
    return (
      micros: best,
      first: firstSync.elapsedMicroseconds,
      pushedDocs: pushed.pushedRows,
      pushedBytes: pushed.pushedBytes,
      chunksRead: read,
    );
  } finally {
    await pair.close();
  }
}
