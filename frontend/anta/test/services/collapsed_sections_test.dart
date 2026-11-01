import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// Which settings sections are folded is a view preference, but it is a
/// *persisted* one keyed on frozen ids — so the two things that matter are
/// that a page's fold survives a round trip untouched, and that the two pages
/// that fold cannot read each other's state.
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

  test('an unset key reads as nothing folded', () async {
    expect(await settings.getAppSettingsCollapsedSections(), isEmpty);
  });

  test('ids round-trip', () async {
    await settings.setAppSettingsCollapsedSections({'editor', 'preview'});

    expect(await settings.getAppSettingsCollapsedSections(), {
      'editor',
      'preview',
    });
  });

  test(
    'an empty set clears the fold rather than leaving the last one',
    () async {
      await settings.setAppSettingsCollapsedSections({'editor'});
      await settings.setAppSettingsCollapsedSections(const {});

      expect(await settings.getAppSettingsCollapsedSections(), isEmpty);
    },
  );

  test('the app and calendar pages fold independently', () async {
    await settings.setAppSettingsCollapsedSections({'editor'});
    await settings.setCalendarSettingsCollapsedSections({'appearance'});

    expect(await settings.getAppSettingsCollapsedSections(), {'editor'});
    expect(await settings.getCalendarSettingsCollapsedSections(), {
      'appearance',
    });
  });

  test('a padded or empty stored id is tolerated, not folded on', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.appSettingsCollapsedSections,
      ' editor , ,preview ',
    );

    expect(await settings.getAppSettingsCollapsedSections(), {
      'editor',
      'preview',
    });
  });

  // A review probe: a page whose copy predates a child page's write wrote
  // its copy back, and the child's fold was lost.
  test('a fold edits the stored set, not the copy a page holds', () async {
    await settings.setCalendarSettingsCollapsedSections({'appearance_cell'});
    // The calendar settings page still holds `{}`, read before the push.
    final written = await settings.setCalendarSettingsSectionCollapsed(
      'filtering',
      collapsed: true,
    );

    expect(written, {'appearance_cell', 'filtering'});
    expect(await settings.getCalendarSettingsCollapsedSections(), {
      'appearance_cell',
      'filtering',
    });

    expect(
      await settings.setCalendarSettingsSectionCollapsed(
        'appearance_cell',
        collapsed: false,
      ),
      {'filtering'},
    );
  });

  test('two folds started together both land', () async {
    await Future.wait([
      settings.setCalendarSettingsSectionCollapsed('alerts', collapsed: true),
      settings.setCalendarSettingsSectionCollapsed('fasting', collapsed: true),
    ]);

    expect(await settings.getCalendarSettingsCollapsedSections(), {
      'alerts',
      'fasting',
    });
  });

  test('an id no longer matching a section is inert, not an error', () async {
    await settings.setAppSettingsCollapsedSections({'gestures'});

    expect(await settings.getAppSettingsCollapsedSections(), {'gestures'});
  });
}
