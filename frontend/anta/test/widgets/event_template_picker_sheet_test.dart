import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_templates.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_template.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/event_template_picker_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

/// The picker's two neutral rows are what make the FAB long press worth
/// answering with no templates saved: the quick alarm above the blank form.
/// Since the 2026-09-27 Tier 1 pass every row is one of the language's,
/// addressed by its `SemanticsIds` value, and the sheet is content-tall.
void main() {
  Finder byId(String id) => find.bySemanticsIdentifier(id);

  Future<_Result> openSheet(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Size? size,
    double textScale = 1.0,
  }) async {
    if (size != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
    }
    final result = _Result();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result.value = await EventTemplatePickerSheet.show(context);
                result.returned = true;
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

  EventTemplate template(String id, String name, {int sortOrder = 0}) =>
      EventTemplate(
        id: id,
        name: name,
        categoryId: 'gym',
        rule: const WeeklyRecurrence(weekdays: {1, 3}),
        time: const EventTime(startMinute: 18 * 60, durationMinutes: 90),
        sortOrder: sortOrder,
      );

  setUp(CalendarTemplates.resetCache);
  tearDown(CalendarTemplates.resetCache);

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

  testWidgets('the blank row carries its id', (tester) async {
    final result = await openSheet(tester);

    await tester.tap(byId(SemanticsIds.templatePickBlank));
    await tester.pumpAndSettle();

    expect(result.value, isA<EventTemplateBlank>());
  });

  testWidgets('each template row wears its avatar and summary, carries its id '
      'and pops its template, above the two neutral rows', (tester) async {
    CalendarTemplates.updateCache([
      template('t1', 'Leg day'),
      template('t2', 'Push day', sortOrder: 1),
    ]);
    final result = await openSheet(tester);

    expect(byId(SemanticsIds.templatePickRow('t1')), findsOneWidget);
    expect(byId(SemanticsIds.templatePickRow('t2')), findsOneWidget);
    expect(find.byType(EventAvatar), findsNWidgets(2));
    expect(find.byType(FormPickerRow), findsNWidgets(2));
    expect(find.byType(FormActionRow), findsNWidgets(2));
    // The summary is the row's caption, inside its one node.
    final data = tester
        .getSemantics(byId(SemanticsIds.templatePickRow('t1')))
        .getSemanticsData();
    expect(data.label, contains('Leg day'));
    expect(data.label, contains('18:00'));

    final leg = tester.getTopLeft(find.text('Leg day'));
    final push = tester.getTopLeft(find.text('Push day'));
    final alarm = tester.getTopLeft(find.text('Alarm…'));
    final blank = tester.getTopLeft(find.text('Blank event'));
    expect(leg.dy, lessThan(push.dy));
    expect(push.dy, lessThan(alarm.dy));
    expect(alarm.dy, lessThan(blank.dy));

    await tester.tap(byId(SemanticsIds.templatePickRow('t2')));
    await tester.pumpAndSettle();
    expect(
      result.value,
      isA<EventTemplatePicked>().having(
        (choice) => choice.template.id,
        'template',
        't2',
      ),
    );
  });

  testWidgets('the header is ✕ · title · nothing, and ✕ pops null', (
    tester,
  ) async {
    final result = await openSheet(tester);

    expect(find.byType(FormSheetHeader), findsOneWidget);
    expect(find.text('Add from template'), findsOneWidget);
    expect(find.byType(FormHeaderTextButton), findsNothing);

    await tester.tap(byId(SemanticsIds.templatePickClose));
    await tester.pumpAndSettle();
    expect(result.returned, isTrue);
    expect(result.value, isNull);
    expect(find.byType(EventTemplatePickerSheet), findsNothing);
  });

  testWidgets('at text scale 2.0 in German on a 360 × 780 phone nothing '
      'overflows and every row reads whole', (tester) async {
    CalendarTemplates.updateCache([
      template('t1', 'Beintag'),
      template('t2', 'Drücken', sortOrder: 1),
    ]);
    await openSheet(
      tester,
      locale: const Locale('de'),
      size: const Size(360, 780),
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Aus Vorlage hinzufügen'), findsOneWidget);
    expect(find.text('Beintag'), findsOneWidget);
    expect(find.text('Alarm…'), findsOneWidget);
    expect(find.text('Leerer Termin'), findsOneWidget);
    // A summary that would run past two lines clamps rather than pushing
    // the rows below it out of the sheet.
    for (final caption in tester.widgetList<Text>(
      find.descendant(
        of: find.byType(FormPickerRow),
        matching: find.byWidgetPredicate(
          (w) => w is Text && (w.data?.contains('18:00') ?? false),
        ),
      ),
    )) {
      expect(caption.maxLines, 2);
    }
    expect(byId(SemanticsIds.templatePickBlank), findsOneWidget);
  });
}

class _Result {
  EventTemplateChoice? value;
  bool returned = false;
}
