import 'package:flutter/material.dart';

import '../utils/line_based_markdown_builder.dart';
import '../utils/markdown_chunker.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/money_display_config.dart';

/// Owns the lifecycle of a [LineBasedMarkdownBuilder] for a single
/// markdown preview surface.
///
/// This service centralizes the cache-invalidation rules and adaptive
/// chunk sizing that previously lived inside
/// `SourceMappedMarkdownView`. It is intentionally widget-free so it
/// can be driven by either a widget's [State] or a BLoC.
///
/// The service preserves the existing performance characteristics:
///   * Builder is reused as long as none of the inputs that affect
///     parsing/styling have changed.
///   * Builder is disposed and recreated when inputs change so that
///     gesture recognizers do not leak.
///   * Chunk LRU cache and lazy line extraction live inside the
///     underlying [LineBasedMarkdownBuilder] and are unaffected.
class MarkdownRenderService {
  LineBasedMarkdownBuilder? _builder;

  String? _lastData;
  double? _lastFontSize;
  List<TextRange>? _lastHighlights;
  int? _lastHighlightIndex;
  Brightness? _lastBrightness;
  int? _lastLinesPerChunk;
  bool? _lastDebugEnabled;
  MoneyDisplayConfig? _lastMoneyConfig;
  MarkdownColorPalette? _lastColorPalette;

  /// The active builder, or `null` if [prepare] has not been called yet.
  LineBasedMarkdownBuilder? get builder => _builder;

  int get chunkCount => _builder?.chunkCount ?? 0;
  int get lineCount => _builder?.lineCount ?? 0;
  int get linesPerChunk => _builder?.linesPerChunk ?? 0;

  /// The first source line of the block-aligned chunk that contains
  /// [lineIndex]. Returns 0 when no builder is prepared. Used by the
  /// editor page to compare the preview's top line against the saved
  /// cursor's chunk without assuming uniform chunk sizes.
  int chunkStartLineForLine(int lineIndex) {
    final b = _builder;
    if (b == null) return 0;
    return b.chunkStartLine(b.chunkIndexForLine(lineIndex));
  }

  /// Ensures the underlying builder is up to date for the given inputs.
  ///
  /// Returns `true` when the builder was rebuilt (i.e. cached spans
  /// were thrown away), `false` when the existing builder was reused.
  ///
  /// The invalidation rules mirror the previous in-widget logic
  /// exactly so behavior is unchanged. Callers without a
  /// [BuildContext] (e.g. a BLoC) build the [LineMarkdownStyle]
  /// themselves and pass it together with the [Brightness] cache key.
  bool prepareWithStyle({
    required String data,
    required double fontSize,
    required Brightness brightness,
    required LineMarkdownStyle style,
    required int linesPerChunk,
    required bool debugEnabled,
    List<TextRange>? searchHighlights,
    int? currentHighlightIndex,
    MoneyDisplayConfig moneyConfig = MoneyDisplayConfig.disabled,
    MarkdownColorPalette colorPalette = MarkdownColorPalette.presets,
    LinkTapCallback? onLinkTap,
    CheckboxTapCallback? onCheckboxTap,
    GhostTapCallback? onGhostTap,
    TagTapCallback? onTagTap,
    MoneyTapCallback? onMoneyTap,
  }) {
    final needsRebuild =
        _builder == null ||
        _lastData != data ||
        _lastFontSize != fontSize ||
        !_highlightsEqual(_lastHighlights, searchHighlights) ||
        _lastHighlightIndex != currentHighlightIndex ||
        _lastBrightness != brightness ||
        _lastLinesPerChunk != linesPerChunk ||
        _lastDebugEnabled != debugEnabled ||
        // Value-equal config: one comparison covers the enabled flag,
        // start balance, currency, and the localized error strings —
        // a locale change rebuilds automatically.
        _lastMoneyConfig != moneyConfig ||
        _lastColorPalette != colorPalette;

    if (!needsRebuild) {
      return false;
    }

    _lastData = data;
    _lastFontSize = fontSize;
    _lastHighlights = searchHighlights;
    _lastHighlightIndex = currentHighlightIndex;
    _lastBrightness = brightness;
    _lastLinesPerChunk = linesPerChunk;
    _lastDebugEnabled = debugEnabled;
    _lastMoneyConfig = moneyConfig;
    _lastColorPalette = colorPalette;

    final adaptiveChunkSize = MarkdownChunker.adaptiveChunkSize(
      _estimateLineCount(data),
      linesPerChunk,
    );

    _disposeBuilder();
    _builder = LineBasedMarkdownBuilder(
      style: style,
      onLinkTap: onLinkTap,
      onCheckboxTap: onCheckboxTap,
      onGhostTap: onGhostTap,
      onTagTap: onTagTap,
      onMoneyTap: onMoneyTap,
      searchHighlights: searchHighlights,
      currentHighlightIndex: currentHighlightIndex,
      moneyConfig: moneyConfig,
      colorPalette: colorPalette,
      linesPerChunk: adaptiveChunkSize,
    );
    _builder!.prepare(data);

    return true;
  }

  /// Pre-warm the LRU cache for [chunkIndex] without forcing a render.
  /// Safe to call with out-of-range indices (no-op).
  void preWarmChunk(int chunkIndex) {
    final b = _builder;
    if (b == null) return;
    if (chunkIndex < 0 || chunkIndex >= b.chunkCount) return;
    b.buildChunk(chunkIndex);
  }

  /// Disposes the underlying builder and clears all cached state.
  void dispose() {
    _disposeBuilder();
    _lastData = null;
    _lastFontSize = null;
    _lastHighlights = null;
    _lastHighlightIndex = null;
    _lastBrightness = null;
    _lastLinesPerChunk = null;
    _lastDebugEnabled = null;
    _lastMoneyConfig = null;
    _lastColorPalette = null;
  }

  void _disposeBuilder() {
    _builder?.dispose();
    _builder = null;
  }

  /// Counts source lines by scanning for newline characters. Used
  /// only to drive [MarkdownChunker.adaptiveChunkSize], so an
  /// off-by-one is inconsequential.
  int _estimateLineCount(String data) {
    return '\n'.allMatches(data).length + 1;
  }

  bool _highlightsEqual(List<TextRange>? a, List<TextRange>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].start != b[i].start || a[i].end != b[i].end) return false;
    }
    return true;
  }
}
