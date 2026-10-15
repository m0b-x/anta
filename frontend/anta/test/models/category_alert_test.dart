import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_alerts.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/event_alert.dart';

/// [CategoryAlert] is the [EventAlert] row keyed by a category, so the codec
/// must decode exactly as the event alert's does, and [CategoryAlert.toEventAlert]
/// must hand the planner an alert it cannot tell from an own one except by
/// `categoryId`.
void main() {
  const full = CategoryAlert(
    id: 'c1',
    categoryId: 'birthday',
    mode: AlertMode.ring,
    offsetMinutes: 30,
    daysBefore: 2,
    dayMinute: 1200,
    sound: 'chime',
    enabled: false,
  );

  group('codec', () {
    test('round-trips every field', () {
      expect(CategoryAlert.fromJson(full.toJson()), full);
    });

    test('a null sound and a null day minute survive the trip', () {
      const bare = CategoryAlert(id: 'c1', categoryId: 'birthday');
      final decoded = CategoryAlert.fromJson(bare.toJson())!;
      expect(decoded.sound, isNull);
      expect(decoded.dayMinute, isNull);
      expect(decoded, bare);
    });

    test('missing identity is rejected, missing detail is not', () {
      expect(CategoryAlert.fromJson({EventAlertKeys.categoryId: 'b'}), isNull);
      expect(CategoryAlert.fromJson({EventAlertKeys.id: 'c1'}), isNull);
      expect(
        CategoryAlert.fromJson({
          EventAlertKeys.id: 'c1',
          EventAlertKeys.categoryId: '',
        }),
        isNull,
      );
      final minimal = CategoryAlert.fromJson({
        EventAlertKeys.id: 'c1',
        EventAlertKeys.categoryId: 'birthday',
      })!;
      expect(minimal.mode, AlertMode.notify);
      expect(minimal.enabled, isTrue);
    });

    test('an unknown mode decodes to the quieter tier', () {
      final decoded = CategoryAlert.fromJson({
        ...full.toJson(),
        EventAlertKeys.mode: 'siren',
      })!;
      expect(decoded.mode, AlertMode.notify);
    });

    test('negative offsets decode to zero and the day minute is clamped', () {
      final decoded = CategoryAlert.fromJson({
        ...full.toJson(),
        EventAlertKeys.offsetMinutes: -15,
        EventAlertKeys.daysBefore: -1,
        EventAlertKeys.dayMinute: 5000,
      })!;
      expect(decoded.offsetMinutes, 0);
      expect(decoded.daysBefore, 0);
      expect(decoded.dayMinute, EventAlert.minutesPerDay - 1);

      final early = CategoryAlert.fromJson({
        ...full.toJson(),
        EventAlertKeys.dayMinute: -3,
      })!;
      expect(early.dayMinute, 0);
    });

    test('carries the category, never an event', () {
      final json = full.toJson();
      expect(json[EventAlertKeys.categoryId], 'birthday');
      expect(json.containsKey(EventAlertKeys.eventId), isFalse);
    });
  });

  group('copyWith', () {
    test('clearSound and clearDayMinute beat a passed value', () {
      expect(full.copyWith(sound: 'bell', clearSound: true).sound, isNull);
      expect(
        full.copyWith(dayMinute: 60, clearDayMinute: true).dayMinute,
        isNull,
      );
    });

    test('an untouched field is carried over', () {
      final toggled = full.copyWith(enabled: true);
      expect(toggled.mode, AlertMode.ring);
      expect(toggled.sound, 'chime');
      expect(toggled.daysBefore, 2);
      expect(toggled.enabled, isTrue);
    });
  });

  group('toEventAlert', () {
    test('keeps the id, the timing, the sound and the switch', () {
      final projected = full.toEventAlert('e1');

      expect(projected.id, 'c1');
      expect(projected.eventId, 'e1');
      expect(projected.mode, AlertMode.ring);
      expect(projected.offsetMinutes, 30);
      expect(projected.daysBefore, 2);
      expect(projected.dayMinute, 1200);
      expect(projected.sound, 'chime');
      expect(projected.enabled, isFalse);
    });

    test('tags the projection with its category', () {
      final projected = full.toEventAlert('e1');
      expect(projected.categoryId, 'birthday');
      expect(
        projected,
        isNot(
          EventAlert(
            id: 'c1',
            eventId: 'e1',
            mode: AlertMode.ring,
            offsetMinutes: 30,
            daysBefore: 2,
            dayMinute: 1200,
            sound: 'chime',
            enabled: false,
          ),
        ),
        reason: 'an inherited alert must never compare equal to an own one',
      );
    });
  });
}
