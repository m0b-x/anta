import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/simple_markdown_preview.dart';

/// The detail sheet stays read-only — checkbox toggling is still its only
/// in-place edit — so the quick edit is an *action it reports*, not an editor
/// it mounts. These pin the three things that changed around the description
/// card: the way out of the empty state, the pencil, and the caption that
/// explains the one unresponsive thing left on the sheet.
void main() {
  final day = DateTime.utc(2026, 8, 25);

  CalendarEvent event({
    String? description,
    RecurrenceRule rule = const OneTimeRecurrence(),
    bool perOccurrenceDescriptions = false,
  }) => CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: day,
    rule: rule,
    description: description,
    perOccurrenceDescriptions: perOccurrenceDescriptions,
  );

  /// Opens the sheet and records the action it pops with.
  Future<List<EventDetailAction?>> openSheet(
    WidgetTester tester,
    CalendarEvent subject, {
    String? pendingOccurrenceDescription,
    bool wireEventWrites = false,
    bool wireOccurrenceWrites = false,
  }) async {
    final actions = <EventDetailAction?>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                actions.add(
                  await EventDetailSheet.show(
                    context,
                    event: subject,
                    day: day,
                    pendingOccurrenceDescription: pendingOccurrenceDescription,
                    onEventChanged: wireEventWrites ? (_) {} : null,
                    onOccurrenceChanged: wireOccurrenceWrites
                        ? (_, _) {}
                        : null,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return actions;
  }

  String renderedDescription(WidgetTester tester) => tester
      .widget<SimpleMarkdownPreview>(find.byType(SimpleMarkdownPreview))
      .data;

  testWidgets('an empty description offers a way out of the empty state', (
    tester,
  ) async {
    final actions = await openSheet(tester, event());

    expect(find.text('Add description'), findsOneWidget);
    expect(
      find.text('No notes for this event'),
      findsNothing,
      reason: 'the dead line was replaced by the affordance that fixes it',
    );

    await tester.tap(find.text('Add description'));
    await tester.pumpAndSettle();

    expect(actions, [EventDetailAction.editDescription]);
  });

  testWidgets('the pencil on the description card reports the quick edit', (
    tester,
  ) async {
    final actions = await openSheet(tester, event(description: 'Squats'));

    await tester.tap(find.byIcon(Icons.edit_note_rounded));
    await tester.pumpAndSettle();

    expect(actions, [EventDetailAction.editDescription]);
  });

  testWidgets('the sheet mounts no editor — the quick edit is only an action', (
    tester,
  ) async {
    await openSheet(tester, event(description: 'Squats'));
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a pending occurrence write beats the facade', (tester) async {
    // The page reopens this sheet in the same turn it dispatches the write, so
    // reading the facade here would show the pre-edit text.
    await openSheet(
      tester,
      event(
        description: 'the template',
        rule: const DailyRecurrence(),
        perOccurrenceDescriptions: true,
      ),
      pendingOccurrenceDescription: 'just written for this day',
    );

    expect(renderedDescription(tester), 'just written for this day');
  });

  testWidgets('inert task boxes get a reason', (tester) async {
    // Repeating, per-occurrence off: a tick would read as ticked on every
    // occurrence, so the boxes stay inert — and now say why.
    await openSheet(
      tester,
      event(description: '- [ ] Warm up', rule: const DailyRecurrence()),
      wireEventWrites: true,
      wireOccurrenceWrites: true,
    );

    expect(
      find.textContaining('would apply to every occurrence'),
      findsOneWidget,
    );
  });

  testWidgets('a description with no task box gets no caption', (tester) async {
    await openSheet(
      tester,
      event(description: 'Just a note', rule: const DailyRecurrence()),
      wireEventWrites: true,
    );

    expect(
      find.textContaining('would apply to every occurrence'),
      findsNothing,
      reason: 'there is nothing to tick, so there is nothing to explain',
    );
  });

  testWidgets('tickable boxes get no caption', (tester) async {
    // A one-time event's tick edits the event, unambiguously.
    await openSheet(
      tester,
      event(description: '- [ ] Warm up'),
      wireEventWrites: true,
    );

    expect(
      find.textContaining('would apply to every occurrence'),
      findsNothing,
    );
  });
}
