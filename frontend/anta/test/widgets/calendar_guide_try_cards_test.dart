import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/bloc/permissions/permissions_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_icons.dart';
import 'package:anta/constants/calendar_templates.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_guide_content.dart';
import 'package:anta/models/event_template.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/alarm_page.dart';
import 'package:anta/pages/calendar_guide_topic_page.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/pages/permissions_page.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_digest_service.dart';
import 'package:anta/services/event_time_formatter.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/event_template_service.dart';
import 'package:anta/services/filter_preset_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/recurrence_formatter.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/alert_labels.dart';
import 'package:anta/widgets/alert_editor_sheet.dart';
import 'package:anta/widgets/calendar_appearance_preview.dart';
import 'package:anta/widgets/calendar_date_picker_sheet.dart';
import 'package:anta/widgets/calendar_filter_sheet.dart';
import 'package:anta/widgets/calendar_guide_try_card.dart';
import 'package:anta/widgets/category_editor_sheet.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';
import 'package:anta/widgets/event_repeat_sheet.dart';
import 'package:anta/widgets/quick_alarm_sheet.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../services/permission_support.dart';
import 'support/category_editor_robot.dart';
import 'support/guide_try_card_robot.dart';
import 'support/practice_calendar_robot.dart';
import 'support/sandbox_write_log.dart';

/// The pages pushed — not the menus and sheets, which are popup routes — so
/// a test can say a card opened a page, or, as often, that it opened none.
class _PushLog extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) pushed.add(route);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final en = AppLocalizationsEn();
  late Directory tempDir;
  late AppDatabase db;
  late SandboxWriteLog writes;
  late MarkdownBarBloc barBloc;
  late List<int> revisions;
  late _PushLog pushes;

  /// Every caption a case showed, and the slot's size at each: one size, or
  /// a caption moved the page.
  final shownSlots = <String, Size>{};

  List<int> staticRevisions() => [
    EventPresence.revision,
    EventSkips.revision,
    OccurrenceDescriptions.revision,
    CalendarCategories.revision,
    EventAlerts.revision,
    PublicHolidays.revision,
    identityHashCode(CalendarTemplates.all),
  ];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_guide_try');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    for (final locale in ['en', 'de', 'ro']) {
      await initializeDateFormatting(locale);
    }
    // Real glyphs: the caption slots and the overflow checks measure text.
    await loadGoldenFonts();
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    writes = SandboxWriteLog();
    db = await openTestDatabase(interceptor: writes);
    SettingsService.reset();
    SettingsService.forTesting(db);
    // Every service a sheet of the cards could write through, bound to the
    // recorded database.
    await CategoryService.forTesting(db);
    await CalendarEventService.forTesting(db);
    await EventPresenceService.forTesting(db);
    await EventSkipService.forTesting(db);
    await EventOccurrenceService.forTesting(db);
    await EventAlertService.forTesting(db);
    await EventTemplateService.forTesting(db);
    await FilterPresetService.forTesting(db);
    await PublicHolidayService.forTesting(db);
    await EventDigestService.forTesting(db);
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.forTesting(db),
    );
    // The Permissions row opens the real page: its bloc over a fake gateway,
    // since a test has no platform to ask.
    GetIt.I.registerFactory<PermissionsBloc>(
      () => PermissionsBloc(
        service: permissionServiceOver(FakePermissionGateway()),
      ),
    );
    expect(writes.statements, isNotEmpty);
    writes.statements.clear();
    revisions = staticRevisions();
    pushes = _PushLog();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await barBloc.close();
    CategoryService.reset();
    CalendarEventService.reset();
    EventPresenceService.reset();
    EventSkipService.reset();
    EventOccurrenceService.reset();
    EventAlertService.reset();
    EventTemplateService.reset();
    FilterPresetService.reset();
    PublicHolidayService.reset();
    EventDigestService.reset();
    MarkdownBarService.reset();
    CalendarPaletteService.reset();
    SettingsService.reset();
    CalendarCategories.updateCache(const []);
    await db.close();
  });

  /// The card saved nothing: no statement reached the database, none of the
  /// calendar's static caches moved, nothing went to the preferences.
  Future<void> expectNothingSaved() async {
    expect(writes.statements, isEmpty);
    expect(staticRevisions(), revisions);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  }

  Future<GuideTryCardRobot> open(
    WidgetTester tester,
    CalendarGuideTopic topic, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    TextScaler textScaler = TextScaler.noScaling,
    Size size = const Size(412, 915),
    DateTime Function() now = DateTime.now,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      BlocProvider<MarkdownBarBloc>.value(
        value: barBloc,
        child: MaterialApp(
          theme: brightness == Brightness.light
              ? AppTheme.light()
              : AppTheme.dark(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: [pushes],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
          home: CalendarGuideTopicPage(topic: topic, now: now),
        ),
      ),
    );
    await tester.pumpAndSettle();
    pushes.pushed.clear();
    shownSlots.clear();
    return GuideTryCardRobot(tester, topic.slug);
  }

  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);
  DateTime day(int offset) =>
      DateTime.utc(today.year, today.month, today.day + offset);
  // Built on first use: the locale data loads in setUpAll.
  late final dates = DateFormat.yMMMMEEEEd('en');

  void note(GuideTryCardRobot robot) =>
      shownSlots[robot.caption] = robot.slotSize;
  void expectOneSlotHeight() {
    expect(shownSlots.length, greaterThan(1));
    expect(shownSlots.values.toSet(), hasLength(1), reason: '$shownSlots');
    shownSlots.clear();
  }

  group('the frame', () {
    testWidgets('the card comes first, above How it works', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);

      expect(robot.card, findsOneWidget);
      expect(
        tester.getTopLeft(find.text(en.calendarGuideTryIt)).dy,
        lessThan(tester.getTopLeft(find.text(en.calendarGuideHowItWorks)).dy),
      );
      // The lead-in is the entry's searchable title, drawn as the body's
      // first line.
      expect(
        find.descendant(
          of: robot.card,
          matching: find.text(en.calendarGuideTryScreen),
        ),
        findsOneWidget,
      );
      await expectNothingSaved();
    });

    testWidgets('a page with nothing to try has no card', (tester) async {
      await open(tester, CalendarGuideTopic.good);

      expect(find.text(en.calendarGuideTryIt), findsNothing);
      expect(find.byType(CalendarGuideTryCard), findsNothing);
    });

    testWidgets('the entry is a container node, never merged: the stage\'s '
        'controls and the live caption are nodes of their own', (tester) async {
      final handle = tester.ensureSemantics();
      // The screen card: its caption is never empty, and an empty one is
      // left out of the tree with nothing to announce.
      final robot = await open(tester, CalendarGuideTopic.screen);

      final entry = tester.getSemantics(robot.card);
      final add = tester.getSemantics(robot.control('more'));
      final caption = tester.getSemantics(
        find.bySemanticsIdentifier(
          SemanticsIds.calendarGuideTryCaption(CalendarGuideTopic.screen.slug),
        ),
      );
      expect(add.id, isNot(entry.id));
      expect(caption.id, isNot(entry.id));
      bool under(SemanticsNode node) {
        for (var p = node.parent; p != null; p = p.parent) {
          if (p.id == entry.id) return true;
        }
        return false;
      }

      expect(under(add), isTrue);
      expect(under(caption), isTrue);
      expect(
        caption.getSemanticsData().label,
        en.calendarGuideDemoFormat(en.calendarFormatMonth),
      );
      expect(add.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(entry.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      expect(caption.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('what she did survives the card scrolling away', (
      tester,
    ) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.alerts,
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(1.5),
      );
      await robot.tap('add');
      await robot.tapId(SemanticsIds.alertSheetSave);
      final said = robot.caption;
      expect(said, isNotEmpty);

      final list = find
          .descendant(
            of: find.byType(SettingsSectionList),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.bySemanticsIdentifier(SemanticsIds.calendarGuideRow('hub')),
        600,
        scrollable: list,
        maxScrolls: 100,
      );
      await tester.pumpAndSettle();
      // Gone from the tree, as the kit's list drops what is far off screen.
      expect(find.byType(CalendarGuideTryCard), findsNothing);

      await tester.scrollUntilVisible(
        robot.card,
        -600,
        scrollable: list,
        maxScrolls: 100,
      );
      await tester.pumpAndSettle();
      expect(robot.caption, said);
      expect(robot.control('alert-0'), findsOneWidget);
      await expectNothingSaved();
    });
  });

  group('screen', () {
    testWidgets('the menus and the mode switch say what they would do, and '
        'open nothing', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.screen);
      expect(robot.caption, en.calendarGuideDemoFormat(en.calendarFormatMonth));
      note(robot);

      await robot.tapId(SemanticsIds.calendarViewMenu);
      await robot.tapId(SemanticsIds.calendarFormatTwoWeeks);
      expect(
        robot.caption,
        en.calendarGuideDemoFormat(en.calendarFormatTwoWeeks),
      );
      note(robot);

      await robot.tapId(SemanticsIds.calendarViewMenu);
      await robot.tapId(SemanticsIds.calendarOverviewOpen);
      expect(robot.caption, en.calendarGuideWouldOpen(en.calendarOverview));
      note(robot);

      for (final (row, said) in [
        (
          SemanticsIds.calendarAlertsOpen,
          en.calendarGuideWouldOpen(en.alertsTitle),
        ),
        (SemanticsIds.calendarExport, en.calendarGuideWouldShare),
        (SemanticsIds.calendarGuideOpen, en.calendarGuideYouAreHere),
        (
          SemanticsIds.calendarSettingsOpen,
          en.calendarGuideWouldOpen(en.calendarSettingsRow),
        ),
      ]) {
        await robot.tap('more');
        await robot.tapId(row);
        expect(robot.caption, said);
        note(robot);
      }

      for (final (mode, said) in [
        ('timeline', en.calendarGuideDemoPanelTimeline(en.panelModeTimeline)),
        ('upcoming', en.calendarGuideDemoPanelUpcoming(en.upcomingEvents)),
        ('day', en.calendarGuideDemoPanelDay(en.panelModeDay)),
      ]) {
        await robot.tapId(SemanticsIds.panelMode(mode));
        expect(robot.caption, said);
        note(robot);
      }

      // The expand button is drawn, disabled: there is no grid to cover.
      final expand = tester.widget<IconButton>(
        find.descendant(of: robot.card, matching: find.byType(IconButton)).last,
      );
      expect(expand.onPressed, isNull);
      expect(pushes.pushed, isEmpty);
      expectOneSlotHeight();
      await expectNothingSaved();
    });
  });

  group('events', () {
    String rowId(String key) => 'row-$key';

    testWidgets('idle, with the three demo rows', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);

      expect(robot.caption, en.calendarGuideDemoLongPressHint);
      for (final key in ['dentist', 'yoga', 'rent']) {
        expect(robot.control(rowId(key)), findsOneWidget, reason: key);
      }
      expect(robot.shows(en.eventAllDay), isTrue);
      await expectNothingSaved();
    });

    testWidgets('+ adds through the sandboxed editor, a row opens, changes '
        'and deletes, and the stage never changes height', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);
      final sheets = PracticeCalendarRobot(tester);
      final stage = robot.stageSize;
      note(robot);

      await robot.tap('add');
      expect(find.byType(EventEditorSheet), findsOneWidget);
      await sheets.typeTitle('Swim');
      await sheets.saveEditor();
      expect(
        robot.caption,
        en.calendarGuideDemoAdded('Swim', dates.format(today)),
      );
      expect(robot.shows('Swim'), isTrue);
      note(robot);

      await robot.tap(rowId('dentist'));
      expect(find.byType(EventDetailSheet), findsOneWidget);
      await sheets.detailEdit();
      await sheets.typeTitle('Dentist at noon');
      await sheets.saveEditor();
      // The editor's Save returns to the detail sheet, as on the calendar.
      expect(sheets.detailOpen, isTrue);
      await sheets.detailClose();
      expect(robot.caption, en.calendarGuideDemoChanged('Dentist at noon'));
      expect(robot.shows('Dentist at noon'), isTrue);
      note(robot);

      await robot.tap(rowId('yoga'));
      await sheets.detailEdit();
      await sheets.deleteInEditor(en.delete);
      expect(robot.control(rowId('yoga')), findsNothing);
      expect(
        robot.caption,
        en.calendarGuideDemoDeleted(en.calendarGuideDemoEventYoga),
      );
      note(robot);

      // Three more of hers: the oldest makes room, the stage holds its size.
      for (final title in ['One', 'Two', 'Three']) {
        await robot.tap('add');
        await sheets.typeTitle(title);
        await sheets.saveEditor();
      }
      expect(robot.shows('Swim'), isFalse);
      expect(robot.shows('Three'), isTrue);
      expect(robot.stageSize, stage);
      expect(pushes.pushed, isEmpty);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('the detail sheet\'s Add date, Dates and description change '
        'the demo, here only', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);
      final sheets = PracticeCalendarRobot(tester);
      final dentist = en.calendarGuideDemoEventDentist;
      // Days in the picker's opening month: today's own.
      final extra = today.day < 20 ? day(3) : day(-3);
      final more = today.day < 20 ? day(5) : day(-5);
      CalendarDatePickerSheet picker() =>
          tester.widget(find.byType(CalendarDatePickerSheet));
      note(robot);

      // Add date on the one-time Dentist pins it to a set.
      await robot.tap(rowId('dentist'));
      await sheets.detailAddDate();
      expect(picker().initialView, CalendarDatePickerView.month);
      await sheets.pickInDatePicker(extra);
      await robot.tapId(SemanticsIds.datePickerSave);
      expect(robot.caption, en.calendarGuideDemoChanged(dentist));
      note(robot);

      // Back on the detail sheet, whose Dates row opens the set as a list.
      expect(sheets.detailOpen, isTrue);
      await robot.tapId(SemanticsIds.eventDetailDates);
      expect(picker().initialView, CalendarDatePickerView.list);
      expect(picker().initialSelection, {today, extra});
      await robot.tapId(SemanticsIds.datePickerView('month'));
      await sheets.pickInDatePicker(more);
      await robot.tapId(SemanticsIds.datePickerSave);
      expect(robot.caption, en.calendarGuideDemoChanged(dentist));
      await robot.tapId(SemanticsIds.eventDetailDates);
      expect(picker().initialSelection, {today, extra, more});
      // Cancel returns to the detail sheet, the set as it was.
      await robot.tapId(SemanticsIds.datePickerCancel);
      expect(sheets.detailOpen, isTrue);

      // The description cell's quick edit.
      await sheets.quickEditDescription('Bring the card');
      expect(robot.caption, en.calendarGuideDemoChanged(dentist));
      note(robot);
      expect(
        find.descendant(
          of: find.byType(EventDetailSheet),
          matching: find.textContaining('Bring the card', findRichText: true),
        ),
        findsWidgets,
      );
      await sheets.detailClose();
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('a long title is cut in the caption', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.events);
      final sheets = PracticeCalendarRobot(tester);
      final long = 'A' * 40;

      await robot.tap('add');
      await sheets.typeTitle(long);
      await sheets.saveEditor();

      expect(
        robot.caption,
        en.calendarGuideDemoAdded('${'A' * 24}…', dates.format(today)),
      );
      await expectNothingSaved();
    });

    testWidgets('a skip from the detail sheet is kept here only', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.events);
      final sheets = PracticeCalendarRobot(tester);

      // Yoga repeats on today's weekday, so its row stands for today.
      await robot.tap(rowId('yoga'));
      await sheets.detailSkip();
      expect(
        robot.caption,
        en.calendarGuideDemoSkipped(
          dates.format(today),
          en.calendarGuideDemoEventYoga,
        ),
      );
      await expectNothingSaved();
    });

    testWidgets('the long press offers the templates, Blank and the quick '
        'alarm', (tester) async {
      final template = await (await EventTemplateService.getInstance()).create(
        EventTemplate(id: '', name: 'Haircut', categoryId: kDefaultCategoryId),
      );
      writes.statements.clear();
      revisions = staticRevisions();
      final robot = await open(tester, CalendarGuideTopic.events);
      final sheets = PracticeCalendarRobot(tester);
      note(robot);

      await robot.longPress('add');
      await robot.tapId(SemanticsIds.templatePickRow(template.id));
      expect(robot.caption, en.calendarGuideDemoTemplate('Haircut'));
      expect(robot.shows('Haircut'), isTrue);
      note(robot);

      await robot.longPress('add');
      await robot.tapId(SemanticsIds.quickAlarmRow);
      expect(robot.caption, en.calendarGuideWouldOpen(en.quickAlarmTitle));
      note(robot);

      await robot.longPress('add');
      await robot.tapId(SemanticsIds.templatePickBlank);
      expect(find.byType(EventEditorSheet), findsOneWidget);
      await sheets.typeTitle('Blank one');
      await sheets.saveEditor();
      expect(
        robot.caption,
        en.calendarGuideDemoAdded('Blank one', dates.format(today)),
      );
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });
  });

  group('alerts', () {
    testWidgets('the slot rests empty and reserved', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);

      expect(robot.caption, isEmpty);
      expect(robot.slotSize.height, greaterThan(0));
      expect(robot.control('alert-0'), findsNothing);
      await expectNothingSaved();
    });

    testWidgets('Add alert, change it, remove it — through the real sheet', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);
      note(robot);

      await robot.tap('add');
      expect(find.byType(AlertEditorSheet), findsOneWidget);
      await robot.tapId(SemanticsIds.alertSheetSave);
      expect(robot.control('alert-0'), findsOneWidget);
      expect(
        robot.caption,
        en.calendarGuideDemoAlertSet(
          en.calendarGuideDemoEventDentist,
          en.eventAlertMinutesBefore(kDraftAlertOffsetMinutes),
        ),
      );
      note(robot);

      await robot.tap('alert-0');
      await robot.tapId(SemanticsIds.alertTypeAlarm);
      await robot.tapId(SemanticsIds.alertSheetSave);
      expect(robot.shows(en.eventAlertModeRing), isTrue);
      note(robot);

      await robot.tap('alert-0');
      await robot.tapId(SemanticsIds.alertRemove);
      expect(robot.control('alert-0'), findsNothing);
      expect(
        robot.caption,
        en.calendarGuideDemoChanged(en.calendarGuideDemoEventDentist),
      );
      note(robot);
      expect(pushes.pushed, isEmpty);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('the alarm screen opens on its own page and Stop closes it', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);

      await robot.tap('show-alarm');
      expect(find.byType(AlarmPage), findsOneWidget);
      expect(pushes.pushed, hasLength(1));
      expect(pushes.pushed.single, isA<PageRoute<dynamic>>());
      expect(find.text(en.calendarGuideDemoEventDentist), findsWidgets);

      // Removal is off: no Remove / Keep row.
      expect(
        find.bySemanticsIdentifier(SemanticsIds.alarmKeepEvent),
        findsNothing,
      );

      await robot.tapId(SemanticsIds.alarmStop);
      expect(find.byType(AlarmPage), findsNothing);
      expect(find.byType(CalendarGuideTopicPage), findsOneWidget);
      await expectNothingSaved();
    });

    testWidgets('the alarm screen draws what a ring of the event draws, the '
        'Remove / Keep row with removal on', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);
      await robot.tap('add');
      await robot.tapId(SemanticsIds.alertTypeAlarm);
      await robot.tapId(SemanticsIds.alertRemoveAfter);
      await robot.tapId(SemanticsIds.alertSheetSave);

      await robot.tap('show-alarm');
      final alarm = find.byType(AlarmPage);
      expect(alarm, findsOneWidget);
      expect(tester.widget<AlarmPage>(alarm).payload.removeAfterAlert, isTrue);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.alarmKeepEvent),
        findsOneWidget,
      );

      // The seed: tomorrow at nine for 45 minutes, in the fallback category.
      final tomorrow = day(1);
      final fireAt = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);
      final labels = AlertLabels(strings: en, use24Hour: false);
      Finder onPage(String text) =>
          find.descendant(of: alarm, matching: find.text(text));
      expect(
        onPage(
          EventTimeFormatter.formatMinuteFor(
            9 * 60,
            localeName: 'en',
            use24Hour: false,
          ),
        ),
        findsOneWidget,
      );
      expect(
        onPage(
          labels.whenLabel(
            time: const EventTime(startMinute: 9 * 60, durationMinutes: 45),
            day: tomorrow,
            fireAt: fireAt,
          ),
        ),
        findsOneWidget,
      );
      final avatar = tester.widget<EventAvatar>(
        find.descendant(of: alarm, matching: find.byType(EventAvatar)),
      );
      expect(avatar.icon, CalendarIcons.forKey('medical_services'));
      expect(
        avatar.color,
        CalendarCategories.resolve(CalendarCategories.fallback.id).color,
      );

      // The preview's Keep only closes the page.
      await robot.tapId(SemanticsIds.alarmKeepEvent);
      expect(find.byType(AlarmPage), findsNothing);
      await expectNothingSaved();
    });

    testWidgets('the quick alarm reports its draft, here only', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);
      note(robot);

      await robot.tap('quick');
      expect(find.byType(QuickAlarmSheet), findsOneWidget);
      await robot.tapId(SemanticsIds.quickAlarmSave);
      expect(find.byType(QuickAlarmSheet), findsNothing);
      // The sheet's default name; the time and the day are the clock's.
      expect(robot.caption, startsWith('Alarm set for '));
      expect(robot.caption, endsWith(en.calendarGuideDemoHereOnly('')));
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('the Permissions row opens the real page', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.alerts);

      await robot.tap('permissions');
      expect(find.byType(PermissionsPage), findsOneWidget);
      expect(pushes.pushed, hasLength(1));
      await expectNothingSaved();
    });
  });

  group('kinds', () {
    testWidgets('idle on one day; repeat, pick a day, skip it', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.kinds);
      expect(robot.caption, en.calendarGuideDemoOneDay(dates.format(today)));
      note(robot);
      // One day: nothing to skip; its dates can grow.
      expect(robot.enabled('skip'), isFalse);
      expect(robot.enabled('add-date'), isTrue);

      await robot.tap('repeat');
      expect(find.byType(EventRepeatSheet), findsOneWidget);
      await robot.tapId(SemanticsIds.repeatKind('daily'));
      await robot.tapId(SemanticsIds.repeatDone);
      final daysThisMonth =
          DateUtils.getDaysInMonth(today.year, today.month) - today.day + 1;
      expect(
        robot.caption,
        en.calendarGuideDemoRepeats(en.recurrenceDaily, daysThisMonth),
      );
      note(robot);
      // A repeating event has no dates of its own; a day is not picked yet.
      expect(robot.enabled('add-date'), isFalse);
      expect(robot.enabled('skip'), isFalse);

      // Today is in the month shown and a day a daily event falls on.
      await robot.tap('day');
      expect(find.byType(CalendarDatePickerSheet), findsOneWidget);
      await PracticeCalendarRobot(tester).pickInDatePicker(today);
      expect(find.byType(CalendarDatePickerSheet), findsNothing);
      expect(robot.enabled('skip'), isTrue);

      await robot.tap('skip');
      expect(
        robot.caption,
        en.calendarGuideDemoSkipped(
          dates.format(today),
          en.calendarGuideDemoEventDentist,
        ),
      );
      expect(robot.enabled('skip'), isFalse);
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('Repeat keeps the last rule through "does not repeat", and a '
        'pinned set survives the trip', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.kinds);
      final sheets = PracticeCalendarRobot(tester);
      final weekly = RecurrenceFormatter.format(
        const WeeklyRecurrence(
          weekdays: {1, 2, 3, 4, 5, 6, 7},
          interval: EventRepeatDraft.maxInterval,
        ),
        en,
        'en',
        retroactive: true,
      );
      EventRepeatDraft opened() =>
          tester.widget<EventRepeatSheet>(find.byType(EventRepeatSheet)).draft;
      Future<void> doesNotRepeat() =>
          _tapIn(tester, _inRepeatSheet(find.text(en.recurrenceDoesNotRepeat)));
      note(robot);

      // Weekly on every day, every 99 weeks, until today, also before.
      await robot.tap('repeat');
      await _longestWeeklyRule(tester, en, endOn: today);
      await robot.tapId(SemanticsIds.repeatDone);
      expect(robot.shows(weekly), isTrue);
      note(robot);

      // Back to one day.
      await robot.tap('repeat');
      await doesNotRepeat();
      await robot.tapId(SemanticsIds.repeatDone);
      expect(robot.caption, en.calendarGuideDemoOneDay(dates.format(today)));
      note(robot);

      // Repeat again opens on the rule she had, switched off.
      await robot.tap('repeat');
      final kept = opened();
      expect(kept.recurring, isFalse);
      expect(kept.kind, RepeatKind.weekly);
      expect(kept.interval, EventRepeatDraft.maxInterval);
      expect(kept.weekdays, {1, 2, 3, 4, 5, 6, 7});
      expect(kept.endDate, today);
      expect(kept.retroactive, isTrue);
      await robot.tapId(SemanticsIds.repeatKind('weekly'));
      await robot.tapId(SemanticsIds.repeatDone);
      expect(robot.shows(weekly), isTrue);

      // Pinned to two dates, then through Daily and back in the sheet: the
      // set stays, as the editor's "does not repeat" keeps it.
      await robot.tap('repeat');
      await doesNotRepeat();
      await robot.tapId(SemanticsIds.repeatDone);
      final extra = today.day < 20 ? day(3) : day(-3);
      await robot.tap('add-date');
      await sheets.pickInDatePicker(extra);
      await robot.tapId(SemanticsIds.datePickerSave);
      expect(robot.caption, en.recurrenceSpecificDates(2));
      await robot.tap('repeat');
      expect(opened().kind, RepeatKind.weekly);
      await robot.tapId(SemanticsIds.repeatKind('daily'));
      await doesNotRepeat();
      await robot.tapId(SemanticsIds.repeatDone);
      expect(robot.caption, en.recurrenceSpecificDates(2));
      expect(robot.enabled('add-date'), isTrue);
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('Add date pins the event to the dates picked', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.kinds);
      final sheets = PracticeCalendarRobot(tester);
      note(robot);

      // A day in the picker's opening month: today's own month.
      final extra = today.day < 20 ? day(3) : day(-3);
      await robot.tap('add-date');
      expect(find.byType(CalendarDatePickerSheet), findsOneWidget);
      await sheets.pickInDatePicker(extra);
      await robot.tapId(SemanticsIds.datePickerSave);
      expect(robot.caption, en.recurrenceSpecificDates(2));
      note(robot);
      // Two days now: one of them can be skipped once picked.
      expect(robot.enabled('add-date'), isTrue);
      expectOneSlotHeight();
      await expectNothingSaved();
    });
  });

  group('attendance', () {
    String counts(int attended, int total, int current, int best) =>
        '${en.eventAdherenceSummary(attended, total, 30)}'
        ' · ${en.eventAdherenceStreak(current, best)}';

    testWidgets('idle on the seed\'s count; today\'s button and a past day '
        'change the summary and the streak', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.attendance);
      // Today and the four weeks before it; the week before last missed.
      expect(robot.caption, counts(4, 5, 1, 3));
      note(robot);
      for (var i = 0; i < 4; i++) {
        expect(robot.chip('day-$i').selected, i != 3, reason: 'day-$i');
      }

      await robot.tap('today');
      expect(robot.caption, counts(3, 5, 0, 3));
      note(robot);
      expect(
        find.descendant(
          of: robot.control('today'),
          matching: find.byTooltip(en.eventMarkPresent),
        ),
        findsOneWidget,
      );

      await robot.tap('day-3');
      expect(robot.chip('day-3').selected, isTrue);
      expect(robot.caption, counts(4, 5, 0, 4));
      note(robot);

      await robot.tap('today');
      expect(robot.caption, counts(5, 5, 5, 5));
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('the count switch enables the styles and the example '
        'follows them, the stage never changing height', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.attendance);
      final stage = robot.stageSize;
      final numbered = [1, 2, 3].map(en.eventNumberedWeeks).join(' · ');
      final elapsed = [0, 1, 2].map(en.eventElapsedWeeks).join(' · ');
      // Off: the styles stay drawn, disabled.
      expect(robot.chip('count-numbered').onTap, isNull);
      expect(robot.chip('count-elapsed').onTap, isNull);

      await robot.tap('count');
      expect(robot.chip('count-elapsed').onTap, isNotNull);
      expect(robot.stageCaption, numbered);

      await robot.tap('count-elapsed');
      expect(robot.chip('count-elapsed').selected, isTrue);
      expect(robot.stageCaption, elapsed);
      expect(robot.stageSize, stage);
      expect(pushes.pushed, isEmpty);
      await expectNothingSaved();
    });
  });

  group('categories', () {
    testWidgets('idle: three rows, an empty reserved slot, Delete disabled '
        'on a built-in', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.categories);

      expect(robot.caption, isEmpty);
      expect(robot.slotSize.height, greaterThan(0));
      for (var i = 0; i < 3; i++) {
        expect(robot.control('row-$i'), findsOneWidget, reason: 'row-$i');
      }
      expect(robot.shows(en.eventCategoryGym), isTrue);
      expect(robot.shows(en.calendarGuideDemoEventBookClub), isTrue);

      await robot.tap('more-0');
      final delete = tester.widget<PopupMenuItem<dynamic>>(
        find.ancestor(
          of: robot.control('delete'),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
      );
      expect(delete.enabled, isFalse);
      await robot.tap('delete');
      // Still open, nothing deleted.
      expect(robot.control('edit'), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(robot.control('row-0'), findsOneWidget);
      expect(robot.caption, isEmpty);
      await expectNothingSaved();
    });

    testWidgets('create, edit, hide, show and delete — in this list only', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.categories);
      final sheet = CategoryEditorRobot(tester);
      final stage = robot.stageSize;
      final gym = en.eventCategoryGym;

      await robot.tap('add');
      expect(find.byType(CategoryEditorSheet), findsOneWidget);
      await sheet.typeName('Chess');
      await sheet.save();
      expect(robot.caption, en.calendarGuideDemoCatCreated('Chess'));
      expect(robot.control('row-3'), findsOneWidget);
      note(robot);

      await robot.tap('row-2');
      await sheet.typeName('Reading');
      await sheet.save();
      expect(robot.caption, en.calendarGuideDemoChanged('Reading'));
      expect(robot.shows('Reading'), isTrue);
      note(robot);

      await robot.tap('eye-0');
      expect(robot.caption, en.calendarGuideDemoCatHidden(gym));
      note(robot);
      await robot.tap('eye-0');
      expect(robot.caption, en.calendarGuideDemoChanged(gym));
      note(robot);

      await robot.tap('more-1');
      await robot.tap('edit');
      expect(find.byType(CategoryEditorSheet), findsOneWidget);
      await sheet.save();
      expect(
        robot.caption,
        en.calendarGuideDemoChanged(en.eventCategoryCardio),
      );

      await robot.tap('more-2');
      await robot.tap('delete');
      expect(robot.control('row-3'), findsNothing);
      expect(robot.shows('Reading'), isFalse);
      expect(
        robot.caption,
        en.calendarGuideDemoCatDeleted('Reading', en.eventCategoryOther),
      );
      note(robot);
      expect(robot.stageSize, stage);
      expect(pushes.pushed, isEmpty);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('at six rows Create category is disabled, not gone', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.categories);
      final sheet = CategoryEditorRobot(tester);
      final stage = robot.stageSize;

      for (final name in ['One', 'Two', 'Three']) {
        expect(robot.enabled('add'), isTrue);
        await robot.tap('add');
        await sheet.typeName(name);
        await sheet.save();
      }
      expect(robot.enabled('add'), isFalse);
      expect(robot.stageSize, stage);
      await expectNothingSaved();
    });
  });

  group('finding', () {
    const all = ['dentist', 'yoga', 'rent', 'birthday', 'book-club', 'flight'];

    Future<void> search(
      WidgetTester tester,
      GuideTryCardRobot robot,
      String text,
    ) async {
      await tester.enterText(
        find.descendant(
          of: robot.control('search'),
          matching: find.byType(EditableText),
        ),
        text,
      );
      await tester.pumpAndSettle();
    }

    void expectListed(GuideTryCardRobot robot, Set<String> listed) {
      for (final key in all) {
        expect(
          robot.control('match-$key'),
          listed.contains(key) ? findsOneWidget : findsNothing,
          reason: key,
        );
      }
    }

    testWidgets('a title, a category\'s name and a date narrow the list, '
        'which never changes height', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.finding);
      final stage = robot.stageSize;
      expect(robot.caption, en.calendarGuideDemoMatches(6));
      expectListed(robot, all.toSet());
      note(robot);

      await search(tester, robot, 'yoga');
      expect(robot.caption, en.calendarGuideDemoMatches(1));
      expectListed(robot, {'yoga'});
      note(robot);

      // The seed takes the visible built-ins in order: Rent wears the third.
      await search(tester, robot, en.eventCategoryRest);
      expect(robot.caption, en.calendarGuideDemoMatches(1));
      expectListed(robot, {'rent'});
      note(robot);

      final flight = day(9);
      await search(tester, robot, DateFormat('d MMMM', 'en').format(flight));
      expect(robot.control('match-flight'), findsOneWidget);
      expect(robot.control('match-dentist'), findsNothing);
      note(robot);

      await search(tester, robot, 'nothing like it');
      expect(robot.caption, en.calendarGuideDemoMatches(0));
      expectListed(robot, const {});
      note(robot);
      expect(robot.stageSize, stage);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('the funnel opens the sandboxed filter sheet and its count '
        'narrows the list', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.finding);
      note(robot);

      await robot.tap('filter');
      expect(find.byType(CalendarFilterSheet), findsOneWidget);
      await robot.tapId(SemanticsIds.filterRepeat);
      await robot.tapId(SemanticsIds.filterRepeatOneTime);
      await robot.tapId(SemanticsIds.filterApply);
      expect(find.byType(CalendarFilterSheet), findsNothing);
      expect(robot.caption, en.calendarGuideDemoFiltered(1));
      expectListed(robot, {'dentist', 'flight'});
      note(robot);

      await robot.tap('filter');
      await robot.tapId(SemanticsIds.filterTime);
      await robot.tapId(SemanticsIds.filterTimeAllDay);
      await robot.tapId(SemanticsIds.filterApply);
      expect(robot.caption, en.calendarGuideDemoFiltered(2));
      expectListed(robot, {'flight'});
      expect(
        find.descendant(
          of: robot.control('filter'),
          matching: find.byIcon(Icons.filter_alt_rounded),
        ),
        findsOneWidget,
      );
      note(robot);

      // A query on top of the filters.
      await search(tester, robot, 'dentist');
      expect(robot.caption, en.calendarGuideDemoMatches(0));
      expectListed(robot, const {});
      note(robot);
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('Missed only reads the demo\'s own marks', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.finding);

      await robot.tap('filter');
      await robot.tapId(SemanticsIds.filterOnlyShow);
      await robot.tapId(SemanticsIds.filterListRow('missed'));
      await robot.tapId(SemanticsIds.filterListDone);
      await robot.tapId(SemanticsIds.filterApply);
      expect(robot.caption, en.calendarGuideDemoFiltered(1));
      // The practice Yoga's week before last is marked missed in the demo;
      // the calendar's own presence cache holds no mark of a demo id.
      expectListed(robot, {'yoga'});
      await expectNothingSaved();
    });

    testWidgets('the keyboard up over the focused field overflows nothing', (
      tester,
    ) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.finding,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(2.0),
      );
      const inset = 320.0;
      final field = find.descendant(
        of: robot.control('search'),
        matching: find.byType(EditableText),
      );
      void expectAboveKeyboard() =>
          expect(tester.getRect(field).bottom, lessThanOrEqualTo(780 - inset));
      await tester.ensureVisible(robot.control('search'));
      await tester.pumpAndSettle();
      await tester.showKeyboard(field);
      tester.view.viewInsets = const FakeViewPadding(bottom: inset);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectAboveKeyboard();
      await tester.enterText(field, 'yoga');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectAboveKeyboard();

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectNothingSaved();
    });
  });

  group('setup', () {
    final year = today.year;
    int countIn(HolidayProfile profile, int year) => HolidaySeeds.forYear(
      profile,
      year,
    ).keys.where((day) => day.year == year).length;

    testWidgets('every holiday set says its own count, the next days in a '
        'slot that never changes height', (tester) async {
      final robot = await open(tester, CalendarGuideTopic.setup);
      final stage = robot.stageSize;
      expect(
        robot.caption,
        en.calendarGuideDemoHolidays(
          countIn(HolidayProfile.generic, year),
          '$year',
        ),
      );
      final next = <String>{};
      for (final profile in HolidayProfile.values) {
        await robot.tap('holidays');
        await robot.tapId(
          SemanticsIds.calendarGuideTryControl(
            'setup',
            'holidays-${profile.name}',
          ),
        );
        expect(
          robot.caption,
          en.calendarGuideDemoHolidays(countIn(profile, year), '$year'),
          reason: profile.name,
        );
        note(robot);
        final lines = robot.stageCaption;
        expect(
          lines.isEmpty ? 0 : lines.split('\n').length,
          profile == HolidayProfile.none ? 0 : 3,
          reason: profile.name,
        );
        next.add(lines);
        expect(robot.stageSize, stage, reason: profile.name);
      }
      expect(robot.shows(en.holidayProfileNone), isTrue);
      expect(next.length, greaterThan(1));
      expectOneSlotHeight();
      await expectNothingSaved();
    });

    testWidgets('across the year\'s end a holiday is listed once', (
      tester,
    ) async {
      const us = HolidayProfile.unitedStates;
      final newYearObserved = DateTime.utc(2027, 12, 31);
      // The premise: both years' seeds hold the Saturday 1 January 2028
      // observed on 31 December 2027.
      expect(HolidaySeeds.forYear(us, 2027), contains(newYearObserved));
      expect(HolidaySeeds.forYear(us, 2028), contains(newYearObserved));

      final robot = await open(
        tester,
        CalendarGuideTopic.setup,
        now: () => DateTime(2027, 12, 26, 15),
      );
      await robot.tap('holidays');
      await robot.tapId(
        SemanticsIds.calendarGuideTryControl('setup', 'holidays-${us.name}'),
      );

      final lines = robot.stageCaption.split('\n');
      expect(lines, hasLength(3));
      final shownDates = [for (final line in lines) line.split(' · ').first];
      expect(shownDates.toSet(), hasLength(3), reason: '$lines');
      expect(shownDates.first, dates.format(newYearObserved));
      expect(
        robot.caption,
        en.calendarGuideDemoHolidays(countIn(us, 2027), '2027'),
      );
      await expectNothingSaved();
    });

    testWidgets('the year\'s count holds only its own days', (tester) async {
      const us = HolidayProfile.unitedStates;
      final own = countIn(us, 2028);
      expect(own, HolidaySeeds.forYear(us, 2028).length - 1);

      final robot = await open(
        tester,
        CalendarGuideTopic.setup,
        now: () => DateTime(2028, 6, 1, 9),
      );
      await robot.tap('holidays');
      await robot.tapId(
        SemanticsIds.calendarGuideTryControl('setup', 'holidays-${us.name}'),
      );

      expect(robot.caption, en.calendarGuideDemoHolidays(own, '2028'));
      await expectNothingSaved();
    });

    testWidgets('starts from her holiday set, read from the service', (
      tester,
    ) async {
      await (await PublicHolidayService.getInstance()).setProfile(
        HolidayProfile.romania,
        reconcile: false,
      );
      writes.statements.clear();
      revisions = staticRevisions();

      final robot = await open(tester, CalendarGuideTopic.setup);

      expect(robot.shows(en.holidayProfileRomania), isTrue);
      expect(
        robot.caption,
        en.calendarGuideDemoHolidays(
          countIn(HolidayProfile.romania, year),
          '$year',
        ),
      );
      await expectNothingSaved();
    });

    testWidgets('the first day of the week turns the sample week', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.setup);
      CalendarWeekStart shown() => tester
          .widget<CalendarAppearancePreview>(
            find.descendant(
              of: robot.card,
              matching: find.byType(CalendarAppearancePreview),
            ),
          )
          .appearance
          .weekStart;
      expect(shown(), CalendarWeekStart.monday);

      for (final start in [
        CalendarWeekStart.sunday,
        CalendarWeekStart.saturday,
        CalendarWeekStart.monday,
      ]) {
        await robot.tap('week-${start.name}');
        expect(shown(), start);
        // The strip's first day is the start's own weekday.
        final todayIndex = (today.weekday - start.weekday + 7) % 7;
        final first = day(-todayIndex);
        expect(first.weekday, start.weekday);
        expect(
          find.descendant(
            of: find.byType(CalendarAppearancePreview),
            matching: find.text('${first.day}'),
          ),
          findsWidgets,
        );
      }
      expect(pushes.pushed, isEmpty);
      await expectNothingSaved();
    });

    testWidgets('the settings row opens the real Calendar settings', (
      tester,
    ) async {
      final robot = await open(tester, CalendarGuideTopic.setup);

      await robot.tap('settings');
      expect(find.byType(CalendarSettingsPage), findsOneWidget);
      expect(pushes.pushed, hasLength(1));
      await expectNothingSaved();
    });
  });

  group('a stage never changes height at text scale 2.0', () {
    testWidgets('alerts: every alert up to the cap', (tester) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.alerts,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(2.0),
      );
      final stage = robot.stageSize;
      for (var i = 0; i < kMaxAlertsPerEvent; i++) {
        await robot.tap('add');
        await robot.tapId(SemanticsIds.alertSheetSave);
        expect(robot.control('alert-$i'), findsOneWidget);
        expect(robot.stageSize, stage, reason: '${i + 1} alerts');
      }
      expect(robot.enabled('add'), isFalse);
      await robot.tap('alert-0');
      await robot.tapId(SemanticsIds.alertRemove);
      expect(robot.stageSize, stage);
      expect(tester.takeException(), isNull);
      await expectNothingSaved();
    });

    testWidgets('kinds: a picked day and the longest rule', (tester) async {
      final robot = await open(
        tester,
        CalendarGuideTopic.kinds,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(2.0),
      );
      final de = AppLocalizationsDe();
      final stage = robot.stageSize;
      await robot.tap('day');
      await PracticeCalendarRobot(tester).pickInDatePicker(today);
      expect(robot.stageSize, stage, reason: 'a picked day');
      await robot.tap('repeat');
      await _longestWeeklyRule(tester, de);
      await robot.tapId(SemanticsIds.repeatDone);
      expect(
        robot.shows(
          RecurrenceFormatter.format(
            const WeeklyRecurrence(
              weekdays: {1, 2, 3, 4, 5, 6, 7},
              interval: EventRepeatDraft.maxInterval,
            ),
            de,
            'de',
            retroactive: true,
          ),
        ),
        isTrue,
      );
      expect(robot.stageSize, stage, reason: 'the longest rule');
      expect(tester.takeException(), isNull);
      await expectNothingSaved();
    });
  });

  group('the stage\'s controls are nodes of their own under the entry', () {
    for (final (topic, controls) in const [
      (
        CalendarGuideTopic.events,
        ['row-dentist', 'row-yoga', 'row-rent', 'add'],
      ),
      (CalendarGuideTopic.kinds, ['repeat', 'add-date', 'day', 'skip']),
      (
        CalendarGuideTopic.alerts,
        ['alert-0', 'add', 'show-alarm', 'quick', 'permissions'],
      ),
      (CalendarGuideTopic.attendance, ['today', 'day-0', 'count']),
      (CalendarGuideTopic.categories, ['row-0', 'eye-0', 'more-0', 'add']),
      (CalendarGuideTopic.finding, ['search', 'match-yoga', 'filter']),
      (CalendarGuideTopic.setup, ['holidays', 'week-sunday', 'settings']),
    ]) {
      testWidgets(topic.slug, (tester) async {
        final handle = tester.ensureSemantics();
        final robot = await open(tester, topic);
        // An empty caption is left out of the tree: give the categories
        // and the alerts cards one to say first — the alerts card's an
        // alert row too.
        if (topic == CalendarGuideTopic.categories) await robot.tap('eye-1');
        if (topic == CalendarGuideTopic.alerts) {
          await robot.tap('add');
          await robot.tapId(SemanticsIds.alertSheetSave);
        }

        final entry = tester.getSemantics(robot.card);
        bool under(SemanticsNode node) {
          for (var p = node.parent; p != null; p = p.parent) {
            if (p.id == entry.id) return true;
          }
          return false;
        }

        final ids = <int>{entry.id};
        for (final name in [
          for (final control in controls)
            SemanticsIds.calendarGuideTryControl(topic.slug, control),
          SemanticsIds.calendarGuideTryCaption(topic.slug),
        ]) {
          final node = tester.getSemantics(find.bySemanticsIdentifier(name));
          expect(under(node), isTrue, reason: name);
          expect(ids.add(node.id), isTrue, reason: '$name shares a node');
        }
        expect(
          entry.getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse,
        );
        handle.dispose();
      });
    }
  });

  group('no overflow and no clipped label at text scale 2.0', () {
    for (final topic in const [
      CalendarGuideTopic.screen,
      CalendarGuideTopic.events,
      CalendarGuideTopic.kinds,
      CalendarGuideTopic.alerts,
      CalendarGuideTopic.attendance,
      CalendarGuideTopic.categories,
      CalendarGuideTopic.finding,
      CalendarGuideTopic.setup,
    ]) {
      for (final locale in const [Locale('de'), Locale('ro')]) {
        for (final size in const [Size(360, 780), Size(412, 915)]) {
          for (final brightness in Brightness.values) {
            testWidgets('${topic.slug} ${locale.languageCode} '
                '${size.width.toInt()}×${size.height.toInt()} '
                '${brightness.name}', (tester) async {
              final robot = await open(
                tester,
                topic,
                locale: locale,
                brightness: brightness,
                textScaler: const TextScaler.linear(2.0),
                size: size,
              );
              expect(tester.takeException(), isNull);
              Future<void> expectClean(String state) async {
                await tester.ensureVisible(
                  find
                      .descendant(
                        of: robot.card,
                        matching: find.byType(RepaintBoundary),
                      )
                      .first,
                );
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull, reason: state);
                final paragraphs = tester.renderObjectList<RenderParagraph>(
                  find.descendant(
                    of: robot.card,
                    matching: find.byType(RichText),
                  ),
                );
                // The unseen copies that size a slot are not drawn: a
                // stand-in cut at its row's limit is not a clipped label.
                bool unseen(RenderObject paragraph) {
                  for (RenderObject? o = paragraph; o != null; o = o.parent) {
                    if (o is RenderOpacity && o.opacity == 0) return true;
                  }
                  return false;
                }

                for (final paragraph in paragraphs) {
                  if (unseen(paragraph)) continue;
                  expect(
                    paragraph.didExceedMaxLines,
                    isFalse,
                    reason: '$state: ${paragraph.text.toPlainText()}',
                  );
                }
              }

              await expectClean('idle');
              // One changed state: what she does first on the card.
              await _changeOnce(tester, robot, topic);
              await expectClean('changed');
              await expectNothingSaved();
            });
          }
        }
      }
    }
  });
}

/// The first thing she would do on [topic]'s card: a mode, an added event,
/// a rule, an alert, a mark, a category, a query, a holiday set.
Future<void> _changeOnce(
  WidgetTester tester,
  GuideTryCardRobot robot,
  CalendarGuideTopic topic,
) async {
  switch (topic) {
    case CalendarGuideTopic.screen:
      await robot.tapId(SemanticsIds.panelMode('timeline'));
    case CalendarGuideTopic.events:
      final sheets = PracticeCalendarRobot(tester);
      await robot.tap('add');
      await sheets.typeTitle('Swim');
      await sheets.saveEditor();
    case CalendarGuideTopic.kinds:
      await robot.tap('repeat');
      await robot.tapId(SemanticsIds.repeatKind('weekly'));
      await robot.tapId(SemanticsIds.repeatDone);
    case CalendarGuideTopic.alerts:
      await robot.tap('add');
      await robot.tapId(SemanticsIds.alertSheetSave);
    case CalendarGuideTopic.attendance:
      await robot.tap('today');
    case CalendarGuideTopic.categories:
      final sheet = CategoryEditorRobot(tester);
      await robot.tap('add');
      await sheet.typeName('Chess');
      await sheet.save();
    case CalendarGuideTopic.finding:
      await tester.enterText(
        find.descendant(
          of: robot.control('search'),
          matching: find.byType(EditableText),
        ),
        'yoga',
      );
      await tester.pumpAndSettle();
    case CalendarGuideTopic.setup:
      await robot.tap('holidays');
      await robot.tapId(
        SemanticsIds.calendarGuideTryControl(
          'setup',
          'holidays-${HolidayProfile.unitedKingdom.name}',
        ),
      );
    default:
      fail('$topic has no card');
  }
  expect(robot.caption, isNotEmpty, reason: topic.slug);
}

/// Taps [target] in the open sheet, scrolled into view first.
Future<void> _tapIn(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// The open repeat sheet's live controls: the last of each, after the
/// unseen copy that sizes its area.
Finder _inRepeatSheet(Finder matching) =>
    find.descendant(of: find.byType(EventRepeatSheet), matching: matching).last;

/// Turns the open repeat sheet to the longest rule its words can say:
/// weekly, on every weekday, every 99 weeks, also before the start — and,
/// with [endOn], ending that day.
Future<void> _longestWeeklyRule(
  WidgetTester tester,
  AppLocalizations l10n, {
  DateTime? endOn,
}) async {
  await _tapIn(
    tester,
    find.bySemanticsIdentifier(SemanticsIds.repeatKind('weekly')),
  );
  final names = DateFormat.EEEE(l10n.localeName);
  for (var weekday = 1; weekday <= 7; weekday++) {
    final name = names.format(DateTime(2024, 1, weekday));
    final cell = _inRepeatSheet(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == name,
      ),
    );
    if (tester.widget<Semantics>(cell).properties.selected ?? false) continue;
    await _tapIn(tester, cell);
  }
  final more = _inRepeatSheet(find.byTooltip(l10n.recurrenceIntervalIncrement));
  await tester.ensureVisible(more);
  await tester.pumpAndSettle();
  for (var i = 1; i < EventRepeatDraft.maxInterval; i++) {
    await tester.tap(more);
    await tester.pump();
  }
  await tester.pumpAndSettle();
  if (endOn != null) {
    await _tapIn(tester, _inRepeatSheet(find.text(l10n.never)));
    await PracticeCalendarRobot(tester).pickInDatePicker(endOn);
  }
  await _tapIn(tester, _inRepeatSheet(find.byType(Switch)));
}
