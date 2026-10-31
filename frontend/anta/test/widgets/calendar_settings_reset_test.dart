import 'package:drift/drift.dart'
    show BatchedStatements, QueryExecutor, QueryInterceptor;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/fasting_schedule.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/settings_section_list.dart';
import 'package:anta/widgets/value_change_highlight.dart';

import '../database/support/db_test_support.dart';

/// Calendar settings has no Reset to defaults (D7 of
/// `docs/settings-rework-roadmap.md`): the reset it had wiped hand-picked
/// fasting dates, the traditions and their looks, the holiday set and the
/// removed holidays (S1). These pin that nothing on the page can reach them
/// — no reset control, and the page's own controls write only what they
/// show. A fold toggle edits the stored set it read, so the appearance
/// page's `appearance_` folds survive it.
void main() {
  late AppDatabase db;
  late SettingsService settings;
  late PublicHolidayService holidays;
  late _Writes writes;

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

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    CalendarPaletteService.reset();
    CalendarEventService.reset();
    PublicHolidayService.reset();
    writes = _Writes();
    db = await openTestDatabase(interceptor: writes);
    settings = SettingsService.forTesting(db);
    await CalendarEventService.forTesting(db);
    holidays = await PublicHolidayService.forTesting(db);

    await settings.setFastingTraditions({FastingTradition.orthodox});
    await settings.setFastingSchedule(picked);
    await settings.setFastingOrthodoxGreatFasts(false);
    await settings.setFastingAppearance(movedFastingLook);
    await settings.setAlertSnoozeMinutes(
      SettingsKeys.defaultAlertSnoozeMinutes + 5,
    );
    await settings.setAlertNoticeLeadMinutes(
      SettingsKeys.defaultAlertNoticeLeadMinutes + 60,
    );
    await settings.setAlertSilenceAfterMinutes(
      SettingsKeys.defaultAlertSilenceAfterMinutes + 5,
    );
    await settings.setAlertDefaultTimed(movedTimed);
    await settings.setAlertDefaultAllDay(movedAllDay);
    await settings.setAlertSound(movedSound);
    await settings.setEventDescriptionLimit(
      SettingsKeys.defaultEventDescriptionLimit + 500,
    );
    await settings.setCalendarShowWeekNumbers(!defaults.showWeekNumbers);
    // A retired section id beside one of the appearance page's.
    await settings.setCalendarSettingsCollapsedSections(const {
      'fasting',
      'appearance_week',
    });
    await holidays.setProfile(HolidayProfile.romania, reconcile: false);
    // The Romanian profile's New Year, removed for this one date.
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

  Future<T> read<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Finder scrollable() => find
      .descendant(
        of: find.byType(SettingsSectionList),
        matching: find.byType(Scrollable),
      )
      .first;

  testWidgets('the page ends at Delete all events, with no reset control '
      'under it', (tester) async {
    await pumpPage(tester);

    await tester.scrollUntilVisible(
      find.bySemanticsIdentifier(SemanticsIds.calendarDeleteAllEvents),
      300,
      scrollable: scrollable(),
    );
    final position = tester.state<ScrollableState>(scrollable()).position;
    position.jumpTo(position.maxScrollExtent);
    await settle(tester, rounds: 2);

    expect(find.text(l10n.resetToDefaults), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SettingsSectionList),
        matching: find.byType(TextButton),
      ),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a fold toggled and the filter switch flipped leave the '
      'fasting data, the holidays and the alert values as they were; the '
      'appearance page\'s fold survives', (tester) async {
    await pumpPage(tester);

    await tester.tap(
      find.text(l10n.calendarSettingsPagesSection.toUpperCase()),
    );
    await settle(tester);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.calendarShowFilterChips),
    );
    await settle(tester);

    expect(await read(tester, settings.getCalendarSettingsCollapsedSections), {
      'fasting',
      'appearance_week',
      'pages',
    });
    expect(
      await read(tester, settings.getCalendarShowFilterChips),
      !defaults.showFilterChips,
      reason: 'the switch writes what it shows',
    );

    expect(await read(tester, settings.getFastingSchedule), picked);
    expect(await read(tester, settings.getFastingTraditions), {
      FastingTradition.orthodox,
    });
    expect(await read(tester, settings.getFastingOrthodoxGreatFasts), isFalse);
    expect(await read(tester, settings.getFastingAppearance), movedFastingLook);
    expect(holidays.profile, HolidayProfile.romania);
    final removed = await read(tester, holidays.suppressedHolidays);
    expect(removed.map((h) => h.date), [newYear]);
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
      await read(tester, settings.getEventDescriptionLimit),
      SettingsKeys.defaultEventDescriptionLimit + 500,
    );
    expect(
      await read(tester, settings.getCalendarShowWeekNumbers),
      !defaults.showWeekNumbers,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the holiday set is a value with a menu of every set, the '
      'current one checked; a pick switches the set through the service and '
      'the row reads it', (tester) async {
    await pumpPage(tester);
    final row = find.bySemanticsIdentifier(SemanticsIds.calendarHolidayProfile);
    final romania = PublicHolidays.profileNameOf(HolidayProfile.romania, l10n);
    final germany = PublicHolidays.profileNameOf(HolidayProfile.germany, l10n);
    expect(find.descendant(of: row, matching: find.text(romania)), findsOne);

    await tester.tap(row);
    await settle(tester);
    for (final profile in HolidayProfile.values) {
      expect(
        find.bySemanticsIdentifier(
          SemanticsIds.calendarHolidayProfileItem(profile.name),
        ),
        findsOneWidget,
        reason: profile.name,
      );
    }
    expect(
      tester
          .widgetList<FormMenuChoiceItem<HolidayProfile>>(
            find.byType(FormMenuChoiceItem<HolidayProfile>),
          )
          .where((item) => item.checked)
          .map((item) => item.value),
      [HolidayProfile.romania],
    );

    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.calendarHolidayProfileItem(HolidayProfile.germany.name),
      ),
    );
    await settle(tester);

    expect(holidays.profile, HolidayProfile.germany);
    expect(find.descendant(of: row, matching: find.text(germany)), findsOne);
    expect(find.byType(FormMenuChoiceItem<HolidayProfile>), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('picking the set already chosen writes nothing, buzzes '
      'nothing and flashes nothing', (tester) async {
    await pumpPage(tester);
    final row = find.bySemanticsIdentifier(SemanticsIds.calendarHolidayProfile);
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.tap(row);
    await settle(tester);
    writes.count = 0;
    await tester.tap(
      find.bySemanticsIdentifier(
        SemanticsIds.calendarHolidayProfileItem(HolidayProfile.romania.name),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final wash = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.descendant(
              of: row,
              matching: find.byType(ValueChangeHighlight),
            ),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((wash.decoration as BoxDecoration).color, isNull);
    await settle(tester);
    // The service no-ops on its own set too, so the guard on the page is
    // what the missing haptic pins; the write count pins the store.
    expect(haptics, isEmpty);
    expect(writes.count, 0);
    expect(holidays.profile, HolidayProfile.romania);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// Counts every write the database runs, so a case can pin that a pick
/// wrote nothing.
class _Writes extends QueryInterceptor {
  int count = 0;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    count++;
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    count++;
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    count++;
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    count++;
    return super.runBatched(executor, statements);
  }
}
