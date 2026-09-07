import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../constants/app_bar_metrics.dart';

/// The leading control of every bar that has somewhere to go back to: the
/// back arrow and the drawer button side by side, split by a hairline.
///
/// The drawer is reachable three ways — this button, the edge swipe, and the
/// Settings row that ends every overflow menu — because the swipe shares the
/// left edge with the Android back gesture and loses often enough to be worth
/// a button.
///
/// The two halves stay two [IconButton]s rather than one wide target, so a
/// screen reader announces each on its own and [onBackLongPress] is offered
/// for the arrow alone.
class LeadingNavPair extends StatelessWidget {
  const LeadingNavPair({
    super.key,
    required this.onBack,
    required this.onMenu,
    this.onBackLongPress,
    this.backLongPressLabel,
  });

  /// The side of each half. Below the 48 dp minimum on purpose: the two of
  /// them sit in one corner, and 48 apiece would take the collapsed title
  /// down to a handful of characters on a 360 dp screen.
  static const double halfSize = 42;

  /// The gap between the arrow and the screen edge.
  static const double leadingPadding = 2;

  /// What a bar must reserve in `leadingWidth`: the padding, two halves and
  /// the hairline between them, which is exactly what the pair draws.
  static const double width = leadingPadding + halfSize + 1 + halfSize;

  /// The hairline between the halves.
  static const double dividerHeight = 20;

  final VoidCallback onBack;
  final VoidCallback onMenu;

  /// Receives the context of the arrow half, so a menu raised from here is
  /// anchored under the arrow rather than under the pair.
  final void Function(BuildContext anchorContext)? onBackLongPress;

  /// Names [onBackLongPress] for screen readers, which cannot long-press.
  /// Without it the long-press is offered to touch only.
  final String? backLongPressLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: leadingPadding),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildBack(),
          Container(
            width: 1,
            height: dividerHeight,
            color: colorScheme.outlineVariant,
          ),
          Builder(
            builder: (context) => _NavButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
              onPressed: onMenu,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBack() {
    return Builder(
      builder: (context) {
        final longPress = onBackLongPress;
        final button = _NavButton(
          icon: const BackButtonIcon(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onBack,
          onLongPress: longPress == null ? null : () => longPress(context),
        );
        final label = backLongPressLabel;
        if (longPress == null || label == null) return button;
        // Without the merge the annotation would settle on whichever node
        // encloses the button rather than on the button itself, and the
        // action would be offered for the drawer half as well.
        return MergeSemantics(
          child: Semantics(
            customSemanticsActions: {
              CustomSemanticsAction(label: label): () => longPress(context),
            },
            child: button,
          ),
        );
      },
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.onLongPress,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      onLongPress: onLongPress,
      iconSize: AppBarMetrics.glyphSize,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.standard,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      constraints: const BoxConstraints.tightFor(
        width: LeadingNavPair.halfSize,
        height: LeadingNavPair.halfSize,
      ),
    );
  }
}
