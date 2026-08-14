import 'package:flutter/material.dart';

import '../constants/markdown_constants.dart';
import '../utils/line_based_markdown_builder.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/money_display_config.dart';

/// Renders a short markdown string clamped to [maxLines], for list rows.
///
/// Uses the same [LineBasedMarkdownBuilder] the preview pipeline uses — there
/// is exactly one markdown grammar in this app and this widget does not add a
/// second one. What it changes are display decisions only:
///
/// * headings render at body size (`flattenHeadings`) so a `# Leg day` cannot
///   blow a two-line row open,
/// * blank lines are dropped and only the first few lines are kept, so the
///   clamp spends its budget on text instead of spacers,
/// * every tap callback is left null, so the builder allocates **no**
///   `TapGestureRecognizer`s and the resulting spans are inert — that is what
///   makes them safe to cache and drop without a dispose dance,
/// * the money ledger is off: a balance is a per-note concept, so `$` lines in
///   an event description stay literal text.
class MarkdownInlineText extends StatelessWidget {
  final String data;
  final TextStyle? style;

  /// Visible line budget. The shared span keeps 3 source lines regardless, so
  /// values above that clamp — raise `_InlineMarkdownCache._maxLines` too if a
  /// caller ever needs more.
  final int maxLines;

  final MarkdownColorPalette colorPalette;

  const MarkdownInlineText({
    super.key,
    required this.data,
    this.style,
    this.maxLines = 2,
    this.colorPalette = MarkdownColorPalette.presets,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle =
        style ?? theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    final span = _InlineMarkdownCache.spanFor(
      data,
      theme: theme,
      fontSize: baseStyle.fontSize ?? 12,
      color: baseStyle.color ?? theme.colorScheme.onSurfaceVariant,
      palette: colorPalette,
    );
    if (span == null) return const SizedBox.shrink();
    return Text.rich(
      span,
      style: baseStyle,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Process-wide memo for row-sized markdown spans.
///
/// One builder is kept alive per render configuration and re-prepared per
/// string; both the builder and the memo are thrown away when the
/// configuration changes (theme, size, colour palette). The palette is
/// value-equal on its persisted `source`, which is what makes it a legal part
/// of the cache key. Eviction is oldest-inserted-first (Dart maps keep
/// insertion order) — good enough for a bounded set of visible rows, and it
/// avoids touching the map on every hit.
///
/// **The hit path allocates nothing.** This runs in `build` for every visible
/// row on every frame a list scrolls, so the config is compared field by field
/// rather than through a composed key string, the map is keyed on the raw
/// source, and the line collapsing only happens on a miss.
abstract final class _InlineMarkdownCache {
  static const int _maxEntries = 128;

  /// Lines kept from the source. Two are ever visible; the third exists so an
  /// ellipsis has something to elide.
  static const int _maxLines = 3;

  static LineBasedMarkdownBuilder? _builder;
  static final Map<String, TextSpan> _spans = {};

  // Render configuration the live builder and memo were made for.
  static Brightness? _brightness;
  static double? _fontSize;
  static Color? _color;
  static Color? _primary;
  static String? _paletteSource;

  static TextSpan? spanFor(
    String data, {
    required ThemeData theme,
    required double fontSize,
    required Color color,
    required MarkdownColorPalette palette,
  }) {
    if (data.isEmpty) return null;

    final primary = theme.colorScheme.primary;
    if (_brightness != theme.brightness ||
        _fontSize != fontSize ||
        _color != color ||
        _primary != primary ||
        _paletteSource != palette.source) {
      _builder?.dispose();
      _builder = null;
      _spans.clear();
      _brightness = theme.brightness;
      _fontSize = fontSize;
      _color = color;
      _primary = primary;
      _paletteSource = palette.source;
    }

    final cached = _spans[data];
    if (cached != null) return cached;

    final source = _collapse(data);
    if (source.isEmpty) return null;

    final builder = _builder ??= LineBasedMarkdownBuilder(
      style: LineMarkdownStyle.fromTheme(
        theme,
        fontSize,
        flattenHeadings: true,
        textColor: color,
      ),
      moneyConfig: MoneyDisplayConfig.disabled,
      colorPalette: palette,
      linesPerChunk: _maxLines,
    );

    final lines = builder.prepare(source);
    final children = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) children.add(const TextSpan(text: '\n'));
      children.add(builder.buildLine(lines[i], i));
    }
    final span = TextSpan(
      style: TextStyle(
        fontSize: fontSize,
        height: MarkdownConstants.lineHeight,
        color: color,
      ),
      children: children,
    );

    if (_spans.length >= _maxEntries) {
      _spans.remove(_spans.keys.first);
    }
    _spans[data] = span;
    return span;
  }

  /// Drops blank lines and keeps at most [_maxLines], so a description that
  /// opens with a heading and a blank line still shows real text in the two
  /// visible rows.
  static String _collapse(String data) {
    final kept = <String>[];
    for (final line in data.split('\n')) {
      if (line.trim().isEmpty) continue;
      kept.add(line);
      if (kept.length == _maxLines) break;
    }
    return kept.join('\n');
  }
}
