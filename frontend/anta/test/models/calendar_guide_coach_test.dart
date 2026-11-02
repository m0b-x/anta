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

  test('hasStep answers for the steps alone; hasDone for the done or '
      'skipped ones, until reset', () {
    final c = coach();
    expect(c.hasStep('open'), isTrue);
    expect(c.hasStep('menu'), isFalse);
    expect(c.hasDone('open'), isFalse);

    c
      ..did('open')
      ..skip();
    expect(c.hasDone('open'), isTrue);
    expect(c.hasDone('add'), isTrue, reason: 'skipped');
    expect(c.hasDone('delete'), isFalse);
    expect(c.hasDone('menu'), isFalse);

    c.reset();
    expect(c.hasDone('open'), isFalse);
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

  group('reading back (D70)', () {
    Set<String> doneOf(GuideCoach c) => {
      for (final step in c.steps)
        if (c.hasDone(step.action)) step.action,
    };

    test('back from the live line after two done steps shows step 1, then '
        'step 0, and stops there', () {
      final c = coach()
        ..did('add')
        ..did('open');
      expect(c.reading, isFalse);
      expect(c.viewed, isNull);
      expect(c.canBack, isTrue);

      c.back();
      expect(c.reading, isTrue);
      expect(c.viewed?.action, 'open');
      expect(c.line(en), 'Open it.');
      expect(c.canBack, isTrue);

      c.back();
      expect(c.viewed?.action, 'add');
      expect(c.line(en), 'Add one.');
      expect(c.canBack, isFalse);

      c.back();
      expect(c.viewed?.action, 'add', reason: 'nothing before the first');
    });

    test('canBack is off at the live line with nothing done, and back there '
        'is a no-op', () {
      final c = coach();
      expect(c.canBack, isFalse);
      c.back();
      expect(c.reading, isFalse);
      expect(c.line(en), 'Add one.');
    });

    test('only the steps before the live line read back: one done out of '
        'order past it is not reachable', () {
      final c = coach()..did('open');
      expect(c.current?.action, 'add');
      expect(c.canBack, isFalse);
    });

    test('forward walks back to the live line and then skips', () {
      final c = coach()
        ..did('add')
        ..did('open')
        ..back()
        ..back();
      expect(c.canForward, isTrue);

      c.forward();
      expect(c.viewed?.action, 'open');
      c.forward();
      expect(c.reading, isFalse, reason: 'past the last done step: live');
      expect(c.line(en), 'Delete it.');
      expect(doneOf(c), {'add', 'open'}, reason: 'returning skipped nothing');

      c.forward();
      expect(c.finished, isTrue, reason: 'at the live line forward skips');
      expect(c.canForward, isFalse);
      expect(c.line(en), en.calendarGuideCoachDone);
    });

    test('a finished tour reads back every step; forward is on while reading '
        'and the closing line is the live one', () {
      final c = coach()
        ..did('add')
        ..did('open')
        ..did('delete');
      expect(c.canForward, isFalse);
      c.back();
      expect(c.viewed?.action, 'delete');
      expect(c.canForward, isTrue);
      c.forward();
      expect(c.reading, isFalse);
      expect(c.line(en), en.calendarGuideCoachDone);
    });

    test('a standing report is never read back and returns with the live '
        'line', () {
      final c = coach()
        ..did('add')
        ..say((_) => 'Said.');
      c.back();
      expect(c.line(en), 'Add one.');
      c.forward();
      expect(c.line(en), 'Said.');
    });

    test('did, say, clearReport, skip and reset each snap back to the live '
        'line', () {
      GuideCoach reading() => coach()
        ..did('add')
        ..did('open')
        ..back();

      final viaDid = reading()..did('delete');
      expect(viaDid.reading, isFalse);
      expect(viaDid.line(en), en.calendarGuideCoachDone);

      final viaSay = reading()..say((_) => 'Said.');
      expect(viaSay.reading, isFalse);
      expect(viaSay.line(en), 'Said.');

      final viaClear = reading()..clearReport();
      expect(viaClear.reading, isFalse);
      expect(viaClear.line(en), 'Delete it.');

      final viaSkip = reading()..skip();
      expect(viaSkip.reading, isFalse);
      expect(viaSkip.finished, isTrue);

      final viaReset = reading()..reset();
      expect(viaReset.reading, isFalse);
      expect(viaReset.line(en), 'Add one.');
    });

    test('reading never changes the done set', () {
      final c = coach()
        ..did('add')
        ..did('open');
      c
        ..back()
        ..back()
        ..back()
        ..forward();
      expect(doneOf(c), {'add', 'open'});
      expect(c.current?.action, 'delete');
      expect(c.advanced, isTrue);
    });
  });
}
