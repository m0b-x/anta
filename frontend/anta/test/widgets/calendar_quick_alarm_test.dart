import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/pages/calendar_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/quick_alarm_request.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/quick_alarm.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/quick_alarm_sheet.dart';

import '../database/support/db_test_support.dart';

/// Where the Quick Settings tile and the launcher shortcut land (OS-5, **B9**):
/// `main.dart`'s drain publishes a `QuickAlarmRequest` and brings the calendar
/// up, and the page opens the quick-alarm sheet on today — whether the request
/// was waiting when the page mounted or arrived while it was up — and turns
/// its Save into one event with one alert, with Undo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase testDb;
  late CalendarBloc bloc;
  late ImportExportBloc importExportBloc;
  late List<({String eventId, List<EventAlert> alerts})> writes;
  late List<String> reconciled;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_quick');
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
    QuickAlarmRequest.instance.clearForTesting();
    testDb = await openTestDatabase();
    SettingsService.forTesting(testDb);
    writes = [];
    reconciled = [];

    final service = await CalendarEventService.getInstance();
    await service.deleteAll();
    bloc = CalendarBloc(
      service: service,
      alertReconciler: (eventId, reason) async => reconciled.add(eventId),
      alertWriter: (eventId, alerts) async =>
          writes.add((eventId: eventId, alerts: alerts)),
    );
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
    QuickAlarmRequest.instance.clearForTesting();
    SettingsService.reset();
    await testDb.close();
  });

  Future<void> pumpCalendar(WidgetTester tester) async {
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
          home: const CalendarPage(),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      if (find.byType(CalendarDayBars).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
    // The sheet's entry animation, run by hand like every calendar sheet test.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  List<Object?> events() =>
      (bloc.state as CalendarPageLoaded).allEvents.map((e) => e.id).toList();

  /// Taps [target] on the fake clock, then lets the bloc's database write
  /// land under real time until the state says [until]. The tap stays outside
  /// `runAsync` so the route and snackbar animations it starts complete on
  /// the fake clock, with the tree still up; the write needs the real event
  /// loop, which is what the delayed loop spins, and each `pump` flushes the
  /// handler's continuation.
  Future<void> tapAndAwaitState(
    WidgetTester tester,
    Finder target, {
    required bool Function(CalendarPageState state) until,
  }) async {
    await tester.tap(target);
    await tester.pump();
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!until(bloc.state)) {
        if (DateTime.now().isAfter(deadline)) {
          fail('the bloc never reached the expected state');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('a request waiting at mount opens the sheet on today', (
    tester,
  ) async {
    QuickAlarmRequest.instance.publish();

    await pumpCalendar(tester);

    expect(find.byType(QuickAlarmSheet), findsOneWidget);
    expect(find.text('Today'), findsWidgets);
    expect(QuickAlarmRequest.instance.hasPending, isFalse);
  });

  testWidgets('a request arriving while the page is up opens the sheet too', (
    tester,
  ) async {
    await pumpCalendar(tester);
    expect(find.byType(QuickAlarmSheet), findsNothing);

    QuickAlarmRequest.instance.publish();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(QuickAlarmSheet), findsOneWidget);
  });

  testWidgets('a stale request opens nothing', (tester) async {
    QuickAlarmRequest.instance.clock = () =>
        DateTime.now().subtract(QuickAlarmRequest.freshness * 2);
    QuickAlarmRequest.instance.publish();
    QuickAlarmRequest.instance.clock = DateTime.now;

    await pumpCalendar(tester);

    expect(find.byType(QuickAlarmSheet), findsNothing);
    expect(QuickAlarmRequest.instance.hasPending, isFalse);
  });

  testWidgets('Save makes one event with one alert, and Undo deletes it', (
    tester,
  ) async {
    QuickAlarmRequest.instance.publish();
    await pumpCalendar(tester);
    expect(events(), isEmpty, reason: 'precondition');

    await tapAndAwaitState(
      tester,
      find.bySemanticsIdentifier(SemanticsIds.quickAlarmSave),
      until: (state) =>
          state is CalendarPageLoaded && state.allEvents.isNotEmpty,
    );

    expect(find.byType(QuickAlarmSheet), findsNothing);
    expect(events(), hasLength(1));
    final created = (bloc.state as CalendarPageLoaded).allEvents.single;
    expect(created.title, 'Alarm');
    expect(created.iconKey, kQuickAlarmIconKey);
    expect(created.removeAfterAlert, isTrue);
    expect(created.time, isNotNull);
    expect(writes, hasLength(1));
    expect(writes.single.eventId, created.id);
    expect(writes.single.alerts.single.mode, AlertMode.ring);
    expect(writes.single.alerts.single.offsetMinutes, 0);
    expect(reconciled, [created.id]);
    expect(find.textContaining('Alarm set for'), findsOneWidget);

    await tapAndAwaitState(
      tester,
      find.text('UNDO'),
      until: (state) => state is CalendarPageLoaded && state.allEvents.isEmpty,
    );

    expect(events(), isEmpty);
    expect(reconciled, [created.id, created.id]);
    // The snackbar's own timer and its dismissal run under the fake clock;
    // left pending they would complete against a torn-down tree.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  });
}
