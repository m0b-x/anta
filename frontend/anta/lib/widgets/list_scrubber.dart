import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';

/// Fast travel through a long list: a lane along the list's right edge maps
/// a vertical drag onto the whole scroll extent, and a bubble beside the
/// finger names the section the list has reached.
///
/// The lane is [FormMetrics.scrubberLaneWidth] (48) wide so a thumb finds it
/// without aiming at the 4 dp scrollbar thumb beneath; it carries no tap
/// recognizer, so a tap there still reaches the row it covers, and a drag
/// that starts on the rows scrolls them as usual. [child] is the bare list on
/// [controller]; the scrubber draws its scrollbar, so the thumb holds while a
/// scrub stands still, and the scrollbar takes no gesture of its own — the
/// lane is its drag, and its track-tap band would take a row's tap.
class ListScrubber extends StatefulWidget {
  const ListScrubber({
    super.key,
    required this.controller,
    required this.labelAt,
    required this.semanticsLabel,
    this.identifier,
    this.onLabelChanged,
    this.onStep,
    required this.child,
  });

  final ScrollController controller;

  /// The bubble's text at a scroll offset; null shows no bubble.
  final String? Function(double offset) labelAt;

  final String semanticsLabel;
  final String? identifier;

  /// A scrub moved the label to another text — where a page clicks.
  final VoidCallback? onLabelChanged;

  /// The lane's semantics actions: a screen reader cannot drag a lane, so
  /// increase and decrease step the list one section on (1) or back (-1).
  /// Null leaves the node without actions.
  final ValueChanged<int>? onStep;

  final Widget child;

  @override
  State<ListScrubber> createState() => _ListScrubberState();
}

class _ListScrubberState extends State<ListScrubber> {
  bool _scrubbing = false;

  /// The label at the list's offset while a scrub runs; null hides the
  /// bubble.
  String? _label;

  /// The last label shown, kept so the bubble fades out with its text.
  String? _shown;

  /// The pointer's height in the lane, which the bubble is centred on.
  double _pointerY = 0;

  /// The newest position: a cross-fade can hold an outgoing list for a
  /// moment on the same controller.
  ScrollPosition? get _position =>
      widget.controller.hasClients ? widget.controller.positions.last : null;

  void _onStart(DragStartDetails details) {
    final position = _position;
    if (position == null) return;
    _scrubbing = true;
    _label = widget.labelAt(position.pixels);
    _scrubTo(details.localPosition.dy);
  }

  void _onUpdate(DragUpdateDetails details) {
    if (_scrubbing) _scrubTo(details.localPosition.dy);
  }

  void _onEnd([DragEndDetails? _]) {
    if (!_scrubbing || !mounted) return;
    setState(() => _scrubbing = false);
  }

  /// The lane is the scrubber's whole height, so [y] over that height is the
  /// share of the extent to jump to.
  void _scrubTo(double y) {
    final position = _position;
    final box = context.findRenderObject() as RenderBox?;
    if (position == null || box == null || !box.hasSize) return;
    final height = box.size.height;
    final share = height > 0 ? (y / height).clamp(0.0, 1.0) : 0.0;
    final offset = share * position.maxScrollExtent;
    if (offset != position.pixels) position.jumpTo(offset);
    final label = widget.labelAt(position.pixels);
    if (label != null && label != _label) widget.onLabelChanged?.call();
    setState(() {
      _pointerY = y.clamp(0.0, height);
      _label = label;
      if (label != null) _shown = label;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    // The list's own drag takes the device's touch slop (8 dp on Android)
    // from here; with the framework default (18 dp) the lane would reach its
    // slop after the list and lose every real touch to a scroll. On equal
    // slop the lane, hit first, sees the move first and wins.
    final gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    return Stack(
      children: [
        Scrollbar(
          controller: widget.controller,
          thickness: FormMetrics.scrubberThumbWidth,
          thumbVisibility: _scrubbing,
          interactive: false,
          child: widget.child,
        ),
        Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: FormMetrics.scrubberLaneWidth,
          child: Semantics(
            container: true,
            identifier: widget.identifier,
            label: widget.semanticsLabel,
            onIncrease: switch (widget.onStep) {
              final step? => () => step(1),
              null => null,
            },
            onDecrease: switch (widget.onStep) {
              final step? => () => step(-1),
              null => null,
            },
            child: RawGestureDetector(
              behavior: HitTestBehavior.translucent,
              // The node above speaks for the lane; the recognizer's own
              // scroll actions would read as a second scrollable.
              excludeFromSemantics: true,
              gestures: {
                VerticalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      VerticalDragGestureRecognizer
                    >(() => VerticalDragGestureRecognizer(debugOwner: this), (
                      recognizer,
                    ) {
                      recognizer
                        ..gestureSettings = gestureSettings
                        ..onStart = _onStart
                        ..onUpdate = _onUpdate
                        ..onEnd = _onEnd
                        ..onCancel = _onEnd;
                    }),
              },
            ),
          ),
        ),
        if (shown != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: CustomSingleChildLayout(
                  delegate: _BubbleLayout(_pointerY),
                  child: AnimatedOpacity(
                    opacity: _scrubbing && _label != null ? 1 : 0,
                    // In at once under the finger; out at the scrollbar's
                    // pace once it lifts.
                    duration: _scrubbing
                        ? Duration.zero
                        : FormMetrics.scrubberBubbleFade,
                    child: _Bubble(text: shown),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.menuSurface,
        borderRadius: BorderRadius.circular(FormMetrics.scrubberBubbleRadius),
      ),
      child: Padding(
        padding: FormMetrics.scrubberBubblePadding,
        child: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Puts the bubble [FormMetrics.scrubberBubbleInset] left of the lane,
/// centred on the pointer and kept inside the lane's height.
class _BubbleLayout extends SingleChildLayoutDelegate {
  const _BubbleLayout(this.pointerY);

  final double pointerY;

  static const double _reserved =
      FormMetrics.scrubberLaneWidth + FormMetrics.scrubberBubbleInset;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.max(0.0, constraints.maxWidth - _reserved),
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double top = (pointerY - childSize.height / 2).clamp(
      0.0,
      math.max(0.0, size.height - childSize.height),
    );
    return Offset(size.width - _reserved - childSize.width, top);
  }

  @override
  bool shouldRelayout(_BubbleLayout oldDelegate) =>
      oldDelegate.pointerY != pointerY;
}
