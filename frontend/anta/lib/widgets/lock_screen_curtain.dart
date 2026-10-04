import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/lock_screen_state.dart';

/// Hides the app while it is on top of a locked phone with no alarm page to
/// show for it.
///
/// Mounted once by `MaterialApp.builder` in `main.dart`, above the navigator,
/// so it covers every route, sheet and dialog at once. It never unmounts or
/// moves [child]: the navigator keeps its whole stack under the cover, which
/// is the point — the user unlocks and is exactly where they were.
///
/// The cover is opaque, takes every touch and drops the tree out of
/// accessibility, because all three are ways of reading a note off a locked
/// phone. A touch on it also asks the platform again, so a cover that outlived
/// an unlock nobody reported lifts at the first tap instead of staying.
class LockScreenCurtain extends StatefulWidget {
  const LockScreenCurtain({super.key, required this.child, this.state});

  final Widget child;

  /// The state to follow. Defaults to the app-wide one; a test passes its own.
  final LockScreenState? state;

  @override
  State<LockScreenCurtain> createState() => _LockScreenCurtainState();
}

class _LockScreenCurtainState extends State<LockScreenCurtain> {
  LockScreenState get _state => widget.state ?? LockScreenState.instance;

  @override
  void initState() {
    super.initState();
    _state.changes.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(LockScreenCurtain oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.state ?? LockScreenState.instance;
    if (identical(previous, _state)) return;
    previous.changes.removeListener(_onChanged);
    _state.changes.addListener(_onChanged);
  }

  @override
  void dispose() {
    _state.changes.removeListener(_onChanged);
    super.dispose();
  }

  /// The alarm page reports itself from inside the frame — mounting is a
  /// build, and a route removed outright is disposed while the tree is locked
  /// — and a `setState` there throws and is swallowed by the notifier, leaving
  /// the cover in whatever state it had. That is the one failure this widget
  /// cannot have, so a change that lands mid-frame is applied right after it.
  void _onChanged() {
    if (!mounted) return;
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    scheduler.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final covered = _state.mustCover;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: covered,
          child: AbsorbPointer(absorbing: covered, child: widget.child),
        ),
        if (covered)
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _state.refresh(),
            child: ColoredBox(color: Theme.of(context).colorScheme.surface),
          ),
      ],
    );
  }
}
