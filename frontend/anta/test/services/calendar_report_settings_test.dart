import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/markdown_color_syntax.dart';

import '../database/support/db_test_support.dart';

/// What the calendar report remembers (D35), read in one statement: a fresh
/// install opens on This month over every category, a stored kind decodes
/// on the day it is read and the stored week start, All time and anything
/// unreadable fall back to This month, a span that is not kept clears its
/// key, and the allowlist round-trips.
void main() {
  late AppDatabase db;
  late StatementCounter counter;
  late SettingsService settings;
  // A Sunday: the week it is in starts on the 5th, the 11th or the 10th.
  final today = DateTime.utc(2026, 10, 11);
  const october = OverviewMonthPeriod(2026, 10);

  setUp(() async {
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
    settings = SettingsService.forTesting(db);
  });

  tearDown(() async {
    SettingsService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  Future<OverviewPeriod> periodFor(String? raw) async {
    if (raw == null) {
      await db.userSettingsDao.deleteValue(SettingsKeys.reportPeriod);
    } else {
      await db.userSettingsDao.setValue(SettingsKeys.reportPeriod, raw);
    }
    return (await settings.getCalendarReportSettings(today: today)).period;
  }

  test('a fresh install opens on this month over every category', () async {
    final loaded = await settings.getCalendarReportSettings(today: today);

    expect(loaded.period, october);
    expect(loaded.categoryIds, isEmpty);
  });

  test('the read costs one statement', () async {
    counter.reset();
    await settings.getCalendarReportSettings(today: today);

    expect(counter.count, 1);
    expect(counter.selects, hasLength(1));
  });

  test('thisWeek reads on the stored week start', () async {
    expect(
      await periodFor('thisWeek'),
      OverviewWeekPeriod(DateTime.utc(2026, 10, 5)),
    );

    await settings.setCalendarWeekStart(CalendarWeekStart.sunday);
    expect(
      await periodFor('thisWeek'),
      OverviewWeekPeriod(DateTime.utc(2026, 10, 11)),
    );

    await settings.setCalendarWeekStart(CalendarWeekStart.saturday);
    expect(
      await periodFor('thisWeek'),
      OverviewWeekPeriod(DateTime.utc(2026, 10, 10)),
    );
  });

  test('thisMonth and thisYear read as the period of the day they are '
      'read', () async {
    expect(await periodFor('thisMonth'), october);
    expect(await periodFor('thisYear'), const OverviewYearPeriod(2026));

    await db.userSettingsDao.setValue(SettingsKeys.reportPeriod, 'thisMonth');
    final nextMonth = await settings.getCalendarReportSettings(
      today: DateTime.utc(2026, 11, 2),
    );
    expect(nextMonth.period, const OverviewMonthPeriod(2026, 11));
  });

  test('a rolling preset is kept, All time is not the report\'s', () async {
    expect(
      await periodFor('preset:last12Months'),
      const OverviewRollingPeriod(OverviewRollingPreset.last12Months),
    );
    expect(await periodFor('preset:allTime'), october);
  });

  test('anything unreadable reads as this month', () async {
    expect(await periodFor('preset:nextDecade'), october);
    expect(await periodFor('garbage'), october);
    expect(await periodFor(''), october);
  });

  test('a stepped week clears the stored period', () async {
    await settings.setCalendarReportPeriod(
      OverviewPeriod.thisWeek(
        today: today,
        weekStart: CalendarWeekStart.monday,
      ),
      today: today,
    );
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.reportPeriod),
      'thisWeek',
    );

    await settings.setCalendarReportPeriod(
      OverviewWeekPeriod(DateTime.utc(2026, 9, 28)),
      today: today,
    );
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.reportPeriod),
      isNull,
    );
    expect(
      (await settings.getCalendarReportSettings(today: today)).period,
      october,
    );
  });

  test('the categories round-trip, empty meaning every category', () async {
    await settings.setCalendarReportCategories({'gym', 'health'});
    expect(
      (await settings.getCalendarReportSettings(today: today)).categoryIds,
      {'gym', 'health'},
    );

    await settings.setCalendarReportCategories(const {});
    expect(
      (await settings.getCalendarReportSettings(today: today)).categoryIds,
      isEmpty,
    );
  });

  test('the palette is the presets until custom colours are stored, then '
      'the stored ones', () async {
    var loaded = await settings.getCalendarReportSettings(today: today);
    expect(loaded.palette, MarkdownColorPalette.presets);

    await db.userSettingsDao.setValue(
      SettingsKeys.markdownCustomColors,
      'brand=ff112233',
    );
    loaded = await settings.getCalendarReportSettings(today: today);
    expect(loaded.palette.source, 'brand=ff112233');
    expect(loaded.palette.contains('brand'), isTrue);
    expect(loaded.palette.contains('red'), isTrue);
  });

  test('haptics follow the app-wide switch, on by default', () async {
    expect(
      (await settings.getCalendarReportSettings(today: today)).hapticFeedback,
      SettingsKeys.defaultHapticFeedback,
    );

    await settings.setHapticFeedback(false);
    expect(
      (await settings.getCalendarReportSettings(today: today)).hapticFeedback,
      isFalse,
    );

    await settings.setHapticFeedback(true);
    expect(
      (await settings.getCalendarReportSettings(today: today)).hapticFeedback,
      isTrue,
    );
  });
}
