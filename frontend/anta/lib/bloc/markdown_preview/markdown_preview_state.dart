import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart' show TextRange;

import '../../utils/markdown_color_syntax.dart';
import '../../utils/money_display_config.dart';

/// Immutable snapshot of the markdown preview pipeline.
///
/// Stays intentionally small: no [InlineSpan] trees, no AST nodes, no
/// builder reference. Widgets read spans on demand from the bloc's
/// `MarkdownRenderService` keyed off [renderHandle], which is bumped
/// every time the underlying builder is rebuilt.
final class MarkdownPreviewState extends Equatable {
  /// Source markdown text last submitted to the bloc.
  final String content;

  /// Logical-pixel font size for preview text.
  final double fontSize;

  /// Configured (non-adaptive) lines per chunk.
  final int linesPerChunk;

  /// Whether the parent page is currently showing the preview.
  /// The bloc only records this; rendering work is gated by the
  /// widget consuming the state.
  final bool isPreviewMode;

  /// Active search match ranges, or `null` when search is inactive.
  final List<TextRange>? searchHighlights;

  /// Index of the "current" match within [searchHighlights].
  final int? currentHighlightIndex;

  /// Opaque token bumped every time the underlying builder is
  /// rebuilt. Widgets observing `buildWhen` should treat any change
  /// to this value as "spans may have changed; rebuild the list".
  final int renderHandle;

  /// Whether the bloc has received a [PreviewThemeChanged] event yet.
  /// Until this is `true` the bloc cannot prepare the builder, even
  /// if content/font are present.
  final bool hasTheme;

  /// Money ledger display config resolved by the page on note load —
  /// enabled flag, global start balance, the note's effective currency,
  /// and localized error strings — as one value-equal object (like
  /// [colorPalette], which makes it a safe render-cache key).
  final MoneyDisplayConfig moneyConfig;

  /// Resolved markdown colour palette (presets + the user's custom
  /// colours) driving `{name:text}` and `==name:text==`. Value-equal on
  /// its persisted source, so it is a safe render-cache key.
  final MarkdownColorPalette colorPalette;

  const MarkdownPreviewState({
    this.content = '',
    this.fontSize = 14.0,
    this.linesPerChunk = 10,
    this.isPreviewMode = false,
    this.searchHighlights,
    this.currentHighlightIndex,
    this.renderHandle = 0,
    this.hasTheme = false,
    this.moneyConfig = MoneyDisplayConfig.disabled,
    this.colorPalette = MarkdownColorPalette.presets,
  });

  MarkdownPreviewState copyWith({
    String? content,
    double? fontSize,
    int? linesPerChunk,
    bool? isPreviewMode,
    List<TextRange>? searchHighlights,
    bool clearSearchHighlights = false,
    int? currentHighlightIndex,
    bool clearCurrentHighlightIndex = false,
    int? renderHandle,
    bool? hasTheme,
    MoneyDisplayConfig? moneyConfig,
    MarkdownColorPalette? colorPalette,
  }) {
    return MarkdownPreviewState(
      content: content ?? this.content,
      fontSize: fontSize ?? this.fontSize,
      linesPerChunk: linesPerChunk ?? this.linesPerChunk,
      isPreviewMode: isPreviewMode ?? this.isPreviewMode,
      searchHighlights: clearSearchHighlights
          ? null
          : (searchHighlights ?? this.searchHighlights),
      currentHighlightIndex: clearCurrentHighlightIndex
          ? null
          : (currentHighlightIndex ?? this.currentHighlightIndex),
      renderHandle: renderHandle ?? this.renderHandle,
      hasTheme: hasTheme ?? this.hasTheme,
      moneyConfig: moneyConfig ?? this.moneyConfig,
      colorPalette: colorPalette ?? this.colorPalette,
    );
  }

  @override
  List<Object?> get props => [
    content,
    fontSize,
    linesPerChunk,
    isPreviewMode,
    searchHighlights,
    currentHighlightIndex,
    renderHandle,
    hasTheme,
    moneyConfig,
    colorPalette,
  ];
}
