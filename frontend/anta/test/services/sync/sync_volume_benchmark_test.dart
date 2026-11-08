@Tags(['benchmark'])
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/note_metadata.dart';

import '../../support/scale_fixtures.dart';
import 'support/sync_pair.dart';

/// The initial merge at the volume a personal tracker reaches over years
/// (`docs/scalability-roadmap.md` §2): 5,000 notes in 300 folders and
/// 20,000 calendar events, bound on one device, pushed whole, then pulled
/// whole by a second. Both databases are files on background isolates with
/// `configureSqliteConnection`'s pragmas, as the app opens them.
///
/// **Tagged `benchmark` and excluded from the default run**; the numbers are
/// the baseline S9 and S10 (§5.4) measure against. Run it alone:
///
/// ```powershell
/// flutter test --tags benchmark --run-skipped --concurrency=1 test/services/sync/sync_volume_benchmark_test.dart
/// ```
void main() {
  const folderCount = 300;
  const noteCount = 5000;
  const eventCount = 20000;

  test(
    'the initial merge of $noteCount notes and $eventCount events',
    () async {
      final pair = await SyncPair.open(
        bind: false,
        background: true,
        setup: configureSqliteConnection,
      );
      try {
        final seed = Stopwatch()..start();
        await _seed(
          pair.a.db,
          folders: folderCount,
          notes: noteCount,
          events: eventCount,
        );
        seed.stop();

        final bindA = Stopwatch()..start();
        await pair.bind(pair.a);
        bindA.stop();
        final queued = await pair.a.db.syncOutboxDao.count();

        // A note is a manifest and its chunks since S6, so the push is cut
        // into parts by count, each waiting out the spacing on the manual
        // scheduler — fired here as it comes, at no wall time.
        final push = Stopwatch()..start();
        final (pushed, _) = await pair.a.syncFiringSpacing();
        push.stop();

        await pair.bind(pair.b);
        final pull = Stopwatch()..start();
        final pulled = await pair.b.sync();
        pull.stop();
        // The chunks B read by hash for the manifests it pulled (S6b).
        final chunkReads = [
          for (final (i, keys) in pair.gateway.rowReadKeys.indexed)
            if (pair.gateway.rowReads[i].startsWith('content_chunks:')) keys,
        ];

        // ignore: avoid_print
        print(
          '\n=== initial merge: $folderCount folders, $noteCount notes, '
          '$eventCount events ===\n'
          '  seed     ${seed.elapsedMilliseconds} ms\n'
          '  bind A   ${bindA.elapsedMilliseconds} ms ($queued queued)\n'
          '  push A   ${push.elapsedMilliseconds} ms '
          '(${pushed.pushedRows} rows, ${pushed.pushedBytes} B, '
          '${pair.gateway.pushes.length} batches)\n'
          '  pull B   ${pull.elapsedMilliseconds} ms '
          '(${pulled.pulledRows} rows in ${pulled.pages} pages, '
          '${chunkReads.fold(0, (n, keys) => n + keys.length)} chunks read '
          'in ${chunkReads.length} calls)',
        );
        expect(pushed.failure, isNull);
        expect(pulled.failure, isNull);
        expect(await pair.b.db.noteDao.getAllNotes(), hasLength(noteCount));
        expect(
          await pair.b.db.calendarEventDao.getAll(),
          hasLength(eventCount),
        );
        expect(
          push.elapsed + pull.elapsed,
          lessThan(const Duration(minutes: 5)),
        );
      } finally {
        await pair.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// Rows written as an install that has never synced holds them: stamped by
/// this device, unowned, a body of about 1,500 code units per note in one
/// chunk, as `NoteDao` stores a short note.
Future<void> _seed(
  AppDatabase db, {
  required int folders,
  required int notes,
  required int events,
}) async {
  final epoch = DateTime.utc(2026, 1, 1);
  var wall = epoch.millisecondsSinceEpoch;
  String stamp() => '${(++wall).toRadixString(16).padLeft(12, '0')}:0000:A';
  final text = bigBody(1500);
  await db.batch((batch) {
    for (var f = 0; f < folders; f++) {
      batch.insert(
        db.folders,
        FoldersCompanion.insert(
          id: 'folder-$f',
          name: 'Folder $f',
          hlcTimestamp: stamp(),
          deviceId: 'A',
          createdAt: epoch,
          updatedAt: epoch,
          position: Value(f),
        ),
      );
    }
    for (var i = 0; i < notes; i++) {
      final id = 'note-$i';
      final body = '$text\nsession$i';
      final hlc = stamp();
      batch
        ..insert(
          db.notes,
          NotesCompanion.insert(
            id: id,
            folderId: 'folder-${i % folders}',
            title: 'Session $i',
            preview: Value(NoteMetadata.generatePreview(body)),
            contentLength: Value(body.length),
            chunkCount: const Value(1),
            hlcTimestamp: hlc,
            deviceId: 'A',
            createdAt: epoch,
            updatedAt: epoch,
            position: Value(i ~/ folders),
          ),
        )
        ..insert(
          db.contentChunks,
          ContentChunksCompanion.insert(
            id: '${id}_chunk_0',
            noteId: id,
            chunkIndex: 0,
            content: body,
            hlcTimestamp: hlc,
            deviceId: 'A',
          ),
        );
    }
    for (var i = 0; i < events; i++) {
      batch.insert(
        db.calendarEvents,
        CalendarEventsCompanion.insert(
          id: 'event-$i',
          title: 'Event $i',
          category: 'gym',
          startDate: epoch.add(Duration(days: i % 3650)),
          ruleKind: 'daily',
          createdAt: epoch,
          updatedAt: epoch,
          hlcTimestamp: Value(stamp()),
          deviceId: const Value('A'),
        ),
      );
    }
  });
}
