import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/alert_gateway.dart';

/// What the app owes a ring that ended outside the alarm page is decided in
/// one method of the app root, `_settleEndedRing`, by the cause the gateway
/// reports — and getting one cause wrong is silent and destructive: a
/// cancelled entry read as a dismissal posted the session chip and deleted an
/// event set to go after its alarm, with nobody answering.
///
/// No test pumps the app root (`main.dart` brings up Firebase, the database
/// and every app-wide bloc), and the method reaches the scheduler through
/// statics. The compiler holds the first half — the switch has no default, so
/// a new cause does not build until it has an arm — and what each arm then
/// does is pinned here, as text, like the rest of the root's wiring
/// (`test/widgets/keyboard_inset_wiring_test.dart`).
void main() {
  final source = File('lib/main.dart').readAsStringSync();

  String settle() {
    final method = RegExp(
      r'Future<void> _settleEndedRing\(AlertRingEnd end\) async \{'
      r'[\s\S]*?^  \}',
      multiLine: true,
    ).stringMatch(source);
    expect(method, isNotNull);
    return method!;
  }

  /// One arm of the switch without its comments: from its `case` to the next
  /// one, or to the end of the method.
  String armOf(AlertRingEndCause cause) {
    final method = settle();
    final from = method.indexOf('case AlertRingEndCause.${cause.name}:');
    expect(from, isNonNegative, reason: cause.name);
    final next = method.indexOf('case AlertRingEndCause.', from + 1);
    return method
        .substring(from, next < 0 ? method.length : next)
        .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
  }

  /// What an arm runs: its text under the `case` label, without the braces
  /// that close the switch and the method behind the last one.
  String bodyOf(AlertRingEndCause cause) => armOf(cause)
      .substring('case AlertRingEndCause.${cause.name}:'.length)
      .replaceAll('}', '')
      .trim();

  test('every cause has an arm of its own, and there is no default to fall '
      'into', () {
    final method = settle();

    expect(method, contains('switch (end.cause) {'));
    expect(method, isNot(contains('default:')));
    for (final cause in AlertRingEndCause.values) {
      expect(
        'case AlertRingEndCause.${cause.name}:'.allMatches(method),
        hasLength(1),
        reason: cause.name,
      );
      // A `case` with nothing under it runs the body of the next one, and the
      // compiler lets it: a bare label set above `dismissed` settles its
      // cause as a Stop, while every "this arm does not" below holds of its
      // empty text.
      expect(bodyOf(cause), isNotEmpty, reason: cause.name);
    }
  });

  test('an entry cancelled while it rang settles nothing', () {
    // No acknowledgement, no session chip, no removal, no Missed, no
    // registry write and no reconcile: whoever cancelled has done its own.
    final arm = armOf(AlertRingEndCause.cancelled);

    // A statement of its own, so that nothing is what the arm runs rather
    // than what the arm under it does.
    expect(arm, contains('break;'));
    expect(arm, isNot(contains('await')));
    expect(arm, isNot(contains('AlertScheduler')));
    expect(arm, isNot(contains('AlertAcknowledgement')));
    expect(arm, isNot(contains('SessionChip')));
  });

  test('only a Stop on the notification is an acknowledgement', () {
    for (final cause in AlertRingEndCause.values) {
      expect(
        armOf(cause).contains('AlertAcknowledgement.apply('),
        cause == AlertRingEndCause.dismissed,
        reason: cause.name,
      );
    }
    expect(armOf(AlertRingEndCause.dismissed), contains('answered: true'));
    expect(armOf(AlertRingEndCause.timedOut), contains('answered: false'));
    // A native Snooze is written down by the reconcile, never settled.
    expect(
      armOf(AlertRingEndCause.snoozed),
      isNot(contains('settleEndedRingByPayload')),
    );
  });

  test('what a ring held back is routed after every ending, whatever it '
      'settled', () {
    // Outside the switch: a cancelled ring settles nothing and still frees
    // the intents that waited behind it.
    expect(
      source,
      matches(
        RegExp(
          r'gateway\.ringEnded\.listen\(\(end\) \{\s*'
          r'unawaited\(_settleEndedRing\(end\)\);\s*'
          r'(?://[^\n]*\s*)*'
          r'_scheduleNavigationDrain\(\);\s*\}\);',
        ),
      ),
    );
  });
}
