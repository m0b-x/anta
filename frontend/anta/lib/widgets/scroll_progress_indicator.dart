import 'dart:async';

import 'package:flutter/material.dart';
import '../constants/scroll_indicator_constants.dart';

/// A touch-friendly scroll progress indicator optimized for mobile.
/// Features a wide touch area, always visible, and supports edge swipe.
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
  /// [_scrollToPosition] — one formula, so a tap lands where the thumb
  /// is actually drawn.
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

  /// The track's live height, read from this widget's own box rather than
  /// from anything cached in a previous build. The box is laid out with a
  /// tight height by the caller's `Positioned`, so it is the track.
  double _trackHeight() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return 0;
    return box.size.height;
  }

  /// Watches for content dimension changes that arrive without a scroll
  /// notification. Callers that pass [repaint] are already covered by it;
  /// this is the fallback for the ones that do not.
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
  /// has to bring the bar out of its idle width.
  void _onScroll() {
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

  void _scrollToPosition(double localY) {
    final position = _activePosition();
    if (position == null) return;
    final maxScroll = position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final trackHeight = _trackHeight();
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
    _scrollToPosition(details.localPosition.dy);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _scrollToPosition(details.localPosition.dy);
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });
    _expandTemporarily();
  }

  void _onTap(TapUpDetails details) {
    setState(() => _isExpanded = true);
    _scrollToPosition(details.localPosition.dy);
    _expandTemporarily();
  }

  /// The scroll position as a 0..1 fraction, damped.
  ///
  /// Smoothing exists to absorb the small jitter a changing
  /// `maxScrollExtent` causes while content is measured — so it applies
  /// only to small deltas. A large one is a real move (a restore, a
  /// search jump, a fling) and is adopted immediately; easing into it is
  /// what made a reopened note's thumb travel across the track.
  double _readProgress() {
    final position = _activePosition();
    if (position == null) return _smoothedProgress;

    final maxScroll = position.maxScrollExtent;
    _lastKnownMaxScroll = maxScroll;
    if (maxScroll <= 0) return 0;

    final rawProgress = (position.pixels / maxScroll).clamp(0.0, 1.0);

    if (!_hasProgressBaseline) {
      _hasProgressBaseline = true;
      _smoothedProgress = rawProgress;
      return _smoothedProgress;
    }

    if (_isDragging) {
      // Snap to edges immediately when dragging
      if (rawProgress <= ScrollIndicatorConstants.dragEdgeSnapThreshold) {
        _smoothedProgress = 0;
      } else if (rawProgress >=
          1 - ScrollIndicatorConstants.dragEdgeSnapThreshold) {
        _smoothedProgress = 1;
      } else {
        _smoothedProgress =
            _smoothedProgress +
            ScrollIndicatorConstants.dragSmoothingFactor *
                (rawProgress - _smoothedProgress);
      }
      return _smoothedProgress;
    }

    // Snap to edges when at the very beginning or end
    if (rawProgress <= ScrollIndicatorConstants.immediateEdgeSnapThreshold) {
      _smoothedProgress = 0;
      return _smoothedProgress;
    }
    if (rawProgress >=
        1 - ScrollIndicatorConstants.immediateEdgeSnapThreshold) {
      _smoothedProgress = 1;
      return _smoothedProgress;
    }

    final delta = (rawProgress - _smoothedProgress).abs();
    if (delta > ScrollIndicatorConstants.fastSmoothingDeltaThreshold) {
      _smoothedProgress = rawProgress;
      return _smoothedProgress;
    }

    // Exponential smoothing: smoothed = smoothed + factor * (raw - smoothed)
    // This dampens small fluctuations while tracking large changes
    _smoothedProgress =
        _smoothedProgress +
        ScrollIndicatorConstants.smoothingFactor *
            (rawProgress - _smoothedProgress);

    // Snap to edges when very close
    if (_smoothedProgress < ScrollIndicatorConstants.nearEdgeSmoothedThreshold &&
        rawProgress < ScrollIndicatorConstants.nearEdgeRawThreshold) {
      _smoothedProgress = 0;
    } else if (_smoothedProgress >
            1 - ScrollIndicatorConstants.nearEdgeSmoothedThreshold &&
        rawProgress > 1 - ScrollIndicatorConstants.nearEdgeRawThreshold) {
      _smoothedProgress = 1;
    }
    return _smoothedProgress;
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
                    delegate: _ScrollThumbLayoutDelegate(progress: progress),
                    child: AnimatedContainer(
                      duration: const Duration(
                        milliseconds:
                            ScrollIndicatorConstants.thumbAnimationMs,
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
    final trackHeight = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : ScrollIndicatorConstants.defaultThumbHeight;
    return BoxConstraints.tightFor(
      width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
      height: _ScrollProgressIndicatorState.thumbHeightFor(trackHeight),
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
