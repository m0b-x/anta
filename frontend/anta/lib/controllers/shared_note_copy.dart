import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/note_metadata.dart';
import '../services/app_navigator.dart';
import '../services/duplicate_name_exception.dart';
import '../services/note_storage_service.dart';
import '../services/share_service.dart';
import '../utils/share_copy.dart';
import '../widgets/folder_picker_dialog.dart';
import '../widgets/overlay_snackbar.dart';

/// "Copy to my notes" (share surfaces §6.13, D19): the one deliberate act
/// that makes a partner's [note] mine — the editor's ⋮ menu and a partner
/// row's long-press sheet both run it.
///
/// The person picks one of their own folders (the partner's are no
/// destination, nor the root, where no note lives); the copy is created
/// there, opens in the editor on top of [context]'s route — Back returns to
/// the partner's note — and one line says it no longer follows the source.
/// A title the folder already holds says so and copies nothing.
///
/// [partnerName] is the name the caller already holds; null reads it.
/// Returns the copy, or null when nothing was copied.
Future<NoteMetadata?> copySharedNoteToMine(
  BuildContext context,
  NoteMetadata note, {
  String? partnerName,
}) async {
  final l10n = AppLocalizations.of(context)!;
  // The picker lists none of the partner's folders.
  final target = await showFolderPickerDialog(
    context,
    currentFolderId: '',
    allowRoot: false,
    purpose: FolderPickPurpose.copy,
  );
  if (target == null || target.isEmpty || !context.mounted) return null;

  // The app's own, which outlive the page that asked: a copy made after it
  // left — the partner's note un-shared under the open picker, a Back mid
  // write — is still opened and still said.
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String message) {
    if (context.mounted) {
      _say(context, message);
    } else {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: AppConstants.snackbarDuration,
        ),
      );
    }
  }

  final NoteMetadata? copy;
  try {
    copy = await GetIt.I<NoteStorageService>().copyToMine(note.id, target);
  } on DuplicateNameException catch (e) {
    say(l10n.noteTitleAlreadyExists(e.name));
    return null;
  } on FolderGoneException {
    say(l10n.sharedNoteCopyFolderGone);
    return null;
  } catch (e, st) {
    debugPrint('[SharedNoteCopy] copy failed: $e\n$st');
    say(l10n.error('$e'));
    return null;
  }
  // The source left while the picker was open: the page it was open on
  // closes and says so, and that is the one line.
  if (copy == null) return null;
  final name = ShareCopy.partnerName(l10n, partnerName ?? await _partnerName());
  if (!navigator.mounted) return copy;
  // Not awaited: the push answers when the copy's editor is popped. The
  // line is raised once its route is in, on the overlay above it.
  AppNavigator.toNoteEditor(
    context.mounted ? context : navigator.context,
    folderId: copy.folderId,
    noteId: copy.id,
    metadata: copy,
  );
  say(l10n.sharedNoteCopied(name));
  return copy;
}

/// The overlay's bar: the editor's Scaffold does not resize for the
/// keyboard, and a row's sheet would cover a Scaffold's bar.
void _say(BuildContext context, String message) => OverlaySnackbar.show(
  context,
  message,
  duration: AppConstants.snackbarDuration,
);

Future<String?> _partnerName() async {
  try {
    return (await ShareService.getInstance())
        .availability
        .audience
        ?.displayName;
  } catch (e) {
    debugPrint('[SharedNoteCopy] partner not read: $e');
    return null;
  }
}
