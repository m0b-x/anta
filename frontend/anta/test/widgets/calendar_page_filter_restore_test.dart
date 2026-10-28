import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_grid_filters.dart';
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

/// The grid's filter restore, against a change made while it was still out.
///
/// The read (`getCalendarPageSettings`) and the write (`_persistFilters`) are
/// independent, and the read can take ~1.5 s on a cold start, so a set read
/// before the user's change used to win on screen while the store kept
/// theirs — the UI and the preference disagreeing until the next filter
/// change. The panel's twin of this race is pinned by
/// `calendar_bottom_panel_mode_test.dart`; this is the page's.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;
  late ImportExportBloc importExportBloc;
  late AppDatabase testDb;
  late _HeldRead gate;
  late SettingsService settings;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_filter_restore');
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
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    gate = _HeldRead();
    testDb = await openTestDatabase(interceptor: gate);
    settings = SettingsService.forTesting(testDb);

    final service = await CalendarEventService.getInstance();
    await service.tombstoneAll();
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    final now = DateTime.now();
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'e1',
          title: 'Leg day',
          categoryId: 'gym',
          startDate: DateTime.utc(now.year, now.month, now.day),
          rule: const DailyRecurrence(),
        ),
      ),
    );

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
    gate.release();
    await bloc.close();
    await importExportBloc.close();
    SettingsService.reset();
    await testDb.close();
  });

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpCalendar(WidgetTester tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1600);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<CalendarBloc>.value(value: bloc),
          BlocProvider<ImportExportBloc>.value(value: importExportBloc),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const CalendarPage(),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      if (find.byType(CalendarDayBars).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> tapId(WidgetTester tester, String id) async {
    await tester.tap(find.bySemanticsIdentifier(id));
    await pumpFrames(tester);
  }

  CalendarGridFilters shown() => (bloc.state as CalendarPageLoaded).filters;

  Future<CalendarGridFilters> stored() async =>
      (await settings.getCalendarPageSettings()).filters;

  const restored = CalendarGridFilters(priorities: {1});

  testWidgets('a filter turned off before the restore lands survives it', (
    tester,
  ) async {
    await settings.setCalendarGridFilters(restored);
    gate.hold(SettingsKeys.calendarGridFilters);

    await pumpCalendar(tester);
    expect(gate.held, isTrue);
    // The stored set is still out; the sheet opens on the defaults and the
    // user turns holidays off over them.
    await tapId(tester, SemanticsIds.calendarFilterOpen);
    await tapId(tester, SemanticsIds.filterHolidays);
    await tapId(tester, SemanticsIds.filterApply);
    expect(shown().showHolidays, isFalse);

    gate.release();
    await pumpFrames(tester);

    const merged = CalendarGridFilters(priorities: {1}, showHolidays: false);
    expect(shown(), merged);
    // And the store follows what the grid shows: the pick was made on the
    // defaults, so it was not written before the merge.
    expect(await stored(), merged);
  });

  testWidgets('a filter change still persists after the read failed', (
    tester,
  ) async {
    await settings.setCalendarGridFilters(restored);
    gate.failOnce(SettingsKeys.calendarGridFilters);

    await pumpCalendar(tester);
    await pumpFrames(tester);
    expect(gate.failed, isTrue);
    // Nothing was restored: the page is on its defaults.
    expect(shown(), CalendarGridFilters.none);

    await tapId(tester, SemanticsIds.calendarFilterOpen);
    await tapId(tester, SemanticsIds.filterHolidays);
    await tapId(tester, SemanticsIds.filterApply);

    expect(shown().showHolidays, isFalse);
    // The read is what failed, not the write: a session whose restore never
    // landed must not stop writing every filter the user picks after it.
    expect((await stored()).showHolidays, isFalse);
  });

  testWidgets('with no change the stored set is restored as it was', (
    tester,
  ) async {
    await settings.setCalendarGridFilters(restored);

    await pumpCalendar(tester);
    await pumpFrames(tester);

    expect(shown(), restored);
  });
}

/// Delivers one setting's read late: the select runs at once, so its answer is
/// the value stored when the page asked, and is handed back only on [release]
/// — the shape of the race on a device, where the user's change lands between
/// the read and the restore's dispatch.
class _HeldRead extends QueryInterceptor {
  Completer<void>? _hold;
  String? _key;
  String? _failKey;
  bool held = false;
  bool failed = false;

  void hold(String key) {
    _key = key;
    _hold = Completer<void>();
  }

  /// Fails the first read carrying [key] and lets every later one through —
  /// a settings trip lost to a locked or corrupt database, after which the
  /// page must still write what the user picks.
  void failOnce(String key) => _failKey = key;

  void release() {
    final hold = _hold;
    _hold = null;
    if (hold != null && !hold.isCompleted) hold.complete();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final failKey = _failKey;
    if (failKey != null && args.contains(failKey)) {
      _failKey = null;
      failed = true;
      throw Exception('settings read failed');
    }
    final rows = await super.runSelect(executor, statement, args);
    final hold = _hold;
    if (hold != null && args.contains(_key)) {
      held = true;
      await hold.future;
    }
    return rows;
  }
}
