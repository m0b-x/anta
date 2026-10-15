import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../constants/form_metrics.dart';
import '../constants/overview_list_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/agenda_day_list.dart' show AgendaYearBounds;
import '../models/calendar_appearance.dart';
import 'agenda_day_list_rows.dart';
import 'agenda_year_grid.dart';
import 'list_scrubber.dart';
import 'year_month_tile.dart';

/// Where the overview's year scroll is and where it goes, in years: the
/// page's chevrons, its Today slot and its Period menu land through it, and
/// it tells the page which year is at the top as the scroll moves, so the
/// nav's title follows the finger.
///
/// It outlives the scroll itself — a switch to the list and back mounts a
/// new one — and holds the year to open on meanwhile: a year asked for while
/// nothing is laid out is remembered and becomes the first frame's offset.
class AgendaYearScrollController {
  AgendaYearScrollController({
    required int initialYear,
    this.onTopYearChanged,
    this.onLanded,
  }) : _topYear = initialYear,
       _reportedYear = initialYear,
       _firstYear = initialYear,
       _lastYear = initialYear;

  /// Called once per change of [topYear] — never per pixel — and in the same
  /// turn as a jump, so the title never lags a landing.
  final ValueChanged<int>? onTopYearChanged;

  /// Called when an animated landing ends — on its target, or cut short by a
  /// finger or a jump — so the owner resolves where the scroll stopped: the
  /// years it passed on the way were reported but are not worth resolving
  /// ([isLanding]).
  final VoidCallback? onLanded;

  /// Bumped by every [animateToYear]; only the newest one's end clears
  /// [isLanding].
  int _landings = 0;
  bool _landing = false;
  int? _landingYear;

  /// Set by [dispose]: the owner is gone, so nothing is reported to it.
  bool _disposed = false;

  int _topYear;
  int _reportedYear;
  int _firstYear;
  int _lastYear;
  double? _headerHeight;
  double? _extent;
  _AgendaYearScrollState? _attached;

  /// The span the scroll last laid out; the year asked for until then. The
  /// owner's span may have moved since — it reaches the controller with the
  /// next layout — so it clamps its own targets to its own span.
  int get firstYear => _firstYear;
  int get lastYear => _lastYear;

  /// A section's header height and a section's whole height, null until the
  /// first layout fixed them.
  double? get headerHeight => _headerHeight;
  double? get extent => _extent;

  /// The year whose section holds the top of the scroll (see
  /// [yearAtOffset]).
  int get topYear => _topYear;

  /// Whether a scroll is laid out under this controller.
  bool get isAttached => _attached?._position != null;

  /// Whether an [animateToYear] is under way. The years it brings to the top
  /// are only on its way, so the owner resolves none of them until
  /// [onLanded].
  bool get isLanding => _landing;

  /// The year the [animateToYear] under way lands on, null between landings.
  /// A rebuild of the owner mid-landing resolves this year, not the one
  /// passing the top, and a screen reader's step goes on from it.
  int? get landingYear => _landing ? _landingYear : null;

  /// The years whose sections show any part in the viewport, null while
  /// nothing is laid out — what the page resolves first.
  AgendaYearBounds? get visibleYears {
    final position = _attached?._position;
    final extent = _extent;
    if (position == null ||
        extent == null ||
        !position.hasPixels ||
        !position.hasViewportDimension) {
      return null;
    }
    final top = position.pixels;
    final bottom = top + position.viewportDimension;
    final first = _firstYear + (top / extent).floor();
    // A section that ends exactly at the bottom edge shows nothing below it.
    final last =
        _firstYear + ((bottom - precisionErrorTolerance) / extent).floor();
    return (
      first: first.clamp(_firstYear, _lastYear),
      last: last.clamp(_firstYear, _lastYear),
    );
  }

  /// The offset that puts [year]'s header at the top of the scroll — once the
  /// first layout fixed a section's height; before it there is no offset to
  /// give, and a caller that wants the scroll to open on a year asks
  /// [jumpToYear], which remembers it.
  double offsetOfYear(int year) {
    final extent = _extent;
    assert(
      extent != null,
      'AgendaYearScrollController.offsetOfYear before the first layout: '
      'jumpToYear remembers a year until then',
    );
    return (year - _firstYear) * (extent ?? 0);
  }

  /// The year at the top of a scroll at [offset]: the next year takes over
  /// once its header is within half a header of the top edge — by then the
  /// year above shows little more than its gap, and the header reads as the
  /// heading of what is shown.
  int yearAtOffset(double offset) {
    final extent = _extent;
    if (extent == null) return _topYear;
    final year = _firstYear + ((offset + _headerHeight! / 2) / extent).floor();
    return year.clamp(_firstYear, _lastYear);
  }

  /// Puts [year]'s header at the top at once, or opens there once laid out.
  /// Only a jump on a laid-out scroll is reported: a year remembered for
  /// later is the caller's own.
  void jumpToYear(int year) {
    final position = _attached?._position;
    if (position == null || _extent == null) {
      _topYear = _reportedYear = year;
      return;
    }
    position.jumpTo(offsetOfYear(year.clamp(_firstYear, _lastYear)));
    _scrolledTo(position.pixels);
  }

  /// Scrolls [year]'s header to the top over [OverviewListMetrics
  /// .pageDuration]; the years passed on the way are reported as they reach
  /// the top, as a drag reports them, while [isLanding] holds.
  Future<void> animateToYear(int year) async {
    final position = _attached?._position;
    if (position == null || _extent == null) {
      jumpToYear(year);
      return;
    }
    final target = year.clamp(_firstYear, _lastYear);
    final landing = ++_landings;
    _landing = true;
    _landingYear = target;
    try {
      await position.animateTo(
        offsetOfYear(target),
        duration: OverviewListMetrics.pageDuration,
        curve: Curves.easeOutCubic,
      );
    } finally {
      if (landing == _landings) {
        _landing = false;
        _landingYear = null;
        if (!_disposed) onLanded?.call();
      }
    }
  }

  /// Silences the callbacks; the scroll's own controller belongs to the
  /// widget and goes with it.
  void dispose() {
    _disposed = true;
    _attached = null;
  }

  void _scrolledTo(double pixels) {
    _topYear = yearAtOffset(pixels);
    _report();
  }

  /// Reports a new [topYear]. Never from inside a frame's build or layout —
  /// a span change can clamp the top year there — where the page could not
  /// rebuild; such a report waits for the frame's end.
  void _report() {
    if (_topYear == _reportedYear) return;
    _reportedYear = _topYear;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) onTopYearChanged?.call(_reportedYear);
      });
      return;
    }
    if (!_disposed) onTopYearChanged?.call(_reportedYear);
  }

  /// Aims the landing under way at its target's offset anew, once the frame
  /// that moved the span or the extent is laid out: correcting the pixels
  /// keeps the top year but leaves the running animation driving toward the
  /// offset the target had before, which is another year's now. The new
  /// animation takes the whole [OverviewListMetrics.pageDuration] from where
  /// the scroll is, so the landing never jumps.
  void _retargetLanding() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final year = landingYear;
      if (year == null || _disposed || !isAttached) return;
      unawaited(animateToYear(year));
    });
  }

  /// The scroll view's controller for a layout of [firstYear]…[lastYear] in
  /// sections of [extent]: made on the first layout with the top year's
  /// offset as its initial one, so the first frame already shows that
  /// year's header at the top; corrected in place when the extent or the
  /// span moves, so a width, text-scale or events change never changes the
  /// top year — the same section stays at the top, as far into it as it was.
  ScrollController _layout(
    _AgendaYearScrollState state, {
    required int firstYear,
    required int lastYear,
    required double headerHeight,
    required double extent,
  }) {
    final scroll = state._scroll;
    // A scroll fading out under the next one keeps its offset as it is.
    if (scroll != null && !identical(_attached, state)) return scroll;
    if (scroll == null) {
      _setMetrics(firstYear, lastYear, headerHeight, extent);
      _topYear = _topYear.clamp(firstYear, lastYear);
      _report();
      return state._scroll = ScrollController(
        initialScrollOffset: offsetOfYear(_topYear),
      )..addListener(state._onScroll);
    }
    if (firstYear == _firstYear &&
        lastYear == _lastYear &&
        headerHeight == _headerHeight &&
        extent == _extent) {
      return scroll;
    }
    final position = scroll.hasClients ? scroll.position : null;
    final pixels = position != null && position.hasPixels
        ? position.pixels
        : null;
    final top = pixels == null ? _topYear : yearAtOffset(pixels);
    final into = pixels == null ? 0.0 : pixels - offsetOfYear(top);
    final share = _extent == null ? 0.0 : into / _extent!;
    _setMetrics(firstYear, lastYear, headerHeight, extent);
    final kept = top.clamp(firstYear, lastYear);
    var target = offsetOfYear(kept);
    if (kept == top) {
      final scaled = target + share * extent;
      if (yearAtOffset(scaled) == kept) target = scaled;
    }
    _topYear = kept;
    if (pixels != null) {
      position!.correctPixels(math.max(0, target));
      if (_landing) _retargetLanding();
    }
    _report();
    return scroll;
  }

  void _setMetrics(int first, int last, double header, double extent) {
    _firstYear = first;
    _lastYear = last;
    _headerHeight = header;
    _extent = extent;
  }
}

/// Year mode of the overview as one continuous vertical scroll: every year
/// of [firstYear]…[lastYear] a section — a header with the year and its
/// count, then its twelve tiles, then a gap — earlier years above, later
/// below (D26).
///
/// Built for spans of a century: one [SliverFixedExtentList] of sections of
/// one height, so a far jump is arithmetic and only the sections in view are
/// built. [tiles] is cache-only — it answers from what the owner has
/// resolved and null for a year it has not, which draws a placeholder of the
/// same geometry (D30) until the owner's next run fills it; nothing here
/// resolves anything.
class AgendaYearScroll extends StatefulWidget {
  /// Created once per page and kept for the scroll's life: the scroll view's
  /// own controller is made from it on the first layout, and a swap would
  /// leave that controller's position, and its offset, with the old one.
  final AgendaYearScrollController controller;

  /// The span laid out, oldest first (D26): every year a section, so the
  /// owner hands only the years worth scrolling through (D28's ceiling).
  final int firstYear;
  final int lastYear;

  /// Each year's tiles, written by the owner as it resolves them. A section
  /// rebuilds when its own year's tiles change and at no other write, so a
  /// rebuild of the owner for any other reason — the keyboard resizing the
  /// page frame by frame, a year resolved beside it — rebuilds no section.
  final AgendaYearTileSource tiles;

  /// The marked days' colour: the page's, which follows the calendar's
  /// palette rather than the theme.
  final Color color;

  /// The calendar's appearance, for the week's first day and the accent;
  /// passed down rather than read here, as every calendar surface takes it.
  final CalendarAppearance appearance;

  /// The day the tiles ring, the page's own `today` so a scroll mounted
  /// across midnight agrees with the nav above it.
  final DateTime today;

  /// A tile's tap: the owner opens that month — the scroll only reports it.
  final ValueChanged<DateTime> onOpenMonth;

  /// Horizontal insets only: a section's offset is its index times its
  /// extent.
  final EdgeInsets padding;

  /// The scrubber lane along the right edge (D29), shown while the span
  /// holds two or more years; null shows none. The scroll owns the lane
  /// because the lane drives its own scroll controller.
  final AgendaYearScrubber? scrubber;

  const AgendaYearScroll({
    super.key,
    required this.controller,
    required this.firstYear,
    required this.lastYear,
    required this.tiles,
    required this.color,
    required this.appearance,
    required this.today,
    required this.onOpenMonth,
    required this.padding,
    this.scrubber,
  });

  /// A section's height for [columns] tiles a row under a header
  /// [headerHeight] tall: the header, the rows of [YearMonthTile.gridDelegate]
  /// with its spacing between them, and [OverviewListMetrics.yearSectionGap].
  static double sectionExtent({
    required int columns,
    required double headerHeight,
  }) {
    final grid = YearMonthTile.gridDelegate;
    final rows = (DateTime.monthsPerYear / columns).ceil();
    return headerHeight +
        rows * grid.mainAxisExtent! +
        (rows - 1) * grid.mainAxisSpacing +
        OverviewListMetrics.yearSectionGap;
  }

  @override
  State<AgendaYearScroll> createState() => _AgendaYearScrollState();
}

/// What the year scroll's [ListScrubber] lane says and where it clicks. Its
/// bubble names the year at the finger; a screen reader's increase and
/// decrease land one year on or back.
class AgendaYearScrubber {
  /// The lane's spoken name: its own words, since the list's lane scrolls by
  /// month and this one by year.
  final String semanticsLabel;

  /// The lane's id for the QA driver, which cannot tell the lane by a label
  /// it shares with nothing on screen; null where no flow walks it.
  final String? identifier;

  /// A scrub reached another year — where a page clicks.
  final VoidCallback? onLabelChanged;

  /// A screen reader's increase or decrease, as the year to land on: one on
  /// or back from the landing under way, else from the top year, so a
  /// second step during a landing goes on from its target. The owner lands
  /// there as its chevrons do — the target resolved before the first frame
  /// of the way, and a click — which the scroll, resolving nothing, cannot.
  final ValueChanged<int> onStep;

  const AgendaYearScrubber({
    required this.semanticsLabel,
    this.identifier,
    this.onLabelChanged,
    required this.onStep,
  });
}

/// The year scroll's tiles per year, written by the page that resolves them
/// and read by the sections. Each section listens and rebuilds only when its
/// own year's [versionOf] moved, so resolving one year rebuilds one section
/// and never the ones beside it. Writes are told to the sections at
/// [notify], once per batch.
class AgendaYearTileSource extends ChangeNotifier {
  final Map<int, List<AgendaYearTile>> _tiles = {};

  /// Every year ever written, cleared ones included — at most the
  /// calendar's two centuries — so a section showing a year that was
  /// dropped sees its version move.
  final Map<int, int> _versions = {};
  int _version = 0;
  bool _changed = false;

  /// [year]'s tiles; null while the year is unresolved (D30).
  List<AgendaYearTile>? tilesFor(int year) => _tiles[year];

  /// Moves whenever [tilesFor] answers anew for [year]; 0 for a year never
  /// written.
  int versionOf(int year) => _versions[year] ?? 0;

  /// The years holding tiles.
  Iterable<int> get years => _tiles.keys;

  bool holds(int year) => _tiles.containsKey(year);

  void put(int year, List<AgendaYearTile> tiles) {
    _tiles[year] = tiles;
    _bump(year);
  }

  /// Drops the tiles of every year [test] picks.
  void removeWhere(bool Function(int year) test) {
    final dropped = [
      for (final year in _tiles.keys)
        if (test(year)) year,
    ];
    for (final year in dropped) {
      _tiles.remove(year);
      _bump(year);
    }
  }

  void clear() => removeWhere((_) => true);

  /// Tells the sections what was written since the last call, if anything.
  void notify() {
    if (!_changed) return;
    _changed = false;
    notifyListeners();
  }

  void _bump(int year) {
    _versions[year] = ++_version;
    _changed = true;
  }
}

/// The header's two line heights at one text scale and pair of styles.
typedef _HeaderMetrics = ({
  TextScaler scaler,
  TextStyle? yearStyle,
  TextStyle? countStyle,
  double height,
  double countHeight,
});

class _AgendaYearScrollState extends State<AgendaYearScroll> {
  ScrollController? _scroll;
  _HeaderMetrics? _header;

  /// The sections' delegate and every input its sections draw. The sliver is
  /// handed the same instance while none moves, and an identical delegate
  /// rebuilds none of its children.
  SliverChildBuilderDelegate? _sections;
  Object? _sectionsInputs;

  /// Keeps the scroll view's state — its position — when the scrubber lane
  /// comes or goes above it.
  final GlobalKey _viewKey = GlobalKey();

  ScrollPosition? get _position {
    final scroll = _scroll;
    return scroll != null && scroll.hasClients ? scroll.position : null;
  }

  @override
  void initState() {
    super.initState();
    widget.controller._attached = this;
  }

  @override
  void didUpdateWidget(AgendaYearScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      identical(oldWidget.controller, widget.controller),
      'AgendaYearScroll.controller is created once per page and never '
      'swapped',
    );
  }

  @override
  void dispose() {
    // A mode cross-fade can mount the next scroll before this one leaves:
    // the newest keeps the controller.
    if (identical(widget.controller._attached, this)) {
      widget.controller._attached = null;
    }
    _scroll?.removeListener(_onScroll);
    _scroll?.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _position;
    if (position == null || !identical(widget.controller._attached, this)) {
      return;
    }
    widget.controller._scrolledTo(position.pixels);
  }

  /// The header's height — at least [OverviewListMetrics.yearHeaderHeight],
  /// more once the scaled year line and the air under it need it — and the
  /// count's one-line box, laid out once per text scale and theme, never per
  /// header.
  _HeaderMetrics _headerMetrics(
    TextScaler scaler,
    TextStyle? yearStyle,
    TextStyle? countStyle,
    TextDirection direction,
  ) {
    final cached = _header;
    if (cached != null &&
        cached.scaler == scaler &&
        cached.yearStyle == yearStyle &&
        cached.countStyle == countStyle) {
      return cached;
    }
    double lineOf(TextStyle? style) {
      final painter = TextPainter(
        // A line's height is its style's, whatever the line reads.
        text: TextSpan(text: '0000', style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return _header = (
      scaler: scaler,
      yearStyle: yearStyle,
      countStyle: countStyle,
      height: math.max(
        OverviewListMetrics.yearHeaderHeight,
        lineOf(yearStyle) + FormMetrics.bodyTop,
      ),
      countHeight: lineOf(countStyle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final yearStyle = theme.textTheme.titleLarge?.copyWith(
      fontSize: OverviewListMetrics.yearHeaderFontSize,
      fontWeight: FontWeight.w500,
      color: colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final countStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: FormMetrics.captionSize,
      fontWeight: FontWeight.w400,
      color: colorScheme.onSurfaceVariant,
    );
    final header = _headerMetrics(
      MediaQuery.textScalerOf(context),
      yearStyle,
      countStyle,
      Directionality.of(context),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // The width alone sizes a section; the height is read only by the
        // tail below, so a keyboard resizing the page frame by frame reaches
        // no section.
        final width = constraints.maxWidth - widget.padding.horizontal;
        final columns = YearMonthTile.columnsFor(width);
        final extent = AgendaYearScroll.sectionExtent(
          columns: columns,
          headerHeight: header.height,
        );
        final scroll = widget.controller._layout(
          this,
          firstYear: widget.firstYear,
          lastYear: widget.lastYear,
          headerHeight: header.height,
          extent: extent,
        );
        Widget view = Semantics(
          key: _viewKey,
          container: true,
          identifier: SemanticsIds.overviewYears,
          child: CustomScrollView(
            controller: scroll,
            slivers: [
              SliverPadding(
                padding: widget.padding,
                sliver: SliverFixedExtentList(
                  itemExtent: extent,
                  delegate: _sectionsFor(
                    context,
                    l10n: l10n,
                    colorScheme: colorScheme,
                    columns: columns,
                    header: header,
                  ),
                ),
              ),
              // Room under the last year, on a viewport taller than a
              // section, for its header to reach the top as every other
              // year's can — or a jump to it would stop short and the title
              // name the year above.
              SliverLayoutBuilder(
                builder: (context, constraints) {
                  final tail = constraints.viewportMainAxisExtent - extent;
                  return SliverToBoxAdapter(
                    child: SizedBox(height: tail > 0 ? tail : 0),
                  );
                },
              ),
            ],
          ),
        );
        final scrubber = widget.scrubber;
        if (scrubber != null && widget.lastYear > widget.firstYear) {
          final controller = widget.controller;
          // Outside the scroll's node, so the lane joins none of its
          // indexes; it overlays the right tiles' trailing 48 dp, and a tap
          // there still reaches the tile.
          view = ListScrubber(
            controller: scroll,
            labelAt: (offset) => '${controller.yearAtOffset(offset)}',
            semanticsLabel: scrubber.semanticsLabel,
            identifier: scrubber.identifier,
            onLabelChanged: scrubber.onLabelChanged,
            onStep: (direction) => scrubber.onStep(
              (controller.landingYear ?? controller.topYear) + direction,
            ),
            child: view,
          );
        }
        return view;
      },
    );
  }

  /// The sections' delegate, made anew only when an input every section
  /// draws moved — the columns, the header's metrics, the span, the colour,
  /// the appearance, the day, the locale, the theme or the tile source. A
  /// [SliverChildBuilderDelegate] always reports that it should rebuild, so
  /// only handing the sliver the identical instance keeps its sections as
  /// they are; a year's own tiles reach its section through the source.
  SliverChildBuilderDelegate _sectionsFor(
    BuildContext context, {
    required AppLocalizations l10n,
    required ColorScheme colorScheme,
    required int columns,
    required _HeaderMetrics header,
  }) {
    final inputs = (
      columns,
      header,
      widget.firstYear,
      widget.lastYear,
      widget.color,
      widget.appearance,
      widget.today,
      l10n.localeName,
      colorScheme,
      widget.tiles,
    );
    final cached = _sections;
    if (cached != null && inputs == _sectionsInputs) return cached;
    _sectionsInputs = inputs;
    final firstYear = widget.firstYear;
    final tileBuilder = AgendaYearTileBuilder.of(
      context,
      color: widget.color,
      appearance: widget.appearance,
      today: widget.today,
      onOpenMonth: (month) => widget.onOpenMonth(month),
    );
    // The delegate's own repaint boundary is the section's, and a section
    // listens for its own year: a year resolved rebuilds and repaints its
    // section alone.
    return _sections = SliverChildBuilderDelegate(
      (context, index) => _Section(
        year: firstYear + index,
        tiles: widget.tiles,
        columns: columns,
        header: header,
        tileBuilder: tileBuilder,
        l10n: l10n,
      ),
      childCount: widget.lastYear - firstYear + 1,
    );
  }
}

/// One year: its header, then its tiles in rows cut as
/// [YearMonthTile.gridDelegate] cuts them — each tile as wide as the grid
/// would make it — then the gap to the next year. While the year is
/// unresolved: month names, blank counts, every day at the unmarked alpha
/// (D30).
class _Section extends StatefulWidget {
  final int year;
  final AgendaYearTileSource tiles;
  final int columns;
  final _HeaderMetrics header;
  final AgendaYearTileBuilder tileBuilder;
  final AppLocalizations l10n;

  const _Section({
    required this.year,
    required this.tiles,
    required this.columns,
    required this.header,
    required this.tileBuilder,
    required this.l10n,
  });

  @override
  State<_Section> createState() => _SectionState();

  static List<AgendaYearTile> _placeholders(int year) => [
    for (var month = 1; month <= DateTime.monthsPerYear; month++)
      () {
        final days = DateTime.utc(year, month + 1, 0).day;
        return AgendaYearTile(
          month: DateTime.utc(year, month, 1),
          daysInMonth: days,
          count: 0,
          missedCount: 0,
          markedMask: 0,
          missedMask: 0,
          windowMask: (1 << days) - 1,
        );
      }(),
  ];
}

class _SectionState extends State<_Section> {
  /// The version of the year's tiles this section last built from.
  int _builtVersion = 0;

  @override
  void initState() {
    super.initState();
    widget.tiles.addListener(_onTiles);
  }

  @override
  void didUpdateWidget(_Section oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tiles, widget.tiles)) {
      oldWidget.tiles.removeListener(_onTiles);
      widget.tiles.addListener(_onTiles);
    }
  }

  @override
  void dispose() {
    widget.tiles.removeListener(_onTiles);
    super.dispose();
  }

  void _onTiles() {
    if (widget.tiles.versionOf(widget.year) != _builtVersion) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final year = widget.year;
    final columns = widget.columns;
    final tileBuilder = widget.tileBuilder;
    _builtVersion = widget.tiles.versionOf(year);
    final grid = YearMonthTile.gridDelegate;
    final resolved = widget.tiles.tilesFor(year);
    final shown = resolved ?? _Section._placeholders(year);
    final rows = (shown.length / columns).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _YearHeader(
          year: year,
          tiles: resolved,
          header: widget.header,
          l10n: widget.l10n,
        ),
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) SizedBox(height: grid.mainAxisSpacing),
          SizedBox(
            height: grid.mainAxisExtent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) SizedBox(width: grid.crossAxisSpacing),
                  Expanded(
                    child: row * columns + column < shown.length
                        ? tileBuilder.build(
                            shown[row * columns + column],
                            placeholder: resolved == null,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: OverviewListMetrics.yearSectionGap),
      ],
    );
  }
}

/// The year on the tiles' left edge, its count on the right in a one-line
/// box that shrinks rather than wraps — empty, at the same height, while the
/// year is unresolved — both on the line [FormMetrics.bodyTop] above the
/// tiles. One node for a screen reader, a heading.
class _YearHeader extends StatelessWidget {
  final int year;

  /// Null while the year is unresolved.
  final List<AgendaYearTile>? tiles;
  final _HeaderMetrics header;
  final AppLocalizations l10n;

  const _YearHeader({
    required this.year,
    required this.tiles,
    required this.header,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = tiles;
    String? count;
    if (resolved != null) {
      var kept = 0;
      var missed = 0;
      for (final tile in resolved) {
        kept += tile.count;
        missed += tile.missedCount;
      }
      count = agendaDayListCountLabel(l10n, kept, missed);
    }
    final yearText = '$year';
    return Semantics(
      container: true,
      header: true,
      label: count == null ? yearText : '$yearText, $count',
      identifier: SemanticsIds.overviewYearHeader(year),
      excludeSemantics: true,
      child: SizedBox(
        height: header.height,
        child: Padding(
          padding: const EdgeInsets.only(bottom: FormMetrics.bodyTop),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                yearText,
                style: header.yearStyle,
                maxLines: 1,
                softWrap: false,
              ),
              const SizedBox(width: FormMetrics.gap),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.bottomEnd,
                  child: SizedBox(
                    height: header.countHeight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        count ?? '',
                        style: header.countStyle,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
