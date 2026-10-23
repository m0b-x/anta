@Tags(['golden'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_selection_source.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/calendar_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/calendar_day_bars.dart';

import '../database/support/db_test_support.dart';
import '../widgets/support/layout_errors.dart';
import 'support/golden_matrix.dart';

/// The calendar's month grid and day panel, harnessed as
/// `test/widgets/calendar_grid_output_memo_test.dart` harnesses it.
///
/// The grid opens on August 2026 with the 14th selected, never on the
/// current month: the grid marks today, so a golden of this month would
/// change every day. A month wholly in the past also fixes everything else
/// that is drawn against the clock — a tracked series' missed days, the
/// Today button's state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Two databases on purpose: the app's own, which the event service is
  // bound to, beside the in-memory one the settings live in.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final shown = DateTime.utc(2026, 8, 14);

  late Directory tempDir;
  late CalendarBloc bloc;
  late ImportExportBloc importExportBloc;
  late AppDatabase testDb;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_golden_calendar');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    await next;
  }

  setUp(() async {
    // Settings on a same-isolate in-memory database: the page and its
    // bottom panel read them from `initState`, outside any `runAsync`.
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    testDb = await openTestDatabase();
    SettingsService.forTesting(testDb);

    final service = await CalendarEventService.getInstance();
    await service.tombstoneAll();
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'e1',
          title: 'Leg day',
          categoryId: 'gym',
          startDate: DateTime.utc(2026, 8, 3),
          endDate: DateTime.utc(2026, 8, 28),
          rule: const DailyRecurrence(),
          tracksPresence: true,
        ),
      ),
    );
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'e2',
          title: 'Stretch class',
          categoryId: 'mobility',
          startDate: shown,
          rule: const OneTimeRecurrence(),
        ),
      ),
    );
    // A create already focuses its event's start, so this only moves the
    // selection when the bloc landed elsewhere; an equal state never emits.
    final loaded = bloc.state as CalendarPageLoaded;
    if (loaded.selectedDay != shown || loaded.focusedDay != shown) {
      await dispatch(
        SelectCalendarDay(
          day: shown,
          focusedDay: shown,
          source: CalendarSelectionSource.navigation,
        ),
      );
    }

    // Only so `ImportExportBloc` exists in the tree: the page's listener
    // reads it, and nothing here exports.
    final noteRepository = NoteRepository(database: testDb);
    importExportBloc = ImportExportBloc(
      service: ImportExportService(
        noteStorage: NoteStorageService(repository: noteRepository),
        folderStorage: FolderStorageService(
          repository: FolderRepository(database: testDb),
        ),
        noteRepository: noteRepository,
      ),
    );
  });

  tearDown(() async {
    await bloc.close();
    await importExportBloc.close();
    SettingsService.reset();
    await testDb.close();
  });

  for (final cell in goldenCells) {
    testWidgets('calendar page, ${cell.label}', (tester) async {
      setGoldenSurface(tester, cell);
      final errors = await layoutErrorsDuring(() async {
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<CalendarBloc>.value(value: bloc),
              BlocProvider<ImportExportBloc>.value(value: importExportBloc),
            ],
            child: goldenApp(cell, home: const CalendarPage()),
          ),
        );
        // The settings reads are real async gaps before the first paint;
        // bounded frames rather than a settle, so a stalled read fails.
        for (var i = 0; i < 20; i++) {
          if (find.byType(CalendarDayBars).evaluate().isNotEmpty) break;
          await tester.pump(const Duration(milliseconds: 20));
        }
        // Past the grid's and the panel's entrance motion.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
      });

      expect(errors, isEmpty);
      await expectGolden('calendar_page', cell);
    });
  }
}
