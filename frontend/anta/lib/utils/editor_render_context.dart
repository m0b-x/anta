import 'package:flutter/material.dart';

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
/// and therefore never compared.
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

/// One [EditorRenderContext] per theme/style generation, held by the
/// surface that owns an editor.
///
/// re_editor asks for a span once per visible line per layout pass, so
/// the derivation must not run per line. `Theme.of` hands back the same
/// [ThemeData] instance until the theme actually changes, and the fork
/// reuses its line style, so the common path is two identity checks;
/// only a real generation change allocates.
class EditorRenderContextCache {
  ThemeData? _theme;
  TextStyle? _style;
  EditorRenderContext? _context;

  EditorRenderContext of(ThemeData theme, TextStyle style) {
    final cached = _context;
    if (cached != null &&
        identical(theme, _theme) &&
        (identical(style, _style) || style == _style)) {
      return cached;
    }
    final context = EditorRenderContext.fromTheme(theme, style);
    _theme = theme;
    _style = style;
    _context = context;
    return context;
  }
}
