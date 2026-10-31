import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/l10n/app_localizations_ro.dart';
import 'package:anta/models/alert_sound.dart';
import 'package:anta/models/app_permission.dart';
import 'package:anta/models/calendar_guide_content.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/pages/alert_settings_page.dart';
import 'package:anta/pages/calendar_guide_topic_page.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/alert_sound_sheet.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../services/permission_support.dart';
import 'support/alert_settings_robot.dart';
import 'support/alert_sheet_robot.dart';

/// Alert settings (D5): the rows that left Calendar settings, re-pinned on
/// their own page — the two defaults through the alert sheet, the sliders'
/// writes and the reconcile after each, the notice read in hours, the sound
/// sheet, the test alarm's permission check first — plus the two rows the
/// page added, its fold set, and the large-text cases the default rows
/// carried on Calendar settings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = AppLocalizationsEn();

  late AppDatabase db;
  late SettingsService settings;
  late List<AlertReconcileReason> reconciles;
  late List<(String, Duration)> testAlarms;

  /// What the stand-in scheduler answers a test alarm with: an os id, or
  /// null where the platform refused.
  late int? testAlarmAnswer;

  /// Read when a test alarm is asked for, so the suite can say the
  /// permission refresh came first.
  int Function() statusReadsAtArm = () => 0;
  late List<int> statusReadsAtTestAlarm;

  setUpAll(loadGoldenFonts);

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    reconciles = [];
    testAlarms = [];
    testAlarmAnswer = 7;
    statusReadsAtArm = () => 0;
    statusReadsAtTestAlarm = [];
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<PermissionService>()) {
      await GetIt.I.unregister<PermissionService>();
    }
    SettingsService.reset();
    // A read of a seeded all-day default publishes its minute app-wide.
    EventAlerts.configureDefaultDayMinute(null);
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  Widget page() => AlertSettingsPage.forTesting(
    reconcile: (reason) async => reconciles.add(reason),
    scheduleTestAlarm: (title, delay) async {
      testAlarms.add((title, delay));
      statusReadsAtTestAlarm.add(statusReadsAtArm());
      return testAlarmAnswer;
    },
  );

  /// The app's own theme, light or [dark]. [density] is the theme's: left
  /// out, the host's — compact on a desktop, which is where these tests run,
  /// so a tile hands its trailing 48 dp; `VisualDensity.standard` is the
  /// phone's, with its 56 dp.
  Future<void> pumpPage(
    WidgetTester tester, {
    Size surface = const Size(800, 3000),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    bool dark = false,
    VisualDensity? density,
    List<NavigatorObserver> observers = const [],
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final theme = dark ? AppTheme.dark() : AppTheme.light();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        theme: density == null
            ? theme
            : theme.copyWith(visualDensity: density),
        navigatorObservers: observers,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: page(),
      ),
    );
    await AlertSettingsRobot(tester).settle();
  }

  Future<AlertSettings> stored(WidgetTester tester) async =>
      (await tester.runAsync(settings.getAlertSettings))!;

  Future<void> teardownApp(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  /// The row [id] shows [text] somewhere inside it.
  void expectRowSays(String id, String text) => expect(
    find.descendant(
      of: find.bySemanticsIdentifier(id),
      matching: find.text(text),
    ),
    findsOneWidget,
  );

  group('the page', () {
    testWidgets('five sections in order — Defaults, Sound and timing, '
        'Permissions, Categories, How it works — every row with its id, '
        'under the bar\'s', (tester) async {
      await pumpPage(tester);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.settingsBarAlertSettings),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.alertSettingsList),
        findsOneWidget,
      );
      final headers = [
        l10n.alertSettingsSectionDefaults,
        l10n.alertSettingsSectionTiming,
        l10n.permissionsTitle,
        l10n.calendarCategories,
        l10n.calendarGuideHowItWorks,
      ];
      final tops = [
        for (final title in headers)
          tester.getTopLeft(find.text(title.toUpperCase())).dy,
      ];
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i], greaterThan(tops[i - 1]), reason: headers[i]);
      }
      for (final id in const [
        SemanticsIds.alertsDefaultTimed,
        SemanticsIds.alertsDefaultAllDay,
        SemanticsIds.alertSettingsSound,
        SemanticsIds.alertSettingsSnooze,
        SemanticsIds.alertSettingsNotice,
        SemanticsIds.alertSettingsSilence,
        SemanticsIds.alertSettingsPermissions,
        SemanticsIds.alertsTestAlarm,
        SemanticsIds.alertSettingsCategoriesOpen,
        SemanticsIds.alertSettingsHowItWorksOpen,
      ]) {
        expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
      }
      // Each row sits under its section: the defaults above the timing
      // header, the test alarm above the categories header.
      expect(
        tester
            .getTopLeft(
              find.bySemanticsIdentifier(SemanticsIds.alertsDefaultAllDay),
            )
            .dy,
        lessThan(tops[1]),
      );
      expect(
        tester
            .getTopLeft(
              find.bySemanticsIdentifier(SemanticsIds.alertsTestAlarm),
            )
            .dy,
        allOf(greaterThan(tops[2]), lessThan(tops[3])),
      );
      expectRowSays(
        SemanticsIds.alertSettingsCategoriesOpen,
        l10n.alertSettingsCategoriesRow,
      );
      // Titled by the guide topic it opens, with the topic's own caption.
      expectRowSays(
        SemanticsIds.alertSettingsHowItWorksOpen,
        l10n.calendarGuidePageAlerts,
      );
      expectRowSays(
        SemanticsIds.alertSettingsHowItWorksOpen,
        l10n.calendarGuidePageAlertsCaption,
      );
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(
            SemanticsIds.alertSettingsHowItWorksOpen,
          ),
          matching: find.text(l10n.calendarGuideHowItWorks),
        ),
        findsNothing,
      );

      await teardownApp(tester);
    });

    testWidgets('a fold is kept under the alerts_ prefix in the calendar '
        'settings set, beside that page\'s own `alerts` fold, which folds '
        'nothing here', (tester) async {
      final robot = AlertSettingsRobot(tester);
      await tester.runAsync(
        () => settings.setCalendarSettingsCollapsedSections(const {'alerts'}),
      );
      await pumpPage(tester);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.alertsDefaultTimed),
        findsOneWidget,
      );

      await robot.toggleSection(l10n.alertSettingsSectionDefaults);

      expect(
        find.bySemanticsIdentifier(SemanticsIds.alertsDefaultTimed),
        findsNothing,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.alertSettingsSound),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(settings.getCalendarSettingsCollapsedSections),
        {'alerts', 'alerts_defaults'},
      );

      await robot.toggleSection(l10n.alertSettingsSectionDefaults);
      expect(
        await tester.runAsync(settings.getCalendarSettingsCollapsedSections),
        {'alerts'},
      );

      await teardownApp(tester);
    });
  });

  group('the defaults', () {
    testWidgets('Timed events opens the alert sheet, whose remove reads "No '
        'default alert"; a saved change is written and read back on the '
        'row', (tester) async {
      final robot = AlertSettingsRobot(tester);
      final sheet = AlertSheetRobot(tester);
      await tester.runAsync(
        () => settings.setAlertDefaultTimed((
          mode: AlertMode.notify,
          offsetMinutes: 10,
        )),
      );
      await pumpPage(tester);
      expectRowSays(
        SemanticsIds.alertsDefaultTimed,
        'Reminder · 10 min before',
      );

      await robot.tapRow(SemanticsIds.alertsDefaultTimed);
      expect(sheet.removeAlertLabel, l10n.alertsDefaultRemove);
      expect(sheet.removeAlertLabel, 'No default alert');
      await sheet.chooseTier(AlertMode.ring);
      await sheet.save();
      await robot.settle();

      expect((await stored(tester)).timedDefault, (
        mode: AlertMode.ring,
        offsetMinutes: 10,
      ));
      expectRowSays(SemanticsIds.alertsDefaultTimed, 'Alarm · 10 min before');

      await teardownApp(tester);
    });

    testWidgets('All-day events: its remove reads "No default alert", writes '
        'none, and the row reads "No alert"', (tester) async {
      final robot = AlertSettingsRobot(tester);
      final sheet = AlertSheetRobot(tester);
      await tester.runAsync(
        () => settings.setAlertDefaultAllDay((
          mode: AlertMode.notify,
          daysBefore: 1,
          dayMinute: 9 * 60,
        )),
      );
      await pumpPage(tester);
      expectRowSays(
        SemanticsIds.alertsDefaultAllDay,
        'Reminder · The day before, 9:00 AM',
      );

      await robot.tapRow(SemanticsIds.alertsDefaultAllDay);
      expect(sheet.removeAlertLabel, 'No default alert');
      await sheet.tapRemoveAlert();
      await robot.settle();

      expect((await stored(tester)).allDayDefault, isNull);
      expectRowSays(SemanticsIds.alertsDefaultAllDay, l10n.alertsDefaultNone);

      await teardownApp(tester);
    });

    testWidgets('with no default set, an untouched Done writes nothing: '
        'alerts stay opt-in', (tester) async {
      final robot = AlertSettingsRobot(tester);
      final sheet = AlertSheetRobot(tester);
      await pumpPage(tester);
      expectRowSays(SemanticsIds.alertsDefaultTimed, l10n.alertsDefaultNone);

      await robot.tapRow(SemanticsIds.alertsDefaultTimed);
      await sheet.save();
      await robot.settle();
      await robot.tapRow(SemanticsIds.alertsDefaultAllDay);
      await sheet.save();
      await robot.settle();

      final alerts = await stored(tester);
      expect(alerts.timedDefault, isNull);
      expect(alerts.allDayDefault, isNull);
      expectRowSays(SemanticsIds.alertsDefaultTimed, l10n.alertsDefaultNone);
      expectRowSays(SemanticsIds.alertsDefaultAllDay, l10n.alertsDefaultNone);

      await teardownApp(tester);
    });

    testWidgets('with no default set, a Done after a change does write it', (
      tester,
    ) async {
      final robot = AlertSettingsRobot(tester);
      final sheet = AlertSheetRobot(tester);
      await pumpPage(tester);

      await robot.tapRow(SemanticsIds.alertsDefaultTimed);
      await sheet.chooseTier(AlertMode.ring);
      await sheet.save();
      await robot.settle();

      expect((await stored(tester)).timedDefault, (
        mode: AlertMode.ring,
        offsetMinutes: kDraftAlertOffsetMinutes,
      ));

      await teardownApp(tester);
    });

    testWidgets('with no default set, a change and back writes the draft it '
        'opened on: touch, not value, is the choice (N148)', (tester) async {
      final robot = AlertSettingsRobot(tester);
      final sheet = AlertSheetRobot(tester);
      await pumpPage(tester);

      await robot.tapRow(SemanticsIds.alertsDefaultTimed);
      await sheet.chooseTier(AlertMode.ring);
      await sheet.chooseTier(AlertMode.notify);
      await sheet.save();
      await robot.settle();

      expect((await stored(tester)).timedDefault, (
        mode: AlertMode.notify,
        offsetMinutes: kDraftAlertOffsetMinutes,
      ));
      expectRowSays(
        SemanticsIds.alertsDefaultTimed,
        'Reminder · 10 min before',
      );

      await teardownApp(tester);
    });

    testWidgets('with no default set, Remove writes none and cancel writes '
        'nothing', (tester) async {
      final robot = AlertSettingsRobot(tester);
      final sheet = AlertSheetRobot(tester);
      await pumpPage(tester);

      await robot.tapRow(SemanticsIds.alertsDefaultTimed);
      await sheet.chooseTier(AlertMode.ring);
      await sheet.close();
      await robot.settle();
      expect((await stored(tester)).timedDefault, isNull);

      await robot.tapRow(SemanticsIds.alertsDefaultAllDay);
      await sheet.tapRemoveAlert();
      await robot.settle();
      final alerts = await stored(tester);
      expect(alerts.timedDefault, isNull);
      expect(alerts.allDayDefault, isNull);
      expectRowSays(SemanticsIds.alertsDefaultTimed, l10n.alertsDefaultNone);
      expectRowSays(SemanticsIds.alertsDefaultAllDay, l10n.alertsDefaultNone);

      await teardownApp(tester);
    });

    testWidgets('with a default set, a cancel leaves it as it was', (
      tester,
    ) async {
      final robot = AlertSettingsRobot(tester);
      final sheet = AlertSheetRobot(tester);
      const value = (mode: AlertMode.ring, offsetMinutes: 30);
      await tester.runAsync(() => settings.setAlertDefaultTimed(value));
      await pumpPage(tester);

      await robot.tapRow(SemanticsIds.alertsDefaultTimed);
      await sheet.chooseTier(AlertMode.notify);
      await sheet.close();
      await robot.settle();

      expect((await stored(tester)).timedDefault, value);
      expectRowSays(SemanticsIds.alertsDefaultTimed, 'Alarm · 30 min before');

      await teardownApp(tester);
    });
  });

  group('sound and timing', () {
    testWidgets('Sound opens the sound sheet', (tester) async {
      final robot = AlertSettingsRobot(tester);
      await pumpPage(tester);

      await robot.tapRow(SemanticsIds.alertSettingsSound);

      expect(find.byType(AlertSoundSheet), findsOneWidget);

      await teardownApp(tester);
    });

    testWidgets('a picked sound writes alert_sound and asks for one reconcile '
        'pass', (tester) async {
      final robot = AlertSettingsRobot(tester);
      await pumpPage(tester);
      expect((await stored(tester)).sound, SettingsKeys.defaultAlertSound);

      await robot.tapRow(SemanticsIds.alertSettingsSound);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.soundPhoneDefault));
      await robot.settle();

      expect(find.byType(AlertSoundSheet), findsNothing);
      expect((await stored(tester)).sound, AlertSound.systemDefaultValue);
      expect(reconciles, [AlertReconcileReason.eventChanged]);
      expectRowSays(SemanticsIds.alertSettingsSound, l10n.alertSoundPhoneDefault);

      await teardownApp(tester);
    });

    for (final (name, id, value, read)
        in <(String, String, int, int Function(AlertSettings))>[
          (
            'Snooze',
            SemanticsIds.alertSettingsSnooze,
            15,
            (a) => a.snoozeMinutes,
          ),
          (
            'Upcoming notice',
            SemanticsIds.alertSettingsNotice,
            60,
            (a) => a.noticeLeadMinutes,
          ),
          (
            'Silence after',
            SemanticsIds.alertSettingsSilence,
            5,
            (a) => a.silenceAfterMinutes,
          ),
        ]) {
      testWidgets('$name writes its key once the drag lets go, then asks for '
          'the reconcile pass — never mid-drag', (tester) async {
        final robot = AlertSettingsRobot(tester);
        await pumpPage(tester);
        final before = read(await stored(tester));
        expect(before, isNot(value));

        await robot.dragTo(id, value);
        expect(reconciles, isEmpty);
        await robot.release(id, value);

        expect(read(await stored(tester)), value);
        expect(reconciles, [AlertReconcileReason.eventChanged]);

        await teardownApp(tester);
      });
    }

    test('the notice reads hours from an hour up when they are whole, '
        'minutes otherwise, off at zero (N121 / N153)', () {
      String en(int minutes) =>
          AlertSettingsPage.noticeLeadCaption(l10n, minutes);
      expect(en(0), l10n.alertsNoticeLeadOff);
      expect(en(30), contains('30 minutes before'));
      expect(en(60), contains('1 hour before'));
      expect(en(90), contains('90 minutes before'));
      expect(en(120), contains('2 hours before'));
      expect(en(1440), contains('24 hours before'));

      final de = AppLocalizationsDe();
      expect(
        AlertSettingsPage.noticeLeadCaption(de, 60),
        contains('1 Stunde vor'),
      );
      expect(
        AlertSettingsPage.noticeLeadCaption(de, 120),
        contains('2 Stunden vor'),
      );
      final ro = AppLocalizationsRo();
      expect(
        AlertSettingsPage.noticeLeadCaption(ro, 60),
        contains('cu 1 oră înainte'),
      );
      expect(
        AlertSettingsPage.noticeLeadCaption(ro, 120),
        contains('cu 2 ore înainte'),
      );
      expect(
        AlertSettingsPage.noticeLeadCaption(ro, 1440),
        contains('cu 24 de ore înainte'),
      );
    });

    testWidgets('the notice row\'s caption and its draft caption read the '
        'same: hours while a drag holds a whole hour, minutes between, off '
        'at zero', (tester) async {
      final robot = AlertSettingsRobot(tester);
      await pumpPage(tester);

      /// The caption the row shows: its slot also lays out the readings at
      /// either end of the range, invisibly, to hold its height.
      void expectCaption(String text) {
        final shown = find
            .descendant(
              of: find.bySemanticsIdentifier(SemanticsIds.alertSettingsNotice),
              matching: find.text(text),
            )
            .evaluate()
            .where((element) {
              var template = false;
              element.visitAncestorElements((ancestor) {
                final widget = ancestor.widget;
                template = widget is Opacity && widget.opacity == 0;
                return !template;
              });
              return !template;
            });
        expect(shown, hasLength(1), reason: text);
      }

      // Shipped at 120.
      expectCaption(AlertSettingsPage.noticeLeadCaption(l10n, 120));

      for (final minutes in const [60, 90, 1440, 30, 0]) {
        await robot.dragTo(SemanticsIds.alertSettingsNotice, minutes);
        expectCaption(AlertSettingsPage.noticeLeadCaption(l10n, minutes));
      }
      await robot.release(SemanticsIds.alertSettingsNotice, 0);
      expectCaption(l10n.alertsNoticeLeadOff);
      expect((await stored(tester)).noticeLeadMinutes, 0);

      await teardownApp(tester);
    });
  });

  group('permissions', () {
    PermissionService register(FakePermissionGateway gateway) {
      final service = PermissionService(
        gateway: gateway,
        store: MemoryPermissionPromptStore(),
        deviceId: () async => 'device-a',
      );
      GetIt.I.registerSingleton<PermissionService>(service);
      return service;
    }

    testWidgets('the permissions row shows the snapshot\'s attention', (
      tester,
    ) async {
      final service = register(
        FakePermissionGateway(
          statuses: {AppPermission.notifications: PermissionStatus.denied},
        ),
      );
      await tester.runAsync(service.refresh);
      await pumpPage(tester);

      Finder glyph(IconData icon) => find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.alertSettingsPermissions),
        matching: find.byIcon(icon),
      );
      expect(glyph(Icons.error_outline_rounded), findsOneWidget);
      expect(glyph(Icons.chevron_right_rounded), findsNothing);

      await teardownApp(tester);
    });

    testWidgets('the row speaks the hub\'s attention sentence while '
        'attention is on, and not without', (tester) async {
      final semantics = tester.ensureSemantics();
      final gateway = FakePermissionGateway(
        statuses: {AppPermission.notifications: PermissionStatus.denied},
      );
      final service = register(gateway);
      await tester.runAsync(service.refresh);
      await pumpPage(tester);

      final sentence = l10n.permissionsRowAttention(
        service.snapshot.value!.missingEssential.length,
      );
      String label() => tester
          .getSemantics(
            find.bySemanticsIdentifier(SemanticsIds.alertSettingsPermissions),
          )
          .getSemanticsData()
          .label;
      expect(label(), contains(sentence));

      gateway.current
        ..[AppPermission.notifications] = PermissionStatus.granted
        ..[AppPermission.exactAlarms] = PermissionStatus.granted;
      await tester.runAsync(service.refresh);
      await tester.pump();
      expect(service.snapshot.value!.needsAttention, isFalse);
      expect(label(), isNot(contains(sentence)));
      expect(label(), contains(l10n.permissionsTitle));

      await teardownApp(tester);
      semantics.dispose();
    });

    testWidgets('Test alarm refreshes permissions first, then arms through '
        'the scheduler with its title and delay', (tester) async {
      final robot = AlertSettingsRobot(tester);
      final gateway = FakePermissionGateway(
        statuses: {
          AppPermission.notifications: PermissionStatus.granted,
          AppPermission.exactAlarms: PermissionStatus.granted,
        },
      );
      register(gateway);
      statusReadsAtArm = () => gateway.statusReads;
      await pumpPage(tester);
      final readsBefore = gateway.statusReads;

      await robot.tapRow(SemanticsIds.alertsTestAlarm);

      expect(testAlarms, [(l10n.alertsTestAlarm, kAlertTestAlarmDelay)]);
      expect(statusReadsAtTestAlarm.single, greaterThan(readsBefore));
      expect(find.text(l10n.alertsTestAlarmScheduled), findsOneWidget);

      await teardownApp(tester);
    });

    testWidgets('Test alarm with an essential permission missing arms '
        'nothing and offers the review', (tester) async {
      final robot = AlertSettingsRobot(tester);
      register(
        FakePermissionGateway(
          statuses: {AppPermission.notifications: PermissionStatus.denied},
        ),
      );
      await pumpPage(tester);

      await robot.tapRow(SemanticsIds.alertsTestAlarm);

      expect(testAlarms, isEmpty);
      expect(find.text(l10n.permissionsAlertBlocked), findsOneWidget);
      expect(find.text(l10n.permissionsReview), findsOneWidget);

      await teardownApp(tester);
    });

    testWidgets('a refused test alarm says it failed', (tester) async {
      final robot = AlertSettingsRobot(tester);
      testAlarmAnswer = null;
      await pumpPage(tester);

      await robot.tapRow(SemanticsIds.alertsTestAlarm);

      expect(testAlarms, hasLength(1));
      expect(find.text(l10n.alertsTestAlarmFailed), findsOneWidget);

      await teardownApp(tester);
    });
  });

  group('the rows to other pages', () {
    testWidgets('Alerts per category opens the categories page, stamped', (
      tester,
    ) async {
      final observer = _RecordingObserver();
      await pumpPage(tester, observers: [observer]);
      observer.pushed.clear();

      await AlertSettingsRobot(
        tester,
      ).tapRowUnbuilt(SemanticsIds.alertSettingsCategoriesOpen);

      expect(
        observer.pushed.single.settings.arguments,
        const NavDestination(NavDestinationKind.calendarCategories),
      );

      await teardownApp(tester);
    });

    testWidgets('How it works pushes the guide\'s alerts topic, unstamped '
        '(D12)', (tester) async {
      final observer = _RecordingObserver();
      await pumpPage(tester, observers: [observer]);
      observer.pushed.clear();

      await AlertSettingsRobot(
        tester,
      ).tapRowUnbuilt(SemanticsIds.alertSettingsHowItWorksOpen);

      final route = observer.pushed.single as MaterialPageRoute<Object?>;
      expect(route.settings.arguments, isNull);
      final topicPage = route.builder(
        tester.element(find.byType(AlertSettingsPage)),
      );
      expect(topicPage, isA<CalendarGuideTopicPage>());
      expect(
        (topicPage as CalendarGuideTopicPage).topic,
        CalendarGuideTopic.alerts,
      );

      await teardownApp(tester);
    });
  });

  // The default rows' large-text cases, moved with the rows from
  // `calendar_settings_large_text_test.dart`. Roboto is loaded, so a word is
  // as wide as a phone draws it.
  group('large text', () {
    const phone = Size(360, 780);

    setUp(() async {
      await settings.setAlertDefaultTimed((
        mode: AlertMode.ring,
        offsetMinutes: 10,
      ));
      await settings.setAlertDefaultAllDay((
        mode: AlertMode.notify,
        daysBefore: 1,
        dayMinute: 9 * 60,
      ));
    });

    /// Scrolls the page until [text] is built, laying every section out on
    /// the way; a layout that throws anywhere on the page surfaces here.
    Future<void> scrollTo(WidgetTester tester, String text) async {
      for (var i = 0; i < 60; i++) {
        expect(tester.takeException(), isNull);
        if (find.text(text).evaluate().isNotEmpty) return;
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      fail('"$text" never came into view');
    }

    /// Every line of [paragraph] starts after a space, after a hyphen, or at
    /// a soft hyphen (U+00AD) — the engine's legitimate break inside a long
    /// word, though it draws no hyphen there — and never inside a word.
    void expectBreaksBetweenWords(RenderParagraph paragraph) {
      final text = paragraph.text.toPlainText();
      int? previous;
      double? previousTop;
      for (var i = 0; i < text.length; i++) {
        if (text[i] == ' ' || text[i] == '\u00AD') continue;
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: i, extentOffset: i + 1),
        );
        if (boxes.isEmpty) continue;
        final top = boxes.first.top;
        if (previous != null && (top - previousTop!).abs() > 0.5) {
          final between = text.substring(previous + 1, i);
          expect(
            text[previous] == '-' ||
                between.contains(' ') ||
                between.contains('\u00AD'),
            isTrue,
            reason:
                '"$text" breaks inside a word: '
                '"${text.substring(0, i)}|${text.substring(i)}"',
          );
        }
        previous = i;
        previousTop = top;
      }
    }

    /// Every paragraph laid out on the page — top to bottom, the slot
    /// templates too — is painted whole and holds its words: none is cut
    /// short or at the side, none is narrower than its longest word where
    /// that word fits the width it was given, and none breaks inside a word
    /// there. Nothing overflows on the way down.
    Future<void> expectPageWhole(WidgetTester tester) async {
      final list = find.byType(ListView);
      for (var i = 0; i < 60; i++) {
        expect(tester.takeException(), isNull);
        for (final element in find.byType(RichText).evaluate()) {
          final paragraph = element.renderObject;
          if (paragraph is! RenderParagraph || !paragraph.hasSize) continue;
          final text = paragraph.text.toPlainText();
          expect(paragraph.didExceedMaxLines, isFalse, reason: '"$text"');
          expect(
            paragraph.size.height,
            greaterThanOrEqualTo(paragraph.textSize.height - 0.01),
            reason: '"$text" is cut short',
          );
          expect(
            paragraph.size.width,
            greaterThanOrEqualTo(paragraph.textSize.width - 0.01),
            reason: '"$text" is cut at the side',
          );
          final longestWord = paragraph.getMinIntrinsicWidth(double.infinity);
          if (longestWord <= paragraph.constraints.maxWidth) {
            expect(
              paragraph.size.width,
              greaterThanOrEqualTo(longestWord - 0.01),
              reason: '"$text" breaks inside a word',
            );
            expectBreaksBetweenWords(paragraph);
          }
        }
        final position = tester
            .state<ScrollableState>(
              find
                  .descendant(of: list, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        if (position.pixels >= position.maxScrollExtent) return;
        await tester.drag(list, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      fail('the page never reached its end');
    }

    Finder tileOf(String title) =>
        find.ancestor(of: find.text(title), matching: find.byType(ListTile));

    /// The width the tile's text column has: the tile less its padding, its
    /// leading slot and the gap after it.
    double columnOf(WidgetTester tester, String title) =>
        tester.getRect(tileOf(title)).width -
        FormMetrics.settingsRowPadding.horizontal -
        FormMetrics.settingsLeadingWidth -
        FormMetrics.settingsTitleGap;

    /// [text], a line of the tile titled [title], holds its words whole, or
    /// — where one word is wider than the whole text column — fills the
    /// column: it is never narrower than the row allows.
    void expectWholeWords(WidgetTester tester, String text, {String? title}) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      final longestWord = paragraph.getMinIntrinsicWidth(double.infinity);
      final column = columnOf(tester, title ?? text);
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(math.min(longestWord, column) - 0.01),
        reason: '"$text" breaks inside a word',
      );
      if (longestWord <= column) expectBreaksBetweenWords(paragraph);
    }

    /// Every line of [text] is painted: the paragraph is as large as the
    /// text it laid out.
    void expectUnclipped(WidgetTester tester, String text) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(paragraph.textSize.height - 0.01),
        reason: '"$text" is cut short',
      );
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(paragraph.textSize.width - 0.01),
        reason: '"$text" is cut at the side',
      );
    }

    int linesOf(WidgetTester tester, String text) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      return paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: text.length),
          )
          .map((box) => box.top.round())
          .toSet()
          .length;
    }

    void expectBeside(WidgetTester tester, String title, String value) {
      final tile = tester.widget<ListTile>(tileOf(title));
      expect(tile.trailing, isNotNull, reason: '"$value" is not beside');
      expect(
        find.descendant(
          of: find.byWidget(tile.trailing!),
          matching: find.text(value),
        ),
        findsOneWidget,
      );
      expectUnclipped(tester, value);
      expectWholeWords(tester, value, title: title);
    }

    void expectUnder(WidgetTester tester, String title, String value) {
      expect(
        tester.widget<ListTile>(tileOf(title)).trailing,
        isNull,
        reason: '"$value" is not under its title',
      );
      final tile = tester.getRect(tileOf(title));
      final valueRect = tester.getRect(find.text(value));
      expect(
        valueRect.top,
        greaterThanOrEqualTo(tester.getRect(find.text(title)).bottom),
        reason: '"$value" is not under its title',
      );
      expect(
        valueRect.right,
        lessThanOrEqualTo(tile.right - FormMetrics.rowEndPadding),
      );
      expect(
        valueRect.left,
        greaterThanOrEqualTo(tile.left + RowMetrics.groupInset),
      );
      expectUnclipped(tester, value);
      expectWholeWords(tester, value, title: title);
    }

    testWidgets('German at text scale 2.0 on a 360 × 780 phone lays out to '
        'the end with no overflow, every value under its title, whole and '
        'uncut, every title and subtitle holding its words', (tester) async {
      await tester.runAsync(
        () => settings.setAlertDefaultAllDay((
          mode: AlertMode.ring,
          daysBefore: 7,
          dayMinute: 9 * 60,
        )),
      );
      await pumpPage(
        tester,
        surface: phone,
        locale: const Locale('de'),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);

      for (final (title, value, subtitle) in const [
        (
          'Termine mit Uhrzeit',
          'Alarm · 10 Min. vorher',
          'Die Erinnerung, mit der ein neuer Termin mit Uhrzeit startet',
        ),
        (
          'Ganztägige Termine',
          'Alarm · 7 Tage vorher, 09:00',
          'Die Erinnerung, mit der ein neuer ganztägiger Termin startet',
        ),
        (
          'Weckton',
          'Standard-Weckton des Telefons',
          'Was ein Alarm spielt, wenn die Erinnerung keinen Ton nennt',
        ),
      ]) {
        await scrollTo(tester, title);
        expect(tester.takeException(), isNull);
        expectWholeWords(tester, title);
        expectUnder(tester, title, value);
        expectWholeWords(tester, subtitle, title: title);
      }
      // Down to the last row, every section laid out on the way.
      await scrollTo(tester, 'Erinnert werden');
      expect(tester.takeException(), isNull);
      expectUnclipped(tester, 'Erinnert werden');

      await teardownApp(tester);
    });

    for (final (locale, strings) in <(Locale, AppLocalizations)>[
      (const Locale('de'), AppLocalizationsDe()),
      (const Locale('ro'), AppLocalizationsRo()),
    ]) {
      testWidgets('${locale.languageCode} at 2.0 on a 360 phone: the Test '
          'alarm label breaks only between whole words, "10 s" never alone, '
          'and the button holds it with its air', (tester) async {
        await pumpPage(
          tester,
          surface: phone,
          locale: locale,
          textScale: 2.0,
        );
        final label = strings.alertsTestAlarm;
        await scrollTo(tester, label);
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expectUnclipped(tester, label);
        expect(
          paragraph.size.width,
          greaterThanOrEqualTo(
            paragraph.getMinIntrinsicWidth(double.infinity) - 0.01,
          ),
          reason: '"$label" breaks inside a word',
        );
        // The preposition, the number and the unit are one unbreakable run.
        final tail = label.lastIndexOf(' ') + 1;
        final tops = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: tail, extentOffset: label.length),
            )
            .map((box) => box.top.round())
            .toSet();
        expect(tops, hasLength(1), reason: '"${label.substring(tail)}"');

        final button = tester.getRect(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );
        expect(button.height, greaterThanOrEqualTo(FormMetrics.rowMinHeight));
        expect(
          button.height,
          greaterThanOrEqualTo(
            paragraph.size.height +
                FormMetrics.settingsButtonPadding.vertical -
                0.01,
          ),
        );

        await teardownApp(tester);
      });
    }

    testWidgets('German at 2.0 with the all-day default at Reminder · the day '
        'before: its value is under its title too', (tester) async {
      await pumpPage(
        tester,
        surface: phone,
        locale: const Locale('de'),
        textScale: 2.0,
      );
      await scrollTo(tester, 'Ganztägige Termine');
      expectUnder(
        tester,
        'Ganztägige Termine',
        'Mitteilung · Am Vortag, 09:00',
      );

      await teardownApp(tester);
    });

    testWidgets('a value that fits the cap the tile gives a trailing stays '
        'beside the title, one that does not goes under: one line beside at '
        '2.0, under at 2.0 where beside it would take two lines', (
      tester,
    ) async {
      // No all-day default: "No alert" is one line at any width.
      await tester.runAsync(() => settings.setAlertDefaultAllDay(null));
      // The large phone at the phone's density, so the cap is 56 dp: in
      // Roboto at 2.0 the timed value would wrap beside its title there, and
      // the column under it holds it on one line.
      await pumpPage(
        tester,
        surface: const Size(412, 915),
        textScale: 2.0,
        density: VisualDensity.standard,
      );
      expect(tester.takeException(), isNull);
      await scrollTo(tester, 'All-day events');

      const timed = 'Alarm · 10 min before';
      expectUnder(tester, 'Timed events', timed);
      expect(linesOf(tester, timed), 1);
      expectBeside(tester, 'All-day events', 'No alert');
      expect(linesOf(tester, 'No alert'), 1);

      await teardownApp(tester);
    });

    testWidgets('at 1.0 on a 360 phone a value that would leave its title '
        'less than half the column goes under it: "All-day events" on one '
        'line, its caption whole, the value under it whole', (tester) async {
      await pumpPage(tester, surface: phone, density: VisualDensity.standard);
      expect(tester.takeException(), isNull);

      const allDay = 'Reminder · The day before, 9:00 AM';
      expectUnder(tester, 'All-day events', allDay);
      expect(linesOf(tester, 'All-day events'), 1);
      expectWholeWords(
        tester,
        l10n.alertsDefaultAllDayDesc,
        title: 'All-day events',
      );
      expect(linesOf(tester, l10n.alertsDefaultAllDayDesc), lessThan(3));
      // The timed value leaves its title 44 % of the column on this phone.
      const timed = 'Alarm · 10 min before';
      expectUnder(tester, 'Timed events', timed);
      expect(linesOf(tester, 'Timed events'), 1);

      await teardownApp(tester);
    });

    testWidgets('at 1.0 on a 360 phone a short value stays beside its title', (
      tester,
    ) async {
      await tester.runAsync(() => settings.setAlertDefaultAllDay(null));
      await pumpPage(tester, surface: phone, density: VisualDensity.standard);
      expect(tester.takeException(), isNull);

      expectBeside(tester, 'All-day events', 'No alert');
      expect(linesOf(tester, 'All-day events'), 1);

      await teardownApp(tester);
    });

    testWidgets('English at 1.0 on a 412 × 915 phone lays out to the end '
        'whole; the timed value beside its title, the all-day one under its '
        'one-line title', (tester) async {
      await pumpPage(
        tester,
        surface: const Size(412, 915),
        density: VisualDensity.standard,
      );
      expect(tester.takeException(), isNull);

      expectBeside(tester, 'Timed events', 'Alarm · 10 min before');
      expect(linesOf(tester, 'Timed events'), 1);
      expectUnder(
        tester,
        'All-day events',
        'Reminder · The day before, 9:00 AM',
      );
      expect(linesOf(tester, 'All-day events'), 1);
      await expectPageWhole(tester);

      await teardownApp(tester);
    });

    for (final (locale, scale, dark) in const [
      (Locale('en'), 1.0, false),
      (Locale('de'), 2.0, true),
      (Locale('ro'), 2.0, true),
      (Locale('ro'), 2.0, false),
    ]) {
      testWidgets('${locale.languageCode} at $scale on a 360 × 780 phone, '
          '${dark ? 'dark' : 'light'}: every paragraph down to the last row '
          'whole, uncut and unbroken inside a word, no overflow', (
        tester,
      ) async {
        await pumpPage(
          tester,
          surface: phone,
          locale: locale,
          textScale: scale,
          dark: dark,
        );
        await expectPageWhole(tester);

        await teardownApp(tester);
      });
    }

    testWidgets('German at 2.0 on a 360 phone: the Permissions caption breaks '
        'only between words \u2014 it says Mitteilungen, since Benachrichtigungen '
        'alone is wider than the column', (tester) async {
      await pumpPage(
        tester,
        surface: phone,
        locale: const Locale('de'),
        textScale: 2.0,
        dark: true,
      );
      final caption = AppLocalizationsDe().permissionsCalendarRowDesc;
      // Flutter 3.44 breaks at a soft hyphen but draws no hyphen there, so
      // the caption keeps a word that fits the column whole instead.
      expect(caption, isNot(contains('\u00AD')));
      expect(caption, startsWith('Mitteilungen'));
      await scrollTo(tester, caption);

      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(caption),
      );
      expectUnclipped(tester, caption);
      // Every word fits the column, so every break falls between words.
      expect(
        paragraph.getMinIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(paragraph.size.width),
      );
      expectBreaksBetweenWords(paragraph);

      await teardownApp(tester);
    });

    for (final (locale, scale) in const [
      (Locale('en'), 1.0),
      (Locale('de'), 2.0),
      (Locale('ro'), 2.0),
    ]) {
      testWidgets('${locale.languageCode} at $scale on a 360 phone: each '
          'slider stays put at every step of a drag — the notice at 150, 270, '
          '1350 and 1410 as at its idle 120 — and after it lets go', (
        tester,
      ) async {
        await pumpPage(
          tester,
          surface: phone,
          locale: locale,
          textScale: scale,
        );
        final robot = AlertSettingsRobot(tester);
        List<int> steps(int min, int max, int step) => [
          for (var value = min; value <= max; value += step) value,
        ];
        // The readings the review saw move the notice slider in ro at 2.0.
        expect(
          steps(
            SettingsKeys.minAlertNoticeLeadMinutes,
            SettingsKeys.maxAlertNoticeLeadMinutes,
            SettingsKeys.alertNoticeLeadMinutesStep,
          ),
          containsAll(const [150, 270, 1350, 1410]),
        );
        expect(SettingsKeys.defaultAlertNoticeLeadMinutes, 120);
        for (final (id, idle, values) in [
          (
            SemanticsIds.alertSettingsNotice,
            SettingsKeys.defaultAlertNoticeLeadMinutes,
            steps(
              SettingsKeys.minAlertNoticeLeadMinutes,
              SettingsKeys.maxAlertNoticeLeadMinutes,
              SettingsKeys.alertNoticeLeadMinutesStep,
            ),
          ),
          (
            SemanticsIds.alertSettingsSnooze,
            SettingsKeys.defaultAlertSnoozeMinutes,
            steps(
              SettingsKeys.minAlertSnoozeMinutes,
              SettingsKeys.maxAlertSnoozeMinutes,
              SettingsKeys.alertSnoozeMinutesStep,
            ),
          ),
          (
            SemanticsIds.alertSettingsSilence,
            SettingsKeys.defaultAlertSilenceAfterMinutes,
            steps(
              SettingsKeys.minAlertSilenceAfterMinutes,
              SettingsKeys.maxAlertSilenceAfterMinutes,
              1,
            ),
          ),
        ]) {
          final row = robot.row(id);
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          final slider = find.descendant(
            of: row,
            matching: find.byType(Slider),
          );
          double top() =>
              tester.getTopLeft(slider).dy - tester.getTopLeft(row).dy;
          final idleTop = top();
          for (final value in values) {
            await robot.dragTo(id, value);
            expect(top(), idleTop, reason: '$id at $value');
          }
          await robot.release(id, idle);
          expect(top(), idleTop, reason: '$id let go');
        }
        expect(tester.takeException(), isNull);

        await teardownApp(tester);
      });
    }
  });
}

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) pushed.add(route);
  }
}
