import 'dart:async';

import 'package:flutter/material.dart';
import '../constants/scroll_indicator_constants.dart';

/// A touch-friendly scroll progress indicator optimized for mobile: always
/// visible, with a thumb that can be tapped or dragged to a position.
class ScrollProgressIndicator extends StatefulWidget {
  final ScrollController scrollController;

  /// An extra repaint trigger for scroll offsets that change without the
  /// controller notifying — a viewport corrected inside layout, which is
  /// how the editor lands on a stored position. The thumb re-reads the
  /// position on every tick of this as well as on every scroll; without
  /// it a corrected offset showed only at the next periodic metrics check.
  final Listenable? repaint;
  final double visibleWidth;
  final double touchAreaWidth;
  final Color? activeColor;
  final Duration animationDuration;

  const ScrollProgressIndicator({
    super.key,
    required this.scrollController,
    this.repaint,
    this.visibleWidth = ScrollIndicatorConstants.visibleWidth,
    this.touchAreaWidth = ScrollIndicatorConstants.touchAreaWidth,
    this.activeColor,
    this.animationDuration = const Duration(
      milliseconds: ScrollIndicatorConstants.animationDurationMs,
    ),
  });

  @override
  State<ScrollProgressIndicator> createState() =>
      _ScrollProgressIndicatorState();
}

class _ScrollProgressIndicatorState extends State<ScrollProgressIndicator> {
  bool _isDragging = false;
  bool _isExpanded = false;
  double _lastKnownMaxScroll = 0;
  Timer? _collapseTimer;
  Timer? _metricsCheckTimer;

  // Smoothing state for reducing jiggle
  double _smoothedProgress = 0;

  /// Whether [_smoothedProgress] has ever been given a real reading.
  ///
  /// The filter must never ease up from its `0` initializer: a note
  /// reopened at a stored offset would render its thumb at the top and
  /// then crawl to the true position over a dozen rebuilds. The first
  /// reading is adopted outright, and only later ones are smoothed.
  bool _hasProgressBaseline = false;

  /// The progress behind the previous reading, to tell a continuous scroll
  /// (smoothed) from a discontinuity (taken in one step). Measured in
  /// progress space, not pixels: a content extent that changes under a
  /// still offset — a note reloaded longer beneath a buried editor — moves
  /// the thumb just as a jump does, and has to be recognised as one.
  double? _lastRawProgress;

  /// Whether a frame has already been requested to carry the smoothing
  /// filter closer to rest. The filter only steps when this widget builds,
  /// and builds stop with the last scroll notification — so without this,
  /// a fast swipe left the thumb resting short of the true position until
  /// the next touch lurched it forward.
  bool _settlePending = false;

  /// Frames spent settling since the last scroll notification. The loop
  /// converges in well under [ScrollIndicatorConstants.maxSettleFrames]
  /// from any lag the filter can hold; the cap only matters if a target
  /// ever kept moving without a scroll — which nothing here can cause,
  /// and which this keeps from becoming a spin at the refresh rate.
  int _settleFrames = 0;

  /// The track's box: the one place both the thumb's geometry and the
  /// gesture-to-offset mapping read from, so a tap lands where the thumb is
  /// drawn no matter what padding sits between here and there.
  final GlobalKey _trackKey = GlobalKey();

  /// What the thumb rebuilds on: the controller, merged with [repaint]
  /// when one is given. Built once here and on a widget change rather
  /// than per build, so the builder below keeps one subscription.
  late Listenable _thumbListenable;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    _thumbListenable = _mergeListenables();
    // Periodically check for content dimension changes
    _startMetricsCheck();
  }

  Listenable _mergeListenables() {
    final repaint = widget.repaint;
    return repaint == null
        ? widget.scrollController
        : Listenable.merge([widget.scrollController, repaint]);
  }

  /// The thumb's height for a given track, derived at layout time by
  /// [_ScrollThumbLayoutDelegate] and at gesture time by
  /// [_scrollToPosition] — one formula over one box ([_trackKey]).
  static double thumbHeightFor(double trackHeight) {
    if (trackHeight <= 0) return 0;
    final height = trackHeight * ScrollIndicatorConstants.thumbHeightPercentage;
    return height
        .clamp(
          ScrollIndicatorConstants.minThumbHeight,
          ScrollIndicatorConstants.maxThumbHeight,
        )
        .clamp(0.0, trackHeight);
  }

  /// The first attached position that can answer for the content, or
  /// `null` while the viewport is still being measured. Iterating
  /// [ScrollController.positions] rather than reading `.position`
  /// tolerates the frame in which a remounted editor has two attached.
  ScrollPosition? _activePosition() {
    if (!widget.scrollController.hasClients) return null;
    for (final position in widget.scrollController.positions) {
      if (position.hasContentDimensions) return position;
    }
    return null;
  }

  /// The laid-out track, or `null` before its first layout.
  RenderBox? _trackBox() {
    final box = _trackKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  /// Watches for content extent changes that arrive without a scroll
  /// notification, for callers that pass no [repaint]. It cannot see an
  /// offset-only correction (`correctBy` moves `pixels` and notifies
  /// nobody) — the editor hands its metrics notifications in as [repaint]
  /// for exactly that.
  void _startMetricsCheck() {
    _metricsCheckTimer?.cancel();
    _metricsCheckTimer = Timer.periodic(
      const Duration(
        milliseconds: ScrollIndicatorConstants.metricsCheckIntervalMs,
      ),
      (_) {
        if (!mounted) return;
        final position = _activePosition();
        if (position == null) return;
        if (position.maxScrollExtent != _lastKnownMaxScroll) {
          setState(() => _lastKnownMaxScroll = position.maxScrollExtent);
        }
      },
    );
  }

  @override
  void didUpdateWidget(ScrollProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
      // Reset smoothing state for new controller — the next reading is
      // adopted as the baseline instead of being eased into.
      _smoothedProgress = 0;
      _hasProgressBaseline = false;
      _lastRawProgress = null;
    }
    if (oldWidget.scrollController != widget.scrollController ||
        oldWidget.repaint != widget.repaint) {
      _thumbListenable = _mergeListenables();
    }
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _metricsCheckTimer?.cancel();
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  /// The thumb itself repaints from [_thumbListenable], so a scroll only
  /// has to bring the bar out of its idle width — and restart the settle
  /// budget, since the target is moving for a reason.
  void _onScroll() {
    _settleFrames = 0;
    if (!_isDragging) {
      _expandTemporarily();
    }
  }

  void _expandTemporarily() {
    if (!_isExpanded) {
      setState(() => _isExpanded = true);
    }
    _collapseTimer?.cancel();
    _collapseTimer = Timer(
      const Duration(milliseconds: ScrollIndicatorConstants.collapseDelayMs),
      () {
        if (mounted && !_isDragging) {
          setState(() => _isExpanded = false);
        }
      },
    );
  }

  void _scrollToPosition(Offset globalPosition) {
    final position = _activePosition();
    if (position == null) return;
    final maxScroll = position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final track = _trackBox();
    if (track == null) return;
    final trackHeight = track.size.height;
    final localY = track.globalToLocal(globalPosition).dy;
    final thumbHeight = thumbHeightFor(trackHeight);
    final effectiveTrack = trackHeight - thumbHeight;
    // A track shorter than the minimum thumb leaves nothing to aim at —
    // and would make the clamp below throw on its inverted range.
    if (effectiveTrack <= 0) return;

    final adjustedY = (localY - thumbHeight / 2).clamp(0.0, effectiveTrack);
    final newOffset = (adjustedY / effectiveTrack * maxScroll).clamp(
      0.0,
      maxScroll,
    );

    position.jumpTo(newOffset);
  }

  void _onDragStart(DragStartDetails details) {
    _collapseTimer?.cancel();
    setState(() {
      _isDragging = true;
      _isExpanded = true;
    });
    _scrollToPosition(details.globalPosition);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _scrollToPosition(details.globalPosition);
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });
    _expandTemporarily();
  }

  void _onTap(TapUpDetails details) {
    setState(() => _isExpanded = true);
    _scrollToPosition(details.globalPosition);
    _expandTemporarily();
  }

  /// The scroll position as a 0..1 fraction, damped.
  ///
  /// The editor's content extent is an estimate that is re-measured as
  /// paragraphs scroll through the window, and it corrects the offset by
  /// the difference — so `pixels / maxScrollExtent` twitches during a
  /// continuous scroll even though the reader sees smooth motion. The
  /// filter absorbs that. It is bypassed whenever exactness matters more:
  /// the first reading, the thumb under a finger, the edges, and any
  /// discontinuity (a jump, a restore, a search hit, a note that grew
  /// under a still offset), judged by the size of the step since the
  /// previous reading rather than by how far the thumb has fallen behind
  /// — a fast fling accumulates lag too, and snapping on that stuttered.
  ///
  /// After a smoothed step the filter asks for one more frame until it
  /// has settled, so the thumb comes to rest on the true position instead
  /// of wherever the last scroll notification left it.
  double _readProgress() {
    final position = _activePosition();
    if (position == null) return _smoothedProgress;

    final maxScroll = position.maxScrollExtent;
    _lastKnownMaxScroll = maxScroll;
    if (maxScroll <= 0) {
      _lastRawProgress = 0;
      _smoothedProgress = 0;
      return 0;
    }

    final rawProgress = (position.pixels / maxScroll).clamp(0.0, 1.0);
    final previousRaw = _lastRawProgress;
    _lastRawProgress = rawProgress;

    final isFirstReading = !_hasProgressBaseline;
    _hasProgressBaseline = true;

    final step = previousRaw == null ? 0.0 : (rawProgress - previousRaw).abs();
    final atStart =
        rawProgress <= ScrollIndicatorConstants.immediateEdgeSnapThreshold;
    final atEnd =
        rawProgress >= 1 - ScrollIndicatorConstants.immediateEdgeSnapThreshold;

    if (atStart ||
        atEnd ||
        isFirstReading ||
        _isDragging ||
        step > ScrollIndicatorConstants.fastSmoothingDeltaThreshold ||
        _settleFrames >= ScrollIndicatorConstants.maxSettleFrames) {
      _settleFrames = 0;
      _smoothedProgress = atStart
          ? 0
          : atEnd
          ? 1
          : rawProgress;
      return _smoothedProgress;
    }

    // Exponential smoothing: smoothed = smoothed + factor * (raw - smoothed)
    _smoothedProgress =
        _smoothedProgress +
        ScrollIndicatorConstants.smoothingFactor *
            (rawProgress - _smoothedProgress);
    if ((rawProgress - _smoothedProgress).abs() <=
        ScrollIndicatorConstants.settleTolerance) {
      _smoothedProgress = rawProgress;
      _settleFrames = 0;
    } else {
      _requestSettleFrame();
    }
    return _smoothedProgress;
  }

  /// Rebuilds once more after the current frame so the smoothing filter
  /// can take its next step. One request at a time: a build that is still
  /// unsettled re-arms it, a settled one lets it lapse.
  void _requestSettleFrame() {
    if (_settlePending) return;
    _settlePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _settlePending = false;
      if (!mounted) return;
      _settleFrames++;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseColor =
        widget.activeColor ?? Theme.of(context).colorScheme.primary;

    // Dynamic widths based on state
    final barWidth = _isDragging || _isExpanded
        ? widget.visibleWidth * ScrollIndicatorConstants.expandedWidthMultiplier
        : widget.visibleWidth;

    // Colors - always visible but more prominent when active
    final thumbColor = _isDragging
        ? baseColor
        : _isExpanded
        ? baseColor.withValues(
            alpha: ScrollIndicatorConstants.expandedThumbOpacity,
          )
        : baseColor.withValues(
            alpha: ScrollIndicatorConstants.idleThumbOpacity,
          );

    final trackColor = _isDragging || _isExpanded
        ? Theme.of(context).colorScheme.onSurface.withValues(
            alpha: ScrollIndicatorConstants.expandedTrackOpacity,
          )
        : Theme.of(context).colorScheme.onSurface.withValues(
            alpha: ScrollIndicatorConstants.idleTrackOpacity,
          );

    return AnimatedBuilder(
      animation: _thumbListenable,
      builder: (context, child) {
        final progress = _readProgress();

        // Use a narrower touch area that only covers the visible scrollbar
        // This prevents blocking touches on the editor content
        final effectiveTouchWidth =
            barWidth + 12; // Visible bar + small touch margin

        return Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTapUp: _onTap,
            onVerticalDragStart: _onDragStart,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            onHorizontalDragStart: (_) {
              setState(() => _isExpanded = true);
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: effectiveTouchWidth,
              color: Colors.transparent,
              child: Align(
                alignment: Alignment.centerRight,
                child: AnimatedContainer(
                  duration: widget.animationDuration,
                  curve: Curves.easeOut,
                  width: barWidth,
                  margin: const EdgeInsets.only(
                    right: ScrollIndicatorConstants.rightMargin,
                  ),
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: BorderRadius.circular(barWidth),
                  ),
                  // The thumb is sized and placed by layout, from the
                  // track's live height. Nothing about its geometry
                  // survives a build, so a viewport that grows back when
                  // the keyboard closes cannot leave a keyboard-sized
                  // thumb behind — there is no cached height to go stale.
                  child: CustomSingleChildLayout(
                    key: _trackKey,
                    delegate: _ScrollThumbLayoutDelegate(progress: progress),
                    child: AnimatedContainer(
                      duration: const Duration(
                        milliseconds: ScrollIndicatorConstants.thumbAnimationMs,
                      ),
                      decoration: BoxDecoration(
                        color: thumbColor,
                        borderRadius: BorderRadius.circular(barWidth),
                        boxShadow: _isDragging
                            ? [
                                BoxShadow(
                                  color: baseColor.withValues(
                                    alpha: ScrollIndicatorConstants
                                        .dragShadowOpacity,
                                  ),
                                  blurRadius: ScrollIndicatorConstants
                                      .dragShadowBlurRadius,
                                  spreadRadius: ScrollIndicatorConstants
                                      .dragShadowSpreadRadius,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Sizes the thumb to a share of the track and slides it along it.
///
/// Both numbers come from the track's size at layout time, so they follow
/// a viewport that changes height (the keyboard opening over the editor)
/// without needing a rebuild to notice.
class _ScrollThumbLayoutDelegate extends SingleChildLayoutDelegate {
  const _ScrollThumbLayoutDelegate({required this.progress});

  final double progress;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // No track to be a share of — an unbounded parent, which the callers
    // never produce — falls back to a fixed thumb.
    final thumbHeight = constraints.hasBoundedHeight
        ? _ScrollProgressIndicatorState.thumbHeightFor(constraints.maxHeight)
        : ScrollIndicatorConstants.defaultThumbHeight;
    return BoxConstraints.tightFor(
      width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
      height: thumbHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final travel = size.height - childSize.height;
    if (travel <= 0) return Offset.zero;
    return Offset(0, progress.clamp(0.0, 1.0) * travel);
  }

  @override
  bool shouldRelayout(_ScrollThumbLayoutDelegate oldDelegate) =>
      oldDelegate.progress != progress;
}

/// A widget that wraps content with a scroll progress indicator on the right.
class ScrollProgressWrapper extends StatefulWidget {
  final Widget child;
  final ScrollController? scrollController;
  final double indicatorWidth;
  final Color? activeColor;

  const ScrollProgressWrapper({
    super.key,
    required this.child,
    this.scrollController,
    this.indicatorWidth = 6,
    this.activeColor,
  });

  @override
  State<ScrollProgressWrapper> createState() => _ScrollProgressWrapperState();
}

class _ScrollProgressWrapperState extends State<ScrollProgressWrapper> {
  late ScrollController _scrollController;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    if (widget.scrollController != null) {
      _scrollController = widget.scrollController!;
    } else {
      _scrollController = ScrollController();
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: ScrollProgressIndicator(
            scrollController: _scrollController,
            visibleWidth: widget.indicatorWidth,
            activeColor: widget.activeColor,
          ),
        ),
      ],
    );
  }
}
