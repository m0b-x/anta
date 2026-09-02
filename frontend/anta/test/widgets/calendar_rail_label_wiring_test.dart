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
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/day_bar.dart';
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
import 'package:anta/widgets/calendar_day_cell.dart';

import '../database/support/db_test_support.dart';

/// The rail's label has to be *wired* by the real page, not merely composable.
///
/// `calendar_day_rail_grid_semantics_test.dart` pins the mechanism — that a
/// label handed to `CalendarDayBars.railLabel` survives `table_calendar`'s
/// `Semantics(excludeSemantics: true)` around every custom-built cell — but it
/// hand-rolls its own `markerBuilder` and never imports `calendar_page.dart`.
/// That left the production composition unchecked: deleting
/// `railLabel: railLabel` from `calendar_page.dart`'s `markerBuilder` failed
/// nothing, which is the same shape as the bug the relocation fixed (a green
/// suite proving a mechanism nobody was calling).
///
/// So these tests pump the **real** [CalendarPage] — real settings, real
/// resolvers, the page's own `markerBuilder` — and read the compiled semantics
/// tree, post-merge and post-exclusion. Every assertion is scoped to a
/// [CalendarDayBars] descendant on purpose: the bottom panel lists the same
/// event titles as ordinary text, and an unscoped `bySemanticsLabel` would
/// pass on those whether or not the grid ever announced anything.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;
  late ImportExportBloc importExportBloc;

  /// One database per test, shared by the settings facade and the repositories
  /// the page-level `ImportExportBloc` needs — same arrangement as
  /// `calendar_grid_output_memo_test.dart`.
  late AppDatabase testDb;
  late DateTime today;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_rail_label');
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
    // Settings on a same-isolate in-memory database, because the page reads
    // them from `initState` — outside any `runAsync` this test controls, and a
    // background-isolate round trip cannot resolve under the fake clock.
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    testDb = await openTestDatabase();
    SettingsService.forTesting(testDb);

    final service = await CalendarEventService.getInstance();
    await service.deleteAll();
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    final now = DateTime.now();
    today = DateTime.utc(now.year, now.month, now.day);

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

  /// A daily commitment the rail claims: recurring and presence-tracking, so
  /// `eventInDayRail` is true and `EventDayBarProvider` drops it from the
  /// bottom strip while the rail is on.
  CalendarEvent railEvent() => CalendarEvent(
    id: 'rail-event',
    title: 'Leg day',
    categoryId: 'gym',
    // `_onCreateEvent` re-focuses the grid on the new event's start date, so
    // every fixture starts on `today` and the rendered page stays there.
    startDate: today,
    rule: const DailyRecurrence(),
    tracksPresence: true,
  );

  /// A one-time appointment, which `eventInDayRail` excludes outright, so it
  /// lands in the marker strip and gives the merged node a second half.
  CalendarEvent barEvent() => CalendarEvent(
    id: 'bar-event',
    title: 'Dentist',
    categoryId: 'health',
    startDate: today,
  );

  /// Writes the rail settings, creates [events], then pumps the real page.
  ///
  /// The settings write and the event creation run inside [runAsync] because
  /// both do real Drift I/O; awaiting either under `testWidgets`' fake clock
  /// would hang rather than fail.
  Future<void> pumpCalendar(
    WidgetTester tester, {
    required List<CalendarEvent> events,
    int maxRailMarks = 3,
  }) async {
    await tester.runAsync(() async {
      final settings = await SettingsService.getInstance();
      await settings.setCalendarDayRailStyle(DayRailStyle.line);
      await settings.setCalendarMaxDayRailMarks(maxRailMarks);
      for (final event in events) {
        final next = bloc.stream.first.timeout(const Duration(seconds: 10));
        bloc.add(CreateCalendarEvent(event: event));
        await next;
      }
    });

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

    // `_loadSettings` is a real async gap before the first paint, and the
    // page's *first* frame renders with the default appearance — rail off. So
    // wait for the loaded style to reach the cells rather than for the first
    // `CalendarDayBars`, which appears either way and would let this run
    // against the pre-settings grid. Bounded, so a stalled read fails on the
    // assertion instead of hanging.
    for (var i = 0; i < 20; i++) {
      final cells = tester.widgetList<CalendarDayCell>(
        find.byType(CalendarDayCell),
      );
      if (cells.isNotEmpty && cells.first.railStyle == DayRailStyle.line) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Anti-vacuity: with the rail still off every assertion below would be
    // about a grid that has no rail to announce, and would pass by saying
    // nothing.
    expect(
      tester.widget<CalendarDayCell>(find.byType(CalendarDayCell).first),
      isA<CalendarDayCell>().having(
        (cell) => cell.railStyle,
        'railStyle',
        DayRailStyle.line,
      ),
      reason: 'the rail settings never reached the grid',
    );
  }

  /// Dispatches [event] and waits for the bloc's next emission before pumping,
  /// through [runAsync] for the same reason [pumpCalendar] uses it.
  Future<void> dispatchAndPump(
    WidgetTester tester,
    CalendarPageEvent event,
  ) async {
    await tester.runAsync(() async {
      final next = bloc.stream.first.timeout(const Duration(seconds: 10));
      bloc.add(event);
      await next;
    });
    await tester.pump();
  }

  /// A semantics label on a grid marker node, and nowhere else. The bottom
  /// panel renders the same titles as `Text`, which carry identical labels.
  Finder gridLabel(Pattern label) => find.descendant(
    of: find.byType(CalendarDayBars),
    matching: find.bySemanticsLabel(label),
  );

  /// A merged marker label that **starts with** [prefix].
  ///
  /// Anchored rather than exact because the grid's other bar providers are
  /// live: `WeekendDayBarProvider` is ungated, and holidays and fasting fire
  /// on real dates, so a fixture pinned to an exact string would pass or fail
  /// depending on the day the suite happens to run. What the wiring guarantees
  /// is the *position*: the rail's half is composed first, ahead of every bar.
  Finder gridLabelStartingWith(String prefix) =>
      gridLabel(RegExp('^${RegExp.escape(prefix)}(,|\$)'));

  /// The bars behind every rendered marker strip, flattened.
  Iterable<DayBar> renderedBars(WidgetTester tester) => tester
      .widgetList<CalendarDayBars>(find.byType(CalendarDayBars))
      .expand((strip) => strip.bars);

  testWidgets('the real page announces a rail-only day through its strip', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpCalendar(tester, events: [railEvent()]);

    // With the rail on, `EventDayBarProvider` drops every event the rail
    // claimed, so nothing in the bottom strip can be the source of the label
    // below — the day's marks exist only on the rail.
    expect(
      renderedBars(tester).map((bar) => bar.semanticLabel),
      isNot(contains('Leg day')),
      reason: 'the rail did not claim the event, so this proves nothing',
    );

    final finder = gridLabelStartingWith('Leg day');
    expect(
      finder,
      findsWidgets,
      reason:
          "calendar_page.dart's markerBuilder must pass its composed "
          'railLabel to CalendarDayBars, or the day is silent',
    );
    // A zero-size render object is dropped from the semantics tree, so the
    // label would be reachable in the widget tree and unreachable to a screen
    // reader — the exact failure this wiring exists to prevent.
    expect(tester.getSemantics(finder.first).rect.isEmpty, isFalse);
    handle.dispose();
  });

  testWidgets('the rail and the bars reach the grid as one merged node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpCalendar(tester, events: [railEvent(), barEvent()]);

    // Today carries both channels: the rail's mark reads first (its lane runs
    // down the cell's left edge, the strip sits along the bottom).
    expect(
      gridLabelStartingWith('Leg day, Dentist'),
      findsOneWidget,
      reason: 'the two channels must announce once, in lane order',
    );
    // What that same node would say with the rail's half dropped. Its absence
    // is the assertion: it appears the moment `railLabel` stops being wired.
    expect(gridLabelStartingWith('Dentist'), findsNothing);
    handle.dispose();
  });

  testWidgets('a missed occurrence carries its localized state to the grid', (
    tester,
  ) async {
    // The rail is where missed state is announced at all — the bars encode it
    // as alpha — so `calendarRailMarkMissedLabel` reaches a screen reader only
    // through this wiring.
    final handle = tester.ensureSemantics();
    await pumpCalendar(tester, events: [railEvent()]);
    expect(gridLabelStartingWith('Leg day, missed'), findsNothing);

    await dispatchAndPump(
      tester,
      SetOccurrenceMissed(eventId: 'rail-event', day: today),
    );

    expect(
      gridLabelStartingWith('Leg day, missed'),
      findsOneWidget,
      reason:
          'exactly one day was marked, and colour must not be the only '
          'carrier of that state',
    );
    handle.dispose();
  });
}
