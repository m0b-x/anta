import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/alert_sound.dart';

/// The codec every alarm sound crosses a boundary through — a nullable column,
/// a settings row, a backup archive and a sync payload.
///
/// Two properties carry the whole design and are what these tests are for.
/// **Total**: there is no input that throws and none that produces silence, so
/// a URI written by another phone — which is every picked sound after a
/// restore — degrades to the one sound that is always there. And **the null /
/// empty distinction is real**: `null` is an alert deferring to the app
/// setting, `''` is an alert insisting on the bundled sound, and collapsing the
/// two would make "ANTA sound" unrepresentable on an alert whose setting says
/// something else.
void main() {
  group('decode', () {
    test('the four values it is allowed to store round-trip', () {
      const cases = <String?, Type>{
        null: AlertSoundInherit,
        '': AlertSoundBundled,
        'system:default': AlertSoundSystemDefault,
        'content://media/external/audio/media/42': AlertSoundUri,
        'content://settings/system/alarm_alert': AlertSoundUri,
        'file:///storage/emulated/0/Music/wake.mp3': AlertSoundUri,
      };

      for (final entry in cases.entries) {
        final decoded = AlertSound.decode(entry.key);
        expect(
          decoded.runtimeType,
          entry.value,
          reason: '${entry.key} decoded as $decoded',
        );
        expect(
          decoded.stored,
          entry.key,
          reason: 'a decode that cannot be written back is not a codec',
        );
      }
    });

    test('everything unreadable is the bundled sound, never an exception', () {
      const garbage = <String>[
        'nonsense',
        ' ',
        'default',
        'system:',
        // The reserved scheme is the app's own literal namespace; a value that
        // borrows it and says something else is not a URI to hand the phone.
        'system:whatever',
        'content:',
        '://media/1',
        '{"sound":"x"}',
        '42',
      ];

      for (final raw in garbage) {
        expect(
          AlertSound.decode(raw),
          isA<AlertSoundBundled>(),
          reason: '"$raw" should degrade to the app default',
        );
      }
    });

    test('a URI is kept verbatim, not normalised', () {
      // The value is handed straight back to the phone's own ContentResolver,
      // so re-spelling it — case, trailing slash — is how it stops resolving.
      const raw = 'content://Media/External/Audio/Media/7';

      expect((AlertSound.decode(raw) as AlertSoundUri).uri, raw);
      expect(AlertSound.decode(raw).stored, raw);
    });

    test('only a picked sound needs the device that picked it', () {
      expect(AlertSound.decode(null).needsDevice, isFalse);
      expect(AlertSound.decode('').needsDevice, isFalse);
      expect(AlertSound.decode('system:default').needsDevice, isFalse);
      expect(AlertSound.decode('content://media/1').needsDevice, isTrue);
    });
  });

  group('resolve', () {
    test('the alert wins, then the setting, then the bundled sound', () {
      // The alert chose: the setting is not consulted at all.
      expect(
        AlertSound.resolve(alert: 'system:default', setting: 'content://a/1'),
        isA<AlertSoundSystemDefault>(),
      );
      expect(
        AlertSound.resolve(alert: '', setting: 'system:default'),
        isA<AlertSoundBundled>(),
        reason:
            '"" on an alert is "the ANTA sound whatever the setting says" — '
            'the whole reason the column is nullable',
      );
      // The alert deferred: the setting answers.
      expect(
        AlertSound.resolve(alert: null, setting: 'system:default'),
        isA<AlertSoundSystemDefault>(),
      );
      expect(
        AlertSound.resolve(alert: null, setting: 'content://media/9'),
        const AlertSoundUri('content://media/9'),
      );
      // Neither said anything.
      expect(
        AlertSound.resolve(alert: null, setting: ''),
        isA<AlertSoundBundled>(),
      );
    });

    test('it never answers "follow the setting"', () {
      // Inherit is a thing an alert stores, never a thing the platform can be
      // handed — a gateway that received one would have no sound at all.
      for (final setting in <String>['', 'system:default', 'content://a/1']) {
        expect(
          AlertSound.resolve(alert: null, setting: setting),
          isNot(isA<AlertSoundInherit>()),
        );
      }
      expect(
        AlertSound.resolve(alert: 'garbage', setting: 'garbage'),
        isA<AlertSoundBundled>(),
      );
    });
  });
}
