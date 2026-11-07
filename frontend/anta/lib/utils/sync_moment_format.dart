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
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }
  final localeName = AppLocalizations.of(context)!.localeName;
  return local.year == today.year
      ? DateFormat.MMMd(localeName).format(local)
      : DateFormat.yMMMd(localeName).format(local);
}
