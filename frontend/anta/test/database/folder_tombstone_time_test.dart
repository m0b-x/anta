import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/migrations.dart';

import 'support/db_test_support.dart';

/// Guards the unit of the folder cascade's timestamps.
///
/// `FolderDao.softDeleteFolderWithDescendants` once bound `deleted_at` and
/// `updated_at` as milliseconds in raw SQL where Drift stores unix seconds, so
/// every tombstone it wrote read back some fifty thousand years late. Nothing
/// on screen reads a tombstone's time; a sync engine does. v43 fixed the
/// binding and repairs the rows already written.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  test('a cascaded tombstone reads back at the instant it was made', () async {
    final parent = await db.folderDao.createFolder(name: 'Training');
    final child = await db.folderDao.createFolder(
      name: 'Legs',
      parentId: parent.id,
    );
    final note = await db.noteDao.createNote(
      folderId: child.id,
      title: 'Squats',
      preview: '',
      contentLength: 0,
      chunkCount: 0,
    );
    final before = DateTime.now();

    await db.folderDao.softDeleteFolderWithDescendants(parent.id);

    final after = DateTime.now();
    final folders = await db.select(db.folders).get();
    final notes = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(note.id))).get();
    // Drift keeps whole seconds, so the window widens by one on each side.
    for (final stamp in [
      for (final f in folders) ...[f.deletedAt!, f.updatedAt],
      notes.single.deletedAt!,
      notes.single.updatedAt,
    ]) {
      expect(
        stamp.isAfter(before.subtract(const Duration(seconds: 1))) &&
            stamp.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
        reason: '$stamp is not between $before and $after',
      );
    }
    expect(folders.every((f) => f.isDeleted), isTrue);
    expect(notes.single.isDeleted, isTrue);
  });

  group('the v43 repair', () {
    const millis = 1760000000000; // 2025-10-09, as milliseconds.
    const seconds = 1760000000; // The same instant, as Drift stores it.

    Future<void> insertFolder(String id, int deletedAt, int updatedAt) {
      return db.customStatement(
        'INSERT INTO folders (id, name, created_at, updated_at, '
        'hlc_timestamp, device_id, is_deleted, deleted_at) '
        "VALUES ('$id', '$id', $seconds, $updatedAt, 'h', 'd', 1, $deletedAt)",
      );
    }

    Future<void> runV43() {
      return DatabaseMigrations(db).runMigrations(
        db.createMigrator(),
        DatabaseSchema.v42CategoryAlertsAndDigests,
        DatabaseSchema.v43SyncReadiness,
      );
    }

    Future<Map<String, (int, int)>> stamps(String table) async {
      final rows = await db
          .customSelect('SELECT id, deleted_at, updated_at FROM $table')
          .get();
      return {
        for (final row in rows)
          row.read<String>('id'): (
            row.read<int>('deleted_at'),
            row.read<int>('updated_at'),
          ),
      };
    }

    test('fixes a millisecond row and leaves a seconds row alone', () async {
      await insertFolder('broken', millis, millis);
      await insertFolder('sound', seconds + 5, seconds + 5);
      await db.customStatement(
        'INSERT INTO notes (id, folder_id, title, created_at, updated_at, '
        'hlc_timestamp, device_id, is_deleted, deleted_at) '
        "VALUES ('n1', 'broken', 'Log', $seconds, $millis, 'h', 'd', 1, "
        '$millis)',
      );

      await runV43();

      expect(await stamps('folders'), {
        'broken': (seconds, seconds),
        'sound': (seconds + 5, seconds + 5),
      });
      expect(await stamps('notes'), {'n1': (seconds, seconds)});
    });

    test('re-running it divides nothing twice', () async {
      await insertFolder('broken', millis, millis);

      await runV43();
      await runV43();

      expect(await stamps('folders'), {'broken': (seconds, seconds)});
    });
  });
}
