import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/event_digest.dart';

export 'digest_notification_content.dart'
    show digestCategoriesLabel, digestPeriodOf, digestTitleOf;

/// "Monthly on the 1st, 09:00" — how [digest] fires, the line the hub's row
/// and the digest sheet read it back with (the `EventAlert.describe` rule:
/// one formatter for every surface).
///
/// Pure: [formatMinute] writes the time on the phone's clock and
/// [weekdayName] a weekday (`DateTime.monday` .. `DateTime.sunday`) in the
/// language's own words — both from `intl`, never an ARB matrix.
String digestDescribe(
  EventDigest digest,
  AppLocalizations l10n, {
  required String Function(int minute) formatMinute,
  required String Function(int weekday) weekdayName,
}) {
  final time = formatMinute(digest.minute);
  final anchor = EventDigest.clampAnchor(digest.cadence, digest.anchor);
  return switch (digest.cadence) {
    DigestCadence.daily => l10n.digestDescribeDaily(time),
    DigestCadence.weekly => l10n.digestDescribeWeekly(
      weekdayName(anchor),
      time,
    ),
    DigestCadence.monthly => l10n.digestDescribeMonthly(
      digestDayOfMonth(anchor, l10n),
      time,
    ),
    DigestCadence.weeklyReport => l10n.digestDescribeWeeklyReport(
      weekdayName(anchor),
      time,
    ),
    DigestCadence.monthlyReport => l10n.digestDescribeMonthlyReport(
      digestDayOfMonth(anchor, l10n),
      time,
    ),
  };
}

/// A monthly digest's day in its bare form — "1st", "1.", "1": each
/// language writes its own ordinal around the digits, so none is built
/// here; the preposition belongs to the sentence around it.
String digestDayOfMonth(int day, AppLocalizations l10n) =>
    l10n.digestOnDayOfMonth('$day');

/// [weekday]'s full name in [localeName], as `intl` writes it inside a
/// sentence ("Monday", "Montag", "luni") — 2024-01-01 was a Monday.
String digestWeekdayName(int weekday, String localeName) =>
    DateFormat.EEEE(localeName).format(DateTime.utc(2024, 1, weekday));
