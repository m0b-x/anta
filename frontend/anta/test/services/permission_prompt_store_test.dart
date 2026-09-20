import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

void main() {
  late AppDatabase db;
  const store = SettingsPermissionPromptStore();

  setUp(() async {
    db = await openTestDatabase();
    SettingsService.forTesting(db);
  });

  tearDown(() async {
    SettingsService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  test('a fresh database has no acknowledgement and asks at launch', () async {
    expect(await store.readAcknowledgement(), isNull);
    expect(await store.readLaunchPromptEnabled(), isTrue);
  });

  test('both values round-trip through user_settings', () async {
    await store.writeAcknowledgement('device-a|notifications');
    await store.writeLaunchPromptEnabled(false);

    expect(await store.readAcknowledgement(), 'device-a|notifications');
    expect(await store.readLaunchPromptEnabled(), isFalse);
  });
}
