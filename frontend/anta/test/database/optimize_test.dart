import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';

/// Guards the Optimize action (`AppDatabase.optimize`, D13): the file is
/// vacuumed and checkpointed, with no index rebuilt first since `notes_fts`
/// retired (v50) — and the caption beside the action reads the free pages a
/// vacuum gives back.
void main() {
  late _CustomStatements statements;
  late AppDatabase db;

  setUp(() async {
    statements = _CustomStatements();
    db = AppDatabase.forTesting(
      NativeDatabase.memory().interceptWith(statements),
    );
    await db.customSelect('SELECT 1').get();
  });
  tearDown(() async => db.close());

  test('vacuums and rebuilds no index', () async {
    final folder = await db.folderDao.createFolder(name: 'Log');
    final gone = await db.noteDao.createNote(
      folderId: folder.id,
      title: 'bravo',
    );
    await db.noteDao.softDeleteNote(gone.id);

    statements.sql.clear();
    await db.optimize();

    expect(statements.sql, ['VACUUM']);
  });

  test('reclaimable bytes are the free pages times the page size', () async {
    await db.customStatement('CREATE TABLE ballast (v TEXT)');
    await db.customStatement(
      'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
      'WHERE x < 200) INSERT INTO ballast SELECT hex(randomblob(2000)) FROM n',
    );
    await db.customStatement('DELETE FROM ballast');
    final free = (await db.customSelect('PRAGMA freelist_count').getSingle())
        .read<int>('freelist_count');
    final page = (await db.customSelect('PRAGMA page_size').getSingle())
        .read<int>('page_size');
    expect(free, greaterThan(0));

    expect(await db.reclaimableBytes(), free * page);

    await db.optimize();
    expect(await db.reclaimableBytes(), 0);
  });

  // Under WAL a VACUUM writes the compacted copy into `-wal`; the main file
  // shrinks only at a checkpoint.
  test(
    'on a WAL file the main file shrinks and the sidecar is emptied',
    () async {
      final dir = await Directory.systemTemp.createTemp('anta_optimize_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/optimize.db');
      final wal = File('${file.path}-wal');
      final onFile = AppDatabase.forTesting(
        NativeDatabase(file, setup: configureSqliteConnection),
      );
      var closed = false;
      addTearDown(() async {
        if (!closed) await onFile.close();
      });
      await onFile.customStatement('CREATE TABLE ballast (v TEXT)');
      await onFile.customStatement(
        'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
        'WHERE x < 1000) INSERT INTO ballast SELECT hex(randomblob(2000)) FROM n',
      );
      await onFile.checkpoint();
      await onFile.customStatement('DELETE FROM ballast');
      await onFile.checkpoint();
      final before = file.lengthSync();
      expect(await onFile.reclaimableBytes(), greaterThan(0));

      await onFile.optimize();

      expect(wal.existsSync() ? wal.lengthSync() : 0, 0);
      expect(file.lengthSync(), lessThan(before));
      await onFile.close();
      closed = true;
    },
  );
}

/// Records the statements `customStatement` runs, which the shared
/// `StatementCounter` does not see.
class _CustomStatements extends QueryInterceptor {
  final List<String> sql = [];

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    sql.add(statement);
    return super.runCustom(executor, statement, args);
  }
}
