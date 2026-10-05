import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `AndroidAlertGateway` keeps the rings in progress in two maps, and reads a
/// ring's ending off them. A ring that leaves the plugin's ringing set while
/// its id is still tracked ended behind the app's back — Stop on the
/// notification — and is settled as the user's answer: the session chip, and
/// the removal of an event set to go after its alarm. So every path of the
/// app's own that ends a ring has to take the id out **before** it asks the
/// plugin to stop, and `cancel` did not: cancelling an id that was ringing
/// was settled as an acknowledgement nobody made, and a stop that threw left
/// the id counted as ringing for the life of the process, which holds every
/// destination but an alarm page in the navigation queue.
///
/// Two more rules hang off the same lines. A ring `cancel` takes out is
/// reported as **cancelled** — the alarm page closes on it and nothing is
/// settled — and never for an id that was not ringing. And an id the binding
/// is itself stopping is **not announced again**: when a stop lets a queued
/// alarm through, the plugin tells of the new ring while the stopped one is
/// still in its set, and that one, tracked afresh, ended as a dismissal — a
/// Snooze on the alarm page lost the snooze it had just armed.
///
/// The class cannot be built off a device (`AlertAvailability` keeps it out
/// of every suite), and an order of statements is not something a pure piece
/// hoisted out of it would hold either. So the order is read here, as text.
void main() {
  final gateway = File(
    'lib/services/android_alert_gateway.dart',
  ).readAsStringSync();

  /// One method of the binding, whole: from its signature to the first brace
  /// that closes at a member's own indent.
  String methodOf(String signature) {
    final method = RegExp(
      '${RegExp.escape(signature)}[\\s\\S]*?^  \\}',
      multiLine: true,
    ).stringMatch(gateway);
    expect(method, isNotNull, reason: signature);
    return method!;
  }

  /// Where [method] first asks a backend to drop the entry: the `alarm`
  /// plugin is asked first, the notifications plugin after it.
  int firstAskOf(String method) {
    final alarm = method.indexOf('await Alarm.stop(osId);');
    final notifications = method.indexOf('await _plugin.cancel(id: osId);');
    expect(alarm, isNonNegative);
    expect(notifications, greaterThan(alarm));
    return alarm;
  }

  const cancel = 'Future<void> cancel(int osId) async {';
  const stopRinging = 'Future<void> stopRinging(int osId) async {';
  const handleRinging = 'void _handleRinging(AlarmSet set) {';

  /// What ends the app's own tracking of a ring: its silence timer, which
  /// would otherwise stop whatever holds the id by then, and the two maps.
  const takenOut = [
    '_silenceTimers.remove(osId)?.cancel();',
    '_pluginRings.remove(osId);',
    '_rings.remove(osId)',
  ];

  test('a ring that leaves the plugin\'s set is an answer only while its id '
      'is tracked, and holds navigation back only while it is', () {
    // The two readings the order below exists for.
    expect(
      methodOf(handleRinging),
      contains('for (final osId in _pluginRings.toList()) {'),
    );
    expect(
      gateway,
      contains(
        'Set<int> get ringingIds => Set<int>.unmodifiable(_rings.keys);',
      ),
    );
  });

  group('cancel', () {
    test('takes the id off its silence timer and out of both ring maps '
        'before either backend is asked', () {
      final method = methodOf(cancel);
      final firstAsk = firstAskOf(method);

      for (final removal in takenOut) {
        final at = method.indexOf(removal);

        expect(at, isNonNegative, reason: removal);
        expect(at, lessThan(firstAsk), reason: removal);
      }
    });

    test('lowers the keyguard flag when that took the last ring out, and '
        'not for an id that was never ringing', () {
      // A reconcile cancels up to 48 entries that are not ringing; only the
      // one that was, and was the last, has a flag to lower.
      final method = methodOf(cancel);
      final lowered = RegExp(
        r'final ring = _rings\.remove\(osId\);\s*'
        r'if \(ring != null && _rings\.isEmpty\) \{\s*'
        r'unawaited\(_showOverKeyguard\(false\)\);\s*\}',
      ).firstMatch(method);

      expect(lowered, isNotNull);
      expect(lowered!.start, lessThan(firstAskOf(method)));
    });

    test('reports the ring it took out as cancelled, once both backends '
        'have been asked, and nothing for an id that was not ringing', () {
      final method = methodOf(cancel);
      final reported = RegExp(
        r'if \(ring != null && !_ringEnded\.isClosed\) \{\s*'
        r'_ringEnded\.add\(\(payload: ring, '
        r'cause: AlertRingEndCause\.cancelled\)\);\s*\}',
      ).firstMatch(method);

      expect(reported, isNotNull);
      // The ring is over when it is said to be: the alarm page closes on
      // this, and a page that left first would leave the phone ringing
      // behind it.
      expect(
        reported!.start,
        greaterThan(method.indexOf('await _plugin.cancel(id: osId);')),
      );
      // And it is cancel's word alone. A cancelled ring told as a dismissal
      // is the acknowledgement nobody made, back again.
      expect('AlertRingEndCause.cancelled'.allMatches(gateway), hasLength(1));
      expect(method, isNot(contains('AlertRingEndCause.dismissed')));
    });
  });

  test('stopRinging, whose order cancel follows, takes the id out first '
      'too', () {
    final method = methodOf(stopRinging);
    final firstAsk = firstAskOf(method);

    for (final removal in takenOut) {
      final at = method.indexOf(removal);

      expect(at, isNonNegative, reason: removal);
      expect(at, lessThan(firstAsk), reason: removal);
    }
  });

  group('an id the binding is itself stopping', () {
    // Held from before the plugin is asked until its answer is back, thrown
    // or not: an id left behind would never be announced again, and the id
    // of a snooze is the one its next snooze is armed under.
    final held = RegExp(
      r'_stopping\.add\(osId\);\s*'
      r'try \{\s*await Alarm\.stop\(osId\);\s*\}'
      r' catch \(e\) \{[^}]*\}'
      r' finally \{\s*_stopping\.remove\(osId\);\s*\}',
    );

    for (final (name, signature) in [
      ('cancel', cancel),
      ('stopRinging', stopRinging),
    ]) {
      test('is held as one for exactly as long as $name\'s stop is out', () {
        expect(held.hasMatch(methodOf(signature)), isTrue);
      });
    }

    test('is not announced again by a ringing set that still lists it', () {
      final method = methodOf(handleRinging);
      final announcing = method.indexOf('for (final alarm in set.alarms) {');
      final skipped = method.indexOf(
        'if (_stopping.contains(alarm.id)) continue;',
      );
      final tracked = method.indexOf('_pluginRings.add(alarm.id);');

      expect(announcing, isNonNegative);
      expect(skipped, greaterThan(announcing));
      // Before it is tracked as the plugin's, or the next emission would end
      // it as a Stop on the notification all the same.
      expect(tracked, greaterThan(skipped));
    });

    test('changes nothing else of the ring handling', () {
      // The ending loop reads endings as it did, the launch lookup announces
      // what it finds, and the emit-once guard is the same: the two stop
      // paths fill the set and the announce loop alone reads it.
      final ending = methodOf(handleRinging);

      expect(
        ending.substring(
          0,
          ending.indexOf('for (final alarm in set.alarms) {'),
        ),
        isNot(contains('_stopping')),
      );
      for (final untouched in [
        'Future<void> _reportRingsInProgress() async {',
        'void _emitRing(AlertPayload payload) {',
        'bool _trackRing(AlertPayload payload) {',
        'void _endRing(int osId, AlertRingEndCause cause) {',
      ]) {
        expect(
          methodOf(untouched),
          isNot(contains('_stopping')),
          reason: untouched,
        );
      }
      expect('_stopping.contains('.allMatches(gateway), hasLength(1));
      expect('_stopping.add('.allMatches(gateway), hasLength(2));
      expect('_stopping.remove('.allMatches(gateway), hasLength(2));
    });
  });
}
