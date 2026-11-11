import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/interrupt.dart';

void main() {
  group('a Ctrl+C on a pass', () {
    late List<String> steps;
    late List<String> said;

    PassInterrupt handler({
      String? quietSkipped,
      Future<void> Function()? leaveQuiet,
      void Function()? writePartial,
      Duration quietLimit = interruptQuietLimit,
    }) => PassInterrupt(
      writePartial: writePartial ?? () => steps.add('report'),
      leaveQuiet: leaveQuiet ?? () async => steps.add('quiet'),
      quietSkipped: () => quietSkipped,
      release: () => steps.add('release'),
      say: said.add,
      quietLimit: quietLimit,
    );

    setUp(() {
      steps = [];
      said = [];
    });

    test(
      'writes the report, leaves the device quiet, releases, exits 130',
      () async {
        expect(await handler().handle(), exitInterrupted);
        expect(exitInterrupted, 130);
        expect(steps, ['report', 'quiet', 'release']);
        expect(said.first, 'interrupted — writing the report as it stands');
      },
    );

    test('skips the quiet end where a finished pass would skip it', () async {
      expect(
        await handler(quietSkipped: '--keep-state').handle(),
        exitInterrupted,
      );
      expect(steps, ['report', 'release']);
      expect(said, contains('quiet relaunch skipped: --keep-state'));
    });

    test('gives the quiet end fifteen seconds and no more', () async {
      expect(interruptQuietLimit, const Duration(seconds: 15));
      final never = Completer<void>();
      final code = await handler(
        leaveQuiet: () => never.future,
        quietLimit: const Duration(milliseconds: 20),
      ).handle();
      expect(code, exitInterrupted);
      expect(steps, [
        'report',
        'release',
      ], reason: 'the hold is released all the same');
      expect(said.last, startsWith('the quiet end did not finish within 0 s'));
    });

    test('a step that throws never keeps the next from running', () async {
      final code = await handler(
        writePartial: () => throw StateError('disk full'),
        leaveQuiet: () async => throw StateError('adb gone'),
      ).handle();
      expect(code, exitInterrupted);
      expect(steps, ['release']);
      expect(
        said,
        contains('the report could not be written: Bad state: disk full'),
      );
      expect(said, contains('the quiet end failed: Bad state: adb gone'));
    });
  });

  group('a Ctrl+C on a fleet pass', () {
    test('waits for its shards to end, then exits 130', () async {
      final said = <String>[];
      final shards = Completer<void>();
      final waited = awaitShardsOnInterrupt(
        shards.future,
        say: said.add,
        limit: const Duration(seconds: 5),
      );
      shards.complete();
      expect(await waited, exitInterrupted);
      expect(
        said.single,
        startsWith('interrupted — waiting up to 5 s for the shards'),
      );
    });

    test('gives its shards twenty seconds and no more', () async {
      expect(interruptShardWait, const Duration(seconds: 20));
      final said = <String>[];
      final code = await awaitShardsOnInterrupt(
        Completer<void>().future,
        say: said.add,
        limit: const Duration(milliseconds: 20),
      );
      expect(code, exitInterrupted);
      expect(said.last, 'the shards did not end within 0 s');
    });
  });
}
