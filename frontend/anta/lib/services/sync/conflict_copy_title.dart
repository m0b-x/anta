import '../../constants/app_constants.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/text_fit.dart';

/// D3's title for the copy of a note titled [loserTitle] filed at [at]:
/// "`<title>` (conflict copy, `<date time>`)", then ` (n)` from the second
/// copy of the same minute on — literal, as the import pipeline numbers a
/// clashing title. Shared by the engine's copy and the open editor's (record
/// §3.9), so the two read alike.
///
/// An untitled loser is named as the browser names it rather than leaving a
/// leading space, and a long one is cut on a whole character ([TextFit]) so
/// the whole fits the title column: a copy filed inside a pulled page that
/// the column refused would roll the page back on every run (S3c review F3).
String conflictCopyTitle(
  AppLocalizations strings,
  String loserTitle,
  DateTime at, {
  int copy = 1,
}) {
  final suffix = copy < 2 ? '' : ' ($copy)';
  final frame = strings.syncConflictCopyTitle('', at).length + suffix.length;
  final room = AppConstants.maxNoteTitleLength - frame;
  final title = TextFit.cut(
    loserTitle.trim().isEmpty ? strings.untitledNote : loserTitle,
    room,
  );
  return '${strings.syncConflictCopyTitle(title, at)}$suffix';
}
