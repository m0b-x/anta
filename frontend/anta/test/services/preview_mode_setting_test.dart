import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// The preview is deprecated, and the whole retirement rests on this key
/// reading `false` on an install that has never written it — a default that
/// flipped the other way would put the eye button back on every fresh
/// install. The stored-value cases guard the other direction: an existing
/// user who turned it on must keep it across a restart.
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

  test('an unset key reads as off', () async {
    expect(await settings.getPreviewModeEnabled(), isFalse);
    expect(SettingsKeys.defaultPreviewModeEnabled, isFalse);
  });

  test('on round-trips', () async {
    await settings.setPreviewModeEnabled(true);

    expect(await settings.getPreviewModeEnabled(), isTrue);
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.previewModeEnabled),
      'true',
    );
  });

  test(
    'turning it back off writes the value rather than clearing the row',
    () async {
      await settings.setPreviewModeEnabled(true);
      await settings.setPreviewModeEnabled(false);

      expect(await settings.getPreviewModeEnabled(), isFalse);
      expect(
        await db.userSettingsDao.getValue(SettingsKeys.previewModeEnabled),
        'false',
      );
    },
  );

  test('a stored value survives a service reset', () async {
    await settings.setPreviewModeEnabled(true);
    SettingsService.reset();

    expect(
      await SettingsService.forTesting(db).getPreviewModeEnabled(),
      isTrue,
    );
  });
}
