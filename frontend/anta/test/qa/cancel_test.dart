import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/cancel.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/poll.dart';
import '../../tool/qa/src/process_runner.dart';

void main() {
  group('a cancel token', () {
    test('follows its own async chain and nothing else', () async {
      final token = CancelToken();
      final inside = token.run(() async {
        await pause(const Duration(seconds: 5));
        return 'woke';
      });
      // Started beside it, outside its zone: never cancelled.
      final outside = pause(const Duration(milliseconds: 50));
      token.cancel('the flow ran past its ceiling');
      await expectLater(
        inside,
        throwsA(
          isA<Cancelled>().having(
            (e) => e.message,
            'message',
            'cancelled: the flow ran past its ceiling',
          ),
        ),
      );
      await outside;
      expect(CancelToken.current, isNull);
    });

    test('a child is cancelled with its parent, not the other way', () {
      final parent = CancelToken();
      final first = CancelToken(parent: parent);
      final second = CancelToken(parent: parent);
      first.cancel('ceiling');
      expect(parent.isCancelled, isFalse);
      expect(second.isCancelled, isFalse);
      parent.cancel('interrupted');
      expect(second.reason, 'interrupted');
      expect(first.reason, 'ceiling', reason: 'the first reason stands');
    });

    test('a cancelled call is a device failure, as every verb handles one', () {
      expect(Cancelled('x'), isA<DeviceFailure>());
      expect(Cancelled('x').code, exitDevice);
    });

    test('a poll stops at its next tick', () async {
      final token = CancelToken();
      var probes = 0;
      final polling = token.run(
        () => pollUntil<bool>(
          timeout: const Duration(seconds: 30),
          interval: const Duration(milliseconds: 20),
          probe: () {
            probes++;
            return null;
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 70));
      token.cancel('interrupted');
      final started = DateTime.now();
      await expectLater(polling, throwsA(isA<Cancelled>()));
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 1)),
      );
      final seen = probes;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(probes, seen, reason: 'nothing probes after the cancel');
    });

    test('work that fails after it was cancelled is dropped, not '
        'unhandled', () async {
      final token = CancelToken();
      final late = Completer<int>();
      final waiting = token.run(() => cancellable(late.future));
      token.cancel('ceiling');
      await expectLater(waiting, throwsA(isA<Cancelled>()));
      late.completeError(StateError('the socket closed'));
      await Future<void>.delayed(Duration.zero);
    });

    test('the process runner kills its child on cancel instead of waiting '
        'out its timeout, and starts none once cancelled', () async {
      final (executable, arguments) = Platform.isWindows
          ? ('ping', ['-n', '30', '127.0.0.1'])
          : ('sleep', ['30']);
      const runner = RealProcessRunner();
      final token = CancelToken();
      final started = DateTime.now();
      final running = token.run(
        () => runner.run(
          executable,
          arguments,
          timeout: const Duration(seconds: 60),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      token.cancel('the flow ran past its ceiling');
      await expectLater(running, throwsA(isA<Cancelled>()));
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 10)),
      );
      await expectLater(
        token.run(() => runner.run(executable, arguments)),
        throwsA(isA<Cancelled>()),
      );
    });
  });
}
