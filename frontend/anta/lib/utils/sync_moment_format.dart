import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/sync/sync_status.dart';

/// A sync time as the Sync section, the picker and the drawer say it: the
/// time of day when it is today — a sync minutes ago is what the owner
/// checks — else the date, with the year only when it is not this one.
String formatSyncMoment(BuildContext context, DateTime at, {DateTime? now}) {
  final local = at.toLocal();
  final today = now ?? DateTime.now();
  if (DateUtils.isSameDay(local, today)) {
    return formatSyncTimeOfDay(context, TimeOfDay.fromDateTime(local));
  }
  final localeName = AppLocalizations.of(context)!.localeName;
  return local.year == today.year
      ? DateFormat.MMMd(localeName).format(local)
      : DateFormat.yMMMd(localeName).format(local);
}

/// [time] as the device says a time of day, 24-hour or not.
String formatSyncTimeOfDay(BuildContext context, TimeOfDay time) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      time,
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// The time of day the quota pause ends, [reset] being that reset: the time
/// alone, since the pause words it only while the reset is still ahead and
/// a reset is at most a day and an hour away.
String formatSyncQuotaReset(BuildContext context, DateTime reset) =>
    formatSyncTimeOfDay(context, TimeOfDay.fromDateTime(reset.toLocal()));

/// What the Sync page says while a run that cut over to a new sync wire
/// reads every note again and then sends them ([SyncStatus.updating]),
/// null for any other run: it is said before the pulling and pushing
/// words, since it is what keeps the browser and the calendar slow for a
/// while after an update.
String? syncUpdatingText(AppLocalizations l10n, SyncStatus status) {
  if (_updatingProgress(status) case (final done, final total)) {
    return status.updatingSending
        ? l10n.syncUpdatingSending(done, total)
        : l10n.syncUpdatingNotes(done, total);
  }
  return status.updating ? l10n.syncUpdating : null;
}

/// [syncUpdatingText] in the drawer's words, one for both phases: the
/// drawer's row is one line below the two-line text scale and would cut the
/// page's.
String? drawerSyncUpdatingText(AppLocalizations l10n, SyncStatus status) {
  if (_updatingProgress(status) case (final done, final total)) {
    return l10n.drawerSyncUpdating(done, total);
  }
  return status.updating ? l10n.drawerSyncUpdatingNoTotal : null;
}

/// The cutover's count of its current phase and that phase's total, while
/// both are known. The count is held to the total: notes another device
/// added, or this one saved, after the total was read are synced too. The
/// phase is [SyncStatus.updatingSending], which the engine flips with the
/// total, never the activity, which says pulling until the drain's first
/// batch.
(int, int)? _updatingProgress(SyncStatus status) {
  final total = status.updatingTotal;
  if (!status.updating || total == null) return null;
  final done = status.updatingSending
      ? status.updatingSent
      : status.downloadedRows;
  return (math.min(done, total), total);
}
