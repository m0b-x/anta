import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A mixin that provides momentum-based scrolling functionality.
/// Use with SingleTickerProviderStateMixin for animation support.
mixin ScrollZoneMixin<T extends StatefulWidget> on State<T>, TickerProvider {
  /// Override these to customize scroll behavior
  double get scrollSensitivity => 1.8;
  double get minVelocityThreshold => 150.0;
  double get momentumMultiplier => 0.35;
  Duration get momentumDuration => const Duration(milliseconds: 900);

  late AnimationController _scrollMomentumController;
  Animation<double>? _scrollMomentumAnimation;

  Offset? _lastScrollDragPosition;
  double _scrollVelocity = 0;
  DateTime _lastScrollDragTime = DateTime.now();

  /// Call this in initState
  void initScrollZone() {
    _scrollMomentumController = AnimationController(
      vsync: this,
      duration: momentumDuration,
    );
    _scrollMomentumController.addListener(_onMomentumTick);
  }

  /// Call this in dispose
  void disposeScrollZone() {
    _scrollMomentumController.removeListener(_onMomentumTick);
    _scrollMomentumController.dispose();
  }

  void _onMomentumTick() {
    final controller = getScrollController();
    if (_scrollMomentumAnimation == null || !controller.hasClients) {
      return;
    }
    final offset = _scrollMomentumAnimation!.value;
    final maxScroll = controller.position.maxScrollExtent;
    controller.jumpTo(offset.clamp(0.0, maxScroll));
  }

  /// Override this to provide the scroll controller
  ScrollController getScrollController();

  void handleScrollDragStart(DragStartDetails details) {
    stopScrollMomentum();
    _lastScrollDragPosition = details.globalPosition;
    _lastScrollDragTime = DateTime.now();
    _scrollVelocity = 0;
    HapticFeedback.selectionClick();
  }

  void handleScrollDragUpdate(DragUpdateDetails details) {
    final controller = getScrollController();
    if (!controller.hasClients) {
      return;
    }

    final now = DateTime.now();
    final dy = details.globalPosition.dy - (_lastScrollDragPosition?.dy ?? 0);
    final dt = now.difference(_lastScrollDragTime).inMilliseconds.toDouble();

    if (dt > 0) {
      _scrollVelocity = -dy / dt * 1000;
    }

    final currentOffset = controller.offset;
    final maxOffset = controller.position.maxScrollExtent;
    final newOffset = (currentOffset - dy * scrollSensitivity).clamp(
      0.0,
      maxOffset,
    );

    controller.jumpTo(newOffset);

    _lastScrollDragPosition = details.globalPosition;
    _lastScrollDragTime = now;
  }

  void handleScrollDragEnd(DragEndDetails details) {
    startScrollMomentum(_scrollVelocity);
  }

  void startScrollMomentum(double velocity) {
    final controller = getScrollController();
    if (!controller.hasClients || velocity.abs() < minVelocityThreshold) {
      return;
    }

    final currentOffset = controller.offset;
    final maxScroll = controller.position.maxScrollExtent;
    final distance = velocity * momentumMultiplier;
    final targetOffset = (currentOffset + distance).clamp(0.0, maxScroll);

    _scrollMomentumAnimation =
        Tween<double>(begin: currentOffset, end: targetOffset).animate(
          CurvedAnimation(
            parent: _scrollMomentumController,
            curve: Curves.easeOutCubic,
          ),
        );

    _scrollMomentumController.forward(from: 0);
  }

  void stopScrollMomentum() {
    _scrollMomentumController.stop();
  }

  /// Builds a positioned scroll zone widget for use in a Stack
  Widget buildScrollZone({
    double width = 80.0,
    double top = 0,
    double bottom = 0,
    double right = 0,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      right: right,
      width: width,
      child: GestureDetector(
        onVerticalDragStart: handleScrollDragStart,
        onVerticalDragUpdate: handleScrollDragUpdate,
        onVerticalDragEnd: handleScrollDragEnd,
        behavior: HitTestBehavior.translucent,
        child: Container(color: Colors.transparent),
      ),
    );
  }
}
