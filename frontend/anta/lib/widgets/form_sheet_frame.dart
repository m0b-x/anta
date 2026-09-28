import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';

/// The form sheet's shell — the event editor's, and every form sheet after
/// it (`docs/calendar-language-tier-1-roadmap.md`, D15): the ground and the
/// top radius, the dirty guard's one entry point, and the sheet's own drag.
/// Hoisted out of the editor so the next sheet with typed text does not grow
/// a copy of this chrome.
///
/// A form sheet owns its drag because `showModalBottomSheet`'s own drag pops
/// the route without consulting `PopScope`: the route opens with
/// `enableDrag: false` and the handle and header ([chrome]) are the drag
/// surface here. The sheet follows the finger; a fling past
/// [FormMetrics.sheetDismissVelocity] or a drag past
/// [FormMetrics.sheetDismissFraction] of the sheet's height dismisses —
/// straight through [onDismiss] while [isClean], else
/// after a snap back through [onLeave], the same guard that ✕, back, the
/// system back gesture and the barrier reach through the `PopScope` — and
/// anything shorter snaps back over [FormMetrics.sheetSnapBackDuration].
class FormSheetFrame extends StatefulWidget {
  /// The drag surface: a `FormSheetHandle` over a `FormSheetHeader`.
  final Widget chrome;

  /// What follows the chrome in the sheet's column — the `Expanded` scroll
  /// view and any fixed footer, a docked bar included — laid out as the
  /// column's remaining children rather than nested, so a footer sits under
  /// the scroll view exactly as it did before the hoist.
  final List<Widget> body;

  /// Asked to leave: ✕, back, the system back gesture, the barrier and a
  /// dismissing drag on a dirty form. It owns the guard and its own
  /// re-entrancy latch; the frame only awaits it, and a drag that ends while
  /// it is in flight snaps back instead of asking again.
  final Future<void> Function() onLeave;

  /// Whether a dismissing drag may pop without asking.
  final bool Function() isClean;

  /// Pops the route with its "cancelled" result — the clean drag's exit.
  final VoidCallback onDismiss;

  const FormSheetFrame({
    super.key,
    required this.chrome,
    required this.body,
    required this.onLeave,
    required this.isClean,
    required this.onDismiss,
  });

  @override
  State<FormSheetFrame> createState() => _FormSheetFrameState();
}

class _FormSheetFrameState extends State<FormSheetFrame>
    with SingleTickerProviderStateMixin {
  /// The sheet's own box, which the dismiss threshold measures; before its
  /// first layout the fraction of the screen a form sheet takes stands in.
  final GlobalKey _sheetKey = GlobalKey();
  final ValueNotifier<double> _dragOffset = ValueNotifier<double>(0);
  late final AnimationController _snapBack;
  double _snapFrom = 0;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _snapBack = AnimationController(
      vsync: this,
      duration: FormMetrics.sheetSnapBackDuration,
    )..addListener(_onSnapBackTick);
  }

  @override
  void dispose() {
    _snapBack.dispose();
    _dragOffset.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    _leaving = true;
    try {
      await widget.onLeave();
    } finally {
      _leaving = false;
    }
  }

  void _onDragStart(DragStartDetails details) {
    _snapBack.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragOffset.value = math.max(0, _dragOffset.value + details.delta.dy);
  }

  void _onDragCancel() {
    _animateSnapBack();
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (_leaving) {
      await _animateSnapBack();
      return;
    }
    final velocity =
        details.primaryVelocity ?? details.velocity.pixelsPerSecond.dy;
    final height =
        _sheetKey.currentContext?.size?.height ??
        MediaQuery.sizeOf(context).height * FormMetrics.sheetHeightFactor;
    final dismiss =
        velocity > FormMetrics.sheetDismissVelocity ||
        _dragOffset.value > height * FormMetrics.sheetDismissFraction;
    if (!dismiss) {
      await _animateSnapBack();
      return;
    }
    if (widget.isClean()) {
      widget.onDismiss();
      return;
    }
    // The guard's dialog opens over a sheet at rest, not one hanging a
    // quarter of the way down the screen.
    await _animateSnapBack();
    if (!mounted) return;
    await _leave();
  }

  Future<void> _animateSnapBack() async {
    _snapFrom = _dragOffset.value;
    if (_snapFrom == 0) return;
    try {
      await _snapBack.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
  }

  void _onSnapBackTick() {
    final progress = Curves.easeOut.transform(_snapBack.value);
    _dragOffset.value = _snapFrom * (1 - progress);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _leave();
      },
      child: ValueListenableBuilder<double>(
        valueListenable: _dragOffset,
        builder: (context, offset, child) =>
            Transform.translate(offset: Offset(0, offset), child: child),
        child: Material(
          key: _sheetKey,
          color: colorScheme.pageGround,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(FormMetrics.sheetRadius),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Excluded from semantics: a gesture detector with vertical
              // drag callbacks otherwise announces them as scroll actions,
              // and with the header's title as the only label under it the
              // whole chrome read as one `Scroll "Edit event"` node on the
              // device — the title lost its own node, and the sheet claimed
              // to scroll. The drag is a pointer-only gesture; ✕ and back
              // are the accessible ways out.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onVerticalDragStart: _onDragStart,
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: _onDragEnd,
                onVerticalDragCancel: _onDragCancel,
                child: widget.chrome,
              ),
              ...widget.body,
            ],
          ),
        ),
      ),
    );
  }
}
