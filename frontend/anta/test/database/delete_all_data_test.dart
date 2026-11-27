import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import 'package:anta/database/database.dart';

/// [AppDatabase.deleteAllData]'s order: what belongs to no database, then
/// each database before its own sidecars, the device id last — so a delete
/// that stops half-way never leaves databases behind under a new identity,
/// nor a database behind without the commits still in its `-wal` (settings
/// rework review, 2026-11-01, and the review of its fix).
///
/// The failure is staged through [AppDatabase.debugDeleteEntity], not through
/// an open handle alone: an open file refuses its delete on Windows and
/// unlinks on POSIX, so a pin that only held a file open would say nothing on
/// the machines where the order matters least and pass for no reason on the
/// others. The open-handle case runs beside it where it can fail.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory dataDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_delete_all');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  setUp(() {
    dataDir = Directory(p.join(tempDir.path, 'gym_notes'))..createSync();
  });

  tearDown(() {
    AppDatabase.debugDeleteEntity = null;
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  File seed(String name, [String content = 'x']) =>
      File(p.join(dataDir.path, name))..writeAsStringSync(content);

  /// An install with two databases, each with sidecars; a sidecar whose
  /// database is already gone; an import's leftover; and a folder nothing
  /// in the app makes.
  void seedInstall() {
    seed('device_id', 'device-here');
    seed('gym_notes.db');
    seed('gym_notes.db-wal');
    seed('gym_notes.db-shm');
    seed('work.db');
    seed('work.db-wal');
    seed('gone.db-wal');
    seed('travel.db.import-1700000000000');
    Directory(p.join(dataDir.path, 'stray')).createSync();
    seed(p.join('stray', 'note.txt'));
  }

  Set<String> left() => {
    for (final entity in dataDir.listSync()) p.basename(entity.path),
  };

  void reallyDelete(FileSystemEntity entity) => entity is Directory
      ? entity.deleteSync(recursive: true)
      : entity.deleteSync();

  test('everything goes, the folder included', () async {
    seedInstall();

    await AppDatabase.deleteAllData();

    expect(dataDir.existsSync(), isFalse);
  });

  test('a folder that is not there is nothing to delete', () async {
    dataDir.deleteSync();

    await AppDatabase.deleteAllData();

    expect(dataDir.existsSync(), isFalse);
  });

  test('what belongs to no database goes first, each database before its '
      'own sidecars, the device id last', () async {
    seedInstall();
    final order = <String>[];
    AppDatabase.debugDeleteEntity = (entity) {
      order.add(p.basename(entity.path));
      reallyDelete(entity);
    };

    await AppDatabase.deleteAllData();

    expect(order, hasLength(9));
    expect(order.last, 'device_id');
    expect(order.sublist(0, 3).toSet(), {
      'gone.db-wal',
      'travel.db.import-1700000000000',
      'stray',
    });
    final gym = order.indexOf('gym_notes.db');
    expect(order.sublist(gym + 1, gym + 3).toSet(), {
      'gym_notes.db-wal',
      'gym_notes.db-shm',
    });
    expect(order[order.indexOf('work.db') + 1], 'work.db-wal');
  });

  test('a database that cannot be deleted keeps its own -wal and the '
      'device id it was written under', () async {
    seedInstall();
    AppDatabase.debugDeleteEntity = (entity) {
      if (p.basename(entity.path) == 'work.db') {
        throw FileSystemException('held open', entity.path);
      }
      reallyDelete(entity);
    };

    await expectLater(
      AppDatabase.deleteAllData(),
      throwsA(isA<FileSystemException>()),
    );

    // Its -wal holds the commits not yet folded into the file: deleted
    // ahead of a database that then survives, they would be lost.
    expect(left(), containsAll(['work.db', 'work.db-wal', 'device_id']));
    expect(
      File(p.join(dataDir.path, 'device_id')).readAsStringSync(),
      'device-here',
    );
  });

  test('a file gone between the listing and its delete is not a failure: '
      'the rest still goes', () async {
    seedInstall();
    final tried = <String>[];
    AppDatabase.debugDeleteEntity = (entity) {
      final name = p.basename(entity.path);
      tried.add(name);
      // SQLite removes a closing connection's -wal on its own.
      if (name == 'work.db') {
        File(p.join(dataDir.path, 'work.db-wal')).deleteSync();
      }
      reallyDelete(entity);
    };

    await AppDatabase.deleteAllData();

    expect(tried, containsAll(['work.db-wal', 'device_id']));
    expect(dataDir.existsSync(), isFalse);
  });

  test('every delete runs in one turn of the event loop, as the one '
      'recursive delete before them did', () async {
    seedInstall();
    var turned = false;
    final turnedAt = <String, bool>{};
    AppDatabase.debugDeleteEntity = (entity) {
      if (turnedAt.isEmpty) scheduleMicrotask(() => turned = true);
      turnedAt[p.basename(entity.path)] = turned;
      reallyDelete(entity);
    };

    await AppDatabase.deleteAllData();

    expect(turnedAt, hasLength(9));
    expect(turnedAt.values, everyElement(isFalse));
  });

  test(
    'on Windows a database another handle holds open stops the delete with '
    'its -wal and the device id still there',
    () async {
      seedInstall();
      final held = File(p.join(dataDir.path, 'work.db')).openSync();
      try {
        await expectLater(
          AppDatabase.deleteAllData(),
          throwsA(isA<FileSystemException>()),
        );

        expect(left(), containsAll(['work.db', 'work.db-wal', 'device_id']));
      } finally {
        held.closeSync();
      }
      // Released, the same call finishes the job.
      await AppDatabase.deleteAllData();
      expect(dataDir.existsSync(), isFalse);
    },
    skip: Platform.isWindows
        ? false
        : 'an open file unlinks on POSIX: nothing fails there',
  );

  // Why a sidecar may outlive its database, and never the reverse: the
  // order above rests on this, so it is pinned against the SQLite the app
  // ships with rather than believed.
  test('a -wal that outlives its database is dropped by SQLite, never '
      'replayed into the database created under that name', () {
    final sourcePath = p.join(dataDir.path, 'source.db');
    final source = sqlite3.open(sourcePath);
    final String nextPath = p.join(dataDir.path, 'next.db');
    try {
      source.execute('PRAGMA journal_mode = WAL');
      source.execute('CREATE TABLE left_behind (v TEXT)');
      source.execute("INSERT INTO left_behind VALUES ('deleted')");
      // Not checkpointed: the table is in the -wal alone, and this copy of
      // it is what a failed delete would leave beside a name with no `.db`.
      final wal = File('$sourcePath-wal');
      expect(wal.lengthSync(), greaterThan(0));
      wal.copySync('$nextPath-wal');
    } finally {
      source.close();
    }

    final next = sqlite3.open(nextPath);
    try {
      expect(next.select('SELECT name FROM sqlite_master'), isEmpty);
    } finally {
      next.close();
    }
    expect(File('$nextPath-wal').existsSync(), isFalse);
  });

  test('a hot journal that outlives its database is dropped by SQLite, '
      'never rolled back into the database created under that name', () {
    final sourcePath = p.join(dataDir.path, 'source.db');
    final source = sqlite3.open(sourcePath);
    final String nextPath = p.join(dataDir.path, 'next.db');
    try {
      source.execute('PRAGMA journal_mode = DELETE');
      source.execute('CREATE TABLE left_behind (v TEXT)');
      source.execute("INSERT INTO left_behind VALUES ('deleted')");
      // Mid-transaction: the journal holds the pages as they were, the
      // shape a kill leaves beside a database.
      source.execute('BEGIN');
      source.execute("UPDATE left_behind SET v = 'changed'");
      final journal = File('$sourcePath-journal');
      expect(journal.lengthSync(), greaterThan(0));
      journal.copySync('$nextPath-journal');
      source.execute('ROLLBACK');
    } finally {
      source.close();
    }

    final next = sqlite3.open(nextPath);
    try {
      expect(next.select('SELECT name FROM sqlite_master'), isEmpty);
    } finally {
      next.close();
    }
    expect(File('$nextPath-journal').existsSync(), isFalse);
  });
}
