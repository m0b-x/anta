import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'ghost_text.dart';

/// The live editor's leaf emission: the one place a source range turns
/// into spans, and the one place the surface's hard invariant is
/// checked.
///
/// Every line shape in the renderer funnels its content through [emit],
/// which splits the range around ghost runs (markers concealed, inner
/// text dimmed) and guards in debug builds that the spans appended for
/// `[start, end)` carry exactly `end - start` UTF-16 code units — a
/// placeholder run counting as the single unit it substitutes. Chrome
/// the grammar guarantees ghost-free goes through [emitChrome] instead,
/// which skips both the split and the walk.
///
/// Everything here is static: emission is a pure function of its
/// arguments, so the build path allocates no emitter and captures no
/// closure per line.
class EditorSpanEmitter {
  const EditorSpanEmitter._();

  /// Concealed markers keep their code units but paint nothing: fully
  /// transparent and collapsed to a ~0 width, so the caret still counts
  /// them and the reader never sees them.
  static const Color transparent = Color(0x00000000);
  static const double concealedFontSize = 0.01;

  /// Alpha for raw markers on a reveal (caret) line and for ghost inner
  /// text — the "present but receding" tone this surface uses.
  static const double dimAlpha = 0.45;

  /// Markers rendered raw on a reveal line: dimmed and de-emphasised so
  /// the content still leads while the source is editable.
  static TextStyle dimStyle(TextStyle context, Color baseColor) =>
      context.copyWith(
        color: baseColor.withValues(alpha: dimAlpha),
        fontWeight: FontWeight.normal,
      );

  /// Markers hidden off-caret: transparent and ~0 wide, never dropped.
  static TextStyle concealStyle(TextStyle context) =>
      context.copyWith(color: transparent, fontSize: concealedFontSize);

  static bool isSpace(int codeUnit) => codeUnit == 0x20 || codeUnit == 0x09;

  /// Emits [start]..[end] in [style], splitting around ghost runs so
  /// their markers render concealed and their inner text dimmed (with an
  /// underline when blank, so the empty slot stays findable) — the same
  /// treatment as the standalone ghost builder, but inheriting the
  /// surrounding markdown style.
  ///
  /// Guards the code-unit invariant in debug builds: the spans appended
  /// to [out] for `[start, end)` must total exactly `end - start` UTF-16
  /// code units (a placeholder run counting as the one unit it
  /// substitutes). The check lives entirely inside `assert`s, so release
  /// builds pay nothing and allocate nothing for it.
  static void emit({
    required String text,
    required int start,
    required int end,
    required TextStyle style,
    required Color baseColor,
    required List<GhostMatch> ghosts,
    required List<InlineSpan> out,
    CodeTextDecoration? decoration,
  }) {
    var mark = 0;
    assert(() {
      mark = out.length;
      return true;
    }());
    _emitRange(
      text: text,
      start: start,
      end: end,
      style: style,
      baseColor: baseColor,
      ghosts: ghosts,
      out: out,
      decoration: decoration,
    );
    assert(
      _unitsAppendedFrom(out, mark) == (end > start ? end - start : 0),
      'code-unit invariant: emit appended '
      '${_unitsAppendedFrom(out, mark)} units for [$start, $end) of a '
      '${text.length}-unit line',
    );
  }

  /// Chrome the grammar guarantees ghost-free — delimiter runs, backtick
  /// fences, `{name:` and `}` — emitted as one span: the substring is
  /// the range, so the code-unit inventory holds by construction and
  /// the ghost split + debug inventory walk of [emit] would be wasted.
  static void emitChrome(
    String text,
    int start,
    int end,
    TextStyle style,
    List<InlineSpan> out,
  ) {
    if (start < end) {
      out.add(TextSpan(text: text.substring(start, end), style: style));
    }
  }

  /// UTF-16 code units carried by `out[from..]`, counting each
  /// placeholder run as the single source unit it substitutes. Only ever
  /// invoked from an `assert`.
  static int _unitsAppendedFrom(List<InlineSpan> out, int from) {
    var units = 0;
    for (var i = from; i < out.length; i++) {
      units += _unitsOf(out[i]);
    }
    return units;
  }

  static int _unitsOf(InlineSpan span) {
    if (span is PlaceholderSpan) return 1;
    if (span is TextSpan) {
      var units = span.text?.length ?? 0;
      final children = span.children;
      if (children != null) {
        for (final child in children) {
          units += _unitsOf(child);
        }
      }
      return units;
    }
    return 0;
  }

  static void _emitRange({
    required String text,
    required int start,
    required int end,
    required TextStyle style,
    required Color baseColor,
    required List<GhostMatch> ghosts,
    required List<InlineSpan> out,
    CodeTextDecoration? decoration,
  }) {
    if (start >= end) return;
    if (ghosts.isEmpty) {
      out.add(_plainSpan(text.substring(start, end), style, decoration));
      return;
    }
    var pos = start;
    for (final g in ghosts) {
      if (g.end <= pos) continue;
      if (g.start >= end) break;
      if (g.start > pos) {
        out.add(_plainSpan(text.substring(pos, g.start), style, decoration));
      }
      final ghostColor = baseColor.withValues(alpha: dimAlpha);
      var innerStyle = style.copyWith(color: ghostColor);
      if (_ghostBlank(text, g)) {
        innerStyle = innerStyle.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: ghostColor,
        );
      }
      final concealed = concealStyle(style);
      _emitClamped(text, g.start, g.innerStart, pos, end, concealed, out);
      _emitClamped(text, g.innerStart, g.innerEnd, pos, end, innerStyle, out);
      _emitClamped(text, g.innerEnd, g.end, pos, end, concealed, out);
      pos = g.end < end ? g.end : end;
      if (pos >= end) return;
    }
    if (pos < end) {
      out.add(_plainSpan(text.substring(pos, end), style, decoration));
    }
  }

  /// A plain emitted segment: an ordinary [TextSpan], or a
  /// [CodeDecoratedTextSpan] when the run paints a chip behind itself
  /// (tags, inline code). Ghost segments inside a decorated run keep
  /// plain spans — the ghost treatment wins there.
  static InlineSpan _plainSpan(
    String text,
    TextStyle style,
    CodeTextDecoration? decoration,
  ) => decoration == null
      ? TextSpan(text: text, style: style)
      : CodeDecoratedTextSpan(decoration: decoration, text: text, style: style);

  static void _emitClamped(
    String text,
    int from,
    int to,
    int lo,
    int hi,
    TextStyle style,
    List<InlineSpan> out,
  ) {
    final a = from > lo ? from : lo;
    final b = to < hi ? to : hi;
    if (a < b) {
      out.add(TextSpan(text: text.substring(a, b), style: style));
    }
  }

  static bool _ghostBlank(String text, GhostMatch g) {
    for (var i = g.innerStart; i < g.innerEnd; i++) {
      if (!isSpace(text.codeUnitAt(i))) return false;
    }
    return true;
  }
}
