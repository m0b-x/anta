import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../controllers/preview_scroll_controller.dart';
import '../../services/markdown_render_service.dart';
import '../../utils/line_based_markdown_builder.dart';
import 'markdown_preview_event.dart';
import 'markdown_preview_state.dart';

export 'markdown_preview_event.dart';
export 'markdown_preview_state.dart';

/// Coordinates the markdown preview rendering pipeline for a single
/// preview surface (typically one note editor page).
///
/// Owns a [MarkdownRenderService] and forwards input changes to it.
/// The bloc itself never produces or holds [InlineSpan] trees: when a
/// rebuild happens it bumps [MarkdownPreviewState.renderHandle] and
/// the consuming widget pulls spans from [renderService] on demand.
///
/// ### Theme dependency
///
/// The bloc is widget-free and therefore cannot resolve a [Theme]
/// itself. It relies on a mounted `MarkdownPreviewBlocView` (or any
/// equivalent caller) to dispatch [PreviewThemeChanged] before the
/// builder can be prepared. Until that first dispatch arrives,
/// content / font / search events are recorded into state but no
/// rendering work happens. Owners that need to read derived data
/// (e.g. `renderService.chunkCount`) before the view mounts should
/// dispatch `PreviewThemeChanged` themselves first.
///
/// Performance characteristics preserved from the previous in-widget
/// implementation:
///   * Builder is reused when none of the prepare-relevant inputs
///     changed (content, font, brightness, lines-per-chunk, debug,
///     search highlights, current highlight index).
///   * Builder is disposed and recreated when inputs change so that
///     gesture recognizers do not leak.
///   * Adaptive chunk sizing for large documents (delegated to the
///     service).
///   * Scroll progress updates are zero-cost: they emit a state with
///     an updated `progress` field and never touch the builder.
class MarkdownPreviewBloc
    extends Bloc<MarkdownPreviewEvent, MarkdownPreviewState> {
  final MarkdownRenderService _renderService;
  final PreviewScrollController _scrollController;

  /// Last theme inputs received. The bloc cannot prepare the builder
  /// without these — until [PreviewThemeChanged] arrives, any
  /// content/font changes are recorded in state but do not trigger a
  /// prepare call.
  Brightness? _brightness;
  LineMarkdownStyle Function(double fontSize)? _styleBuilder;
  bool _debugEnabled = false;

  /// Optional callbacks forwarded into every [LineBasedMarkdownBuilder]
  /// the service constructs. Set once via [bindCallbacks] from the
  /// owning widget; the bloc itself is widget-free.
  LinkTapCallback? _onLinkTap;
  CheckboxTapCallback? _onCheckboxTap;
  GhostTapCallback? _onGhostTap;
  TagTapCallback? _onTagTap;
  MoneyTapCallback? _onMoneyTap;

  /// Optional pull-style content source. When set, callers can
  /// dispatch [PreviewContentRefreshRequested] (and bump the dirty
  /// version via [markContentDirty]) instead of materializing the
  /// editor text and dispatching [PreviewContentChanged] eagerly.
  /// See [bindContentProvider].
  String Function()? _contentProvider;

  /// Monotonic counter incremented by [markContentDirty]. Cheap to
  /// bump on every keystroke. The handler for
  /// [PreviewContentRefreshRequested] short-circuits when this hasn't
  /// moved since the last consumed pull.
  int _contentVersion = 0;
  int _lastConsumedContentVersion = -1;

  MarkdownPreviewBloc({MarkdownRenderService? renderService})
    : _renderService = renderService ?? MarkdownRenderService(),
      _scrollController = PreviewScrollController(),
      super(const MarkdownPreviewState()) {
    on<PreviewContentChanged>(_onContentChanged);
    on<PreviewContentRefreshRequested>(_onContentRefreshRequested);
    on<PreviewFontSizeChanged>(_onFontSizeChanged);
    on<PreviewSearchUpdated>(_onSearchUpdated);
    on<PreviewLinesPerChunkChanged>(_onLinesPerChunkChanged);
    on<PreviewMoneyConfigChanged>(_onMoneyConfigChanged);
    on<PreviewColorPaletteChanged>(_onColorPaletteChanged);
    on<PreviewModeToggled>(_onModeToggled);
    on<PreviewThemeChanged>(_onThemeChanged);
  }

  /// The scroll controller owned by this bloc. The bloc-view wrapper
  /// binds the underlying [SourceMappedMarkdownView]'s key into it on
  /// mount (reusing an already-bound key across remounts), so all
  /// imperative scroll calls resolve to the live state.
  PreviewScrollController get scrollController => _scrollController;

  /// Convenience: the same [ValueNotifier] used by
  /// `InteractivePreviewScrollbar`. Exposed so widgets can bind
  /// without reaching into [scrollController].
  ValueListenable<double> get scrollProgress => _scrollController.progress;

  // ─────────────────────────────────────────────────────────────────
  // Scroll facades — thin pass-throughs so call sites don’t need to
  // know about the controller. All preserve existing semantics.
  // ─────────────────────────────────────────────────────────────────

  void scrollToProgress(double value, {bool animate = false}) =>
      _scrollController.scrollToProgress(value, animate: animate);

  void scrollToTop({bool animate = true}) =>
      _scrollController.scrollToTop(animate: animate);

  void scrollToBottom({bool animate = true}) =>
      _scrollController.scrollToBottom(animate: animate);

  Future<bool> scrollToLineIndex(
    int lineIndex,
    int totalLines, {
    bool animate = true,
    Duration duration = const Duration(milliseconds: 300),
  }) => _scrollController.scrollToLineIndex(
    lineIndex,
    totalLines,
    animate: animate,
    duration: duration,
  );

  Future<bool> scrollToSourceOffset(int offset) =>
      _scrollController.scrollToSourceOffset(offset);

  void restoreProgress(
    double targetProgress, {
    Duration delay = const Duration(milliseconds: 150),
  }) => _scrollController.restoreProgress(targetProgress, delay: delay);

  void cancelPendingRestores() => _scrollController.cancelPendingRestores();

  int get currentLineIndex => _scrollController.currentLineIndex;

  /// The render service owned by this bloc. Widgets call
  /// `renderService.builder?.buildChunk(i)` to read spans for a
  /// specific chunk index.
  MarkdownRenderService get renderService => _renderService;

  /// Binds the link / checkbox callbacks used by the underlying
  /// builder. Safe to call multiple times; only the most recent
  /// callbacks are used on the next prepare.
  void bindCallbacks({
    LinkTapCallback? onLinkTap,
    CheckboxTapCallback? onCheckboxTap,
    GhostTapCallback? onGhostTap,
    TagTapCallback? onTagTap,
    MoneyTapCallback? onMoneyTap,
  }) {
    _onLinkTap = onLinkTap;
    _onCheckboxTap = onCheckboxTap;
    _onGhostTap = onGhostTap;
    _onTagTap = onTagTap;
    _onMoneyTap = onMoneyTap;
  }

  /// Binds a pull-style content source. Subsequent
  /// [PreviewContentRefreshRequested] events read from [provider]
  /// instead of carrying a content payload, so callers can defer the
  /// (now-cached but still O(n) for the equality compare) string
  /// materialization until the bloc actually needs it.
  void bindContentProvider(String Function() provider) {
    _contentProvider = provider;
  }

  /// Marks the bound content as dirty without dispatching anything.
  /// Cheap (single `int` increment); safe to call on every keystroke.
  /// A subsequent [PreviewContentRefreshRequested] dispatch is what
  /// actually triggers the refresh.
  void markContentDirty() {
    _contentVersion++;
  }

  /// Pre-warm the LRU chunk cache for [chunkIndex]. Forwarded to the
  /// service. Used by the view to look ahead in the scroll direction.
  void preWarmChunk(int chunkIndex) {
    _renderService.preWarmChunk(chunkIndex);
  }

  // ─────────────────────────────────────────────────────────────────
  // Event handlers
  // ─────────────────────────────────────────────────────────────────

  void _onContentChanged(
    PreviewContentChanged event,
    Emitter<MarkdownPreviewState> emit,
  ) {
    if (event.content == state.content && state.hasTheme) {
      // Identical content and we already prepared once — nothing to
      // re-prepare. Still mark the dirty counter as consumed so a
      // subsequent [PreviewContentRefreshRequested] doesn't pull and
      // string-compare for nothing.
      _lastConsumedContentVersion = _contentVersion;
      return;
    }
    // Treat an explicit content push as "version consumed" so a
    // subsequent refresh request doesn't redundantly reprepare with
    // identical text.
    _lastConsumedContentVersion = _contentVersion;
    final next = state.copyWith(content: event.content);
    _emitPrepared(next, emit);
  }

  void _onContentRefreshRequested(
    PreviewContentRefreshRequested event,
    Emitter<MarkdownPreviewState> emit,
  ) {
    final provider = _contentProvider;
    if (provider == null) return;
    if (_contentVersion == _lastConsumedContentVersion && state.hasTheme) {
      // Nothing dirtied the content since the last consumed pull.
      return;
    }
    _lastConsumedContentVersion = _contentVersion;
    final content = provider();
    if (content == state.content && state.hasTheme) {
      // Version moved but text is identical (e.g. keystrokes that
      // cancelled out). Nothing to reprepare.
      return;
    }
    _emitPrepared(state.copyWith(content: content), emit);
  }

  void _onFontSizeChanged(
    PreviewFontSizeChanged event,
    Emitter<MarkdownPreviewState> emit,
  ) {
    if (event.fontSize == state.fontSize) return;
    _emitPrepared(state.copyWith(fontSize: event.fontSize), emit);
  }

  void _onSearchUpdated(
    PreviewSearchUpdated event,
    Emitter<MarkdownPreviewState> emit,
  ) {
    final next = state.copyWith(
      searchHighlights: event.highlights,
      clearSearchHighlights: event.highlights == null,
      currentHighlightIndex: event.currentIndex,
      clearCurrentHighlightIndex: event.currentIndex == null,
    );
    _emitPrepared(next, emit);
  }

  void _onLinesPerChunkChanged(
    PreviewLinesPerChunkChanged event,
    Emitter<MarkdownPreviewState> emit,
  ) {
    if (event.linesPerChunk == state.linesPerChunk) return;
    _emitPrepared(state.copyWith(linesPerChunk: event.linesPerChunk), emit);
  }

  void _onMoneyConfigChanged(
    PreviewMoneyConfigChanged event,
    Emitter<MarkdownPreviewState> emit,
  ) {
    if (event.config == state.moneyConfig) return;
    _emitPrepared(state.copyWith(moneyConfig: event.config), emit);
  }

  void _onColorPaletteChanged(
    PreviewColorPaletteChanged event,
    Emitter<MarkdownPreviewState> emit,
  ) {
    if (event.palette == state.colorPalette) return;
    _emitPrepared(state.copyWith(colorPalette: event.palette), emit);
  }

  void _onModeToggled(
    PreviewModeToggled event,
    Emitter<MarkdownPreviewState> emit,
  ) {
    if (event.isPreviewMode == state.isPreviewMode) return;
    emit(state.copyWith(isPreviewMode: event.isPreviewMode));
  }

  void _onThemeChanged(
    PreviewThemeChanged event,
    Emitter<MarkdownPreviewState> emit,
  ) {
    final brightnessChanged = _brightness != event.brightness;
    final debugChanged = _debugEnabled != event.debugEnabled;
    // Always update the cached style builder — even when
    // [brightness] / [debugEnabled] are unchanged the closure may
    // capture an updated theme tint. We only trigger a rebuild when
    // the cache key actually changes.
    _brightness = event.brightness;
    _styleBuilder = event.styleBuilder;
    _debugEnabled = event.debugEnabled;

    final hadTheme = state.hasTheme;
    if (!brightnessChanged && !debugChanged && hadTheme) {
      // No-op: cached factory updated for next prepare, no rebuild needed.
      return;
    }

    _emitPrepared(state.copyWith(hasTheme: true), emit);
  }

  // ─────────────────────────────────────────────────────────────────
  // Prepare
  // ─────────────────────────────────────────────────────────────────

  /// Calls into the render service with the current state + cached
  /// theme inputs and emits the resulting state.
  ///
  /// If theme has not yet been provided, only the input state change
  /// is emitted and the service is left untouched.
  void _emitPrepared(
    MarkdownPreviewState next,
    Emitter<MarkdownPreviewState> emit,
  ) {
    final brightness = _brightness;
    final styleBuilder = _styleBuilder;
    if (brightness == null || styleBuilder == null) {
      emit(next);
      return;
    }

    // Always rebuild the style with the *current* font size so the
    // builder receives a style whose [LineMarkdownStyle.baseFontSize]
    // matches what the view will render.
    final style = styleBuilder(next.fontSize);

    final rebuilt = _renderService.prepareWithStyle(
      data: next.content,
      fontSize: next.fontSize,
      brightness: brightness,
      style: style,
      linesPerChunk: next.linesPerChunk,
      debugEnabled: _debugEnabled,
      searchHighlights: next.searchHighlights,
      currentHighlightIndex: next.currentHighlightIndex,
      moneyConfig: next.moneyConfig,
      colorPalette: next.colorPalette,
      onLinkTap: _onLinkTap,
      onCheckboxTap: _onCheckboxTap,
      onGhostTap: _onGhostTap,
      onTagTap: _onTagTap,
      onMoneyTap: _onMoneyTap,
    );

    if (rebuilt) {
      emit(next.copyWith(renderHandle: next.renderHandle + 1, hasTheme: true));
    } else {
      // No builder rebuild: still emit the new input state so
      // downstream observers see e.g. font/lines-per-chunk changes.
      // Equatable will short-circuit if nothing actually changed.
      emit(next.copyWith(hasTheme: true));
    }
  }

  @override
  Future<void> close() {
    _renderService.dispose();
    _scrollController.dispose();
    return super.close();
  }
}
