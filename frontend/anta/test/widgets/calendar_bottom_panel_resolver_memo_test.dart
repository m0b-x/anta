import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_panel_mode.dart';
import 'package:anta/models/calendar_selection_source.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/day_summary_resolver.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/widgets/calendar_bottom_panel.dart';
import 'package:anta/widgets/day_summary_panel.dart';

import '../database/support/db_test_support.dart';

/// Guard for **4.3**: the day panel's [DaySummaryResolver] is built once and
/// reused, not reconstructed inside `build`.
///
/// `DaySummaryResolver.defaults` allocates five stateless providers, and it
/// used to be called straight from `CalendarBottomPanel._buildPanel` — so a
/// day tap, a presence tick, or any parent rebuild threw away five identical
/// objects and made five more. Its only inputs are the localization and the
/// recurrence-label setting.
///
/// Counted through `DaySummaryResolver.debugDefaultsBuilds` because the memo
/// has no other seam: the resolver is private state on the panel, and
/// `resolve` returns a freshly built list whether or not the instance was
/// reused, so an output comparison could not tell the two apart.
///
/// Runs at panel level, and `SettingsService` is pointed at a same-isolate
/// database — the panel issues its settings read from its own `initState`,
/// outside any `runAsync` a test controls, and on the real database that read
/// never resolves inside `testWidgets`' fake-async zone.
void main() {
  late CalendarBloc bloc;

  final selected = DateTime.utc(2026, 8, 10);
  final later = DateTime.utc(2026, 8, 20);

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    SettingsService.forTesting(await openTestDatabase());
    final settings = await SettingsService.getInstance();
    await settings.setCalendarPanelMode(CalendarPanelMode.day);
    // The panel reads the bloc only for `eventsForDay`, which returns const []
    // until the bloc is loaded — enough to build the day panel, and it keeps
    // this test off the real database.
    bloc = CalendarBloc(service: Completer<CalendarEventService>().future);
  });

  tearDown(() async {
    await bloc.close();
    SettingsService.reset();
  });

  CalendarPageLoaded stateFor(DateTime selectedDay) => CalendarPageLoaded(
    allEvents: const [],
    focusedDay: selectedDay,
    selectedDay: selectedDay,
    selectionSource: CalendarSelectionSource.grid,
  );

  Future<void> pumpPanel(
    WidgetTester tester,
    CalendarPageLoaded loaded, {
    required bool showRecurrenceLabels,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider<CalendarBloc>.value(
          value: bloc,
          child: Scaffold(
            body: CalendarBottomPanel(
              loaded: loaded,
              expanded: false,
              showRecurrenceLabels: showRecurrenceLabels,
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
    // The mode restore is a real async gap. Pump a bounded number of frames
    // rather than settling, so a stalled read fails with a missing-widget
    // error instead of hanging.
    for (var i = 0; i < 20; i++) {
      if (find.byType(DaySummaryPanel).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(DaySummaryPanel), findsOneWidget);
  }

  testWidgets('rebuilds reuse the resolver instead of rebuilding it', (
    tester,
  ) async {
    await pumpPanel(tester, stateFor(selected), showRecurrenceLabels: true);
    DaySummaryResolver.debugDefaultsBuilds = 0;

    // A day change and two plain repaints: none of them touches an input the
    // providers depend on.
    await pumpPanel(tester, stateFor(later), showRecurrenceLabels: true);
    await pumpPanel(tester, stateFor(selected), showRecurrenceLabels: true);
    await tester.pump();

    expect(DaySummaryResolver.debugDefaultsBuilds, 0);
  });

  testWidgets('the recurrence-label setting does rebuild it, once', (
    tester,
  ) async {
    await pumpPanel(tester, stateFor(selected), showRecurrenceLabels: true);
    DaySummaryResolver.debugDefaultsBuilds = 0;

    await pumpPanel(tester, stateFor(selected), showRecurrenceLabels: false);
    expect(DaySummaryResolver.debugDefaultsBuilds, 1);

    // The new value is now the memo's key, so it stays put.
    await pumpPanel(tester, stateFor(later), showRecurrenceLabels: false);
    expect(DaySummaryResolver.debugDefaultsBuilds, 1);
  });
}
