import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/agenda_day_list_mode.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_panel_mode.dart';
import 'package:anta/models/calendar_selection_source.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/widgets/calendar_bottom_panel.dart';
import 'package:anta/widgets/day_summary_panel.dart';
import 'package:anta/widgets/day_timeline_view.dart';
import 'package:anta/widgets/upcoming_agenda_view.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';

/// Guards the panel's restore in `initState`: it must never overwrite a
/// mode, a drill-down mode or agenda filters the user set while the settings
/// reads were still out, which on a device snapped a tap on Upcoming back to
/// Day within ~1.5 s of landing on the calendar — and must never let such an
/// early change wipe the stored filters either. Also the mode bar at large
/// text, measured in Roboto (the fit decision is a measurement, and the test
/// font draws every glyph a full em wide).
void main() {
  late AppDatabase db;
  late CalendarBloc bloc;
  late _HeldRead gate;

  setUpAll(loadGoldenFonts);

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    gate = _HeldRead();
    db = await openTestDatabase(interceptor: gate);
    SettingsService.forTesting(db);
    // The panel only dispatches to the bloc; a service that never resolves
    // keeps it inert.
    bloc = CalendarBloc(service: Completer<CalendarEventService>().future);
  });

  tearDown(() async {
    gate.release();
    await bloc.close();
    SettingsService.reset();
    await db.close();
  });

  final day = DateTime.utc(2026, 8, 10);

  void setPhone(WidgetTester tester, {Size size = const Size(360, 780)}) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    DateTime? selectedDay,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: BlocProvider<CalendarBloc>.value(
          value: bloc,
          child: Scaffold(
            body: CalendarBottomPanel(
              loaded: CalendarPageLoaded(
                allEvents: const [],
                focusedDay: day,
                selectedDay: selectedDay ?? day,
                selectionSource: CalendarSelectionSource.grid,
              ),
              appearance: const CalendarAppearance(),
              expanded: false,
              onToggleExpanded: () {},
              onEditEvent: (_, _) {},
              onShowEvent: (_, _) {},
              onOpenNote: (_) {},
              onSuppressHoliday: (_) {},
              onToggleMissed: (_, _, _) {},
              colorPalette: MarkdownColorPalette.presets,
            ),
          ),
        ),
      ),
    );
  }

  /// Bounded frames instead of a settle, so a stalled read fails on the
  /// expectation rather than hanging the suite.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Finder segment(CalendarPanelMode mode) =>
      find.bySemanticsIdentifier(SemanticsIds.panelMode(mode.name));

  Future<void> tapId(WidgetTester tester, String id) async {
    await tester.tap(find.bySemanticsIdentifier(id));
    await pumpFrames(tester);
  }

  Future<String> storedMode() async {
    final settings = await SettingsService.getInstance();
    return (await settings.getCalendarPanelMode()).name;
  }

  testWidgets('with no pick the stored mode is restored', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarPanelMode(CalendarPanelMode.timeline);

    await pumpPanel(tester);
    await pumpFrames(tester);

    expect(find.byType(DayTimelineView), findsOneWidget);
  });

  testWidgets('a pick made before the restore lands survives it', (
    tester,
  ) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarPanelMode(CalendarPanelMode.timeline);
    gate.hold(SettingsKeys.calendarPanelMode);

    await pumpPanel(tester);
    await pumpFrames(tester);
    // The mode read has run but its answer is still held: the bar shows the
    // default and the user picks Upcoming over it.
    expect(gate.held, isTrue);
    await tester.tap(segment(CalendarPanelMode.upcoming));
    await pumpFrames(tester);
    expect(find.byType(UpcomingAgendaView), findsOneWidget);

    gate.release();
    await pumpFrames(tester);

    expect(find.byType(UpcomingAgendaView), findsOneWidget);
    expect(find.byType(DayTimelineView), findsNothing);
    expect(await storedMode(), CalendarPanelMode.upcoming.name);
  });

  testWidgets('a tap on the shown segment before the restore keeps it', (
    tester,
  ) async {
    // The segmented button reports no change for the segment already
    // selected, so only the bar's own touch can say the user chose it.
    final settings = await SettingsService.getInstance();
    await settings.setCalendarPanelMode(CalendarPanelMode.timeline);
    gate.hold(SettingsKeys.calendarPanelMode);

    await pumpPanel(tester);
    await pumpFrames(tester);
    expect(gate.held, isTrue);
    expect(find.byType(DaySummaryPanel), findsOneWidget);
    await tester.tap(segment(CalendarPanelMode.day));
    await pumpFrames(tester);

    gate.release();
    await pumpFrames(tester);

    expect(find.byType(DaySummaryPanel), findsOneWidget);
    expect(find.byType(DayTimelineView), findsNothing);
    expect(await storedMode(), CalendarPanelMode.day.name);
  });

  testWidgets('an early filter change is replayed on the stored filters', (
    tester,
  ) async {
    final settings = await SettingsService.getInstance();
    await settings.saveUpcomingAgendaFilters(
      const UpcomingAgendaFilters(rangeDays: 90, query: 'gym'),
    );
    gate.hold(SettingsKeys.calendarUpcomingRangeDays);
    // Tall enough that every row of the filters sheet is on screen.
    setPhone(tester, size: const Size(800, 1400));

    await pumpPanel(tester);
    await pumpFrames(tester);
    expect(gate.held, isTrue);
    // Over the defaults: switch to the agenda and turn holidays on.
    await tester.tap(segment(CalendarPanelMode.upcoming));
    await pumpFrames(tester);
    await tapId(tester, SemanticsIds.agendaFilterOpen);
    await tapId(tester, SemanticsIds.agendaFilterHolidays);
    await tapId(tester, SemanticsIds.agendaFilterApply);
    expect(
      tester
          .widget<UpcomingAgendaView>(find.byType(UpcomingAgendaView))
          .filters
          .showHolidays,
      isTrue,
    );

    gate.release();
    await pumpFrames(tester);

    const expected = UpcomingAgendaFilters(
      rangeDays: 90,
      query: 'gym',
      showHolidays: true,
    );
    expect(
      tester
          .widget<UpcomingAgendaView>(find.byType(UpcomingAgendaView))
          .filters,
      expected,
    );
    expect(await settings.getUpcomingAgendaFilters(), expected);
  });

  testWidgets('a drill-down mode set before the restore survives it', (
    tester,
  ) async {
    final settings = await SettingsService.getInstance();
    await settings.setAgendaDayListMode(AgendaDayListMode.year);
    gate.hold(SettingsKeys.calendarDayListMode);

    await pumpPanel(tester);
    await pumpFrames(tester);
    expect(gate.held, isTrue);
    await tester.tap(segment(CalendarPanelMode.upcoming));
    await pumpFrames(tester);
    // The summary card's drill-down reports its mode through this callback.
    tester
        .widget<UpcomingAgendaView>(find.byType(UpcomingAgendaView))
        .onDayListModeChanged!(AgendaDayListMode.month);
    await pumpFrames(tester);

    gate.release();
    await pumpFrames(tester);

    expect(
      tester
          .widget<UpcomingAgendaView>(find.byType(UpcomingAgendaView))
          .dayListMode,
      AgendaDayListMode.month,
    );
    expect(await settings.getAgendaDayListMode(), AgendaDayListMode.month);
  });

  group('mode bar', () {
    Finder scrollableOverBar() => find.ancestor(
      of: find.byType(SegmentedButton<CalendarPanelMode>),
      matching: find.byType(Scrollable),
    );

    // The labelled bar's height — its 8 dp top inset over the 40 dp compact
    // expand button — which the icon segments keep, so the panel under the
    // bar starts at the same place whichever the segments show.
    const barHeight = 48.0;
    double panelTop(WidgetTester tester) =>
        tester.getTopLeft(find.byType(DaySummaryPanel)).dy;

    testWidgets('German at 2.0 on 360 shows three named icon segments', (
      tester,
    ) async {
      setPhone(tester);
      await pumpPanel(tester, locale: const Locale('de'), textScale: 2.0);
      await pumpFrames(tester);

      const names = {
        CalendarPanelMode.day: 'Tag',
        CalendarPanelMode.timeline: 'Zeitplan',
        CalendarPanelMode.upcoming: 'Demnächst',
      };
      for (final MapEntry(key: mode, value: name) in names.entries) {
        expect(
          find.descendant(of: segment(mode), matching: find.byType(Text)),
          findsNothing,
          reason: mode.name,
        );
        expect(
          find.descendant(of: segment(mode), matching: find.byType(Icon)),
          findsOneWidget,
        );
        expect(find.byTooltip(name), findsOneWidget);
        // What TalkBack and the QA dump read: the segment's merged node.
        final node = tester.getSemantics(segment(mode)).getSemanticsData();
        expect(node.identifier, SemanticsIds.panelMode(mode.name));
        expect(node.label, name);
        expect(node.hasAction(SemanticsAction.tap), isTrue);
        final button = find.ancestor(
          of: segment(mode),
          matching: find.byType(TextButton),
        );
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      }
      expect(scrollableOverBar(), findsNothing);
      expect(panelTop(tester), barHeight);
      expect(tester.takeException(), isNull);
    });

    /// The fit decision is three `TextPainter.layout()` calls, and the bar is
    /// rebuilt on every day tap — the panel's `buildWhen` watches the
    /// selection. Neither budget suite sees that path, so the measurement
    /// counter is what pins it.
    testWidgets('a day tap costs the bar no new measurement', (tester) async {
      setPhone(tester);
      await pumpPanel(tester);
      await pumpFrames(tester);
      final measured = panelModeFitMeasurements;

      await pumpPanel(tester, selectedDay: day.add(const Duration(days: 1)));
      await pumpFrames(tester);

      expect(panelModeFitMeasurements, measured);

      // The counter is live: a text scale the memo has not seen measures again.
      await pumpPanel(tester, textScale: 2.0);
      await pumpFrames(tester);

      expect(panelModeFitMeasurements, greaterThan(measured));
    });

    testWidgets('a tap on an icon segment still switches the mode', (
      tester,
    ) async {
      setPhone(tester);
      await pumpPanel(tester, locale: const Locale('de'), textScale: 2.0);
      await pumpFrames(tester);

      await tester.tap(segment(CalendarPanelMode.upcoming));
      await pumpFrames(tester);

      expect(find.byType(UpcomingAgendaView), findsOneWidget);
      expect(await storedMode(), CalendarPanelMode.upcoming.name);
    });

    for (final locale in const [Locale('en'), Locale('de'), Locale('ro')]) {
      testWidgets(
        '${locale.languageCode} at 1.0 on 360 keeps three labelled segments',
        (tester) async {
          setPhone(tester);
          await pumpPanel(tester, locale: locale);
          await pumpFrames(tester);

          for (final mode in CalendarPanelMode.values) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(
                of: segment(mode),
                matching: find.byType(RichText),
              ),
            );
            expect(paragraph.didExceedMaxLines, isFalse, reason: mode.name);
            expect(
              find.descendant(of: segment(mode), matching: find.byType(Icon)),
              findsNothing,
            );
          }
          expect(scrollableOverBar(), findsNothing);
          // The geometry the panel was laid out on: three equal thirds of
          // the row beside the expand button, 32 dp tall.
          expect(
            tester.getSize(find.byType(SegmentedButton<CalendarPanelMode>)),
            const Size(296, 32),
          );
          expect(panelTop(tester), barHeight);
        },
      );
    }
  });
}

/// Delivers one setting's read late: the select runs at once, so its answer
/// is the value stored when the panel asked, and is handed back only on
/// [release] — the shape of the race on a device, where the user's write
/// lands between the read and the restore's `setState`. The restore reads
/// its settings one after another, so every read after the held one waits
/// too.
class _HeldRead extends QueryInterceptor {
  Completer<void>? _hold;
  String? _key;
  bool held = false;

  void hold(String key) {
    _key = key;
    _hold = Completer<void>();
  }

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
    final rows = await super.runSelect(executor, statement, args);
    final hold = _hold;
    if (hold != null && args.contains(_key)) {
      held = true;
      await hold.future;
    }
    return rows;
  }
}
