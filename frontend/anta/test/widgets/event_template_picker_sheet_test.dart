import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_templates.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/event_template_picker_sheet.dart';

/// The picker's two neutral rows are what make the FAB long press worth
/// answering with no templates saved: the quick alarm above the blank form.
void main() {
  Future<_Result> openSheet(WidgetTester tester) async {
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
                result.value = await EventTemplatePickerSheet.show(context);
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

  setUp(CalendarTemplates.resetCache);

  testWidgets('offers the quick alarm above the blank event with no templates',
      (tester) async {
    expect(CalendarTemplates.isEmpty, isTrue, reason: 'precondition');
    final result = await openSheet(tester);

    final alarm = tester.getTopLeft(find.text('Alarm…'));
    final blank = tester.getTopLeft(find.text('Blank event'));
    expect(alarm.dy, lessThan(blank.dy));

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.quickAlarmRow),
    );
    await tester.pumpAndSettle();

    expect(result.value, isA<EventTemplateQuickAlarm>());
  });

  testWidgets('the blank row still opens the form', (tester) async {
    final result = await openSheet(tester);

    await tester.tap(find.text('Blank event'));
    await tester.pumpAndSettle();

    expect(result.value, isA<EventTemplateBlank>());
  });
}

class _Result {
  EventTemplateChoice? value;
}
