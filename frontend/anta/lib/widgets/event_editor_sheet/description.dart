part of '../event_editor_sheet.dart';

/// The description field as an editor: its change notifications, keeping
/// the caret in view while the form scrolls or resizes, and the line
/// styling it shares with the note editor.
mixin _EventEditorDescription on _EventEditorState {
  /// How the form follows the description's caret — `EditableText`'s own
  /// caret-reveal timing, so typing here moves the form exactly as typing
  /// in any text field does.
  static const Duration _caretRevealDuration = Duration(milliseconds: 100);
  static const Curve _caretRevealCurve = Curves.fastOutSlowIn;

  /// Frames a caret reveal waits for the editor to bring the caret into its
  /// own box before giving up. The editor's scroll after an edit is itself a
  /// post-frame retry registered after ours, so the first look can be early.
  static const int _caretRevealRetries = 3;

  /// Republishes a controller notification on [_descriptionRevision], moving
  /// it out of the build phase when it arrives during one. See that field for
  /// why a direct listener is unsafe here.
  void _relayDescriptionChange() {
    _scheduleCaretReveal();
    final phase = SchedulerBinding.instance.schedulerPhase;
    final duringFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (!duringFrame) {
      _descriptionRevision.value++;
      return;
    }
    if (_revisionBumpScheduled) return;
    _revisionBumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revisionBumpScheduled = false;
      if (mounted) _descriptionRevision.value++;
    });
  }

  void _onDescriptionFocusChanged() {
    final hasFocus = _descriptionFocus.hasFocus;
    if (hasFocus == _descriptionFocused || !mounted) return;
    setState(() => _descriptionFocused = hasFocus);
    if (hasFocus) _revealDescription();
  }

  /// Scrolls the description into view when it takes focus. A CodeEditor is
  /// not an [EditableText], so nothing does this automatically, and the field
  /// sits far enough down the form that the rising keyboard would otherwise
  /// cover the line being typed. The delay lets the keyboard inset and the
  /// markdown bar settle first, so the target rect is the final one. The
  /// caret reveal that follows only moves anything when the cell is taller
  /// than what is left of the form, where centring the cell can leave the
  /// caret's end of it behind the bar.
  void _revealDescription() {
    _focusRevealPending = true;
    Future.delayed(const Duration(milliseconds: 320), () async {
      try {
        if (!mounted || !_descriptionFocus.hasFocus) return;
        final target = _descriptionKey.currentContext;
        if (target == null || !target.mounted) return;
        await Scrollable.ensureVisible(
          target,
          alignment: 0.5,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } finally {
        _focusRevealPending = false;
      }
      _revealCaret();
    });
  }

  /// Re-reveals the caret when the form's own viewport changes size under a
  /// focused description — the keyboard brought back by a tap after the
  /// system back dismissed it, or growing into an emoji panel: neither moves
  /// the caret or the focus, so nothing else would notice. `EditableText`
  /// does the same from `didChangeMetrics`.
  ///
  /// It listens to the form's metrics rather than to the inset because the
  /// inset is not what resizes the form: the docked bar carries it inside an
  /// [AnimatedSize], so the viewport is still shrinking for a moment after
  /// the inset has stopped changing. Depth 0 and vertical is the form
  /// itself: the description's own scroller reports through here one level
  /// down, and the markdown bar's strip sideways.
  ///
  /// Only a new viewport height counts. The content growing by a line
  /// reports here as well, a frame after the edit's own reveal began, and
  /// revealing again would restart that animation from where it stood.
  bool _onFormMetrics(ScrollMetricsNotification notification) {
    final metrics = notification.metrics;
    if (notification.depth != 0 || metrics.axis != Axis.vertical) return false;
    if (metrics.viewportDimension == _formViewportHeight) return false;
    _formViewportHeight = metrics.viewportDimension;
    if (!_focusRevealPending) _scheduleCaretReveal();
    return false;
  }

  /// Follows the caret with the form while the description is being edited.
  ///
  /// The editor keeps the caret inside its own box, and nothing else: the
  /// box grows a line at a time under the keyboard and the markdown bar, so
  /// on a short screen the sixth line was typed blind until the form was
  /// dragged by hand. An `EditableText` reveals its caret in its ancestors
  /// after every change; this is that half for the re_editor surface.
  ///
  /// Deferred to after the frame because the caret's place is only known
  /// once the edit has been laid out (the cell resizes inside layout), and
  /// coalesced because one edit notifies more than once.
  void _scheduleCaretReveal() {
    if (_caretRevealScheduled || !_descriptionFocus.hasFocus) return;
    _caretRevealScheduled = true;
    // An edit has a frame coming; a resized form may not, and the callback
    // would then wait for whatever frame came next.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _caretRevealScheduled = false;
        _revealCaret();
      })
      ..ensureVisualUpdate();
  }

  /// Scrolls the form the least it takes to show the caret's line with the
  /// cell's own padding around it, so the last line brings the cell's edge
  /// along instead of sitting flush against the bar. Does nothing while the
  /// line is already on screen, or once focus has left the description.
  ///
  /// A finger on the form outranks the caret: an animation started here
  /// would replace the drag and snap the form back under it, so a drag or
  /// its fling is left alone and the next change reveals instead.
  ///
  /// When the caret is not inside the editor's box yet — a paste that ends
  /// past the tenth line, Enter on the box's last line — the editor is
  /// about to scroll to it in a post-frame retry of its own, registered
  /// after this one; [retries] looks again on the following frames.
  void _revealCaret({int retries = _caretRevealRetries}) {
    if (!mounted || !_descriptionFocus.hasFocus) return;
    if (_bodyScroll.hasClients &&
        _bodyScroll.position.userScrollDirection != ScrollDirection.idle) {
      return;
    }
    final revealed = _descriptionScroll.revealInAncestors(
      _descriptionController.selection.extent,
      margin: const EdgeInsets.symmetric(
        vertical: FormMetrics.descriptionCellPadding,
      ),
      duration: _caretRevealDuration,
      curve: _caretRevealCurve,
    );
    if (revealed || retries == 0) return;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _revealCaret(retries: retries - 1))
      ..ensureVisualUpdate();
  }

  /// Restyles one description line, exactly as the note editor does.
  /// Unhandled lines (and every line while live rendering is off) fall back
  /// to the ghost-text builder, which leaves a line without a `{{ … }}` run
  /// as re_editor's own span — the same routing
  /// [EditorRenderController.buildSpan] does for the note editor, so a ghost
  /// never renders raw on one surface and concealed on another.
  TextSpan _buildDescriptionSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    final render = _descriptionRenderContext.of(Theme.of(context), style);
    if (_liveMarkdownRendering) {
      final span = _descriptionSpanBuilder.build(
        context: render,
        index: index,
        codeLine: codeLine,
      );
      if (span != null) return span;
    }
    return EditorRenderController.ghostSpan(
      codeLine: codeLine,
      textSpan: textSpan,
      style: style,
      baseColor: render.baseColor,
    );
  }
}
