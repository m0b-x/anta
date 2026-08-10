import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_notes_track_app/database/database.dart';

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
