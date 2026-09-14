import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/shell_words.dart';

void main() {
  group('splitShellWords', () {
    test('splits on whitespace', () {
      expect(splitShellWords('key back'), ['key', 'back']);
      expect(splitShellWords('  tap \t  Training '), ['tap', 'Training']);
    });

    test('double quotes group a label with spaces', () {
      expect(
        splitShellWords('tap "Search all notes"'),
        ['tap', 'Search all notes'],
      );
    });

    test('single quotes group too, and keep backslashes literal', () {
      expect(splitShellWords(r"type 'a\b'"), ['type', r'a\b']);
    });

    test('a backslash escapes the next character outside quotes', () {
      expect(splitShellWords(r'tap a\ b'), ['tap', 'a b']);
      expect(splitShellWords(r'type \"quoted\"'), ['type', '"quoted"']);
    });

    test('a backslash escapes inside double quotes', () {
      expect(splitShellWords(r'type "say \"hi\""'), ['type', 'say "hi"']);
    });

    test('quotes can sit inside a word', () {
      expect(splitShellWords('tap id:"search-open"'), ['tap', 'id:search-open']);
    });

    test('an empty quoted argument survives as an empty token', () {
      expect(splitShellWords('type ""'), ['type', '']);
    });

    test('an empty line has no tokens', () {
      expect(splitShellWords(''), isEmpty);
      expect(splitShellWords('   '), isEmpty);
    });

    test('an unbalanced quote is a usage failure, not a silent truncation', () {
      expect(() => splitShellWords('tap "Search'), throwsA(isA<UsageFailure>()));
      expect(() => splitShellWords("tap 'Search"), throwsA(isA<UsageFailure>()));
    });

    test('a dangling backslash is a usage failure', () {
      expect(() => splitShellWords('tap a\\'), throwsA(isA<UsageFailure>()));
    });

    test('an option after the target stays its own token', () {
      expect(
        splitShellWords('tap "All notes" --shot after --dump'),
        ['tap', 'All notes', '--shot', 'after', '--dump'],
      );
    });
  });

  group('parseStepLines', () {
    test('drops blank lines and # comments', () {
      expect(
        parseStepLines('# a flow\n\ntap "Training"\n\n  # nested comment\n'
            'key back\n'),
        ['tap "Training"', 'key back'],
      );
    });

    test('keeps a # that is not at the start of the line', () {
      expect(parseStepLines('type "a # b"'), ['type "a # b"']);
    });

    test('an all-comment file has no steps', () {
      expect(parseStepLines('# nothing\n#at all\n'), isEmpty);
    });
  });
}
