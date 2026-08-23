import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_panel_mode.dart';
import 'package:anta/models/calendar_selection_source.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/widgets/calendar_bottom_panel.dart';
import 'package:anta/widgets/upcoming_agenda_view.dart';

import '../database/support/db_test_support.dart';

/// Guards where the upcoming agenda's look-ahead window starts.
///
/// The selection and the window are deliberately two different things: an
/// agenda row tap moves the grid but must not truncate the list it was tapped
/// in, and with "start from selected day" off a grid tap must not move the
/// window at all. Every rule lives in `CalendarBottomPanel._syncAnchor`, and
/// none of them is observable from `UpcomingAgendaView` — that widget only ever
/// sees the anchor it is handed, which is exactly why these run at panel level.
void main() {
  late CalendarBloc bloc;

  final today = EventAgenda.dateOnly(DateTime.now());
  final selected = DateTime.utc(2026, 8, 10);
  final later = DateTime.utc(2026, 8, 20);

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    SettingsService.forTesting(await openTestDatabase());
    // In upcoming mode the panel touches the bloc only to dispatch a row tap,
    // so a service that never resolves keeps it inert and this test off the
    // real database.
    bloc = CalendarBloc(service: Completer<CalendarEventService>().future);
  });

  tearDown(() async {
    await bloc.close();
    SettingsService.reset();
  });

  /// The panel restores its mode and filters from settings in `initState`, so
  /// both have to be on disk before it is pumped.
  Future<void> persist({required bool followSelectedDay}) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarPanelMode(CalendarPanelMode.upcoming);
    await settings.saveUpcomingAgendaFilters(
      UpcomingAgendaFilters(followSelectedDay: followSelectedDay),
    );
  }

  CalendarPageLoaded stateFor(
    DateTime selectedDay,
    CalendarSelectionSource source,
  ) {
    return CalendarPageLoaded(
      allEvents: const [],
      focusedDay: selectedDay,
      selectedDay: selectedDay,
      selectionSource: source,
    );
  }

  Future<void> pumpPanel(WidgetTester tester, CalendarPageLoaded loaded) async {
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
    // The settings read is a real async gap before the panel can switch into
    // upcoming mode. Pump a bounded number of frames rather than settling, so
    // a stalled read fails with a missing-widget error instead of hanging.
    for (var i = 0; i < 20; i++) {
      if (find.byType(UpcomingAgendaView).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  UpcomingAgendaView agenda(WidgetTester tester) =>
      tester.widget<UpcomingAgendaView>(find.byType(UpcomingAgendaView));

  group('following off', () {
    testWidgets('the window starts today, not on the selection', (
      tester,
    ) async {
      await persist(followSelectedDay: false);
      await pumpPanel(tester, stateFor(selected, CalendarSelectionSource.grid));

      expect(agenda(tester).anchorDay, today);
    });

    testWidgets('a grid tap does not move the window', (tester) async {
      await persist(followSelectedDay: false);
      await pumpPanel(tester, stateFor(selected, CalendarSelectionSource.grid));
      await pumpPanel(tester, stateFor(later, CalendarSelectionSource.grid));

      expect(agenda(tester).anchorDay, today);
    });
  });

  group('following on', () {
    testWidgets('the window adopts the selection it opened on', (tester) async {
      await persist(followSelectedDay: true);
      await pumpPanel(tester, stateFor(selected, CalendarSelectionSource.grid));

      expect(agenda(tester).anchorDay, selected);
    });

    testWidgets('a grid tap re-anchors the window', (tester) async {
      await persist(followSelectedDay: true);
      await pumpPanel(tester, stateFor(selected, CalendarSelectionSource.grid));
      await pumpPanel(tester, stateFor(later, CalendarSelectionSource.grid));

      expect(agenda(tester).anchorDay, later);
    });

    testWidgets('navigation, like "today", also re-anchors', (tester) async {
      await persist(followSelectedDay: true);
      await pumpPanel(tester, stateFor(selected, CalendarSelectionSource.grid));
      await pumpPanel(
        tester,
        stateFor(later, CalendarSelectionSource.navigation),
      );

      expect(agenda(tester).anchorDay, later);
    });

    testWidgets('an agenda row tap never re-anchors', (tester) async {
      await persist(followSelectedDay: true);
      await pumpPanel(tester, stateFor(selected, CalendarSelectionSource.grid));
      await pumpPanel(
        tester,
        stateFor(later, CalendarSelectionSource.agendaRow),
      );

      // The whole point of the selection source: the row moved the selection,
      // so the grid and the day panel follow it, but the list the tap landed
      // in did not lose everything above the tapped day.
      expect(agenda(tester).anchorDay, selected);
    });
  });

  testWidgets('turning following off returns the window to today', (
    tester,
  ) async {
    await persist(followSelectedDay: true);
    await pumpPanel(tester, stateFor(selected, CalendarSelectionSource.grid));
    expect(agenda(tester).anchorDay, selected);

    final view = agenda(tester);
    view.onFiltersChanged(view.filters.copyWith(followSelectedDay: false));
    await tester.pump();

    expect(agenda(tester).anchorDay, today);
  });

  testWidgets('the header chip callback returns the window to today', (
    tester,
  ) async {
    await persist(followSelectedDay: true);
    await pumpPanel(tester, stateFor(selected, CalendarSelectionSource.grid));

    agenda(tester).onResetAnchor!();
    await tester.pump();

    expect(agenda(tester).anchorDay, today);
  });
}
