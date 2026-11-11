import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/fleet.dart';
import '../../tool/qa/src/pass_report.dart';
import '../../tool/qa/src/recovery.dart';
import '../../tool/qa/src/suite.dart';

FlowFailure _failure(int exitCode, {int step = 3}) =>
    FlowFailure(step: step, line: 'tap id:x', exitCode: exitCode, message: 'm');

FleetMember _member(FleetState state, {bool qemu = true, String? heldBy}) =>
    FleetMember(
      index: 1,
      created: state != FleetState.notCreated,
      state: state,
      qemu: qemu
          ? const QemuProcess(pid: 4242, avd: 'anta_qa_1', port: 5556)
          : null,
      heldBy: heldBy,
    );

void main() {
  group('which failures are the fleet\'s', () {
    test('a ceiling, a seed that did not go in, a step that exited 3', () {
      expect(
        deviceFailureCause(
          _failure(exitTarget),
          ceiling: true,
          reseedFailed: false,
        ),
        'ceiling',
      );
      expect(
        deviceFailureCause(
          _failure(exitDevice, step: 0),
          ceiling: false,
          reseedFailed: true,
        ),
        'reseed',
      );
      expect(
        deviceFailureCause(
          _failure(exitDevice),
          ceiling: false,
          reseedFailed: false,
        ),
        'device',
      );
    });

    test(
      'a target not found, a usage error or a prelude red are the app\'s',
      () {
        for (final code in [exitTarget, exitUsage]) {
          expect(
            deviceFailureCause(
              _failure(code),
              ceiling: false,
              reseedFailed: false,
            ),
            isNull,
            reason: 'exit $code',
          );
        }
        expect(
          deviceFailureCause(
            _failure(exitTarget, step: 0),
            ceiling: false,
            reseedFailed: false,
          ),
          isNull,
        );
      },
    );
  });

  group('the probe', () {
    test('healthy only when on adb, booted, and its qemu runs', () {
      expect(guestTrouble(_member(FleetState.device)), isNull);
      expect(
        guestTrouble(_member(FleetState.stopped, qemu: false)),
        'not on adb',
      );
      expect(
        guestTrouble(_member(FleetState.booting)),
        'off adb or still booting',
      );
      expect(guestTrouble(_member(FleetState.offline)), 'offline');
      expect(
        guestTrouble(_member(FleetState.device, qemu: false)),
        'its qemu is gone',
      );
      expect(
        guestTrouble(_member(FleetState.device, heldBy: '"Pixel_9_Pro"')),
        'answers as "Pixel_9_Pro"',
      );
      expect(guestTrouble(null), 'not listed');
    });
  });

  group('the budget', () {
    test('once per flow: a second failure of the same flow is its own red', () {
      final budget = RecoveryBudget();
      expect(budget.refusal('01_a', ReseedMode.flow), isNull);
      budget.spend('01_a', ReseedMode.flow);
      final again = budget.refusal('01_a', ReseedMode.flow)!;
      expect(again.perFlow, isTrue);
      expect(budget.refusal('02_b', ReseedMode.flow), isNull);
    });

    test('twice per pass, then the pass stops on a further flow', () {
      final budget = RecoveryBudget()
        ..spend('01_a', ReseedMode.flow)
        ..spend('02_b', ReseedMode.flow);
      final spent = budget.refusal('03_c', ReseedMode.flow)!;
      expect(spent.perFlow, isFalse);
      expect(spent.reason, contains('budget is spent (2 per pass)'));
      final rerun = budget.refusal('02_b', ReseedMode.flow)!;
      expect(
        rerun.perFlow,
        isTrue,
        reason:
            'the flow\'s own allowance is checked first: a rerun that fails '
            'after the pass\'s last recovery is that flow\'s red (H8)',
      );
      expect(rerun.reason, '02_b already ran again once');
    });

    test('a reseed=suite suite restarts once', () {
      final budget = RecoveryBudget()..spend('02_b', ReseedMode.suite);
      final again = budget.refusal('03_c', ReseedMode.suite)!;
      expect(again.perFlow, isFalse);
      expect(again.reason, contains('already restarted once'));
    });

    test('what a recovery does under each reseed mode', () {
      expect(recoveryAction(ReseedMode.flow), 'rerun');
      expect(recoveryAction(ReseedMode.suite), 'restart suite');
      expect(recoveryAction(ReseedMode.none), 'stop');
    });
  });

  group('ceilings', () {
    test('the defaults', () {
      expect(defaultFlowCeiling, const Duration(seconds: 360));
      expect(defaultPassMinutes, 45);
    });

    test('seconds above 0, a fraction allowed', () {
      expect(parseCeilingSeconds('360'), const Duration(seconds: 360));
      expect(parseCeilingSeconds(' 0.25 '), const Duration(milliseconds: 250));
      for (final bad in ['0', '-1', '', 'x', 'Infinity', 'NaN']) {
        expect(parseCeilingSeconds(bad), isNull, reason: bad);
      }
    });

    test('the message says device failure and where the flow was', () {
      expect(
        ceilingMessage(const Duration(seconds: 360), 'step 4'),
        'device failure: the flow ran past its ceiling of 360 s (reseed, '
        'prelude and steps together) in step 4 — the device or the harness '
        'stopped answering',
      );
      expect(
        ceilingMessage(const Duration(milliseconds: 2500), 'its reseed'),
        contains('ceiling of 2.5 s'),
      );
    });
  });
}
