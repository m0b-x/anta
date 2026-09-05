import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'lru_cache.dart';

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
/// The span is `const`, so the laid-out [TextPainter] cannot live on the
/// instance: it comes from a small shared LRU keyed by the three things
/// that decide the glyph's pixels — icon, colour and side. Callout leads
/// are rare enough that a handful of entries covers every visible line,
/// and a miss costs one icon-glyph layout.
class EditorCalloutIconSpan extends CodeInlinePaintSpan {
  final IconData icon;
  final Color accent;

  const EditorCalloutIconSpan({
    required double side,
    required this.icon,
    required this.accent,
  }) : super(width: side, height: side);

  static const int _painterCacheSize = 32;

  static final LruCache<(IconData, Color, double), TextPainter> _painters =
      LruCache(maxSize: _painterCacheSize);

  static TextPainter _painterFor(IconData icon, Color accent, double side) {
    final key = (icon, accent, side);
    final cached = _painters.get(key);
    if (cached != null) return cached;
    final painter = TextPainter(
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
    _painters.put(key, painter);
    return painter;
  }

  @override
  void paint(Canvas canvas, Rect rect) {
    final painter = _painterFor(icon, accent, rect.height);
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
      other is EditorCalloutIconSpan &&
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
enum EditorCheckboxVisual { unchecked, checked, indeterminate }

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

  const EditorCheckboxSpan({
    required double side,
    required this.visual,
    required this.accent,
    required this.border,
    required this.mark,
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
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorCheckboxSpan &&
          other.visual == visual &&
          other.accent == accent &&
          other.border == border &&
          other.mark == mark &&
          other.width == width &&
          other.height == height &&
          other.style == style;

  @override
  int get hashCode =>
      Object.hash(visual, accent, border, mark, width, height, style);
}
