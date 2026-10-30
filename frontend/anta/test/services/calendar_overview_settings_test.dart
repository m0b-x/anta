import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/agenda_day_list_mode.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/overview_list_options.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// The overview's settings read in one statement: a fresh install opens on
/// this year with the default list options, a kept period and the options
/// round-trip, a period that is not kept clears its key, and values written
/// by a newer build degrade to the defaults.
void main() {
  late AppDatabase db;
  late SettingsService settings;
  final today = DateTime.utc(2026, 10, 11);

  setUp(() async {
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
  });

  tearDown(() async {
    SettingsService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  test('a fresh install opens on this year with the default options', () async {
    final loaded = await settings.getCalendarOverviewSettings(today: today);

    expect(loaded.mode, AgendaDayListMode.year);
    expect(loaded.categoryIds, isEmpty);
    expect(loaded.period, const OverviewYearPeriod(2026));
    expect(loaded.listOptions, OverviewListOptions.defaults);
  });

  for (final preset in OverviewRollingPreset.values) {
    test('${preset.name} survives a round trip', () async {
      await settings.setCalendarOverviewPeriod(
        OverviewRollingPeriod(preset),
        today: today,
      );

      final loaded = await settings.getCalendarOverviewSettings(today: today);
      expect(loaded.period, OverviewRollingPeriod(preset));
      expect(
        await db.userSettingsDao.getValue(SettingsKeys.calendarOverviewPeriod),
        'preset:${preset.name}',
      );
    });
  }

  test('this year is stored as thisYear and reads as the year of the day '
      'it is read', () async {
    await settings.setCalendarOverviewPeriod(
      const OverviewYearPeriod(2026),
      today: today,
    );

    expect(
      await db.userSettingsDao.getValue(SettingsKeys.calendarOverviewPeriod),
      'thisYear',
    );
    final nextYear = await settings.getCalendarOverviewSettings(
      today: DateTime.utc(2027, 1, 2),
    );
    expect(nextYear.period, const OverviewYearPeriod(2027));
  });

  // October 11, 2026 is a Sunday.
  test('this week reads on the stored week start, this month as the month '
      'of the day it is read', () async {
    await settings.setCalendarOverviewPeriod(
      OverviewPeriod.thisWeek(
        today: today,
        weekStart: CalendarWeekStart.monday,
      ),
      today: today,
    );
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.calendarOverviewPeriod),
      'thisWeek',
    );
    expect(
      (await settings.getCalendarOverviewSettings(today: today)).period,
      OverviewWeekPeriod(DateTime.utc(2026, 10, 5)),
    );

    await settings.setCalendarWeekStart(CalendarWeekStart.sunday);
    expect(
      (await settings.getCalendarOverviewSettings(today: today)).period,
      OverviewWeekPeriod(DateTime.utc(2026, 10, 11)),
    );
    await settings.setCalendarWeekStart(CalendarWeekStart.saturday);
    expect(
      (await settings.getCalendarOverviewSettings(today: today)).period,
      OverviewWeekPeriod(DateTime.utc(2026, 10, 10)),
    );

    await settings.setCalendarOverviewPeriod(
      OverviewPeriod.thisMonth(today: today),
      today: today,
    );
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.calendarOverviewPeriod),
      'thisMonth',
    );
    final nextMonth = await settings.getCalendarOverviewSettings(
      today: DateTime.utc(2026, 11, 2),
    );
    expect(nextMonth.period, const OverviewMonthPeriod(2026, 11));
  });

  test('a paged week or month clears the stored period', () async {
    await settings.setCalendarOverviewPeriod(
      OverviewPeriod.thisMonth(today: today),
      today: today,
    );
    await settings.setCalendarOverviewPeriod(
      OverviewWeekPeriod(DateTime.utc(2026, 9, 28)),
      today: today,
    );
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.calendarOverviewPeriod),
      isNull,
    );

    await settings.setCalendarOverviewPeriod(
      OverviewPeriod.thisMonth(today: today),
      today: today,
    );
    await settings.setCalendarOverviewPeriod(
      const OverviewMonthPeriod(2026, 9),
      today: today,
    );
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.calendarOverviewPeriod),
      isNull,
    );
  });

  test('a custom span or a past year clears the stored period', () async {
    await settings.setCalendarOverviewPeriod(
      const OverviewRollingPeriod(OverviewRollingPreset.last90Days),
      today: today,
    );
    await settings.setCalendarOverviewPeriod(
      OverviewCustomPeriod(DateTime.utc(2026, 3, 1), DateTime.utc(2026, 4, 1)),
      today: today,
    );

    expect(
      await db.userSettingsDao.getValue(SettingsKeys.calendarOverviewPeriod),
      isNull,
    );
    expect(
      (await settings.getCalendarOverviewSettings(today: today)).period,
      const OverviewYearPeriod(2026),
    );

    await settings.setCalendarOverviewPeriod(
      const OverviewRollingPeriod(OverviewRollingPreset.allTime),
      today: today,
    );
    await settings.setCalendarOverviewPeriod(
      const OverviewYearPeriod(2024),
      today: today,
    );
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.calendarOverviewPeriod),
      isNull,
    );
  });

  test('the list options round-trip, Missed only never persists', () async {
    await settings.setCalendarOverviewListOptions(
      const OverviewListOptions(
        order: OverviewOrder.newestFirst,
        rows: OverviewRows.perEvent,
        missedOnly: true,
      ),
    );

    final loaded = await settings.getCalendarOverviewSettings(today: today);
    expect(
      loaded.listOptions,
      const OverviewListOptions(
        order: OverviewOrder.newestFirst,
        rows: OverviewRows.perEvent,
      ),
    );
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.calendarOverviewOrder),
      'newestFirst',
    );
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.calendarOverviewRows),
      'perEvent',
    );
  });

  test('values written by a newer build degrade to the defaults', () async {
    await db.userSettingsDao.setValues({
      SettingsKeys.calendarOverviewPeriod: 'preset:nextDecade',
      SettingsKeys.calendarOverviewOrder: 'byColour',
      SettingsKeys.calendarOverviewRows: 'perWeek',
    });

    final loaded = await settings.getCalendarOverviewSettings(today: today);
    expect(loaded.period, const OverviewYearPeriod(2026));
    expect(loaded.listOptions, OverviewListOptions.defaults);
  });

  test('the new settings leave the mode and the categories alone', () async {
    await settings.setCalendarOverviewMode(AgendaDayListMode.list);
    await settings.setCalendarOverviewCategories({'gym', 'health'});
    await settings.setCalendarOverviewPeriod(
      const OverviewRollingPeriod(OverviewRollingPreset.last12Months),
      today: today,
    );
    await settings.setCalendarOverviewListOptions(
      const OverviewListOptions(order: OverviewOrder.newestFirst),
    );

    final loaded = await settings.getCalendarOverviewSettings(today: today);
    expect(loaded.mode, AgendaDayListMode.list);
    expect(loaded.categoryIds, {'gym', 'health'});
  });

  test('the default keys name real values', () {
    expect(
      OverviewOrder.fromName(SettingsKeys.defaultCalendarOverviewOrder).name,
      SettingsKeys.defaultCalendarOverviewOrder,
    );
    expect(
      OverviewRows.fromName(SettingsKeys.defaultCalendarOverviewRows).name,
      SettingsKeys.defaultCalendarOverviewRows,
    );
  });
}
