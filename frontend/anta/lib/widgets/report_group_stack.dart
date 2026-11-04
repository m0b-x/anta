import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        RenderAbstractViewport,
        RenderSliver,
        RenderSliverMultiBoxAdaptor,
        SliverGeometry;

import '../constants/analytics_metrics.dart';
import '../constants/report_metrics.dart';
import '../constants/semantics_ids.dart';
import '../models/calendar_event.dart';
import '../models/calendar_report.dart';
import '../utils/report_labels.dart';
import 'form_rows.dart';
import 'report_category_group.dart';

/// Whether a report group's rows are shown and whether it shows every row
/// rather than its preview, by card and category — absent is open, absent
/// is the preview. Per visit, kept across steps and refolds (X): the
/// surface that owns the scroll owns one, and hands it to each card's
/// [ReportGroupStack].
class ReportGroupFolds {
  final Map<(ReportCard, String), bool> _open = {};
  final Set<(ReportCard, String)> _expanded = {};

  /// A By tag group is closed until opened (S5 O): eight open tags would
  /// push every card below them a screen down.
  bool isOpen(ReportCard card, String categoryId) =>
      _open[(card, categoryId)] ?? card != ReportCard.tags;

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

  bool _dueSoonExpanded = false;

  /// Whether the Due soon card shows every row rather than its first
  /// `AnalyticsMetrics.dueSoonRows`. Kept for the visit like the groups'
  /// folds: a refold rebuilds the card, and must not collapse what the
  /// owner opened.
  bool get isDueSoonExpanded => _dueSoonExpanded;

  /// Written by the card's disclosure row alone, so a new report never
  /// resets it within the visit.
  void setDueSoonExpanded(bool expanded) => _dueSoonExpanded = expanded;

  bool _tagsExpanded = false;

  /// Whether the By tag card shows every tag rather than its
  /// [ReportGroupStack.preview], kept for the visit as [isDueSoonExpanded]
  /// is.
  bool get isTagsExpanded => _tagsExpanded;

  /// Written by the card's own disclosure row and by a reveal past the
  /// preview.
  void setTagsExpanded(bool expanded) => _tagsExpanded = expanded;
}

/// [card]'s [groups], each a `SliverList` of its own in the surface's one
/// scroll (X) — the report page's cards and the "n more categories" sheet
/// draw their groups through it, so a fold behaves the same in both. The
/// By tag card's tags fold through the same machinery, as groups
/// [tagGroups] adapts them into.
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
    this.onDatedTap,
    this.onRoutineTap,
    this.onPresence,
    this.onShowAsList,
    required this.today,
    required this.spansMonths,
    required this.use24Hour,
    this.trailingGap = false,
    this.onShrink,
    this.measures = const {},
    this.tags = const {},
    this.preview,
  });

  /// [tags] as the groups a By tag stack folds — the first
  /// [AnalyticsMetrics.tagRows] in the model's order, each under its key,
  /// counting its kept days — handed to the stack as [groups] beside the
  /// tags by key.
  static List<ReportCategoryGroup> tagGroups(Iterable<ReportTag> tags) => [
    for (final tag in tags.take(AnalyticsMetrics.tagRows))
      ReportCategoryGroup(
        categoryId: tag.key,
        count: tag.count,
        minutes: tag.minutes,
        missed: 0,
        rows: tag.rows,
      ),
  ];

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

  /// The count a Categories or By tag meter is a share of; null reads the
  /// largest of [groups] — past a [preview] too, so expanding the card never
  /// rescales the meters above. The "n more categories" sheet passes the
  /// page's, so its meters compare with the card's rather than restart at
  /// full.
  final int? largest;

  /// A row's tap; null leaves the rows inert, as the guide's stage draws
  /// them.
  final void Function(ReportDatedRow row)? onDatedTap;
  final void Function(ReportRoutineRow row)? onRoutineTap;

  /// The Missed card's presence button; null everywhere else.
  final void Function(ReportDatedRow row, bool missed)? onPresence;

  /// A capped group's "Show as list", handed the group it closes; null
  /// draws it disabled.
  final void Function(ReportCategoryGroup group)? onShowAsList;

  final DateTime today;
  final bool spansMonths;
  final bool use24Hour;

  /// The air below the last group; the groups before it always carry it.
  final bool trailingGap;

  /// Called before a frame that may shrink the content under the finger;
  /// null for a surface with no slack to arm.
  final VoidCallback? onShrink;

  /// [CalendarReport.measures] by category, which a profiled Categories
  /// header leads with (N); the other cards never read it, and empty keeps
  /// every header's count facts.
  final Map<String, ReportMeasures> measures;

  /// The By tag card's tags by [ReportTag.key], the [groups] [tagGroups]
  /// made of them stand for; empty on every other card.
  final Map<String, ReportTag> tags;

  /// How many groups show before the card's own "n more", which expands
  /// the rest in place and folds them back (O); null shows every group. The
  /// By tag card's: the expansion is [ReportGroupFolds.isTagsExpanded].
  final int? preview;

  @override
  State<ReportGroupStack> createState() => ReportGroupStackState();
}

/// The stack's state, public so the body can reach [reveal] through a
/// `GlobalKey`: a goal's or an insight's tap opens a group and scrolls to
/// it, and only the stack holds the group's list.
class ReportGroupStackState extends State<ReportGroupStack> {
  /// Each group's `SliverList`, by category: it keeps the list's rows with
  /// the group when a refold reorders the groups, and "Show less" measures
  /// the built rows through it.
  final Map<String, GlobalKey> _lists = {};

  /// The By tag headers' measured captions, kept across folds and refolds.
  final ReportTagCaptions _tagCaptions = ReportTagCaptions();

  @override
  void didUpdateWidget(ReportGroupStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tags, widget.tags)) {
      _tagCaptions.retain(widget.tags);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final groups = widget.groups;
    final folds = widget.folds;
    final onShowAsList = widget.onShowAsList;
    final largest = switch (card) {
      ReportCard.missed || ReportCard.ahead => 0,
      ReportCard.categories || ReportCard.tags =>
        widget.largest ??
            groups.fold<int>(0, (top, group) => math.max(top, group.count)),
    };
    final preview = widget.preview;
    final previews = preview != null && groups.length > preview;
    final expanded = previews && folds.isTagsExpanded;
    final shown = previews && !expanded ? groups.sublist(0, preview) : groups;
    return SliverMainAxisGroup(
      slivers: [
        for (final (index, group) in shown.indexed)
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
              onShowAsList: onShowAsList == null
                  ? null
                  : () => onShowAsList(group),
              today: widget.today,
              spansMonths: widget.spansMonths,
              use24Hour: widget.use24Hour,
              // The card's "n more" is a card of its own, after the gap.
              trailingGap:
                  widget.trailingGap || previews || index < shown.length - 1,
              measures: card == ReportCard.categories
                  ? widget.measures[group.categoryId]
                  : null,
              tag: widget.tags[group.categoryId],
              tagCaptions: _tagCaptions,
            ),
          ),
        if (previews)
          SliverToBoxAdapter(
            child: FormRowShell(
              first: true,
              last: true,
              trailingGap: widget.trailingGap,
              child: _moreGroups(groups.length - preview, expanded),
            ),
          ),
      ],
    );
  }

  /// The card's "n more ▾" under its preview, "Show less ▴" under every
  /// group — one id both ways, the look of the Categories card's "n more
  /// categories" row, spoken "4 more tags" and "Show fewer tags".
  Widget _moreGroups(int hidden, bool expanded) {
    final l10n = widget.labels.l10n;
    if (expanded) {
      return FormActionRow.disclosure(
        glyph: Icons.expand_less_rounded,
        label: l10n.reportGroupLess,
        onTap: _toggleCard,
        expanded: true,
        semanticsLabel: l10n.reportTagsLessSpoken,
        identifier: SemanticsIds.reportTagsMore,
      );
    }
    return FormActionRow.disclosure(
      glyph: Icons.expand_more_rounded,
      label: l10n.reportGroupMore(hidden),
      onTap: _toggleCard,
      expanded: false,
      semanticsLabel: l10n.reportTagsMoreSpoken(hidden),
      identifier: SemanticsIds.reportTagsMore,
    );
  }

  /// The card's "n more" and "Show less". Folding back scrolls up by the
  /// lists that leave, gaps included, so "n more" lands where the finger
  /// was (S); a list above the viewport is read at its laid-out extent,
  /// which for an open group's unbuilt rows is the list's own estimate.
  void _toggleCard() {
    final folds = widget.folds;
    if (!folds.isTagsExpanded) {
      setState(() => folds.setTagsExpanded(true));
      return;
    }
    final leaving = widget.groups.skip(widget.preview ?? widget.groups.length);
    foldBackInPlace(
      widget.scroll,
      onShrink: widget.onShrink,
      extent: () {
        var extent = 0.0;
        for (final group in leaving) {
          final list = _lists[group.categoryId]?.currentContext
              ?.findRenderObject();
          final geometry = list is RenderSliver ? list.geometry : null;
          if (geometry == null) return null;
          extent += geometry.scrollExtent;
        }
        return extent;
      },
    );
    setState(() => folds.setTagsExpanded(false));
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
    if (open) widget.onShrink?.call();
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
    foldBackInPlace(
      widget.scroll,
      onShrink: widget.onShrink,
      extent: () {
        final sliver = _lists[group.categoryId]?.currentContext
            ?.findRenderObject();
        if (sliver is! RenderSliverMultiBoxAdaptor) return null;
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
        if (rowHeight == null || (capped && listHeight == null)) return null;
        return (shown - ReportMetrics.groupPreviewRows) * rowHeight +
            (listHeight ?? 0);
      },
    );
  }

  /// Opens [categoryId]'s group — a tag's key on the By tag card, which
  /// expands past its [ReportGroupStack.preview] to reach it — and lands
  /// its header at the viewport's top (G): a goal's or an insight's tap
  /// reads the group it names. A group this stack does not draw moves
  /// nothing.
  void reveal(String categoryId) {
    final groups = widget.groups;
    final index = groups.indexWhere((group) => group.categoryId == categoryId);
    if (index < 0) return;
    final card = widget.card;
    final folds = widget.folds;
    final hidden =
        index >= (widget.preview ?? groups.length) && !folds.isTagsExpanded;
    if (!folds.isOpen(card, categoryId) || hidden) {
      setState(() {
        folds.setOpen(card, categoryId, true);
        if (hidden) folds.setTagsExpanded(true);
      });
    }
    revealAtTop(
      widget.scroll,
      () => _lists[categoryId]?.currentContext?.findRenderObject(),
    );
  }
}

/// Before a "Show less" folds rows away above its disclosure row, scrolls
/// back by the [extent] about to go, so "n more" lands where the finger was
/// (S) — a report group's and the Due soon card's alike, so the two never
/// drift. The list or card would hold its first row in place instead —
/// right for an edit far above, the opposite of what a reader folding a
/// long run wants: the rows below would jump up past the finger. Called
/// before the fold's `setState`, so the folded frame is laid out at the new
/// offset — one frame, never a post-frame jump; the offset clamps at 0.
/// [onShrink] is called first, for a fold at the scroll's end; a null
/// [extent] — nothing built to measure — moves nothing.
void foldBackInPlace(
  ScrollController? scroll, {
  required double? Function() extent,
  VoidCallback? onShrink,
}) {
  onShrink?.call();
  if (scroll == null || !scroll.hasClients) return;
  final leaving = extent();
  if (leaving == null) return;
  scroll.jumpTo(math.max(0, scroll.offset - leaving));
}

/// Scrolls [scroll] so [target] — a group's list, a card's label — starts
/// at the viewport's top edge, clamped to the scroll's range: where a goal
/// or an insight takes the reader. It runs after the frame that lays the
/// target out, since the tap may have just opened it; and once more after
/// its own jump, because a list above the old viewport, or the target
/// itself, may have been laid out at an estimated extent the jump then
/// builds for real.
void revealAtTop(ScrollController scroll, RenderObject? Function() target) {
  void jump({required bool again}) {
    final object = target();
    if (object == null || !object.attached || !scroll.hasClients) return;
    final viewport = RenderAbstractViewport.maybeOf(object);
    if (viewport == null) return;
    final position = scroll.position;
    final offset = viewport
        .getOffsetToReveal(object, 0)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((offset - position.pixels).abs() < precisionErrorTolerance) return;
    position.jumpTo(offset);
    if (again) {
      WidgetsBinding.instance.addPostFrameCallback((_) => jump(again: false));
    }
  }

  WidgetsBinding.instance
    ..addPostFrameCallback((_) => jump(again: true))
    // A tap on a group already open changes nothing, so no frame would
    // come to run the jump.
    ..ensureVisualUpdate();
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
