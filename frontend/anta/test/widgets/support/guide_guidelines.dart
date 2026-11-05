import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:anta/constants/guide_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/widgets/agenda_month_grid.dart';
import 'package:anta/widgets/calendar_bottom_panel.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/widgets/form_rows.dart';

/// Android's 48 dp tap-target guideline with the calendar guide's three
/// accepted exceptions taken out by name rather than the check skipped:
///
/// * a day cell of a grid inside [GuideTapTargetGuideline.of]'s `gridsOf` —
///   a "Try it" card's stage is 40 dp narrower than the screen, so at 360
///   its cells are about 45 dp wide where the real grid's are 51.4; a node
///   there is let off only when its width alone falls short;
/// * `PanelModeBar`'s 32 dp segments — the real calendar's own chrome, drawn
///   here as it is there (record §6 c);
/// * the practice band's back and forward, 40 wide × 48 tall (D87): two
///   full targets wrapped the band's line and broke its pinned height
///   (D39); a node there is let off only at that width and the full height.
///
/// Every other node is judged as the stock guideline judges it.
class GuideTapTargetGuideline extends MinimumTapTargetGuideline {
  GuideTapTargetGuideline._(
    this._ratio,
    this._grids,
    this._segments,
    this._bandPair,
  ) : super(size: _android.size, link: _android.link);

  static final MinimumTapTargetGuideline _android =
      androidTapTargetGuideline as MinimumTapTargetGuideline;

  /// The exceptions where they stand now.
  factory GuideTapTargetGuideline.of(WidgetTester tester, {Finder? gridsOf}) {
    List<Rect> areas(Finder finder) => [
      for (final element in finder.evaluate())
        if (element.renderObject case final RenderBox box when box.hasSize)
          box.localToGlobal(Offset.zero) & box.size,
    ];
    return GuideTapTargetGuideline._(
      tester.view.devicePixelRatio,
      gridsOf == null
          ? const []
          : areas(
              find.descendant(
                of: gridsOf,
                matching: find.byWidgetPredicate(
                  (widget) => widget is TableCalendar,
                ),
              ),
            ),
      areas(
        find.descendant(
          of: find.byType(PanelModeBar),
          matching: find.byWidgetPredicate(
            (widget) => widget is SegmentedButton,
          ),
        ),
      ),
      areas(
        find.byWidgetPredicate(
          (widget) =>
              widget is FormTrailingButton &&
              (widget.identifier == SemanticsIds.practiceStepBack ||
                  widget.identifier == SemanticsIds.practiceSkip),
        ),
      ),
    );
  }

  final double _ratio;

  /// Logical pixels, as the widgets measure.
  final List<Rect> _grids;
  final List<Rect> _segments;
  final List<Rect> _bandPair;

  @override
  bool shouldSkipNode(SemanticsNode node) {
    if (super.shouldSkipNode(node)) return true;
    // The node in physical pixels, as the stock check measures it, then in
    // logical ones.
    var physical = node.rect;
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      if (n.transform case final transform?) {
        physical = MatrixUtils.transformRect(transform, physical);
      }
    }
    final rect = Rect.fromLTRB(
      physical.left / _ratio,
      physical.top / _ratio,
      physical.right / _ratio,
      physical.bottom / _ratio,
    );
    bool inside(Rect area) {
      final room = area.inflate(0.5);
      return room.contains(rect.topLeft) && room.contains(rect.bottomRight);
    }

    final narrowCell = rect.width < size.width && rect.height >= size.height;
    final bandButton =
        rect.width >= GuideMetrics.bannerButtonWidth - 0.5 &&
        rect.height >= size.height;
    return _segments.any(inside) ||
        (narrowCell && _grids.any(inside)) ||
        (bandButton && _bandPair.any(inside));
  }

  @override
  String get description =>
      '${super.description}, the guide\'s three named exceptions aside';
}

/// Flutter's labelled-target guideline with one exception taken out by
/// name: the blank slots `AgendaMonthGrid` leaves for the days outside its
/// month (`outsideDaysVisible: false`), which `table_calendar` still wraps in
/// its tap and long-press detector — a tappable node with nothing to say, on
/// the real overview page's Month as on the guide's stage. A node there is
/// let off only when it holds no drawn day and has no label, tooltip or
/// value.
class GuideLabeledTapTargetGuideline extends AccessibilityGuideline {
  GuideLabeledTapTargetGuideline._(this._ratio, this._grids, this._days);

  /// The exception where it stands now.
  factory GuideLabeledTapTargetGuideline.of(WidgetTester tester) {
    List<Rect> areas(Finder finder) => [
      for (final element in finder.evaluate())
        if (element.renderObject case final RenderBox box when box.hasSize)
          box.localToGlobal(Offset.zero) & box.size,
    ];
    final grids = find.byType(AgendaMonthGrid);
    return GuideLabeledTapTargetGuideline._(
      tester.view.devicePixelRatio,
      areas(grids),
      areas(find.descendant(of: grids, matching: find.byType(CalendarDayCell))),
    );
  }

  final double _ratio;

  /// Logical pixels, as the widgets measure.
  final List<Rect> _grids;
  final List<Rect> _days;

  @override
  String get description =>
      '${labeledTapTargetGuideline.description}, the month grid\'s blank '
      'slots aside';

  @override
  FutureOr<Evaluation> evaluate(WidgetTester tester) {
    var result = const Evaluation.pass();
    for (final view in tester.binding.renderViews) {
      result += _traverse(view.owner!.semanticsOwner!.rootSemanticsNode!);
    }
    return result;
  }

  Evaluation _traverse(SemanticsNode node) {
    var result = const Evaluation.pass();
    node.visitChildren((child) {
      result += _traverse(child);
      return true;
    });
    // The stock guideline's own reading, node for node.
    if (node.isMergedIntoParent ||
        node.isInvisible ||
        node.flagsCollection.isHidden ||
        node.flagsCollection.isTextField) {
      return result;
    }
    final data = node.getSemanticsData();
    if (!data.hasAction(ui.SemanticsAction.longPress) &&
        !data.hasAction(ui.SemanticsAction.tap)) {
      return result;
    }
    if (data.label.isNotEmpty || data.tooltip.isNotEmpty) return result;
    if (data.value.isEmpty && _blankSlot(node)) return result;
    return result +
        Evaluation.fail(
          '$node: expected tappable node to have semantic label, '
          'but none was found.',
        );
  }

  bool _blankSlot(SemanticsNode node) {
    var physical = node.rect;
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      if (n.transform case final transform?) {
        physical = MatrixUtils.transformRect(transform, physical);
      }
    }
    final rect = Rect.fromLTRB(
      physical.left / _ratio,
      physical.top / _ratio,
      physical.right / _ratio,
      physical.bottom / _ratio,
    );
    final room = rect.inflate(0.5);
    bool inside(Rect area) {
      final grid = area.inflate(0.5);
      return grid.contains(rect.topLeft) && grid.contains(rect.bottomRight);
    }

    return _grids.any(inside) && !_days.any((day) => room.contains(day.center));
  }
}

/// WCAG's text contrast as the stock guideline checks it, completed for a
/// disabled control drawn inside a merged row: the stock check leaves out a
/// node whose own flags say disabled, but a row's disabled switch, chip or
/// picker merges into the row's node and leaves its flag on the merged data
/// only — the fasting card's rows at 38 % while no tradition is on, the
/// attendance card's count styles while counting is off. WCAG 1.4.3 does
/// not judge an inactive control.
///
/// With a [viewport], a text whose sampled box crosses the viewport's edge
/// is left out too: the stock check samples the box whole, so a field half
/// under a page's pinned bar was read as its own ground against the bar's
/// (the finding card's 1.09:1 at 360 light, G6). A text wholly inside the
/// viewport, or wholly outside it on the bar, is judged as before.
///
/// The ink is read from the text's own line boxes. The stock check pairs the
/// box's most frequent light and dark colours, and on a short word in a
/// light weight whose stems straddle two pixel columns an anti-aliasing step
/// outnumbers the full-strength pixels: the report stage's "2 events" in
/// `onSurfaceVariant` (8.6:1) was read at 2.10:1 off the step between it and
/// its ground. Here the ground is the most frequent colour of the box the
/// stock check samples; the ink is, among the colours that make up at least
/// [_inkShare] of what the text's line boxes draw besides that ground
/// (inline widgets left out), the one that stands furthest from it. Every
/// anti-aliasing step lies between the two, so where the glyphs reach full
/// strength the ink is the text's colour, and a dim text reads dim; a few
/// pixels of a neighbour's edge inside the line boxes stay under the share.
/// Not guarded: a strong span beside a dim one in a `Text.rich`, or a second
/// ground or a larger element under the line boxes, passes on its own
/// colour — the ratio is that of the strongest colour drawn in the share.
class GuideTextContrastGuideline extends MinimumTextContrastGuideline {
  const GuideTextContrastGuideline({this.viewport});

  /// The scrolling list's box, in logical pixels.
  final Rect? viewport;

  /// The stock check's slack on the target ratio.
  static const double _tolerance = -0.01;

  /// The share of a text's drawn pixels a colour must cover to be its ink:
  /// a 13 px label's full-strength pixels are about a quarter of them
  /// ("2 events": 31 of 121), each anti-aliasing step and a neighbour's
  /// fringe a few.
  static const double _inkShare = 0.05;

  @override
  Future<Evaluation> evaluate(WidgetTester tester) async {
    var result = const Evaluation.pass();
    for (final view in tester.binding.renderViews) {
      final layer = view.debugLayer! as OffsetLayer;
      final shot = await tester.binding.runAsync<_Shot>(() async {
        // Logical pixels, as the render boxes measure.
        final image = await layer.toImage(
          view.paintBounds,
          pixelRatio: 1 / view.flutterView.devicePixelRatio,
        );
        final bytes = await image.toByteData();
        final shot = (bytes: bytes!, width: image.width, height: image.height);
        image.dispose();
        return shot;
      });
      result += _evaluateNode(
        view.owner!.semanticsOwner!.rootSemanticsNode!,
        view,
        shot!,
      );
    }
    return result;
  }

  /// The stock check's walk: children first, then the node's own text.
  Evaluation _evaluateNode(SemanticsNode node, RenderView view, _Shot shot) {
    var result = const Evaluation.pass();
    if (node.isInvisible ||
        node.isMergedIntoParent ||
        node.flagsCollection.isHidden ||
        node.flagsCollection.isEnabled == ui.Tristate.isFalse) {
      return result;
    }
    node.visitChildren((child) {
      result += _evaluateNode(child, view, shot);
      return true;
    });
    final data = node.getSemanticsData();
    if (shouldSkipNode(data)) return result;
    final text = data.label.isEmpty ? data.value : data.label;
    for (final element in find.text(text).hitTestable().evaluate()) {
      result += _evaluateElement(node, element, view, shot);
    }
    return result;
  }

  Evaluation _evaluateElement(
    SemanticsNode node,
    Element element,
    RenderView view,
    _Shot shot,
  ) {
    const pass = Evaluation.pass();
    final box = element.renderObject;
    if (box is! RenderBox) {
      throw StateError('Unexpected renderObject type: $box');
    }
    final toGlobal = box.getTransformTo(null);
    final glyphs = MatrixUtils.transformRect(toGlobal, box.paintBounds);
    final surround = MatrixUtils.transformRect(
      toGlobal,
      box.paintBounds.inflate(4),
    );
    // A text found by its label stands for the node only where the two
    // overlap on screen, as the stock check reads it.
    final toScreen = Matrix4.identity();
    view.applyPaintTransform(view.child!, toScreen);
    toScreen.multiply(toGlobal);
    var nodeBounds = node.rect;
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      if (n.transform case final transform?) {
        nodeBounds = MatrixUtils.transformRect(transform, nodeBounds);
      }
    }
    final overlap = nodeBounds.intersect(
      MatrixUtils.transformRect(toScreen, box.paintBounds),
    );
    if (overlap.width <= 0 || overlap.height <= 0) return pass;

    final style = switch (element.widget) {
      Text(:final style) =>
        style == null || style.inherit
            ? DefaultTextStyle.of(element).style.merge(style)
            : style,
      EditableText(:final style) => style,
      final widget => throw StateError(
        'Unexpected widget type: ${widget.runtimeType}',
      ),
    };
    if (isNodeOffScreen(surround, view.flutterView)) return pass;

    final around = _colorsIn(shot, [surround]);
    if (around.isEmpty) return pass;
    final ground = around.entries
        .reduce((a, b) => b.value > a.value ? b : a)
        .key;
    final (:lines, :widgets) =
        _textBoxesOf(box) ?? (lines: [glyphs], widgets: const <Rect>[]);
    // A text drawn only in its ground's colour reads 1:1.
    final drawn = _colorsIn(shot, lines, outside: widgets)..remove(ground);
    final drawnCount = drawn.values.fold(0, (sum, n) => sum + n);
    final groundLuminance = ground.computeLuminance();
    double contrastWith(Color color) {
      final luminance = color.computeLuminance();
      final (light, dark) = luminance > groundLuminance
          ? (luminance, groundLuminance)
          : (groundLuminance, luminance);
      return (light + 0.05) / (dark + 0.05);
    }

    final ink = [
      ground,
      for (final MapEntry(key: color, value: n) in drawn.entries)
        if (n >= drawnCount * _inkShare) color,
    ].reduce((a, b) => contrastWith(b) > contrastWith(a) ? b : a);
    final ratio = contrastWith(ink);
    final target = targetContrastRatio(
      style.fontSize,
      bold: style.fontWeight == FontWeight.bold,
    );
    if (ratio - target >= _tolerance) return pass;
    return Evaluation.fail(
      '$node:\n'
      'Expected contrast ratio of at least $target but found '
      '${ratio.toStringAsFixed(2)} for a font size of ${style.fontSize}.\n'
      'The computed colors was:\n'
      'ground - $ground, ink - $ink',
    );
  }

  /// The text's line boxes on screen — its runs, not its render box, which
  /// a parent may stretch past the text — and the boxes its `WidgetSpan`s
  /// draw in, where a glyph is an icon's; null when [root] holds no text.
  static ({List<Rect> lines, List<Rect> widgets})? _textBoxesOf(
    RenderObject root,
  ) {
    RenderBox? text;
    void visit(RenderObject object) {
      if (text != null) return;
      if (object is RenderParagraph || object is RenderEditable) {
        text = object as RenderBox;
      } else {
        object.visitChildren(visit);
      }
    }

    visit(root);
    final List<TextBox> boxes;
    final widgets = <Rect>[];
    switch (text) {
      case final RenderParagraph paragraph:
        boxes = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: paragraph.text.toPlainText().length,
          ),
        );
        paragraph.visitChildren((child) {
          if (child is RenderBox && child.hasSize) {
            widgets.add(
              MatrixUtils.transformRect(
                child.getTransformTo(null),
                Offset.zero & child.size,
              ),
            );
          }
        });
      case final RenderEditable editable:
        boxes = editable.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: editable.plainText.length),
        );
      default:
        return null;
    }
    final toGlobal = text!.getTransformTo(null);
    return (
      lines: [
        for (final box in boxes)
          MatrixUtils.transformRect(toGlobal, box.toRect()),
      ],
      widgets: widgets,
    );
  }

  /// How often each colour is drawn inside one of [inside], the pixels whose
  /// centre lies in one of [outside] left out.
  static Map<Color, int> _colorsIn(
    _Shot shot,
    List<Rect> inside, {
    List<Rect> outside = const [],
  }) {
    if (inside.isEmpty) return const {};
    final bounds = inside
        .reduce((a, b) => a.expandToInclude(b))
        .intersect(
          Rect.fromLTWH(0, 0, shot.width.toDouble(), shot.height.toDouble()),
        );
    final counts = <int, int>{};
    for (var x = bounds.left.floor(); x < bounds.right.ceil(); x++) {
      for (var y = bounds.top.floor(); y < bounds.bottom.ceil(); y++) {
        final centre = Offset(x + 0.5, y + 0.5);
        if (!inside.any((box) => box.contains(centre)) ||
            outside.any((box) => box.contains(centre))) {
          continue;
        }
        final rgba = shot.bytes.getUint32((y * shot.width + x) * 4);
        counts.update(rgba, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return {
      for (final MapEntry(key: rgba, value: n) in counts.entries)
        Color.fromARGB(
          rgba & 0xFF,
          rgba >> 24 & 0xFF,
          rgba >> 16 & 0xFF,
          rgba >> 8 & 0xFF,
        ): n,
    };
  }

  @override
  bool shouldSkipNode(SemanticsData data) =>
      super.shouldSkipNode(data) ||
      data.flagsCollection.isEnabled == ui.Tristate.isFalse;

  @override
  bool isNodeOffScreen(Rect paintBounds, ui.FlutterView window) {
    if (super.isNodeOffScreen(paintBounds, window)) return true;
    final viewport = this.viewport;
    if (viewport == null || !paintBounds.overlaps(viewport)) return false;
    final room = viewport.inflate(0.5);
    return !room.contains(paintBounds.topLeft) ||
        !room.contains(paintBounds.bottomRight);
  }

  @override
  String get description =>
      '${super.description}, a disabled control inside a merged row '
      '${viewport == null ? '' : 'and a text across the viewport\'s edge '}'
      'aside';
}

/// A screenshot's RGBA bytes, row-first, in logical pixels.
typedef _Shot = ({ByteData bytes, int width, int height});
