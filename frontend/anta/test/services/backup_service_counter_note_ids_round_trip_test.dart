// An isolate-backed file database, as the other backup round trips.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

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
}
