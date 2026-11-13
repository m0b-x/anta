import 'package:flutter/scheduler.dart';

/// One line for one leave of the partner's share (share surfaces §6.12,
/// N6): when it ends, every page of it that is open closes — her folder's
/// pages, her note's editor — and each has its words, but the person is
/// told once, by the page in front.
///
/// The page in front [claim]s the voice and speaks; a page of the same
/// leave underneath [offer]s its line, said after the frame only when no
/// page in front spoke — the page above it may be no part of the leave.
/// Owned by neither page, so the folder pages and the editor ask the one.
abstract final class ShareLeaveVoice {
  static bool _claimed = false;
  static void Function()? _offered;
  static bool _scheduled = false;

  /// Speaks [say] unless a page in front already spoke for this leave.
  static void claim(void Function() say) {
    if (!_claimed) {
      _claimed = true;
      say();
    }
    _settleAfterFrame();
  }

  /// Keeps [say] — the first offered — to speak after the frame, unless a
  /// page in front [claim]s the voice first.
  static void offer(void Function() say) {
    _offered ??= say;
    _settleAfterFrame();
  }

  static void _settleAfterFrame() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        final offered = _offered;
        if (!_claimed && offered != null) offered();
        _claimed = false;
        _offered = null;
        _scheduled = false;
      })
      ..scheduleFrame();
  }
}
