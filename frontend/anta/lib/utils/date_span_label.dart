import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// "Sep 25 – Oct 16, 2026" — the one grammar for a span of days, shared by
/// the Dates sheet's summary, its range mode and the overview's custom
/// period so a span reads the same wherever it is shown. Both years are
/// named when the span crosses one.
String dateSpanLabel(AppLocalizations l10n, DateTime first, DateTime last) {
  final localeName = l10n.localeName;
  final firstLabel = first.year == last.year
      ? DateFormat.MMMd(localeName).format(first)
      : DateFormat.yMMMd(localeName).format(first);
  final lastLabel = DateFormat.yMMMd(localeName).format(last);
  return '$firstLabel – $lastLabel';
}
