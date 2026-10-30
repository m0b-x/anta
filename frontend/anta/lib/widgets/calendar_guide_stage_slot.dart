import 'package:flutter/material.dart';

/// A part of a "Try it" stage that scrolls inside the guide page: the panel
/// card's body, the overview card's body, the events card's list.
///
/// Flutter does not chain nested scrolling, so a drag that starts inside a
/// slot moves the slot only, and at the slot's end it moved nothing at all:
/// with a slot taking most of the screen she could not scroll the page past
/// it. Here the slot's scrollables clamp at their ends, and a finger's
/// overscroll goes on to move the page by the same distance, as if the
/// slot's end handed the drag over. A fling's overscroll is not passed on:
/// it would throw the page on after the finger has left.
///
/// The slot's scrollables also run on their own controllers — the page's
/// list holds the route's primary one — and draw no glow, which would read
/// as the slot being the page.
class GuideStageSlot extends StatelessWidget {
  const GuideStageSlot({super.key, this.height, required this.child});

  /// The slot's fixed height; null when the caller sizes the slot itself
  /// (the events card's list, over an unseen template).
  final double? height;

  final Widget child;

  bool _forward(BuildContext context, OverscrollNotification notification) {
    if (notification.dragDetails == null) return false;
    final page = Scrollable.maybeOf(context)?.position;
    if (page == null) return false;
    // The slot's own axis only: a mini month's sideways swipe that runs
    // past its last page is no page scroll.
    if (axisDirectionToAxis(notification.metrics.axisDirection) != page.axis) {
      return false;
    }
    final target = (page.pixels + notification.overscroll).clamp(
      page.minScrollExtent,
      page.maxScrollExtent,
    );
    if (target != page.pixels) page.jumpTo(target);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final slot = ScrollConfiguration(
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(overscroll: false, physics: const ClampingScrollPhysics()),
      child: PrimaryScrollController.none(
        child: NotificationListener<OverscrollNotification>(
          onNotification: (notification) => _forward(context, notification),
          child: child,
        ),
      ),
    );
    final height = this.height;
    return height == null ? slot : SizedBox(height: height, child: slot);
  }
}
