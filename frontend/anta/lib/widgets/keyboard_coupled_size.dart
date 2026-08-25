import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Animates the height of a child that resizes in a single frame, driving the
/// motion from an external progress signal when one is available and from its
/// own timed animation when it is not.
///
/// This exists instead of [AnimatedSize] because the calendar grid collapse is
/// caused by the soft keyboard, and the keyboard reports its own animation
/// frame by frame. Following it directly is what makes the two feel coupled
/// rather than merely simultaneous.
///
/// The child is always laid out at its natural height — it is never given a
/// bounded height, because `table_calendar` redistributes a bounded height
/// across its rows instead of showing fewer of them.
class KeyboardCoupledSize extends StatefulWidget {
  const KeyboardCoupledSize({
    super.key,
    required this.progress,
    this.duration = const Duration(milliseconds: 250),
    this.curve = Curves.easeOutCubic,
    this.child,
  });

  /// Progress of the driving animation, or `null` while nothing external is
  /// driving it — in which case [duration] and [curve] take over.
  final ValueListenable<double?> progress;

  final Duration duration;
  final Curve curve;
  final Widget? child;

  @override
  State<KeyboardCoupledSize> createState() => _KeyboardCoupledSizeState();
}

class _KeyboardCoupledSizeState extends State<KeyboardCoupledSize>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    return _KeyboardCoupledSize(
      vsync: this,
      progress: widget.progress,
      duration: widget.duration,
      curve: widget.curve,
      animationsEnabled: !MediaQuery.disableAnimationsOf(context),
      child: widget.child,
    );
  }
}

class _KeyboardCoupledSize extends SingleChildRenderObjectWidget {
  const _KeyboardCoupledSize({
    required this.vsync,
    required this.progress,
    required this.duration,
    required this.curve,
    required this.animationsEnabled,
    super.child,
  });

  final TickerProvider vsync;
  final ValueListenable<double?> progress;
  final Duration duration;
  final Curve curve;
  final bool animationsEnabled;

  @override
  RenderKeyboardCoupledSize createRenderObject(BuildContext context) {
    return RenderKeyboardCoupledSize(
      vsync: vsync,
      progress: progress,
      duration: duration,
      curve: curve,
      animationsEnabled: animationsEnabled,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderKeyboardCoupledSize renderObject,
  ) {
    renderObject
      ..vsync = vsync
      ..progress = progress
      ..duration = duration
      ..curve = curve
      ..animationsEnabled = animationsEnabled;
  }
}

class RenderKeyboardCoupledSize extends RenderShiftedBox {
  RenderKeyboardCoupledSize({
    required TickerProvider vsync,
    required ValueListenable<double?> progress,
    required Duration duration,
    required Curve curve,
    required bool animationsEnabled,
    RenderBox? child,
  }) : _vsync = vsync,
       _progress = progress,
       _curve = curve,
       _animationsEnabled = animationsEnabled,
       super(child) {
    _controller = AnimationController(vsync: vsync, duration: duration)
      // Starting the controller from inside `performLayout` republishes the
      // value synchronously, so the latch is what keeps that from marking
      // this render object dirty during its own layout.
      ..addListener(() {
        if (_controller.value != _lastValue) markNeedsLayout();
      })
      ..addStatusListener((status) {
        if (status.isCompleted) _endTransition();
      });
  }

  /// A coupled transition that stops receiving updates would otherwise freeze
  /// the grid at a partial height. The keyboard can stall (an IME panel swap,
  /// a paused activity) and a learned peak can overshoot the real one, so an
  /// idle coupled transition hands off to the timed animation.
  static const Duration _idleTimeout = Duration(milliseconds: 150);

  late final AnimationController _controller;
  Timer? _idleTimer;

  double _gap = 0;
  double _gapStart = 0;
  double? _lastValue;
  double _progressStart = 0;
  double? _lastChildHeight;
  bool _active = false;
  bool _coupled = false;
  bool _hasVisualOverflow = false;

  TickerProvider _vsync;
  set vsync(TickerProvider value) {
    if (value == _vsync) return;
    _vsync = value;
    _controller.resync(value);
  }

  ValueListenable<double?> _progress;
  set progress(ValueListenable<double?> value) {
    if (identical(value, _progress)) return;
    if (attached) _progress.removeListener(_handleProgressChanged);
    _progress = value;
    if (attached) _progress.addListener(_handleProgressChanged);
  }

  Duration get duration => _controller.duration!;
  set duration(Duration value) {
    if (value == _controller.duration) return;
    _controller.duration = value;
  }

  Curve _curve;
  set curve(Curve value) {
    if (value == _curve) return;
    _curve = value;
    if (_active && !_coupled) markNeedsLayout();
  }

  bool _animationsEnabled;
  set animationsEnabled(bool value) {
    if (value == _animationsEnabled) return;
    _animationsEnabled = value;
    if (!value && _active) {
      _endTransition();
      markNeedsLayout();
    }
  }

  @visibleForTesting
  bool get isCoupled => _active && _coupled;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(_handleProgressChanged);
    if (_active && !_coupled && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void detach() {
    _progress.removeListener(_handleProgressChanged);
    _idleTimer?.cancel();
    _idleTimer = null;
    _controller.stop();
    super.detach();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _clipRectLayer.layer = null;
    _controller.dispose();
    super.dispose();
  }

  void _handleProgressChanged() {
    if (!_active || !_coupled) return;
    if (_progress.value == null) {
      _handOffToTimed();
    } else {
      _restartIdleTimer();
      markNeedsLayout();
    }
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _handOffToTimed);
  }

  void _handOffToTimed() {
    if (!_active || !_coupled) return;
    _idleTimer?.cancel();
    _idleTimer = null;
    _gapStart = _gap;
    _coupled = false;
    _lastValue = 0.0;
    _controller.forward(from: 0);
  }

  void _beginTransition(double gapStart) {
    _idleTimer?.cancel();
    _idleTimer = null;
    _controller.stop();
    _gapStart = gapStart;
    _gap = gapStart;

    if (!_animationsEnabled || gapStart == 0) {
      _active = false;
      _coupled = false;
      _gap = 0;
      return;
    }

    _active = true;
    final external = _progress.value;
    if (external != null) {
      _coupled = true;
      _progressStart = external;
      _gap = _resolveGap();
      if (_active) _restartIdleTimer();
    } else {
      _coupled = false;
      _lastValue = 0.0;
      _controller.forward(from: 0);
    }
  }

  void _endTransition() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _active = false;
    _coupled = false;
    _gap = 0;
  }

  double _resolveGap() {
    final double t;
    if (_coupled) {
      final external = _progress.value;
      if (external == null) return _gap;
      final span = 1.0 - _progressStart;
      t = span <= 0
          ? 1.0
          : ((external - _progressStart) / span).clamp(0.0, 1.0);
    } else {
      t = _curve.transform(_controller.value);
    }
    if (t >= 1.0) {
      _endTransition();
      return 0;
    }
    return _gapStart * (1.0 - t);
  }

  @override
  void performLayout() {
    _lastValue = _controller.value;
    final constraints = this.constraints;
    final child = this.child;
    if (child == null) {
      _lastChildHeight = null;
      _hasVisualOverflow = false;
      size = constraints.smallest;
      return;
    }

    child.layout(
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ),
      parentUsesSize: true,
    );

    final childHeight = child.size.height;
    final previousHeight = _lastChildHeight;
    _lastChildHeight = childHeight;

    if (previousHeight != null && previousHeight != childHeight) {
      // Absorb the jump so the painted height is continuous across the frame
      // the child resized in, then let the gap relax back to zero.
      _beginTransition(previousHeight + _gap - childHeight);
    } else if (_active) {
      _gap = _resolveGap();
    }

    (child.parentData! as BoxParentData).offset = Offset.zero;
    size = constraints.constrain(Size(child.size.width, childHeight + _gap));
    _hasVisualOverflow = size.height < childHeight;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    final childSize = child.getDryLayout(
      BoxConstraints(
        minWidth: constraints.minWidth,
        maxWidth: constraints.maxWidth,
      ),
    );
    return constraints.constrain(
      Size(childSize.width, childSize.height + _gap),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null && _hasVisualOverflow) {
      _clipRectLayer.layer = context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        super.paint,
        oldLayer: _clipRectLayer.layer,
      );
    } else {
      _clipRectLayer.layer = null;
      super.paint(context, offset);
    }
  }

  final LayerHandle<ClipRectLayer> _clipRectLayer =
      LayerHandle<ClipRectLayer>();

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _hasVisualOverflow ? Offset.zero & size : null;
}
