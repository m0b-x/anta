import 'package:flutter/material.dart';

import 'markdown_editor_paint_spans.dart';
import 'markdown_list_syntax.dart';

/// Everything the live editor's renderer reads from the widget tree,
/// resolved once per theme/style generation instead of once per line.
///
/// The re_editor fork calls the page's line builder with a
/// [BuildContext] and the line's [TextStyle]; the page turns that pair
/// into one of these and hands the same instance to every line, so no
/// library under `lib/utils/markdown_editor_*` depends on the widget
/// tree and every rendering surface is testable as plain Dart.
///
/// Value equality over [style], [baseColor], [primary] and [isDark] is
/// what makes it the span memos' generation key: two contexts that
/// compare equal produce byte-identical spans, so a memo filled under
/// one is valid under the other. [onAccent] is derived from [primary]
/// and [listAdvances] and [quoteAdvances] from [style], so none of them
/// is ever compared.
@immutable
class EditorRenderContext {
  /// The style re_editor gives the line. Every style the renderer
  /// produces is a `copyWith` off this one.
  final TextStyle style;

  /// The colour plain text renders in: [style]'s own colour when it
  /// sets one, the theme's body colour otherwise.
  final Color baseColor;

  final Color primary;

  final bool isDark;

  /// Contrast colour for a mark painted on a [primary]-filled shape —
  /// the checked task box's tick.
  final Color onAccent;

  EditorRenderContext({
    required this.style,
    required this.baseColor,
    required this.primary,
    required this.isDark,
  }) : onAccent =
           ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
           ? Colors.white
           : Colors.black87;

  /// The measured list-chrome advances in [style]'s font, upright or
  /// italic (a quote's content is italic), from which a list line's
  /// letter spacing is derived. Measured lazily, once per context
  /// instance, because one context serves every line of a generation and
  /// a `TextPainter` layout per line would cost the render path more than
  /// the whole marker prefix.
  EditorListAdvances listAdvances(FontStyle? fontStyle) =>
      fontStyle == FontStyle.italic ? _italicAdvances : _uprightAdvances;

  late final EditorListAdvances _uprightAdvances = EditorListAdvances._measure(
    style.copyWith(fontStyle: FontStyle.normal),
  );

  late final EditorListAdvances _italicAdvances = EditorListAdvances._measure(
    style.copyWith(fontStyle: FontStyle.italic),
  );

  /// The measured quote-marker advances in [style]'s font, upright or
  /// italic, from which the gap after a quote's `>` run is letter-spaced.
  /// Lazy and once per context instance for the reason [listAdvances] is.
  EditorQuoteAdvances quoteAdvances(FontStyle? fontStyle) =>
      fontStyle == FontStyle.italic ? _italicQuote : _uprightQuote;

  late final EditorQuoteAdvances _uprightQuote = EditorQuoteAdvances._measure(
    style.copyWith(fontStyle: FontStyle.normal),
  );

  late final EditorQuoteAdvances _italicQuote = EditorQuoteAdvances._measure(
    style.copyWith(fontStyle: FontStyle.italic),
  );

  /// Resolves the renderer's palette from [theme] and the line's
  /// [style], the one derivation both editor surfaces use.
  factory EditorRenderContext.fromTheme(ThemeData theme, TextStyle style) =>
      EditorRenderContext(
        style: style,
        baseColor:
            style.color ?? theme.textTheme.bodyLarge?.color ?? Colors.grey,
        primary: theme.colorScheme.primary,
        isDark: theme.brightness == Brightness.dark,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorRenderContext &&
          other.style == style &&
          other.baseColor == baseColor &&
          other.primary == primary &&
          other.isDark == isDark;

  @override
  int get hashCode => Object.hash(style, baseColor, primary, isDark);
}

/// The advances a list line's letter spacing is derived from, in one
/// font style of one [EditorRenderContext]: the indent's space and tab,
/// the bold depth glyphs a concealed bullet draws and the plain raw
/// markers a revealed one draws. Colour never changes an advance, so the
/// dimmed and primary styles share these.
@immutable
class EditorListAdvances {
  final double space;
  final double tab;
  final List<double> _glyphs;
  final List<double> _markers;

  /// The bullet markers the list grammar accepts, in [_markers]' order.
  static const String _markerChars = '-*+•';

  const EditorListAdvances._(this.space, this.tab, this._glyphs, this._markers);

  factory EditorListAdvances._measure(TextStyle style) {
    final painter = TextPainter(textDirection: TextDirection.ltr);
    try {
      final glyphStyle = style.copyWith(fontWeight: FontWeight.bold);
      final markerStyle = style.copyWith(fontWeight: FontWeight.normal);
      return EditorListAdvances._(
        _advanceOf(painter, ' ', style),
        _advanceOf(painter, '\t', style),
        [
          for (var level = 0; level < 2; level++)
            _advanceOf(
              painter,
              MarkdownListSyntax.bulletGlyph(level),
              glyphStyle,
            ),
        ],
        [
          for (var i = 0; i < _markerChars.length; i++)
            _advanceOf(painter, _markerChars[i], markerStyle),
        ],
      );
    } finally {
      painter.dispose();
    }
  }

  static double _advanceOf(TextPainter painter, String unit, TextStyle style) {
    painter
      ..text = TextSpan(text: '$unit|', style: style)
      ..layout();
    return painter
        .getOffsetForCaret(const TextPosition(offset: 1), Rect.zero)
        .dx;
  }

  /// The bold advance of [MarkdownListSyntax.bulletGlyph] for [level],
  /// whose three glyphs cycle with the level. A level that draws the
  /// painted [EditorBulletSquareSpan] takes the `•`'s advance as its box
  /// width, so its gap and content column are a dot line's.
  double glyph(int level) =>
      _glyphs[EditorBulletSquareSpan.drawsLevel(level) ? 0 : level % 3];

  /// The plain advance of the raw bullet [marker] code unit; a unit the
  /// grammar never yields measures as the [level]'s glyph, so the gap
  /// after it is left as typed.
  double marker(int marker, int level) => switch (marker) {
    0x2D => _markers[0],
    0x2A => _markers[1],
    0x2B => _markers[2],
    0x2022 => _markers[3],
    _ => glyph(level),
  };
}

/// The advances a quote line's `>` run is drawn with, in one font style
/// of one [EditorRenderContext]: the `┃` bar a concealed line draws (in
/// the line's weight for a plain quote, bold for a callout) and the raw
/// `>` a revealed one draws dimmed at normal weight. The fallback face
/// the bar comes from is wider than the `>` on some devices, so the gap
/// after the run absorbs the difference.
@immutable
class EditorQuoteAdvances {
  final double bar;
  final double boldBar;
  final double marker;

  const EditorQuoteAdvances._(this.bar, this.boldBar, this.marker);

  factory EditorQuoteAdvances._measure(TextStyle style) {
    final painter = TextPainter(textDirection: TextDirection.ltr);
    try {
      // The quote's bar ground: the line style, its weight pinned to
      // normal when it leaves the weight unset.
      final ground = style.fontWeight == null
          ? style.copyWith(fontWeight: FontWeight.normal)
          : style;
      return EditorQuoteAdvances._(
        EditorListAdvances._advanceOf(painter, '┃', ground),
        EditorListAdvances._advanceOf(
          painter,
          '┃',
          ground.copyWith(fontWeight: FontWeight.bold),
        ),
        EditorListAdvances._advanceOf(
          painter,
          '>',
          ground.copyWith(fontWeight: FontWeight.normal),
        ),
      );
    } finally {
      painter.dispose();
    }
  }
}

/// One [EditorRenderContext] per theme/style generation, held by the
/// surface that owns an editor.
///
/// re_editor asks for a span once per visible line per layout pass, so
/// the derivation must not run per line. `Theme.of` hands back the same
/// [ThemeData] instance until the theme actually changes, and the fork
/// reuses its line style, so the common path is two identity checks;
/// only a real generation change allocates.
///
/// An ancestor that builds its `ThemeData(...)` inside `build()` hands
/// over a fresh instance every frame, which no identity check can
/// absorb — so a miss falls back to comparing the *derived* context by
/// value and keeps returning the cached instance when it matches. That
/// costs one derivation per layout pass instead of one per line, and it
/// is what keeps the span memos (whose generation key this is) warm.
class EditorRenderContextCache {
  ThemeData? _theme;
  TextStyle? _style;
  EditorRenderContext? _context;

  /// The render context for [theme] and [style], reusing the cached
  /// instance whenever the derived values have not moved.
  EditorRenderContext of(ThemeData theme, TextStyle style) {
    final cached = _context;
    if (cached != null &&
        identical(theme, _theme) &&
        (identical(style, _style) || style == _style)) {
      return cached;
    }
    final context = EditorRenderContext.fromTheme(theme, style);
    // Adopt the new references either way, so a rebuilt-but-equal theme
    // pays the value comparison once rather than on every line.
    _theme = theme;
    _style = style;
    if (cached != null && context == cached) return cached;
    _context = context;
    return context;
  }
}
