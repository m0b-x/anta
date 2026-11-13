import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/share_overview.dart' show ShareChange;

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
  /// A name is left as its owner wrote it in every other position — and an
  /// address in this one too: an account with no profile name publishes
  /// its e-mail address, which no sentence capitalises.
  static String sentence(String text) {
    if (text.isEmpty) return text;
    final end = text.indexOf(' ');
    final first = end < 0 ? text : text.substring(0, end);
    if (first.contains('@')) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  /// What a folder's share act did, in one sentence — the words of the
  /// Sharing page's folder sheet and of a folder's own share entry, so the
  /// two never drift: "Sharing {folder} with {name}", "{inner} is now
  /// shared through {outer}" when the share covered a folder inside it, and
  /// "No longer shared: {folder}" — "… and 2 folders inside it" when the
  /// un-share also took the marks of folders inside it, which an Undo marks
  /// again. Null for an act that wrote nothing — a folder shared already.
  static String? folderAct(
    AppLocalizations l10n,
    ShareChange change, {
    required String? partnerName,
  }) {
    final shared = change.sharedFolders.firstOrNull;
    if (shared != null) {
      final covered = change.coveredFolders.firstOrNull;
      return covered == null
          ? l10n.shareStarted(
              shared.name,
              ShareCopy.partnerName(l10n, partnerName),
            )
          : l10n.shareNowThrough(covered.name, shared.name);
    }
    final unshared = change.unsharedFolders.firstOrNull;
    if (unshared == null) return null;
    final inner = change.clearedInnerFolders.length;
    return inner == 0
        ? l10n.shareStopped(unshared.name)
        : l10n.shareStoppedWithInner(unshared.name, inner);
  }

  /// A category row's caption — the Categories page's rows, mine and the
  /// partner's, and the received categories sheet's: [parts] joined by
  /// [AppConstants.captionSeparator], whose no-break space binds each dot
  /// to the word before it, so a wrapped line never starts with a dot.
  ///
  /// The first part's last no-break space — a count bound to its noun,
  /// "123 Ereignisse" — becomes a plain one: bound to the dot as well, that
  /// run can be wider than a narrow column at 2.0, and the line breaker then
  /// cuts it just before the dot. Free there, the noun goes down with its
  /// dot. Only the first part, which starts the line: anywhere else a bound
  /// run moves down whole.
  static String caption(List<String> parts) {
    if (parts.length < 2) return parts.join();
    final first = parts.first;
    final glue = first.lastIndexOf(' ');
    return [
      if (glue < 0)
        first
      else
        '${first.substring(0, glue)} ${first.substring(glue + 1)}',
      ...parts.skip(1),
    ].join(AppConstants.captionSeparator);
  }
}
