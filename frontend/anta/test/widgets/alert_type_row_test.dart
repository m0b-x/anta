import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/alert_editor_sheet.dart';
import 'package:anta/widgets/alert_type_row.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/quick_alarm_sheet.dart';

import '../database/support/db_test_support.dart';

/// The Type row is one widget on two sheets, the alert sheet and the quick
/// alarm. Each sheet's suite proves it in place; this pins the row itself —
/// the order, the ids it is handed, the tap it reports and the slot that
/// keeps the rows under it still — so neither sheet has to stand for the
/// other, and that both sheets still draw this row rather than a copy.
void main() {
  const reminderId = 'type-reminder';
  const alarmId = 'type-alarm';
  const notifyHint =
      'Sits in the shade with Snooze and Done. Silent mode and Focus apply.';
  const ringHint = 'Plays on the alarm stream until you stop or snooze it.';
  const warning =
      'Full-screen alarms are off, so this rings as a banner instead of '
      'taking over the screen.';

  /// The row as a group's first row, at the width a 360 dp phone gives a
  /// group, where the lines under the chips wrap to different heights.
  Future<void> pumpRow(
    WidgetTester tester, {
    required AlertMode mode,
    ValueChanged<AlertMode>? onChanged,
    String? alarmWarning,
    bool showAlarmWarning = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 328,
              child: FormRowGroup(
                children: [
                  AlertTypeRow(
                    mode: mode,
                    onChanged: onChanged ?? (_) {},
                    reminderIdentifier: reminderId,
                    alarmIdentifier: alarmId,
                    alarmWarning: alarmWarning,
                    showAlarmWarning: showAlarmWarning,
                  ),
                  FormPickerRow(label: 'Below', onTap: () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  bool selectedOf(WidgetTester tester, String id) => switch (tester
      .getSemantics(byId(id))
      .getSemanticsData()
      .flagsCollection
      .isSelected) {
    Tristate.isTrue => true,
    _ => false,
  };

  /// The copy of [text] a finger can reach: the slot also lays out every
  /// line it may say, unseen, to hold its height.
  Finder shown(String text) => find.text(text).hitTestable();

  double rowHeight(WidgetTester tester) =>
      tester.getSize(find.byType(AlertTypeRow)).height;

  Rect below(WidgetTester tester) => tester.getRect(find.text('Below'));

  testWidgets('Reminder comes before Alarm on the ids the sheet hands over, '
      'the tier\'s chip the selected one', (tester) async {
    await pumpRow(tester, mode: AlertMode.ring);

    final chips = tester.widgetList<FormChip>(find.byType(FormChip)).toList();
    expect([for (final chip in chips) chip.label], ['Reminder', 'Alarm']);
    expect([for (final chip in chips) chip.identifier], [reminderId, alarmId]);
    expect([for (final chip in chips) chip.selected], [isFalse, isTrue]);
    expect(selectedOf(tester, reminderId), isFalse);
    expect(selectedOf(tester, alarmId), isTrue);
    expect(
      tester.getRect(byId(reminderId)).right,
      lessThanOrEqualTo(tester.getRect(byId(alarmId)).left),
    );

    await pumpRow(tester, mode: AlertMode.notify);
    expect(selectedOf(tester, reminderId), isTrue);
    expect(selectedOf(tester, alarmId), isFalse);
  });

  testWidgets('a tap reports the tier of its chip, the selected one included', (
    tester,
  ) async {
    final reported = <AlertMode>[];
    await pumpRow(tester, mode: AlertMode.notify, onChanged: reported.add);

    await tester.tap(byId(alarmId));
    await tester.tap(byId(reminderId));

    // The row owns no tier: it says what was tapped, and the sheet decides
    // what a tap on the tier it is already on means.
    expect(reported, [AlertMode.ring, AlertMode.notify]);
  });

  testWidgets('the row is the labelled chip row, with a glyph row\'s '
      'hairline under it', (tester) async {
    await pumpRow(tester, mode: AlertMode.notify);

    final chipRow = tester.widget<FormChipRow>(find.byType(FormChipRow));
    expect(chipRow.label, 'Type');
    expect(chipRow.glyph, Icons.notifications_outlined);
    final row = tester.widget<AlertTypeRow>(find.byType(AlertTypeRow));
    expect(FormRowGroup.indentOf(row), FormMetrics.dividerIndentGlyph);
    expect(
      tester.widget<Divider>(find.byType(Divider)).indent,
      FormMetrics.dividerIndentGlyph,
    );
  });

  testWidgets('each tier reads back its own line, and only the line shown is '
      'announced', (tester) async {
    await pumpRow(tester, mode: AlertMode.notify);
    expect(shown(notifyHint), findsOneWidget);
    expect(shown(ringHint), findsNothing);
    expect(find.semantics.byLabel(notifyHint), findsOne);
    expect(find.semantics.byLabel(ringHint), findsNothing);

    await pumpRow(tester, mode: AlertMode.ring);
    expect(shown(ringHint), findsOneWidget);
    expect(shown(notifyHint), findsNothing);
    expect(find.semantics.byLabel(ringHint), findsOne);
    expect(find.semantics.byLabel(notifyHint), findsNothing);
  });

  testWidgets('the slot is as tall as the taller line on both tiers, so the '
      'row under it never moves', (tester) async {
    await pumpRow(tester, mode: AlertMode.notify);
    double lineHeight(String text) =>
        tester.getSize(find.text(text).first).height;
    // At this width the two lines differ, so a bare caption would move the
    // row below.
    expect(lineHeight(ringHint), lessThan(lineHeight(notifyHint)));
    final slot = tester.widget<FormCaptionSlot>(find.byType(FormCaptionSlot));
    expect(slot.candidates, hasLength(2));
    expect(
      tester.getSize(find.byType(FormCaptionSlot)).height,
      lineHeight(notifyHint),
    );
    final height = rowHeight(tester);
    final rowBelow = below(tester);

    await pumpRow(tester, mode: AlertMode.ring);
    expect(rowHeight(tester), height);
    expect(below(tester), rowBelow);
  });

  testWidgets('a warning has its room from the first frame: turning up '
      'late, it moves nothing', (tester) async {
    await pumpRow(tester, mode: AlertMode.ring);
    final withoutWarning = rowHeight(tester);

    await pumpRow(tester, mode: AlertMode.ring, alarmWarning: warning);
    // The longest of the three lines, so the slot is taller for it even
    // while the Alarm tier still shows its own hint.
    final height = rowHeight(tester);
    expect(height, greaterThan(withoutWarning));
    final rowBelow = below(tester);
    expect(shown(ringHint), findsOneWidget);
    expect(shown(warning), findsNothing);
    expect(find.semantics.byLabel(warning), findsNothing);

    await pumpRow(
      tester,
      mode: AlertMode.ring,
      alarmWarning: warning,
      showAlarmWarning: true,
    );
    expect(rowHeight(tester), height);
    expect(below(tester), rowBelow);
    expect(shown(warning), findsOneWidget);
    expect(shown(ringHint), findsNothing);
    expect(
      tester.widget<Text>(shown(warning)).style!.color,
      Theme.of(tester.element(find.byType(AlertTypeRow))).colorScheme.error,
    );

    // The warning is the Alarm tier's: a reminder takes over no screen.
    await pumpRow(
      tester,
      mode: AlertMode.notify,
      alarmWarning: warning,
      showAlarmWarning: true,
    );
    expect(rowHeight(tester), height);
    expect(below(tester), rowBelow);
    expect(shown(notifyHint), findsOneWidget);
    expect(shown(warning), findsNothing);
  });

  testWidgets('a flag with no warning to show changes nothing', (tester) async {
    await pumpRow(tester, mode: AlertMode.ring, showAlarmWarning: true);

    expect(shown(ringHint), findsOneWidget);
    expect(
      tester.widget<FormCaptionSlot>(find.byType(FormCaptionSlot)).candidates,
      hasLength(2),
    );
  });

  group('on the two sheets', () {
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

    Future<AlertTypeRow> rowOf(
      WidgetTester tester,
      Future<void> Function(BuildContext context) open,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return tester.widget<AlertTypeRow>(find.byType(AlertTypeRow));
    }

    // One row on both sheets is the point of the widget: a sheet that draws
    // its own copy again is how the two came to disagree.
    testWidgets('the alert sheet draws this row on its own ids, with its '
        'full-screen warning to make room for', (tester) async {
      final row = await rowOf(
        tester,
        (context) => AlertEditorSheet.show(
          context,
          alert: const EventAlert(id: 'a1', eventId: 'e1', offsetMinutes: 10),
          event: CalendarEvent(
            id: 'e1',
            title: 'Leg day',
            categoryId: 'gym',
            startDate: DateTime.utc(2026, 9, 20),
            rule: const OneTimeRecurrence(),
            time: const EventTime(startMinute: 18 * 60),
          ),
        ),
      );

      expect(row.mode, AlertMode.notify);
      expect(row.reminderIdentifier, SemanticsIds.alertTypeReminder);
      expect(row.alarmIdentifier, SemanticsIds.alertTypeAlarm);
      expect(row.alarmWarning, warning);
      // No answer from the phone yet is not a no.
      expect(row.showAlarmWarning, isFalse);
    });

    testWidgets('the quick alarm draws this row on its own ids, with no '
        'warning', (tester) async {
      final row = await rowOf(
        tester,
        (context) =>
            QuickAlarmSheet.show(context, day: DateTime.utc(2026, 9, 23)),
      );

      expect(row.mode, AlertMode.ring);
      expect(row.reminderIdentifier, SemanticsIds.quickAlarmTypeReminder);
      expect(row.alarmIdentifier, SemanticsIds.quickAlarmTypeAlarm);
      expect(row.alarmWarning, isNull);
      expect(row.showAlarmWarning, isFalse);
    });
  });
}
