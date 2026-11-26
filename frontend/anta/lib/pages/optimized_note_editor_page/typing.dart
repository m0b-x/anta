part of '../optimized_note_editor_page.dart';

/// What a change in the editor sets off: the text the controller reports,
/// and the undo and redo buttons that follow the history.
mixin _NoteEditorTyping on _NoteEditorPreview {
  /// The document [_onContentNotified] last reported, so a notification
  /// that only moved the caret or hopped a search match is told apart.
  CodeLines? _notifiedLines;
  int _notifiedLength = 0;

  /// The editing controller notifies on selection moves too; only a change
  /// of the text reaches the save coordinator, or a caret move flips the
  /// save indicator to unsaved (U2.3). Every edit replaces the code-lines
  /// instance, so identity plus length is exact without reading the text.
  void _onContentNotified() {
    final lines = _contentController.codeLines;
    final length = _contentController.textLength;
    if (identical(lines, _notifiedLines) && length == _notifiedLength) return;
    _notifiedLines = lines;
    _notifiedLength = length;
    _onTextChanged();
  }

  void _onTextChanged() {
    _stats.onTextChanged(_contentController.textLength);
    _scheduleLivePreviewRefresh();
    _saves.onContentChanged();
    _syncHistoryButtons();
  }

  /// The undo/redo state the toolbar was last built with, so a keystroke
  /// rebuilds the page only when that state actually flips (the first edit
  /// after a load, an undo that bottoms out, a redo that reaches the top) —
  /// never per keystroke.
  ({bool canUndo, bool canRedo}) _builtHistory = (
    canUndo: false,
    canRedo: false,
  );

  ({bool canUndo, bool canRedo}) get _historyState =>
      (canUndo: _historyObserver.canUndo, canRedo: _historyObserver.canRedo);

  /// Rebuilds the toolbar's undo/redo buttons when the history state moved
  /// away from what they show. The controller can notify mid-build (the
  /// editor's delegate handoff does when a controller is swapped into a
  /// mounted editor, and did on every mount until 2026-10-01), so a change
  /// seen during a frame's build phase is applied after that frame instead
  /// of throwing.
  void _syncHistoryButtons() {
    if (_historyState == _builtHistory) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncHistoryButtons();
      });
      return;
    }
    if (mounted) setState(() {});
  }
}
