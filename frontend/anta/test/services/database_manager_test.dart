import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/sync/sync_gateway.dart';

import '../support/scripted_prefs_store.dart';

/// `DatabaseManager.checkpoint` is what makes a shared `.db` whole: the app
/// runs in WAL, so committed writes sit in the `-wal` sidecar until a
/// checkpoint folds them back, and a share hands over the main file alone
/// (S2 of the settings rework, `docs/settings-rework-roadmap.md`, D8).
///
/// Everything is file-backed in a temporary documents directory — an
/// in-memory database never journals. "The main file holds the rows" is read
/// from a copy of the `.db` taken without its sidecars, which is exactly what
/// a share sees.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseManager manager;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_db_manager');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    manager = await DatabaseManager.getInstance();
  });

  tearDown(() async {
    // Closes the open database and empties the directory.
    await AppDatabase.deleteAllData();
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Opens a copy of [dbPath] taken without its sidecars and runs [read].
  T readMainFileAlone<T>(String dbPath, T Function(Database db) read) {
    final copyPath = p.join(tempDir.path, 'copy.db');
    File(dbPath).copySync(copyPath);
    final copy = sqlite3.open(copyPath);
    try {
      return read(copy);
    } finally {
      copy.close();
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('$copyPath$suffix');
        if (file.existsSync()) file.deleteSync();
      }
    }
  }

  int count(Database db, String sql) =>
      db.select(sql).single.values.first as int;

  /// Leaves [name] as an app quit before folding leaves it: a `.db` and a
  /// `-wal` holding 300 items the main file does not, copied in from a
  /// writer elsewhere while it still held them open.
  Future<String> leaveInSidecar(String name) async {
    final sourcePath = p.join(tempDir.path, 'writer', '$name.db');
    await Directory(p.dirname(sourcePath)).create(recursive: true);
    final targetPath = await manager.getDatabasePath(name);
    await Directory(p.dirname(targetPath)).create(recursive: true);
    final writer = sqlite3.open(sourcePath);
    try {
      writer.execute('PRAGMA journal_mode = WAL');
      writer.execute('PRAGMA wal_autocheckpoint = 0');
      writer.execute('CREATE TABLE items (v TEXT)');
      writer.execute(
        'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
        'WHERE x < 300) INSERT INTO items SELECT hex(randomblob(100)) FROM n',
      );
      File(sourcePath).copySync(targetPath);
      File('$sourcePath-wal').copySync('$targetPath-wal');
    } finally {
      writer.close();
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('$sourcePath$suffix');
        if (file.existsSync()) file.deleteSync();
      }
    }
    expect(File('$targetPath-wal').lengthSync(), greaterThan(0));
    return targetPath;
  }

  /// Whether [path]'s `-wal` still holds frames.
  bool walHasContent(String path) {
    final wal = File('$path-wal');
    return wal.existsSync() && wal.lengthSync() > 0;
  }

  test('the open database folds its WAL into the main file on its own '
      'connection', () async {
    final db = await AppDatabase.getInstance();
    final path = await manager.getDatabasePath(manager.getActiveDatabaseName());
    // Past the WAL's 1,000-page auto-checkpoint, so the sidecar is large and
    // already partly folded; the folder written last sits in the WAL alone.
    await db.customStatement('CREATE TABLE ballast (v TEXT)');
    await db.customStatement(
      'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
      'WHERE x < 2500) INSERT INTO ballast SELECT hex(randomblob(1000)) FROM n',
    );
    await db.folderDao.createFolder(name: 'Latest');

    const latestSql = "SELECT count(*) FROM folders WHERE name = 'Latest'";
    expect(File('$path-wal').lengthSync(), greaterThan(0));
    expect(
      readMainFileAlone(path, (copy) => count(copy, latestSql)),
      0,
      reason: 'before the checkpoint a copy of the .db lacks the last write',
    );

    await manager.checkpoint(manager.getActiveDatabaseName());

    expect(File('$path-wal').lengthSync(), 0);
    expect(readMainFileAlone(path, (copy) => count(copy, latestSql)), 1);
    expect(
      readMainFileAlone(
        path,
        (copy) => count(copy, 'SELECT count(*) FROM ballast'),
      ),
      2500,
    );
    // The live connection is the same one, still usable.
    expect(identical(await AppDatabase.getInstance(), db), isTrue);
  });

  test('another database with a sidecar left behind is folded on a '
      'short-lived connection', () async {
    // A WAL database written elsewhere, its files copied in while the writer
    // still holds them open — the shape an app quit before folding leaves.
    final sourcePath = p.join(tempDir.path, 'source', 'work.db');
    await Directory(p.dirname(sourcePath)).create(recursive: true);
    final writer = sqlite3.open(sourcePath);
    final targetPath = await manager.getDatabasePath('work');
    await Directory(p.dirname(targetPath)).create(recursive: true);
    try {
      writer.execute('PRAGMA journal_mode = WAL');
      writer.execute('PRAGMA wal_autocheckpoint = 0');
      writer.execute('CREATE TABLE items (v TEXT)');
      writer.execute(
        'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
        'WHERE x < 300) INSERT INTO items SELECT hex(randomblob(100)) FROM n',
      );
      File(sourcePath).copySync(targetPath);
      File('$sourcePath-wal').copySync('$targetPath-wal');
    } finally {
      writer.close();
    }
    expect(File('$targetPath-wal').lengthSync(), greaterThan(0));
    expect(
      readMainFileAlone(
        targetPath,
        (copy) => count(
          copy,
          "SELECT count(*) FROM sqlite_master WHERE name = 'items'",
        ),
      ),
      0,
      reason: 'the table exists only in the sidecar',
    );

    await manager.checkpoint('work');

    final wal = File('$targetPath-wal');
    expect(!wal.existsSync() || wal.lengthSync() == 0, isTrue);
    expect(
      readMainFileAlone(
        targetPath,
        (copy) => count(copy, 'SELECT count(*) FROM items'),
      ),
      300,
    );
    expect(AppDatabase.openInstanceOf('work'), isNull);
  });

  test(
    'a database with no sidecar is left alone and nothing is opened',
    () async {
      await manager.createDatabase('quiet');
      final path = await manager.getDatabasePath('quiet');

      await manager.checkpoint('quiet');
      await manager.checkpoint(manager.getActiveDatabaseName());

      expect(File(path).lengthSync(), 0);
      expect(File('$path-wal').existsSync(), isFalse);
      expect(AppDatabase.openInstanceOf('quiet'), isNull);
      expect(
        AppDatabase.openInstanceOf(manager.getActiveDatabaseName()),
        isNull,
        reason: 'a checkpoint never opens the database it was asked about',
      );
    },
  );

  test('a sidecar with no database beside it creates nothing', () async {
    final path = await manager.getDatabasePath('orphan');
    await Directory(p.dirname(path)).create(recursive: true);
    File('$path-wal').writeAsBytesSync([1, 2, 3]);

    await manager.checkpoint('orphan');

    expect(File(path).existsSync(), isFalse);
    expect(File('$path-wal').readAsBytesSync(), [1, 2, 3]);
    expect(
      (await manager.listDatabases()).map((db) => db.name),
      isNot(contains('orphan')),
    );
  });

  test('renaming a database with writes left in its sidecar folds them into '
      'the renamed file first', () async {
    await leaveInSidecar('work');
    final oldPath = await manager.getDatabasePath('work');

    await manager.renameDatabase('work', 'office');

    final newPath = await manager.getDatabasePath('office');
    expect(File(oldPath).existsSync(), isFalse);
    expect(walHasContent(oldPath), isFalse);
    expect(
      walHasContent(newPath),
      isFalse,
      reason: 'nothing a kill between the renames could strand',
    );
    expect(
      readMainFileAlone(
        newPath,
        (copy) => count(copy, 'SELECT count(*) FROM items'),
      ),
      300,
    );
    expect(AppDatabase.openInstanceOf('office'), isNull);
  });

  test(
    'a sidecar rename that fails still reports the failure, yet the sync '
    'claim and the active name follow the `.db` (review BA-M6, RA2-1)',
    () async {
      const space = SyncSpaceRef(ownerUid: 'uid-1', spaceId: 'space-1');
      await manager.createDatabase('work');
      await manager.spaceRegistry.claim(space, 'work');
      await manager.setActiveDatabaseName('work');
      addTearDown(() async {
        await (await SharedPreferences.getInstance()).remove(
          SettingsKeys.syncBoundSpaces,
        );
        await manager.setActiveDatabaseName('gym_notes');
      });
      // A stray `-shm` beside a closed database, and a directory where its
      // renamed twin must go: the `.db` moves, then the sidecar's rename fails.
      // Closed, because Windows cannot rename an open file.
      final oldPath = await manager.getDatabasePath('work');
      File('$oldPath-shm').writeAsStringSync('stray');
      final newPath = await manager.getDatabasePath('office');
      Directory('$newPath-shm/blocked').createSync(recursive: true);

      await expectLater(
        manager.renameDatabase('work', 'office'),
        throwsA(isA<FileSystemException>()),
      );

      expect(File(newPath).existsSync(), isTrue);
      expect(manager.spaceRegistry.claims().single.databaseName, 'office');
      expect(await manager.spaceRegistry.holderOf(space), 'office');
      expect(manager.getActiveDatabaseName(), 'office');
    },
  );

  test('a registry write that fails during a rename is logged: every file '
      'still moves and the rename completes (final review X-3)', () async {
    const space = SyncSpaceRef(ownerUid: 'uid-1', spaceId: 'space-1');
    await manager.createDatabase('work');
    await manager.spaceRegistry.claim(space, 'work');
    await manager.setActiveDatabaseName('work');
    final previous = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = ScriptedPrefsStore()
      ..failWrite = (key) => key == SettingsKeys.syncBoundSpaces;
    addTearDown(() async {
      SharedPreferencesStorePlatform.instance = previous;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(SettingsKeys.syncBoundSpaces);
      await manager.setActiveDatabaseName('gym_notes');
    });
    // A closed file's `-wal` is folded and removed by the checkpoint before
    // any file moves, so the sidecar left to carry here is the `-shm`.
    final oldPath = await manager.getDatabasePath('work');
    File('$oldPath-shm').writeAsStringSync('stray');

    await manager.renameDatabase('work', 'office');

    final newPath = await manager.getDatabasePath('office');
    expect(File(newPath).existsSync(), isTrue);
    expect(File('$newPath-shm').readAsStringSync(), 'stray');
    // The two `-wal` checks document the checkpoint-first contract; on a
    // closed file they cannot fail, so they do not pin it.
    for (final suffix in ['', '-wal', '-shm']) {
      expect(File('$oldPath$suffix').existsSync(), isFalse, reason: suffix);
    }
    expect(File('$newPath-wal').existsSync(), isFalse);
    expect(manager.getActiveDatabaseName(), 'office');
  });

  group('a blocked checkpoint throws', () {
    test('on the live connection, which stays writable and folds once the '
        'reader is gone', () async {
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final path = await manager.getDatabasePath(name);
      await db.folderDao.createFolder(name: 'In the WAL');
      expect(File('$path-wal').lengthSync(), greaterThan(0));

      // A foreign reader holding a snapshot of the WAL.
      final reader = sqlite3.open(path, mode: OpenMode.readWrite);
      Object? error;
      try {
        reader.execute('BEGIN');
        reader.select('SELECT count(*) FROM folders');
        try {
          await manager.checkpoint(name);
        } catch (e) {
          error = e;
        }
        reader.execute('COMMIT');
      } finally {
        reader.close();
      }
      expect(error, isA<StateError>());

      await db.folderDao.createFolder(name: 'Still writable');
      await manager.checkpoint(name);
      expect(File('$path-wal').lengthSync(), 0);
      expect(
        readMainFileAlone(
          path,
          (copy) => count(copy, 'SELECT count(*) FROM folders'),
        ),
        2,
      );
    });

    test('on the short-lived connection, which it still closes', () async {
      final path = await manager.getDatabasePath('work');
      await Directory(p.dirname(path)).create(recursive: true);
      final writer = sqlite3.open(path);
      Object? error;
      try {
        writer.execute('PRAGMA journal_mode = WAL');
        writer.execute('PRAGMA wal_autocheckpoint = 0');
        writer.execute('CREATE TABLE t (v)');
        writer.execute('INSERT INTO t VALUES (1)');
        writer.execute('BEGIN');
        writer.select('SELECT * FROM t');
        try {
          await manager.checkpoint('work');
        } catch (e) {
          error = e;
        }
        writer.execute('COMMIT');
      } finally {
        writer.close();
      }
      expect(error, isA<StateError>());
      expect(AppDatabase.openInstanceOf('work'), isNull);
      // SQLite folds and removes the sidecar only as the last connection
      // closes: had the checkpoint's own connection stayed open, the
      // writer's close would not have been the last.
      expect(File('$path-wal').existsSync(), isFalse);
      expect(File(path).existsSync(), isTrue);
    });
  });

  test('a name stored as active but not yet open takes the file branch and '
      'opens nothing', () async {
    final path = await leaveInSidecar('later');
    await manager.setActiveDatabaseName('later');
    addTearDown(() => manager.setActiveDatabaseName('gym_notes'));
    expect(AppDatabase.openInstanceOf('later'), isNull);

    await manager.checkpoint('later');

    expect(walHasContent(path), isFalse);
    expect(
      readMainFileAlone(
        path,
        (copy) => count(copy, 'SELECT count(*) FROM items'),
      ),
      300,
    );
    expect(AppDatabase.openInstanceOf('later'), isNull);
  });

  // S18 (D11): the share hands over a `VACUUM INTO` copy, so no checkpoint —
  // which a reader can block — stands between a write and the shared file.
  group('the share snapshot', () {
    final snapshotFolder = RegExp(
      '^${DatabaseManager.shareSnapshotPrefix}\\d+\$',
    );

    /// The snapshot folders in the temp directory, by name.
    Set<String> snapshotFolders() => {
      for (final entity in tempDir.listSync())
        if (entity is Directory &&
            p.basename(entity.path).startsWith('anta_db_share_'))
          p.basename(entity.path),
    };

    tearDown(() {
      for (final name in snapshotFolders()) {
        Directory(p.join(tempDir.path, name)).deleteSync(recursive: true);
      }
    });

    test('the open database is copied beside the app\'s connection, the '
        'write still in its WAL included', () async {
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final path = await manager.getDatabasePath(name);
      await db.folderDao.createFolder(name: 'Latest');
      expect(walHasContent(path), isTrue);

      final snapshot = await manager.snapshotForShare(name);

      expect(p.basename(snapshot), '$name.db');
      expect(p.dirname(p.dirname(snapshot)), tempDir.path);
      expect(p.basename(p.dirname(snapshot)), matches(snapshotFolder));
      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        expect(
          count(copy, "SELECT count(*) FROM folders WHERE name = 'Latest'"),
          1,
        );
      } finally {
        copy.close();
      }
      // Nothing was folded to take it, and the app's connection is the same
      // one, still writing.
      expect(walHasContent(path), isTrue);
      expect(identical(await AppDatabase.getInstance(), db), isTrue);
      await db.folderDao.createFolder(name: 'After');
    });

    test('a copy of the open database that fails takes its folder with it and '
        'leaves the live database as it was', () async {
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      await db.folderDao.createFolder(name: 'Kept');
      // A full disk: part of the copy written, then SQLITE_FULL.
      DatabaseManager.debugSnapshotCopy = (source, snapshot) {
        File(snapshot).writeAsBytesSync([1, 2, 3]);
        throw SqliteException(
          extendedResultCode: 13,
          message: 'database or disk is full',
        );
      };
      addTearDown(() => DatabaseManager.debugSnapshotCopy = null);

      await expectLater(
        manager.snapshotForShare(name),
        throwsA(isA<SqliteException>()),
      );

      expect(snapshotFolders(), isEmpty);
      expect(identical(await AppDatabase.getInstance(), db), isTrue);
      final kept = await db.folderDao.getAllFolders(includeDeleted: false);
      expect([for (final folder in kept) folder.name], contains('Kept'));
      await db.folderDao.createFolder(name: 'After');
    });

    test('a missing database fails the copy and is never created', () async {
      final path = await manager.getDatabasePath('ghost');

      await expectLater(manager.snapshotForShare('ghost'), throwsA(anything));

      expect(File(path).existsSync(), isFalse);
      expect(snapshotFolders(), isEmpty);
    });

    test('a reader holding the WAL does not stop the copy', () async {
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final path = await manager.getDatabasePath(name);
      await db.folderDao.createFolder(name: 'In the WAL');
      final reader = sqlite3.open(path, mode: OpenMode.readWrite);
      addTearDown(reader.close);
      reader.execute('BEGIN');
      reader.select('SELECT count(*) FROM folders');

      final snapshot = await manager.snapshotForShare(name);
      reader.execute('COMMIT');

      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        expect(
          count(copy, "SELECT count(*) FROM folders WHERE name = 'In the WAL'"),
          1,
        );
      } finally {
        copy.close();
      }
    });

    test('a database that is not open is copied, sidecar included, and '
        'stays closed', () async {
      await leaveInSidecar('work');

      final snapshot = await manager.snapshotForShare('work');

      expect(p.basename(snapshot), 'work.db');
      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        expect(count(copy, 'SELECT count(*) FROM items'), 300);
      } finally {
        copy.close();
      }
      expect(AppDatabase.openInstanceOf('work'), isNull);
    });

    test('the next snapshot deletes the earlier ones and nothing else in the '
        'temp directory', () async {
      await leaveInSidecar('work');
      final earlier = Directory(
        p.join(tempDir.path, '${DatabaseManager.shareSnapshotPrefix}1'),
      )..createSync();
      File(p.join(earlier.path, 'work.db')).writeAsStringSync('old');
      final foreign = Directory(p.join(tempDir.path, 'another_app'))
        ..createSync();
      addTearDown(() => foreign.deleteSync(recursive: true));

      final snapshot = await manager.snapshotForShare('work');

      expect(earlier.existsSync(), isFalse);
      expect(foreign.existsSync(), isTrue);
      expect(snapshotFolders(), {p.basename(p.dirname(snapshot))});
    });

    // `SQLITE_FULL` cannot be staged here; a file SQLite refuses to read
    // fails the same statement on the same path.
    test('a copy that fails takes its folder with it', () async {
      final path = await manager.getDatabasePath('broken');
      await Directory(p.dirname(path)).create(recursive: true);
      await File(path).writeAsBytes([
        ...'SQLite format 3\u0000'.codeUnits,
        ...List.filled(84, 0),
      ]);

      await expectLater(manager.snapshotForShare('broken'), throwsA(anything));

      expect(snapshotFolders(), isEmpty);
    });
  });

  group('the memoized open', () {
    late SharedPreferencesStorePlatform previous;

    setUp(() {
      previous = SharedPreferencesStorePlatform.instance;
      DatabaseManager.resetForTesting();
    });

    tearDown(() {
      SharedPreferencesStorePlatform.instance = previous;
      SharedPreferences.resetStatic();
      DatabaseManager.resetForTesting();
    });

    test('two first callers share one manager, built before either reads '
        'it (final review X-11)', () async {
      final arrived = Completer<void>();
      final release = Completer<void>();
      ScriptedPrefsStore.install({'active_database': 'phone'}).onRead = (_) {
        if (!arrived.isCompleted) arrived.complete();
        return release.future;
      };
      final managers = <DatabaseManager>[];
      Future<String> readActiveName() async {
        final manager = await DatabaseManager.getInstance();
        managers.add(manager);
        return manager.getActiveDatabaseName();
      }

      final names = [readActiveName(), readActiveName()];
      await arrived.future;
      release.complete();

      expect(await Future.wait(names), ['phone', 'phone']);
      expect(identical(managers[0], managers[1]), isTrue);
    });

    test('an open that fails is not kept: the next call opens anew '
        '(final review X-7)', () async {
      final store = ScriptedPrefsStore.install()
        ..onRead = (read) {
          if (read == 1) throw StateError('the store is not ready');
        };

      await expectLater(DatabaseManager.getInstance(), throwsStateError);
      final retried = await DatabaseManager.getInstance();

      expect(retried.getActiveDatabaseName(), 'gym_notes');
      expect(identical(await DatabaseManager.getInstance(), retried), isTrue);
      expect(store.reads, 2);
    });
  });
}
