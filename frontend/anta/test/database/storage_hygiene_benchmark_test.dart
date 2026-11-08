@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';

import '../support/scale_fixtures.dart';

/// The v47 step on a 500 MB-class database (`docs/scalability-roadmap.md`
/// §5.7 S16): every note's body is a copy of one `bigBody` note's stored
/// chunks, half the notes are tombstones whose chunks v46 kept, and a few
/// live notes carry a stray tombstoned chunk. The step's purge is a full read
/// of `content_chunks` — it is timed here, on a file opened the way the app
/// opens one.
///
/// **Tagged `benchmark` and excluded from the default run**; it writes about
/// half a gigabyte to the system temp directory. Run it alone:
///
/// ```powershell
/// flutter test --tags benchmark --run-skipped test/database/storage_hygiene_benchmark_test.dart
/// ```
void main() {
  const targetBytes = 500 * 1024 * 1024;

  test(
    'the v47 step on a 500 MB database',
    () async {
      final dir = await Directory.systemTemp.createTemp('anta_v47_');
      final file = File('${dir.path}/app.sqlite');
      final db = AppDatabase.forTesting(
        NativeDatabase.createInBackground(
          file,
          setup: configureSqliteConnection,
        ),
      );
      try {
        final folder = await db.folderDao.createFolder(name: 'Log');
        final seed = await db.noteDao.createNote(
          folderId: folder.id,
          title: 'Seed',
          content: bigBody(900000),
        );
        final perNote =
            (await db
                    .customSelect(
                      'SELECT SUM(LENGTH(content)) AS n FROM content_chunks '
                      'WHERE note_id = ?',
                      variables: [Variable<String>(seed.id)],
                    )
                    .getSingle())
                .read<int>('n');
        final copies = targetBytes ~/ perNote;

        final build = Stopwatch()..start();
        await db.transaction(() async {
          // Every second copy is a tombstone holding its tombstoned body, as
          // every build before v47 left one; every tenth live one carries a
          // stray tombstoned chunk.
          await db.customStatement(
            'WITH RECURSIVE k(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM k '
            'WHERE i < ?) '
            "INSERT INTO notes (id, folder_id, title, preview, content_length, "
            'chunk_count, is_compressed, position, created_at, updated_at, '
            'hlc_timestamp, device_id, version, is_deleted) '
            "SELECT 'n' || i, folder_id, 'Note ' || i, preview, content_length, "
            'chunk_count, is_compressed, i, created_at, updated_at, '
            'hlc_timestamp, device_id, version, i % 2 FROM notes, k '
            'WHERE notes.id = ?',
            [copies, seed.id],
          );
          await db.customStatement(
            'WITH RECURSIVE k(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM k '
            'WHERE i < ?) '
            'INSERT INTO content_chunks (id, note_id, chunk_index, content, '
            'is_compressed, content_hash, hlc_timestamp, device_id, version, '
            'is_deleted) '
            "SELECT 'n' || i || '_' || c.id, 'n' || i, c.chunk_index, "
            'c.content, c.is_compressed, c.content_hash, c.hlc_timestamp, '
            'c.device_id, c.version, i % 2 FROM content_chunks c, k '
            'WHERE c.note_id = ?',
            [copies, seed.id],
          );
          await db.customStatement(
            'WITH RECURSIVE k(i) AS (SELECT 2 UNION ALL SELECT i + 20 FROM k '
            'WHERE i + 20 <= ?) '
            'INSERT INTO content_chunks (id, note_id, chunk_index, content, '
            'is_compressed, hlc_timestamp, device_id, is_deleted) '
            "SELECT 'stray' || i, 'n' || i, 9999, 'x', 0, 'h', 'd', 1 FROM k",
            [copies],
          );
        });
        // The v46 index shape the step starts from.
        await db.customStatement('DROP INDEX idx_content_chunks_note');
        await db.customStatement('DROP INDEX idx_sync_outbox_order');
        await db.customStatement(
          'CREATE INDEX idx_chunks_note_index ON content_chunks(note_id, '
          'chunk_index) WHERE is_deleted = 0',
        );
        await db.customStatement(
          'CREATE INDEX idx_notes_folder ON notes(folder_id) '
          'WHERE is_deleted = 0',
        );
        await db.customStatement(
          'CREATE INDEX idx_folders_parent ON folders(parent_id) '
          'WHERE is_deleted = 0',
        );
        await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
        build.stop();

        Future<int> chunkCount() async =>
            (await db
                    .customSelect('SELECT COUNT(*) AS n FROM content_chunks')
                    .getSingle())
                .read<int>('n');
        final rowsBefore = await chunkCount();
        final sizeBefore = await file.length();

        final step = Stopwatch()..start();
        await DatabaseMigrations(db).runMigrations(
          db.createMigrator(),
          DatabaseSchema.v46ContentChunkHashes,
          DatabaseSchema.v47StorageHygiene,
        );
        step.stop();

        final rowsAfter = await chunkCount();
        final reclaimable = await db.reclaimableBytes();
        // ignore: avoid_print
        print(
          '  v47 on ${(sizeBefore / (1024 * 1024)).toStringAsFixed(0)} MB '
          '($copies notes of ${(perNote / 1024).toStringAsFixed(0)} KB stored, '
          'half tombstoned): built in ${build.elapsedMilliseconds} ms; '
          'chunks $rowsBefore -> $rowsAfter; '
          'step ${step.elapsedMilliseconds} ms; '
          'reclaimable after ${(reclaimable / (1024 * 1024)).toStringAsFixed(0)} '
          'MB',
        );
        expect(rowsAfter, lessThan(rowsBefore));
        expect(step.elapsed, lessThan(const Duration(minutes: 5)));
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
