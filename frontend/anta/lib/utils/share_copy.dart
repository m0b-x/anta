import '../l10n/app_localizations.dart';

/// The partner's name as the sharing copy says it.
///
/// Every sharing string takes `{name}` undeclined — German and Romanian
/// decline names and a placeholder cannot — so one localized word has to
/// stand in when the partner never published a profile name. Unlike a name,
/// that word is lower case in English and Romanian, which is why a string
/// that begins with `{name}` goes through [sentence].
abstract final class ShareCopy {
  /// [name] as the strings take it: the partner's own, or the localized
  /// stand-in when it is missing or blank.
  static String partnerName(AppLocalizations l10n, String? name) {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return l10n.sharePartnerFallback;
    return trimmed;
  }

  /// [text] with its first letter in upper case, for a string that begins
  /// with `{name}`: the stand-in then starts the sentence as a name would.
  /// A name is left as its owner wrote it in every other position.
  static String sentence(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}
