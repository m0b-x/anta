import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:anta/database/database.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';

/// What `shareExport` leaves behind: a temporary export is deleted after the
/// share sheet returns, however it returned, and a file the app keeps —
/// `ExportResult.file`, the live database the Databases page shares — never
/// is (S6 of the settings rework, `docs/settings-rework-roadmap.md`).
///
/// Every file here is closed. On Windows an open file cannot be deleted at
/// all and `cleanupExport` swallows the failure, so a test over an open file
/// stays green whatever the guards do; on Android and macOS the delete would
/// go through and take the user's database with it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late AppDatabase db;
  late ImportExportService service;
  late Directory dir;

  setUp(() async {
    db = await openTestDatabase();
    final notes = NoteRepository(database: db);
    service = ImportExportService(
      noteStorage: NoteStorageService(repository: notes),
      folderStorage: FolderStorageService(
        repository: FolderRepository(database: db),
      ),
      noteRepository: notes,
    );
    dir = await Directory.systemTemp.createTemp('anta_export_result');
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(shareChannel, null);
    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  File write(String name) =>
      File(p.join(dir.path, name))..writeAsStringSync('payload');

  test('every export is temporary, a kept file is not', () {
    expect(const ExportResult(filePath: 'a').isTemporary, isTrue);
    expect(
      const ExportResult(
        filePath: 'a',
        isArchive: true,
        notesExported: 3,
      ).isTemporary,
      isTrue,
    );
    expect(const ExportResult.file('a').isTemporary, isFalse);
  });

  test('cleanup leaves a kept file and deletes a temporary export', () async {
    final kept = write('live.db');
    final temp = write('export.zip');

    await service.cleanupExport(ExportResult.file(kept.path));
    await service.cleanupExport(ExportResult(filePath: temp.path));

    expect(kept.readAsStringSync(), 'payload');
    expect(temp.existsSync(), isFalse);
  });

  test('a successful share keeps the kept file and deletes the temporary '
      'export', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      calls.add(call);
      return null;
    });
    final kept = write('live.db');
    final temp = write('export.zip');

    await service.shareExport(ExportResult.file(kept.path));
    await service.shareExport(ExportResult(filePath: temp.path));

    expect(calls, hasLength(2));
    expect(kept.readAsStringSync(), 'payload');
    expect(temp.existsSync(), isFalse);
  });

  test('a share that throws rethrows, keeps the kept file whole and still '
      'cleans the temporary export', () async {
    messenger.setMockMethodCallHandler(
      shareChannel,
      (call) async => throw PlatformException(code: 'share_failed'),
    );
    final kept = write('live.db');
    final temp = write('export.zip');

    await expectLater(
      service.shareExport(ExportResult.file(kept.path)),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(
      service.shareExport(ExportResult(filePath: temp.path)),
      throwsA(isA<PlatformException>()),
    );

    expect(kept.readAsStringSync(), 'payload');
    expect(temp.existsSync(), isFalse);
  });

  test('a share with no handler at all keeps the kept file whole', () async {
    final kept = write('live.db');

    await expectLater(
      service.shareExport(ExportResult.file(kept.path)),
      throwsA(isA<MissingPluginException>()),
    );

    expect(kept.readAsStringSync(), 'payload');
  });
}
