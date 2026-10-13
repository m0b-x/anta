@Tags(['benchmark'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/overview_list_metrics.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/agenda_day_list_mode.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/overview_period.dart';
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
import 'package:anta/widgets/form_rows.dart';

import '../database/support/db_test_support.dart';
import 'support/overview_robot.dart';

/// The overview's list mode over seeded volume, against the budgets of the
/// List mode rework (`docs/calendar-overview-list-roadmap.md` §3.8 item 7,
/// §7 item 11).
///
/// **Tagged `benchmark` and excluded from the default run** (see
/// `dart_test.yaml`) because it is slow, not because it is flaky. Run it
/// deliberately:
///
/// ```powershell
/// flutter test test/widgets/overview_list_benchmark_test.dart --tags benchmark --run-skipped
/// ```
///
/// The budgets are asserted in scans and row builds, never in milliseconds:
/// wall-clock numbers are printed for reading, and are not a pass/fail
/// signal. A scan is one `EventAgenda.occurrencesInRange` call; its cost in
/// `occursOn` calls is measured on the same events up front, so a budget of
/// "one scan" is the `occursOn` count one scan of that range costs.
void main() {
  late CalendarBloc bloc;
  late ImportExportBloc importExport;
  late AppDatabase db;

  final today = EventAgenda.dateOnly(DateTime.now());
  final year = today.year;
  final en = lookupAppLocalizations(const Locale('en'));

  void emitEvents(List<CalendarEvent> events) {
    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(
      CalendarPageLoaded(
        allEvents: events,
        focusedDay: today,
        selectedDay: today,
      ),
    );
  }

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
    emitEvents(_mixedEvents(year));
  });

  tearDown(() async {
    await bloc.close();
    await importExport.close();
    CalendarCategories.updateCache(const []);
    SettingsService.reset();
    await db.close();
  });

  /// What one scan of [year] over [events] costs in `occursOn` calls.
  int yearScan(List<CalendarEvent> events, int year) {
    CalendarEvent.debugOccursOnCalls = 0;
    EventAgenda.occurrencesInRange(
      events: events,
      from: DateTime.utc(year, 1, 1),
      to: DateTime.utc(year, 12, 31),
    );
    return CalendarEvent.debugOccursOnCalls;
  }

  testWidgets(
    'list mode over 10 000 events: open, a preset, keystroke, far jump',
    (tester) async {
      final robot = OverviewRobot(tester);
      final lines = <String>[];
      final events = (bloc.state as CalendarPageLoaded).allEvents;
      final thisYearScan = yearScan(events, year);
      final lastYearScan = yearScan(events, year - 1);

      Future<int> measure(String label, Future<void> Function() body) async {
        CalendarEvent.debugOccursOnCalls = 0;
        final watch = Stopwatch()..start();
        await body();
        watch.stop();
        final calls = CalendarEvent.debugOccursOnCalls;
        lines.add(
          '  ${label.padRight(28)}'
          '${watch.elapsedMilliseconds.toString().padLeft(7)} ms'
          '${calls.toString().padLeft(10)} occursOn',
        );
        return calls;
      }

      final open = await measure(
        'open in list mode',
        () => robot.open(
          bloc: bloc,
          importExport: importExport,
          mode: AgendaDayListMode.list,
          surface: const Size(412, 915),
        ),
      );
      await measure(
        'prewarm (250 ms later)',
        () => tester.pump(const Duration(milliseconds: 250)),
      );
      final last12 = await measure(
        'preset: last 12 months',
        () => robot.pickPeriod(OverviewPeriodChoice.last12Months),
      );
      await robot.pickPeriod(OverviewPeriodChoice.thisYear);
      await tester.pump(const Duration(milliseconds: 300));
      final keystroke = await measure(
        'keystroke pause',
        () => robot.typeQuery('squat'),
      );
      await robot.clearQuery();
      await tester.pump(const Duration(milliseconds: 300));

      // A row of the list is a section label or a row in its shell.
      var rowBuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        final widget = element.widget;
        if ((widget is FormRowShell || widget is FormSectionLabel) &&
            element.findAncestorWidgetOfExactType<CustomScrollView>() != null) {
          rowBuilds++;
        }
      };
      final before = robot.listMaxOffset;
      try {
        await measure(
          'far jumpTo(maxScrollExtent)',
          () => robot.scrollListTo(robot.listMaxOffset),
        );
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      final smallest = robot.laidOutRows
          .map((row) => row.$2)
          .reduce((a, b) => a < b ? a : b);
      final viewportsWorth =
          ((robot.listViewportExtent +
                      2 * RenderAbstractViewport.defaultCacheExtent) /
                  smallest)
              .ceil();
      final farJumpBuilds = rowBuilds;
      final landed = robot.listOffset;
      final extentAfter = robot.listMaxOffset;

      // A fling back from the end, where every frame used to walk the
      // extents of every row before it (review 17): read, not asserted.
      rowBuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        final widget = element.widget;
        if ((widget is FormRowShell || widget is FormSectionLabel) &&
            element.findAncestorWidgetOfExactType<CustomScrollView>() != null) {
          rowBuilds++;
        }
      };
      final flingWatch = Stopwatch()..start();
      try {
        await tester.fling(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
          const Offset(0, 600),
          6000,
        );
        await tester.pumpAndSettle();
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      flingWatch.stop();
      final flingBuilds = rowBuilds;
      rowBuilds = farJumpBuilds;

      lines
        ..add('  one scan of $year: $thisYearScan occursOn')
        ..add('  far jump: $rowBuilds row builds (budget $viewportsWorth)')
        ..add(
          '  fling from the end: $flingBuilds row builds in '
          '${flingWatch.elapsedMilliseconds} ms',
        )
        ..add(
          '  far jump: estimated extent ${before.round()} px before, '
          '${extentAfter.round()} px after, '
          'landed at ${landed.round()} px',
        );

      debugPrint('\n=== Overview list mode, 10 000 events, $year ===');
      lines.forEach(debugPrint);

      expect(robot.currentMode, AgendaDayListMode.list);
      // This year: one scan.
      expect(open, lessThanOrEqualTo(thisYearScan));
      // Twelve months that may straddle New Year: two scans at most.
      expect(last12, lessThanOrEqualTo(lastYearScan + thisYearScan));
      // The query is a post-filter (T3).
      expect(keystroke, 0);
      // A viewport's worth: the viewport and the cache band on either side
      // of it, at the smallest slot a row takes.
      expect(rowBuilds, greaterThan(0));
      expect(rowBuilds, lessThanOrEqualTo(viewportsWorth));
      expect(landed, extentAfter);
      expect(extentAfter, before, reason: 'the extent was exact before');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'All time over eight years: two years with the frame, the rest in later '
    'turns',
    (tester) async {
      final robot = OverviewRobot(tester);
      AgendaMonthStore? store;
      emitEvents(const []);
      await robot.open(
        bloc: bloc,
        importExport: importExport,
        mode: AgendaDayListMode.list,
        period: const OverviewRollingPeriod(OverviewRollingPreset.allTime),
        surface: const Size(412, 915),
        onStore: (resolved) => store = resolved,
      );
      final first = DateTime.utc(year - 7, 1, 1);
      final months = [
        for (
          var month = first;
          !month.isAfter(today);
          month = DateTime.utc(month.year, month.month + 1, 1)
        )
          month,
      ];

      // A bloc emit is a rebuild whose frame can be pumped without letting
      // the clock move, so the turns after it are counted apart.
      final watch = Stopwatch()..start();
      emitEvents(_oneOffEvents(year, years: 8));
      await robot.pumpWithoutTurns();
      watch.stop();
      final syncMs = watch.elapsedMilliseconds;

      final synced = months.take(OverviewListMetrics.syncMonths);
      final pending = months.skip(OverviewListMetrics.syncMonths);
      expect(synced.every((month) => store!.cached(month) != null), isTrue);
      expect(pending.every((month) => store!.cached(month) == null), isTrue);
      await robot.scrollListTo(robot.listMaxOffset, settle: false);
      expect(robot.listTexts.last, en.overviewLoading);

      watch
        ..reset()
        ..start();
      await robot.finishResolving();
      watch.stop();

      debugPrint('\n=== Overview list mode, All time over 8 years ===');
      debugPrint(
        '  ${months.length} months: first ${synced.length} with the frame '
        'in $syncMs ms, the other ${pending.length} in '
        '${watch.elapsedMilliseconds} ms of later turns',
      );

      expect(months.every((month) => store!.cached(month) != null), isTrue);
      await robot.scrollListTo(robot.listMaxOffset);
      expect(robot.shows(en.overviewLoading), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// 10 000 events shaped like a long training log: mostly one-off entries
/// spread over ten years, with weekly blocks on weekday sets, monthly and
/// yearly series, short daily runs, and five retroactive open-ended daily
/// series that reach every year of the bounds.
List<CalendarEvent> _mixedEvents(int year) {
  const categories = ['gym', 'mobility', 'other'];
  const kinds = ['Squat', 'Run', 'Swim', 'Stretch', 'Checkup'];
  final first = DateTime.utc(year - 9, 1, 1);
  final events = <CalendarEvent>[];
  for (var i = 0; i < 10000; i++) {
    final start = first.add(Duration(days: (i * 37) % (365 * 10)));
    final slot = i % 100;
    final (
      RecurrenceRule rule,
      DateTime? endDate,
      bool retroactive,
    ) = switch (slot) {
      < 90 => (const OneTimeRecurrence(), null, false),
      < 96 => (
        WeeklyRecurrence(weekdays: {1 + i % 7, 1 + (i + 3) % 7}),
        start.add(const Duration(days: 56)),
        false,
      ),
      < 98 => (const MonthlyRecurrence(), null, false),
      98 => (
        const DailyRecurrence(),
        start.add(const Duration(days: 14)),
        false,
      ),
      _ when i < 500 => (const DailyRecurrence(), null, true),
      _ => (const YearlyRecurrence(), null, false),
    };
    events.add(
      CalendarEvent(
        id: 'bench-$i',
        title: '${kinds[i % kinds.length]} $i',
        categoryId: categories[i % categories.length],
        startDate: start,
        endDate: endDate,
        rule: rule,
        retroactive: retroactive,
      ),
    );
  }
  return events;
}

/// 10 000 one-off entries over [years] years ending this one — a log All
/// time spans from its first January, under the entry cap.
List<CalendarEvent> _oneOffEvents(int year, {required int years}) {
  const categories = ['gym', 'mobility', 'other'];
  final first = DateTime.utc(year - years + 1, 1, 1);
  return [
    for (var i = 0; i < 10000; i++)
      CalendarEvent(
        id: 'log-$i',
        title: 'Entry $i',
        categoryId: categories[i % categories.length],
        startDate: first.add(Duration(days: (i * 37) % (365 * years))),
        rule: const OneTimeRecurrence(),
      ),
  ];
}
