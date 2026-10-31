import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/import_export/import_export_event.dart';
import 'package:anta/bloc/import_export/import_export_state.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/export_format.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';

/// Share report (K): a page's composed text goes through the import/export
/// bloc as one file in the temp directory, handed to `shareExport` once —
/// the page never reaches `SharePlus`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late _SharingService service;
  late ImportExportBloc bloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_export_text');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    db = await openTestDatabase();
    final notes = NoteRepository(database: db);
    service = _SharingService(
      noteStorage: NoteStorageService(repository: notes),
      folderStorage: FolderStorageService(
        repository: FolderRepository(database: db),
      ),
      noteRepository: notes,
    );
    bloc = ImportExportBloc(service: service);
  });

  tearDown(() async {
    await bloc.close();
    await db.close();
  });

  /// German, so the file round-trips more than ASCII.
  const text = '# Bericht · März 2026\n\n31 Termine · 1 verpasst\n';

  test('writes the text to the named file and shares it once', () async {
    final states = <ImportExportState>[];
    final heard = bloc.stream.listen(states.add);
    addTearDown(heard.cancel);
    final done = bloc.stream.firstWhere(
      (state) => state is! ImportExportInProgress,
    );
    bloc.add(
      const ExportTextRequested(
        fileName: 'anta_report_20260301-20260331.md',
        text: text,
        format: ExportFormat.markdown,
      ),
    );
    final end = await done;

    expect(states.first, isA<ImportExportInProgress>());
    expect(
      (states.first as ImportExportInProgress).operation,
      ImportExportOperation.exportText,
    );
    expect(end, isA<ImportExportExportSuccess>());
    final result = (end as ImportExportExportSuccess).result;
    expect(end.operation, ImportExportOperation.exportText);
    expect(result.format, ExportFormat.markdown);
    expect(result.eventsExported, 0);
    expect(
      result.filePath,
      '${tempDir.path}${Platform.pathSeparator}anta_report_20260301-20260331.md',
    );
    expect(service.shared, hasLength(1));
    expect(service.shared.single.filePath, result.filePath);
    expect(service.sharedText.single, text);
  });

  test('share: false writes the file and shares nothing', () async {
    final done = bloc.stream.firstWhere(
      (state) => state is! ImportExportInProgress,
    );
    bloc.add(
      const ExportTextRequested(
        fileName: 'kept.md',
        text: text,
        format: ExportFormat.markdown,
        share: false,
      ),
    );
    final end = await done as ImportExportExportSuccess;
    expect(service.shared, isEmpty);
    expect(await File(end.result.filePath).readAsString(), text);
    await service.cleanupExport(end.result);
  });

  test('a write that fails mid-file fails the export and leaves no file '
      '(D46)', () async {
    final failing = ImportExportBloc(
      service: _FailingWriteService(
        noteStorage: NoteStorageService(
          repository: NoteRepository(database: db),
        ),
        folderStorage: FolderStorageService(
          repository: FolderRepository(database: db),
        ),
        noteRepository: NoteRepository(database: db),
      ),
    );
    addTearDown(failing.close);
    final done = failing.stream.firstWhere(
      (state) => state is! ImportExportInProgress,
    );
    failing.add(
      const ExportTextRequested(
        fileName: 'anta_report_half.md',
        text: text,
        format: ExportFormat.markdown,
      ),
    );
    final end = await done;

    expect(end, isA<ImportExportFailure>());
    expect(
      (end as ImportExportFailure).operation,
      ImportExportOperation.exportText,
    );
    expect(
      File(
        '${tempDir.path}${Platform.pathSeparator}anta_report_half.md',
      ).existsSync(),
      isFalse,
    );
  });

  test('the file name is a bare name with the format\'s extension', () async {
    for (final fileName in ['report.txt', 'nested/report.md', 'report']) {
      await expectLater(
        service.exportText(
          fileName: fileName,
          text: text,
          format: ExportFormat.markdown,
        ),
        throwsAssertionError,
        reason: fileName,
      );
    }
  });
}

/// Writes the first half of the text, then fails, as a full disk would.
class _FailingWriteService extends ImportExportService {
  _FailingWriteService({
    required super.noteStorage,
    required super.folderStorage,
    required super.noteRepository,
  });

  @override
  Future<void> writeExportText(File file, String text) async {
    await file.writeAsString(text.substring(0, text.length ~/ 2));
    throw const FileSystemException('No space left on device');
  }
}

/// The real service with only the share sheet stubbed: it reads the file
/// back at the moment it is shared, then cleans it up as the real one does.
class _SharingService extends ImportExportService {
  _SharingService({
    required super.noteStorage,
    required super.folderStorage,
    required super.noteRepository,
  });

  final List<ExportResult> shared = [];
  final List<String> sharedText = [];

  @override
  Future<void> shareExport(ExportResult result) async {
    shared.add(result);
    sharedText.add(await File(result.filePath).readAsString());
    await cleanupExport(result);
  }
}
