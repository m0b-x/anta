import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// One [DateFormat] of a demo, made again only when the language changes:
/// a format parses its pattern when it is made, and a stage or a caption
/// that made one per build paid that on every keystroke and every tap.
class GuideLocaleFormat {
  GuideLocaleFormat(this._make);

  final DateFormat Function(String localeName) _make;
  DateFormat? _format;
  String? _localeName;

  DateFormat of(AppLocalizations l10n) {
    final format = _format;
    if (format != null && _localeName == l10n.localeName) return format;
    _localeName = l10n.localeName;
    return _format = _make(l10n.localeName);
  }
}
