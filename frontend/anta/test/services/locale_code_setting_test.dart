import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// The app's language as the settings singleton reads it, for a reader that
/// asks again and again while the app runs: the alert binding, once per
/// scheduling pass. It must answer from the database the singleton is bound
/// to — the row `AppSettingsBloc` writes — and tell "follow the device" (no
/// row) from a language, because the binding re-arms every standing alert
/// when the answer moves.
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

  test('an install that never chose a language reads null', () async {
    expect(await settings.getLocaleCode(), isNull);
  });

  test('a chosen language reads as its code', () async {
    await db.userSettingsDao.setValue(SettingsKeys.locale, 'de');

    expect(await settings.getLocaleCode(), 'de');
  });

  test('going back to the device language reads null again', () async {
    // What the language page does for "System": it deletes the row.
    await db.userSettingsDao.setValue(SettingsKeys.locale, 'ro');
    await db.userSettingsDao.deleteValue(SettingsKeys.locale);

    expect(await settings.getLocaleCode(), isNull);
  });
}
