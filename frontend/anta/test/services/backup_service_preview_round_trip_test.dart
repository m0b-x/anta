import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/counter_service.dart';

/// Restore used to compute a preview of its own — `content.substring(0, 200)`,
/// newlines and every markdown marker kept — so a restored note's row read
/// differently from the same note saved by the editor, and the archived
/// preview was never consulted at all. The single generator is
/// [NoteMetadata.generatePreview]; this pins that the import path goes
/// through it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_backup_preview');
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

  test('a restored note carries the generated preview, not a raw slice',
      () async {
    const content =
        '# Wednesday heavy\n'
        '- 5 x 3 @ 140kg\n'
        '> [!note] belt on the last set\n'
        r'$+ 45.00 chalk and tape';
    const title = 'Restored heavy day';

    final archive = jsonEncode({
      'version': 1,
      'folders': <Map<String, dynamic>>[
        {JsonKeys.name: 'Training', JsonKeys.parentId: null},
      ],
      'notes': <Map<String, dynamic>>[
        {
          JsonKeys.folderId: 'root',
          JsonKeys.title: title,
          JsonKeys.content: content,
          JsonKeys.preview: 'a stale archived preview',
        },
      ],
      'settings': <String, dynamic>{},
    });

    final backup = await BackupService.getInstance();
    final result = await backup.importFromJson(archive);
    expect(result.success, isTrue, reason: 'error: ${result.error}');

    final db = await AppDatabase.getInstance();
    final notes = await db.noteDao.getAllNotes(includeDeleted: false);
    final restored = notes.firstWhere((n) => n.title == title);

    expect(restored.preview, NoteMetadata.generatePreview(content));
    expect(
      restored.preview,
      'Wednesday heavy 5 x 3 @ 140kg Note belt on the last set 45.00 chalk '
      'and tape',
    );
    expect(restored.preview, isNot(contains('\n')));
    expect(restored.preview, isNot(contains('#')));
    expect(restored.preview, isNot(contains('[!')));
  });

  test('a long note is capped exactly like an editor save', () async {
    final content = List.generate(60, (i) => '- item number $i').join('\n');
    const title = 'Restored long note';

    final archive = jsonEncode({
      'version': 1,
      'folders': const <Map<String, dynamic>>[],
      'notes': <Map<String, dynamic>>[
        {
          JsonKeys.folderId: 'root',
          JsonKeys.title: title,
          JsonKeys.content: content,
        },
      ],
      'settings': const <String, dynamic>{},
    });

    final backup = await BackupService.getInstance();
    final result = await backup.importFromJson(archive);
    expect(result.success, isTrue, reason: 'error: ${result.error}');

    final db = await AppDatabase.getInstance();
    final notes = await db.noteDao.getAllNotes(includeDeleted: false);
    final restored = notes.firstWhere((n) => n.title == title);

    expect(restored.preview, NoteMetadata.generatePreview(content));
    expect(restored.preview.length, 203);
    expect(restored.preview.endsWith('...'), isTrue);
  });
}
