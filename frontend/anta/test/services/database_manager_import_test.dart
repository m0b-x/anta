import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/services/database_manager.dart';

import '../widgets/support/settings_platform_fakes.dart';

/// The import's real verifier (S19, `docs/scalability-roadmap.md`) against
/// real files, and the copy around it: a file is renamed in as a database
/// only once it is whole SQLite, no newer than this build, and ANTA's; every
/// other outcome leaves nothing behind. The widget suites fake the verifier,
/// since SQLite cannot run under `FakeAsync`; this suite is where it runs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseManager manager;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_db_import');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    manager = await DatabaseManager.getInstance();
  });

  tearDown(() async {
    DatabaseManager.debugImportChunkWritten = null;
    manager.verifyImport = DatabaseManager.verifyImportFile;
    await AppDatabase.deleteAllData();
    final picked = Directory(p.join(tempDir.path, 'picked'));
    if (await picked.exists()) await picked.delete(recursive: true);
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  String picked(String name) => p.join(tempDir.path, 'picked', name);

  /// Every file in the databases directory, by name.
  Future<Set<String>> databaseDirectory() async {
    final dir = Directory(await manager.getDatabaseDirectory());
    if (!await dir.exists()) return {};
    return {await for (final entity in dir.list()) p.basename(entity.path)};
  }

  int notesIn(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      return db.select('SELECT count(*) AS n FROM notes').single['n'] as int;
    } finally {
      db.close();
    }
  }

  group('the verifier', () {
    test('accepts a rollback-journal database, as a share writes it', () async {
      final file = await writeSqliteFile(picked('share.db'), notes: 20);
      final header = file.readAsBytesSync().sublist(18, 20);
      expect(header, [1, 1]);

      await DatabaseManager.verifyImportFile(file.path);
    });

    test(
      'accepts a WAL-flagged database, as an older share wrote it',
      () async {
        final path = picked('older.db');
        await writeSqliteFile(path, notes: 20);
        final db = sqlite3.open(path);
        db.execute('PRAGMA journal_mode = WAL');
        db.close();
        expect(File(path).readAsBytesSync().sublist(18, 20), [2, 2]);
        expect(File('$path-wal').existsSync(), isFalse);

        await DatabaseManager.verifyImportFile(path);
      },
    );

    test('refuses a truncated file: its pages outrun its length', () async {
      final path = picked('truncated.db');
      await writeSqliteFile(path, notes: 400);
      final bytes = File(path).readAsBytesSync();
      File(path).writeAsBytesSync(bytes.sublist(0, bytes.length - 4096));

      await expectLater(
        DatabaseManager.verifyImportFile(path),
        throwsA(isA<DatabaseImportCorrupt>()),
      );
    });

    test(
      'refuses a file whose header is sound and whose pages are garbage',
      () async {
        final path = picked('garbage.db');
        await writeSqliteFile(path, notes: 400);
        final bytes = File(path).readAsBytesSync();
        const pageSize = 4096;
        // Page 1 — the header and the schema — stays; every later page is
        // overwritten, the length kept, so only quick_check can tell.
        for (var i = pageSize; i < bytes.length; i++) {
          bytes[i] = (i * 31 + 7) & 0xff;
        }
        File(path).writeAsBytesSync(bytes);

        await expectLater(
          DatabaseManager.verifyImportFile(path),
          throwsA(isA<DatabaseImportCorrupt>()),
        );
      },
    );

    test('refuses a file with only the SQLite magic', () async {
      final file = await writeSqliteHeaderFile(picked('header.db'));

      await expectLater(
        DatabaseManager.verifyImportFile(file.path),
        throwsA(isA<DatabaseImportCorrupt>()),
      );
    });

    test('refuses a sound SQLite file without ANTA\'s tables', () async {
      final file = await writeSqliteFile(
        picked('recipes.db'),
        shape: SqliteFileShape.foreign,
      );

      await expectLater(
        DatabaseManager.verifyImportFile(file.path),
        throwsA(isA<DatabaseImportNotAnta>()),
      );
    });

    // At the current version Drift migrates nothing, so every query would
    // throw; at 0 its `onCreate` would add ANTA's tables beside the foreign
    // ones (`IF NOT EXISTS` keeps these) and stamp the file current.
    for (final version in [0, DatabaseSchema.currentVersion]) {
      test('refuses ANTA\'s three table names over another app\'s columns at '
          'version $version', () async {
        final file = await writeSqliteFile(
          picked('names_only.db'),
          shape: SqliteFileShape.antaNamesOnly,
          userVersion: version,
        );

        await expectLater(
          DatabaseManager.verifyImportFile(file.path),
          throwsA(isA<DatabaseImportNotAnta>()),
        );
      });
    }

    test(
      'refuses ANTA\'s own tables at version 0, which no ANTA wrote',
      () async {
        final file = await writeSqliteFile(picked('zero.db'), userVersion: 0);

        await expectLater(
          DatabaseManager.verifyImportFile(file.path),
          throwsA(isA<DatabaseImportNotAnta>()),
        );
      },
    );

    test('an older file needs only the first schema\'s columns; the current '
        'version needs the current ones', () async {
      Future<String> firstSchema(String name, int version) async {
        final path = picked(name);
        await Directory(p.dirname(path)).create(recursive: true);
        final db = sqlite3.open(path);
        try {
          db.execute('CREATE TABLE folders (id TEXT PRIMARY KEY, name TEXT)');
          db.execute(
            'CREATE TABLE notes (id TEXT PRIMARY KEY, folder_id TEXT, '
            'title TEXT)',
          );
          db.execute(
            'CREATE TABLE content_chunks (id TEXT PRIMARY KEY, note_id TEXT, '
            'chunk_index INTEGER, content TEXT)',
          );
          db.execute('PRAGMA user_version = $version');
        } finally {
          db.close();
        }
        return path;
      }

      await DatabaseManager.verifyImportFile(await firstSchema('v1.db', 1));
      await expectLater(
        DatabaseManager.verifyImportFile(
          await firstSchema('current.db', DatabaseSchema.currentVersion),
        ),
        throwsA(isA<DatabaseImportNotAnta>()),
      );
    });

    test(
      'refuses a database from a newer schema, naming its version',
      () async {
        final newer = DatabaseSchema.currentVersion + 1;
        final file = await writeSqliteFile(
          picked('newer.db'),
          userVersion: newer,
        );

        await expectLater(
          DatabaseManager.verifyImportFile(file.path),
          throwsA(
            isA<DatabaseImportTooNew>().having(
              (e) => e.version,
              'version',
              newer,
            ),
          ),
        );
      },
    );
  });

  group('the import', () {
    test('a WAL source arrives with the rows its sidecar held, folded into '
        'one file', () async {
      final source = picked('live.db');
      await writeSqliteFile(source, notes: 300, inSidecar: true);
      expect(File('$source-wal').lengthSync(), greaterThan(0));

      final progress = DatabaseImportProgress();
      final seen = <(DatabaseImportPhase, double)>[];
      progress.addListener(() => seen.add((progress.phase, progress.fraction)));
      await manager.importDatabase(source, 'live', progress: progress);

      // Read before the rows are counted: a read-only reader of a WAL-mode
      // file leaves sidecars of its own.
      expect(await databaseDirectory(), {'live.db'});
      final target = await manager.getDatabasePath('live');
      expect(notesIn(target), 300);
      expect(seen.first.$1, DatabaseImportPhase.copying);
      expect(seen.last, (DatabaseImportPhase.verifying, 1.0));
    });

    test(
      'a verified rollback-journal source is copied byte for byte',
      () async {
        final source = await writeSqliteFile(picked('share.db'), notes: 50);

        await manager.importDatabase(source.path, 'share');

        final target = File(await manager.getDatabasePath('share'));
        expect(target.readAsBytesSync(), source.readAsBytesSync());
      },
    );

    test('an imported file arrives without its replica id, so its first tap '
        'mints its own (S20)', () async {
      final source = await writeSqliteFile(picked('bound.db'), notes: 5);
      final writer = sqlite3.open(source.path);
      try {
        writer.execute(
          'CREATE TABLE sync_metadata (key TEXT PRIMARY KEY, value TEXT, '
          'updated_at INTEGER)',
        );
        writer.execute(
          "INSERT INTO sync_metadata VALUES ('replica_id', 'source-replica', 0), "
          "('device_id', 'source-device', 0)",
        );
      } finally {
        writer.close();
      }

      await manager.importDatabase(source.path, 'bound');

      final target = sqlite3.open(
        await manager.getDatabasePath('bound'),
        mode: OpenMode.readOnly,
      );
      try {
        final keys = {
          for (final row in target.select('SELECT key FROM sync_metadata'))
            row['key'],
        };
        expect(keys, {'device_id'});
      } finally {
        target.close();
      }
    });

    test('a refused file leaves nothing behind and is never listed', () async {
      final source = await writeSqliteFile(
        picked('newer.db'),
        userVersion: DatabaseSchema.currentVersion + 1,
      );

      await expectLater(
        manager.importDatabase(source.path, 'newer'),
        throwsA(isA<DatabaseImportTooNew>()),
      );

      expect(await manager.databaseExists('newer'), isFalse);
      expect(await databaseDirectory(), isEmpty);
    });

    test('a cancel between two chunks deletes the partial copy, sidecar '
        'included, and never verifies', () async {
      final source = picked('big.db');
      await writeSqliteFile(source, notes: 9000, inSidecar: true);
      expect(File(source).lengthSync(), lessThan(1 << 20));
      expect(File('$source-wal').lengthSync(), greaterThan(1 << 20));

      final progress = DatabaseImportProgress();
      final held = Completer<void>();
      final release = Completer<void>();
      var chunks = 0;
      // The main file is one chunk; the second is the sidecar's first.
      DatabaseManager.debugImportChunkWritten = () async {
        if (++chunks < 2) return;
        if (!held.isCompleted) held.complete();
        await release.future;
      };
      var verified = false;
      manager.verifyImport = (_) async => verified = true;

      final import = manager.importDatabase(source, 'big', progress: progress);
      await held.future;
      // The main file is in and the sidecar's first chunk written.
      expect(
        (await databaseDirectory()).where((n) => n.contains('.db.import-')),
        hasLength(2),
      );
      progress.cancel();
      release.complete();

      await expectLater(import, throwsA(isA<DatabaseImportCancelled>()));
      expect(verified, isFalse);
      expect(await databaseDirectory(), isEmpty);
    });

    test('a Cancel taken after the last chunk still cancels, before the '
        'check', () async {
      final source = await writeSqliteFile(picked('small.db'), notes: 10);
      final progress = DatabaseImportProgress();
      // The file is one chunk: the copy's loop never looks again.
      DatabaseManager.debugImportChunkWritten = () async => progress.cancel();
      var verified = false;
      manager.verifyImport = (_) async => verified = true;

      await expectLater(
        manager.importDatabase(source.path, 'small', progress: progress),
        throwsA(isA<DatabaseImportCancelled>()),
      );
      expect(progress.phase, DatabaseImportPhase.copying);
      expect(verified, isFalse);
      expect(await databaseDirectory(), isEmpty);
    });

    test('a rollback-mode source copied mid-transaction arrives rolled back: '
        'its hot journal comes too', () async {
      final writerPath = picked('writer.db');
      await writeSqliteFile(writerPath, notes: 2000);
      final source = picked('mid.db');
      final writer = sqlite3.open(writerPath);
      try {
        // A small cache spills the UPDATE's pages into the main file before
        // the commit, the originals saved in the journal.
        writer.execute('PRAGMA cache_size = 10');
        writer.execute('BEGIN');
        writer.execute("UPDATE notes SET title = 'torn'");
        File(writerPath).copySync(source);
        File('$writerPath-journal').copySync('$source-journal');
      } finally {
        writer.execute('ROLLBACK');
        writer.close();
      }
      int torn(String path) {
        final db = sqlite3.open(path, mode: OpenMode.readOnly);
        try {
          return db
                  .select(
                    "SELECT count(*) AS n FROM notes WHERE title = 'torn'",
                  )
                  .single['n']
              as int;
        } finally {
          db.close();
        }
      }

      // Not vacuous: the main file alone holds the uncommitted rows.
      final alone = picked('alone.db');
      File(source).copySync(alone);
      expect(torn(alone), greaterThan(0));

      await manager.importDatabase(source, 'mid');

      expect(await databaseDirectory(), {'mid.db'});
      final target = await manager.getDatabasePath('mid');
      expect(torn(target), 0);
      expect(notesIn(target), 2000);
    });

    test('an orphan sidecar beside the target is deleted before the rename, '
        'never replayed over the import', () async {
      final source = await writeSqliteFile(picked('share.db'), notes: 50);
      final foreign = picked('foreign.db');
      await writeSqliteFile(foreign, notes: 7, inSidecar: true);
      final target = await manager.getDatabasePath('share');
      await Directory(p.dirname(target)).create(recursive: true);
      File('$foreign-wal').copySync('$target-wal');
      File('$target-shm').writeAsStringSync('stale');

      await manager.importDatabase(source.path, 'share');

      expect(await databaseDirectory(), {'share.db'});
      expect(notesIn(target), 50);
    });
  });

  test('the launch sweep deletes an import\'s temporary files and nothing '
      'else', () async {
    final dir = await manager.getDatabaseDirectory();
    await Directory(dir).create(recursive: true);
    const temps = [
      'travel.db.import-1731000000000',
      'travel.db.import-1731000000000-wal',
      'travel.db.import-1731000000000-shm',
      'travel.db.import-1731000000000-journal',
    ];
    const kept = [
      'gym_notes.db',
      'gym_notes.db-wal',
      'travel.db.import-',
      'travel.db.import-notes',
      'notes.txt',
    ];
    for (final name in [...temps, ...kept]) {
      File(p.join(dir, name)).writeAsStringSync('x');
    }

    await manager.sweepStaleImports();

    expect(await databaseDirectory(), kept.toSet());
    for (final name in kept) {
      File(p.join(dir, name)).deleteSync();
    }
  });
}
