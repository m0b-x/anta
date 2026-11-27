part of '../optimized_note_editor_page.dart';

/// What the editor is handed besides the note's text: the vocabularies, the
/// money config, the colour palette, the developer options and the
/// measurements a paste is reflowed with — and the notices those raise.
mixin _NoteEditorInputs on _NoteEditorTyping {
  /// Loads the user's vocabularies and hands the suggestion controller its
  /// settings. Runs off the settings listener, so it re-applies whenever
  /// the flag or the trigger character changes.
  ///
  /// The service is a lazy singleton, so the first editor open is what pulls
  /// the tables into memory; later opens hit the cache. Failure is silent by
  /// design — autocomplete is an accelerator, and a note must always open.
  Future<void> _refreshVocabularies() async {
    final settings = _editorSettings.value;
    if (settings.vocabularySuggestionsEnabled) {
      unawaited(_primeTagCatalog());
      try {
        await VocabularyService.getInstance();
      } catch (e) {
        debugPrint('[NoteEditor] Vocabulary load error: $e');
      }
    }
    if (!mounted) return;
    _appliedVocabularySettings = (
      enabled: settings.vocabularySuggestionsEnabled,
      trigger: settings.vocabularyTriggerChar,
    );
    _vocabularySuggestions.configure(
      enabled: settings.vocabularySuggestionsEnabled,
      trigger: settings.vocabularyTriggerChar,
      isFenceLine: _render.lineInFence,
    );
  }

  /// Opens the tag catalog the `#…` suggestions read, never awaited by the
  /// mount: until its read lands the facade is empty and a tag offers only
  /// this note's own. The catalog follows the search index's drains, so
  /// priming also asks the index to catch up on what other notes saved
  /// ([TagCatalogService.prime]).
  Future<void> _primeTagCatalog() async {
    try {
      await TagCatalogService.prime();
    } catch (e) {
      debugPrint('[NoteEditor] Tag catalog load error: $e');
    }
  }

  /// Applies an accepted suggestion, with the same bookkeeping every other
  /// programmatic insert uses (see [_handleShortcut]): the edit tracker's
  /// guard so the paste heuristic cannot fire mid-op and the length is
  /// resynced afterwards, wrapped in one revocable op so the whole
  /// completion is a single undo step.
  void _applyVocabularyInsertion(VocabularyInsertion insertion) {
    _edits.runGuarded(() {
      _contentController.runRevocableOp(() {
        _contentController.replaceSelection(
          insertion.text,
          CodeLineSelection(
            baseIndex: insertion.lineIndex,
            baseOffset: insertion.start,
            extentIndex: insertion.lineIndex,
            extentOffset: insertion.end,
          ),
        );
      });
    });
    _onTextChanged();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentController.makeCursorVisible();
    });
  }

  /// Resolves the effective money config (enabled flag, global start
  /// balance, this note's currency) and applies it to both render
  /// surfaces. Called on note open and again when returning from
  /// settings.
  ///
  /// The editor surface is refreshed non-destructively:
  /// [EditorRenderController.applyMoneyConfig] clears the builder's span
  /// memos, and — only when the config actually changed —
  /// `forceRepaint()` makes re_editor drop and rebuild its display
  /// paragraphs (re-running the span builder) without remounting,
  /// mutating text, or moving the caret. On the first open the render
  /// isn't attached yet, so `forceRepaint` is a null-safe no-op and the
  /// first layout paints fresh. (An earlier attempt folded the config
  /// into the editor's ValueKey to force a remount; that remounted the
  /// CodeEditor mid-initialization and crashed re_editor's controller-
  /// delegate handoff — never remount the editor for a settings change.)
  Future<void> _refreshMoneyConfig() async {
    final settings = await SettingsService.getInstance();
    final resolved = await settings.getMoneyConfig(
      noteId: _saves.effectiveNoteId ?? widget.noteId,
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    // One value-equal object, built once here and handed to every
    // consumer — the span builder, the preview bloc, and the detail
    // sheet all read the same instance, so the surfaces can never
    // receive different halves of the config.
    final config = MoneyDisplayConfig(
      enabled: resolved.enabled,
      startCents: resolved.startCents,
      currencySymbol: resolved.symbol,
      currencySuffix: resolved.suffix,
      errorMessages: l10n == null ? null : MoneyErrorMessages.of(l10n),
    );
    if (_render.applyMoneyConfig(config)) {
      // The wrapper's money tap zone reads `enabled` off the config, so
      // the rebuild is what keeps the tap surface in step with the paint.
      setState(() {});
      _contentController.forceRepaint();
    }
    _previewBloc.add(PreviewMoneyConfigChanged(config));
  }

  /// Resolves the markdown colour palette (presets + the user's custom
  /// colours) and applies it to both render surfaces. Same
  /// non-destructive refresh contract as [_refreshMoneyConfig]: the
  /// editor's span memos are cleared and a repaint is nudged only when
  /// the palette actually changed — never a remount.
  Future<void> _refreshColorPalette() async {
    final settings = await SettingsService.getInstance();
    final palette = await settings.getColorPalette();
    if (!mounted) return;
    if (_render.applyPalette(palette)) {
      // The wrapper takes the palette as a widget field (its tap zones
      // resolve `{name:…}` runs with it), so this needs the rebuild as
      // much as the repaint.
      setState(() {});
      _contentController.forceRepaint();
    }
    _previewBloc.add(PreviewColorPaletteChanged(palette));
  }

  Future<void> _initDevOptions() async {
    // Initialize dev options service (loads settings from DB)
    await DevOptionsService.getInstance();
    // Listen for changes and rebuild if needed
    if (mounted) {
      DevOptions.instance.addListener(_onDevOptionsChanged);
    }
  }

  void _onDevOptionsChanged() {
    if (mounted) setState(() {});
  }

  /// Warns once that the title the user typed is already taken in this
  /// folder. The content is still saved — under the note's original
  /// title — so a rename that cannot be applied never costs keystrokes.
  /// The app bar goes back to the title the row keeps, or it would show a
  /// rename that never happened (U2.2).
  void _showDuplicateTitleWarning(String title) {
    if (!mounted) return;
    setState(() {
      _titleController.text = _saves.originalTitle ?? '';
    });
    CustomSnackbar.showError(
      context,
      AppLocalizations.of(context)!.noteTitleAlreadyExists(title),
    );
  }

  /// The measurements [EditorEditTracker] needs to reflow a paste, or
  /// null while the editor has no laid-out width to break lines against
  /// (a paste into a page that has not been measured yet).
  PasteReformatContext? _pasteReformatContext() {
    final calculator = _createWidthCalculator();
    final width = calculator.getAvailableTextWidth();
    if (width == null) return null;
    return (calculator: calculator, availableWidth: width);
  }

  /// Tells the user a paste was reflowed to the editor's width, so the
  /// rewrapped lines do not read as text they did not type.
  void _showLinesFormatted(int linesModified) {
    if (!mounted) return;
    CustomSnackbar.show(
      context,
      AppLocalizations.of(context)!.linesFormatted(linesModified),
      withToolbarOffset: true,
    );
  }

  /// Creates an EditorWidthCalculator with current configuration
  EditorWidthCalculator _createWidthCalculator() {
    return EditorWidthCalculator(
      config: EditorWidthConfig(
        editorContainerKey: _editorWrapperKey,
        lineNumbersKey: _editorSettings.value.showLineNumbers
            ? _lineNumbersKey
            : null,
        scrollIndicatorKey: _scrollIndicatorKey,
        // The wrapper's formula, so reflow breaks at the width it wraps at.
        fontSize: ModernEditorWrapper.scaledFontSize(
          context,
          _editorSettings.value.editorFontSize,
        ),
        fontFamily: FontConstants.editorFontFamily,
      ),
      editorPadding: EdgeInsets.only(
        left: AppSpacing.lg,
        top: AppSpacing.lg,
        right: AppSpacing.lg + AppConstants.editorScrollbarPadding,
        bottom: AppSpacing.lg,
      ),
    );
  }
}
