import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// The holiday presentation is a **new axis**, not a replacement, so unlike the
/// fasting one it has no legacy key to fall back on — which makes the property
/// worth pinning simply that an install predating it opens on the behaviour it
/// already had, and that a value from a newer build degrades to the same.
void main() {
  late AppDatabase db;
  late SettingsService settings;

  setUp(() async {
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
  });

  tearDown(() async {
    SettingsService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  Future<AgendaHolidayDisplay> load() async =>
      (await settings.getUpcomingAgendaFilters()).holidayDisplay;

  test('an install that predates the setting keeps every-day rows', () async {
    expect(await load(), AgendaHolidayDisplay.everyDay);
  });

  test('the chosen presentation round-trips', () async {
    await settings.saveUpcomingAgendaFilters(
      const UpcomingAgendaFilters(holidayDisplay: AgendaHolidayDisplay.summary),
    );

    expect(
      await db.userSettingsDao.getValue(
        SettingsKeys.calendarUpcomingHolidayDisplay,
      ),
      'summary',
    );
    expect(await load(), AgendaHolidayDisplay.summary);
  });

  test('a value written by a newer build degrades to every day', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingHolidayDisplay,
      'someFutureMode',
    );

    expect(await load(), AgendaHolidayDisplay.everyDay);
  });

  test('the two display axes are stored independently', () async {
    await settings.saveUpcomingAgendaFilters(
      const UpcomingAgendaFilters(
        holidayDisplay: AgendaHolidayDisplay.summary,
        fastingDisplay: AgendaFastingDisplay.everyDay,
      ),
    );
    final loaded = await settings.getUpcomingAgendaFilters();

    expect(loaded.holidayDisplay, AgendaHolidayDisplay.summary);
    expect(loaded.fastingDisplay, AgendaFastingDisplay.everyDay);
  });
}
