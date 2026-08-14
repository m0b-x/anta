import 'dart:async';

import 'package:flutter/widgets.dart';

import '../widgets/source_mapped_markdown_view.dart';

/// Centralized controller for preview scroll state.
///
/// Follows the same pattern as [CodeScrollController] in re_editor:
/// a plain class that binds to a widget via [GlobalKey] and provides
/// imperative scroll commands through a private [_state] accessor.
///
/// Owns a [progress] notifier (0.0–1.0) for scrollbar binding and
/// position persistence, and manages internal timers for deferred
/// scroll restores.
class PreviewScrollController {
  GlobalKey<SourceMappedMarkdownViewState>? _viewKey;
  final List<Timer> _pendingTimers = [];

  /// Current scroll progress (0.0 to 1.0).
  /// Bound to the interactive scrollbar and persisted across sessions.
  final ValueNotifier<double> progress = ValueNotifier(0.0);

  // ═══════════════════════════════════════════════════════════════════════════
  // Binding
  // ═══════════════════════════════════════════════════════════════════════════

  /// Binds this controller to a [SourceMappedMarkdownView] via its
  /// [GlobalKey]. Typically called once when the key is created, or
  /// re-called in [State.didUpdateWidget] if the controller is swapped.
  void bindView(GlobalKey<SourceMappedMarkdownViewState> key) {
    _viewKey = key;
  }

  /// The [GlobalKey] for the bound view — exposed so widgets like
  /// [InteractivePreviewScrollbar] can pass it as the widget key.
  GlobalKey<SourceMappedMarkdownViewState>? get viewKey => _viewKey;

  /// Accessor for the bound view state.
  /// Returns `null` when the view is offstage or not yet built.
  SourceMappedMarkdownViewState? get _state => _viewKey?.currentState;

  // ═══════════════════════════════════════════════════════════════════════════
  // Scroll commands
  // ═══════════════════════════════════════════════════════════════════════════

  /// Scrolls the preview to [value] (0.0 = top, 1.0 = bottom).
  void scrollToProgress(double value, {bool animate = false}) {
    _state?.scrollToProgress(value, animate: animate);
  }

  /// Scrolls to the very top of the preview.
  void scrollToTop({bool animate = true}) {
    scrollToProgress(0.0, animate: animate);
  }

  /// Scrolls to the very bottom of the preview.
  void scrollToBottom({bool animate = true}) {
    scrollToProgress(1.0, animate: animate);
  }

  /// Scrolls the preview so that [lineIndex] (out of [totalLines]) is
  /// visible. Returns `true` if the view handled the request.
  Future<bool> scrollToLineIndex(
    int lineIndex,
    int totalLines, {
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
  }) async {
    return await _state?.scrollToLineIndex(
          lineIndex,
          totalLines,
          animate: animate,
          duration: duration,
        ) ??
        false;
  }

  /// Scrolls to the chunk that contains the given character [offset]
  /// in the source text. Returns `true` if handled.
  Future<bool> scrollToSourceOffset(int offset) async {
    return await _state?.scrollToSourceOffset(offset) ?? false;
  }

  /// Current visible line index (approximate).
  int get currentLineIndex => _state?.currentLineIndex ?? 0;

  // ═══════════════════════════════════════════════════════════════════════════
  // Progress tracking
  // ═══════════════════════════════════════════════════════════════════════════

  /// Called by the view's [SourceMappedMarkdownView.onScrollProgress]
  /// callback to keep [progress] in sync.
  void updateProgress(double value) {
    progress.value = value;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Deferred restore
  // ═══════════════════════════════════════════════════════════════════════════

  /// Scrolls the preview to [targetProgress] after [delay].
  /// Cancels any previously scheduled restore.
  void restoreProgress(
    double targetProgress, {
    Duration delay = const Duration(milliseconds: 150),
  }) {
    cancelPendingRestores();
    _scheduleDelayed(delay, () {
      scrollToProgress(targetProgress.clamp(0.0, 1.0));
    });
  }

  /// Cancels all pending deferred scroll operations.
  void cancelPendingRestores() {
    for (final timer in _pendingTimers) {
      timer.cancel();
    }
    _pendingTimers.clear();
  }

  void _scheduleDelayed(Duration delay, VoidCallback callback) {
    late final Timer timer;
    timer = Timer(delay, () {
      _pendingTimers.remove(timer);
      callback();
    });
    _pendingTimers.add(timer);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Lifecycle
  // ═══════════════════════════════════════════════════════════════════════════

  /// Releases all resources. After calling this, the controller must
  /// not be used again.
  void dispose() {
    cancelPendingRestores();
    progress.dispose();
    _viewKey = null;
  }
}
