import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A ring's Silence-after window counts the time the `alarm` host sounds it.
///
/// The host rings one alarm at a time and holds one that comes due during
/// another, silent, until that one ends — and the plugin's fallback timer
/// tells the app of the held alarm at its own instant anyway (the fork's
/// Patch 7 keeps that, with the app in front), so the binding tracks it from
/// then. Its window used to start there too. Two alarms due a minute apart,
/// nobody answering: the first was silenced when its window ran out, the
/// host promoted the second, and the binding silenced that one a minute
/// later, when what was left of its own window ran out — settled as timed
/// out, a Missed for an alarm that had sounded for a minute.
///
/// So the binding asks the host before it starts a window and before it
/// ends one: a held ring waits, unwindowed, and is asked after again at
/// every change to the ringing set — the ending in front of it, the host's
/// report of the ring it promotes. What the answers mean is
/// `alertSilenceWindowRuns`, pinned with the binding's other pure pieces in
/// `test/services/android_alert_gateway_test.dart`. The class cannot be
/// built off a device, so the order is read here, as text, the way
/// `alert_ring_maps_test.dart` reads the ring maps.
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

  const silence = 'Future<void> _silence(int osId) async {';
  const arm = 'Future<void> _armSilenceTimer(int osId) async {';
  const ask = 'Future<bool> _silenceWindowRuns(int osId) async {';
  const handleRinging = 'void _handleRinging(AlarmSet set) {';
  const asks = 'await _silenceWindowRuns(osId);';

  test('a window that runs out stops a ring only once the host says it was '
      'the one sounding', () {
    final method = methodOf(silence);
    final asked = method.indexOf(asks);
    final stopped = method.indexOf('await stopRinging(osId);');

    expect(asked, isNonNegative);
    expect(stopped, greaterThan(asked));
    // Held behind another ring: its window starts again, and nothing is
    // stopped — a stop here would end a ring nobody has heard yet.
    final held = RegExp(
      r'if \(!runs\) \{\s*unawaited\(_armSilenceTimer\(osId\)\);\s*'
      r'return;\s*\}',
    ).firstMatch(method);
    expect(held, isNotNull);
    expect(held!.start, greaterThan(asked));
    expect(held.end, lessThan(stopped));
  });

  test('a window starts only once the host sounds the ring', () {
    final method = methodOf(arm);
    final asked = method.indexOf(asks);
    final started = method.indexOf('_silenceTimers[osId] = Timer(');

    expect(asked, isNonNegative);
    expect(started, greaterThan(asked));
    final held = RegExp(
      r'if \(!runs\) \{\s*_heldRings\.add\(osId\);[\s\S]*?return;\s*\}',
    ).firstMatch(method);
    expect(held, isNotNull);
    expect(held!.end, lessThan(started));
  });

  test('a held answer is asked again when the ringing set changed while the '
      'host was being asked', () {
    // An emission handled then found no mark, so it asked nothing — and
    // what it told of, the ring in front ending with nothing promoted, can
    // be exactly what the answer missed. Every emission after the mark asks
    // by itself.
    final method = methodOf(arm);
    final before = method.indexOf('final emissionsBefore = _ringingEmissions;');
    final again = RegExp(
      r'_heldRings\.add\(osId\);[\s\S]*?'
      r'if \(_ringingEmissions != emissionsBefore\) \{\s*'
      r'unawaited\(_armSilenceTimer\(osId\)\);\s*\}\s*return;',
    ).firstMatch(method);

    expect(before, isNonNegative);
    expect(before, lessThan(method.indexOf(asks)));
    expect(again, isNotNull);
    // Counted first thing, so no emission goes uncounted.
    expect(
      RegExp(
        '${RegExp.escape(handleRinging)}\\s*_ringingEmissions\\+\\+;',
      ).hasMatch(gateway),
      isTrue,
    );
  });

  test('a held ring is asked after again at every change to the ringing '
      'set', () {
    final method = methodOf(handleRinging);
    final announcing = method.indexOf('for (final alarm in set.alarms) {');
    final again = RegExp(
      r'for \(final osId in _heldRings\.toList\(\)\) \{\s*'
      r'unawaited\(_armSilenceTimer\(osId\)\);\s*\}',
    ).firstMatch(method);

    expect(announcing, isNonNegative);
    expect(again, isNotNull);
    // After the set has been read, so a ring announced by this emission is
    // tracked before anything asks after it.
    expect(again!.start, greaterThan(announcing));
  });

  test("the host is asked — never the plugin's ringing set, which holds the "
      'announced ring too — and only of a ring the plugin reported', () {
    final method = methodOf(ask);
    final pluginOnly = method.indexOf(
      'if (!_pluginRings.contains(osId)) return true;',
    );
    final thisRing = method.indexOf('isRinging(osId)');
    final anyRing = method.indexOf('isRinging()');

    expect(pluginOnly, isNonNegative);
    expect(thisRing, greaterThan(pluginOnly));
    expect(method, contains('AndroidAlarm()'));
    expect(anyRing, isNonNegative);
    // Anything first, this ring second: a promotion between the two reads
    // then reads as sounding. The other way round it read as held, and the
    // emissions it made were handled before the mark existed — a held ring
    // sounding with no window, until somebody stopped it.
    expect(anyRing, lessThan(thisRing));
    expect(method, contains('alertSilenceWindowRuns('));
    expect(method, isNot(contains('Alarm.isRinging(')));
    // A host that cannot answer leaves the window running, as it ran before
    // anything asked: nothing can wait on an answer that never comes.
    expect(
      RegExp(r'catch \(e\) \{[^}]*return true;\s*\}').hasMatch(method),
      isTrue,
    );
  });

  test('every path that ends a ring ends its wait with its timer', () {
    for (final signature in [
      'Future<void> cancel(int osId) async {',
      'Future<void> stopRinging(int osId) async {',
      'void _endRing(int osId, AlertRingEndCause cause) {',
    ]) {
      final method = methodOf(signature);

      expect(
        method,
        contains('_silenceTimers.remove(osId)?.cancel();'),
        reason: signature,
      );
      expect(method, contains('_heldRings.remove(osId);'), reason: signature);
    }
  });
}
