import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/agenda_month_store.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/widgets/year_month_tile.dart';

import '../database/support/db_test_support.dart';
import 'support/overview_robot.dart';

/// The overview's year scroll over a century of events, against the budgets
/// of the years scroll (`docs/calendar-overview-list-roadmap.md` §3.14 and
/// slice 12): sections built per frame, years resolved per frame, and no
/// work at all on a keyboard frame or a keystroke.
///
/// The budgets are asserted in sections built, years resolved and
/// `occursOn` calls, never in milliseconds — counts that hold on every
/// machine — so they run in the default suite, in a few seconds. A section
/// is built when its tiles are, and each tile's label names its year; a
/// year is resolved once the store holds a tally for each of its months —
/// one marks call.
///
/// The same pass with its wall-clock numbers printed is **tagged
/// `benchmark` and excluded from the default run** (see `dart_test.yaml`):
/// the numbers move with the machine's load and are for reading, never a
/// pass/fail signal. Run it deliberately:
///
/// ```powershell
/// flutter test test/widgets/overview_years_benchmark_test.dart --tags benchmark --run-skipped
/// ```
void main() {
  late CalendarBloc bloc;
  late ImportExportBloc importExport;
  late AppDatabase db;

  final today = EventAgenda.dateOnly(DateTime.now());
  final year = today.year;

  /// The span's first year: with the open-ended series ending it next year,
  /// a hundred years.
  final firstYear = year - 98;

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    db = await openTestDatabase();
    SettingsService.forTesting(db);
    final notes = NoteRepository(database: db);
    importExport = ImportExportBloc(
      service: ImportExportService(
        noteStorage: NoteStorageService(repository: notes),
        folderStorage: FolderStorageService(
          repository: FolderRepository(database: db),
        ),
        noteRepository: notes,
      ),
    );
    CalendarCategories.updateCache([
      for (final (index, seed) in CalendarCategories.builtInSeeds.indexed)
        CalendarCategory(
          id: seed.id,
          name: seed.kind.name,
          colorValue: seed.colorValue,
          iconKey: seed.iconKey,
          sortOrder: index,
          isBuiltIn: true,
        ),
    ]);
    bloc = CalendarBloc(service: Completer<CalendarEventService>().future);
    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(
      CalendarPageLoaded(
        allEvents: _centuryEvents(firstYear),
        focusedDay: today,
        selectedDay: today,
      ),
    );
  });

  tearDown(() async {
    await bloc.close();
    await importExport.close();
    CalendarCategories.updateCache(const []);
    SettingsService.reset();
    await db.close();
  });

  /// The five budgets in one pass, as one session of the page meets them;
  /// [report] hears each step's wall-clock time and what it cost.
  Future<void> yearBudgets(
    WidgetTester tester, {
    void Function(String label, int ms, String what)? report,
  }) async {
    final robot = OverviewRobot(tester);
    AgendaMonthStore? store;

    bool resolvedYear(int shown) => AgendaMonthStore.monthsOfYear(
      shown,
    ).every((month) => store!.cachedTally(month) != null);
    int resolvedYears() => [
      for (var shown = firstYear; shown <= year + 1; shown++)
        if (resolvedYear(shown)) shown,
    ].length;

    // The years whose sections built tiles while [body] ran.
    Future<Set<int>> sectionsBuiltDuring(Future<void> Function() body) async {
      final built = <int>{};
      debugOnRebuildDirtyWidget = (element, _) {
        final widget = element.widget;
        if (widget is YearMonthTile) {
          built.add(int.parse(widget.label.substring(widget.label.length - 4)));
        }
      };
      try {
        await body();
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      return built;
    }

    // --- Open --------------------------------------------------------
    CalendarEvent.debugOccursOnCalls = 0;
    final watch = Stopwatch()..start();
    final openSections = await sectionsBuiltDuring(
      () => robot.open(
        bloc: bloc,
        importExport: importExport,
        surface: const Size(412, 915),
        onStore: (resolved) => store = resolved,
      ),
    );
    await robot.finishResolving();
    watch.stop();
    final openResolved = resolvedYears();
    expect(robot.yearSpan, (first: firstYear, last: year + 1));
    report?.call(
      'open on $year',
      watch.elapsedMilliseconds,
      '${openSections.length} sections built, $openResolved years '
          'resolved, ${CalendarEvent.debugOccursOnCalls} occursOn',
    );
    expect(openSections.length, lessThanOrEqualTo(3));
    expect(openResolved, 3);

    // --- Far jump, fifty years back ------------------------------------
    final extent = robot.yearSectionExtent;
    final target = year - 50;
    watch
      ..reset()
      ..start();
    final jumpSections = await sectionsBuiltDuring(() async {
      await robot.jumpYearsTo(
        robot.yearsOffset - (year - target) * extent,
        settle: false,
      );
      await robot.finishResolving();
    });
    watch.stop();
    final jumpResolved = resolvedYears() - openResolved;
    expect(robot.navTitle, '$target');
    report?.call(
      'far jump to $target',
      watch.elapsedMilliseconds,
      '${jumpSections.length} sections built $jumpSections, '
          '$jumpResolved years resolved',
    );
    expect(jumpSections.length, lessThanOrEqualTo(3));
    expect(
      jumpSections.every((built) => (built - target).abs() <= 1),
      isTrue,
      reason: 'no section between the two landings is built',
    );
    expect(jumpResolved, lessThanOrEqualTo(3));

    // --- A fling over twenty years, frame by frame ---------------------
    final flingFrom = robot.yearsOffset;
    final beforeFling = resolvedYears();
    final seen = <int>{};
    final perFrame = <int>[];
    watch
      ..reset()
      ..start();
    // A decelerating drive over the scroll, as a fling's frames are: a
    // scroll notification per frame, no landing.
    unawaited(
      robot.yearsPosition.animateTo(
        flingFrom + 20 * extent,
        duration: const Duration(milliseconds: 800),
        curve: Curves.decelerate,
      ),
    );
    var last = resolvedYears();
    for (var frame = 0; frame < 70; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      seen.addAll(robot.visibleYearsAt());
      final now = resolvedYears();
      perFrame.add(now - last);
      last = now;
    }
    await robot.finishResolving();
    seen.addAll(robot.visibleYearsAt());
    watch.stop();
    final flingResolved = resolvedYears() - beforeFling;
    expect(robot.navTitle, '${target + 20}');
    final worstFrame = perFrame.reduce((a, b) => a > b ? a : b);
    report?.call(
      'fling over 20 years',
      watch.elapsedMilliseconds,
      '$flingResolved years resolved over ${seen.length} years seen, '
          'at most $worstFrame in a frame',
    );
    expect(worstFrame, lessThanOrEqualTo(1));
    expect(flingResolved, lessThanOrEqualTo(seen.length + 2));

    // --- The keyboard folding the chip row -----------------------------
    await robot.focusSearch();
    await tester.pumpAndSettle();
    await robot.finishResolving();
    CalendarEvent.debugOccursOnCalls = 0;
    var tileBuilds = 0;
    addTearDown(tester.view.resetViewInsets);
    watch
      ..reset()
      ..start();
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is YearMonthTile) tileBuilds++;
    };
    try {
      for (var frame = 1; frame <= 20; frame++) {
        tester.view.viewInsets = FakeViewPadding(bottom: 16.0 * frame);
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    watch.stop();
    final keyboardScans = CalendarEvent.debugOccursOnCalls;
    report?.call(
      'keyboard, 20 frames',
      watch.elapsedMilliseconds,
      '$tileBuilds tile builds, $keyboardScans occursOn',
    );
    expect(tileBuilds, 0);
    expect(keyboardScans, 0);

    // --- A keystroke under a live query --------------------------------
    await robot.typeQuery('squat');
    await robot.finishResolving();
    CalendarEvent.debugOccursOnCalls = 0;
    watch
      ..reset()
      ..start();
    await robot.typeQuery('squa');
    watch.stop();
    final keystroke = CalendarEvent.debugOccursOnCalls;
    report?.call(
      'keystroke under a query',
      watch.elapsedMilliseconds,
      '$keystroke occursOn',
    );
    expect(keystroke, 0);
  }

  group('budgets', () {
    testWidgets(
      'year mode over a hundred years: open, far jump, fling, keyboard, '
      'keystroke',
      yearBudgets,
    );
  });

  testWidgets(
    'year mode over a hundred years, timed',
    (tester) async {
      final lines = <String>[];
      await yearBudgets(
        tester,
        report: (label, ms, what) => lines.add(
          '  ${label.padRight(30)}${ms.toString().padLeft(7)} ms   $what',
        ),
      );
      debugPrint(
        '\n=== Overview year mode, ${year + 1 - firstYear + 1} years, '
        '412 × 915 ===',
      );
      lines.forEach(debugPrint);
    },
    tags: ['benchmark'],
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// A century of training log from [firstYear] on: a one-off entry every
/// nine days, an eight-week weekly block every year, a monthly checkup, and
/// three open-ended daily series from the first January, which end the
/// overview's span next year (D28).
List<CalendarEvent> _centuryEvents(int firstYear) {
  const categories = ['gym', 'mobility', 'other'];
  const kinds = ['Squat', 'Run', 'Swim', 'Stretch', 'Checkup'];
  final first = DateTime.utc(firstYear, 1, 1);
  final events = <CalendarEvent>[
    for (var i = 0; i < 4000; i++)
      CalendarEvent(
        id: 'one-$i',
        title: '${kinds[i % kinds.length]} $i',
        categoryId: categories[i % categories.length],
        startDate: first.add(Duration(days: i * 9)),
        rule: const OneTimeRecurrence(),
      ),
    for (var i = 0; i < 100; i++)
      CalendarEvent(
        id: 'block-$i',
        title: 'Block $i',
        categoryId: categories[i % categories.length],
        startDate: DateTime.utc(firstYear + i, 3, 1),
        endDate: DateTime.utc(firstYear + i, 4, 26),
        rule: WeeklyRecurrence(weekdays: {1 + i % 7, 1 + (i + 3) % 7}),
      ),
    CalendarEvent(
      id: 'checkup',
      title: 'Checkup',
      categoryId: 'other',
      startDate: first,
      rule: const MonthlyRecurrence(),
    ),
    for (var i = 0; i < 3; i++)
      CalendarEvent(
        id: 'daily-$i',
        title: 'Daily ${kinds[i]}',
        categoryId: categories[i],
        startDate: first,
        rule: const DailyRecurrence(),
      ),
  ];
  return events;
}
