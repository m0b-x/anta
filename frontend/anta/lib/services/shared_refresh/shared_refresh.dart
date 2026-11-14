import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../constants/shared_refresh_constants.dart';
import '../settings_service.dart';
import '../sync/sync_status.dart';
import 'shared_refresh_plan.dart';
import 'shared_refresh_scheduler.dart';

/// What the check's plan remembers past the isolate that made it: for each
/// slot, when the check scheduled there is due — until its work reports
/// that it runs, or it is taken off.
///
/// Outside the planner's own memory because every launch, and every run a
/// message starts, is a new isolate: one that planned "from now" with
/// nothing remembered replaced a nearer check by a later one each time,
/// and no check ran for as long as launches kept coming (review R2).
abstract interface class SharedRefreshMemory {
  /// The checks that stand, by slot. Re-read each time: another isolate may
  /// have written since.
  Future<Map<SharedRefreshSlot, DateTime>> standing();

  /// The check in [slot] is due at [due]; null when none stands there any
  /// more — its work runs or has ended, or it was taken off.
  Future<void> stands(SharedRefreshSlot slot, DateTime? due);
}

/// [SharedRefreshMemory] of one isolate: a suite's, and a build that binds
/// no background work.
class InProcessSharedRefreshMemory implements SharedRefreshMemory {
  final Map<SharedRefreshSlot, DateTime> _standing = {};

  @override
  Future<Map<SharedRefreshSlot, DateTime>> standing() async => {..._standing};

  @override
  Future<void> stands(SharedRefreshSlot slot, DateTime? due) async {
    if (due == null) {
      _standing.remove(slot);
    } else {
      _standing[slot] = due;
    }
  }
}

/// What a pass's report left of the check.
enum SharedRefreshPlanned {
  /// No pass has reported since [SharedRefresh.passAwaited].
  untold,

  /// Nothing of the partner's depends on a check, or the database does not
  /// share: none stands.
  notWanted,

  /// A check stands: scheduled now, or one that stood was kept.
  stands,

  /// A check is wanted and none could be made to stand — the platform
  /// refused it, or what decides could not be asked. Never read as "not
  /// wanted": a run that did ended with no successor and no retry, and the
  /// phone looked no more until the app was opened (review R1).
  wantedNotStanding,
}

/// Keeps the check scheduled for as long as an alert depends on what the
/// partner shares, and takes it off when none does
/// (`docs/cloud-shared-freshness.md` §4, decision b).
///
/// Fed by every alert pass: the pass reports what of the partner's it armed,
/// this decides whether the check is wanted, plans it and asks the platform
/// — at most once for one plan. Global like the gateways it sits beside: it
/// holds no database, and what it remembers is about the platform's one
/// unique work, which a database switch does not change.
///
/// What a pass may do to a check that stands ([SharedRefreshMemory]):
///
/// 1. One that lies ahead is kept when the pass, with nothing read, would
///    plan a later one — a plan counts from now, so every such pass plans a
///    little later than the last — and is replaced by a nearer one.
/// 2. One that is due and whose work has not reported running waits for
///    the network. A pass with nothing read neither replaces nor cancels
///    it, whatever the plan says now, "none" included: the read it makes
///    the moment the network is back is the one the plan was for. It goes
///    only for cause — the database no longer shares (unpaired, unbound,
///    signed out, another database) — and with it its memory.
/// 3. A pass that follows a read ([readMade]) plans from now.
/// 4. A memory that cannot be read is no memory: the pass plans as a first
///    one. A later check than the one that stood is the cost; a phone with
///    no check at all would be the other.
///
/// 5. The memory is believed only where the platform agrees. Before a
///    check that stands is the reason to schedule nothing — 1's "kept", 2
///    whole — the platform is asked whether it holds that work
///    ([SharedRefreshScheduler.stands]): once in an isolate for an entry
///    while it lies ahead, once more when it is first found due. "No"
///    drops the entry and the pass plans as a first one; a platform that
///    cannot tell leaves the memory trusted. The preferences come back
///    with the phone's backup and the works do not; a work can be consumed
///    by an app in which sync never came up, or lost — each left an entry
///    "due" that no pass might replace and no platform would run.
///
/// Not done: asking the platform at every pass, or re-registering a due
/// check under a "keep" policy to restore one it lost — the question above
/// is asked where the answer changes what is done, and no oftener.
class SharedRefresh {
  final SharedRefreshScheduler _scheduler;
  final SharedRefreshMemory _memory;
  final Future<bool> Function() _shares;
  final DateTime Function() _clock;

  /// Whether the last pass left a check standing — how a run that has just
  /// planned its successor learns whether one is there.
  bool get scheduled => _planned == SharedRefreshPlanned.stands;

  /// What the last pass's report left; [SharedRefreshPlanned.untold] from
  /// [passAwaited] until one reports.
  SharedRefreshPlanned get planned => _planned;
  SharedRefreshPlanned _planned = SharedRefreshPlanned.untold;

  /// The slot of the check's work that is running now, while passes report
  /// here: the run itself in its own isolate, or in the app the worker
  /// whose read it is doing. What is scheduled meanwhile goes into the
  /// other slot, so the running work is never replaced — and so cancelled.
  SharedRefreshSlot? _runningIn;

  /// Whether the last pass found a message from the partner worth a read
  /// ([SharedRefreshNeed.pokeWorthy]) — asked by a run a message started,
  /// which has already checked that the database shares.
  bool get pokeWorthy => _lastNeed?.pokeWorthy ?? false;

  /// [pokeWorthy], or null while no pass of this isolate has reported: not
  /// known is not "no".
  bool? get pokeWorthyIfTold => _lastNeed?.pokeWorthy;
  SharedRefreshNeed? _lastNeed;

  /// This process took the work off and scheduled none since.
  bool _cancelled = false;

  /// This process scheduled a check, or served the work of one.
  bool _touched = false;

  /// Tail of the chain the requests run on, one after the other: two passes
  /// that end close together must reach the platform in their order.
  Future<void>? _requests;

  /// Told each time a check has reached the platform; the app remembers
  /// from it that a trigger can exist on this install.
  final void Function()? _onScheduled;

  /// [shares] answers decision b's standing conditions for the open
  /// database ([databaseShares]); asked for a need that depends on the
  /// partner's rows, and before a due check is taken off.
  ///
  /// [memory] is the plan's memory past this isolate; one of this isolate
  /// alone when none is given.
  SharedRefresh({
    required SharedRefreshScheduler scheduler,
    required Future<bool> Function() shares,
    SharedRefreshMemory? memory,
    DateTime Function() clock = DateTime.now,
    void Function()? onScheduled,
  }) : _scheduler = scheduler,
       _shares = shares,
       _memory = memory ?? InProcessSharedRefreshMemory(),
       _clock = clock,
       _onScheduled = onScheduled;

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
  /// logged and left in [planned], and the next pass asks again.
  Future<void> afterAlertPass(SharedRefreshNeed need) => _queued(
    () async => _planned = await _apply(need),
    failed: () => _planned = need.checkWorthy
        ? SharedRefreshPlanned.wantedNotStanding
        : SharedRefreshPlanned.notWanted,
  );

  Future<void> _queued(
    Future<void> Function() request, {
    void Function()? failed,
  }) {
    final previous = _requests;
    final queued = () async {
      if (previous != null) await previous;
      try {
        await request();
      } catch (e, st) {
        debugPrint('[SharedRefresh] not applied: $e\n$st');
        failed?.call();
      }
    }();
    _requests = queued;
    return queued;
  }

  /// Completes when every request made so far has reached the platform —
  /// for a run that ends its isolate once it is done.
  Future<void> settled() => _requests ?? Future<void>.value();

  /// A pass is about to run whose report is waited for: [planned] says
  /// [SharedRefreshPlanned.untold] until it has reported, so a pass that
  /// ended before it reached this — its setup failed, it threw — is told
  /// from one that found nothing wanted.
  void passAwaited() => _planned = SharedRefreshPlanned.untold;

  /// The check's work in [slot] has started and its trigger is being
  /// served here — by the run in its own isolate, or by the app for a read
  /// forwarded to it. Two things follow until [workEnded]:
  ///
  /// - whatever a pass schedules goes into the other slot: the unique work
  ///   a schedule replaces is cancelled, and a run that replaced its own
  ///   was stopped by the platform before it had read anything (device
  ///   pass, 2026-11-13);
  /// - the check that stood in [slot] stands no more, in any isolate's
  ///   memory, because it is the one that just ran: remembered, the pass
  ///   that follows the read finds its plan "already scheduled" and leaves
  ///   the phone with no successor.
  void workRunning(SharedRefreshSlot slot) {
    _runningIn = slot;
    _touched = true;
    _cancelled = false;
    unawaited(_queued(() => _memory.stands(slot, null)));
  }

  /// The work [workRunning] named has been answered: the next schedule is
  /// the app's own again. Waits for the requests still on their way.
  Future<void> workEnded() async {
    await settled();
    _runningIn = null;
  }

  /// A shared read was made that no work of the check's stands for — a
  /// message's, forwarded to the app: the pass that follows may plan the
  /// check from now, later than it stood. Spent by that one pass.
  ///
  /// It carries its time, and counts only for a pass within
  /// [kSharedRefreshReadPassWindow] of it. Every read made to its end says
  /// this, and one that changed nothing is followed by no pass: left
  /// standing, it was spent by whichever pass came next — a resume the next
  /// morning, which moved a check that had fallen due and was waiting for
  /// the network half a day out.
  void readMade() => _readAt = _clock();
  DateTime? _readAt;

  /// The pass [readMade] was for has ended, reported or not: a read is not
  /// left standing for a later pass that has nothing to do with it.
  void readSpent() => _readAt = null;

  /// Whether a read was made that the pass running at [now] follows; spent
  /// by the asking. A read from after [now] — the clock went back — is
  /// none.
  bool _readJustMade(DateTime now) {
    final at = _readAt;
    _readAt = null;
    if (at == null) return false;
    final since = now.difference(at);
    return !since.isNegative && since < kSharedRefreshReadPassWindow;
  }

  /// The check that stands where a schedule made now would write or take
  /// off: every slot but the running one, and but those in [except]. The
  /// earliest when two do — a retried work and its successor. Null when
  /// none, or when the memory cannot be read.
  Future<_Standing?> _standing(
    SharedRefreshSlot? running, {
    Set<SharedRefreshSlot> except = const {},
  }) async {
    try {
      _Standing? earliest;
      for (final MapEntry(key: slot, value: due)
          in (await _memory.standing()).entries) {
        if (slot == running || except.contains(slot)) continue;
        if (earliest == null || due.isBefore(earliest.due)) {
          earliest = (slot: slot, due: due);
        }
      }
      return earliest;
    } catch (e) {
      debugPrint('[SharedRefresh] plan not remembered: $e');
      return null;
    }
  }

  /// The entries this isolate has asked the platform about, or scheduled
  /// itself: one that lies ahead, and one found due — by slot, the instant
  /// each was due at when asked.
  final Map<SharedRefreshSlot, DateTime> _believedAhead = {};
  final Map<SharedRefreshSlot, DateTime> _believedDue = {};

  /// Whether the work the memory says stands is on the platform too, asked
  /// until it is answered and then no more, for an entry in each of its two
  /// states. Only "no" is disbelief: a platform that cannot tell changes
  /// nothing — and is no answer either, so the next pass asks again. Kept
  /// as one, a single failed call pinned a stale entry for the life of the
  /// process.
  Future<bool> _believed(_Standing entry, DateTime now) async {
    final asked = entry.due.isAfter(now) ? _believedAhead : _believedDue;
    if (asked[entry.slot] == entry.due) return true;
    bool? stands;
    try {
      stands = await _scheduler.stands(entry.slot);
    } catch (e) {
      debugPrint('[SharedRefresh] platform not asked: $e');
    }
    if (stands == false) return false;
    if (stands == true) asked[entry.slot] = entry.due;
    return true;
  }

  /// What a schedule or a cancel made with [running] left standing, written
  /// down. The platform has already answered: a memory that cannot be
  /// written costs the next pass its rule, never this one its check.
  Future<void> _remember(SharedRefreshSlot? running, DateTime? at) async {
    try {
      final written = running?.other ?? SharedRefreshSlot.first;
      for (final slot in SharedRefreshSlot.values) {
        if (slot == running) continue;
        await _memory.stands(slot, slot == written ? at : null);
      }
    } catch (e) {
      debugPrint('[SharedRefresh] plan not written down: $e');
    }
  }

  Future<SharedRefreshPlanned> _apply(SharedRefreshNeed need) async {
    final now = _clock();
    _lastNeed = need;
    final read = _readJustMade(now);
    final running = _runningIn;
    final shares = need.checkWorthy && await _shares();
    final gap = shares
        ? SharedRefreshPlan.next(
            now,
            need.fireTimes,
            categoryAlerts: need.categoryAlerts,
            alertAhead: need.alertAhead,
          )
        : null;
    // A pass that saw nothing of sharing, in a process that never had a
    // check: nothing is asked, of the platform or of the memory — what an
    // account that never paired pays on every pass.
    if (gap == null && !need.sharing && !_touched) {
      return SharedRefreshPlanned.notWanted;
    }
    final at = gap == null ? null : now.add(gap);
    // The entries the platform turned out not to hold, in this pass: each
    // is dropped, and the pass decides again against what is left.
    final disbelieved = <SharedRefreshSlot>{};
    while (true) {
      final standing = await _standing(running, except: disbelieved);
      final due = standing?.due;
      // Due, and its work has not said it runs: it waits for the network.
      final waiting = due != null && !read && !due.isAfter(now);
      final bool kept;
      if (at == null) {
        if (due == null) {
          // Work an earlier process left standing is taken off once, and
          // only where the pass saw sharing: a database that never paired
          // has none.
          if (_cancelled || !need.sharing) {
            return SharedRefreshPlanned.notWanted;
          }
          kept = false;
        } else {
          kept = waiting && (need.checkWorthy ? shares : await _shares());
        }
      } else {
        kept =
            due != null &&
            (at.difference(due).abs() <= kSharedRefreshSameInstant ||
                waiting ||
                (!read && at.isAfter(due)));
      }
      if (!kept) break;
      if (await _believed(standing!, now)) return SharedRefreshPlanned.stands;
      disbelieved.add(standing.slot);
      try {
        await _memory.stands(standing.slot, null);
      } catch (e) {
        debugPrint('[SharedRefresh] lost check not written off: $e');
      }
    }
    if (gap == null || at == null) {
      await _scheduler.cancel(runningIn: running);
      await _remember(running, null);
      _cancelled = true;
      return SharedRefreshPlanned.notWanted;
    }
    await _scheduler.schedule(gap, runningIn: running);
    await _remember(running, at);
    // Scheduled here a moment ago: nothing to ask the platform about.
    final written = running?.other ?? SharedRefreshSlot.first;
    _believedAhead[written] = at;
    _believedDue.remove(written);
    _touched = true;
    _cancelled = false;
    _onScheduled?.call();
    return SharedRefreshPlanned.stands;
  }
}

/// A check the memory says stands: where, and when it is due.
typedef _Standing = ({SharedRefreshSlot slot, DateTime due});
