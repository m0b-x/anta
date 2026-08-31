import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// `CalendarPage.initState` issued 16-18 sequential single-row SELECTs before
/// the grid could paint — 11 of them inside `getCalendarAppearance` alone. Each
/// await is its own round trip to the drift isolate, so the latencies add
/// rather than overlap, and appearance resolving after the first frame is what
/// made the grid visibly re-lay-out.
///
/// The bulk path decodes from one keyed `getValuesFor` read. It shares the
/// decoders with the single-row getters, so the round-trip cases below are what
/// keeps the two from drifting apart — and the "keyed, not a full-table read"
/// case is what keeps the fix from inverting at volume: `user_settings` is not
/// only app settings, `NotePositionService` writes a `note_position_<id>` row
/// per note, so a `getAllSettings()` here would scale with the note count on
/// the one path that runs before the first frame.
void main() {
  late AppDatabase db;
  late StatementCounter counter;
  late SettingsService settings;

  setUp(() async {
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
    settings = SettingsService.forTesting(db);
  });

  tearDown(() async {
    SettingsService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  test('the calendar bundle costs one statement', () async {
    counter.reset();
    await settings.getCalendarPageSettings();

    expect(counter.count, 1);
    expect(counter.selects, hasLength(1));
  });

  test('calendar appearance costs one statement', () async {
    counter.reset();
    await settings.getCalendarAppearance();

    expect(counter.count, 1);
  });

  test('the bulk read is keyed, not a full-table read', () async {
    // NotePositionService writes one of these per note the user has opened, so
    // this table grows with the note count, not with the number of settings.
    for (var i = 0; i < 200; i++) {
      await db.userSettingsDao.setValue(
        '${SettingsKeys.notePositionPrefix}note$i',
        '{"offset":0}',
      );
    }

    counter.reset();
    await settings.getCalendarPageSettings();

    final captured = counter.captured.single;
    // A keyed read binds one parameter per key; a full-table read binds none.
    // Statement *count* alone cannot tell the two apart, which is the whole
    // point of this case.
    expect(captured.args, isNotEmpty);
    expect(captured.sql, contains('IN'));
    expect(
      await db.userSettingsDao.getValuesFor(const ['nope', 'also_nope']),
      isEmpty,
    );
  });

  test('unrelated rows do not change what the bundle resolves', () async {
    final before = await settings.getCalendarPageSettings();

    for (var i = 0; i < 50; i++) {
      await db.userSettingsDao.setValue(
        '${SettingsKeys.notePositionPrefix}note$i',
        '{"offset":$i}',
      );
    }

    final after = await settings.getCalendarPageSettings();

    expect(after.appearance, before.appearance);
    expect(after.fastingSchedule, before.fastingSchedule);
    expect(after.fastingAppearance, before.fastingAppearance);
  });

  test('the bundle agrees with every single-row getter', () async {
    await settings.setCalendarTodayStyle(CalendarTodayStyle.ring);
    await settings.setCalendarMarkerStyle(CalendarMarkerStyle.dots);
    await settings.setCalendarWeekStart(CalendarWeekStart.sunday);
    await settings.setCalendarAccentColor(0xFF00BCD4);
    await settings.setCalendarHighlightWeekends(true);
    await settings.setCalendarShowWeekNumbers(true);
    await settings.setCalendarMaxDayBars(4);
    await settings.setCalendarShowRecurrenceLabels(false);
    await settings.setCalendarMissedDisplay(CalendarMissedDisplay.hidden);
    await settings.setCalendarEventTint(true);
    await settings.setCalendarTintConflict(CalendarTintConflict.both);
    await settings.setCalendarDayRailStyle(DayRailStyle.dot);
    await settings.setCalendarMaxDayRailMarks(5);
    await settings.setFastingOrthodoxGreatFasts(false);

    final bundle = await settings.getCalendarPageSettings();

    expect(bundle.appearance, await settings.getCalendarAppearance());
    // Against the *single-row* getters, not just the other bulk path: both
    // bulk reads share `_calendarAppearanceKeys`, so a key missing from that
    // list would leave them agreeing on the same stale default.
    expect(
      bundle.appearance.dayRailStyle,
      await settings.getCalendarDayRailStyle(),
    );
    expect(
      bundle.appearance.maxDayRailMarks,
      await settings.getCalendarMaxDayRailMarks(),
    );
    expect(bundle.palette, same(await settings.getColorPalette()));
    expect(bundle.fastingTraditions, await settings.getFastingTraditions());
    expect(bundle.fastingAppearance, await settings.getFastingAppearance());
    expect(
      bundle.fastingGreatFasts,
      await settings.getFastingOrthodoxGreatFasts(),
    );
    expect(bundle.fastingSchedule, await settings.getFastingSchedule());
  });

  test('the bundle agrees with the getters on a virgin database', () async {
    final bundle = await settings.getCalendarPageSettings();

    expect(bundle.appearance, await settings.getCalendarAppearance());
    expect(bundle.fastingTraditions, await settings.getFastingTraditions());
    expect(bundle.fastingAppearance, await settings.getFastingAppearance());
    expect(bundle.fastingSchedule, await settings.getFastingSchedule());
    expect(
      bundle.fastingGreatFasts,
      await settings.getFastingOrthodoxGreatFasts(),
    );
  });

  group('absent is not the same as empty', () {
    test(
      'an empty legacy weekday CSV is a deliberate no-weekly-fast',
      () async {
        await db.userSettingsDao.setValue(
          SettingsKeys.calendarFastingWeekdays,
          '',
        );

        final bundle = await settings.getCalendarPageSettings();

        expect(bundle.fastingSchedule, await settings.getFastingSchedule());
        expect(bundle.fastingSchedule.weekdays, isEmpty);
      },
    );

    test('an absent legacy weekday CSV means never chosen', () async {
      final bundle = await settings.getCalendarPageSettings();

      expect(bundle.fastingSchedule, await settings.getFastingSchedule());
      // The two must differ, or the distinction the decoder preserves would be
      // unobservable and this suite would be asserting nothing.
      await db.userSettingsDao.setValue(
        SettingsKeys.calendarFastingWeekdays,
        '',
      );
      final blanked = await settings.getCalendarPageSettings();
      expect(blanked.fastingSchedule, isNot(equals(bundle.fastingSchedule)));
    });

    test('the retired fasting style key seeds the appearance', () async {
      await db.userSettingsDao.setValue(
        SettingsKeys.calendarFastingStyle,
        FastingDisplayStyle.strong.name,
      );

      final bundle = await settings.getCalendarPageSettings();

      expect(bundle.fastingAppearance, await settings.getFastingAppearance());
      expect(
        bundle.fastingAppearance,
        isNot(equals(FastingAppearance.decode(null))),
      );
    });

    test('an out-of-range rail cap is clamped, never trusted', () async {
      // The rail draws a fixed number of slots; a hand-edited or
      // future-written value asking for twelve would silently overflow the
      // cell, so both the setter and the decoder clamp.
      await db.userSettingsDao.setValue(
        SettingsKeys.calendarMaxDayRailMarks,
        '12',
      );

      final bundle = await settings.getCalendarPageSettings();

      expect(
        bundle.appearance.maxDayRailMarks,
        SettingsKeys.maxCalendarMaxDayRailMarks,
      );
      expect(
        await settings.getCalendarMaxDayRailMarks(),
        SettingsKeys.maxCalendarMaxDayRailMarks,
      );

      await settings.setCalendarMaxDayRailMarks(0);
      expect(
        await settings.getCalendarMaxDayRailMarks(),
        SettingsKeys.minCalendarMaxDayRailMarks,
      );
    });

    test('an unknown rail style falls back to off', () async {
      // Forward compatibility, and the direction matters: a style this build
      // cannot draw must leave the grid exactly as it was, not paint garbage.
      await db.userSettingsDao.setValue(
        SettingsKeys.calendarDayRailStyle,
        'chevron',
      );

      final bundle = await settings.getCalendarPageSettings();

      expect(bundle.appearance.dayRailStyle, DayRailStyle.none);
    });
  });
}
