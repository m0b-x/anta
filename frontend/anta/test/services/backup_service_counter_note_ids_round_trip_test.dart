// An isolate-backed file database, as the other backup round trips.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/counter.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/counter_service.dart';

/// A restore gives every note a fresh id, so the per-note counter values,
/// their pins, positions and owners have to follow the note to its new id —
/// once a database syncs, a value under a note id that exists nowhere is
/// copied to every device and no later restore clears it. The global value
/// keeps its empty note id.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_backup_counters');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    GetIt.I.registerSingleton<CounterService>(
      await CounterService.getInstance(),
    );
  });

  tearDownAll(() async {
    await GetIt.I.reset();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('a per-note counter value, pin, position and owner come back under '
      "the restored note's new id; the global value is unchanged", () async {
    const archivedNoteId = 'archived-note';
    const title = 'Leg day';
    final createdAt = DateTime(2026, 11, 1);

    final archive = jsonEncode({
      'version': 7,
      'folders': const <Map<String, dynamic>>[],
      'notes': <Map<String, dynamic>>[
        {
          JsonKeys.id: archivedNoteId,
          JsonKeys.folderId: 'root',
          JsonKeys.title: title,
          JsonKeys.content: 'squats',
        },
      ],
      'settings': const <String, dynamic>{},
      'counterData': {
        'counters': jsonEncode([
          Counter(id: 'sets', name: 'Sets', createdAt: createdAt).toJson(),
          Counter(
            id: 'laps',
            name: 'Laps',
            scope: CounterScope.perNote,
            createdAt: createdAt,
          ).toJson(),
        ]),
        'globalValues': jsonEncode({'sets': 4}),
        'noteValues': jsonEncode({
          archivedNoteId: {'laps': 7},
        }),
        'noteValueExtras': jsonEncode({
          'sets::': {'ownerId': 'owner-1'},
          'laps::$archivedNoteId': {
            'ownerId': 'owner-1',
            'isPinned': true,
            'position': 3,
          },
        }),
      },
    });

    final backup = await BackupService.getInstance();
    final result = await backup.importFromJson(archive);
    expect(result.success, isTrue, reason: 'error: ${result.error}');

    final db = await AppDatabase.getInstance();
    final notes = await db.noteDao.getAllNotes(includeDeleted: false);
    final restoredId = notes.firstWhere((n) => n.title == title).id;
    expect(restoredId, isNot(archivedNoteId));

    final values = await db.counterDao.getAllValues();
    final perNote = values.where((v) => v.counterId == 'laps').toList();
    expect(perNote.map((v) => v.noteId), [restoredId]);
    expect(perNote.single.value, 7);
    expect(perNote.single.isPinned, isTrue);
    expect(perNote.single.position, 3);
    expect(perNote.single.ownerId, 'owner-1');

    final global = values.singleWhere((v) => v.counterId == 'sets');
    expect(global.noteId, '');
    expect(global.value, 4);
    expect(global.ownerId, 'owner-1');
  });

  /// Folders and notes are the two tables an import appends to; wiping them
  /// is what lets a restored row be found by its name.
  Future<AppDatabase> wipe() async {
    final db = await AppDatabase.getInstance();
    await db.customStatement('DELETE FROM notes');
    await db.customStatement('DELETE FROM folders');
    await db.counterDao.deleteAll();
    return db;
  }

  test("a per-note value under a note the archive did not carry is dropped; "
      'an archive without notes keeps every archived id', () async {
    await wipe();
    final createdAt = DateTime(2026, 11, 1);
    Map<String, dynamic> counterData() => {
      'counters': jsonEncode([
        Counter(
          id: 'laps',
          name: 'Laps',
          scope: CounterScope.perNote,
          createdAt: createdAt,
        ).toJson(),
      ]),
      'globalValues': jsonEncode(const <String, int>{}),
      'noteValues': jsonEncode({
        'gone-note': {'laps': 9},
      }),
      'noteValueExtras': jsonEncode({
        'laps::gone-note': {
          'ownerId': 'owner-1',
          'isPinned': true,
          'position': 2,
        },
      }),
    };
    final backup = await BackupService.getInstance();
    final db = await AppDatabase.getInstance();

    final withNotes = await backup.importFromJson(
      jsonEncode({
        'version': 7,
        'folders': const <Map<String, dynamic>>[],
        'notes': <Map<String, dynamic>>[
          {
            JsonKeys.id: 'kept-note',
            JsonKeys.folderId: '',
            JsonKeys.title: 'Kept',
            JsonKeys.content: '',
          },
        ],
        'settings': const <String, dynamic>{},
        'counterData': counterData(),
      }),
    );
    expect(withNotes.success, isTrue, reason: 'error: ${withNotes.error}');
    expect(await db.counterDao.getAllValues(), isEmpty);

    // No notes, so no map: the archived id stands, as before the fix.
    final withoutNotes = await backup.importFromJson(
      jsonEncode({
        'version': 7,
        'folders': const <Map<String, dynamic>>[],
        'notes': const <Map<String, dynamic>>[],
        'settings': const <String, dynamic>{},
        'counterData': counterData(),
      }),
    );
    expect(
      withoutNotes.success,
      isTrue,
      reason: 'error: ${withoutNotes.error}',
    );
    final kept = (await db.counterDao.getAllValues()).single;
    expect(kept.noteId, 'gone-note');
    expect(kept.value, 9);
    expect(kept.isPinned, isTrue);
    expect(kept.position, 2);
    expect(kept.ownerId, 'owner-1');
  });

  test(
    "BackupService's own export restores per-note values, pins and "
    'positions under the new note ids, and drops a deleted note\'s',
    () async {
      final db = await wipe();
      final folder = await db.folderDao.createFolder(name: 'Gym');
      final kept = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Leg day',
      );
      final deleted = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Old plan',
      );
      await db.noteDao.softDeleteNote(deleted.id);
      final now = DateTime.now();
      await db.counterDao.insertCounter(
        CountersCompanion.insert(id: 'sets', name: 'Sets', createdAt: now),
      );
      await db.counterDao.insertCounter(
        CountersCompanion.insert(
          id: 'laps',
          name: 'Laps',
          createdAt: now,
          scope: const Value('perNote'),
        ),
      );
      await db.counterDao.upsertValue('sets', '', 4, ownerId: 'owner-1');
      await db.counterDao.upsertValue('laps', kept.id, 7);
      await db.counterDao.setNoteValuePinned('laps', kept.id, true);
      await db.counterDao.updateNoteValuePositions('laps', {kept.id: 3});
      await db.counterDao.upsertValue('laps', deleted.id, 5);

      final backup = await BackupService.getInstance();
      final exported = jsonEncode(await backup.exportAllData());
      await db.customStatement('DELETE FROM notes');
      await db.customStatement('DELETE FROM folders');
      final result = await backup.importFromJson(exported);
      expect(result.success, isTrue, reason: 'error: ${result.error}');

      final notes = await db.noteDao.getAllNotes(includeDeleted: false);
      final restoredId = notes.singleWhere((n) => n.title == 'Leg day').id;
      expect(restoredId, isNot(kept.id));

      final values = await db.counterDao.getAllValues();
      final perNote = values.where((v) => v.counterId == 'laps').toList();
      expect(perNote.map((v) => v.noteId), [restoredId]);
      expect(perNote.single.value, 7);
      expect(perNote.single.isPinned, isTrue);
      expect(perNote.single.position, 3);

      final global = values.singleWhere((v) => v.counterId == 'sets');
      expect(global.noteId, '');
      expect(global.value, 4);
      expect(global.ownerId, 'owner-1');
    },
  );
}
