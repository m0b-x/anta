import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/agenda_day_list_mode.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// The drill-down's presentation is persisted like the agenda's event display,
/// and the same two things matter: a fresh install opens on the flat list it
/// always did, and a value written by a build that knows more modes than this
/// one degrades to that list rather than throwing.
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

  test('a fresh install opens on the list', () async {
    expect(await settings.getAgendaDayListMode(), AgendaDayListMode.list);
  });

  for (final mode in AgendaDayListMode.values) {
    test('${mode.name} survives a round trip', () async {
      await settings.setAgendaDayListMode(mode);

      expect(await settings.getAgendaDayListMode(), mode);
      expect(
        await db.userSettingsDao.getValue(SettingsKeys.calendarDayListMode),
        mode.name,
      );
    });
  }

  test('a value written by a newer build degrades', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarDayListMode,
      'someFutureMode',
    );

    expect(await settings.getAgendaDayListMode(), AgendaDayListMode.list);
  });

  test('the default key names a real mode', () async {
    expect(
      AgendaDayListMode.fromName(SettingsKeys.defaultCalendarDayListMode).name,
      SettingsKeys.defaultCalendarDayListMode,
    );
  });
}
