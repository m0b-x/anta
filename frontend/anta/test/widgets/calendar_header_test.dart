import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart' show CalendarFormat;

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/import_export/import_export_event.dart';
import 'package:anta/bloc/import_export/import_export_state.dart';
import 'package:anta/constants/semantics_ids.dart';
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
import 'package:anta/widgets/calendar_filter_sheet.dart';
import 'package:anta/widgets/calendar_header_menus.dart';

import '../database/support/db_test_support.dart';

/// The calendar page's header (`docs/calendar-header-roadmap.md`): the title
/// is the view menu, the bar keeps saved filters and filter, and the ⋮ holds
/// Alerts, the export and the calendar's settings. The grid's format is
/// picked from the view menu and no longer from the filter sheet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;
  late _RecordingImportExportBloc importExportBloc;
  late AppDatabase testDb;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_header');
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
    importExportBloc = _RecordingImportExportBloc(
      ImportExportService(
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

  /// [pushed] puts the page over a root, as the drawer does, so its bar
  /// carries the back button and the title gets the width it has on a phone.
  Future<void> pumpCalendar(
    WidgetTester tester, {
    Size size = const Size(800, 1400),
    Locale locale = const Locale('en'),
    bool pushed = false,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<CalendarBloc>.value(value: bloc),
          BlocProvider<ImportExportBloc>.value(value: importExportBloc),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          home: pushed ? const Scaffold() : const CalendarPage(),
        ),
      ),
    );
    if (pushed) {
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const CalendarPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    for (var i = 0; i < 20; i++) {
      if (find.byType(CalendarDayBars).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Finder id(String identifier) => find.bySemanticsIdentifier(identifier);

  Finder inBar(Finder matching) =>
      find.descendant(of: find.byType(AppBar), matching: matching);

  Future<void> open(WidgetTester tester, String identifier) async {
    await tester.tap(id(identifier));
    await tester.pumpAndSettle();
  }

  CalendarFormat format() => (bloc.state as CalendarPageLoaded).format;

  /// The bloc is built in `setUp`, outside the test's fake-async zone, so a
  /// state it emits reaches the page's builders only once the real zone has
  /// run its microtasks.
  Future<void> deliver(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('the bar holds the view menu, saved filters, filter and ⋮', (
    tester,
  ) async {
    await pumpCalendar(tester);

    expect(id(SemanticsIds.calendarViewMenu), findsOneWidget);
    expect(inBar(find.text('Calendar')), findsOneWidget);
    expect(inBar(find.byIcon(Icons.bookmarks_outlined)), findsOneWidget);
    expect(inBar(find.byIcon(Icons.filter_alt_outlined)), findsOneWidget);
    expect(id(SemanticsIds.calendarMore), findsOneWidget);
    // The overview and settings buttons are gone; the icon buttons left are
    // saved filters, filter and the ⋮.
    expect(inBar(find.byIcon(Icons.grid_view_rounded)), findsNothing);
    expect(inBar(find.byIcon(Icons.settings_outlined)), findsNothing);
    expect(inBar(find.byType(IconButton)), findsNWidgets(3));
    // The route is named by the labelled title node, not by an empty header
    // annotation around it.
    expect(tester.widget<AppBar>(find.byType(AppBar)).excludeHeaderSemantics,
        isTrue);
    expect(
      tester
          .getSemantics(id(SemanticsIds.calendarViewMenu))
          .getSemanticsData()
          .flagsCollection
          .namesRoute,
      isTrue,
    );
  });

  testWidgets('a format picked in the view menu applies at once', (
    tester,
  ) async {
    await pumpCalendar(tester);
    expect(format(), CalendarFormat.month);

    await open(tester, SemanticsIds.calendarViewMenu);
    await tester.tap(id(SemanticsIds.calendarFormatWeek));
    await deliver(tester);
    expect(format(), CalendarFormat.week);
    expect(
      tester.widget<CalendarViewMenu>(find.byType(CalendarViewMenu)).format,
      CalendarFormat.week,
    );

    await open(tester, SemanticsIds.calendarViewMenu);
    expect(
      find.descendant(
        of: id(SemanticsIds.calendarFormatWeek),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(id(SemanticsIds.calendarFormatMonth));
    await deliver(tester);
    expect(format(), CalendarFormat.month);
  });

  testWidgets('the menu checks a format the grid took some other way', (
    tester,
  ) async {
    await pumpCalendar(tester);
    // `add`, not `dispatch`: awaiting the bloc's stream from inside the
    // test's fake-async zone never completes.
    bloc.add(const ChangeCalendarFormat(format: CalendarFormat.twoWeeks));
    await deliver(tester);

    await open(tester, SemanticsIds.calendarViewMenu);
    expect(
      find.descendant(
        of: id(SemanticsIds.calendarFormatTwoWeeks),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the filter sheet no longer carries the format', (tester) async {
    await pumpCalendar(tester);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.filter_alt_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(CalendarFilterSheet), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is SegmentedButton<CalendarFormat>),
      findsNothing,
    );
    expect(find.text('Month'), findsNothing);
  });

  testWidgets('the ⋮ offers Alerts, Export and Calendar settings', (
    tester,
  ) async {
    await pumpCalendar(tester);

    await open(tester, SemanticsIds.calendarMore);
    expect(id(SemanticsIds.calendarAlertsOpen), findsOneWidget);
    expect(id(SemanticsIds.calendarExport), findsOneWidget);
    expect(id(SemanticsIds.calendarSettingsOpen), findsOneWidget);
    expect(find.text('Calendar settings'), findsOneWidget);
  });

  testWidgets('Export hands the loaded events over and reports the outcome '
      'once', (tester) async {
    await pumpCalendar(tester);

    await open(tester, SemanticsIds.calendarMore);
    await tester.tap(id(SemanticsIds.calendarExport));
    await tester.pumpAndSettle();
    final request = importExportBloc.recorded
        .whereType<ExportCalendarRequested>()
        .single;
    expect(request.events.map((event) => event.id), ['e1']);
    expect(request.share, isTrue);

    // Emitted from the test's own zone, so the page's listener hears it
    // without a trip through the real one.
    // ignore: invalid_use_of_visible_for_testing_member
    importExportBloc.emit(
      const ImportExportExportSuccess(
        operation: ImportExportOperation.exportCalendar,
        result: ExportResult(filePath: 'events.ics', eventsExported: 1),
      ),
    );
    // One frame delivers the state to the listener, the next draws its bar.
    await tester.pump();
    await tester.pump();
    expect(find.text('1 event exported'), findsOneWidget);
    expect(importExportBloc.recorded.whereType<ImportExportReset>(), hasLength(1));
  });

  // The test font is wider than the device's, so whether "Kalender" reads in
  // full is the device pass's to say (123 dp against a 148 dp slot at
  // 360 dp); what this pins is the layout: no overflow, and the caret never
  // pushed under the actions.
  testWidgets('German on a 360 dp phone lays the bar out beside its back '
      'button', (tester) async {
    await pumpCalendar(
      tester,
      size: const Size(360, 780),
      locale: const Locale('de'),
      pushed: true,
    );
    expect(tester.takeException(), isNull);
    expect(inBar(find.byType(BackButton)), findsOneWidget);
    expect(inBar(find.text('Kalender')), findsOneWidget);

    final glyph = tester.getRect(
      inBar(find.byIcon(Icons.arrow_drop_down_rounded)),
    );
    final savedFilters = tester.getRect(
      inBar(find.byIcon(Icons.bookmarks_outlined)),
    );
    expect(glyph.right, lessThanOrEqualTo(savedFilters.left));
  });
}

/// Records every event instead of running it: an export would reach the
/// share sheet.
class _RecordingImportExportBloc extends ImportExportBloc {
  _RecordingImportExportBloc(ImportExportService service)
    : super(service: service);

  final List<ImportExportEvent> recorded = [];

  @override
  void add(ImportExportEvent event) => recorded.add(event);
}
