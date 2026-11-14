import 'dart:io';
import 'dart:isolate';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:anta/constants/app_constants.dart';
import 'package:anta/database/database.dart';

/// A second connection to [path], configured as the app configures one,
/// writing a row from an isolate of its own — where the app's connection
/// lives too, so its wait does not hold this isolate. How long the write
/// took, in milliseconds.
Future<int> _writeFromAnotherIsolate(String path) => Isolate.run(() {
  final other = sqlite3.open(path);
  try {
    configureSqliteConnection(other);
    final waited = Stopwatch()..start();
    other.execute('INSERT INTO t VALUES (2)');
    return waited.elapsedMilliseconds;
  } finally {
    other.close();
  }
});

/// Guards the connection pragmas, which are worth roughly a **20×** speedup on
/// the app's dominant write shape (many small auto-save commits: 561 ms → 28 ms
/// for 200 individually-committed inserts on a real file).
///
/// A setting that valuable and that invisible needs a test — dropping the
/// `setup:` callback would compile, pass every other test, and silently return
/// the app to stock SQLite defaults. In-memory databases never journal, so this
/// is the one suite that has to touch the filesystem.
void main() {
  late Directory dir;
  late AppDatabase db;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pragma_test');
    db = AppDatabase.forTesting(
      NativeDatabase(
        File('${dir.path}/app.sqlite'),
        setup: configureSqliteConnection,
      ),
    );
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<Object?> pragma(String name) async {
    final row = await db.customSelect('PRAGMA $name').getSingle();
    return row.data.values.first;
  }

  test('runs in WAL mode', () async {
    // Readers stop blocking on the writer, and a commit appends to the log
    // instead of rewriting a rollback journal.
    expect(await pragma('journal_mode'), 'wal');
  });

  test('uses synchronous = NORMAL', () async {
    // 1 == NORMAL. Only safe *because* of WAL: an app crash loses nothing, and
    // a power cut can roll back recent transactions but cannot corrupt the
    // file. Raising this back to FULL costs ~5x on small writes.
    expect(await pragma('synchronous'), 1);
  });

  test('sorts and spills in memory', () async {
    // 2 == MEMORY. The folder list sorted by title/date builds a temp B-tree;
    // this keeps it off the filesystem.
    expect(await pragma('temp_store'), 2);
  });

  test('has a page cache sized in kibibytes, not pages', () async {
    // Negative values mean KiB and are page-size independent. The exact number
    // matters least of the four — but a positive value here would mean someone
    // reintroduced the page-count form by accident.
    expect(await pragma('cache_size'), lessThan(0));
  });

  test('caps the WAL a checkpoint leaves behind', () async {
    // Without it the `-wal` keeps the size of the largest transaction it
    // ever held — a migration step or an Optimize leaves one the size of the
    // database on the phone for good.
    expect(
      await pragma('journal_size_limit'),
      AppConstants.sqliteJournalSizeLimitBytes,
    );
  });

  test(
    'waits for another connection\'s write rather than failing at once',
    () async {
      // Zero is SQLite's default: "database is locked" within a millisecond.
      expect(AppConstants.sqliteBusyTimeout, const Duration(seconds: 5));
      expect(
        await pragma('busy_timeout'),
        AppConstants.sqliteBusyTimeout.inMilliseconds,
      );
    },
  );

  test('a second writer configured as the app configures one waits for the '
      'first\'s commit and then writes — the shared check\'s run and the '
      'app, in the bounded windows where the handshake cannot keep them '
      'apart', () async {
    final path = '${dir.path}/two.sqlite';
    final first = sqlite3.open(path);
    addTearDown(first.close);
    configureSqliteConnection(first);
    first
      ..execute('CREATE TABLE t (x INTEGER)')
      ..execute('BEGIN IMMEDIATE')
      ..execute('INSERT INTO t VALUES (1)');

    final second = _writeFromAnotherIsolate(path);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    first.execute('COMMIT');

    expect(await second, greaterThanOrEqualTo(200));
    expect(first.select('SELECT x FROM t ORDER BY x').map((row) => row['x']), [
      1,
      2,
    ]);
  });

  test('WAL sidecars land beside the database file', () async {
    // DatabaseManager renames and deletes `-wal` / `-shm` alongside the main
    // file. If WAL ever produced differently-named sidecars, the
    // multi-database feature would start orphaning them.
    final now = DateTime.now();
    await db
        .into(db.folders)
        .insert(
          FoldersCompanion.insert(
            id: 'probe',
            name: 'Probe',
            hlcTimestamp: '0',
            deviceId: 'test',
            createdAt: now,
            updatedAt: now,
          ),
        );
    expect(await File('${dir.path}/app.sqlite-wal').exists(), isTrue);
  });
}
