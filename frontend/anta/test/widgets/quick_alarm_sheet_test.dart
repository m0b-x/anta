import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/utils/quick_alarm.dart';
import 'package:anta/widgets/quick_alarm_sheet.dart';

/// The sheet is a form over `quick_alarm.dart`'s arithmetic, so what is worth
/// pinning is the round trip: what it opens on, what each preset does, and
/// what Save reports.
void main() {
  /// 10:03:40 on a Wednesday: not on a quarter hour, so the default and the
  /// presets all have something to round.
  final now = DateTime(2026, 9, 23, 10, 3, 40);
  final today = DateTime.utc(2026, 9, 23);

  Future<_Result> openSheet(
    WidgetTester tester, {
    DateTime? day,
    DateTime? at,
  }) async {
    final result = _Result();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
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

  Finder byId(String id) =>
      find.bySemanticsIdentifier(id, skipOffstage: false);

  Future<void> save(WidgetTester tester) async {
    await tester.tap(byId(SemanticsIds.quickAlarmSave));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the next quarter hour, today, as an alarm', (
    tester,
  ) async {
    final result = await openSheet(tester);

    expect(find.textContaining('10:15'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Alarm'), findsOneWidget);
    final segmented = tester.widget<SegmentedButton<AlertMode>>(
      find.byType(SegmentedButton<AlertMode>),
    );
    expect(segmented.selected, {AlertMode.ring});
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );

    await save(tester);

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
    final result = await openSheet(tester);

    await tester.tap(find.text('In 20 min'));
    await tester.pumpAndSettle();
    expect(find.textContaining('10:24'), findsOneWidget);

    await tester.tap(find.text('In 1 hour'));
    await tester.pumpAndSettle();
    expect(find.textContaining('11:04'), findsOneWidget);

    await tester.tap(find.textContaining('Tonight'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(result.value?.startMinute, kQuickAlarmTonightMinute);
    expect(result.value?.day, today);
  });

  testWidgets('tonight is disabled once 21:00 has passed', (tester) async {
    await openSheet(tester, at: DateTime(2026, 9, 23, 21, 30));

    final chip = tester.widget<ChoiceChip>(
      find.ancestor(
        of: find.textContaining('Tonight'),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(chip.onSelected, isNull);
  });

  testWidgets('a preset that crosses midnight lands on tomorrow', (
    tester,
  ) async {
    final result = await openSheet(tester, at: DateTime(2026, 9, 23, 23, 50));

    expect(find.text('Tomorrow'), findsOneWidget, reason: 'the default too');
    await tester.tap(find.text('In 1 hour'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(result.value?.day, DateTime.utc(2026, 9, 24));
    expect(result.value?.startMinute, 50);
  });

  testWidgets('a time picked by hand is on the opened day, not the preset\'s', (
    tester,
  ) async {
    // 23:50: the default and every preset land on tomorrow, and a time
    // picked by hand that is still ahead tonight must stay tonight.
    final result = await openSheet(tester, at: DateTime(2026, 9, 23, 23, 50));
    await tester.tap(find.text('In 1 hour'));
    await tester.pumpAndSettle();
    expect(find.text('Tomorrow'), findsOneWidget);

    await tester.tap(byId(SemanticsIds.quickAlarmTime));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to text input mode'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '11');
    await tester.enterText(fields.at(1), '58');
    await tester.tap(find.text('PM'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    await save(tester);

    expect(result.value?.day, DateTime.utc(2026, 9, 23));
    expect(result.value?.startMinute, 23 * 60 + 58);
  });

  testWidgets('a day still ahead keeps the day it was opened for', (
    tester,
  ) async {
    final result = await openSheet(tester, day: DateTime.utc(2026, 9, 30));

    expect(find.text('Today'), findsNothing);
    await save(tester);

    expect(result.value?.day, DateTime.utc(2026, 9, 30));
    expect(result.value?.startMinute, 10 * 60 + 15);
  });

  testWidgets('the reminder tier hides the switch and never removes', (
    tester,
  ) async {
    final result = await openSheet(tester);

    await tester.tap(find.text('Reminder'));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);

    await save(tester);

    expect(result.value?.mode, AlertMode.notify);
    expect(result.value?.removeAfterAlert, isFalse);
  });

  testWidgets('the switch off is reported, and back on again', (
    tester,
  ) async {
    final result = await openSheet(tester);

    // Below the fold of the 70% sheet on a phone-sized test surface.
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await save(tester);

    expect(result.value?.removeAfterAlert, isFalse);
  });

  testWidgets('a typed name is the title; an emptied one falls back', (
    tester,
  ) async {
    var result = await openSheet(tester);
    await tester.enterText(find.byType(TextField), '  Dentist  ');
    await save(tester);
    expect(result.value?.name, 'Dentist');

    result = await openSheet(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await save(tester);
    expect(result.value?.name, 'Alarm');
  });

  testWidgets('the big time opens the picker, and cancel keeps the time', (
    tester,
  ) async {
    final result = await openSheet(tester);

    await tester.tap(byId(SemanticsIds.quickAlarmTime));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
    await save(tester);

    expect(result.value?.startMinute, 10 * 60 + 15);
  });

  testWidgets('close reports nothing', (tester) async {
    final result = await openSheet(tester);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(result.closed, isTrue);
    expect(result.value, isNull);
  });
}

class _Result {
  QuickAlarmDraft? value;
  bool closed = false;
}
