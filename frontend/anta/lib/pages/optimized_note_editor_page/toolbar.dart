part of '../optimized_note_editor_page.dart';

/// The markdown bar's work: a shortcut and its counters, ghost text, the
/// format keys, paste and indent, the bar switcher, and a dragged order.
mixin _NoteEditorToolbar on _NoteEditorTaps {
  /// Adopts a dragged shortcut order locally before the bloc answers, so
  /// the row does not snap back for the length of the write.
  Future<void> _handleReorderComplete(
    List<CustomMarkdownShortcut> reorderedShortcuts,
  ) async {
    final bar = _bar;
    if (bar != null) {
      setState(() {
        _bar = bar.copyWith(currentShortcuts: reorderedShortcuts);
      });
    }
    context.read<MarkdownBarBloc>().add(
      UpdateShortcuts(
        profileId: _activeBarProfileId,
        shortcuts: reorderedShortcuts,
      ),
    );
  }

  /// Same for the utility half of the toolbar; the settings controller
  /// updates its value before writing, so nothing is re-read here.
  Future<void> _handleUtilityReorderComplete(
    List<UtilityButtonConfig> reorderedUtilities,
  ) => _editorSettings.setToolbarUtilityConfig(reorderedUtilities);

  /// Increments the given counter and returns its post-increment value.
  /// Also refreshes counter state in the BLoC.
  Future<int> _incrementCounter(String counterId) async {
    final bloc = context.read<CounterBloc>();
    final counterState = bloc.state;
    if (counterState is! CounterLoaded) return 0;

    final counter = counterState.counters
        .where((c) => c.id == counterId)
        .firstOrNull;
    if (counter == null) return 0;

    final currentValue =
        counterState.counterValues[counterId] ?? counter.startValue;
    final noteId = _saves.effectiveNoteId ?? widget.noteId;
    bloc.add(IncrementCounter(counterId: counterId, noteId: noteId));
    return currentValue + counter.step;
  }

  /// Decrements the given counter and returns its post-decrement value.
  Future<int> _decrementCounter(String counterId) async {
    final bloc = context.read<CounterBloc>();
    final counterState = bloc.state;
    if (counterState is! CounterLoaded) return 0;

    final counter = counterState.counters
        .where((c) => c.id == counterId)
        .firstOrNull;
    if (counter == null) return 0;

    final currentValue =
        counterState.counterValues[counterId] ?? counter.startValue;
    final noteId = _saves.effectiveNoteId ?? widget.noteId;
    bloc.add(DecrementCounter(counterId: counterId, noteId: noteId));
    return currentValue - counter.step;
  }

  Future<void> _showCounterPicker() async {
    final counterState = context.read<CounterBloc>().state;
    if (counterState is! CounterLoaded) return;

    final selected = await AppDialogs.counterPicker(
      context,
      counters: counterState.counters,
      counterValues: counterState.counterValues,
      noteId: _saves.effectiveNoteId,
      onManageCounters: () async {
        await AppNavigator.toCounterManagement(
          context,
          noteId: _saves.effectiveNoteId,
        );
        if (!mounted) return null;
        final bloc = context.read<CounterBloc>();
        bloc.add(RefreshCounters(noteId: _saves.effectiveNoteId));
        final updated = await bloc.stream
            .where((s) => s is CounterLoaded)
            .first
            .timeout(const Duration(seconds: 2), onTimeout: () => bloc.state);
        if (updated is! CounterLoaded) return null;
        return (
          counters: updated.counters,
          counterValues: updated.counterValues,
        );
      },
    );

    if (selected == null || !mounted) return;

    final currentValue = await _incrementCounter(selected.id);
    _edits.runGuarded(() {
      _contentController.runRevocableOp(() {
        _contentController.replaceSelection(currentValue.toString());
      });
    });
    _onTextChanged();
  }

  /// Wraps the current editor selection as ghost text (`{{ … }}`). With
  /// no selection, inserts an empty `{{  }}` and parks the caret between
  /// the markers so the user can type the placeholder.
  void _insertGhostText() {
    final beforeLength = _contentController.textLength;
    _edits.runGuarded(
      () => MarkdownShortcutInserter.insertGhost(_contentController),
    );
    _onTextChanged();
    // Same reflow the generic shortcut path gets: wrapping a wide
    // selection in `{{ … }}` grows the line exactly as Bold does.
    _edits.reformatInserted(beforeLength: beforeLength);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentController.makeCursorVisible();
    });
  }

  /// Wraps the selection in [shortcut]'s before/after text, dropping a
  /// selected ghost placeholder into the slot when there is no selection —
  /// see [MarkdownShortcutInserter.insertWithGhostSlot].
  void _insertWithGhostSlot(CustomMarkdownShortcut shortcut) {
    final beforeLength = _contentController.textLength;
    _edits.runGuarded(
      () => MarkdownShortcutInserter.insertWithGhostSlot(
        _contentController,
        shortcut,
      ),
    );
    _onTextChanged();
    // Same reflow the generic shortcut path gets: `{name: … }` around a
    // wide selection is exactly as likely to overflow as Bold's markers.
    _edits.reformatInserted(beforeLength: beforeLength);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentController.makeCursorVisible();
    });
  }

  /// The heading level of the line the heading menu would rewrite — the
  /// selection's start line, as [ShortcutApplier.applyHeaderLevel] reads
  /// it — so the menu checks the level a second pick removes.
  int? _caretHeadingLevel() {
    final lines = _contentController.codeLines;
    final index = _contentController.selection.startIndex;
    if (index < 0 || index >= lines.length) return null;
    // An underline answers its heading's level, negated.
    final level = _render.headingLevelAt(index);
    return level == 0 ? null : level.abs();
  }

  /// Ctrl/Cmd+B and Ctrl/Cmd+I, through the bookkeeping the bar's Bold
  /// and Italic get in [_handleShortcut]: the tracker's guard, the length
  /// resync, the reflow of a wide wrap and the caret kept in view.
  void _toggleFormatShortcut(String marker) {
    final beforeLength = _contentController.textLength;
    _edits.runGuarded(
      () => ShortcutApplier.toggleWrap(_contentController, marker),
    );
    _onTextChanged();
    _edits.reformatInserted(beforeLength: beforeLength);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contentController.makeCursorVisible();
    });
  }

  /// The bar's Paste. Focus first: on an unfocused editor the insert would
  /// land at a stale caret with none painted and the keyboard down, so the
  /// user could not see where the text went.
  void _pasteFromBar() {
    _contentFocusNode.requestFocus();
    _contentController.paste();
  }

  /// The bar's indent and outdent — the Tab edit a soft keyboard cannot
  /// send. Guarded like every other programmatic insert so the tracker
  /// never reads the indent's growth as typing or a paste.
  ///
  /// A tap that changes nothing (an Indent at the nesting cap, an Outdent
  /// at column 0) is no edit: it must not mark the note unsaved or
  /// schedule a save.
  void _shiftListIndent({required bool outdent}) {
    _focusContentFirst();
    final CodeLines before = _contentController.codeLines;
    _edits.runGuarded(
      () => ListIndentAction.apply(
        _contentController,
        outdent: outdent,
        isFenceLine: _render.lineInFence,
      ),
    );
    if (_contentController.codeLines == before) return;
    _onTextChanged();
  }

  /// Raises the caret and the keyboard before a bar edit, as the bar's
  /// Paste does: on an unfocused editor the edit would land at a stale,
  /// unpainted caret (U2.1).
  void _focusContentFirst() {
    if (!_contentFocusNode.hasFocus) _contentFocusNode.requestFocus();
  }

  Future<void> _handleShortcut(CustomMarkdownShortcut shortcut) async {
    _focusContentFirst();
    // Ghost text has bespoke insert behavior (on an empty selection the
    // caret lands inside the placeholder), so it bypasses the generic
    // applier — mirroring how the header shortcut has its own handling.
    if (shortcut.id == 'default_ghost') {
      _insertGhostText();
      return;
    }

    // Colour constructs wrap a selection like Bold, but on an empty
    // selection they drop a ghost placeholder into the slot so the
    // fill-in is visible and tappable instead of a bare caret.
    if (shortcut.id == 'default_color_text' ||
        shortcut.id == 'default_color_highlight') {
      _insertWithGhostSlot(shortcut);
      return;
    }

    // Counter mutations and date resolution are awaited *first*, with the
    // document untouched. The write below has to be synchronous: an insert
    // landing in a microtask would arrive after both wrappers around it had
    // returned, so the tracker would diff it as a paste (and a one-newline
    // insert at the end of a list line as an Enter, growing a marker), and
    // the reflow below would measure a length nothing had changed yet.
    final text = await ShortcutApplier.resolve(
      controller: _contentController,
      shortcut: shortcut,
      mutateCounter: _mutateShortcutCounter,
    );
    if (!mounted) return;

    // Store length before applying the shortcut to calculate inserted range
    final beforeLength = _contentController.textLength;

    // The guard keeps the tracker's paste heuristic out of the revocable
    // op — `replaceSelection` notifies synchronously, and a reformat
    // running mid-op would work off stale offsets and then be repeated
    // below. It also resyncs the length, so the next keystroke diffs
    // against what the shortcut actually left behind.
    //
    // The revocable op inside it makes the whole shortcut one undo entry
    // whatever the insert does — a wrap toggle is a replace plus a
    // selection, and an insert that wrote the value directly would
    // otherwise merge into the typing burst before it.
    _edits.runGuarded(() {
      _contentController.runRevocableOp(() {
        // A null resolution is a rewrite — a heading level, a line marker
        // or a wrapper toggled — rather than an insert at the selection.
        if (text == null) {
          ShortcutApplier.applyRewrite(
            _contentController,
            shortcut,
            isFenceLine: _render.lineInFence,
            headingLevelAt: _render.headingLevelAt,
          );
        } else {
          _contentController.replaceSelection(text);
        }
      });
    });

    _onTextChanged();

    // Reflow whatever the shortcut inserted, if it was wide enough to
    // need it and auto-break is on (the tracker checks both).
    _edits.reformatInserted(beforeLength: beforeLength);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _contentController.makeCursorVisible();
      }
    });
  }

  /// Resolves one `{cN}` binding for [ShortcutApplier.resolve]: applies the
  /// bound operation and reports the value the token expands to, or `null`
  /// when the counter is unknown to the loaded state.
  Future<int?> _mutateShortcutCounter(String counterId, CounterOp op) async {
    if (!mounted) return null;
    final counterState = context.read<CounterBloc>().state;
    if (counterState is! CounterLoaded) return null;
    if (!counterState.counters.any((c) => c.id == counterId)) return null;
    switch (op) {
      case CounterOp.increment:
        return _incrementCounter(counterId);
      case CounterOp.decrement:
        return _decrementCounter(counterId);
      case CounterOp.keep:
        // Counter existence already confirmed by the .any() guard above.
        final counter = counterState.counters.firstWhere(
          (c) => c.id == counterId,
        );
        return counterState.counterValues[counterId] ?? counter.startValue;
    }
  }

  /// Opens the bar switcher bottom sheet and applies the selection.
  Future<void> _showBarSwitcher() async {
    final result = await BarSwitcherSheet.show(
      context,
      currentProfileId: _activeBarProfileId,
      noteId: _saves.effectiveNoteId ?? widget.noteId,
    );
    if (result == null || !mounted) return;

    final noteId = _saves.effectiveNoteId ?? widget.noteId;

    if (result.clearedOverride) {
      if (noteId != null) {
        context.read<MarkdownBarBloc>().add(
          SetNoteBarAssignment(noteId: noteId, profileId: null),
        );
      }
      return;
    }

    if (result.profile != null) {
      final selected = result.profile!;
      if (noteId != null) {
        context.read<MarkdownBarBloc>().add(
          SetNoteBarAssignment(noteId: noteId, profileId: selected.id),
        );
      } else {
        context.read<MarkdownBarBloc>().add(
          SetActiveProfile(profileId: selected.id),
        );
      }
    }
  }

  /// Opens the markdown settings page.
  ///
  /// Nothing is re-read after the push: this is a page route, so
  /// [didPopNext] re-reads the settings and re-resolves the bar on the way
  /// back — the same path a restored Markdown settings page pops through.
  Future<void> _openMarkdownSettings() =>
      AppNavigator.toMarkdownSettings(context, allShortcuts: _shortcuts);
}
