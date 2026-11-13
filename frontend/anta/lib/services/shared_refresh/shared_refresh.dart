import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../constants/shared_refresh_constants.dart';
import '../settings_service.dart';
import '../sync/sync_status.dart';
import 'shared_refresh_plan.dart';
import 'shared_refresh_scheduler.dart';

/// Keeps the check scheduled for as long as an alert depends on what the
/// partner shares, and takes it off when none does
/// (`docs/cloud-shared-freshness.md` §4, decision b).
///
/// Fed by every alert pass: the pass reports what of the partner's it armed,
/// this decides whether the check is wanted, plans it and asks the platform
/// — at most once for one plan. Global like the gateways it sits beside: it
/// holds no database, and what it remembers is about the platform's one
/// unique work, which a database switch does not change.
class SharedRefresh {
  final SharedRefreshScheduler _scheduler;
  final Future<bool> Function() _shares;
  final DateTime Function() _clock;

  /// When the check this process last scheduled runs; null while it
  /// scheduled none, or cancelled it.
  DateTime? _scheduledFor;

  /// Whether the last request left a check scheduled — how a run that has
  /// just planned its successor learns whether it is wanted at all.
  bool get scheduled => _scheduledFor != null;

  /// The slot of the check's work that is running now, while passes report
  /// here: the run itself in its own isolate, or in the app the worker
  /// whose read it is doing. What is scheduled meanwhile goes into the
  /// other slot, so the running work is never replaced — and so cancelled.
  SharedRefreshSlot? _runningIn;

  /// Whether the last pass found a message from the partner worth a read
  /// ([SharedRefreshNeed.pokeWorthy]) — asked by a run a message started,
  /// which has already checked that the database shares.
  bool get pokeWorthy => _lastNeed?.pokeWorthy ?? false;
  SharedRefreshNeed? _lastNeed;

  /// This process took the work off and scheduled none since.
  bool _cancelled = false;

  /// Tail of the chain the requests run on, one after the other: two passes
  /// that end close together must reach the platform in their order.
  Future<void>? _requests;

  /// [shares] answers decision b's standing conditions for the open
  /// database ([databaseShares]); asked only for a need that depends on the
  /// partner's rows.
  SharedRefresh({
    required SharedRefreshScheduler scheduler,
    required Future<bool> Function() shares,
    DateTime Function() clock = DateTime.now,
  }) : _scheduler = scheduler,
       _shares = shares,
       _clock = clock;

  /// Whether a database syncs and is paired, both as the signed-in account
  /// ([uid]): bound to it with nothing holding sync, and holding its pair —
  /// the rules the engine and the reader of shared rows go by. Local reads
  /// only.
  static Future<bool> databaseShares({
    required String? uid,
    required SettingsService settings,
  }) async {
    if (uid == null) return false;
    final binding = await settings.getSyncBinding();
    if (binding == null ||
        SyncPause.forAccount(binding, uid) != SyncPause.none) {
      return false;
    }
    final pairing = await settings.getPairingSettings();
    return pairing.pairId != null && pairing.accountUid == uid;
  }

  /// Plans the check from what an alert pass found, and schedules or
  /// cancels it. Completes when the platform has answered; a failure is
  /// logged and forgotten, and the next pass asks again.
  Future<void> afterAlertPass(SharedRefreshNeed need) {
    final previous = _requests;
    final request = () async {
      if (previous != null) await previous;
      try {
        await _apply(need);
      } catch (e, st) {
        debugPrint('[SharedRefresh] not applied: $e\n$st');
      }
    }();
    _requests = request;
    return request;
  }

  /// Completes when every request made so far has reached the platform —
  /// for a run that ends its isolate once it is done.
  Future<void> settled() => _requests ?? Future<void>.value();

  /// The check's work in [slot] has started and its trigger is being
  /// served here — by the run in its own isolate, or by the app for a read
  /// forwarded to it. Two things follow until [workEnded]:
  ///
  /// - whatever a pass schedules goes into the other slot: the unique work
  ///   a schedule replaces is cancelled, and a run that replaced its own
  ///   was stopped by the platform before it had read anything (device
  ///   pass, 2026-11-13);
  /// - the check this process remembered is forgotten, because it is the
  ///   one that just ran: remembered, the pass that follows the read finds
  ///   its plan "already scheduled" and leaves the phone with no successor.
  void workRunning(SharedRefreshSlot slot) {
    _runningIn = slot;
    _scheduledFor = null;
    _cancelled = false;
  }

  /// The work [workRunning] named has been answered: the next schedule is
  /// the app's own again. Waits for the requests still on their way.
  Future<void> workEnded() async {
    await settled();
    _runningIn = null;
  }

  Future<void> _apply(SharedRefreshNeed need) async {
    final now = _clock();
    _lastNeed = need;
    final gap = need.checkWorthy && await _shares()
        ? SharedRefreshPlan.next(
            now,
            need.fireTimes,
            categoryAlerts: need.categoryAlerts,
            alertAhead: need.alertAhead,
          )
        : null;
    if (gap == null) {
      // Work an earlier process left standing is taken off once, and only
      // where the pass saw sharing: a database that never paired has none.
      if (_cancelled || (_scheduledFor == null && !need.sharing)) return;
      await _scheduler.cancel(runningIn: _runningIn);
      _scheduledFor = null;
      _cancelled = true;
      return;
    }
    final at = now.add(gap);
    final standing = _scheduledFor;
    if (standing != null &&
        at.difference(standing).abs() <= kSharedRefreshSameInstant) {
      return;
    }
    await _scheduler.schedule(gap, runningIn: _runningIn);
    _scheduledFor = at;
    _cancelled = false;
  }
}
