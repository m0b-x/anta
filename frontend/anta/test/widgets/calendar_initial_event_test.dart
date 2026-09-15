import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
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
import 'package:anta/widgets/event_detail_sheet.dart';

import '../database/support/db_test_support.dart';

/// Where a tapped reminder lands (**A12**): the calendar on the event's own
/// day, with its detail sheet already open.
///
/// The hard part is not the push, it is the timing. `CalendarBloc` lives above
/// `MaterialApp` and is loaded at launch, so by the time this page mounts its
/// state is usually **already** loaded and a `BlocListener` would never fire —
/// which is why the page also checks the current state after its first frame.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase testDb;
  late CalendarBloc bloc;
  late ImportExportBloc importExportBloc;

  /// Three days out, so selecting it is visibly not "whatever was selected".
  final today = () {
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day);
  }();
  final target = today.add(const Duration(days: 3));

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_initial');
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
    testDb = await openTestDatabase();
    SettingsService.forTesting(testDb);

    final service = await CalendarEventService.getInstance();
    await service.deleteAll();
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'e1',
          title: 'Leg day',
          categoryId: 'gym',
          startDate: target,
          rule: const OneTimeRecurrence(),
          time: const EventTime(startMinute: 18 * 60),
        ),
      ),
    );
    // The create handler selects the new event's day; put the selection back
    // on today so the test is about `initialDay`, not about that side effect.
    await dispatch(const LoadCalendarEvents());

    final noteRepository = NoteRepository(database: testDb);
    final folderRepository = FolderRepository(database: testDb);
    importExportBloc = ImportExportBloc(
      service: ImportExportService(
        noteStorage: NoteStorageService(repository: noteRepository),
        folderStorage: FolderStorageService(repository: folderRepository),
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

  Future<void> pumpCalendar(WidgetTester tester, Widget page) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1400);
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
          home: page,
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      if (find.byType(CalendarDayBars).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
    // The sheets load their own data, which a widget test's fake async never
    // completes, so the entry animation is run by hand.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  DateTime selectedDay() {
    final state = bloc.state;
    return (state as CalendarPageLoaded).selectedDay;
  }

  testWidgets('initialEventId opens the detail sheet on the right day', (
    tester,
  ) async {
    expect(selectedDay(), today, reason: 'precondition');

    await pumpCalendar(
      tester,
      CalendarPage(initialDay: target, initialEventId: 'e1'),
    );

    expect(find.byType(EventDetailSheet), findsOneWidget);
    expect(find.text('Leg day'), findsWidgets);
    expect(selectedDay(), target);
  });

  testWidgets('initialDay alone selects the day and opens nothing', (
    tester,
  ) async {
    await pumpCalendar(tester, CalendarPage(initialDay: target));

    expect(find.byType(EventDetailSheet), findsNothing);
    expect(selectedDay(), target);
  });

  testWidgets('an unknown event id lands on the day without a sheet', (
    tester,
  ) async {
    await pumpCalendar(
      tester,
      CalendarPage(initialDay: target, initialEventId: 'ghost'),
    );

    expect(find.byType(EventDetailSheet), findsNothing);
    expect(selectedDay(), target);
  });

  testWidgets('a plain CalendarPage changes neither selection nor sheet', (
    tester,
  ) async {
    await pumpCalendar(tester, const CalendarPage());

    expect(find.byType(EventDetailSheet), findsNothing);
    expect(selectedDay(), today);
  });

  testWidgets('the sheet is opened once, not again on a later state', (
    tester,
  ) async {
    await pumpCalendar(
      tester,
      CalendarPage(initialDay: target, initialEventId: 'e1'),
    );
    expect(find.byType(EventDetailSheet), findsOneWidget);

    // Dismiss it, then provoke another `CalendarPageLoaded`.
    Navigator.of(tester.element(find.byType(EventDetailSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(EventDetailSheet), findsNothing);

    bloc.add(const LoadCalendarEvents());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byType(EventDetailSheet),
      findsNothing,
      reason: 'a reload must not reopen a sheet the user dismissed',
    );
  });
}
