import 'dart:ui' show Brightness;

import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart' show TextRange;

import '../../utils/line_based_markdown_builder.dart';
import '../../utils/markdown_color_syntax.dart';
import '../../utils/money_display_config.dart';

/// Events for the markdown preview rendering pipeline.
///
/// All events are pure data — they describe an input change. Heavy
/// objects (parsed AST, span trees, gesture recognizers) live inside
/// the bloc's [MarkdownRenderService] and never travel through the
/// event/state stream.
sealed class MarkdownPreviewEvent extends Equatable {
  const MarkdownPreviewEvent();

  @override
  List<Object?> get props => const [];
}

/// New markdown source text. Triggers a re-prepare of the underlying
/// builder when the content actually differs from the last prepared
/// content.
final class PreviewContentChanged extends MarkdownPreviewEvent {
  final String content;

  const PreviewContentChanged(this.content);

  @override
  List<Object?> get props => [content];
}

/// Preview font size changed (in logical pixels).
final class PreviewFontSizeChanged extends MarkdownPreviewEvent {
  final double fontSize;

  const PreviewFontSizeChanged(this.fontSize);

  @override
  List<Object?> get props => [fontSize];
}

/// Search highlight ranges and current match index.
///
/// Pass `highlights: null` to clear all highlights.
final class PreviewSearchUpdated extends MarkdownPreviewEvent {
  final List<TextRange>? highlights;
  final int? currentIndex;

  const PreviewSearchUpdated({this.highlights, this.currentIndex});

  @override
  List<Object?> get props => [highlights, currentIndex];
}

/// Configured chunk size (lines per chunk) for the preview list.
final class PreviewLinesPerChunkChanged extends MarkdownPreviewEvent {
  final int linesPerChunk;

  const PreviewLinesPerChunkChanged(this.linesPerChunk);

  @override
  List<Object?> get props => [linesPerChunk];
}

/// Money ledger display config (enabled flag, global start balance,
/// the note's effective currency, localized error strings), resolved
/// from settings by the page on note load or after a settings/locale
/// change. Carried as one value-equal object so half a config is
/// unrepresentable.
final class PreviewMoneyConfigChanged extends MarkdownPreviewEvent {
  final MoneyDisplayConfig config;

  const PreviewMoneyConfigChanged(this.config);

  @override
  List<Object?> get props => [config];
}

/// Markdown colour palette (presets + the user's custom colours),
/// resolved from settings by the page on note load or after a settings
/// change. Drives `{name:text}` runs and `==name:text==` highlights.
final class PreviewColorPaletteChanged extends MarkdownPreviewEvent {
  final MarkdownColorPalette palette;

  const PreviewColorPaletteChanged(this.palette);

  @override
  List<Object?> get props => [palette];
}

/// Requests the bloc to pull the latest source text from its bound
/// content provider (see [MarkdownPreviewBloc.bindContentProvider]).
///
/// Used by call sites that don't want to materialize the editor text
/// just to dispatch it: they call
/// [MarkdownPreviewBloc.markContentDirty] on every keystroke (free)
/// and dispatch this event when they actually want a refresh. The
/// bloc internally compares the dirty version against the version it
/// last consumed and short-circuits when nothing has changed,
/// avoiding even the string-equality compare against `state.content`.
final class PreviewContentRefreshRequested extends MarkdownPreviewEvent {
  const PreviewContentRefreshRequested();
}

/// Toggles the parent page's preview/edit mode flag. The bloc only
/// records this; it does not by itself change the rendering pipeline.
final class PreviewModeToggled extends MarkdownPreviewEvent {
  final bool isPreviewMode;

  const PreviewModeToggled(this.isPreviewMode);

  @override
  List<Object?> get props => [isPreviewMode];
}

/// Theme/style change. The widget builds a [LineMarkdownStyle]
/// factory bound to the current [BuildContext] and forwards it
/// together with the [Brightness] cache key. The factory takes the
/// current font size so the bloc can rebuild the style with the
/// correct font size on every prepare without the widget having to
/// re-dispatch on font changes. Also carries the dev-options debug
/// flag so the bloc can invalidate when block-coloring or boundary
/// indicators are toggled.
final class PreviewThemeChanged extends MarkdownPreviewEvent {
  final Brightness brightness;
  final LineMarkdownStyle Function(double fontSize) styleBuilder;
  final bool debugEnabled;

  const PreviewThemeChanged({
    required this.brightness,
    required this.styleBuilder,
    required this.debugEnabled,
  });

  // [styleBuilder] is a closure and not Equatable; rely on
  // [brightness] + [debugEnabled] as the comparison key. The bloc
  // updates its cached factory on every dispatch but only triggers
  // a rebuild when the cache key actually changes.
  @override
  List<Object?> get props => [brightness, debugEnabled];
}
