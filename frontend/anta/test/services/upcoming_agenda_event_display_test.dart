import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// The event presentation replaced the `collapse_recurring` boolean, and the
/// point of the read-time fallback is that nobody's agenda changes on update:
/// an install that had collapsing **on** must come back on "per event", and one
/// that never touched it must come back on the uncondensed listing.
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

  Future<AgendaEventDisplay> load() async =>
      (await settings.getUpcomingAgendaFilters()).eventDisplay;

  test('a fresh install lists every occurrence', () async {
    expect(await load(), AgendaEventDisplay.everyOccurrence);
  });

  test('a stored collapse=true loads as per event', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingCollapseRecurring,
      'true',
    );

    expect(await load(), AgendaEventDisplay.perEvent);
  });

  test('a stored collapse=false loads as every occurrence', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingCollapseRecurring,
      'false',
    );

    expect(await load(), AgendaEventDisplay.everyOccurrence);
  });

  test('the new key wins over a stale legacy boolean', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingCollapseRecurring,
      'true',
    );
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingEventDisplay,
      AgendaEventDisplay.summary.name,
    );

    expect(await load(), AgendaEventDisplay.summary);
  });

  test('a value written by a newer build degrades', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingEventDisplay,
      'someFutureMode',
    );

    expect(await load(), AgendaEventDisplay.everyOccurrence);
  });

  test('saving writes the new key and leaves the legacy one alone', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarUpcomingCollapseRecurring,
      'true',
    );
    await settings.saveUpcomingAgendaFilters(
      const UpcomingAgendaFilters(eventDisplay: AgendaEventDisplay.summary),
    );

    expect(
      await db.userSettingsDao.getValue(
        SettingsKeys.calendarUpcomingEventDisplay,
      ),
      'summary',
    );
    // Untouched, not rewritten: the legacy row is read-only now, and a save
    // that "tidied" it would erase what a rollback would need.
    expect(
      await db.userSettingsDao.getValue(
        SettingsKeys.calendarUpcomingCollapseRecurring,
      ),
      'true',
    );
  });
}
