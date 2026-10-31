import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/alert_sound.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/fasting_schedule.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';

/// Calendar settings' Reset to defaults, pinned against today's behaviour
/// before S5 of the settings rework (`docs/settings-rework-roadmap.md`, D7)
/// removes it. Today it reaches past the page's own rows into user-entered
/// fasting data (S1) and the holiday set, and stops short of the appearance
/// page's keys; each of those is read back from the store. The cancel
/// writes nothing.
void main() {
  late AppDatabase db;
  late SettingsService settings;
  late PublicHolidayService holidays;

  final l10n = AppLocalizationsEn();
  const defaults = CalendarAppearance();

  final newYear = DateTime.utc(2026, 1, 1);
  final picked = FastingSchedule(
    forceDates: {DateTime.utc(2026, 11, 3), DateTime.utc(2026, 11, 10)},
  );
  const movedFastingLook = FastingAppearance(
    byTradition: {
      FastingTradition.orthodox: FastingTraditionStyle(
        style: FastingDisplayStyle.bar,
      ),
    },
  );
  const TimedAlertDefault movedTimed = (
    mode: AlertMode.notify,
    offsetMinutes: 15,
  );
  const AllDayAlertDefault movedAllDay = (
    mode: AlertMode.notify,
    daysBefore: 1,
    dayMinute: 9 * 60,
  );
  const movedSound = 'content://media/internal/audio/media/42';
  final shipped = SettingsService.shippedAlertSettings;

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    CalendarPaletteService.reset();
    CalendarEventService.reset();
    PublicHolidayService.reset();
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    await CalendarEventService.forTesting(db);
    holidays = await PublicHolidayService.forTesting(db);

    await settings.setFastingTraditions({FastingTradition.orthodox});
    await settings.setFastingSchedule(picked);
    await settings.setAlertSnoozeMinutes(
      SettingsKeys.defaultAlertSnoozeMinutes + 5,
    );
    await settings.setAlertNoticeLeadMinutes(
      SettingsKeys.defaultAlertNoticeLeadMinutes + 60,
    );
    await settings.setCalendarShowFilterChips(!defaults.showFilterChips);
    await settings.setFastingOrthodoxGreatFasts(false);
    await settings.setFastingAppearance(movedFastingLook);
    await settings.setEventDescriptionLimit(
      SettingsKeys.defaultEventDescriptionLimit + 500,
    );
    await settings.setAlertSilenceAfterMinutes(
      SettingsKeys.defaultAlertSilenceAfterMinutes + 5,
    );
    await settings.setAlertDefaultTimed(movedTimed);
    await settings.setAlertDefaultAllDay(movedAllDay);
    await settings.setAlertSound(movedSound);
    // Owned by the appearance page, which has its own reset.
    await settings.setCalendarShowWeekNumbers(!defaults.showWeekNumbers);
    await settings.setCalendarSettingsCollapsedSections(const {
      'fasting',
      'appearance_week',
    });
    // The generic profile's New Year, removed for this one date.
    await holidays.removeOn(newYear);
  });

  tearDown(() async {
    CalendarEventService.reset();
    PublicHolidayService.reset();
    SettingsService.reset();
    CalendarPaletteService.reset();
    // A read of the seeded all-day default publishes its minute app-wide.
    EventAlerts.configureDefaultDayMinute(null);
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  /// Drift answers on futures `FakeAsync` alone never completes, so real time
  /// and pumped frames are interleaved rather than `pumpAndSettle` used.
  Future<void> settle(WidgetTester tester, {int rounds = 14}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const CalendarSettingsPage(),
      ),
    );
    await settle(tester);
  }

  /// Scrolls to the footer's reset button — built only while the search box
  /// is empty — and answers its confirm with [answer].
  Future<void> resetAndAnswer(WidgetTester tester, String answer) async {
    await tester.scrollUntilVisible(
      find.text(l10n.resetToDefaults),
      600,
      scrollable: find
          .descendant(
            of: find.byType(SettingsSectionList),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await settle(tester);
    await tester.tap(find.text(l10n.resetToDefaults));
    await tester.pumpAndSettle();
    expect(find.text(l10n.resetToDefaultsConfirm), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(answer));
    await settle(tester);
  }

  Future<T> read<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  testWidgets('confirmed wipes the hand-picked fasting dates (today\'s data '
      'loss, S1; S5 removes the reset) and restores the removed holiday, and '
      'leaves the appearance page\'s keys alone', (tester) async {
    await pumpPage(tester);

    await resetAndAnswer(tester, SemanticsIds.sheetConfirm);

    expect(find.text(l10n.settingsReset), findsOneWidget);
    expect(
      await read(tester, settings.getFastingSchedule),
      const FastingSchedule(),
      reason: 'the two forced dates are gone',
    );
    expect(await read(tester, settings.getFastingTraditions), isEmpty);
    expect(
      await read(tester, settings.getFastingAppearance),
      const FastingAppearance(),
    );
    expect(await read(tester, settings.getFastingOrthodoxGreatFasts), isTrue);
    expect(
      await read(tester, settings.getEventDescriptionLimit),
      SettingsKeys.defaultEventDescriptionLimit,
    );
    final alerts = await read(tester, settings.getAlertSettings);
    expect(alerts.snoozeMinutes, SettingsKeys.defaultAlertSnoozeMinutes);
    expect(
      alerts.noticeLeadMinutes,
      SettingsKeys.defaultAlertNoticeLeadMinutes,
    );
    expect(
      alerts.silenceAfterMinutes,
      SettingsKeys.defaultAlertSilenceAfterMinutes,
    );
    // Alerts are opt-in: the shipped defaults carry none.
    expect(alerts.timedDefault, shipped.timedDefault);
    expect(alerts.allDayDefault, shipped.allDayDefault);
    // Decoded: the store writes the phone's default as its literal, where an
    // untouched install reads the absent key as ''; both name the same sound.
    expect(AlertSound.decode(alerts.sound), AlertSound.decode(shipped.sound));
    expect(
      await read(tester, settings.getCalendarShowFilterChips),
      defaults.showFilterChips,
    );
    expect(holidays.profile, HolidayProfile.generic);
    expect(await read(tester, holidays.suppressedHolidays), isEmpty);
    expect(
      await read(tester, settings.getCalendarShowWeekNumbers),
      !defaults.showWeekNumbers,
      reason: 'the appearance page owns it and is not reset from here',
    );
    expect(
      await read(tester, settings.getCalendarSettingsCollapsedSections),
      {'appearance_week'},
      reason: 'this page\'s folds open; the appearance page\'s stay',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancelled keeps all of it', (tester) async {
    await pumpPage(tester);

    await resetAndAnswer(tester, SemanticsIds.sheetCancel);

    expect(find.text(l10n.settingsReset), findsNothing);
    expect(await read(tester, settings.getFastingSchedule), picked);
    expect(await read(tester, settings.getFastingTraditions), {
      FastingTradition.orthodox,
    });
    expect(await read(tester, settings.getFastingOrthodoxGreatFasts), isFalse);
    expect(await read(tester, settings.getFastingAppearance), movedFastingLook);
    expect(
      await read(tester, settings.getEventDescriptionLimit),
      SettingsKeys.defaultEventDescriptionLimit + 500,
    );
    final alerts = await read(tester, settings.getAlertSettings);
    expect(alerts.snoozeMinutes, SettingsKeys.defaultAlertSnoozeMinutes + 5);
    expect(
      alerts.noticeLeadMinutes,
      SettingsKeys.defaultAlertNoticeLeadMinutes + 60,
    );
    expect(
      alerts.silenceAfterMinutes,
      SettingsKeys.defaultAlertSilenceAfterMinutes + 5,
    );
    expect(alerts.timedDefault, movedTimed);
    expect(alerts.allDayDefault, movedAllDay);
    expect(alerts.sound, movedSound);
    expect(
      await read(tester, settings.getCalendarShowFilterChips),
      !defaults.showFilterChips,
    );
    final removed = await read(tester, holidays.suppressedHolidays);
    expect(removed.map((h) => h.date), [newYear]);
    expect(
      await read(tester, settings.getCalendarShowWeekNumbers),
      !defaults.showWeekNumbers,
    );
    expect(await read(tester, settings.getCalendarSettingsCollapsedSections), {
      'fasting',
      'appearance_week',
    });

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
