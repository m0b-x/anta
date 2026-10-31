import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderSliver, RenderSliverMultiBoxAdaptor, SliverGeometry;

import '../constants/report_metrics.dart';
import '../models/calendar_event.dart';
import '../models/calendar_report.dart';
import '../utils/report_labels.dart';
import 'report_category_group.dart';

/// Whether a report group's rows are shown and whether it shows every row
/// rather than its preview, by card and category — absent is open, absent
/// is the preview. Per visit, kept across steps and refolds (X): the
/// surface that owns the scroll owns one, and hands it to each card's
/// [ReportGroupStack].
class ReportGroupFolds {
  final Map<(ReportCard, String), bool> _open = {};
  final Set<(ReportCard, String)> _expanded = {};

  bool isOpen(ReportCard card, String categoryId) =>
      _open[(card, categoryId)] ?? true;

  bool isExpanded(ReportCard card, String categoryId) =>
      _expanded.contains((card, categoryId));

  void setOpen(ReportCard card, String categoryId, bool open) =>
      _open[(card, categoryId)] = open;

  void setExpanded(ReportCard card, String categoryId, bool expanded) {
    if (expanded) {
      _expanded.add((card, categoryId));
    } else {
      _expanded.remove((card, categoryId));
    }
  }
}

/// [card]'s [groups], each a `SliverList` of its own in the surface's one
/// scroll (X) — the report page's cards and the "n more categories" sheet
/// draw their groups through it, so a fold behaves the same in both.
///
/// After a fold a list re-anchors its built rows by index, so one list over
/// a whole card left a later group's rows at the offsets of the rows folded
/// away, and "n more" landed off the finger above another long open group;
/// a group's own list re-lays from its header instead.
///
/// A header tap and "Show less" call [onShrink] before the frame that folds
/// them: the surface arms its [EndSlackSliver] there, for a group folded at
/// the scroll's end.
class ReportGroupStack extends StatefulWidget {
  const ReportGroupStack({
    super.key,
    required this.scroll,
    required this.folds,
    required this.card,
    required this.groups,
    required this.events,
    required this.labels,
    this.largest,
    required this.onDatedTap,
    required this.onRoutineTap,
    this.onPresence,
    required this.onShowAsList,
    required this.today,
    required this.spansMonths,
    required this.use24Hour,
    this.trailingGap = false,
    required this.onShrink,
  });

  /// The surface's one scroll, which "Show less" moves so "n more" stays
  /// under the finger (S).
  final ScrollController scroll;

  /// The surface's fold state; read and written here, kept there.
  final ReportGroupFolds folds;

  final ReportCard card;
  final List<ReportCategoryGroup> groups;

  /// [CalendarReport.events], which every row's words are read from.
  final Map<String, CalendarEvent> events;
  final ReportLabels labels;

  /// The count a Categories meter is a share of; null reads the largest of
  /// [groups]. The "n more categories" sheet passes the page's, so its
  /// meters compare with the card's rather than restart at full.
  final int? largest;

  final void Function(ReportDatedRow row) onDatedTap;
  final void Function(ReportRoutineRow row) onRoutineTap;

  /// The Missed card's presence button; null everywhere else.
  final void Function(ReportDatedRow row, bool missed)? onPresence;

  /// A capped group's "Show as list", handed the group it closes.
  final void Function(ReportCategoryGroup group) onShowAsList;

  final DateTime today;
  final bool spansMonths;
  final bool use24Hour;

  /// The air below the last group; the groups before it always carry it.
  final bool trailingGap;

  /// Called before a frame that may shrink the content under the finger.
  final VoidCallback onShrink;

  @override
  State<ReportGroupStack> createState() => _ReportGroupStackState();
}

class _ReportGroupStackState extends State<ReportGroupStack> {
  /// Each group's `SliverList`, by category: it keeps the list's rows with
  /// the group when a refold reorders the groups, and "Show less" measures
  /// the built rows through it.
  final Map<String, GlobalKey> _lists = {};

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final groups = widget.groups;
    final folds = widget.folds;
    final largest = card != ReportCard.categories
        ? 0
        : widget.largest ??
              groups.fold<int>(0, (top, group) => math.max(top, group.count));
    return SliverMainAxisGroup(
      slivers: [
        for (final (index, group) in groups.indexed)
          _groupList(
            ReportGroupRows(
              card: card,
              group: group,
              events: widget.events,
              labels: widget.labels,
              fraction: largest > 0 ? group.count / largest : 0,
              open: folds.isOpen(card, group.categoryId),
              expanded: folds.isExpanded(card, group.categoryId),
              onToggle: () => _toggle(group),
              onMore: () => _toggleMore(group),
              onDatedTap: widget.onDatedTap,
              onRoutineTap: widget.onRoutineTap,
              onPresence: widget.onPresence,
              onShowAsList: () => widget.onShowAsList(group),
              today: widget.today,
              spansMonths: widget.spansMonths,
              use24Hour: widget.use24Hour,
              trailingGap: widget.trailingGap || index < groups.length - 1,
            ),
          ),
      ],
    );
  }

  /// [rows] as their group's `SliverList`, under the group's own key.
  /// `findChildIndexCallback` follows a built row by its key across a fold
  /// (D38): "n more" turning into "Show less" keeps its element only when
  /// its old index was built; otherwise the list re-creates its rows from
  /// index 0 — the positions still hold, the elements are new. The key map
  /// is built on the callback's first call, so a build that folds nothing
  /// in a group pays nothing for it.
  Widget _groupList(ReportGroupRows rows) {
    Map<Key, int>? indexOf;
    return SliverList(
      key: _lists.putIfAbsent(rows.group.categoryId, GlobalKey.new),
      delegate: SliverChildBuilderDelegate(
        rows.build,
        childCount: rows.rowCount,
        findChildIndexCallback: (key) => (indexOf ??= {
          for (var i = 0; i < rows.rowCount; i++) rows.keyOf(i): i,
        })[key],
      ),
    );
  }

  void _toggle(ReportCategoryGroup group) {
    final card = widget.card;
    final open = widget.folds.isOpen(card, group.categoryId);
    // A long group closed near the scroll's end would let the viewport clamp
    // its offset, and the header would slide down under the finger.
    if (open) widget.onShrink();
    setState(() => widget.folds.setOpen(card, group.categoryId, !open));
  }

  void _toggleMore(ReportCategoryGroup group) {
    final card = widget.card;
    if (!widget.folds.isExpanded(card, group.categoryId)) {
      setState(() => widget.folds.setExpanded(card, group.categoryId, true));
      return;
    }
    _keepMoreInPlace(group);
    setState(() => widget.folds.setExpanded(card, group.categoryId, false));
  }

  /// Before "Show less" folds [group], scrolls back by the extent of the
  /// rows about to go, so "n more" lands where the finger was (S). The list
  /// would hold its first built row in place instead — right for an edit
  /// far above, the opposite of what a reader folding a long group wants:
  /// the rows below would jump up past the finger. The jump comes before
  /// the fold's `setState`, so the folded frame is laid out at the new
  /// offset — one frame, never a post-frame jump. The rows above the
  /// viewport are not built, so their height is read from a built sibling
  /// of the same kind (dated and routine rows share one height); with none
  /// built, nothing moves. The fold also calls [ReportGroupStack.onShrink],
  /// for a group folded at the scroll's end.
  void _keepMoreInPlace(ReportCategoryGroup group) {
    widget.onShrink();
    final scroll = widget.scroll;
    final sliver = _lists[group.categoryId]?.currentContext?.findRenderObject();
    if (sliver is! RenderSliverMultiBoxAdaptor || !scroll.hasClients) return;
    final length = group.rows.length;
    final capped = length > ReportMetrics.maxListRows;
    final shown = math.min(length, ReportMetrics.maxListRows);
    double? rowHeight;
    double? listHeight;
    for (
      var child = sliver.firstChild;
      child != null;
      child = sliver.childAfter(child)
    ) {
      // The header is 0, the rows 1 to [shown], then "Show as list".
      final index = sliver.indexOf(child);
      if (index >= 1 && index <= shown) {
        rowHeight ??= child.size.height;
      } else if (capped && index == shown + 1) {
        listHeight = child.size.height;
      }
    }
    if (rowHeight == null || (capped && listHeight == null)) return;
    final extent =
        (shown - ReportMetrics.groupPreviewRows) * rowHeight +
        (listHeight ?? 0);
    scroll.jumpTo(math.max(0, scroll.offset - extent));
  }
}

/// Blank room after the body's end, so a content that shrinks under the
/// finger at the end of the scroll never slides down (D39, D40, D42).
///
/// Counts, not flags, so a build hands them over and mutates nothing: a
/// count that moved since the last build acts once, on the frame that
/// build lays out.
class EndSlackSliver extends LeafRenderObjectWidget {
  const EndSlackSliver({
    super.key,
    required this.arms,
    this.releases = 0,
    required this.clearance,
  });

  /// How many times the surface has armed the slack — before a frame that
  /// may shrink the content under the finger.
  final int arms;

  /// How many times the surface has released it — when the report drawn
  /// is another look's, whose footer must not sit above blank ground. A
  /// release wins over an arm handed over in the same update.
  final int releases;

  /// The bottom clearance the padding before the slack carries — the larger
  /// of the keyboard and the system inset. Its shrink lies below the
  /// viewport by construction, so the slack takes exactly that shrink back.
  final double clearance;

  @override
  RenderEndSlackSliver createRenderObject(BuildContext context) =>
      RenderEndSlackSliver(
        arms: arms,
        releases: releases,
        clearance: clearance,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderEndSlackSliver renderObject,
  ) {
    renderObject
      ..clearance = clearance
      ..arms = arms
      ..releases = releases;
  }
}

/// When the content shrinks while the offset sits near its end — a Missed
/// row marked away, the whole Missed card leaving, a long group closed by
/// its header — the viewport clamps the offset to the smaller
/// `maxScrollExtent`, and everything on screen slides down under the finger.
///
/// Armed by the surface before a frame that may shrink the content, the next
/// layout remembers `scrollOffset + remainingPaintExtent`. With the slack's
/// start above the leading edge, that is the whole viewport plus how far
/// past the start the offset is; with the start below it, the scroll offset
/// is 0 and that is the gap left under the content. Either way it is
/// `pixels + viewport − preceding`: exactly the room that keeps
/// `maxScrollExtent` at `pixels`, the deficit the clamp would take, and 0
/// while the content still fills the viewport. Every other layout keeps the
/// smaller of what it remembers and that same reach, so the room only ever
/// shrinks: scrolling back up drains it, scrolling down is bounded by it.
/// A release drops the room at once, and an arm in the same update with it.
///
/// It sits after the body's padding, so `preceding` counts the bottom
/// clearance too and the room is exact — and a raised keyboard drains the
/// room by its height. A lowered one is credited back by exactly the
/// clearance's shrink since the last layout, capped at the reach: never
/// re-measured, because the layout that sees the clearance shrink may also
/// see content above the viewport gone — a report offstage under another
/// route hears a keyboard and a deletion together, an editor saved while
/// the keyboard is still closing — and a re-measured reach would keep that
/// extent too, lifting every visible row by it. Offstage nothing is laid
/// out, so a keyboard raised and lowered there credits nothing; during a
/// closing animation each frame credits only its own shrink. It paints
/// nothing and has no children.
class RenderEndSlackSliver extends RenderSliver {
  RenderEndSlackSliver({
    required int arms,
    required int releases,
    required double clearance,
  }) : _arms = arms,
       _releases = releases,
       _clearance = clearance;

  double _remembered = 0;
  bool _armed = false;

  /// The clearance the last layout ran with; null before the first and
  /// after a release, so neither credits a shrink.
  double? _laidClearance;

  double _clearance;

  /// A new clearance makes the next layout credit its shrink.
  set clearance(double value) {
    if (value == _clearance) return;
    _clearance = value;
    markNeedsLayout();
  }

  int _arms;

  /// A new count makes the next layout remember the room that holds the
  /// offset.
  set arms(int value) {
    if (value == _arms) return;
    _arms = value;
    _armed = true;
    markNeedsLayout();
  }

  int _releases;

  /// A new count drops the room remembered, an arm still waiting and the
  /// clearance's credit: a shorter look's footer never sits above blank
  /// ground.
  set releases(int value) {
    if (value == _releases) return;
    _releases = value;
    _remembered = 0;
    _armed = false;
    _laidClearance = null;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final reach = constraints.scrollOffset + constraints.remainingPaintExtent;
    final laid = _laidClearance;
    _laidClearance = _clearance;
    if (_armed) {
      _armed = false;
      _remembered = reach;
    } else if (laid != null) {
      _remembered = math.min(
        _remembered + math.max(0.0, laid - _clearance),
        reach,
      );
    }
    final extent = _remembered = math.min(_remembered, reach);
    final paintExtent = calculatePaintOffset(constraints, from: 0, to: extent);
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintExtent: paintExtent,
      layoutExtent: paintExtent,
      maxPaintExtent: extent,
    );
  }
}
