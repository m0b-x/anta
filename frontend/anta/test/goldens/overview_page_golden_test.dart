@Tags(['golden'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/agenda_day_list_mode.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/calendar_overview_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/overview_view_service.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';
import '../widgets/support/layout_errors.dart';
import '../widgets/support/overview_robot.dart';
import 'support/golden_matrix.dart';

/// The calendar overview's list, harnessed and seeded as
/// `test/widgets/calendar_overview_page_test.dart` does it, with the
/// fixture's events moved into 2025.
///
/// The page always opens on this year or a span ending today, and neither is
/// persisted as a fixed date, so the golden pages the nav back to 2025: a
/// year wholly in the past, whose rows, totals and Today button no longer
/// move with the clock.
void main() {
  const shownYear = 2025;

  late CalendarBloc bloc;
  late ImportExportBloc importExport;
  late AppDatabase db;

  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  final events = [
    CalendarEvent(
      id: 'e1',
      title: 'Leg day',
      categoryId: 'gym',
      startDate: DateTime.utc(shownYear, 1, 1),
      rule: const DailyRecurrence(),
    ),
    CalendarEvent(
      id: 'e2',
      title: 'Stretch class',
      categoryId: 'mobility',
      startDate: DateTime.utc(shownYear, 1, 3),
      rule: const OneTimeRecurrence(),
    ),
    CalendarEvent(
      id: 'e3',
      title: 'Old checkup',
      categoryId: 'other',
      startDate: DateTime.utc(shownYear - 2, 6, 1),
      rule: const OneTimeRecurrence(),
    ),
  ];

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    db = await openTestDatabase();
    final settings = SettingsService.forTesting(db);
    await settings.setCalendarOverviewMode(AgendaDayListMode.list);
    // The bar's saved views button resolves the service as the page opens;
    // bound here so it never reaches for the file database.
    OverviewViewService.reset();
    await OverviewViewService.forTesting(db);
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
    final shown = DateTime.utc(shownYear, 1, 1);
    bloc = CalendarBloc(service: Completer<CalendarEventService>().future);
    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(
      CalendarPageLoaded(
        allEvents: events,
        focusedDay: shown,
        selectedDay: shown,
      ),
    );
  });

  tearDown(() async {
    await bloc.close();
    await importExport.close();
    CalendarCategories.updateCache(const []);
    SettingsService.reset();
    OverviewViewService.reset();
    await db.close();
  });

  for (final cell in goldenCells) {
    testWidgets('overview page, ${cell.label}', (tester) async {
      setGoldenSurface(tester, cell);
      final robot = OverviewRobot(tester);
      final errors = await layoutErrorsDuring(() async {
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<CalendarBloc>.value(value: bloc),
              BlocProvider<ImportExportBloc>.value(value: importExport),
            ],
            child: goldenApp(
              cell,
              navigatorObservers: [AppNavigator.routeObserver],
              home: const CalendarOverviewPage.forTesting(),
            ),
          ),
        );
        // The settings read is a real async gap; bounded frames until the
        // list replaces its spinner.
        for (var i = 0; i < 20; i++) {
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pump();
        for (var year = DateTime.now().year; year > shownYear; year--) {
          await robot.previous();
        }
        await robot.finishResolving();
      });

      expect(errors, isEmpty);
      expect(robot.navTitle, '$shownYear');
      await expectGolden('overview_page', cell);
    });
  }
}
