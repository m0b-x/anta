import 'dart:async';

import 'package:flutter/material.dart';
import '../constants/scroll_indicator_constants.dart';

/// A touch-friendly scroll progress indicator optimized for mobile.
/// Features a wide touch area, always visible, and supports edge swipe.
class ScrollProgressIndicator extends StatefulWidget {
  final ScrollController scrollController;
  final double visibleWidth;
  final double touchAreaWidth;
  final Color? activeColor;
  final Duration animationDuration;

  const ScrollProgressIndicator({
    super.key,
    required this.scrollController,
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
  double _thumbHeight = ScrollIndicatorConstants.defaultThumbHeight;
  double _trackHeight = 0;
  double _maxScroll = 0;
  Timer? _collapseTimer;
  Timer? _metricsCheckTimer;

  // Smoothing state for reducing jiggle
  double _smoothedProgress = 0;

  // Scroll stabilization state
  bool _isStabilizing = false;
  bool _isTapping = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    // Periodically check for content dimension changes
    _startMetricsCheck();
  }

  void _startMetricsCheck() {
    _metricsCheckTimer?.cancel();
    _metricsCheckTimer = Timer.periodic(
      const Duration(
        milliseconds: ScrollIndicatorConstants.metricsCheckIntervalMs,
      ),
      (_) {
        if (!mounted) return;
        if (widget.scrollController.hasClients) {
          // Use positions (plural) to safely handle multiple attached views
          for (final pos in widget.scrollController.positions) {
            if (pos.hasContentDimensions) {
              final newMaxScroll = pos.maxScrollExtent;
              if (newMaxScroll != _maxScroll &&
                  _maxScroll > 0 &&
                  newMaxScroll > 0) {
                // Scroll extent changed - stabilize position to reduce content jumping
                final currentOffset = pos.pixels;
                final currentPercentage = currentOffset / _maxScroll;

                // Only stabilize if not at edges and change is significant
                final extentChange =
                    (newMaxScroll - _maxScroll).abs() / _maxScroll;
                if (extentChange >
                        ScrollIndicatorConstants.minExtentChangeThreshold &&
                    extentChange <
                        ScrollIndicatorConstants.maxExtentChangeThreshold &&
                    currentPercentage >
                        ScrollIndicatorConstants
                            .minScrollPercentageForStabilization &&
                    currentPercentage <
                        ScrollIndicatorConstants
                            .maxScrollPercentageForStabilization &&
                    !_isDragging &&
                    !_isTapping &&
                    !_isStabilizing) {
                  // Calculate what offset would maintain same relative position
                  final targetOffset = currentPercentage * newMaxScroll;
                  final offsetDelta = (targetOffset - currentOffset).abs();

                  // Only correct if the jump would be noticeable but not too large
                  if (offsetDelta >
                          ScrollIndicatorConstants.minOffsetDeltaToCorrect &&
                      offsetDelta <
                          ScrollIndicatorConstants.maxOffsetDeltaToCorrect) {
                    _isStabilizing = true;
                    pos.correctPixels(targetOffset);
                    Future.microtask(() {
                      if (mounted) _isStabilizing = false;
                    });
                  }
                }

                setState(() {
                  _maxScroll = newMaxScroll;
                });
              } else if (newMaxScroll != _maxScroll) {
                setState(() {
                  _maxScroll = newMaxScroll;
                });
              }
              break;
            }
          }
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
      // Reset smoothing state for new controller
      _smoothedProgress = 0;
    }
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _metricsCheckTimer?.cancel();
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    // Force rebuild to update progress indicator position
    setState(() {});
    // Expand briefly when scrolling
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
    if (!widget.scrollController.hasClients) return;

    // Use positions (plural) to safely handle multiple attached views
    ScrollPosition? activePosition;
    for (final pos in widget.scrollController.positions) {
      if (pos.hasContentDimensions) {
        activePosition = pos;
        _maxScroll = pos.maxScrollExtent;
        break;
      }
    }

    if (activePosition == null || _maxScroll <= 0) return;

    final effectiveTrack = _trackHeight - _thumbHeight;
    final adjustedY = (localY - _thumbHeight / 2).clamp(0.0, effectiveTrack);
    final newProgress = effectiveTrack > 0 ? adjustedY / effectiveTrack : 0.0;
    final newOffset = (newProgress * _maxScroll).clamp(0.0, _maxScroll);

    // Jump to position on the active scroll position
    activePosition.jumpTo(newOffset);
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
    setState(() {
      _isExpanded = true;
      _isTapping = true;
    });
    _scrollToPosition(details.localPosition.dy);
    // Reset tapping flag after stabilization window
    Future.delayed(
      const Duration(milliseconds: ScrollIndicatorConstants.tapResetDelayMs),
      () {
        if (mounted) setState(() => _isTapping = false);
      },
    );
    _expandTemporarily();
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

    return LayoutBuilder(
      builder: (context, constraints) {
        _trackHeight = constraints.maxHeight;
        _thumbHeight =
            (_trackHeight * ScrollIndicatorConstants.thumbHeightPercentage)
                .clamp(
                  ScrollIndicatorConstants.minThumbHeight,
                  ScrollIndicatorConstants.maxThumbHeight,
                );
        final maxTop = _trackHeight - _thumbHeight;

        return AnimatedBuilder(
          animation: widget.scrollController,
          builder: (context, child) {
            // Calculate progress directly from scroll controller
            // Use positions (plural) to handle multiple attached scroll views gracefully
            double progress = 0;
            if (widget.scrollController.hasClients) {
              // Get the first position that has content dimensions
              ScrollPosition? activePosition;
              for (final pos in widget.scrollController.positions) {
                if (pos.hasContentDimensions) {
                  activePosition = pos;
                  break;
                }
              }

              if (activePosition != null) {
                final maxScroll = activePosition.maxScrollExtent;
                final currentOffset = activePosition.pixels;
                _maxScroll = maxScroll; // Update for drag operations

                if (maxScroll > 0) {
                  final rawProgress = (currentOffset / maxScroll).clamp(
                    0.0,
                    1.0,
                  );

                  // Apply smoothing to reduce jiggle from dynamic maxScrollExtent changes
                  // When dragging, use faster smoothing for responsiveness
                  if (_isDragging) {
                    // Snap to edges immediately when dragging
                    if (rawProgress <=
                        ScrollIndicatorConstants.dragEdgeSnapThreshold) {
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
                  } else {
                    // Snap to edges when at the very beginning or end
                    if (rawProgress <=
                        ScrollIndicatorConstants.immediateEdgeSnapThreshold) {
                      _smoothedProgress = 0;
                    } else if (rawProgress >=
                        1 -
                            ScrollIndicatorConstants
                                .immediateEdgeSnapThreshold) {
                      _smoothedProgress = 1;
                    } else {
                      // Exponential smoothing: smoothed = smoothed + factor * (raw - smoothed)
                      // This dampens small fluctuations while tracking large changes
                      final delta = (rawProgress - _smoothedProgress).abs();

                      // Use faster smoothing for large jumps, slower for small jitter
                      final adaptiveFactor =
                          delta >
                              ScrollIndicatorConstants
                                  .fastSmoothingDeltaThreshold
                          ? ScrollIndicatorConstants.fastSmoothingFactor
                          : ScrollIndicatorConstants.smoothingFactor;
                      _smoothedProgress =
                          _smoothedProgress +
                          adaptiveFactor * (rawProgress - _smoothedProgress);

                      // Snap to edges when very close
                      if (_smoothedProgress <
                              ScrollIndicatorConstants
                                  .nearEdgeSmoothedThreshold &&
                          rawProgress <
                              ScrollIndicatorConstants.nearEdgeRawThreshold) {
                        _smoothedProgress = 0;
                      } else if (_smoothedProgress >
                              1 -
                                  ScrollIndicatorConstants
                                      .nearEdgeSmoothedThreshold &&
                          rawProgress >
                              1 -
                                  ScrollIndicatorConstants
                                      .nearEdgeRawThreshold) {
                        _smoothedProgress = 1;
                      }
                    }
                  }
                  progress = _smoothedProgress;
                }
              }
            }
            final top = progress * maxTop;

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
                      child: Stack(
                        children: [
                          Positioned(
                            top: top,
                            left: 0,
                            right: 0,
                            child: AnimatedContainer(
                              duration: const Duration(
                                milliseconds:
                                    ScrollIndicatorConstants.thumbAnimationMs,
                              ),
                              height: _thumbHeight,
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
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
