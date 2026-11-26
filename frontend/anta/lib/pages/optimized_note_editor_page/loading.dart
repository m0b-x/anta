part of '../optimized_note_editor_page.dart';

/// The note's text arriving: the first load, putting a loaded text into the
/// editor, the re-read on the way back from another route, and whether the
/// page holds anything unsaved.
mixin _NoteEditorLoading on _NoteEditorMount {
  /// Asks the shared bloc for this note's text. The only dispatch site of
  /// [LoadNoteContent] in the app, and the only place [_awaitingContentLoad]
  /// is raised — which is what makes the answer *this* page's (C1). The
  /// answer always arrives, even when the bloc last answered with this very
  /// text: see [OptimizedNoteContentLoaded.loadSequence].
  Future<void> _loadNoteContent() async {
    _awaitingContentLoad = true;
    context.read<OptimizedNoteBloc>().add(LoadNoteContent(widget.noteId!));
  }

  /// How many times [_adoptLoadedContent] has run: [_adoptFirstLoad] reads
  /// it across its await to tell whether a reload or a remote arrival
  /// adopted newer text meanwhile.
  int _adoptions = 0;

  /// The last remote update of this note that arrived before the first
  /// load landed, when its handler had nothing to compare against.
  NoteChange? _updatedWhileLoading;

  /// The first load. Above [AppConstants.asyncLineBuildThreshold] the line
  /// split runs off the UI isolate; anything adopted during that await is
  /// newer than this text and wins, and a split that fails falls back to
  /// the synchronous load so the page never stays blank. Reloads and remote
  /// arrivals stay synchronous: they replace text the user is looking at.
  ///
  /// A remote update that arrived before the load landed is replayed
  /// through the normal remote path once it has: the loaded body may be the
  /// one from before the merge, and the next save would bury the merge.
  Future<void> _adoptFirstLoad(String content) async {
    if (content.length <= AppConstants.asyncLineBuildThreshold) {
      _adoptLoadedContent(content);
    } else {
      final before = _adoptions;
      CodeLines? codeLines;
      try {
        codeLines = await content.codeLinesAsync;
      } catch (e, st) {
        debugPrint(
          '[OptimizedNoteEditorPage] Async line split failed: $e\n$st',
        );
      }
      if (!mounted || _adoptions != before) return;
      _adoptLoadedContent(content, codeLines: codeLines);
    }
    final missed = _updatedWhileLoading;
    _updatedWhileLoading = null;
    if (missed != null && mounted) {
      _queueRemote(() => _adoptRemoteUpdate(missed));
    }
  }

  /// Puts [content] into the editor and re-baselines everything derived
  /// from the text it replaces: the stats bar, the edit tracker's length,
  /// and auto-save's saved-content baseline.
  ///
  /// The one path for both the first load and the reload
  /// ([_reloadContentIfChanged]), so the two can never drift apart on which
  /// of those re-baselines they remember to take.
  ///
  /// The undo history necessarily restarts at [content]: `loadText` resets
  /// it, and that is the point — undo must never be able to reach the empty
  /// document the controller was constructed with, nor, on a reload, text
  /// the note no longer holds.
  ///
  /// [keepCaret] re-places the collapsed caret at the (line, column) it
  /// held, clamped to the new document. The reload path needs it: coming
  /// back to a note that changed underneath must not also throw the reader
  /// back to the top of it.
  ///
  /// [titlePending] re-baselines the body alone: a title edit not yet saved
  /// stays pending and the next write carries it (record §3.9, M6).
  ///
  /// [codeLines], when given, are [content] already split into lines (the
  /// first load of a large note, [_adoptFirstLoad]).
  void _adoptLoadedContent(
    String content, {
    bool keepCaret = false,
    bool titlePending = false,
    CodeLines? codeLines,
  }) {
    _adoptions++;
    final previous = keepCaret ? _contentController.selection : null;
    final selected = previous == null || previous.isCollapsed
        ? null
        : _contentController.selectedText;
    // The baseline is taken before the load notifies, so the load never
    // reads as a paste; the count runs after it, through the loaded lines,
    // so the per-line counts are cached for the first pause. Not at all
    // while the bar is hidden.
    _stats.markStale(textLength: content.length);
    // A load, not an edit: the loaded text is the undo baseline.
    setState(() {
      if (codeLines != null) {
        _contentController.loadCodeLines(codeLines, content);
      } else {
        _contentController.loadText(content);
      }
      _contentLoaded = true;
    });
    if (_editorSettings.value.showStatsBar) _stats.resume();
    if (previous != null) {
      final lines = _contentController.codeLines;
      // A selection whose ends both still stand around the same text is
      // kept — someone selecting to copy keeps it through a change that
      // did not touch it; any other collapses to its base.
      bool fits(int index, int offset) =>
          index < lines.length && offset <= lines[index].text.length;
      if (selected != null &&
          fits(previous.baseIndex, previous.baseOffset) &&
          fits(previous.extentIndex, previous.extentOffset)) {
        _contentController.selection = previous;
      }
      if (selected == null || _contentController.selectedText != selected) {
        final index = previous.baseIndex.clamp(0, lines.length - 1);
        final offset = previous.baseOffset.clamp(0, lines[index].text.length);
        // The fork folds a selection-only change into the current undo
        // node, so re-placing the caret here does not give the reload
        // something to undo.
        _contentController.selection = CodeLineSelection.collapsed(
          index: index,
          offset: offset,
        );
      }
    }
    // The tracker never saw the assignment above — only the wrapper calls
    // `onTextChanged`, and on the first load it is not mounted yet — so its
    // baseline is still the previous text's length. Adopt the loaded length
    // before the wrapper starts diffing, or the next keystroke reads as a
    // whole-document paste.
    _edits.syncLength();
    // `loadText` above fired the page's text listener, so auto-save thinks
    // the note was edited into this. Re-baseline before the debounce
    // rewrites what was just read back, with a new `updatedAt`, version and
    // HLC.
    if (titlePending) {
      _saves.adoptStoredContent(content);
    } else {
      _saves.contentLoaded();
    }
    _pushPreviewContent(content);
    _markEditorReady();
  }

  /// Re-reads the note on the way back from a route pushed over this page,
  /// for the case that route was *another editor for the same note* — a
  /// `[[wiki link]]` back to a note already open, or the same note reached
  /// twice through search. Without it this page would keep serving the text
  /// it loaded, and its next keystroke would auto-save that stale text over
  /// everything typed above (C1).
  ///
  /// Only a page with nothing of its own to lose reloads. [didPushNext]
  /// force-saved on the way out, so `hasChanges` being false means the
  /// editor's text is what the row held when we left; a page that is still
  /// dirty (a save that failed, a write still in flight) holds the newer
  /// text and auto-save will write it, so it is left exactly as it is.
  ///
  /// Layering: Page -> Service, like every other read this page owns. A
  /// note that has been deleted meanwhile still reads — the row survives as
  /// a tombstone — so its text may be adopted here; the delete itself
  /// reaches the page as a change event ([_onRemoteDelete]), and a note
  /// that is gone outright reads as null and changes nothing.
  ///
  /// Answers true when the title or the text was adopted, false when the
  /// row held what the page shows, and null when nothing was read or the
  /// page turned dirty during the read — the sync rule (§3.9) files the
  /// arriving text as a copy then.
  Future<bool?> _reloadContentIfChanged() async {
    if (!_contentLoaded) return null;
    if (_hasUnsavedText) return null;
    final noteId = _saves.effectiveNoteId ?? widget.noteId;
    if (noteId == null) return null;

    final lazy = await GetIt.I<NoteStorageService>().loadNoteWithContent(
      noteId,
    );
    if (!mounted || lazy == null) return null;
    // Re-checked after the await: a keystroke landing during the read makes
    // the editor's text the newer one again.
    if (_saves.hasChanges.value) return null;

    // The title is held in a plain controller seeded from `widget.metadata`,
    // not by a bloc, so a rename made in the editor above this one would
    // otherwise leave a stale app-bar title for as long as this page lives.
    final titleChanged = lazy.metadata.title != _titleController.text;
    if (titleChanged) {
      setState(() => _titleController.text = lazy.metadata.title);
    }

    final content = lazy.content ?? '';
    if (content == _contentController.text) {
      // Nothing changed, so nothing is adopted: an unchanged round trip
      // must cost neither the caret nor the undo history. The title write
      // above still fired the page's text listener, so re-baseline
      // auto-save on it before the debounce writes it back.
      if (titleChanged) _saves.contentLoaded();
      return titleChanged;
    }
    _adoptLoadedContent(content, keepCaret: true);
    return true;
  }

  /// The page's own text is newer than the row: an edit auto-save has not
  /// written yet, or a write still in flight.
  bool get _hasUnsavedText =>
      _saves.hasChanges.value || _saves.saveStatus.value == SaveStatus.saving;

  /// The page's body differs from the text it last loaded or saved. The body
  /// alone, never the title: a pending title edit leaves nothing to defend,
  /// and [_adoptRemoteUpdate] reloads the arriving body in place (M6).
  /// Never on a read-only page: it takes no edit, and its coordinator, off
  /// for good, holds no baseline to compare against.
  bool get _bodyIsUnsaved =>
      !_readOnly &&
      _contentLoaded &&
      !_saves.isSavedContent(_contentController.text);
}
