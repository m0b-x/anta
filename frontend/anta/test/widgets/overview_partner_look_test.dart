import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/agenda_day_list_mode.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/day_bar.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/pages/calendar_overview_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/overview_view_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/year_month_tile.dart';

import '../database/support/db_test_support.dart';
import 'support/overview_robot.dart';

/// The overview draws a partner's event as the calendar page does
/// (`docs/cloud-share-surfaces-roadmap.md` §6.7, D15): its Month mode grid
/// says whose a bar is and draws it hollow under the Outlined look, a look
/// picked on the settings page repaints it on the way back, and the Years
/// mode tiles summarise my days alone. My own events draw as they always
/// did.
void main() {
  late CalendarBloc bloc;
  late ImportExportBloc importExport;
  late AppDatabase db;

  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  final today = EventAgenda.dateOnly(DateTime.now());
  DateTime dayOf(int day) => DateTime.utc(today.year, today.month, day);

  CalendarEvent once(
    String id,
    String title,
    int day, {
    String categoryId = 'gym',
    bool fromPartner = false,
  }) => CalendarEvent(
    id: id,
    title: title,
    categoryId: categoryId,
    startDate: dayOf(day),
    rule: const OneTimeRecurrence(),
    fromPartner: fromPartner,
  );

  /// Day 10 holds mine and theirs, day 15 mine alone, day 20 theirs alone.
  final mineShared = once('m1', 'Leg day', 10);
  final mineAlone = once('m2', 'Stretch', 15);
  final theirsShared = once(
    'p1',
    'Night shift',
    10,
    categoryId: 'health',
    fromPartner: true,
  );
  final theirsAlone = once(
    'p2',
    'Night shift',
    20,
    categoryId: 'health',
    fromPartner: true,
  );

  void emit(List<CalendarEvent> events) {
    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(
      CalendarPageLoaded(
        allEvents: events,
        focusedDay: today,
        selectedDay: today,
        holdsPartnerEvents: events.any((event) => event.fromPartner),
      ),
    );
  }

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    db = await openTestDatabase();
    SettingsService.forTesting(db);
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
    bloc = CalendarBloc(service: Completer<CalendarEventService>().future);
    emit([mineShared, mineAlone, theirsShared, theirsAlone]);
  });

  tearDown(() async {
    await bloc.close();
    await importExport.close();
    CalendarCategories.updateCache(const []);
    SettingsService.reset();
    OverviewViewService.reset();
    await db.close();
  });

  /// The strip of [day] in Month mode's grid, told by the titles on it.
  CalendarDayBars stripOn(WidgetTester tester, int day) {
    final titles = switch (day) {
      10 => {'Leg day', 'Night shift'},
      15 => {'Stretch'},
      _ => {'Night shift'},
    };
    return tester
        .widgetList<CalendarDayBars>(find.byType(CalendarDayBars))
        .singleWhere(
          (strip) =>
              strip.bars.length == titles.length &&
              titles.every(
                (title) => strip.bars.any(
                  (bar) => bar.semanticLabel.startsWith(title),
                ),
              ),
        );
  }

  DayBar barTitled(CalendarDayBars strip, String title) =>
      strip.bars.singleWhere((bar) => bar.semanticLabel.startsWith(title));

  Future<OverviewRobot> openMonth(WidgetTester tester) async {
    final robot = OverviewRobot(tester);
    await robot.open(
      bloc: bloc,
      importExport: importExport,
      mode: AgendaDayListMode.month,
      period: OverviewPeriod.thisMonth(today: today),
      surface: const Size(412, 915),
    );
    await robot.finishResolving();
    return robot;
  }

  Color pageGroundOf(WidgetTester tester) => Theme.of(
    tester.element(find.byType(CalendarOverviewPage)),
  ).colorScheme.pageGround;

  testWidgets('Month mode draws a partner\'s bar hollow under the default '
      'look, on the page ground, saying whose it is; mine is unchanged', (
    tester,
  ) async {
    await openMonth(tester);

    final shared = stripOn(tester, 10);
    final theirs = barTitled(shared, 'Night shift');
    expect(theirs.hollow, isTrue);
    // No pairing is read here, so the name is the stand-in.
    expect(theirs.semanticLabel, 'Night shift, From your partner');
    expect(shared.ground, pageGroundOf(tester));
    final mine = barTitled(shared, 'Leg day');
    expect(mine.hollow, isFalse);
    expect(mine.semanticLabel, 'Leg day');

    final alone = stripOn(tester, 15);
    expect(alone.ground, isNull, reason: 'no hollow marker, no new ground');
    expect(alone.bars.single.hollow, isFalse);
    expect(alone.bars.single.semanticLabel, 'Stretch');
  });

  testWidgets('a look picked on a page above repaints the grid on the way '
      'back: filled, still saying whose it is', (tester) async {
    final robot = await openMonth(tester);
    expect(barTitled(stripOn(tester, 10), 'Night shift').hollow, isTrue);

    await robot.cover();
    await tester.runAsync(() async {
      final settings = await SettingsService.getInstance();
      await settings.setShareEventLook(ShareEventLook.avatar);
    });
    await robot.uncover();
    await robot.finishResolving();

    final theirs = barTitled(stripOn(tester, 10), 'Night shift');
    expect(theirs.hollow, isFalse);
    expect(theirs.semanticLabel, 'Night shift, From your partner');
    expect(stripOn(tester, 10).ground, isNull);
    expect(barTitled(stripOn(tester, 10), 'Leg day').semanticLabel, 'Leg day');
  });

  testWidgets('Years mode counts and marks my days alone: a day only a '
      'partner\'s event is on stays blank', (tester) async {
    final robot = OverviewRobot(tester);
    await robot.open(
      bloc: bloc,
      importExport: importExport,
      mode: AgendaDayListMode.year,
      surface: const Size(412, 915),
    );
    await robot.finishResolving();

    final tile = tester
        .widgetList<YearMonthTile>(robot.yearTiles(today.year))
        .elementAt(today.month - 1);
    expect(tile.count, '2', reason: 'Leg day and Stretch');
    final matrix = robot.yearMatrices(today.year)[today.month - 1];
    expect(matrix.markedMask, (1 << 9) | (1 << 14));
    expect(
      matrix.dayColors?[9],
      CalendarCategories.resolve('gym').color,
      reason: 'my event is day 10\'s top colour, though theirs is on it',
    );
  });

  /// The allowlist narrows the overview's scan by the stored category id,
  /// so a partner's own category the options sheet now offers keeps its
  /// events listed, and one left out drops them, as one of mine would.
  testWidgets('an allowlist holding one of a partner\'s own categories lists '
      'its events and no other category\'s', (tester) async {
    CalendarCategories.updateCache([
      ...CalendarCategories.all,
      for (final (id, name) in const [
        ('p-night', 'Night shift'),
        ('p-pilates', 'Pilates'),
      ])
        CalendarCategory(
          id: id,
          name: name,
          colorValue: 0xFF8E24AA,
          iconKey: 'work',
          sortOrder: 0,
          isBuiltIn: false,
          fromPartner: true,
        ),
    ]);
    emit([
      mineShared,
      once('p3', 'Ward round', 12, categoryId: 'p-night', fromPartner: true),
      once('p4', 'Reformer', 14, categoryId: 'p-pilates', fromPartner: true),
    ]);
    final settings = await SettingsService.getInstance();
    await settings.setCalendarOverviewCategories({'p-night'});

    final robot = OverviewRobot(tester);
    await robot.open(
      bloc: bloc,
      importExport: importExport,
      mode: AgendaDayListMode.list,
      period: OverviewPeriod.thisMonth(today: today),
      surface: const Size(412, 915),
    );
    await robot.finishResolving();

    expect(robot.shows('Ward round'), isTrue);
    expect(robot.shows('Reformer'), isFalse);
    expect(robot.shows('Leg day'), isFalse);
  });

  testWidgets('Years mode for someone who never paired counts as before', (
    tester,
  ) async {
    emit([mineShared, mineAlone]);
    final robot = OverviewRobot(tester);
    await robot.open(
      bloc: bloc,
      importExport: importExport,
      mode: AgendaDayListMode.year,
      surface: const Size(412, 915),
    );
    await robot.finishResolving();

    final tile = tester
        .widgetList<YearMonthTile>(robot.yearTiles(today.year))
        .elementAt(today.month - 1);
    expect(tile.count, '2');
    expect(
      robot.yearMatrices(today.year)[today.month - 1].markedMask,
      (1 << 9) | (1 << 14),
    );
  });
}
