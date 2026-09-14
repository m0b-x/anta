import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/adb.dart';
import '../../tool/qa/src/process_runner.dart';
import '../../tool/qa/src/shell_batch.dart';
import 'fake_process_runner.dart';

void main() {
  group('buildBatchScript', () {
    test('quotes every token of an argument vector', () {
      expect(
        buildBatchScript(const [
          ShellCommand(['pidof', 'com.alexzamfir.anta']),
        ]),
        "'pidof' 'com.alexzamfir.anta'; echo __QA_SEP__",
      );
    });

    test('leaves a raw fragment alone so pipes stay pipes', () {
      expect(
        buildBatchScript(const [
          ShellCommand.raw('dumpsys power 2>/dev/null | grep -m1 mWakefulness'),
        ]),
        'dumpsys power 2>/dev/null | grep -m1 mWakefulness; echo __QA_SEP__',
      );
    });

    test('separates every command, including the last', () {
      final script = buildBatchScript(const [
        ShellCommand(['wm', 'size']),
        ShellCommand(['wm', 'density']),
      ]);
      expect('; '.allMatches(script).length, 3);
      expect(script.split('echo __QA_SEP__').length, 3);
    });

    test('an embedded quote cannot break out of the argument', () {
      final script = buildBatchScript(const [
        ShellCommand(['echo', "it's"]),
      ]);
      expect(script, contains(r"'it'\''s'"));
    });
  });

  group('splitBatchOutput', () {
    test('splits on the separator line and trims each chunk', () {
      final chunks = splitBatchOutput(
        'Physical size: 1280x2856\n__QA_SEP__\nPhysical density: 480\n'
        '__QA_SEP__\n',
        2,
      );
      expect(chunks, ['Physical size: 1280x2856', 'Physical density: 480']);
    });

    test('keeps an empty answer as an empty string, not a missing slot', () {
      final chunks = splitBatchOutput('__QA_SEP__\n7788\n__QA_SEP__\n', 2);
      expect(chunks, ['', '7788']);
    });

    test('keeps multi-line output inside its own chunk', () {
      final chunks = splitBatchOutput('a\nb\n__QA_SEP__\nc\n__QA_SEP__\n', 2);
      expect(chunks, ['a\nb', 'c']);
    });

    test('pads when the shell died half way', () {
      expect(splitBatchOutput('only\n__QA_SEP__\n', 3), ['only', '', '']);
    });

    test('ignores whitespace around the separator', () {
      expect(
        splitBatchOutput('x\n  __QA_SEP__  \ny\n\t__QA_SEP__\n', 2),
        ['x', 'y'],
      );
    });
  });

  group('Adb.shellBatch', () {
    test('is one adb invocation carrying the whole script', () async {
      final fake = FakeProcessRunner(
        defaultOutcome:
            const RunOutcome(0, 'one\n__QA_SEP__\ntwo\n__QA_SEP__\n', ''),
      );
      final adb =
          Adb(executable: 'adb', runner: fake, serial: 'emulator-5554');
      final outputs = await adb.shellBatch(const [
        ShellCommand(['echo', 'one']),
        ShellCommand(['echo', 'two']),
      ]);
      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.arguments.take(3).toList(),
          ['-s', 'emulator-5554', 'shell']);
      expect(fake.calls.single.arguments, hasLength(4));
      expect(outputs, ['one', 'two']);
    });

    test('an empty batch asks the device nothing', () async {
      final fake = FakeProcessRunner();
      final adb = Adb(executable: 'adb', runner: fake);
      expect(await adb.shellBatch(const []), isEmpty);
      expect(fake.calls, isEmpty);
    });

    test('a failing batch still hands back what the shell printed', () async {
      final fake = FakeProcessRunner(
        defaultOutcome: const RunOutcome(1, '', 'boom\n__QA_SEP__\n'),
      );
      final adb = Adb(executable: 'adb', runner: fake);
      expect(await adb.shellBatch(const [ShellCommand(['true'])]), ['boom']);
    });
  });
}
