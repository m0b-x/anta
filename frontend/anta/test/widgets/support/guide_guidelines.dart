import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:anta/widgets/calendar_bottom_panel.dart';

/// Android's 48 dp tap-target guideline with the calendar guide's two
/// accepted exceptions taken out by name rather than the check skipped:
///
/// * a day cell of a grid inside [GuideTapTargetGuideline.of]'s `gridsOf` —
///   a "Try it" card's stage is 40 dp narrower than the screen, so at 360
///   its cells are about 45 dp wide where the real grid's are 51.4; a node
///   there is let off only when its width alone falls short;
/// * `PanelModeBar`'s 32 dp segments — the real calendar's own chrome, drawn
///   here as it is there (record §6 c).
///
/// Every other node is judged as the stock guideline judges it.
class GuideTapTargetGuideline extends MinimumTapTargetGuideline {
  GuideTapTargetGuideline._(this._ratio, this._grids, this._segments)
    : super(size: _android.size, link: _android.link);

  static final MinimumTapTargetGuideline _android =
      androidTapTargetGuideline as MinimumTapTargetGuideline;

  /// The exceptions where they stand now.
  factory GuideTapTargetGuideline.of(
    WidgetTester tester, {
    Finder? gridsOf,
  }) {
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
    );
  }

  final double _ratio;

  /// Logical pixels, as the widgets measure.
  final List<Rect> _grids;
  final List<Rect> _segments;

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

    final narrowCell =
        rect.width < size.width && rect.height >= size.height;
    return _segments.any(inside) || (narrowCell && _grids.any(inside));
  }

  @override
  String get description =>
      '${super.description}, the guide\'s two named exceptions aside';
}

/// WCAG's text contrast as the stock guideline checks it, completed for a
/// disabled control drawn inside a merged row: the stock check leaves out a
/// node whose own flags say disabled, but a row's disabled switch, chip or
/// picker merges into the row's node and leaves its flag on the merged data
/// only — the fasting card's rows at 38 % while no tradition is on, the
/// attendance card's count styles while counting is off. WCAG 1.4.3 does
/// not judge an inactive control.
class GuideTextContrastGuideline extends MinimumTextContrastGuideline {
  const GuideTextContrastGuideline();

  @override
  bool shouldSkipNode(SemanticsData data) =>
      super.shouldSkipNode(data) ||
      data.flagsCollection.isEnabled == ui.Tristate.isFalse;

  @override
  String get description =>
      '${super.description}, a disabled control inside a merged row aside';
}
