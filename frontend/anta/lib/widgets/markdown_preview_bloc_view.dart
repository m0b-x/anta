import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/markdown_preview/markdown_preview_bloc.dart';
import '../models/checkbox_toggle_info.dart';
import '../models/dev_options.dart';
import '../utils/line_based_markdown_builder.dart';
import 'double_tap_line_detector.dart';
import 'source_mapped_markdown_view.dart';

/// Bloc-driven wrapper around [SourceMappedMarkdownView].
///
/// Reads its render parameters (content, fontSize, search highlights,
/// linesPerChunk) from a [MarkdownPreviewBloc] obtained from the
/// surrounding [BuildContext] and rebuilds the heavy list only when
/// the bloc emits a state with a different
/// [MarkdownPreviewState.renderHandle], `linesPerChunk`, or
/// `fontSize`.
///
/// ### Lifecycle responsibilities
///
/// This widget self-dispatches [PreviewThemeChanged] whenever the
/// inherited [Theme] or [DevOptions] flags actually change. The
/// dispatch happens from [didChangeDependencies] / a
/// [DevOptions] listener — **never** from [build] — so that closure
/// allocations are bounded to real change events instead of every
/// rebuild. Without this widget being mounted at least once, the
/// bloc has no theme reference and cannot prepare the builder. The
/// owning page is responsible for ensuring the bloc-view is mounted
/// before any prepare-dependent state is read.
///
/// All scroll-progress updates are forwarded **directly** to the
/// bloc's `PreviewScrollController` (bypassing the bloc event queue)
/// so high-frequency scroll signals do not churn state emissions.
class MarkdownPreviewBlocView extends StatefulWidget {
  /// Optional pre-resolved bloc. When `null`, the bloc is read from
  /// [BuildContext] via [BlocProvider].
  final MarkdownPreviewBloc? bloc;

  final EdgeInsets? padding;
  final void Function(CheckboxToggleInfo)? onCheckboxToggle;
  final void Function(String url)? onTapLink;
  final DoubleTapLineCallback? onDoubleTapLine;

  /// Invoked when a ghost-text placeholder is tapped in the preview.
  /// Carries the absolute source range of the whole `{{ … }}` run so
  /// the page can delete it and navigate to the editor.
  final void Function(int start, int end)? onGhostTap;

  /// Invoked when a `#tag` is tapped in the preview. Carries the full
  /// token (including `#`) so the page can search for it across notes.
  final void Function(String tag)? onTagTap;

  /// Invoked when a `$$` total or `$?` net-change row is tapped in the
  /// preview. Carries the tapped line index so the page can present
  /// the ledger entries feeding its value.
  final void Function(int lineIndex)? onMoneyTap;

  /// Forwarded **after** the bloc has been notified so callers that
  /// rely on the legacy callback (e.g. `PreviewScrollController`)
  /// keep working without going through the bloc state.
  final ValueChanged<double>? onScrollProgress;

  /// Forwarded to the underlying [SourceMappedMarkdownView] as a
  /// [GlobalKey] so existing imperative APIs (scrollToSourceOffset,
  /// scrollToLineIndex, ...) keep working through the controller.
  ///
  /// When `null`, the bloc's own scroll controller key is used so
  /// `bloc.scrollToProgress(...)` and friends resolve against the
  /// live view automatically.
  final Key? viewKey;

  const MarkdownPreviewBlocView({
    super.key,
    this.bloc,
    this.padding,
    this.onCheckboxToggle,
    this.onTapLink,
    this.onDoubleTapLine,
    this.onGhostTap,
    this.onTagTap,
    this.onMoneyTap,
    this.onScrollProgress,
    this.viewKey,
  });

  @override
  State<MarkdownPreviewBlocView> createState() =>
      _MarkdownPreviewBlocViewState();
}

class _MarkdownPreviewBlocViewState extends State<MarkdownPreviewBlocView> {
  late MarkdownPreviewBloc _bloc;
  late GlobalKey<SourceMappedMarkdownViewState> _scrollKey;

  /// Cached cache key of the last [PreviewThemeChanged] dispatch so
  /// we can skip the dispatch entirely when neither brightness nor
  /// debug flags changed (the closure would still be different but
  /// the bloc's short-circuit would discard it).
  Brightness? _lastBrightness;
  bool? _lastDebugEnabled;
  ThemeData? _lastTheme;

  /// Listener registered on [DevOptions.instance] so flag toggles
  /// invalidate the preview without requiring a [Theme] change.
  late final VoidCallback _devOptionsListener;

  @override
  void initState() {
    super.initState();
    _bloc = widget.bloc ?? context.read<MarkdownPreviewBloc>();

    // Reuse the bloc's existing scroll-controller key when present so
    // imperative scroll APIs keep targeting the same state across
    // remounts of this widget.
    final existing = _bloc.scrollController.viewKey;
    if (existing != null) {
      _scrollKey = existing;
    } else {
      _scrollKey = GlobalKey<SourceMappedMarkdownViewState>();
      _bloc.scrollController.bindView(_scrollKey);
    }

    _bindCallbacks();

    _devOptionsListener = _maybeDispatchTheme;
    DevOptions.instance.addListener(_devOptionsListener);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Dispatched here (not in build) so the closure is only allocated
    // when something an inherited widget depends on actually changes.
    _maybeDispatchTheme();
  }

  @override
  void didUpdateWidget(covariant MarkdownPreviewBlocView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-resolve the bloc only if the caller is providing one
    // explicitly. When the bloc came from an ancestor [BlocProvider]
    // we keep the original reference — reading it again here would
    // throw `ProviderNotFoundException` if the provider was already
    // unmounted as part of the same parent rebuild that triggered
    // this `didUpdateWidget`. Provider swaps without a remount are
    // not supported by this widget.
    if (widget.bloc != null && !identical(widget.bloc, _bloc)) {
      _bloc = widget.bloc!;
      _lastBrightness = null;
      _lastDebugEnabled = null;
      _lastTheme = null;
      _maybeDispatchTheme();
    }
    if (oldWidget.onTapLink != widget.onTapLink ||
        oldWidget.onCheckboxToggle != widget.onCheckboxToggle ||
        oldWidget.onGhostTap != widget.onGhostTap ||
        oldWidget.onTagTap != widget.onTagTap ||
        oldWidget.onMoneyTap != widget.onMoneyTap) {
      _bindCallbacks();
    }
  }

  @override
  void dispose() {
    DevOptions.instance.removeListener(_devOptionsListener);
    super.dispose();
  }

  void _bindCallbacks() {
    final onCheckboxToggle = widget.onCheckboxToggle;
    _bloc.bindCallbacks(
      onLinkTap: widget.onTapLink,
      onCheckboxTap: onCheckboxToggle == null
          ? null
          : (start, end, isChecked) {
              onCheckboxToggle(
                CheckboxToggleInfo(
                  start: start,
                  end: end,
                  replacement: isChecked ? '[ ]' : '[x]',
                ),
              );
            },
      onGhostTap: widget.onGhostTap,
      onTagTap: widget.onTagTap,
      onMoneyTap: widget.onMoneyTap,
    );
  }

  /// Dispatches [PreviewThemeChanged] only when the cache key
  /// (brightness + debug flags) actually changed since the last
  /// dispatch, or when the [Theme] object identity changed (which
  /// covers cases where the theme tint changed without flipping
  /// brightness).
  void _maybeDispatchTheme() {
    if (!mounted) return;
    final theme = Theme.of(context);
    final devOptions = DevOptions.instance;
    final debugEnabled =
        devOptions.colorMarkdownBlocks || devOptions.showBlockBoundaries;

    if (identical(_lastTheme, theme) &&
        _lastBrightness == theme.brightness &&
        _lastDebugEnabled == debugEnabled) {
      return;
    }
    _lastTheme = theme;
    _lastBrightness = theme.brightness;
    _lastDebugEnabled = debugEnabled;

    _bloc.add(
      PreviewThemeChanged(
        brightness: theme.brightness,
        styleBuilder: (fontSize) =>
            LineMarkdownStyle.fromTheme(theme, fontSize),
        debugEnabled: debugEnabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveKey = widget.viewKey ?? _scrollKey;

    return BlocBuilder<MarkdownPreviewBloc, MarkdownPreviewState>(
      bloc: _bloc,
      buildWhen: (prev, next) {
        // Only rebuild the heavy list when the underlying builder
        // actually changed. Search index / highlight changes already
        // bump renderHandle inside the bloc (they re-prepare the
        // builder), so renderHandle alone is sufficient here.
        return prev.renderHandle != next.renderHandle ||
            prev.linesPerChunk != next.linesPerChunk ||
            prev.fontSize != next.fontSize;
      },
      builder: (context, state) {
        return SourceMappedMarkdownView(
          key: effectiveKey,
          service: _bloc.renderService,
          data: state.content,
          fontSize: state.fontSize,
          linesPerChunk: state.linesPerChunk,
          searchHighlights: state.searchHighlights,
          currentHighlightIndex: state.currentHighlightIndex,
          moneyConfig: state.moneyConfig,
          colorPalette: state.colorPalette,
          onGhostTap: widget.onGhostTap,
          onTagTap: widget.onTagTap,
          onMoneyTap: widget.onMoneyTap,
          padding: widget.padding,
          onCheckboxToggle: widget.onCheckboxToggle,
          onTapLink: widget.onTapLink,
          onDoubleTapLine: widget.onDoubleTapLine,
          onScrollProgress: (progress) {
            // Forward progress straight to the bloc-owned controller.
            // We deliberately do *not* round-trip through the bloc's
            // event queue here — scroll progress is a high-frequency
            // signal (60+ Hz) and pushing it through the queue would
            // emit a new state on every scroll frame, churning
            // Equatable comparisons across all listeners. The
            // controller's [ValueListenable<double>] (exposed as
            // `bloc.scrollProgress`) is the authoritative source.
            _bloc.scrollController.updateProgress(progress);
            widget.onScrollProgress?.call(progress);
          },
        );
      },
    );
  }
}
