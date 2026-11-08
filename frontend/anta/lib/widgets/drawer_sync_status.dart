import '../l10n/app_localizations.dart';
import '../services/sync/sync_gateway.dart';
import '../services/sync/sync_status.dart';

/// The drawer account row's one status line, and whether it is drawn in the
/// error colour: only the three pauses the user has to lift are (§12 (e) of
/// `docs/cloud-sync-phase-02-own-space.md`).
///
/// The order is the Sync section's — a pause outranks a run, and a run the
/// last failure it will retry — but the pauses and the retry have words of
/// their own: the page's are cut off in the drawer's narrower column (§12
/// (h)). Only the
/// waiting count is said; the sending and held-back counts stay on the page
/// (§12 (i)). [formatMoment] words the last sync, as the page does;
/// [formatQuotaReset] the reset a quota pause waits for, said only while it
/// is still ahead of [now] — after it, the reason alone.
({String text, bool isError}) drawerSyncStatusLine(
  AppLocalizations l10n,
  SyncStatus status, {
  required String Function(DateTime at) formatMoment,
  required String Function(DateTime reset) formatQuotaReset,
  DateTime? now,
}) {
  if (status.binding == null) {
    return (text: l10n.drawerAccountNotSyncing, isError: false);
  }
  switch (status.pause) {
    case SyncPause.quotaExhausted:
      final reset = status.quotaResetAfter(now ?? DateTime.now());
      return (
        text: reset == null
            ? l10n.drawerSyncPausedQuota
            : l10n.drawerSyncPausedQuotaUntil(formatQuotaReset(reset)),
        isError: false,
      );
    case SyncPause.signedOut:
      return (text: l10n.syncPausedSignedOut, isError: false);
    case SyncPause.accountMismatch:
      return (text: l10n.drawerSyncPausedOtherAccount, isError: true);
    case SyncPause.appOutdated:
      return (text: l10n.drawerSyncPausedAppOutdated, isError: true);
    case SyncPause.noAccess:
      return (text: l10n.drawerSyncPausedNoAccess, isError: true);
    case SyncPause.none:
      break;
  }
  switch (status.activity) {
    case SyncActivity.pushing:
      return (text: l10n.syncSending(0), isError: false);
    case SyncActivity.pulling:
      return (text: l10n.syncReceiving, isError: false);
    case SyncActivity.idle:
      break;
  }
  if (status.lastFailure case final failure?) {
    return (
      text: failure.failure == SyncGatewayFailure.offline
          ? l10n.syncOffline
          : l10n.drawerSyncRetrying,
      isError: false,
    );
  }
  if (status.pendingCount > 0) {
    return (text: l10n.syncPendingCount(status.pendingCount), isError: false);
  }
  // A push alone is not a sync the user can rely on: nothing has been
  // received yet, as the page's "Waiting for the first sync" says.
  final pulled = status.lastPullAt;
  if (pulled == null) return (text: l10n.syncNeverSynced, isError: false);
  return (
    text: l10n.syncLastSynced(formatMoment(status.lastSyncAt ?? pulled)),
    isError: false,
  );
}
