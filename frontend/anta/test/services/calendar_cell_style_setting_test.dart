import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// The day-cell style is stored **per theme**, and that is the only reason the
/// setting exists: one alpha table serves both grounds, but the same alpha
/// reads as a glow over the dark surface and as flat pastel paint over the
/// near-white one. Two keys that quietly aliased each other would give the
/// user one control wearing two labels, so the independence cases below are
/// the ones worth pinning.
///
/// The default is `solid` on both sides — today's look — so an install that
/// has never written either key must render exactly as it did before the
/// setting shipped.
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

  test('unset keys read as solid on both themes', () async {
    expect(await settings.getCalendarCellStyleLight(), CalendarCellStyle.solid);
    expect(await settings.getCalendarCellStyleDark(), CalendarCellStyle.solid);
    expect(SettingsKeys.defaultCalendarCellStyleLight, 'solid');
    expect(SettingsKeys.defaultCalendarCellStyleDark, 'solid');
  });

  test('each style round-trips on the light key', () async {
    for (final style in CalendarCellStyle.values) {
      await settings.setCalendarCellStyleLight(style);

      expect(await settings.getCalendarCellStyleLight(), style);
      expect(
        await db.userSettingsDao.getValue(SettingsKeys.calendarCellStyleLight),
        style.name,
      );
    }
  });

  test('each style round-trips on the dark key', () async {
    for (final style in CalendarCellStyle.values) {
      await settings.setCalendarCellStyleDark(style);

      expect(await settings.getCalendarCellStyleDark(), style);
      expect(
        await db.userSettingsDao.getValue(SettingsKeys.calendarCellStyleDark),
        style.name,
      );
    }
  });

  test('the two keys are independent', () async {
    await settings.setCalendarCellStyleLight(CalendarCellStyle.outline);

    expect(
      await settings.getCalendarCellStyleLight(),
      CalendarCellStyle.outline,
    );
    expect(await settings.getCalendarCellStyleDark(), CalendarCellStyle.solid);

    await settings.setCalendarCellStyleDark(CalendarCellStyle.fade);

    expect(
      await settings.getCalendarCellStyleLight(),
      CalendarCellStyle.outline,
    );
    expect(await settings.getCalendarCellStyleDark(), CalendarCellStyle.fade);
  });

  test('a garbage stored value decodes to solid on either key', () async {
    await db.userSettingsDao.setValue(
      SettingsKeys.calendarCellStyleLight,
      'gradient',
    );
    await db.userSettingsDao.setValue(SettingsKeys.calendarCellStyleDark, '');

    expect(await settings.getCalendarCellStyleLight(), CalendarCellStyle.solid);
    expect(await settings.getCalendarCellStyleDark(), CalendarCellStyle.solid);
  });

  test('the bulk appearance read agrees with the single-row getters', () async {
    // The bulk path and the getters share one raw-string decoder; a key
    // missing from `_calendarAppearanceKeys` would leave the bundle serving a
    // stale default while the getter reported the truth.
    await settings.setCalendarCellStyleLight(CalendarCellStyle.fade);
    await settings.setCalendarCellStyleDark(CalendarCellStyle.outline);

    final appearance = await settings.getCalendarAppearance();

    expect(
      appearance.cellStyleLight,
      await settings.getCalendarCellStyleLight(),
    );
    expect(appearance.cellStyleDark, await settings.getCalendarCellStyleDark());
    expect(appearance.cellStyleLight, CalendarCellStyle.fade);
    expect(appearance.cellStyleDark, CalendarCellStyle.outline);

    final bundle = await settings.getCalendarPageSettings();
    expect(bundle.appearance, appearance);
  });

  test('a virgin bulk read matches the model defaults', () async {
    final appearance = await settings.getCalendarAppearance();

    expect(
      appearance.cellStyleLight,
      const CalendarAppearance().cellStyleLight,
    );
    expect(appearance.cellStyleDark, const CalendarAppearance().cellStyleDark);
  });
}
