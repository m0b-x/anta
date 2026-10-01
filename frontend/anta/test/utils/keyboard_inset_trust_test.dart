import 'package:flutter_test/flutter_test.dart';

import 'package:anta/utils/keyboard_inset_trust.dart';

/// The rule under test is one sentence — with nothing focused the keyboard
/// inset may fall, never rise, and never rest above zero — and every case
/// here is either that sentence or one of the two things it must not break:
/// a real keyboard while a field is focused, and the falling frames of a real
/// dismissal.
void main() {
  const keyboard = 336.0;

  /// A trust that has watched a keyboard come up under a focused field.
  KeyboardInsetTrust withKeyboardUp() {
    final trust = KeyboardInsetTrust();
    for (final inset in [0.0, 90.0, 240.0, keyboard]) {
      trust.observe(raw: inset, hasInputFocus: true, appResumed: true);
    }
    return trust;
  }

  group('while a field holds the focus', () {
    test('believes every frame of the keyboard arriving', () {
      final trust = KeyboardInsetTrust();
      for (final inset in [12.0, 90.0, 240.0, keyboard]) {
        expect(
          trust.observe(raw: inset, hasInputFocus: true, appResumed: true),
          inset,
        );
      }
    });

    test('believes the keyboard leaving while the field keeps focus — the '
        'system back button hides the IME without touching focus', () {
      final trust = withKeyboardUp();
      for (final inset in [200.0, 40.0, 0.0]) {
        expect(
          trust.observe(raw: inset, hasInputFocus: true, appResumed: true),
          inset,
        );
      }
    });

    test('believes an inset that was refused a moment ago, because a wrong '
        'refusal here hides the field behind its own keyboard', () {
      final trust = KeyboardInsetTrust();
      trust.observe(raw: keyboard, hasInputFocus: false, appResumed: true);
      expect(trust.trusted, 0);

      expect(
        trust.observe(raw: keyboard, hasInputFocus: true, appResumed: true),
        keyboard,
      );
    });

    test('keeps believing while the app is not resumed — a notification '
        'shade pulled over a note being typed leaves the keyboard up', () {
      final trust = withKeyboardUp();

      expect(
        trust.observe(raw: keyboard, hasInputFocus: true, appResumed: false),
        keyboard,
      );
    });

    test('is not moved by the settle window', () {
      final trust = withKeyboardUp();

      expect(trust.settle(hasInputFocus: true), keyboard);
    });
  });

  group('with nothing focused', () {
    test('follows a dismissal down frame by frame', () {
      final trust = withKeyboardUp();
      for (final inset in [keyboard, 300.0, 180.0, 60.0, 0.0]) {
        expect(
          trust.observe(raw: inset, hasInputFocus: false, appResumed: true),
          inset,
          reason: 'a closing keyboard is real; the glide must survive',
        );
      }
    });

    test('never rises: the replayed "keyboard up" inset is refused', () {
      final trust = KeyboardInsetTrust();

      expect(
        trust.observe(raw: keyboard, hasInputFocus: false, appResumed: true),
        0,
      );
    });

    test('a replay in the middle of a dismissal holds the lowest frame seen '
        'instead of jumping back up', () {
      final trust = withKeyboardUp();
      trust.observe(raw: 180, hasInputFocus: false, appResumed: true);

      expect(
        trust.observe(raw: keyboard, hasInputFocus: false, appResumed: true),
        180,
      );
      expect(trust.settle(hasInputFocus: false), 0);
    });

    test('an inset that rests above zero is dropped by the settle window', () {
      final trust = withKeyboardUp();
      expect(
        trust.observe(raw: keyboard, hasInputFocus: false, appResumed: true),
        keyboard,
        reason: 'the keyboard has not started leaving yet; nothing to drop',
      );

      expect(trust.settle(hasInputFocus: false), 0);
      expect(
        trust.observe(raw: keyboard, hasInputFocus: false, appResumed: true),
        0,
        reason: 'the same stale value arriving again is still refused',
      );
    });

    test('is dropped at once when the app is not resumed', () {
      final trust = withKeyboardUp();

      expect(
        trust.observe(raw: keyboard, hasInputFocus: false, appResumed: false),
        0,
      );
    });

    test('stays dropped across the resume that brings the stale inset back — '
        'the reported bug', () {
      final trust = withKeyboardUp();
      // The app is paused with the keyboard up; `main.dart` drops focus.
      trust.observe(raw: keyboard, hasInputFocus: false, appResumed: false);

      // It comes back with the keyboard gone and the inset still reported.
      expect(
        trust.observe(raw: keyboard, hasInputFocus: false, appResumed: true),
        0,
      );
      expect(trust.settle(hasInputFocus: false), 0);
    });
  });

  test('a negative inset reads as none', () {
    final trust = KeyboardInsetTrust();

    expect(trust.observe(raw: -4, hasInputFocus: true, appResumed: true), 0);
    expect(trust.observe(raw: -4, hasInputFocus: false, appResumed: true), 0);
  });

  test('recovers on the next real keyboard after a stale inset', () {
    final trust = KeyboardInsetTrust();
    trust.observe(raw: keyboard, hasInputFocus: false, appResumed: true);
    trust.settle(hasInputFocus: false);

    // A field takes focus; the engine's progress frames restart from the
    // bottom and the completed animation leaves the platform value right.
    for (final inset in [8.0, 150.0, keyboard]) {
      expect(
        trust.observe(raw: inset, hasInputFocus: true, appResumed: true),
        inset,
      );
    }
    for (final inset in [220.0, 70.0, 0.0]) {
      expect(
        trust.observe(raw: inset, hasInputFocus: false, appResumed: true),
        inset,
      );
    }
  });
}
