import '../../constants/app_constants.dart';
import '../../l10n/app_localizations.dart';

/// D3's title for the copy of a note titled [loserTitle] filed at [at]:
/// "`<title>` (conflict copy, `<date time>`)", then ` (n)` from the second
/// copy of the same minute on — literal, as the import pipeline numbers a
/// clashing title. Shared by the engine's copy and the open editor's (record
/// §3.9), so the two read alike.
///
/// An untitled loser is named as the browser names it rather than leaving a
/// leading space, and a long one is cut so the whole fits the title column:
/// a copy filed inside a pulled page that the column refused would roll the
/// page back on every run (S3c review F3).
String conflictCopyTitle(
  AppLocalizations strings,
  String loserTitle,
  DateTime at, {
  int copy = 1,
}) {
  final suffix = copy < 2 ? '' : ' ($copy)';
  final frame = strings.syncConflictCopyTitle('', at).length + suffix.length;
  final room = AppConstants.maxNoteTitleLength - frame;
  var title = loserTitle.trim().isEmpty ? strings.untitledNote : loserTitle;
  if (title.length > room) {
    title = title.substring(0, room);
    // Never leave half of a surrogate pair behind the cut.
    final last = title.codeUnitAt(title.length - 1);
    if (last >= 0xD800 && last <= 0xDBFF) {
      title = title.substring(0, title.length - 1);
    }
  }
  return '${strings.syncConflictCopyTitle(title, at)}$suffix';
}
