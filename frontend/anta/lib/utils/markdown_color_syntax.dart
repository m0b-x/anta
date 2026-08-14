/// Shared definition, scanning, and colour resolution for the two
/// colour-aware inline constructs:
///
/// ```text
/// {red:missed the lift}     coloured text
/// ==yellow:new PR==         coloured highlight (`==text==` keeps the default)
/// ```
///
/// This is the single source of truth consumed by the preview renderer
/// (`LineBasedMarkdownBuilder`) and the live editor span builder
/// (`MarkdownEditorSpanBuilder`), so the two surfaces can never
/// disagree about what is a colour construct or which colour it maps
/// to.
///
/// Names are lowercase `[a-z0-9_-]` (1..[maxNameLength] chars). The
/// restricted alphabet keeps the scanner branchless and means a name is
/// rejected by shape long before any allocation happens — `{Todo: buy
/// milk}` never even looks like a colour construct.
///
/// **An unresolved name is never consumed.** `{note:see below}` renders
/// literally and `==note: see below==` renders as an ordinary default
/// highlight with its text intact, so adding a custom colour can only
/// ever add rendering, never retroactively eat existing note text.
library;

import 'package:flutter/painting.dart';

import '../constants/markdown_constants.dart';

/// Colour roles for one palette entry, pre-resolved for both themes so
/// the render hot path is a single map probe plus a field read — no
/// contrast maths, no allocation, no `HSLColor` round-trip per span.
class MarkdownColorSpec {
  /// Foreground colour for `{name:text}` runs.
  final Color lightText;
  final Color darkText;

  /// Background wash for `==name:text==` runs. The foreground stays the
  /// base text colour, so this only ever needs to read as a marker
  /// tint.
  final Color lightHighlight;
  final Color darkHighlight;

  const MarkdownColorSpec({
    required this.lightText,
    required this.darkText,
    required this.lightHighlight,
    required this.darkHighlight,
  });

  Color text({required bool dark}) => dark ? darkText : lightText;

  Color highlight({required bool dark}) =>
      dark ? darkHighlight : lightHighlight;
}

/// A resolved colour set: the built-in presets overlaid with the user's
/// custom colours from settings.
///
/// Instances are immutable and value-equal on [source] (the raw
/// persisted string the palette was decoded from). That makes the
/// palette usable directly as a render-cache key: comparing two
/// palettes is one string compare, and identical palettes short-circuit
/// on `identical` first.
class MarkdownColorPalette {
  /// The persisted `name=aarrggbb;name=aarrggbb` source this palette was
  /// decoded from. Empty for the presets-only palette.
  final String source;

  final Map<String, MarkdownColorSpec> _specs;

  const MarkdownColorPalette._(this.source, this._specs);

  /// Presets only — the palette in force before the user defines
  /// anything, and the fallback whenever settings are unavailable.
  static const MarkdownColorPalette presets = MarkdownColorPalette._(
    '',
    _presetSpecs,
  );

  /// The built-in preset names, in display order.
  static const List<String> presetNames = [
    'red',
    'orange',
    'yellow',
    'green',
    'teal',
    'blue',
    'purple',
    'pink',
    'gray',
  ];

  /// Longest accepted colour name. Bounds the scanner's name probe so a
  /// line of braces can never cost more than a few characters per `{`.
  static const int maxNameLength = 24;

  /// Upper bound on custom colours, so the palette stays a small map and
  /// the settings row list stays scannable.
  static const int maxCustomColors = 64;

  /// The spec for [name], or `null` when the name is unknown. Custom
  /// colours shadow presets of the same name, so redefining `red` works.
  MarkdownColorSpec? lookup(String name) => _specs[name];

  bool contains(String name) => _specs.containsKey(name);

  /// Decodes a palette from its persisted [source]
  /// (`name=aarrggbb;name=aarrggbb`). Malformed pairs are skipped rather
  /// than failing the whole decode, so one bad row can never cost the
  /// user their other colours.
  factory MarkdownColorPalette.decode(String source) {
    if (source.isEmpty) return presets;
    final specs = Map<String, MarkdownColorSpec>.of(_presetSpecs);
    for (final entry in _customEntries(source)) {
      specs[entry.$1] = _specFor(entry.$2);
    }
    return MarkdownColorPalette._(source, specs);
  }

  /// Encodes [colors] (name -> colour) to the persisted form. Names are
  /// assumed already normalized by [normalizeName].
  static String encode(Map<String, Color> colors) {
    final buffer = StringBuffer();
    var first = true;
    for (final entry in colors.entries) {
      if (!first) buffer.write(';');
      first = false;
      buffer
        ..write(entry.key)
        ..write('=')
        ..write(_toHex(entry.value));
    }
    return buffer.toString();
  }

  /// The custom colours in this palette as an editable map, for the
  /// settings page.
  Map<String, Color> toCustomColorMap() {
    final result = <String, Color>{};
    for (final entry in _customEntries(source)) {
      result[entry.$1] = Color(entry.$2);
    }
    return result;
  }

  static Iterable<(String, int)> _customEntries(String source) sync* {
    if (source.isEmpty) return;
    for (final pair in source.split(';')) {
      final sep = pair.indexOf('=');
      if (sep <= 0) continue;
      final name = pair.substring(0, sep);
      if (!isValidName(name)) continue;
      final argb = int.tryParse(pair.substring(sep + 1), radix: 16);
      if (argb == null) continue;
      yield (name, argb);
    }
  }

  static String _toHex(Color color) =>
      color.toARGB32().toRadixString(16).padLeft(8, '0');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkdownColorPalette && other.source == source;

  @override
  int get hashCode => source.hashCode;

  // ─────────────────────────────────────────────────────────────────
  // Name validation
  // ─────────────────────────────────────────────────────────────────

  /// Whether [name] matches the scanner's grammar: 1..[maxNameLength]
  /// characters of `a-z`, `0-9`, `_`, `-`.
  static bool isValidName(String name) {
    if (name.isEmpty || name.length > maxNameLength) return false;
    for (var i = 0; i < name.length; i++) {
      if (!_isNameChar(name.codeUnitAt(i))) return false;
    }
    return true;
  }

  /// Lowercases and strips characters the grammar rejects, so settings
  /// input always produces a name the scanner can actually match.
  static String normalizeName(String input) {
    final buffer = StringBuffer();
    final lower = input.toLowerCase();
    for (var i = 0; i < lower.length && buffer.length < maxNameLength; i++) {
      final c = lower.codeUnitAt(i);
      if (_isNameChar(c)) buffer.writeCharCode(c);
    }
    return buffer.toString();
  }

  static bool _isNameChar(int c) =>
      (c >= 0x61 && c <= 0x7A) || // a-z
      (c >= 0x30 && c <= 0x39) || // 0-9
      c == 0x5F || // _
      c == 0x2D; // -

  // ─────────────────────────────────────────────────────────────────
  // Contrast-safe resolution
  // ─────────────────────────────────────────────────────────────────

  /// Reference backgrounds the custom-colour contrast check resolves
  /// against. Fixed rather than theme-derived so a palette can be built
  /// in the service layer without a `BuildContext`, and so the same
  /// palette instance stays a valid render-cache key across both
  /// brightnesses.
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _darkSurface = Color(0xFF121212);

  /// Minimum contrast ratio a colour must reach against the surface.
  /// 3.0 (WCAG AA for large text) rather than 4.5 — accent text should
  /// stay recognisably the colour the user picked, and pushing every
  /// hue to 4.5 washes the palette out.
  static const double _minContrast = 3.0;

  static const double _highlightAlpha = 0.30;
  static const double _lightnessStep = 0.04;
  static const int _maxAdjustSteps = 20;

  /// Builds a spec for a user-picked [argb]: used verbatim on whichever
  /// theme it already reads on, and lightness-shifted only far enough to
  /// clear [_minContrast] on the theme where it would not.
  static MarkdownColorSpec _specFor(int argb) {
    final base = Color(argb);
    final light = _ensureContrast(base, dark: false);
    final dark = _ensureContrast(base, dark: true);
    return MarkdownColorSpec(
      lightText: light,
      darkText: dark,
      lightHighlight: light.withValues(alpha: _highlightAlpha),
      darkHighlight: dark.withValues(alpha: _highlightAlpha),
    );
  }

  static Color _ensureContrast(Color color, {required bool dark}) {
    final surface = dark ? _darkSurface : _lightSurface;
    if (_contrastRatio(color, surface) >= _minContrast) return color;

    var hsl = HSLColor.fromColor(color);
    for (var i = 0; i < _maxAdjustSteps; i++) {
      final next = dark
          ? hsl.lightness + _lightnessStep
          : hsl.lightness - _lightnessStep;
      if (next <= 0.0 || next >= 1.0) break;
      hsl = hsl.withLightness(next);
      final candidate = hsl.toColor();
      if (_contrastRatio(candidate, surface) >= _minContrast) return candidate;
    }
    return hsl.toColor();
  }

  static double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  // ─────────────────────────────────────────────────────────────────
  // Presets
  // ─────────────────────────────────────────────────────────────────

  /// Preset accents mirror the callout/money palettes so the whole app
  /// reads as one colour system. `yellow`'s highlight is the legacy
  /// `==mark==` amber, which makes `==yellow:x==` render identically to
  /// the default `==x==` — the default is simply the yellow preset.
  static const Map<String, MarkdownColorSpec> _presetSpecs = {
    'red': MarkdownColorSpec(
      lightText: Color(0xFFC62828),
      darkText: Color(0xFFEF9A9A),
      lightHighlight: Color(0x4DC62828),
      darkHighlight: Color(0x4DEF9A9A),
    ),
    'orange': MarkdownColorSpec(
      lightText: Color(0xFFE65100),
      darkText: Color(0xFFFFB74D),
      lightHighlight: Color(0x4DE65100),
      darkHighlight: Color(0x4DFFB74D),
    ),
    'yellow': MarkdownColorSpec(
      lightText: Color(0xFFF9A825),
      darkText: Color(0xFFFFD54F),
      lightHighlight: MarkdownConstants.markBackgroundLight,
      darkHighlight: MarkdownConstants.markBackgroundDark,
    ),
    'green': MarkdownColorSpec(
      lightText: Color(0xFF2E7D32),
      darkText: Color(0xFF81C784),
      lightHighlight: Color(0x4D2E7D32),
      darkHighlight: Color(0x4D81C784),
    ),
    'teal': MarkdownColorSpec(
      lightText: Color(0xFF00897B),
      darkText: Color(0xFF4DB6AC),
      lightHighlight: Color(0x4D00897B),
      darkHighlight: Color(0x4D4DB6AC),
    ),
    'blue': MarkdownColorSpec(
      lightText: Color(0xFF1976D2),
      darkText: Color(0xFF64B5F6),
      lightHighlight: Color(0x4D1976D2),
      darkHighlight: Color(0x4D64B5F6),
    ),
    'purple': MarkdownColorSpec(
      lightText: Color(0xFF6A1B9A),
      darkText: Color(0xFFBA68C8),
      lightHighlight: Color(0x4D6A1B9A),
      darkHighlight: Color(0x4DBA68C8),
    ),
    'pink': MarkdownColorSpec(
      lightText: Color(0xFFAD1457),
      darkText: Color(0xFFF06292),
      lightHighlight: Color(0x4DAD1457),
      darkHighlight: Color(0x4DF06292),
    ),
    'gray': MarkdownColorSpec(
      lightText: Color(0xFF546E7A),
      darkText: Color(0xFFB0BEC5),
      lightHighlight: Color(0x4D546E7A),
      darkHighlight: Color(0x4DB0BEC5),
    ),
  };
}

/// A matched `{name:content}` run. All offsets are relative to the
/// scanned string.
///
/// For a run opening at `open`, `[open, innerStart)` is the opening
/// chrome (`{name:`) and `[innerEnd, end)` is the closing chrome (`}`)
/// — the editor conceals exactly those two ranges and never touches the
/// code units in between, so caret and selection offsets stay aligned.
class MarkdownColorMatch {
  final int innerStart;
  final int innerEnd;
  final int end;
  final MarkdownColorSpec spec;

  const MarkdownColorMatch({
    required this.innerStart,
    required this.innerEnd,
    required this.end,
    required this.spec,
  });
}

/// Scanner for the colour constructs. Kept separate from
/// [MarkdownColorPalette] so the grammar has one home regardless of
/// which palette instance resolves it.
class MarkdownColorSyntax {
  MarkdownColorSyntax._();

  static const int _kOpenBrace = 0x7B;
  static const int _kCloseBrace = 0x7D;
  static const int _kColon = 0x3A;
  static const int _kBackslash = 0x5C;

  /// Lead character of a coloured-text run, for cheap line-level
  /// rejection before the full scanner runs.
  static const int leadCodeUnit = _kOpenBrace;

  /// Tries to match `{name:content}` opening at [open] in [text],
  /// resolving the name against [palette]. Returns `null` when the shape
  /// or the name does not resolve, in which case the caller must leave
  /// every character as literal text.
  ///
  /// [limit] clamps the search (defaults to `text.length`) so a run
  /// nested inside an emphasis segment can never style past that
  /// segment's closing marker.
  static MarkdownColorMatch? matchAt(
    String text,
    int open,
    MarkdownColorPalette palette, [
    int? limit,
  ]) {
    final end = limit ?? text.length;
    if (open < 0 || open >= end) return null;
    if (text.codeUnitAt(open) != _kOpenBrace) return null;

    // `{{` opens ghost text, which owns the run and is matched first by
    // both surfaces. Bail so the two grammars can never contend.
    final nameStart = open + 1;
    if (nameStart >= end || text.codeUnitAt(nameStart) == _kOpenBrace) {
      return null;
    }

    final nameEnd = _scanName(text, nameStart, end);
    if (nameEnd < 0) return null;

    final innerStart = nameEnd + 1; // skip ':'
    if (innerStart >= end) return null;

    final spec = palette.lookup(text.substring(nameStart, nameEnd));
    if (spec == null) return null;

    final innerEnd = _findClose(text, innerStart, end);
    if (innerEnd <= innerStart) return null; // empty or unterminated

    return MarkdownColorMatch(
      innerStart: innerStart,
      innerEnd: innerEnd,
      end: innerEnd + 1,
      spec: spec,
    );
  }

  /// For a `==…==` highlight whose content is `[innerStart, innerEnd)`:
  /// resolves a leading `name:` colour prefix.
  ///
  /// Returns the offset where the highlighted text actually begins
  /// (just past `name:`) together with the resolved colour, or `null`
  /// when the highlight takes the default amber. One substring and one
  /// map probe per run — the resolution check is what makes
  /// `==note: see below==` safe, since an unknown prefix is left as
  /// ordinary highlighted text.
  static ({int contentStart, MarkdownColorSpec spec})? matchHighlightPrefix(
    String text,
    int innerStart,
    int innerEnd,
    MarkdownColorPalette palette,
  ) {
    final nameEnd = _scanName(text, innerStart, innerEnd);
    if (nameEnd < 0) return null;
    // The prefix may not swallow the whole run: `==red:==` has no text.
    if (nameEnd + 1 >= innerEnd) return null;
    final spec = palette.lookup(text.substring(innerStart, nameEnd));
    if (spec == null) return null;
    return (contentStart: nameEnd + 1, spec: spec);
  }

  /// Scans a colour name starting at [start]. Returns the index of the
  /// terminating `:`, or `-1` when the shape does not match. Bounded by
  /// [MarkdownColorPalette.maxNameLength] so this stays O(1) per `{`.
  static int _scanName(String text, int start, int end) {
    var i = start;
    final max = start + MarkdownColorPalette.maxNameLength;
    final stop = end < max ? end : max;
    while (i < stop && MarkdownColorPalette._isNameChar(text.codeUnitAt(i))) {
      i++;
    }
    if (i == start) return -1; // empty name
    if (i >= end || text.codeUnitAt(i) != _kColon) return -1;
    return i;
  }

  /// Finds the `}` closing a run that starts at [innerStart], counting
  /// nested `{`/`}` pairs so `{red:a {green:b} c}` closes correctly.
  /// Backslash-escaped braces are skipped — the surrounding scanners
  /// treat `\{` as a literal, so this must agree.
  static int _findClose(String text, int innerStart, int end) {
    var depth = 0;
    var i = innerStart;
    while (i < end) {
      final c = text.codeUnitAt(i);
      if (c == _kBackslash) {
        i += 2;
        continue;
      }
      if (c == _kOpenBrace) {
        depth++;
      } else if (c == _kCloseBrace) {
        if (depth == 0) return i;
        depth--;
      }
      i++;
    }
    return -1;
  }
}
