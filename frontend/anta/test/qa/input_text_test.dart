import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/input_text.dart';

void main() {
  group('escapeForInputText', () {
    test('substitutes spaces with %s inside single quotes', () {
      expect(escapeForInputText('bench press'), "'bench%spress'");
    });

    test('single-quotes a plain word', () {
      expect(escapeForInputText('squat'), "'squat'");
    });

    test('keeps the shell metacharacters the device sh would eat', () {
      const cases = <String, String>{
        '#tag': "'#tag'",
        'a&b': "'a&b'",
        r'a$b': r"'a$b'",
        'a`b': "'a`b'",
        'f(x)': "'f(x)'",
        'a|b': "'a|b'",
        'a;b': "'a;b'",
        'a<b>c': "'a<b>c'",
        'a*b': "'a*b'",
        '~home': "'~home'",
        'say "hi"': "'say%s\"hi\"'",
        r'100% \ done': r"'100%%s\%sdone'",
      };
      cases.forEach((input, expected) {
        expect(escapeForInputText(input), expected, reason: input);
      });
    });

    test('closes, escapes and reopens an embedded single quote', () {
      expect(escapeForInputText("it's"), r"'it'\''s'");
      expect(escapeForInputText("a 'b' c"), r"'a%s'\''b'\''%sc'");
    });

    test('rejects non-ASCII and points at the Flutter Driver path', () {
      for (final text in ['ăsta', 'grün', 'naïve', 'emoji 🙂']) {
        expect(
          () => escapeForInputText(text),
          throwsA(isA<UsageFailure>()
              .having((e) => e.message, 'message', contains('ASCII only'))
              .having((e) => e.message, 'message', contains('enter_text'))),
          reason: text,
        );
      }
    });

    test('rejects a line break and names the key verb instead', () {
      expect(
        () => escapeForInputText('one\ntwo'),
        throwsA(isA<UsageFailure>()
            .having((e) => e.message, 'message', contains('key enter'))),
      );
    });

    test('rejects a tab and names the key verb instead', () {
      expect(
        () => escapeForInputText('one\ttwo'),
        throwsA(isA<UsageFailure>()
            .having((e) => e.message, 'message', contains('key tab'))),
      );
    });

    test('rejects an empty string', () {
      expect(() => escapeForInputText(''), throwsA(isA<UsageFailure>()));
    });

    test('a usage failure carries exit code 1', () {
      expect(
        () => escapeForInputText('ă'),
        throwsA(isA<UsageFailure>().having((e) => e.code, 'code', exitUsage)),
      );
    });
  });

  group('shellSingleQuote', () {
    test('wraps and escapes', () {
      expect(shellSingleQuote('plain'), "'plain'");
      expect(shellSingleQuote("o'clock"), r"'o'\''clock'");
      expect(shellSingleQuote(''), "''");
    });
  });

  group('resolveKeycode', () {
    test('maps the friendly names', () {
      expect(resolveKeycode('back'), 'KEYCODE_BACK');
      expect(resolveKeycode('HOME'), 'KEYCODE_HOME');
      expect(resolveKeycode('enter'), 'KEYCODE_ENTER');
      expect(resolveKeycode('del'), 'KEYCODE_DEL');
      expect(resolveKeycode('tab'), 'KEYCODE_TAB');
      expect(resolveKeycode('esc'), 'KEYCODE_ESCAPE');
    });

    test('passes a raw keycode through', () {
      expect(resolveKeycode('KEYCODE_MEDIA_PLAY'), 'KEYCODE_MEDIA_PLAY');
      expect(resolveKeycode('66'), '66');
    });

    test('rejects an unknown name', () {
      expect(() => resolveKeycode('wiggle'), throwsA(isA<UsageFailure>()));
      expect(() => resolveKeycode(''), throwsA(isA<UsageFailure>()));
    });
  });
}
