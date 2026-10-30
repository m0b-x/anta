import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_guide_coach.dart';

void main() {
  final en = AppLocalizationsEn();

  GuideCoach coach() => GuideCoach([
    GuideCoachStep('add', (_) => 'Add one.'),
    GuideCoachStep('open', (_) => 'Open it.'),
    GuideCoachStep('delete', (_) => 'Delete it.'),
  ]);

  test('idle names the first step and reports nothing', () {
    final c = coach();
    expect(c.current?.action, 'add');
    expect(c.finished, isFalse);
    expect(c.next(en), 'Add one.');
    expect(c.report(en), isNull);
    expect(c.line(en), 'Add one.');
  });

  test('an action marks its own step done and the line is the next '
      'instruction', () {
    final c = coach()..did('add');
    expect(c.next(en), 'Open it.');
    expect(c.report(en), isNull);
    expect(c.line(en), 'Open it.');
  });

  test('an action out of order marks its step done where it sits, and the '
      'line still asks for the first step not done', () {
    final c = coach()..did('open');
    expect(c.line(en), 'Add one.');

    c.did('add');
    expect(c.line(en), 'Delete it.', reason: 'open is not asked again');
  });

  test('a report is the line alone until the next action', () {
    final c = coach()..did('add');
    c.say((_) => 'Would open the alarm.');
    expect(c.report(en), 'Would open the alarm.');
    expect(c.line(en), 'Would open the alarm.');
    expect(c.next(en), 'Open it.', reason: 'say marks no step');

    c.did('open');
    expect(c.report(en), isNull);
    expect(c.line(en), 'Delete it.');
  });

  test('an action that is no step is refused in debug', () {
    expect(() => coach().did('menu'), throwsA(isA<AssertionError>()));
  });

  test('skip with no report marks the current step done; at the end it is '
      'a no-op', () {
    final c = coach()..did('add');
    c.skip();
    expect(c.next(en), 'Delete it.');
    expect(c.report(en), isNull);

    c.skip();
    expect(c.finished, isTrue);
    expect(c.line(en), en.calendarGuideCoachDone);

    c.skip();
    expect(c.finished, isTrue);
    expect(c.line(en), en.calendarGuideCoachDone);
  });

  test('skip under a standing report only clears it: the instruction it '
      'covered is shown, not stepped past', () {
    final c = coach()
      ..did('add')
      ..say((_) => 'Said.');
    c.skip();
    expect(c.report(en), isNull);
    expect(c.line(en), 'Open it.', reason: 'step 2 is not done');
    expect(c.current?.action, 'open');

    c.skip();
    expect(c.line(en), 'Delete it.');
  });

  test('clearReport drops a standing report and marks no step', () {
    final c = coach()
      ..did('add')
      ..say((_) => 'Said.');
    c.clearReport();
    expect(c.report(en), isNull);
    expect(c.line(en), 'Open it.');

    c.clearReport();
    expect(c.line(en), 'Open it.', reason: 'nothing to clear is a no-op');
  });

  test('reset starts over', () {
    final c = coach()
      ..did('add')
      ..did('open')
      ..say((_) => 'Said.');
    c.reset();
    expect(c.line(en), 'Add one.');
    expect(c.report(en), isNull);
  });

  test('advanced: a done or skipped step, never a report; reset clears it', () {
    final c = coach();
    expect(c.advanced, isFalse);
    c.say((_) => 'Said.');
    expect(c.advanced, isFalse);
    c.skip();
    expect(c.advanced, isFalse, reason: 'the skip only cleared the report');
    c.skip();
    expect(c.advanced, isTrue);
    c.reset();
    expect(c.advanced, isFalse);
    c.did('open');
    expect(c.advanced, isTrue);
  });

  test('a closing line of its own ends the coach and joins the candidates', () {
    final c = GuideCoach([
      GuideCoachStep('add', (_) => 'Add one.'),
    ], closing: (_) => 'That is all.');
    c.did('add');
    expect(c.line(en), 'That is all.');
    expect(c.candidates(en, const []), ['Add one.', 'That is all.']);
  });

  test('candidates: the instructions, the closing line and each report '
      'alone', () {
    final lines = coach().candidates(en, ['A.', 'B.', 'Open it.']);
    expect(lines, [
      'Add one.',
      'Open it.',
      'Delete it.',
      en.calendarGuideCoachDone,
      'A.',
      'B.',
    ]);
  });
}
