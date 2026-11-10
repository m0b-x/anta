import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/sync/sync_cadence.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/widgets/drawer_sync_status.dart';

/// The drawer account row's status line (§12 of
/// `docs/cloud-sync-phase-02-own-space.md`): the twelve cases in the spec's
/// order, each with the case above it still true where it can be, so a
/// reordering shows as the wrong words.
void main() {
  final l10n = AppLocalizationsEn();
  const binding = SyncBinding(
    spaceId: 'space-1',
    ownerUid: 'uid-1',
    accountUid: 'uid-1',
  );
  final pushed = DateTime.utc(2026, 11, 7, 14);
  final pulled = DateTime.utc(2026, 11, 7, 15, 9);
  final failure = SyncFailureInfo(
    SyncGatewayFailure.permissionDenied,
    at: DateTime.utc(2026, 11, 7, 15, 10),
  );

  String moment(DateTime at) => 'at ${at.toIso8601String()}';

  String resetAt(DateTime reset) => 'reset ${reset.toUtc().toIso8601String()}';

  /// Two hours after the pause below: 01:00 in Los Angeles, the reset of
  /// 2026-11-08 08:00 UTC behind.
  final afterReset = DateTime.utc(2026, 11, 8, 9);

  ({String text, bool isError}) lineOf(SyncStatus status, {DateTime? now}) =>
      drawerSyncStatusLine(
        l10n,
        status,
        formatMoment: moment,
        formatQuotaReset: resetAt,
        now: now ?? DateTime.utc(2026, 11, 8, 7, 45),
      );

  /// Everything that would say something further down the list.
  final busy = SyncStatus(
    binding: binding,
    activity: SyncActivity.pushing,
    lastFailure: failure,
    pendingCount: 4,
    lastPushAt: pushed,
    lastPullAt: pulled,
  );

  test('1: an unbound database is not syncing, whatever else it holds', () {
    expect(lineOf(SyncStatus(pause: SyncPause.noAccess, pendingCount: 4)), (
      text: l10n.drawerAccountNotSyncing,
      isError: false,
    ));
    expect(lineOf(const SyncStatus(unboundAsCopyOf: 'other.db')), (
      text: l10n.drawerAccountNotSyncing,
      isError: false,
    ));
  });

  test('2: the quota pause has the drawer\'s short words, with the reset '
      'it waits for while that is ahead', () {
    // 23:30 in Los Angeles: the next midnight there is 08:00 UTC.
    final paused = busy.copyWith(
      pause: SyncPause.quotaExhausted,
      quotaPausedAt: DateTime.utc(2026, 11, 8, 7, 30),
    );

    expect(lineOf(paused), (
      text: l10n.drawerSyncPausedQuotaUntil('reset 2026-11-08T08:00:00.000Z'),
      isError: false,
    ));
    expect(
      lineOf(paused, now: afterReset),
      (text: l10n.drawerSyncPausedQuota, isError: false),
      reason: 'a passed reset is never replaced by the next one',
    );
    expect(
      lineOf(busy.copyWith(pause: SyncPause.quotaExhausted)),
      (text: l10n.drawerSyncPausedQuota, isError: false),
      reason: 'no stored pause moment',
    );
  });

  test('3: signed out reads the page\'s words', () {
    expect(lineOf(busy.copyWith(pause: SyncPause.signedOut)), (
      text: l10n.syncPausedSignedOut,
      isError: false,
    ));
  });

  test('4: another account is a pause the user lifts, in error', () {
    expect(lineOf(busy.copyWith(pause: SyncPause.accountMismatch)), (
      text: l10n.drawerSyncPausedOtherAccount,
      isError: true,
    ));
  });

  test('5: an outdated app is a pause the user lifts, in error', () {
    expect(lineOf(busy.copyWith(pause: SyncPause.appOutdated)), (
      text: l10n.drawerSyncPausedAppOutdated,
      isError: true,
    ));
  });

  test('6: no access is a pause the user lifts, in error', () {
    expect(lineOf(busy.copyWith(pause: SyncPause.noAccess)), (
      text: l10n.drawerSyncPausedNoAccess,
      isError: true,
    ));
  });

  test('6b: a deleted space is a pause the user lifts, in error', () {
    expect(lineOf(busy.copyWith(pause: SyncPause.spaceDeleted)), (
      text: l10n.drawerSyncPausedSpaceDeleted,
      isError: true,
    ));
  });

  test('7: a push says it is sending, without the count', () {
    expect(lineOf(busy), (text: l10n.syncSending(0), isError: false));
    expect(l10n.syncSending(0), 'Sending changes');
  });

  test('8: a pull says it is receiving', () {
    expect(
      lineOf(busy.copyWith(activity: SyncActivity.pulling, downloadedRows: 9)),
      (text: l10n.syncReceiving, isError: false),
    );
  });

  test('8b: the pull of a run that cut over says it is finishing the update '
      'in the drawer\'s short words, the count held to the total, the bare '
      'words before the total', () {
    final pulling = busy.copyWith(activity: SyncActivity.pulling);
    expect(
      lineOf(
        pulling.copyWith(
          updating: true,
          updatingTotal: 120,
          downloadedRows: 50,
        ),
      ),
      (text: 'Finishing update (50 of 120)', isError: false),
    );
    expect(
      lineOf(
        pulling.copyWith(
          updating: true,
          updatingTotal: 120,
          downloadedRows: 130,
        ),
      ).text,
      l10n.drawerSyncUpdating(120, 120),
    );
    expect(lineOf(pulling.copyWith(updating: true)), (
      text: l10n.drawerSyncUpdatingNoTotal,
      isError: false,
    ));
  });

  test('8c: the drain of a run that cut over says it too, counting the notes '
      'sent, never the changes waiting', () {
    expect(
      lineOf(
        busy.copyWith(
          updating: true,
          updatingSending: true,
          updatingTotal: 120,
          updatingSent: 7,
          downloadedRows: 120,
        ),
      ),
      (text: 'Finishing update (7 of 120)', isError: false),
    );
    expect(lineOf(busy.copyWith(updating: true)), (
      text: l10n.drawerSyncUpdatingNoTotal,
      isError: false,
    ));
  });

  test('8d: a pause the user lifts outranks the update, and the update the '
      'bare receiving and sending words', () {
    for (final activity in [SyncActivity.pulling, SyncActivity.pushing]) {
      final updating = busy.copyWith(
        activity: activity,
        updating: true,
        updatingTotal: 120,
      );
      expect(
        lineOf(updating.copyWith(pause: SyncPause.appOutdated)),
        (text: l10n.drawerSyncPausedAppOutdated, isError: true),
        reason: activity.name,
      );
      expect(lineOf(updating.copyWith(pause: SyncPause.noAccess)), (
        text: l10n.drawerSyncPausedNoAccess,
        isError: true,
      ), reason: activity.name);
      expect(
        lineOf(updating.copyWith(pause: SyncPause.spaceDeleted)),
        (text: l10n.drawerSyncPausedSpaceDeleted, isError: true),
        reason: activity.name,
      );
      expect(
        lineOf(updating).text,
        l10n.drawerSyncUpdating(0, 120),
        reason: '${activity.name}: never the bare receiving or sending words',
      );
    }
  });

  test('9: an idle run after a failure says it will retry, offline apart', () {
    final idle = busy.copyWith(activity: SyncActivity.idle);
    expect(lineOf(idle), (text: l10n.drawerSyncRetrying, isError: false));
    expect(
      lineOf(
        idle.copyWith(
          lastFailure: SyncFailureInfo(
            SyncGatewayFailure.offline,
            at: failure.at,
          ),
        ),
      ),
      (text: l10n.syncOffline, isError: false),
    );
  });

  test('10: changes waiting are counted', () {
    final waiting = busy.copyWith(
      activity: SyncActivity.idle,
      clearLastFailure: true,
    );
    expect(lineOf(waiting), (text: l10n.syncPendingCount(4), isError: false));
  });

  test('11: nothing received yet is never synced, a push alone included', () {
    expect(lineOf(SyncStatus(binding: binding, lastPushAt: pushed)), (
      text: l10n.syncNeverSynced,
      isError: false,
    ));
  });

  test('12: otherwise the later of the last push and pull', () {
    expect(
      lineOf(
        SyncStatus(binding: binding, lastPushAt: pushed, lastPullAt: pulled),
      ),
      (text: l10n.syncLastSynced(moment(pulled)), isError: false),
    );
    final later = DateTime.utc(2026, 11, 7, 16);
    expect(
      lineOf(
        SyncStatus(binding: binding, lastPushAt: later, lastPullAt: pulled),
      ),
      (text: l10n.syncLastSynced(moment(later)), isError: false),
    );
  });

  test('13: under the manual cadence a failure promises no retry', () {
    final manual = SyncStatus(
      binding: binding,
      lastFailure: failure,
      lastPullAt: pulled,
      cadence: SyncCadence.manual,
    );

    expect(lineOf(manual), (text: l10n.syncFailedManual, isError: false));
    expect(
      lineOf(
        manual.copyWith(
          lastFailure: SyncFailureInfo(
            SyncGatewayFailure.offline,
            at: failure.at,
          ),
        ),
      ),
      (text: l10n.syncOfflineManual, isError: false),
    );
    expect(l10n.syncOfflineManual, isNot(contains('retry')));
  });

  test('15: under the manual cadence a quota pause names no reset, since '
      'nothing resumes at it', () {
    expect(
      lineOf(
        busy.copyWith(
          pause: SyncPause.quotaExhausted,
          quotaPausedAt: DateTime.utc(2026, 11, 8, 7, 30),
          cadence: SyncCadence.manual,
        ),
      ),
      (text: l10n.drawerSyncPausedQuota, isError: false),
    );
  });

  test('14: under the manual cadence the idle line is still the last sync, '
      'and a pause its pause', () {
    expect(
      lineOf(
        SyncStatus(
          binding: binding,
          lastPullAt: pulled,
          cadence: SyncCadence.manual,
        ),
      ),
      (text: l10n.syncLastSynced(moment(pulled)), isError: false),
    );
    expect(
      lineOf(
        SyncStatus(
          binding: binding,
          pause: SyncPause.noAccess,
          lastFailure: failure,
          cadence: SyncCadence.manual,
        ),
      ),
      (text: l10n.drawerSyncPausedNoAccess, isError: true),
    );
  });

  group('SyncStatus.lastSyncAt', () {
    test('is the later of the two, or whichever is known', () {
      expect(const SyncStatus().lastSyncAt, isNull);
      expect(SyncStatus(lastPushAt: pushed).lastSyncAt, pushed);
      expect(SyncStatus(lastPullAt: pulled).lastSyncAt, pulled);
      expect(
        SyncStatus(lastPushAt: pushed, lastPullAt: pulled).lastSyncAt,
        pulled,
      );
      expect(
        SyncStatus(lastPushAt: pulled, lastPullAt: pushed).lastSyncAt,
        pulled,
      );
    });
  });
}
