import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../constants/shared_refresh_constants.dart';
import 'shared_refresh_entry.dart';
import 'shared_refresh_scheduler.dart';
import 'shared_refresh_trigger.dart';

/// [SharedRefreshScheduler] over Android's WorkManager.
///
/// The plugin is told where its Dart entry is only before the first check
/// is scheduled, never at launch: an account with nothing to keep fresh
/// asks the platform nothing at all.
class WorkmanagerSharedRefreshScheduler implements SharedRefreshScheduler {
  Future<void>? _initialized;

  /// Once per process while it holds; a failure is forgotten, so the next
  /// schedule asks again.
  Future<void> _ensureInitialized() => _initialized ??= _initialize();

  Future<void> _initialize() async {
    try {
      await Workmanager().initialize(sharedRefreshEntry);
    } catch (_) {
      _initialized = null;
      rethrow;
    }
  }

  /// Replace, stated: the plugin's own default for a one-off work keeps the
  /// one already standing, and a plan that moved would never land. Replace
  /// cancels what it replaces, a running work included — which is why the
  /// slot written is never the one a work is running in.
  @override
  Future<void> schedule(Duration delay, {SharedRefreshSlot? runningIn}) async {
    await _ensureInitialized();
    final slot = runningIn?.other ?? SharedRefreshSlot.first;
    await Workmanager().registerOneOffTask(
      slot.workName,
      slot.workName,
      initialDelay: delay,
      // The schedule's own work: what a message starts names itself.
      inputData: {kSharedRefreshCauseKey: SharedRefreshCause.check.name},
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
    // With no work running, the other slot may still hold what a run
    // scheduled: one check stands, never two.
    if (runningIn == null) {
      await Workmanager().cancelByUniqueName(slot.other.workName);
    }
  }

  @override
  Future<void> cancel({SharedRefreshSlot? runningIn}) async {
    for (final slot in SharedRefreshSlot.values) {
      if (slot == runningIn) continue;
      await Workmanager().cancelByUniqueName(slot.workName);
    }
  }

  /// The plugin's own question: true while the unique work is enqueued or
  /// running. Asked without handing the entry over first — nothing is
  /// scheduled by it — and a failure is "cannot tell", never "no": a "no"
  /// has the asker schedule over a check that may stand.
  @override
  Future<bool?> stands(SharedRefreshSlot slot) async {
    try {
      return await Workmanager().isScheduledByUniqueName(slot.workName);
    } catch (error) {
      debugPrint('[SharedRefresh] work not asked about: $error');
      return null;
    }
  }

  /// Called from the messaging plugin's isolate, so the entry is handed
  /// over here too: the plugin refuses a work until its engine knows a
  /// dispatcher, and an app that never scheduled the check stored none.
  ///
  /// A message's work is always a fresh one. Handed over for a message it
  /// **replaces** whatever stands under the name — a work that waits, one
  /// the platform holds on a back-off, one that runs: the fresh work reads
  /// everything, and nothing is ever queued behind another. Appended — the
  /// plugin's `update` and `append` are both the platform's
  /// append-or-replace — a work that had been stopped and re-enqueued came
  /// back plain, never expedited again, and on a phone asleep every later
  /// message's work waited behind it for a maintenance window.
  ///
  /// [behindRunning] is the one hand-over that is appended: asked by the
  /// work that is running, for the read it still owes. Replace would cancel
  /// the very work that asks (what the check's two slots exist for); behind
  /// it, the fresh work starts when this one has answered — a first attempt
  /// again, so expedited where it may be.
  ///
  /// [expedited] where that costs no notification — Android 12 and later,
  /// whose system runs an expedited work in Doze and with the network: a
  /// phone asleep acts on the message instead of only receiving it (case
  /// B8). Out of the expedited quota it runs as an ordinary work. Never on
  /// older Android, which runs an expedited work only as a foreground
  /// service with a notification (D23) — there the work runs within the
  /// short allowance the high-priority message grants.
  ///
  /// Never delayed: a delayed work is a plain one, which a phone asleep
  /// holds for its maintenance window.
  @override
  Future<void> scheduleMessage(
    String pairId, {
    required bool expedited,
    bool behindRunning = false,
  }) async {
    await _ensureInitialized();
    await Workmanager().registerOneOffTask(
      kSharedRefreshMessageWorkName,
      kSharedRefreshMessageWorkName,
      inputData: {
        kSharedRefreshCauseKey: SharedRefreshCause.message.name,
        kSharedRefreshPairKey: pairId,
      },
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: behindRunning
          ? ExistingWorkPolicy.update
          : ExistingWorkPolicy.replace,
      expedited: expedited,
      outOfQuotaPolicy: expedited
          ? OutOfQuotaPolicy.runAsNonExpeditedWorkRequest
          : null,
    );
  }
}
