import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/services/day_summary_resolver.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/quick_alarm.dart';
import 'package:anta/widgets/alert_type_row.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/quick_alarm_sheet.dart';
import 'package:anta/widgets/time_pad_sheet.dart';
import 'package:anta/widgets/value_change_highlight.dart';

import '../database/support/db_test_support.dart';
import 'support/quick_alarm_robot.dart';

/// The sheet is a form over `quick_alarm.dart`'s arithmetic, so what is worth
/// pinning is the round trip: what it opens on, what each preset does, and
/// what Save reports.
void main() {
  /// 10:03:40 on a Wednesday: not on a quarter hour, so the default and the
  /// presets all have something to round.
  final now = DateTime(2026, 9, 23, 10, 3, 40);
  final today = DateTime.utc(2026, 9, 23);

  late AppDatabase db;

  setUp(() async {
    SettingsService.reset();
    db = await openTestDatabase();
    SettingsService.forTesting(db);
  });

  tearDown(() async {
    SettingsService.reset();
    await db.close();
  });

  /// [surface], [locale], [textScale], [use24HourFormat] and [theme] dress
  /// the device for the layout cases; left alone, the app is the bare one
  /// every round-trip case has always opened the sheet from.
  Future<_Result> openSheet(
    WidgetTester tester, {
    DateTime? day,
    DateTime? at,
    Size? surface,
    Locale locale = const Locale('en'),
    double? textScale,
    bool use24HourFormat = false,
    ThemeData? theme,
  }) async {
    if (surface != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
    }
    final result = _Result();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        theme: theme,
        builder: textScale == null && !use24HourFormat
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale ?? 1.0),
                  alwaysUse24HourFormat: use24HourFormat,
                ),
                child: child!,
              ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result.value = await QuickAlarmSheet.show(
                  context,
                  day: day ?? today,
                  now: () => at ?? now,
                );
                result.closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('opens on the next quarter hour, today, as an alarm', (
    tester,
  ) async {
    final sheet = QuickAlarmRobot(tester);
    final result = await openSheet(tester);

    expect(sheet.timeLabel, contains('10:15'));
    expect(sheet.dayLabel, 'Today');
    expect(sheet.name, 'Alarm');
    expect(sheet.currentTier, AlertMode.ring);
    expect(sheet.removeAfterValue, isTrue);

    await sheet.save();

    expect(
      result.value,
      QuickAlarmDraft(
        day: DateTime.utc(2026, 9, 23),
        startMinute: 10 * 60 + 15,
        name: 'Alarm',
      ),
    );
  });

  testWidgets('the presets move the time — rounded up, and tonight at 21:00', (
    tester,
  ) async {
    final sheet = QuickAlarmRobot(tester);
    final result = await openSheet(tester);

    await sheet.choosePreset(QuickAlarmPreset.in20Minutes);
    expect(sheet.timeLabel, contains('10:24'));

    await sheet.choosePreset(QuickAlarmPreset.in1Hour);
    expect(sheet.timeLabel, contains('11:04'));

    await sheet.choosePreset(QuickAlarmPreset.tonight);
    await sheet.save();

    expect(result.value?.startMinute, kQuickAlarmTonightMinute);
    expect(result.value?.day, today);
  });

  testWidgets('tonight is disabled once 21:00 has passed', (tester) async {
    final sheet = QuickAlarmRobot(tester);
    await openSheet(tester, at: DateTime(2026, 9, 23, 21, 30));

    expect(sheet.isPresetEnabled(QuickAlarmPreset.tonight), isFalse);
  });

  testWidgets('a preset that crosses midnight lands on tomorrow', (
    tester,
  ) async {
    final sheet = QuickAlarmRobot(tester);
    final result = await openSheet(tester, at: DateTime(2026, 9, 23, 23, 50));

    expect(sheet.dayLabel, 'Tomorrow', reason: 'the default too');
    await sheet.choosePreset(QuickAlarmPreset.in1Hour);
    await sheet.save();

    expect(result.value?.day, DateTime.utc(2026, 9, 24));
    expect(result.value?.startMinute, 50);
  });

  testWidgets('a time picked by hand is on the opened day, not the preset\'s', (
    tester,
  ) async {
    // 23:50: the default and every preset land on tomorrow, and a time
    // picked by hand that is still ahead tonight must stay tonight.
    final sheet = QuickAlarmRobot(tester);
    final result = await openSheet(tester, at: DateTime(2026, 9, 23, 23, 50));
    await sheet.choosePreset(QuickAlarmPreset.in1Hour);
    expect(sheet.dayLabel, 'Tomorrow');

    await sheet.pickTime(const TimeOfDay(hour: 23, minute: 58));

    expect(sheet.dayLabel, 'Today');
    await sheet.save();

    expect(result.value?.day, DateTime.utc(2026, 9, 23));
    expect(result.value?.startMinute, 23 * 60 + 58);
  });

  testWidgets('a day still ahead keeps the day it was opened for', (
    tester,
  ) async {
    final sheet = QuickAlarmRobot(tester);
    final result = await openSheet(tester, day: DateTime.utc(2026, 9, 30));

    expect(sheet.dayLabel, isNot('Today'));
    await sheet.save();

    expect(result.value?.day, DateTime.utc(2026, 9, 30));
    expect(result.value?.startMinute, 10 * 60 + 15);
  });

  testWidgets('the reminder tier dims the switch in place and never removes', (
    tester,
  ) async {
    final sheet = QuickAlarmRobot(tester);
    final result = await openSheet(tester);

    await sheet.chooseTier(AlertMode.notify);
    expect(sheet.removeAfterVisible, isTrue);
    expect(sheet.removeAfterEnabled, isFalse);
    expect(sheet.removeAfterValue, isFalse);

    await sheet.save();

    expect(result.value?.mode, AlertMode.notify);
    expect(result.value?.removeAfterAlert, isFalse);
  });

  testWidgets('the switch off is reported, and back on again', (
    tester,
  ) async {
    final sheet = QuickAlarmRobot(tester);
    var result = await openSheet(tester);

    await sheet.toggleRemoveAfter();
    expect(sheet.removeAfterValue, isFalse);
    await sheet.save();

    expect(result.value?.removeAfterAlert, isFalse);

    result = await openSheet(tester);
    await sheet.toggleRemoveAfter();
    expect(sheet.removeAfterValue, isFalse);
    await sheet.toggleRemoveAfter();
    expect(sheet.removeAfterValue, isTrue);
    await sheet.save();

    expect(result.value?.removeAfterAlert, isTrue);
  });

  testWidgets('a typed name is the title; an emptied one falls back', (
    tester,
  ) async {
    final sheet = QuickAlarmRobot(tester);
    var result = await openSheet(tester);
    await sheet.enterName('  Dentist  ');
    await sheet.save();
    expect(result.value?.name, 'Dentist');

    result = await openSheet(tester);
    await sheet.enterName('   ');
    await sheet.save();
    expect(result.value?.name, 'Alarm');
  });

  testWidgets('the big time opens the time pad, and cancel keeps the time', (
    tester,
  ) async {
    final sheet = QuickAlarmRobot(tester);
    final result = await openSheet(tester);

    await sheet.openTimePad();
    expect(sheet.timePadOpen, isTrue);
    expect(sheet.dayLabel, 'Today');

    await sheet.cancelTimePad();
    expect(sheet.timePadOpen, isFalse);
    await sheet.save();

    expect(result.value?.startMinute, 10 * 60 + 15);
  });

  testWidgets('close reports nothing', (tester) async {
    final sheet = QuickAlarmRobot(tester);
    final result = await openSheet(tester);

    await sheet.close();

    expect(result.closed, isTrue);
    expect(result.value, isNull);
  });

  const phone = Size(360, 780);
  const notifyHint =
      'Sits in the shade with Snooze and Done. Silent mode and Focus apply.';
  const ringHint = 'Plays on the alarm stream until you stop or snooze it.';

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  Finder inSheet(Finder matching) =>
      find.descendant(of: find.byType(QuickAlarmSheet), matching: matching);

  double sheetHeight(WidgetTester tester) =>
      tester.getSize(find.byType(QuickAlarmSheet)).height;

  SemanticsData dataOf(WidgetTester tester, String id) =>
      tester.getSemantics(byId(id)).getSemanticsData();

  List<FormRowGroup> groupsOf(WidgetTester tester) => tester
      .widgetList<FormRowGroup>(inSheet(find.byType(FormRowGroup)))
      .toList();

  /// A chip of the sheet by the id it was built with.
  Finder chip(String id) => inSheet(
    find.byWidgetPredicate(
      (widget) => widget is FormChip && widget.identifier == id,
    ),
  );

  Finder slot() => inSheet(find.byType(FormCaptionSlot));

  /// The copy of [text] a finger can reach: the caption slot also lays out
  /// every line it may say, unseen, to hold its height.
  Finder shown(String text) => find.text(text).hitTestable();

  group('chrome and ways out', () {
    testWidgets('the header is a close, the title and a text Save on the save '
        'id, enabled whatever the name', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      await openSheet(tester);

      expect(inSheet(find.byType(FormSheetHandle)), findsOneWidget);
      final header = tester.widget<FormSheetHeader>(
        inSheet(find.byType(FormSheetHeader)),
      );
      expect(header.title, 'Quick alarm');
      expect(header.leadingIcon, Icons.close_rounded);
      expect(header.leadingIdentifier, SemanticsIds.quickAlarmClose);
      expect(dataOf(tester, SemanticsIds.quickAlarmClose).tooltip, 'Cancel');
      FormHeaderTextButton save() => tester.widget<FormHeaderTextButton>(
        inSheet(find.byType(FormHeaderTextButton)),
      );
      expect(save().label, 'Save');
      expect(save().identifier, SemanticsIds.quickAlarmSave);
      expect(save().onPressed, isNotNull);
      // The filled Save is the event editor's alone.
      expect(inSheet(find.byType(FilledButton)), findsNothing);

      // An emptied name falls back at Save, so there is nothing to wait for.
      await sheet.enterName('');
      await tester.pump();
      expect(save().onPressed, isNotNull);
    });

    final waysOut = <String, Future<void> Function(WidgetTester tester)>{
      'the ✕': (tester) => QuickAlarmRobot(tester).close(),
      'the barrier': (tester) => tester.tapAt(const Offset(10, 10)),
      'the system back': (tester) => tester.binding.handlePopRoute(),
      'a fling on the handle': (tester) => tester.fling(
        find.byType(FormSheetHandle),
        const Offset(0, 400),
        2000,
      ),
    };
    for (final way in waysOut.entries) {
      testWidgets('${way.key} reports nothing, a typed name and a picked '
          'preset included', (tester) async {
        final sheet = QuickAlarmRobot(tester);
        final result = await openSheet(tester);

        await sheet.choosePreset(QuickAlarmPreset.in1Hour);
        await sheet.enterName('Dentist');
        await way.value(tester);
        await tester.pumpAndSettle();

        expect(result.closed, isTrue);
        expect(result.value, isNull);
        expect(find.byType(QuickAlarmSheet), findsNothing);
      });
    }

    testWidgets('Save reports the time, the day, the name and the tier the '
        'sheet shows', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      final result = await openSheet(tester);

      await sheet.pickTime(const TimeOfDay(hour: 18, minute: 30));
      await sheet.enterName('Dentist');
      await sheet.chooseTier(AlertMode.notify);
      await sheet.save();

      expect(result.closed, isTrue);
      expect(
        result.value,
        QuickAlarmDraft(
          day: today,
          startMinute: 18 * 60 + 30,
          name: 'Dentist',
          mode: AlertMode.notify,
          removeAfterAlert: false,
        ),
      );
    });

    final themes = <String, ThemeData Function()>{
      'light': AppTheme.light,
      'dark': AppTheme.dark,
    };
    for (final theme in themes.entries) {
      testWidgets('in ${theme.key} the sheet is three groups on the page '
          'ground, with nothing of the older chrome left', (tester) async {
        await openSheet(tester, theme: theme.value());
        final colorScheme = Theme.of(
          tester.element(find.byType(QuickAlarmSheet)),
        ).colorScheme;

        expect(
          tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
          colorScheme.pageGround,
        );
        // The time and its presets, the name, the tier and what it governs.
        final groups = groupsOf(tester);
        expect([for (final group in groups) group.children.length], [2, 1, 2]);
        expect(
          [for (final group in groups) group.trailingGap],
          [true, true, false],
        );
        for (final group in groups) {
          final ground = tester.widget<Material>(
            find
                .descendant(
                  of: find.byWidget(group),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(ground.color, colorScheme.rowGroup);
          expect(ground.elevation, 0);
        }
        for (final gone in [
          Card,
          ListTile,
          SwitchListTile,
          ChoiceChip,
          SegmentedButton<AlertMode>,
        ]) {
          expect(inSheet(find.byType(gone)), findsNothing, reason: '$gone');
        }
      });
    }
  });

  group('the time', () {
    testWidgets('the time row is one button node reading the time and the '
        'day, with what a tap does as its hint', (tester) async {
      await openSheet(tester);

      final data = dataOf(tester, SemanticsIds.quickAlarmTime);
      expect(data.identifier, SemanticsIds.quickAlarmTime);
      expect(data.label, '10:15 AM, Today');
      expect(data.hint, 'Change time');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      // Both texts are drawn, and belong to the row's node rather than to
      // nodes of their own.
      expect(inSheet(find.text('10:15 AM')), findsOneWidget);
      expect(inSheet(find.text('Today')), findsOneWidget);
      expect(find.semantics.byLabel('10:15 AM'), findsNothing);
      expect(find.semantics.byLabel('Today'), findsNothing);
    });

    testWidgets('a tap on the time row opens the pad with the arguments it '
        'has always had', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      await openSheet(tester);

      await sheet.openTimePad();

      final pad = tester.widget<TimePadSheet>(find.byType(TimePadSheet));
      expect(pad.title, 'Alarm time');
      expect(pad.initialMinute, 10 * 60 + 15);
      // The clock the sheet reads decides which half of the day a bare hour
      // means.
      expect(pad.periodAfter, 10 * 60 + 3);
      // The pad previews the day a typed time lands on: at 10:03, 09:00 is
      // gone for today and 11:00 is still ahead.
      String format(int minute) => '$minute';
      expect(pad.caption!(9 * 60, format), 'Tomorrow');
      expect(pad.caption!(11 * 60, format), 'Today');
    });

    testWidgets('the time stays on one line at text scale 2.0 on a 360 dp '
        'phone', (tester) async {
      await openSheet(tester, surface: phone, textScale: 2.0);

      expect(tester.takeException(), isNull);
      final value = inSheet(find.text('10:15 AM'));
      expect(tester.widget<Text>(value).maxLines, 1);
      expect(tester.widget<Text>(value).softWrap, isFalse);
      // Laid out at its full size on one 92 px line, then fitted into the
      // row: the painted box ends before the chevron.
      expect(
        tester.getSize(value).height,
        moreOrLessEquals(FormMetrics.heroValueLineHeight * 2.0, epsilon: 0.01),
      );
      final chevron = tester.getRect(
        find.descendant(
          of: inSheet(find.byType(FormHeroRow)),
          matching: find.byType(FormChevron),
        ),
      );
      expect(
        tester.getRect(value).right,
        lessThanOrEqualTo(chevron.left - FormMetrics.gap + 0.01),
      );
      // Fitted, not cut. The whole string is laid out on that line as wide
      // as it runs — a value clipped or ellipsized to the row would be
      // narrower than its own text — and what is drawn is that box scaled
      // down as one, by the same factor both ways.
      final paragraph = tester.renderObject<RenderParagraph>(value);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
        paragraph.size.width,
        moreOrLessEquals(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          epsilon: 0.01,
        ),
      );
      final painted = tester.getRect(value);
      final scale = painted.width / paragraph.size.width;
      expect(scale, lessThan(1));
      expect(
        painted.height / paragraph.size.height,
        moreOrLessEquals(scale, epsilon: 0.001),
      );
    });

    testWidgets('a longer time moves nothing: at text scale 2.0 on a 360 dp '
        'phone, 9:30 AM becoming 10:20 AM leaves the presets under the '
        'finger', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      await openSheet(
        tester,
        at: DateTime(2026, 9, 23, 9, 20),
        surface: phone,
        textScale: 2.0,
      );
      expect(sheet.timeLabel, '9:30 AM');

      const presets = [
        SemanticsIds.quickAlarmPreset20,
        SemanticsIds.quickAlarmPreset60,
        SemanticsIds.quickAlarmPresetTonight,
      ];
      List<Rect> presetRects() => [
        for (final id in presets) tester.getRect(byId(id)),
      ];
      Size timeRowSize() => tester.getSize(inSheet(find.byType(FormHeroRow)));
      // Both times are wider than the row at this scale and so both are
      // fitted, each by its own factor: the case in which the row used to
      // follow the string.
      double fit(String time) {
        final value = inSheet(find.text(time));
        return tester.getRect(value).width / tester.getSize(value).width;
      }

      final shortFit = fit('9:30 AM');
      expect(shortFit, lessThan(1));
      final rects = presetRects();
      final timeRow = timeRowSize();
      final height = sheetHeight(tester);

      // Tapped where it stands. The robot brings a control to the top of the
      // body before it taps, and a rect compared across that scroll would
      // say nothing about the row above it.
      await tester.tap(byId(SemanticsIds.quickAlarmPreset60));
      await tester.pumpAndSettle();

      expect(sheet.timeLabel, '10:20 AM');
      expect(fit('10:20 AM'), lessThan(shortFit));
      expect(presetRects(), rects);
      expect(timeRowSize(), timeRow);
      expect(sheetHeight(tester), height);
    });

    testWidgets('the time row flashes on a new minute and leaves its hairline '
        'at the group\'s edge', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      await openSheet(tester);

      ValueChangeHighlight highlight() => tester.widget(
        find.ancestor(
          of: inSheet(find.byType(FormHeroRow)),
          matching: find.byType(ValueChangeHighlight),
        ),
      );
      expect(highlight().value, 10 * 60 + 15);
      await sheet.choosePreset(QuickAlarmPreset.in20Minutes);
      expect(highlight().value, 10 * 60 + 24);

      // The highlight stands between the group and the row; the wrapper
      // around the pair is what still tells the group where the hairline
      // starts.
      final group = groupsOf(tester).first;
      expect(
        FormRowGroup.indentOf(group.children.first),
        FormMetrics.dividerIndentPlain,
      );
      expect(
        tester
            .widget<Divider>(
              find.descendant(
                of: find.byWidget(group),
                matching: find.byType(Divider),
              ),
            )
            .indent,
        FormMetrics.dividerIndentPlain,
      );
    });

    testWidgets('the time row\'s flash takes the group\'s radius, so the '
        'group\'s clip does not shave its top corners', (tester) async {
      await openSheet(tester);

      final highlight = tester.widget<ValueChangeHighlight>(
        find.ancestor(
          of: inSheet(find.byType(FormHeroRow)),
          matching: find.byType(ValueChangeHighlight),
        ),
      );
      expect(
        highlight.borderRadius,
        const BorderRadius.all(Radius.circular(RowMetrics.groupRadius)),
      );
      // The row is the first of its group, flush with the corners the group
      // rounds and clips.
      expect(
        tester.getRect(inSheet(find.byType(FormHeroRow))).topLeft,
        tester.getRect(find.byWidget(groupsOf(tester).first)).topLeft,
      );
    });

    testWidgets('on a 24-hour phone the time and the Tonight chip read '
        '24-hour', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      await openSheet(tester, use24HourFormat: true);

      expect(sheet.timeLabel, '10:15');
      expect(
        tester
            .widget<FormChip>(chip(SemanticsIds.quickAlarmPresetTonight))
            .label,
        'Tonight 21:00',
      );
    });
  });

  group('the presets', () {
    const ids = [
      SemanticsIds.quickAlarmPreset20,
      SemanticsIds.quickAlarmPreset60,
      SemanticsIds.quickAlarmPresetTonight,
    ];

    testWidgets('three chips on their ids in a row of their own, none '
        'selected until one is picked', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      await openSheet(tester);

      final row = tester.widget<FormChipRow>(
        find.ancestor(of: chip(ids.first), matching: find.byType(FormChipRow)),
      );
      expect(row.indented, isFalse);
      expect(row.label, isNull);
      final chips = row.chips.cast<FormChip>();
      expect([for (final chip in chips) chip.identifier], ids);
      expect(
        [for (final chip in chips) chip.label],
        ['In 20 min', 'In 1 hour', 'Tonight 9:00 PM'],
      );
      expect(sheet.selectedPreset, isNull);
      for (final id in ids) {
        expect(
          dataOf(tester, id).flagsCollection.isSelected,
          Tristate.isFalse,
          reason: id,
        );
      }

      await sheet.choosePreset(QuickAlarmPreset.in20Minutes);
      expect(sheet.selectedPreset, QuickAlarmPreset.in20Minutes);
      expect(
        dataOf(tester, ids.first).flagsCollection.isSelected,
        Tristate.isTrue,
      );

      await sheet.choosePreset(QuickAlarmPreset.in1Hour);
      expect(sheet.selectedPreset, QuickAlarmPreset.in1Hour);
      expect(
        dataOf(tester, ids.first).flagsCollection.isSelected,
        Tristate.isFalse,
      );

      // A time picked by hand is no preset's.
      await sheet.pickTime(const TimeOfDay(hour: 11, minute: 30));
      expect(sheet.selectedPreset, isNull);
    });

    testWidgets('once 21:00 has passed Tonight is disabled in place: dimmed, '
        'inert and announced disabled, the chips beside it where they were', (
      tester,
    ) async {
      final sheet = QuickAlarmRobot(tester);
      await openSheet(tester, at: DateTime(2026, 9, 23, 20, 30));
      expect(sheet.isPresetEnabled(QuickAlarmPreset.tonight), isTrue);
      expect(dataOf(tester, ids.last).hasAction(SemanticsAction.tap), isTrue);
      final rects = [for (final id in ids) tester.getRect(byId(id))];
      final height = sheetHeight(tester);
      await sheet.close();

      await openSheet(tester, at: DateTime(2026, 9, 23, 21, 30));
      expect([for (final id in ids) tester.getRect(byId(id))], rects);
      expect(sheetHeight(tester), height);
      final data = dataOf(tester, ids.last);
      expect(data.label, 'Tonight 9:00 PM');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      final opacity = tester.widget<Opacity>(
        find.descendant(of: chip(ids.last), matching: find.byType(Opacity)),
      );
      expect(opacity.opacity, FormMetrics.disabledOpacity);

      final time = sheet.timeLabel;
      await tester.tap(byId(ids.last), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(sheet.timeLabel, time);
      expect(sheet.selectedPreset, isNull);

      // The chips either side still work.
      await sheet.choosePreset(QuickAlarmPreset.in1Hour);
      expect(sheet.selectedPreset, QuickAlarmPreset.in1Hour);
    });
  });

  group('the name', () {
    testWidgets('a title row on its id, wearing what the event Save makes '
        'will wear', (tester) async {
      await openSheet(tester);

      final row = tester.widget<FormTitleRow>(
        inSheet(find.byType(FormTitleRow)),
      );
      expect(row.hint, 'Title');
      expect(row.identifier, SemanticsIds.quickAlarmName);
      final event = buildQuickAlarmEvent(
        QuickAlarmDraft(day: today, startMinute: 0, name: 'Alarm'),
        id: 'q',
      );
      final avatar = tester.widget<EventAvatar>(
        inSheet(find.byType(EventAvatar)),
      );
      expect(avatar.icon, CalendarCategories.iconFor(event));
      expect(avatar.icon, Icons.alarm_rounded);
      expect(
        avatar.color,
        EventSummaryProvider.colorFor(
          event,
          CalendarCategories.resolve(event.categoryId),
        ),
      );
      // The id is on the field's own node, the one a device script types
      // into.
      final data = dataOf(tester, SemanticsIds.quickAlarmName);
      expect(data.flagsCollection.isTextField, isTrue);
      expect(data.value, 'Alarm');
    });

    testWidgets('seeded once: a typed name survives a change of what the '
        'sheet depends on', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      await openSheet(tester, surface: phone);
      await sheet.enterName('Dentist');

      // The keyboard coming up is such a change.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      expect(sheet.name, 'Dentist');
    });

    testWidgets('the name takes the editor\'s limit: a counter from 100 '
        'characters, the error colour and a stop at 120', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      final result = await openSheet(tester);
      final colorScheme = Theme.of(
        tester.element(find.byType(QuickAlarmSheet)),
      ).colorScheme;

      await sheet.enterName('a' * 99);
      await tester.pump();
      expect(inSheet(find.text('99/120')), findsNothing);

      await sheet.enterName('a' * 100);
      await tester.pump();
      expect(
        tester.widget<Text>(inSheet(find.text('100/120'))).style!.color,
        colorScheme.onSurfaceVariant,
      );

      // Past the limit the field takes no more.
      await sheet.enterName('a' * 150);
      await tester.pump();
      expect(sheet.name, 'a' * 120);
      expect(
        tester.widget<Text>(inSheet(find.text('120/120'))).style!.color,
        colorScheme.error,
      );

      await sheet.save();
      expect(result.value?.name, 'a' * 120);
    });

    testWidgets('a tap in the title row beside its text — its bottom-left '
        'area, under the avatar — focuses the name', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      await openSheet(tester);
      expect(sheet.nameFocused, isFalse);

      final row = tester.getRect(inSheet(find.byType(FormTitleRow)));
      final field = tester.getRect(inSheet(find.byType(TextField)));
      final point = Offset(row.left + 8, row.bottom - 4);
      expect(field.contains(point), isFalse);
      await tester.tapAt(point);
      await tester.pumpAndSettle();

      expect(sheet.nameFocused, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('the name is named by its hint for a screen reader, seeded, '
        'emptied and typed', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      await openSheet(tester);
      final seeded = dataOf(tester, SemanticsIds.quickAlarmName);
      expect(seeded.label, 'Title');
      expect(seeded.value, 'Alarm');

      await sheet.enterName('');
      await tester.pumpAndSettle();
      expect(dataOf(tester, SemanticsIds.quickAlarmName).label, 'Title');

      await sheet.enterName('Dentist');
      await tester.pumpAndSettle();
      final typed = dataOf(tester, SemanticsIds.quickAlarmName);
      expect(typed.label, 'Title');
      expect(typed.value, 'Dentist');
    });

    testWidgets('focus is dropped before the time pad opens, so the keyboard '
        'does not come back when the pad closes', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      final result = await openSheet(tester);

      await sheet.focusName();
      await sheet.enterName('Dentist');
      expect(sheet.nameFocused, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      await sheet.openTimePad();
      expect(sheet.timePadOpen, isTrue);
      expect(sheet.nameFocused, isFalse);

      await sheet.cancelTimePad();
      expect(sheet.nameFocused, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);

      // The same after a pick, with the typed name where it was.
      await sheet.focusName();
      expect(sheet.nameFocused, isTrue);
      await sheet.pickTime(const TimeOfDay(hour: 11, minute: 30));
      expect(sheet.nameFocused, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(sheet.name, 'Dentist');

      await sheet.save();
      expect(result.value?.name, 'Dentist');
      expect(result.value?.startMinute, 11 * 60 + 30);
    });
  });

  group('the tier', () {
    testWidgets('Reminder comes before Alarm, each chip on its id, and the '
        'sheet opens on Alarm', (tester) async {
      await openSheet(tester);

      final chips = tester
          .widgetList<FormChip>(
            find.descendant(
              of: inSheet(find.byType(AlertTypeRow)),
              matching: find.byType(FormChip),
            ),
          )
          .toList();
      expect([for (final chip in chips) chip.label], ['Reminder', 'Alarm']);
      expect(
        [for (final chip in chips) chip.identifier],
        [SemanticsIds.quickAlarmTypeReminder, SemanticsIds.quickAlarmTypeAlarm],
      );
      expect([for (final chip in chips) chip.selected], [isFalse, isTrue]);
      expect(
        dataOf(
          tester,
          SemanticsIds.quickAlarmTypeReminder,
        ).flagsCollection.isSelected,
        Tristate.isFalse,
      );
      expect(
        dataOf(
          tester,
          SemanticsIds.quickAlarmTypeAlarm,
        ).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        tester.getRect(byId(SemanticsIds.quickAlarmTypeReminder)).right,
        lessThanOrEqualTo(
          tester.getRect(byId(SemanticsIds.quickAlarmTypeAlarm)).left,
        ),
      );
    });

    testWidgets('on the Reminder tier the remove switch stays in place, '
        'dimmed, inert and announced disabled', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      await openSheet(tester);
      const id = SemanticsIds.quickAlarmRemoveAfter;
      final rect = tester.getRect(byId(id));
      expect(dataOf(tester, id).hasAction(SemanticsAction.tap), isTrue);

      await sheet.chooseTier(AlertMode.notify);

      expect(tester.getRect(byId(id)), rect);
      final data = dataOf(tester, id);
      expect(data.label, contains('Remove after it rings'));
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      final opacity = tester.widget<Opacity>(
        find.descendant(of: byId(id), matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, FormMetrics.disabledOpacity);

      await tester.tap(byId(id), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(sheet.removeAfterValue, isFalse);
      // The inert tap changed nothing behind the dimmed switch either.
      await sheet.chooseTier(AlertMode.ring);
      expect(sheet.removeAfterValue, isTrue);
    });

    testWidgets('the remove switch is parked across a tier change, not '
        'dropped', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      final result = await openSheet(tester);
      expect(sheet.removeAfterValue, isTrue);

      await sheet.chooseTier(AlertMode.notify);
      expect(sheet.removeAfterEnabled, isFalse);
      expect(sheet.removeAfterValue, isFalse);

      await sheet.chooseTier(AlertMode.ring);
      expect(sheet.removeAfterEnabled, isTrue);
      expect(sheet.removeAfterValue, isTrue);
      await sheet.save();

      expect(result.value?.mode, AlertMode.ring);
      expect(result.value?.removeAfterAlert, isTrue);
    });

    testWidgets('a switch turned off stays off across the round trip', (
      tester,
    ) async {
      final sheet = QuickAlarmRobot(tester);
      final result = await openSheet(tester);

      await sheet.toggleRemoveAfter();
      await sheet.chooseTier(AlertMode.notify);
      await sheet.chooseTier(AlertMode.ring);
      expect(sheet.removeAfterValue, isFalse);
      await sheet.save();

      expect(result.value?.removeAfterAlert, isFalse);
    });

    testWidgets('the tier reads its choice back in one slot, with no '
        'full-screen warning to make room for', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      await openSheet(tester);

      final candidates = tester.widget<FormCaptionSlot>(slot()).candidates;
      expect(
        [for (final candidate in candidates) (candidate as FormCaption).text],
        [notifyHint, ringHint],
      );
      expect(shown(ringHint), findsOneWidget);
      expect(shown(notifyHint), findsNothing);
      expect(find.semantics.byLabel(ringHint), findsOne);
      expect(find.semantics.byLabel(notifyHint), findsNothing);

      await sheet.chooseTier(AlertMode.notify);
      expect(shown(notifyHint), findsOneWidget);
      expect(shown(ringHint), findsNothing);
      expect(find.semantics.byLabel(notifyHint), findsOne);
      expect(find.semantics.byLabel(ringHint), findsNothing);
    });
  });

  group('nothing moves', () {
    const rowIds = [
      SemanticsIds.quickAlarmTime,
      SemanticsIds.quickAlarmPreset20,
      SemanticsIds.quickAlarmName,
      SemanticsIds.quickAlarmTypeReminder,
      SemanticsIds.quickAlarmTypeAlarm,
      SemanticsIds.quickAlarmRemoveAfter,
    ];

    testWidgets('the sheet keeps its height and every row its place on both '
        'tiers', (tester) async {
      // Narrow enough for the two hints to take a different number of lines,
      // and tall enough for the sheet to stay under its clamp.
      const surface = Size(360, 900);
      final sheet = QuickAlarmRobot(tester);
      await openSheet(tester, surface: surface);

      double candidateHeight(String text) =>
          tester.getSize(find.text(text).first).height;
      expect(candidateHeight(ringHint), lessThan(candidateHeight(notifyHint)));

      final height = sheetHeight(tester);
      // Under its clamp, or an unchanged height would prove nothing.
      expect(height, lessThan(surface.height * FormMetrics.sheetHeightFactor));
      final slotHeight = tester.getSize(slot()).height;
      expect(slotHeight, candidateHeight(notifyHint));
      Map<String, Rect> rowRects() => {
        for (final id in rowIds) id: tester.getRect(byId(id)),
      };
      final rows = rowRects();
      void expectUnmoved(String state) {
        expect(sheetHeight(tester), height, reason: state);
        expect(tester.getSize(slot()).height, slotHeight, reason: state);
        expect(rowRects(), rows, reason: state);
      }

      await sheet.chooseTier(AlertMode.notify);
      expectUnmoved('Reminder');
      expect(shown(notifyHint), findsOneWidget);

      await sheet.chooseTier(AlertMode.ring);
      expectUnmoved('Alarm again');
    });

    testWidgets('the keyboard\'s inset pads the scroll view and never the '
        'sheet: the header stays in reach, the sheet within its clamp', (
      tester,
    ) async {
      final sheet = QuickAlarmRobot(tester);
      final result = await openSheet(tester, surface: phone);
      double bodyBottomPadding() => tester
          .widget<SingleChildScrollView>(
            inSheet(find.byType(SingleChildScrollView)),
          )
          .padding!
          .resolve(TextDirection.ltr)
          .bottom;
      expect(bodyBottomPadding(), FormMetrics.bodyBottom);

      const keyboard = 320.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(bodyBottomPadding(), FormMetrics.bodyBottom + keyboard);
      expect(
        sheetHeight(tester),
        lessThanOrEqualTo(phone.height * FormMetrics.sheetHeightFactor),
      );
      // The header is the sheet's first child, above the scroll view the
      // inset pads.
      await sheet.save();
      expect(result.value, isNotNull);
    });

    testWidgets('the header\'s hairline follows the body: on while it is '
        'scrolled over the keyboard, off once the keyboard is down and the '
        'sheet no longer scrolls', (tester) async {
      // Tall enough for the sheet to stay under its clamp without the
      // keyboard, so that the keyboard alone is what makes its body scroll.
      const surface = Size(360, 900);
      await openSheet(tester, surface: surface);
      expect(
        sheetHeight(tester),
        lessThan(surface.height * FormMetrics.sheetHeightFactor),
      );
      final body = inSheet(find.byType(SingleChildScrollView));
      final scrolled = tester
          .widget<FormSheetHeader>(inSheet(find.byType(FormSheetHeader)))
          .scrolled!;
      double offset() => tester
          .state<ScrollableState>(
            find.descendant(of: body, matching: find.byType(Scrollable)).first,
          )
          .position
          .pixels;
      expect(scrolled.value, isFalse);

      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(scrolled.value, isFalse);
      await tester.drag(body, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(offset(), greaterThan(0));
      expect(scrolled.value, isTrue);

      // The sheet is as tall as its rows again and the scroll view back at
      // its top, without a scroll: no listener on a scroll controller hears
      // of it.
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(offset(), 0);
      expect(scrolled.value, isFalse);
    });
  });

  group('ids and layout', () {
    testWidgets('every control carries its id', (tester) async {
      await openSheet(tester);

      for (final id in [
        SemanticsIds.quickAlarmClose,
        SemanticsIds.quickAlarmSave,
        SemanticsIds.quickAlarmTime,
        SemanticsIds.quickAlarmPreset20,
        SemanticsIds.quickAlarmPreset60,
        SemanticsIds.quickAlarmPresetTonight,
        SemanticsIds.quickAlarmName,
        SemanticsIds.quickAlarmTypeReminder,
        SemanticsIds.quickAlarmTypeAlarm,
        SemanticsIds.quickAlarmRemoveAfter,
      ]) {
        expect(byId(id), findsOneWidget, reason: id);
        expect(dataOf(tester, id).identifier, id);
      }
      // One announcement per row: the label and its second line in the
      // switch's own node.
      expect(
        dataOf(tester, SemanticsIds.quickAlarmRemoveAfter).label,
        allOf(
          contains('Remove after it rings'),
          contains('The event is deleted once you stop the alarm.'),
        ),
      );
    });

    testWidgets('what the Quick Settings tile\'s device evidence reads is '
        'still on screen', (tester) async {
      // `docs/event-alerts-os-integration-roadmap.md` records the tile's
      // pass as a Save button on `quick-alarm-save`, "Quick alarm" and
      // "Today".
      await openSheet(tester);

      final save = dataOf(tester, SemanticsIds.quickAlarmSave);
      expect(save.label, 'Save');
      expect(save.flagsCollection.isButton, isTrue);
      expect(find.semantics.byLabel('Quick alarm'), findsOne);
      expect(inSheet(find.text('Today')), findsOneWidget);
      expect(
        dataOf(tester, SemanticsIds.quickAlarmTime).label,
        contains('Today'),
      );
    });

    testWidgets('on a 360 × 780 phone nothing overflows and every control '
        'keeps a 48 dp target', (tester) async {
      await openSheet(tester, surface: phone);

      expect(tester.takeException(), isNull);
      // The test font draws every glyph a full em wide, about twice a
      // phone's, so the captions run to more lines here than on a device;
      // whether the sheet fits unscrolled is the device pass's to see. What
      // holds at any font is the clamp and the targets.
      expect(
        sheetHeight(tester),
        lessThanOrEqualTo(phone.height * FormMetrics.sheetHeightFactor),
      );
      for (final chip in inSheet(find.byType(FormChip)).evaluate()) {
        expect(
          tester.getSize(find.byWidget(chip.widget)).height,
          FormMetrics.chipTapTarget,
        );
      }
      const rowHeights = {
        SemanticsIds.quickAlarmTime: FormMetrics.heroRowMinHeight,
        SemanticsIds.quickAlarmRemoveAfter: FormMetrics.twoLineRowMinHeight,
      };
      for (final MapEntry(key: id, value: minHeight) in rowHeights.entries) {
        await tester.ensureVisible(byId(id));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: id);
        expect(
          tester.getSize(byId(id)).height,
          greaterThanOrEqualTo(minHeight),
          reason: id,
        );
        expect(
          tester.getRect(byId(id)).right,
          lessThanOrEqualTo(phone.width - RowMetrics.groupInset),
          reason: id,
        );
      }
      expect(
        tester.getSize(inSheet(find.byType(FormTitleRow))).height,
        greaterThanOrEqualTo(FormMetrics.titleRowMinHeight),
      );
      expect(
        tester.getSize(byId(SemanticsIds.quickAlarmClose)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(byId(SemanticsIds.quickAlarmSave)).height,
        FormMetrics.headerHeight,
      );
    });

    testWidgets('German at text scale 2.0 on a 360 × 780 phone lays out '
        'without overflow and every label reads whole', (tester) async {
      final sheet = QuickAlarmRobot(tester);
      final result = await openSheet(
        tester,
        surface: phone,
        locale: const Locale('de'),
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
      expect(
        sheetHeight(tester),
        lessThanOrEqualTo(phone.height * FormMetrics.sheetHeightFactor),
      );
      expect(
        tester
            .widget<FormSheetHeader>(inSheet(find.byType(FormSheetHeader)))
            .title,
        'Schnellalarm',
      );
      expect(
        tester
            .widget<FormHeaderTextButton>(
              inSheet(find.byType(FormHeaderTextButton)),
            )
            .label,
        'Speichern',
      );
      expect(sheet.timeLabel, '10:15');

      // A label wraps as far as it needs to and is never cut: no line limit,
      // a box as tall as its text, inside the group. The chips are in the
      // list — a chip's 32 dp is a minimum, and at this scale the longest
      // preset takes two lines. "Alarm" is looked for in its chip: the name
      // field opens on the same word.
      final labels = <String, Finder>{
        for (final label in [
          'Heute',
          'In 20 Min.',
          'In 1 Stunde',
          'Heute Abend 21:00',
          'Art',
          'Mitteilung',
          'Nach dem Klingeln entfernen',
          'Der Termin wird gelöscht, sobald du den Alarm stoppst. '
              'Rückgängig geht direkt danach.',
        ])
          label: inSheet(find.text(label)),
        'Alarm': find.descendant(
          of: chip(SemanticsIds.quickAlarmTypeAlarm),
          matching: find.text('Alarm'),
        ),
      };
      for (final MapEntry(key: label, value: text) in labels.entries) {
        await tester.ensureVisible(text);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
        expect(tester.widget<Text>(text).maxLines, isNull, reason: label);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(
          paragraph.size.height,
          moreOrLessEquals(
            paragraph.getMaxIntrinsicHeight(paragraph.size.width),
            epsilon: 0.01,
          ),
          reason: label,
        );
        final rect = tester.getRect(text);
        expect(
          rect.left,
          greaterThanOrEqualTo(RowMetrics.groupInset),
          reason: label,
        );
        expect(
          rect.right,
          lessThanOrEqualTo(phone.width - RowMetrics.groupInset),
          reason: label,
        );
      }
      for (final chip in inSheet(find.byType(FormChip)).evaluate()) {
        expect(
          tester.getSize(find.byWidget(chip.widget)).height,
          greaterThanOrEqualTo(FormMetrics.chipTapTarget),
        );
      }
      // The tier's line wraps whole as well. It is in the tree twice, the
      // copy that sizes the slot first and the one on screen last.
      final hint = inSheet(
        find.text('Spielt über den Weckton, bis du stoppst oder schlummerst.'),
      ).last;
      expect(tester.widget<Text>(hint).maxLines, isNull);
      expect(
        tester.getRect(hint).right,
        lessThanOrEqualTo(phone.width - RowMetrics.groupInset),
      );
      // The same slot at this scale: the two German lines differ too.
      final slotHeight = tester.getSize(slot()).height;
      await sheet.chooseTier(AlertMode.notify);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(slot()).height, slotHeight);

      // The pad opens and closes at this scale as well, a preset still
      // answers and Save reports it.
      await sheet.openTimePad();
      expect(tester.takeException(), isNull);
      await sheet.cancelTimePad();
      await sheet.choosePreset(QuickAlarmPreset.in1Hour);
      await sheet.save();
      expect(tester.takeException(), isNull);
      expect(result.value?.startMinute, 11 * 60 + 4);
      expect(result.value?.mode, AlertMode.notify);
    });

    testWidgets('en, de and ro at 1.0, 1.3 and 2.0 on both phone sizes, '
        'light and dark: nothing overflows, top to bottom', (tester) async {
      final themes = [AppTheme.light(), AppTheme.dark()];
      for (final surface in const [phone, Size(412, 915)]) {
        for (final locale in AppLocalizations.supportedLocales) {
          for (final textScale in const [1.0, 1.3, 2.0]) {
            for (final theme in themes) {
              final state =
                  '$locale at $textScale on ${surface.width.round()} dp, '
                  '${theme.brightness.name}';
              final sheet = QuickAlarmRobot(tester);
              await openSheet(
                tester,
                surface: surface,
                locale: locale,
                textScale: textScale,
                theme: theme,
              );
              expect(tester.takeException(), isNull, reason: state);
              expect(
                sheetHeight(tester),
                lessThanOrEqualTo(
                  surface.height * FormMetrics.sheetHeightFactor,
                ),
                reason: state,
              );

              // Down to the last row and across the tier, where a line that
              // wraps differently would show.
              await sheet.chooseTier(AlertMode.notify);
              await tester.ensureVisible(
                byId(SemanticsIds.quickAlarmRemoveAfter),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: state);
              expect(
                tester.getRect(byId(SemanticsIds.quickAlarmRemoveAfter)).right,
                lessThanOrEqualTo(surface.width - RowMetrics.groupInset),
                reason: state,
              );
              await sheet.close();
            }
          }
        }
      }
    });
  });
}

class _Result {
  QuickAlarmDraft? value;
  bool closed = false;
}
