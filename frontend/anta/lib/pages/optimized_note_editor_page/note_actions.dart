part of '../optimized_note_editor_page.dart';

/// What the bar and its ⋮ menu do to the note: saving on the way out,
/// opening its folder, moving, labelling, copying, deleting, exporting,
/// renaming, and jumping to an edge.
mixin _NoteEditorNoteActions on _NoteEditorRemote {
  Future<void> _saveBeforeExit() async {
    _contentFocusNode.unfocus();
    await _saveCurrentPosition();
    await _saves.saveBeforeExit();
  }

  /// The way out's last word on the text of a note deleted elsewhere that
  /// is still not filed as a new note: one more try, and when that fails too
  /// the page stays, the notice up — leaving would take the only copy of the
  /// text with it, since the exit's write to the tombstone is refused (M3).
  ///
  /// The remote chain as it stands is waited for, not just the list: a
  /// delete handler already queued has not listed its filing yet, and an
  /// exit that read the list a tick earlier would leave with the text (M1).
  /// One turn of it and one retry, never [_awaitRemoteWork]'s "until nothing
  /// is pending at all": a pull streaming page after page keeps something
  /// pending, and the exit would never resolve — with `canPop` false and
  /// [_isExiting] true, the back presses after it are swallowed in silence
  /// (A6 review R109).
  Future<bool> _keptDeletedNotesText() async {
    if (_remoteBusy == 0 && !_holdsDeletedNotesText) return true;
    // This try is its own news: the filing's notice bookkeeping is re-armed
    // so `_run` raises it once, instead of the exit raising the same error a
    // second time beside it (L6).
    for (final filing in _unfiled) {
      if (filing.keepsText) filing.failed = false;
    }
    await _remoteWork;
    if (mounted) await _retryUnfiled();
    if (!mounted) return false;
    if (_holdsDeletedNotesText) {
      // The retry can join an attempt that had already failed this filing,
      // where `_run` says nothing — then the page stays with no word at all
      // (A6 review R111).
      _raiseFilingFailure(_unfiled.firstWhere((f) => f.keepsText));
      return false;
    }
    // Filed with the text as it stands; anything the retarget still reads
    // as unsaved goes into the new note before the page leaves.
    try {
      await _saves.saveBeforeExit();
    } catch (e) {
      debugPrint('[NoteEditor] save before exit failed: $e');
    }
    return mounted;
  }

  /// "Copy to my notes" from the ⋮ menu of the partner's note.
  Future<void> _copyToMine() async {
    final metadata = await _currentNoteMetadata();
    if (!mounted || metadata == null) return;
    await copySharedNoteToMine(context, metadata, partnerName: _partnerName);
  }

  /// The note as it is stored right now.
  ///
  /// Every menu row that hands the note to another layer — move, share —
  /// needs the persisted row, not the editor's text: the move writes a new
  /// `folderId` onto it, and the export re-reads the content by id. So the
  /// editor flushes first and reads back what landed — a plain flush, not
  /// an exit's: the page stays, and its writes keep every hold (M4).
  ///
  /// So the row can be older than the editor, and nothing is handed on while
  /// it is: the flush is held until every synced change is filed, and a
  /// filing that keeps failing would otherwise let the move carry the stored
  /// body and the export ship it, silently (R18). The filing's own notice
  /// says why instead.
  ///
  /// Null is always reported before it is returned — the filing's notice, or
  /// "note not found" — so a caller only has to stop.
  Future<NoteMetadata?> _currentNoteMetadata() async {
    if (!await _awaitRemoteWork(leaving: false)) {
      // The deleted note's text first, the more urgent of the two, as
      // [_showFilingNoticeOwed] prefers it (R127) — and only when the wait's
      // own retry did not already raise it, which is the ordinary case here:
      // the user taps Move while the merge handler is filing, so `_run` saw
      // that filing's first failure (R110).
      _raiseFilingFailure(
        _unfiled.firstWhere((f) => f.keepsText, orElse: () => _unfiled.first),
      );
      return null;
    }
    if (!mounted) return null;
    await _saves.flush();
    if (!mounted) return null;
    final noteId = _saves.effectiveNoteId ?? widget.noteId;
    final metadata = noteId == null
        ? null
        : await GetIt.I<NoteStorageService>().getNoteMetadata(noteId);
    if (metadata == null && mounted) {
      CustomSnackbar.showError(
        context,
        AppLocalizations.of(context)!.noteNotFound,
      );
    }
    return metadata;
  }

  /// Returns to the folder this note lives in, playing one transition even
  /// when the note was reached through a chain of wiki links.
  ///
  /// [_isExiting] is held for the whole way out, as the `PopScope` handler
  /// holds it: a remote delete arriving while `popToFolder` runs would
  /// otherwise still reach [_leaveRemotelyDeleted] and pop a second route
  /// (R19).
  ///
  /// A note can sit under a deleted folder until the sync repair re-files it:
  /// the row then opens the nearest live folder, the root when there is none,
  /// never a page for the tombstone (P review PR3).
  Future<void> _openFolder() async {
    if (_isExiting) return;
    _isExiting = true;
    try {
      await _saveBeforeExit();
    } catch (e) {
      debugPrint('[NoteEditor] save before open folder failed: $e');
    }
    if (!mounted) return;
    if (!await _keptDeletedNotesText()) {
      _isExiting = false;
      _saves.exitAborted();
      return;
    }
    if (!mounted) return;
    final folderId = await GetIt.I<FolderStorageService>().nearestLiveFolderId(
      _folderId,
    );
    if (!mounted) return;
    if (folderId.isEmpty) {
      await AppNavigator.popToAncestor(context);
    } else {
      await AppNavigator.popToFolder(
        context,
        folderId: folderId,
        title: folderId == _folderId ? _folderName ?? '' : '',
        // A partner's note lies in her folder; anything else is left to
        // the folder page.
        fromPartner: folderId == _folderId && _readOnly ? true : null,
      );
    }
    if (mounted && _isCurrentRoute) {
      _isExiting = false;
      _saves.exitAborted();
    }
  }

  Future<void> _moveNote() async {
    final metadata = await _currentNoteMetadata();
    if (!mounted || metadata == null) return;
    await MoveCoordinator.moveNote(
      context,
      metadata: metadata,
      currentFolderId: _folderId,
    );
    if (!mounted) return;
    final moved = await GetIt.I<NoteStorageService>().getNoteMetadata(
      metadata.id,
    );
    if (!mounted || moved == null || moved.folderId == _folderId) return;
    final readFacts = moved.inSharedFolder && !_inSharedFolder;
    setState(() {
      _folderId = moved.folderId;
      _folderName = null;
      _inSharedFolder = moved.inSharedFolder;
    });
    unawaited(_loadFolderName());
    if (readFacts) unawaited(_loadShareFacts());
  }

  /// Assigns the note's colour label from the editor.
  ///
  /// The current value is read back from storage rather than from
  /// `widget.metadata`, which is whatever the browser held when it pushed
  /// this page. Deliberately no flush first: a label is not an edit, and the
  /// partial companion `updateNote` writes never touches the column.
  Future<void> _labelNote() async {
    final noteId = _saves.effectiveNoteId ?? widget.noteId;
    if (noteId == null) return;
    final current = await GetIt.I<NoteStorageService>().getNoteMetadata(noteId);
    if (!mounted) return;
    if (current == null) {
      CustomSnackbar.showError(
        context,
        AppLocalizations.of(context)!.noteNotFound,
      );
      return;
    }
    final picked = await showLabelPickerSheet(context, value: current.label);
    if (!mounted || picked == null || picked == current.label) return;
    context.read<OptimizedNoteBloc>().add(
      SetOptimizedNoteLabel(noteId: noteId, label: picked),
    );
  }

  /// Deletes the note the editor is showing, then leaves.
  ///
  /// The order is the whole point: saving is switched off *before* the
  /// delete is dispatched, because a debounced auto-save landing afterwards
  /// would write into a row that is already a tombstone, and the early
  /// create of a never-persisted note would bring it back outright.
  /// "Confirm before delete" off skips the dialog (record D24).
  Future<void> _deleteNote() async {
    final l10n = AppLocalizations.of(context)!;
    final noteId = _saves.effectiveNoteId ?? widget.noteId;
    final title = _titleController.text.trim();
    final settings = await SettingsService.getInstance();
    final confirm = await settings.getConfirmDelete();
    if (!mounted) return;
    if (confirm) {
      final confirmed = await AppDialogs.confirm(
        context,
        title: l10n.deleteNote,
        content: l10n.deleteNoteConfirm(
          title.isEmpty ? l10n.deleteThisNote : title,
        ),
        confirmText: l10n.delete,
        isDestructive: true,
      );
      if (!confirmed || !mounted) return;
    }
    _saves.disableSaves();
    if (noteId != null) {
      context.read<OptimizedNoteBloc>().add(DeleteOptimizedNote(noteId));
    }
    AppNavigator.pop(context);
  }

  Future<void> _showExportFormatDialog() async {
    final format = await NoteExportDialog.chooseFormat(context);
    if (format == null || !mounted) return;
    final metadata = await _currentNoteMetadata();
    if (!mounted || metadata == null) return;
    context.read<ImportExportBloc>().add(
      ExportNoteRequested(metadata: metadata, format: format, share: true),
    );
  }

  void _editTitle() async {
    final l10n = AppLocalizations.of(context)!;
    // Answers of the folder's title check, by lower-cased title; the dialog
    // asks again as each one lands, so a taken title is flagged before Save.
    final taken = <String, bool>{};
    final answers = ValueNotifier<int>(0);
    var open = true;
    String? warningFor(String text) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return null;
      final key = trimmed.toLowerCase();
      if (!taken.containsKey(key)) {
        taken[key] = false;
        GetIt.I<NoteStorageService>()
            .noteTitleExistsInFolder(
              folderId: _folderId,
              title: trimmed,
              excludeId: _saves.effectiveNoteId,
            )
            .then((exists) {
              if (!exists || !open) return;
              taken[key] = true;
              answers.value++;
            }, onError: (Object _) {});
      }
      return taken[key]! ? l10n.noteTitleAlreadyExists(trimmed) : null;
    }

    final newTitle = await AppDialogs.textInput(
      context,
      title: l10n.editTitle,
      hintText: l10n.enterNoteTitle,
      initialValue: _titleController.text,
      confirmText: l10n.save,
      selectAll: true,
      warningFor: warningFor,
      warningRefresh: answers,
    );
    open = false;
    answers.dispose();
    if (newTitle == null || !mounted) return;
    setState(() {
      _titleController.text = newTitle;
    });
  }

  void _scrollToEdge({required bool toTop}) {
    if (_showPreview) {
      if (toTop) {
        _previewController.scrollToTop();
      } else {
        _previewController.scrollToBottom();
      }
    } else {
      if (toTop) {
        _contentController.selection = CodeLineSelection.collapsed(
          index: 0,
          offset: 0,
        );
      } else {
        final lastIndex = _contentController.codeLines.length - 1;
        final lastLineLength =
            _contentController.codeLines[lastIndex].text.length;
        _contentController.selection = CodeLineSelection.collapsed(
          index: lastIndex,
          offset: lastLineLength,
        );
      }
      _editorScrollController.makeCenterIfInvisible(
        _contentController.selection.extent,
      );
    }
  }
}
