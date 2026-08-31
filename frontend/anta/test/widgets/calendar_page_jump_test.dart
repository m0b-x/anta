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
import 'package:anta/widgets/calendar_day_cell.dart';

import '../database/support/db_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;
  late ImportExportBloc importExportBloc;

  /// One database per test, shared by the settings facade and the repositories
  /// the page-level `ImportExportBloc` needs. Opening a second `AppDatabase`
  /// over the same executor is what drift warns can corrupt a database, and
  /// nothing here needs the two to be separate.
  late AppDatabase testDb;
  late DateTime today;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_jump');
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
    today = DateTime.utc(now.year, now.month, now.day);
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'e1',
          title: 'Leg day',
          categoryId: 'gym',
          startDate: today,
          rule: const DailyRecurrence(),
        ),
      ),
    );

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

  Future<void> pumpCalendar(WidgetTester tester) async {
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

  int cellCount(WidgetTester tester) =>
      find.byType(CalendarDayCell).evaluate().length;

  /// Days currently mounted in the grid, across every month page the
  /// `PageView` is holding at once.
  Set<DateTime> mountedDays(WidgetTester tester) => {
    for (final cell in tester.widgetList<CalendarDayCell>(
      find.byType(CalendarDayCell),
    ))
      DateTime.utc(cell.day.year, cell.day.month, cell.day.day),
  };

  /// How many cells one month page paints, by the package's own arithmetic:
  /// `CalendarCore` pads the month with leading days back to the week start
  /// and trailing days out to a full week, so a page is 4-6 whole rows.
  ///
  /// Computed rather than hardcoded because these tests anchor on
  /// `DateTime.now()` — a literal 42 would pass in one month and fail in the
  /// next.
  int pageCells(DateTime month) {
    final first = DateTime.utc(month.year, month.month);
    final daysBefore = (first.weekday + 7 - DateTime.monday) % 7;
    final daysInMonth = DateTime.utc(
      month.year,
      month.month + 1,
    ).difference(first).inDays;
    return 7 * ((daysBefore + daysInMonth + 6) ~/ 7);
  }

  /// Every day of [month] is mounted — i.e. that month's own page is on
  /// screen, not just the handful of its days another page shows as
  /// leading/trailing outside days.
  bool wholeMonthMounted(Set<DateTime> days, DateTime month) {
    final length = DateTime.utc(
      month.year,
      month.month + 1,
    ).difference(DateTime.utc(month.year, month.month)).inDays;
    for (var i = 1; i <= length; i++) {
      if (!days.contains(DateTime.utc(month.year, month.month, i))) {
        return false;
      }
    }
    return true;
  }

  /// Focuses [target] the way every programmatic navigation does (the Today
  /// button, the month/year picker, an agenda row tap) and samples the grid
  /// once per frame for the length of a page animation.
  Future<({int peakCells, int doubleFrames, Set<DateTime> monthsPaged})> jumpTo(
    WidgetTester tester,
    DateTime target,
  ) async {
    await tester.runAsync(() async {
      final next = bloc.stream.first.timeout(const Duration(seconds: 10));
      bloc.add(
        SelectCalendarDay(
          day: target,
          focusedDay: target,
          source: CalendarSelectionSource.navigation,
        ),
      );
      await next;
    });

    final targetMonth = DateTime.utc(target.year, target.month);
    final settledCells = pageCells(targetMonth);
    var peakCells = 0;
    var doubleFrames = 0;
    final monthsPaged = <DateTime>{};
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final cells = cellCount(tester);
      if (cells > peakCells) peakCells = cells;
      if (cells > settledCells) doubleFrames++;
      final days = mountedDays(tester);
      for (var offset = -2; offset <= 2; offset++) {
        final month = DateTime.utc(target.year, target.month + offset);
        if (wholeMonthMounted(days, month)) monthsPaged.add(month);
      }
    }
    await tester.pumpAndSettle();
    return (
      peakCells: peakCells,
      doubleFrames: doubleFrames,
      monthsPaged: monthsPaged,
    );
  }

  void sizeSurface(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1200);
  }

  testWidgets('a one-month jump slides between exactly two month pages', (
    tester,
  ) async {
    sizeSurface(tester);
    await pumpCalendar(tester);

    final origin = DateTime.utc(today.year, today.month);
    final target = DateTime.utc(today.year, today.month + 1, 15);
    final targetMonth = DateTime.utc(target.year, target.month);

    final result = await jumpTo(tester, target);

    expect(
      result.peakCells,
      pageCells(origin) + pageCells(targetMonth),
      reason:
          'the origin and the target are both mounted for the length of the '
          'slide — two full month pages laid out per frame, which is the '
          'price of the animation and is exactly what it buys',
    );
    expect(
      cellCount(tester),
      pageCells(targetMonth),
      reason: 'only the target survives the settle',
    );
  });

  testWidgets(
    'a far jump pages through the month before the target, never the origin',
    (tester) async {
      sizeSurface(tester);
      await pumpCalendar(tester);

      final origin = DateTime.utc(today.year, today.month);
      final target = DateTime.utc(today.year, today.month + 7, 15);
      final targetMonth = DateTime.utc(target.year, target.month);
      final beforeTarget = DateTime.utc(target.year, target.month - 1);

      final result = await jumpTo(tester, target);

      // `TableCalendarBase._updatePage`: a focus change of more than one page
      // does `jumpToPage(target ± 1)` and *then* animates one page. So the
      // month the user watches slide past is not the one they left — it is
      // whatever happens to sit next to their destination.
      expect(
        result.monthsPaged,
        containsAll(<DateTime>[beforeTarget, targetMonth]),
        reason:
            'the month before the target is built and laid out in full, '
            'though the user asked for neither it nor a route through it',
      );
      expect(
        result.monthsPaged,
        isNot(contains(origin)),
        reason:
            'the origin is gone before the first frame — the slide does not '
            'depict the journey it appears to',
      );
      expect(
        result.peakCells,
        pageCells(beforeTarget) + pageCells(targetMonth),
        reason: 'two pages again, one of them a month nobody asked for',
      );
    },
  );

  testWidgets('the two-page window spans most of the page animation', (
    tester,
  ) async {
    sizeSurface(tester);
    await pumpCalendar(tester);

    final result = await jumpTo(
      tester,
      DateTime.utc(today.year, today.month + 7, 15),
    );

    // `pageAnimationDuration` defaults to 300 ms and the sampling loop above
    // runs one 16 ms frame at a time, so ~18 frames carry two mounted month
    // pages. This is the number `pageAnimationDuration` shortens and
    // `pageAnimationEnabled: false` takes to zero.
    expect(
      result.doubleFrames,
      greaterThan(10),
      reason:
          'the doubled layout is not a transient frame or two — it is the '
          'whole animation',
    );
  });
}
