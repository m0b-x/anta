import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:anta/database/database.dart';
import 'package:anta/services/database_manager.dart';

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
}
