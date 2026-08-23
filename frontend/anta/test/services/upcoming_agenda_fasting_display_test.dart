import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// The fasting presentation replaced a boolean, and the point of the read-time
/// fallback is that nobody's configuration resets on update: an install that
/// had turned collapsing **off** must come back listing every fasting day, not
/// silently jump to the new default.
///
/// A fallback rather than a migration pass, so the case that matters most is
/// the ordering — the new key always wins, and the legacy one is never written
/// again, which is what stops a stale boolean from resurrecting later.
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

  Future<AgendaFastingDisplay> load() async =>
      (await settings.getUpcomingAgendaFilters()).fastingDisplay;

  test('a fresh install gets the shipped default', () async {
    expect(await load(), AgendaFastingDisplay.periods);
  });

  test('a stored collapse=false loads as every day', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingCollapseFasting,
      'false',
    );

    expect(await load(), AgendaFastingDisplay.everyDay);
  });

  test('a stored collapse=true loads as periods', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingCollapseFasting,
      'true',
    );

    expect(await load(), AgendaFastingDisplay.periods);
  });

  test('the new key wins over a stale legacy boolean', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingCollapseFasting,
      'false',
    );
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingFastingDisplay,
      AgendaFastingDisplay.summary.name,
    );

    expect(await load(), AgendaFastingDisplay.summary);
  });

  test('a value written by a newer build degrades to periods', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingFastingDisplay,
      'someFutureMode',
    );

    expect(await load(), AgendaFastingDisplay.periods);
  });

  test('saving writes the new key and leaves the legacy one alone', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingCollapseFasting,
      'false',
    );
    await settings.saveUpcomingAgendaFilters(
      const UpcomingAgendaFilters(fastingDisplay: AgendaFastingDisplay.summary),
    );

    expect(
      await db.userSettingsDao.getValue(
        SettingsKeys.calendarUpcomingFastingDisplay,
      ),
      'summary',
    );
    // Untouched, not rewritten: the legacy row is read-only now, and a save
    // that "tidied" it would erase the evidence a rollback would need.
    expect(
      await db.userSettingsDao.getValue(
        SettingsKeys.calendarUpcomingCollapseFasting,
      ),
      'false',
    );
    expect(await load(), AgendaFastingDisplay.summary);
  });
}
