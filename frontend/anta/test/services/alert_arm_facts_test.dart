import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/services/android_alert_gateway.dart';

/// `AlertArmFacts` — what the app's pass leaves for a pass with no app
/// (`docs/cloud-shared-freshness.md` §6): the facts only its own engine can
/// read, spelled one way, and the token they arm under.
void main() {
  const facts = AlertArmFacts(
    volume: AlertRingVolume.floor,
    language: 'de',
    use24Hour: true,
    remindersGrouped: true,
    devicePixelRatio: 2.625,
  );

  test('what is stored reads back whole', () {
    final read = AlertArmFacts.tryDecode(facts.encode())!;

    expect(read.volume, AlertRingVolume.floor);
    expect(read.language, 'de');
    expect(read.use24Hour, isTrue);
    expect(read.remindersGrouped, isTrue);
    expect(read.devicePixelRatio, 2.625);
    expect(read.encode(), facts.encode());
  });

  test('the token is the one the app\'s own pass spells for the same '
      'facts, so adopting them re-arms nothing', () {
    final adopted = AlertArmFacts.tryDecode(facts.encode())!;

    expect(
      adopted.contextFor('alarm'),
      alertArmContext(
        backend: 'alarm',
        volume: AlertRingVolume.floor,
        language: 'de',
        use24Hour: true,
      ),
    );
  });

  test('what the app could not read stays unsaid, and equal facts are one '
      'spelling — an unchanged phone is an unchanged string', () {
    const bare = AlertArmFacts(
      volume: AlertRingVolume.follow,
      language: 'en',
      use24Hour: false,
    );

    final read = AlertArmFacts.tryDecode(bare.encode())!;
    expect(read.remindersGrouped, isNull);
    expect(read.devicePixelRatio, isNull);
    expect(
      bare.encode(),
      const AlertArmFacts(
        volume: AlertRingVolume.follow,
        language: 'en',
        use24Hour: false,
      ).encode(),
    );
    expect(bare.encode(), isNot(facts.encode()));
  });

  test('anything this build cannot read whole is no facts: another '
      'build\'s spelling, a volume it does not know, a missing clock', () {
    for (final stored in [
      '',
      'alarm@floor',
      '[]',
      '{"volume":"loud","language":"en","h24":true}',
      '{"volume":"follow","language":"","h24":true}',
      '{"volume":"follow","language":"en"}',
      '{"volume":"follow","language":"en","h24":true,"grouped":"yes"}',
      '{"volume":"follow","language":"en","h24":true,"dpr":"3"}',
    ]) {
      expect(AlertArmFacts.tryDecode(stored), isNull, reason: stored);
    }
  });
}
