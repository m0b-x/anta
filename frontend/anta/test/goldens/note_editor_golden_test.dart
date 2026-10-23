@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/counter/counter_bloc.dart';
import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/bloc/optimized_note/optimized_note_bloc.dart';
import 'package:anta/bloc/optimized_note/optimized_note_event.dart';
import 'package:anta/bloc/optimized_note/optimized_note_state.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/pages/optimized_note_editor_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

import '../widgets/support/layout_errors.dart';
import 'support/golden_matrix.dart';

/// The note editor on a note that shows its grammar — a heading, a list, a
/// task and two money lines — harnessed as
/// `test/widgets/optimized_note_editor_page_test.dart` harnesses it: a real
/// note bloc whose load is inert, so the test hands it the content.
///
/// The editor's body has no font family of its own (it follows the
/// platform's), so its text stays in the test font while the chrome around
/// it is Roboto; on a phone both are Roboto.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const folderId = 'folder-1';
  const noteId = 'note-1';
  const content =
      '# Leg day\n'
      '- Squat 5 x 5\n'
      '- Bench 3 x 8\n'
      '- [ ] Stretch\n'
      '\$= 100\n'
      '\$- 12.50\n';

  final metadata = NoteMetadata(
    id: noteId,
    folderId: folderId,
    title: 'Training log',
    preview: 'Leg day',
    contentLength: content.length,
    chunkCount: 1,
    isCompressed: false,
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
  );

  late Directory tempDir;
  late AppDatabase db;
  late _TestNoteBloc noteBloc;
  late MarkdownBarBloc barBloc;
  late CounterBloc counterBloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_golden_note_editor');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    // Every database open and read happens here, in real async: inside a
    // test body the database answers on an isolate `FakeAsync` never lets
    // run.
    db = await AppDatabase.getInstance();
    await db.customSelect('SELECT 1').get();
    final settings = await SettingsService.getInstance();
    await settings.setShowLineNumbers(false);
    await settings.setLiveMarkdownRendering(true);
    final storageService = NoteStorageService(
      repository: NoteRepository(database: db),
    );
    await storageService.initialize();
    final searchService = FolderSearchService(storageService: storageService);
    await searchService.initialize();
    final folderService = FolderStorageService(
      repository: FolderRepository(database: db),
    );
    await folderService.initialize();
    noteBloc = _TestNoteBloc(
      storageService: storageService,
      searchService: searchService,
    );
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.getInstance(),
    );
    counterBloc = CounterBloc(
      counterService: await CounterService.getInstance(),
    );
    GetIt.I.registerSingleton<NoteStorageService>(storageService);
    GetIt.I.registerSingleton<FolderStorageService>(folderService);
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());
  });

  tearDownAll(() async {
    await noteBloc.close();
    await barBloc.close();
    await counterBloc.close();
    await GetIt.I.reset();
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  // A listener only fires on a state change, so the shared bloc drops back
  // to its initial state before each cell hands it the note again.
  setUp(() => noteBloc.reset());

  /// Real time for the database, then the frames its answers asked for.
  Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 5));
    }
  }

  final editor = find.byType(ModernEditorWrapper);

  for (final cell in goldenCells) {
    testWidgets('note editor, ${cell.label}', (tester) async {
      setGoldenSurface(tester, cell);
      final errors = await layoutErrorsDuring(() async {
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<OptimizedNoteBloc>.value(value: noteBloc),
              BlocProvider<MarkdownBarBloc>.value(value: barBloc),
              BlocProvider<CounterBloc>.value(value: counterBloc),
            ],
            child: goldenApp(
              cell,
              navigatorObservers: [AppNavigator.routeObserver],
              home: const OptimizedNoteEditorPage(
                folderId: folderId,
                noteId: noteId,
              ),
            ),
          ),
        );
        noteBloc.emitContentLoaded(metadata, content);
        await tester.pump();
        for (var i = 0; i < 200 && editor.evaluate().isEmpty; i++) {
          await settle(tester, rounds: 1);
        }
        await settle(tester);
        // Past the editor's first-frame fade-in.
        await tester.pump(const Duration(milliseconds: 300));
      });

      expect(errors, isEmpty);
      expect(editor, findsOneWidget);
      await expectGolden('note_editor', cell);

      // The cursor blink and the auto-save interval are cancelled by
      // `dispose`; neither may outlive the test.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}

/// A real [OptimizedNoteBloc] whose content load is inert, so the test owns
/// when the note's text lands.
class _TestNoteBloc extends OptimizedNoteBloc {
  _TestNoteBloc({required super.storageService, required super.searchService});

  @override
  void add(OptimizedNoteEvent event) {
    if (event is LoadNoteContent) return;
    super.add(event);
  }

  void reset() => emit(OptimizedNoteInitial());

  void emitContentLoaded(NoteMetadata metadata, String content) {
    emit(
      OptimizedNoteContentLoaded(
        note: LazyNote(
          metadata: metadata,
          content: content,
          isContentLoaded: true,
        ),
      ),
    );
  }
}
