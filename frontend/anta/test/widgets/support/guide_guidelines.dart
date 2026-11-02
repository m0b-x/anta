import 'dart:async';
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
class GuideTextContrastGuideline extends MinimumTextContrastGuideline {
  const GuideTextContrastGuideline({this.viewport});

  /// The scrolling list's box, in logical pixels.
  final Rect? viewport;

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
