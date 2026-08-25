import 'package:flutter_test/flutter_test.dart';

import 'package:anta/utils/keyboard_inset_tracker.dart';

/// The tracker turns one bottom view inset per frame into the two signals the
/// calendar grid needs. Its whole reason to exist is asymmetry: the grid must
/// collapse the moment the keyboard starts arriving, but start expanding the
/// moment it starts leaving rather than waiting for the inset to reach zero.
void main() {
  /// Drives a keyboard animation frame by frame, ending on [to].
  void ramp(
    KeyboardInsetTracker tracker,
    double from,
    double to, {
    int frames = 8,
    void Function(double inset)? onFrame,
  }) {
    for (var i = 1; i <= frames; i++) {
      final inset = from + (to - from) * (i / frames);
      tracker.update(inset);
      onFrame?.call(inset);
    }
  }

  /// A completed open/close cycle, which is what teaches the tracker how tall
  /// this device's keyboard is.
  KeyboardInsetTracker trained({double peak = 320}) {
    final tracker = KeyboardInsetTracker();
    tracker.update(peak);
    tracker.update(0);
    return tracker;
  }

  group('collapse flag', () {
    test('flips on as soon as the inset starts rising', () {
      final tracker = KeyboardInsetTracker();
      expect(tracker.collapsed, isFalse);

      tracker.update(12);
      expect(
        tracker.collapsed,
        isTrue,
        reason:
            'the grid collapses on the first frame of the keyboard, not '
            'once it has arrived',
      );
    });

    test('flips off on the first falling frame, long before zero', () {
      final tracker = trained();
      ramp(tracker, 0, 320);
      expect(tracker.collapsed, isTrue);

      tracker.update(300);
      expect(
        tracker.collapsed,
        isFalse,
        reason:
            'the grid must start expanding while the keyboard is still on '
            'screen — waiting for zero is what serialised the two animations',
      );
    });

    test('holds through jitter below the epsilon', () {
      final tracker = trained();
      ramp(tracker, 0, 320);

      tracker.update(319.8);
      expect(
        tracker.collapsed,
        isTrue,
        reason: 'a fraction of a pixel is not the keyboard leaving',
      );
    });

    test('is false again once the keyboard is gone', () {
      final tracker = trained();
      ramp(tracker, 0, 320);
      ramp(tracker, 320, 0);
      expect(tracker.collapsed, isFalse);
    });
  });

  group('coupled progress', () {
    test('is null on the first open of a run, with no peak to divide by', () {
      final tracker = KeyboardInsetTracker();
      tracker.update(20);
      expect(
        tracker.progress,
        isNull,
        reason:
            'nothing has taught it how tall the keyboard gets yet, so the '
            'caller must run its own timed animation',
      );
    });

    test('tracks the inset on the way up once a peak is known', () {
      final tracker = trained();
      expect(tracker.learnedPeak, 320);

      tracker.update(40);
      expect(tracker.progress, closeTo(0.125, 1e-9));
      tracker.update(160);
      expect(tracker.progress, closeTo(0.5, 1e-9));
      tracker.update(320);
      expect(tracker.progress, closeTo(1.0, 1e-9));
    });

    test('clamps to one when the keyboard overshoots the learned peak', () {
      final tracker = trained();
      tracker.update(40);
      tracker.update(400);
      expect(tracker.progress, 1.0);
    });

    test('tracks the inset on the way down against the observed peak', () {
      final tracker = trained();
      ramp(tracker, 0, 320);

      tracker.update(240);
      expect(tracker.progress, closeTo(0.25, 1e-9));
      tracker.update(80);
      expect(tracker.progress, closeTo(0.75, 1e-9));
    });

    test('reaches exactly one when a gradual descent lands on zero', () {
      final tracker = trained();
      ramp(tracker, 0, 320);
      ramp(tracker, 320, 0);
      expect(tracker.progress, 1.0);
    });

    test('rises monotonically across a full ramped cycle', () {
      final tracker = trained();
      final samples = <double>[];
      ramp(
        tracker,
        0,
        320,
        frames: 16,
        onFrame: (_) {
          final progress = tracker.progress;
          if (progress != null) samples.add(progress);
        },
      );

      expect(samples.length, 16);
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i], greaterThanOrEqualTo(samples[i - 1]));
      }
      expect(samples.last, 1.0);
    });
  });

  group('fallbacks', () {
    test('an inset that arrives in one frame never animated', () {
      final tracker = trained();
      tracker.update(320);
      expect(
        tracker.progress,
        isNull,
        reason:
            'Android below API 30 jumps the inset instead of animating '
            'it, and there is no motion to couple to',
      );
      expect(tracker.collapsed, isTrue);
    });

    test('an inset that vanishes in one frame never animated either', () {
      final tracker = trained();
      ramp(tracker, 0, 320);
      tracker.update(0);
      expect(tracker.progress, isNull);
      expect(tracker.collapsed, isFalse);
    });

    test('a descent that stopped short still reports its real progress', () {
      final tracker = trained();
      ramp(tracker, 0, 320);
      ramp(tracker, 320, 40);
      expect(tracker.progress, closeTo(0.875, 1e-9));

      tracker.update(0);
      expect(
        tracker.progress,
        1.0,
        reason:
            'the last leg was small enough to be the tail of the same '
            'animation, not a jump',
      );
    });
  });

  group('peak learning', () {
    test('a cycle teaches the peak, and the next cycle replaces it', () {
      final tracker = KeyboardInsetTracker();
      expect(tracker.learnedPeak, 0);

      ramp(tracker, 0, 320);
      expect(
        tracker.learnedPeak,
        0,
        reason: 'the peak is only known once the cycle has completed',
      );

      ramp(tracker, 320, 0);
      expect(tracker.learnedPeak, 320);

      ramp(tracker, 0, 260);
      ramp(tracker, 260, 0);
      expect(tracker.learnedPeak, 260);
    });

    test('the observed peak resets between cycles', () {
      final tracker = trained();
      ramp(tracker, 0, 320);
      ramp(tracker, 320, 0);

      ramp(tracker, 0, 160);
      tracker.update(80);
      expect(
        tracker.progress,
        closeTo(0.5, 1e-9),
        reason: 'the descent divides by this cycle peak, not the last one',
      );
    });

    test('reset clears everything', () {
      final tracker = trained();
      ramp(tracker, 0, 320);
      tracker.reset();

      expect(tracker.collapsed, isFalse);
      expect(tracker.progress, isNull);
      expect(tracker.learnedPeak, 0);
    });
  });
}
