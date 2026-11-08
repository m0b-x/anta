import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

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
