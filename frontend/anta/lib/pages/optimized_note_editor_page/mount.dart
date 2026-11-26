part of '../optimized_note_editor_page.dart';

/// Getting the page on screen and keeping it current: the settings bundle
/// and its changes, the gate the editor mounts behind, the heading or the
/// new note it opens on, and what is persisted when the app is suspended.
mixin _NoteEditorMount on _NoteEditorInputs {
  /// The editor gained or lost the IME. [_keyboardInset] reads the focus
  /// state directly, so the listener only has to ask for a rebuild.
  void _onContentFocusChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// The settings bundle changed — the first load, or a return from a
  /// page that edited one of them (B3). Rebuilds, then re-derives
  /// everything the page keeps outside the bundle.
  void _onEditorSettingsChanged() {
    if (!mounted) return;
    final settings = _editorSettings.value;
    setState(() {
      // The preview just became unreachable while the user was looking at
      // it — the only mode change a settings load may force. On the first
      // load [_isPreviewMode] is still false, so this is a no-op there and
      // [_applySavedPreviewMode] stays the only thing that turns it on.
      if (!settings.canPreview) _isPreviewMode = false;
    });
    _previewBloc.add(
      PreviewLinesPerChunkChanged(settings.previewLinesPerChunk),
    );
    // The preview owns its font size in bloc state, so the settings row
    // is pushed across only when the two have actually drifted apart —
    // which is what a font-size tap does.
    if (settings.previewFontSize != _previewBloc.state.fontSize) {
      _previewBloc.add(PreviewFontSizeChanged(settings.previewFontSize));
    }
    // Only when one of the two settings it consumes actually moved: the
    // bundle notifies on every font-size tap as well.
    if (_appliedVocabularySettings !=
        (
          enabled: settings.vocabularySuggestionsEnabled,
          trigger: settings.vocabularyTriggerChar,
        )) {
      unawaited(_refreshVocabularies());
    }
    if (settings.showStatsBar) _stats.resume();
    _saves.configureAutoSave(
      enabled: settings.autoSaveEnabled,
      intervalSeconds: settings.autoSaveIntervalSeconds,
    );
    _markEditorReady();
  }

  /// Re-reads the settings bundle plus the two resolved render settings
  /// that are not part of it. Called from [initState] and from
  /// [didPopNext], which is what makes an editor flag changed on the
  /// settings page apply on the way back (B3).
  ///
  /// The first run also opens the render half of the mount gate — in a
  /// `finally`, so a read that throws still lets the editor mount rather
  /// than leaving the page blank for good. The two resolved settings are
  /// independent reads and run side by side.
  Future<void> _reloadSettings() async {
    try {
      await _editorSettings.reload();
      if (!mounted) return;
      await Future.wait([_refreshMoneyConfig(), _refreshColorPalette()]);
    } finally {
      if (!_renderConfigLoaded && mounted) {
        setState(() => _renderConfigLoaded = true);
        _markEditorReady();
      }
    }
  }

  /// The stored position has settled (read, failed or nothing to read), so
  /// the mount gate may open. Runs off the unawaited load, hence the
  /// `mounted` check; the rebuild is what mounts the editor when this was
  /// the last of the three loads.
  void _onPositionLoaded() {
    if (!mounted) return;
    setState(() {});
    _markEditorReady();
  }

  /// Every part of the mount gate has landed: the controller holds the
  /// note and the stored position is known, so a restored caret set now
  /// will stick and the editor — which mounts on the very next frame —
  /// lays itself out around it. Called from every load; the position
  /// controller latches, so whichever lands last is the one that opens
  /// the restore (B2).
  void _markEditorReady() {
    if (_isLoading) return;
    _position.contentReady();
    _applyTargetHeadingOnce();
    _focusNewNoteOnce();
  }

  /// Lands on [OptimizedNoteEditorPage.targetHeading], once. Runs right
  /// after the restore join, so the stored caret it replaces has already
  /// been set and its layout-time centring is still unconsumed — this
  /// request replaces it, and the first frame shows the heading. A
  /// heading the note does not hold leaves the restored position alone.
  void _applyTargetHeadingOnce() {
    final heading = widget.targetHeading;
    if (heading == null || _targetHeadingApplied) return;
    _targetHeadingApplied = true;
    if (_showPreview) return;
    final line = _headingLine(heading);
    if (line < 0) return;
    _contentController.selection = CodeLineSelection.collapsed(
      index: line,
      offset: 0,
    );
    _editorScrollController.makeCenterIfInvisibleOnLayout(
      CodeLinePosition(index: line, offset: 0),
    );
  }

  /// The first line outside a fence whose heading reads as [fragment], or
  /// -1. Each of [MarkdownWikiTarget.headingReadingsOf] is tried over the
  /// whole note in turn, and a heading matches by its source text or by
  /// the text it shows — markup, `[[…]]` brackets and a closing `#` run
  /// dropped, as Obsidian compares rendered headings — trimmed and
  /// case-insensitively. Heading shape and the closing run's end come from
  /// [MarkdownLineShape.headingAt], as everywhere else, so neither reading
  /// strips a second run (`## Foo # ##` reads `Foo #`, never `Foo`).
  int _headingLine(String fragment) {
    final readings = MarkdownWikiTarget.headingReadingsOf(fragment);
    if (readings.isEmpty) return -1;
    final codeLines = _contentController.codeLines;
    final lines = <int>[];
    final texts = <(String, String)>[];
    for (int i = 0; i < codeLines.length; i++) {
      // A setext heading is its whole text line; the underline (negative)
      // is chrome.
      if (_render.headingLevelAt(i) <= 0) continue;
      final text = codeLines[i].text;
      final match = MarkdownLineShape.headingAt(text);
      lines.add(i);
      texts.add((
        match == null
            ? text.trim()
            : text.substring(match.contentStart, match.contentEnd).trim(),
        MarkdownPlainText.strip(text, maxLength: 0, money: false),
      ));
    }
    for (final reading in readings) {
      final wanted = reading.toLowerCase();
      for (int k = 0; k < lines.length; k++) {
        if (texts[k].$1.toLowerCase() == wanted ||
            texts[k].$2.toLowerCase() == wanted) {
          return lines[k];
        }
      }
    }
    return -1;
  }

  /// A new note opens ready to type, keyboard up: there is nothing to read
  /// in it, so the tap into the body the user would otherwise need is pure
  /// overhead. Post-frame, because the editor mounts on the frame the gate
  /// opens; latched, because the gate's callers run again on every settings
  /// reload. An existing note opens unfocused, as it always has.
  void _focusNewNoteOnce() {
    if (widget.noteId != null || _newNoteFocusRequested) return;
    _newNoteFocusRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentFocusNode.requestFocus();
    });
  }

  /// Persists everything that must survive the OS suspending or killing
  /// the app: the reading position, the note itself, and any font size
  /// the user tapped moments ago (whose write is debounced).
  void _saveOnLifecycleEvent() {
    unawaited(_saveCurrentPosition());
    _saves.saveOnLifecyclePause();
    unawaited(_editorSettings.flushPendingWrites());
  }

  /// Debounced reaction to preview scroll progress changes; persists the
  /// position so a hot reload / app suspend / page rebuild keeps the
  /// reader anchored.
  void _onPreviewProgressChanged() {
    if (!_isPreviewMode) return;
    _position.debounceSave(
      const Duration(milliseconds: 500),
      _positionSnapshot,
    );
  }
}
