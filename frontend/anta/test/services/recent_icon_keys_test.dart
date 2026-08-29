import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// The "Recently used" row is what keeps a catalog of hundreds feeling small,
/// so what matters is that it stays *short, ordered and honest*: newest first,
/// no duplicates, bounded, and never naming an icon the catalog no longer has.
///
/// Icon keys are additive-only, but an icon may still be **retired** — dropped
/// from `groups` while its key stays resolvable — and a key can also arrive
/// from a build that had icons this one does not. Both land here as "unknown",
/// and both must leave rather than render a blank tile.
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

  test('an unset key reads as empty', () async {
    expect(await settings.getRecentIconKeys(), isEmpty);
  });

  test('picks come back newest first', () async {
    await settings.recordRecentIconKey('cake');
    await settings.recordRecentIconKey('pool');
    await settings.recordRecentIconKey('alarm');

    expect(await settings.getRecentIconKeys(), ['alarm', 'pool', 'cake']);
  });

  test('re-picking promotes rather than duplicating', () async {
    await settings.recordRecentIconKey('cake');
    await settings.recordRecentIconKey('pool');
    await settings.recordRecentIconKey('cake');

    expect(await settings.getRecentIconKeys(), ['cake', 'pool']);
  });

  test('the list is capped and drops the oldest', () async {
    // One more than the cap, so the first pick has to fall off the end.
    const keys = [
      'cake',
      'pool',
      'alarm',
      'today',
      'event',
      'note',
      'star',
      'flag',
      'spa',
      'hotel',
      'bolt',
      'mood',
      'science',
    ];
    for (final key in keys) {
      await settings.recordRecentIconKey(key);
    }

    final recent = await settings.getRecentIconKeys();
    expect(recent, hasLength(SettingsService.recentIconLimit));
    expect(recent.first, 'science');
    expect(recent, isNot(contains('cake')));
  });

  test('an unknown key is dropped on read', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.recentIconKeys,
      'cake,no_such_icon,pool',
    );

    expect(
      await settings.getRecentIconKeys(),
      ['cake', 'pool'],
      reason: 'a retired icon must leave the row, not render a blank tile',
    );
  });

  test('a junk value degrades to empty rather than throwing', () async {
    await db.userSettingsDao.setValue(SettingsKeys.recentIconKeys, ',,, ,');
    expect(await settings.getRecentIconKeys(), isEmpty);
  });

  test('duplicates written by an older build are collapsed', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.recentIconKeys,
      'cake,cake,pool',
    );
    expect(await settings.getRecentIconKeys(), ['cake', 'pool']);
  });

  test('a letter glyph is a recordable icon like any other', () async {
    await settings.recordRecentIconKey('letter_a');
    expect(await settings.getRecentIconKeys(), ['letter_a']);
  });
}
