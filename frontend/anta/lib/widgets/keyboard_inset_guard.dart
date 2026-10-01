import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../utils/keyboard_inset_trust.dart';

/// Keeps a keyboard inset that no keyboard accounts for out of the whole app.
///
/// Mounted once by `MaterialApp.builder`, above the navigator, so every page,
/// sheet, dialog and snackbar reads the corrected [MediaQuery] and none of
/// them needs a guard of its own. It has to sit there rather than in a page:
/// `Scaffold` shrinks its body by the same inset, so a page that only fixed
/// its own bottom bar would still lose a keyboard's height of list.
///
/// What it corrects is described on [KeyboardInsetTrust], which owns the
/// decision; this widget feeds it the three things it reads — the raw inset,
/// whether a focus node holds the focus, whether the app is resumed — and
/// republishes [MediaQueryData.viewInsets] and the [MediaQueryData.padding]
/// derived from it. While the platform value is believed the data passes
/// through untouched, object and all.
///
/// The [MediaQuery] is in the tree whether or not anything is being
/// corrected. Returning the bare child in the common case would change the
/// element at this slot the moment a stale inset appeared, and that remounts
/// the navigator with every route on it.
class KeyboardInsetGuard extends StatefulWidget {
  const KeyboardInsetGuard({super.key, required this.child, this.onSettled});

  /// How long a non-zero inset has to stand still before it counts as
  /// settled.
  ///
  /// Longer than the gap between two frames of a keyboard animation by a wide
  /// margin, and longer than the IME normally takes to start leaving after
  /// focus is dropped — the hide is a round trip through the system's input
  /// method service. A dismissal that starts later than this loses only its
  /// glide: the layout settles at once and the keyboard slides away over it.
  static const Duration settleWindow = Duration(milliseconds: 400);

  final Widget child;

  /// Called each time a non-zero raw inset has stood still for
  /// [settleWindow], whether or not it was dropped — and again, a window
  /// apart and [repeatLimit] times at most, for as long as the inset is
  /// being held back.
  ///
  /// The hook for asking the platform to send its real insets again: this
  /// widget only corrects what the app lays out against, and an inset that
  /// is stale while a field holds the focus is one it cannot tell from a
  /// keyboard.
  final VoidCallback? onSettled;

  /// How many times [onSettled] is repeated for an inset that stays held
  /// back.
  ///
  /// One request is normally the cure. It is lost when another stale
  /// delivery lands in the same frame as the answer — the two cancel out
  /// and nothing else would restart the window. Holding an inset back is
  /// proof that it is stale, so it is worth asking again; a few times and
  /// not forever, because a platform that cannot answer will not answer
  /// later either.
  static const int repeatLimit = 3;

  @override
  State<KeyboardInsetGuard> createState() => _KeyboardInsetGuardState();
}

class _KeyboardInsetGuardState extends State<KeyboardInsetGuard>
    with WidgetsBindingObserver {
  final KeyboardInsetTrust _trust = KeyboardInsetTrust();

  Timer? _settleTimer;
  int _repeatsLeft = KeyboardInsetGuard.repeatLimit;
  double _raw = 0;
  bool _resumed = true;

  /// The inputs of the last evaluation, so the settle window restarts only
  /// when one of them moved: a rebuild for an unrelated [MediaQuery] change
  /// must not keep a stale inset alive by resetting its clock.
  ({double raw, bool hasInputFocus, bool resumed})? _lastInputs;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _resumed = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_reevaluate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _raw = MediaQuery.viewInsetsOf(context).bottom;
    _evaluate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _reevaluate();
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    FocusManager.instance.removeListener(_reevaluate);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A scope holding the focus means nothing inside it does. Any other node
  /// counts, text field or not: reading a focused button as a possible input
  /// costs nothing while the platform value is right, whereas missing a real
  /// input would hide it behind its own keyboard.
  ///
  /// The premise is that an input gives up its connection when the focus
  /// moves from its node to a scope — true of `EditableText` and of the
  /// editor fork, both keyed on their node's `hasFocus`. A `FocusScope`
  /// placed *inside* an input's own `Focus` would break it: `hasFocus`
  /// counts descendants, so the keyboard would stay up under a scope.
  static bool _hasInputFocus() {
    final focus = FocusManager.instance.primaryFocus;
    return focus != null && focus is! FocusScopeNode;
  }

  void _evaluate() {
    final inputs = (
      raw: _raw,
      hasInputFocus: _hasInputFocus(),
      resumed: _resumed,
    );
    if (inputs == _lastInputs) return;
    _lastInputs = inputs;
    _trust.observe(
      raw: inputs.raw,
      hasInputFocus: inputs.hasInputFocus,
      appResumed: inputs.resumed,
    );
    _repeatsLeft = KeyboardInsetGuard.repeatLimit;
    _settleTimer?.cancel();
    _settleTimer = inputs.raw > 0
        ? Timer(KeyboardInsetGuard.settleWindow, _settle)
        : null;
  }

  /// For the two inputs that do not arrive through a rebuild.
  void _reevaluate() {
    if (!mounted) return;
    final before = _trust.trusted;
    _evaluate();
    if (_trust.trusted != before) setState(() {});
  }

  void _settle() {
    _settleTimer = null;
    if (!mounted) return;
    final before = _trust.trusted;
    _trust.settle(hasInputFocus: _hasInputFocus());
    if (_trust.trusted != before) setState(() {});
    widget.onSettled?.call();
    if (_trust.trusted < _raw && _repeatsLeft > 0) {
      _repeatsLeft--;
      _settleTimer = Timer(KeyboardInsetGuard.settleWindow, _settle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final trusted = _trust.trusted;
    return MediaQuery(
      data: trusted >= data.viewInsets.bottom
          ? data
          : data.copyWith(
              viewInsets: data.viewInsets.copyWith(bottom: trusted),
              // The engine derives `padding` as `viewPadding - viewInsets`,
              // floored at zero, so a keyboard inset that is not there has
              // also eaten the navigation-bar inset every `SafeArea` reads.
              padding: data.padding.copyWith(
                bottom: math.max(0.0, data.viewPadding.bottom - trusted),
              ),
            ),
      child: widget.child,
    );
  }
}
