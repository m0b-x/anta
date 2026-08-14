import 'package:flutter/material.dart';

import '../controllers/preview_scroll_controller.dart';

/// Interactive scrollbar for preview mode that works with ScrollablePositionedList.
/// Supports both display of current position AND dragging to scroll.
class InteractivePreviewScrollbar extends StatefulWidget {
  final PreviewScrollController controller;

  const InteractivePreviewScrollbar({super.key, required this.controller});

  @override
  State<InteractivePreviewScrollbar> createState() =>
      _InteractivePreviewScrollbarState();
}

class _InteractivePreviewScrollbarState
    extends State<InteractivePreviewScrollbar> {
  static const double _barWidth = 6.0;
  static const double _expandedWidth = 12.0;
  static const double _touchAreaWidth = 44.0;
  static const double _thumbMinHeight = 20.0;
  static const double _thumbMaxHeight = 50.0;
  static const double _thumbHeightPercent = 0.10;
  static const double _rightMargin = 2.0;

  bool _isDragging = false;
  bool _isHovering = false;
  double _smoothedProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _smoothedProgress = widget.controller.progress.value;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.primary;

    return ValueListenableBuilder<double>(
      valueListenable: widget.controller.progress,
      builder: (context, progress, _) {
        // When dragging, use the smooth progress we control
        // When not dragging, use the notifier's progress
        final targetProgress = _isDragging ? _smoothedProgress : progress;

        final isActive = _isDragging || _isHovering;
        final barWidth = isActive ? _expandedWidth : _barWidth;
        final thumbColor = isActive
            ? baseColor.withValues(alpha: 0.8)
            : baseColor.withValues(alpha: 0.5);
        final trackColor = isActive
            ? colorScheme.onSurface.withValues(alpha: 0.15)
            : colorScheme.onSurface.withValues(alpha: 0.08);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: _onDragStart,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          onTapDown: _onTapDown,
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovering = true),
            onExit: (_) => setState(() => _isHovering = false),
            child: Container(
              width: _touchAreaWidth,
              alignment: Alignment.centerRight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final trackHeight = constraints.maxHeight;

                  // Dynamic thumb height based on track
                  final thumbHeight = (trackHeight * _thumbHeightPercent).clamp(
                    _thumbMinHeight,
                    _thumbMaxHeight,
                  );

                  final maxOffset = trackHeight - thumbHeight;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: barWidth,
                    margin: const EdgeInsets.only(right: _rightMargin),
                    decoration: BoxDecoration(
                      color: trackColor,
                      borderRadius: BorderRadius.circular(barWidth),
                    ),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: targetProgress, end: targetProgress),
                      duration: _isDragging
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      builder: (context, animatedProgress, child) {
                        final thumbTop = (animatedProgress * maxOffset).clamp(
                          0.0,
                          maxOffset,
                        );
                        return Stack(
                          children: [
                            Positioned(
                              top: thumbTop,
                              left: 0,
                              right: 0,
                              height: thumbHeight,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                decoration: BoxDecoration(
                                  color: thumbColor,
                                  borderRadius: BorderRadius.circular(barWidth),
                                  boxShadow: _isDragging
                                      ? [
                                          BoxShadow(
                                            color: baseColor.withValues(
                                              alpha: 0.3,
                                            ),
                                            blurRadius: 4,
                                            spreadRadius: 1,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _onDragStart(DragStartDetails details) {
    _smoothedProgress = widget.controller.progress.value;
    setState(() => _isDragging = true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _scrollToPosition(details.localPosition.dy);
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() => _isDragging = false);
  }

  void _onTapDown(TapDownDetails details) {
    _scrollToPosition(details.localPosition.dy);
  }

  void _scrollToPosition(double localY) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final trackHeight = renderBox.size.height;
    final thumbHeight = (trackHeight * _thumbHeightPercent).clamp(
      _thumbMinHeight,
      _thumbMaxHeight,
    );

    // Calculate progress, accounting for thumb size
    final maxOffset = trackHeight - thumbHeight;
    final adjustedY = localY - (thumbHeight / 2);
    final progress = (adjustedY / maxOffset).clamp(0.0, 1.0);

    // Update smoothed progress for drag feedback
    setState(() => _smoothedProgress = progress);

    // Scroll the markdown view via the controller
    widget.controller.scrollToProgress(progress);
  }
}
