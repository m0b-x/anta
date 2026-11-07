import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/sync_binding.dart';
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

  ({String text, bool isError}) lineOf(SyncStatus status) =>
      drawerSyncStatusLine(l10n, status, formatMoment: moment);

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

  test('2: the quota pause has the drawer\'s short words', () {
    expect(lineOf(busy.copyWith(pause: SyncPause.quotaExhausted)), (
      text: l10n.drawerSyncPausedQuota,
      isError: false,
    ));
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
