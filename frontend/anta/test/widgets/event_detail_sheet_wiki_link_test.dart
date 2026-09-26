import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/simple_markdown_preview.dart';

/// `[[note]]` in an event's description.
///
/// The sheet never navigates itself — it pops with an
/// [EventDetailAction] and the host acts — so a wiki link, which has no
/// action to pop with, pops with `null` and hands the raw title over
/// afterwards. That order is the whole contract: a "no note titled …"
/// snackbar cannot be seen behind a modal sheet, and the editor for a
/// title that does resolve has to be pushed over the calendar page rather
/// than over a sheet that is about to be dismissed. The cases below pin
/// the order, the rendering, the re-entry guard that keeps a wiki tap from
/// exiting a sheet some other control already exited, and the two things
/// that stay inert — an unwired wiki link and the `[text](url)` links the
/// sheet has never opened.
void main() {
  final day = DateTime.utc(2026, 8, 25);

  CalendarEvent event(String description) => CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: day,
    rule: const OneTimeRecurrence(),
    description: description,
  );

  /// Opens the sheet over [description] and returns the action it pops
  /// with plus an ordered log of the pop and the wiki-link callback.
  Future<({List<EventDetailAction?> actions, List<String> log})> openSheet(
    WidgetTester tester,
    String description, {
    bool wireWikiLinks = true,
  }) async {
    final actions = <EventDetailAction?>[];
    final log = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        navigatorObservers: [_PopRecorder(log)],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                actions.add(
                  await EventDetailSheet.show(
                    context,
                    event: event(description),
                    day: day,
                    onOpenWikiLink: wireWikiLinks
                        ? (title) => log.add('wiki:$title')
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
    return (actions: actions, log: log);
  }

  /// The description card's rendered rich text.
  RichText descriptionText(WidgetTester tester) => tester.widget<RichText>(
    find.descendant(
      of: find.byType(SimpleMarkdownPreview),
      matching: find.byType(RichText),
    ),
  );

  /// Every leaf span of the rendered description whose text is exactly
  /// [text]. The recognizer is attached to every node of the wrapped
  /// subtree, so the leaf carries it.
  List<TextSpan> leavesReading(WidgetTester tester, String text) {
    final found = <TextSpan>[];
    descriptionText(tester).text.visitChildren((span) {
      if (span is TextSpan && span.text == text) found.add(span);
      return true;
    });
    return found;
  }

  testWidgets('a wiki link renders its title without the brackets', (
    tester,
  ) async {
    await openSheet(tester, 'see [[Squat]] now');

    expect(
      descriptionText(tester).text.toPlainText(includePlaceholders: false),
      'see Squat now',
    );
    expect(find.textContaining('[[', findRichText: true), findsNothing);
  });

  testWidgets('tapping a wiki link closes the sheet first, then reports the '
      'title', (tester) async {
    final sheet = await openSheet(tester, 'see [[Squat]] now');

    final title = leavesReading(tester, 'Squat').single;
    (title.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();

    expect(
      sheet.log,
      ['pop', 'wiki:Squat'],
      reason: 'the host is handed the title only once the sheet is gone',
    );
    expect(sheet.actions, [
      null,
    ], reason: 'a wiki link has no action to pop with');
    expect(find.byType(EventDetailSheet), findsNothing);
  });

  testWidgets('a wiki link that fires after another exit is ignored', (
    tester,
  ) async {
    // The window the sheet guards is one frame, not the exit animation: from
    // the moment the pop starts, `_ModalScopeState` wraps the route's page in
    // an `IgnorePointer`, so nothing on it can be *hit* any more. What can
    // still re-enter is a callback invoked directly, which is why the wiki
    // tap here is fired as a recognizer callback rather than through
    // `tester.tap` — a pointer would land on the ignoring scope and prove
    // nothing. Without the guard this pops a second time, taking the calendar
    // page out from under the editor the `edit` action is about to push, and
    // then hands the host a title to open on top of that.
    final sheet = await openSheet(tester, 'see [[Squat]] now');

    final title = leavesReading(tester, 'Squat').single;
    await tester.tap(
      find.descendant(
        of: find.byType(EventDetailSheet),
        matching: find.widgetWithText(TextButton, 'Edit'),
      ),
    );
    // No pump in between: both exits are attempted in the same frame.
    (title.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();

    expect(sheet.log, [
      'pop',
    ], reason: 'one pop, and the wiki callback never fired');
    expect(sheet.actions, [EventDetailAction.edit]);
  });

  testWidgets('an unwired wiki link stays inert and leaves the sheet up', (
    tester,
  ) async {
    final sheet = await openSheet(
      tester,
      'see [[Squat]] now',
      wireWikiLinks: false,
    );

    final title = leavesReading(tester, 'Squat').single;
    expect(title.recognizer, isNull);

    await tester.tapAt(tester.getCenter(find.byType(SimpleMarkdownPreview)));
    await tester.pumpAndSettle();

    expect(find.byType(EventDetailSheet), findsOneWidget);
    expect(sheet.actions, isEmpty);
    expect(sheet.log, isEmpty);
  });

  testWidgets('a [text](url) link on the same line stays inert', (
    tester,
  ) async {
    // The sheet wires `onTapWikiLink` and nothing else, so ordinary links
    // still render as link-styled text that opens nothing — pinned here
    // because the two now sit side by side in the same builder.
    await openSheet(tester, 'see [[Squat]] and [docs](https://x.dev)');

    expect(leavesReading(tester, 'Squat').single.recognizer, isNotNull);
    expect(leavesReading(tester, 'docs').single.recognizer, isNull);
    expect(
      descriptionText(tester).text.toPlainText(includePlaceholders: false),
      'see Squat and docs',
    );
  });
}

/// Records every route pop into a shared log, so the sheet's dismissal can
/// be ordered against the host callback that follows it.
class _PopRecorder extends NavigatorObserver {
  _PopRecorder(this.log);

  final List<String> log;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    log.add('pop');
  }
}
