import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

/// The live editor's custom-painted inline runs.
///
/// Each one is a fork [CodeInlinePaintSpan]: a placeholder run that
/// substitutes 1:1 for exactly one source code unit and paints itself
/// after the paragraph is drawn. All of them keep their box under the
/// line's strut height so a line never grows, and all of them are
/// value-equal so re_editor's paragraph cache stays on its fast path
/// while nothing they draw has changed.

/// The live editor's `$$` money total: a rounded chip with the running
/// balance custom-painted into a placeholder run, substituting 1:1 for
/// the second `$` code unit (the first stays concealed beside it). The
/// [TextPainter] is laid out once at construction and reused every
/// frame; equality is value-based (label + colours + geometry) so
/// re_editor's paragraph cache stays on its fast path when the balance
/// is unchanged.
class EditorMoneyTotalSpan extends CodeInlinePaintSpan {
  final TextPainter painter;
  final String label;
  final Color accent;
  final Color chip;
  final double radius;

  const EditorMoneyTotalSpan({
    required super.width,
    required super.height,
    required this.painter,
    required this.label,
    required this.accent,
    required this.chip,
    required this.radius,
  });

  static final Paint _chipPaint = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Rect rect) {
    // Unfilled (op-row slot) values paint the number alone — the dimmed
    // annotation look the preview gives their trailing `= balance`.
    if (chip.a > 0) {
      _chipPaint.color = chip;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        _chipPaint,
      );
    }
    painter.paint(
      canvas,
      Offset(
        rect.left + (rect.width - painter.width) / 2,
        rect.top + (rect.height - painter.height) / 2,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorMoneyTotalSpan &&
          other.label == label &&
          other.accent == accent &&
          other.chip == chip &&
          other.radius == radius &&
          other.width == width &&
          other.height == height &&
          other.style == style;

  @override
  int get hashCode =>
      Object.hash(label, accent, chip, radius, width, height, style);
}

/// The live editor's callout icon: the type's [IconData] custom-painted
/// into a placeholder run, substituting 1:1 for the `[` of a
/// `> [!TYPE]` lead token (the `!TYPE]` stays concealed beside it). Side
/// and colour come from the line's own style and the shared callout
/// accent, so the mark scales with the editor's text size and matches
/// the preview's header.
///
/// Like the money chip, the glyph's [TextPainter] is laid out once at
/// construction and reused every frame: the span instance lives in the
/// renderer's positional memo, so the painter's lifetime is the span's
/// and a repeat build of the same lead line neither re-lays the glyph
/// nor allocates a new one.
class EditorCalloutIconSpan extends CodeInlinePaintSpan {
  final TextPainter painter;
  final IconData icon;
  final Color accent;

  /// Blank width after the icon's square. A titleless lead sets it: its
  /// label follows the icon with no source blank between them, and the
  /// gap is width, never a code unit.
  final double gap;

  EditorCalloutIconSpan({
    required double side,
    required this.icon,
    required this.accent,
    this.gap = 0,
  }) : painter = layoutPainter(icon, accent, side),
       super(width: side + gap, height: side);

  /// The laid-out icon glyph for one callout mark. Static so the
  /// constructor can hand it to the `final` field, and so a caller that
  /// already holds a painter (a test, a future variant) can build one
  /// the same way.
  static TextPainter layoutPainter(IconData icon, Color accent, double side) =>
      TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: side,
            color: accent,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Rect rect) {
    painter.paint(
      canvas,
      Offset(
        rect.left + (rect.width - gap - painter.width) / 2,
        rect.top + (rect.height - painter.height) / 2,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorCalloutIconSpan &&
          other.gap == gap &&
          other.icon == icon &&
          other.accent == accent &&
          other.width == width &&
          other.height == height &&
          other.style == style;

  @override
  int get hashCode => Object.hash(icon, accent, width, height, style);
}

/// Which glyph the editor checkbox paints. `indeterminate` is a purely
/// visual facet of an unchecked box whose child tasks are partially
/// complete — the source text stays `[ ]`, and a tap still checks it.
/// `custom` is a box holding an Obsidian state unit (`[-]`, `[/]`, …),
/// painted from [EditorCheckboxSpan.state].
enum EditorCheckboxVisual { unchecked, checked, indeterminate, custom }

/// The live editor's task checkbox: a rounded box custom-painted into a
/// placeholder run (fork's [CodeInlinePaintSpan]), replacing the old
/// icon-font glyph. The paragraph layout centers the reserved box on
/// the line box (PlaceholderAlignment.middle) and its side scales with
/// the line's own font size, so the mark stays proportional and
/// vertically centered at every editor text-size setting, independent
/// of any font's metrics. Substitutes 1:1 for the `[` code unit; the
/// `x]` stays concealed beside it.
class EditorCheckboxSpan extends CodeInlinePaintSpan {
  final EditorCheckboxVisual visual;
  final Color accent;
  final Color border;
  final Color mark;

  /// The box's state unit for [EditorCheckboxVisual.custom]: `-` paints a
  /// dimmed cross (cancelled), `/` a half fill (in progress), `>` and `<`
  /// arrows, `*` a star, and any other unit draws itself (`?`, `!`, …).
  /// Empty for the other visuals.
  final String state;

  const EditorCheckboxSpan({
    required double side,
    required this.visual,
    required this.accent,
    required this.border,
    required this.mark,
    this.state = '',
  }) : super(width: side, height: side);

  // Glyph geometry as fractions of the box side.
  static const double _strokeFrac = 0.09;
  static const double _minStroke = 1.4;
  static const double _radiusFrac = 0.21;
  static const double _insetFrac = 0.05;

  // Paint objects are shared across all checkboxes (single-threaded UI
  // painting) so per-frame drawing allocates nothing but the check path.
  static final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;
  static final Paint _markPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Rect rect) {
    final side = rect.height;
    var stroke = side * _strokeFrac;
    if (stroke < _minStroke) stroke = _minStroke;
    final box = rect.deflate(side * _insetFrac + stroke / 2);
    final rrect = RRect.fromRectAndRadius(
      box,
      Radius.circular(side * _radiusFrac),
    );
    switch (visual) {
      case EditorCheckboxVisual.unchecked:
        _strokePaint
          ..color = border
          ..strokeWidth = stroke;
        canvas.drawRRect(rrect, _strokePaint);
      case EditorCheckboxVisual.checked:
        _fillPaint.color = accent;
        canvas.drawRRect(rrect, _fillPaint);
        _markPaint
          ..color = mark
          ..strokeWidth = stroke * 1.15;
        final check = Path()
          ..moveTo(box.left + box.width * 0.24, box.top + box.height * 0.53)
          ..lineTo(box.left + box.width * 0.43, box.top + box.height * 0.72)
          ..lineTo(box.left + box.width * 0.78, box.top + box.height * 0.30);
        canvas.drawPath(check, _markPaint);
      case EditorCheckboxVisual.indeterminate:
        _strokePaint
          ..color = accent
          ..strokeWidth = stroke;
        canvas.drawRRect(rrect, _strokePaint);
        _markPaint
          ..color = accent
          ..strokeWidth = stroke * 1.3;
        canvas.drawLine(
          Offset(box.left + box.width * 0.28, box.center.dy),
          Offset(box.right - box.width * 0.28, box.center.dy),
          _markPaint,
        );
      case EditorCheckboxVisual.custom:
        _paintState(canvas, box, rrect, stroke);
    }
  }

  /// A custom state's box: outlined in the accent (a cancelled `-` in the
  /// dimmed border colour, matching its struck-through content) with the
  /// state's mark inside.
  void _paintState(Canvas canvas, Rect box, RRect rrect, double stroke) {
    final color = state == '-' ? border : accent;
    _strokePaint
      ..color = color
      ..strokeWidth = stroke;
    canvas.drawRRect(rrect, _strokePaint);
    _markPaint
      ..color = color
      ..strokeWidth = stroke * 1.15;
    double x(double f) => box.left + box.width * f;
    double y(double f) => box.top + box.height * f;
    switch (state) {
      // A cross, not a dash: a dash reads as the indeterminate parent's
      // bar, which means "partly done", the opposite of cancelled.
      case '-':
        canvas
          ..drawLine(
            Offset(x(0.32), y(0.32)),
            Offset(x(0.68), y(0.68)),
            _markPaint,
          )
          ..drawLine(
            Offset(x(0.68), y(0.32)),
            Offset(x(0.32), y(0.68)),
            _markPaint,
          );
      case '/':
        canvas
          ..save()
          ..clipRRect(rrect);
        _fillPaint.color = accent;
        canvas
          ..drawRect(
            Rect.fromLTRB(box.left, box.top, box.center.dx, box.bottom),
            _fillPaint,
          )
          ..restore();
      case '>':
        canvas.drawPath(
          Path()
            ..moveTo(x(0.38), y(0.26))
            ..lineTo(x(0.64), y(0.5))
            ..lineTo(x(0.38), y(0.74)),
          _markPaint,
        );
      case '<':
        canvas.drawPath(
          Path()
            ..moveTo(x(0.62), y(0.26))
            ..lineTo(x(0.36), y(0.5))
            ..lineTo(x(0.62), y(0.74)),
          _markPaint,
        );
      case '*':
        final star = Path();
        final outer = box.width * 0.32;
        final inner = outer * 0.45;
        for (var i = 0; i < 10; i++) {
          final r = i.isEven ? outer : inner;
          final a = -math.pi / 2 + i * math.pi / 5;
          final p = box.center + Offset(math.cos(a) * r, math.sin(a) * r);
          i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
        }
        _fillPaint.color = accent;
        canvas.drawPath(star..close(), _fillPaint);
      default:
        final glyph = _glyph(state, accent, box.height * 0.8);
        glyph.paint(
          canvas,
          box.center - Offset(glyph.width / 2, glyph.height / 2),
        );
    }
  }

  // Laid-out state glyphs, shared across boxes so a repaint lays out
  // nothing; bounded because the key carries the size and the colour.
  static final Map<(String, Color, double), TextPainter> _glyphs = {};
  static const int _maxGlyphs = 32;

  static TextPainter _glyph(String unit, Color color, double size) {
    final key = (unit, color, size);
    final cached = _glyphs[key];
    if (cached != null) return cached;
    if (_glyphs.length >= _maxGlyphs) {
      for (final painter in _glyphs.values) {
        painter.dispose();
      }
      _glyphs.clear();
    }
    return _glyphs[key] = TextPainter(
      text: TextSpan(
        text: unit,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorCheckboxSpan &&
          other.visual == visual &&
          other.accent == accent &&
          other.border == border &&
          other.mark == mark &&
          other.state == state &&
          other.width == width &&
          other.height == height &&
          other.style == style;

  @override
  int get hashCode =>
      Object.hash(visual, accent, border, mark, state, width, height, style);
}
