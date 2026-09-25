import 'package:flutter/material.dart';

class ValueChangeHighlight extends StatefulWidget {
  final Object? value;
  final BorderRadius borderRadius;
  final Widget child;

  const ValueChangeHighlight({
    super.key,
    required this.value,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<ValueChangeHighlight> createState() => _ValueChangeHighlightState();
}

class _ValueChangeHighlightState extends State<ValueChangeHighlight>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 1100);
  static const Curve _fade = Interval(0.3, 1, curve: Curves.easeOut);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
    value: 1,
  );
  bool _animationsDisabled = false;

  @override
  void didUpdateWidget(ValueChangeHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_animationsDisabled) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final accent = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final strength = 1 - _fade.transform(_controller.value);
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: strength == 0
              ? const BoxDecoration()
              : BoxDecoration(
                  borderRadius: widget.borderRadius,
                  color: accent.withValues(alpha: 0.12 * strength),
                  border: Border.all(
                    color: accent.withValues(alpha: strength),
                    width: 2,
                  ),
                ),
          child: child,
        );
      },
    );
  }
}
