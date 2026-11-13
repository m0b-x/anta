import 'package:equatable/equatable.dart';

import '../../constants/shared_refresh_constants.dart';

/// What of the partner's can ring on this phone, as the alert pass that
/// just ended saw it — the input of [SharedRefreshPlan.next]
/// (`docs/cloud-shared-freshness.md` §4).
class SharedRefreshNeed extends Equatable {
  /// When each alert armed on one of the partner's events fires.
  final List<DateTime> fireTimes;

  /// "Category alerts too" is on and a category the partner shares holds an
  /// enabled alert of mine: an event they add there has to arm.
  final bool categoryAlerts;

  /// An enabled alert of mine is defined on one of the partner's events the
  /// phone holds, armed or not, a past event's included: the partner may
  /// have just moved that event into the future, so a message from them is
  /// worth a read ([pokeWorthy]). Not worth the phone's own check on its
  /// own — a past one-off would keep it alive for ever.
  final bool alertDefined;

  /// One of those alerts is on an event that can still occur — a one-off
  /// not yet past, a repeating one not yet ended. Past the alerts' horizon
  /// it arms nothing, and the partner may move its event nearer while the
  /// app is closed: the phone's own check goes on for it ([checkWorthy]),
  /// which also rolls the horizon forward.
  final bool alertAhead;

  /// The pass saw something of sharing on this database — a partner's event
  /// held, or the setting moved to "Category alerts too". False is what an
  /// account that never paired reports, and what lets it ask the platform
  /// nothing: with it false, work nobody in this process scheduled is never
  /// cancelled either.
  final bool sharing;

  const SharedRefreshNeed({
    this.fireTimes = const [],
    this.categoryAlerts = false,
    this.alertDefined = false,
    this.alertAhead = false,
    this.sharing = true,
  });

  /// A pass that saw nothing of sharing at all.
  static const SharedRefreshNeed none = SharedRefreshNeed(sharing: false);

  /// Whether the phone looks by itself: something of the partner's can
  /// ring here, now or once its event comes near. What schedules the check,
  /// and what lets a run the schedule started read.
  bool get checkWorthy => fireTimes.isNotEmpty || categoryAlerts || alertAhead;

  /// Whether a message from the partner is worth a read: [checkWorthy], or
  /// an alert of mine on any event of theirs — what they just changed may
  /// be the past event it waits on.
  bool get pokeWorthy => checkWorthy || alertDefined;

  @override
  List<Object?> get props => [
    fireTimes,
    categoryAlerts,
    alertDefined,
    alertAhead,
    sharing,
  ];
}

/// Takes what an alert pass found of the partner's. Never awaited by the
/// pass: the platform's answer is no part of arming an alert.
typedef SharedRefreshSink = void Function(SharedRefreshNeed need);

/// When the phone next reads what the partner shares by itself (decision c):
/// sooner as an alert comes near, never when no alert depends on it.
abstract final class SharedRefreshPlan {
  /// The wait from [now] until the next check, or null for none.
  ///
  /// Half the time left to the nearest of [fireTimes], held between
  /// [kSharedRefreshMinGap] and the ceiling — [kSharedRefreshMaxGap], or
  /// [kSharedRefreshCategoryMaxGap] under [categoryAlerts]. A fire time at
  /// most the floor away takes no further check, a past one included — one
  /// planned for it would land on the ring's own instant — and the next
  /// nearest decides. With none left the wait is the ceiling while
  /// [categoryAlerts] or [alertAhead] still asks for a check, and nothing
  /// is wanted otherwise.
  static Duration? next(
    DateTime now,
    Iterable<DateTime> fireTimes, {
    required bool categoryAlerts,
    bool alertAhead = false,
  }) {
    final ceiling = categoryAlerts
        ? kSharedRefreshCategoryMaxGap
        : kSharedRefreshMaxGap;
    Duration? nearest;
    for (final fireAt in fireTimes) {
      final left = fireAt.difference(now);
      if (left <= kSharedRefreshMinGap) continue;
      if (nearest == null || left < nearest) nearest = left;
    }
    if (nearest == null) {
      return categoryAlerts || alertAhead ? ceiling : null;
    }
    final half = nearest ~/ 2;
    if (half < kSharedRefreshMinGap) return kSharedRefreshMinGap;
    return half > ceiling ? ceiling : half;
  }
}
