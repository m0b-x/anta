import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../constants/form_metrics.dart';

/// One choice of a group only one of which is on — a page, a grid format, a
/// priority — announced as a radio item with its checked state rather than as
/// a plain button.
///
/// The one menu item of the language, shared by the calendar's header menus
/// and by `FormMenuRow`: a `MenuAnchor` item exposes no semantics node on
/// iOS, so every menu here is a popup route built from this item, and a
/// second copy of the anatomy would let the two drift.
class FormMenuChoiceItem<T> extends PopupMenuItem<T> {
  const FormMenuChoiceItem({
    super.key,
    required super.value,
    required this.checked,
    super.enabled,
    required super.child,
  }) : super(height: FormMetrics.menuRowHeight);

  final bool checked;

  @override
  PopupMenuItemState<T, FormMenuChoiceItem<T>> createState() =>
      _FormMenuChoiceItemState<T>();
}

class _FormMenuChoiceItemState<T>
    extends PopupMenuItemState<T, FormMenuChoiceItem<T>> {
  @override
  Widget buildSemantics({required Widget child}) {
    return Semantics(
      role: SemanticsRole.menuItemRadio,
      enabled: widget.enabled,
      checked: widget.checked,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: child,
    );
  }
}

/// The height of a menu of [itemCount] rows at text scale 1 — what the flip
/// decision of [formMenuPosition] assumes. A label that wraps at a larger
/// scale makes the menu taller; the route then shifts it up to stay on
/// screen, so the estimate never lets it spill.
double formMenuHeight(int itemCount) =>
    itemCount * FormMetrics.menuRowHeight + FormMetrics.menuPadding.vertical;

/// Where a menu opened from [anchor] goes, for `showMenu`'s `positionBuilder`:
/// its right edge on the anchor's, under the anchor while [menuHeight] fits
/// above the screen's bottom inset, else above it — what `MenuAnchor`'s
/// `bottomEnd` did. The anchor rect is zero-width at the anchor's right edge,
/// which is the closeness rule the popup layout right-aligns a menu of any
/// width to; the route still clamps the result to the screen.
///
/// [anchor] is the row or the button the menu belongs to: in a form group
/// every row is stretched to the group's width, so a row's right edge is the
/// group's.
RelativeRect formMenuPosition(
  BuildContext anchor,
  BoxConstraints overlay, {
  required double menuHeight,
}) {
  final overlaySize = overlay.biggest;
  final fallback = RelativeRect.fromSize(Rect.zero, overlaySize);
  if (!anchor.mounted) return fallback;
  final box = anchor.findRenderObject();
  final overlayBox = Navigator.of(anchor).overlay?.context.findRenderObject();
  if (box is! RenderBox ||
      overlayBox is! RenderBox ||
      !box.attached ||
      !overlayBox.attached) {
    return fallback;
  }
  final rect = box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
  final bottomInset = MediaQuery.viewPaddingOf(anchor).bottom;
  final fitsBelow = rect.bottom + menuHeight <= overlaySize.height - bottomInset;
  final top = fitsBelow ? rect.bottom : rect.top - menuHeight;
  return RelativeRect.fromRect(
    Rect.fromLTWH(rect.right, top, 0, 0),
    Offset.zero & overlaySize,
  );
}

/// A row in the anatomy of the app's overflow menus: a 20 px glyph in
/// `onSurfaceVariant`, the theme's 15/400 label and, on the current choice, a
/// trailing check in `primary`.
///
/// The label wraps as far as it needs to: at a large text scale a German or
/// Romanian label outgrows even the 280 dp cap ("Ereignisse exportieren
/// (.ics)" takes three lines at 200 %), and a menu item's height is a
/// minimum, so only that row grows instead of its words being cut off.
///
/// A disabled row's label is dimmed here because the theme's menu label
/// style is state-independent; its glyph is dimmed by the menu item itself.
///
/// The [identifier] lands on the item's own node: `PopupMenuItem` merges its
/// subtree, so the id, the label, the radio role and the checked state are one
/// announcement and one target.
class FormMenuItemRow extends StatelessWidget {
  const FormMenuItemRow({
    super.key,
    this.identifier,
    this.icon,
    required this.label,
    this.checked = false,
    this.enabled = true,
    this.color,
  });

  final String? identifier;
  final IconData? icon;
  final String label;
  final bool checked;
  final bool enabled;

  /// Glyph and label together — `error` on a destructive item (a preset's
  /// Delete). Null keeps the anatomy's own colours.
  final Color? color;

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelColor = enabled
        ? color
        : colorScheme.onSurface.withValues(alpha: FormMetrics.disabledOpacity);
    final row = Row(
      children: [
        if (icon case final glyph?) ...[
          Icon(
            glyph,
            size: FormMetrics.menuIconSize,
            color: color ?? colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: _gap),
        ],
        Expanded(
          child: Text(
            label,
            style: labelColor == null ? null : TextStyle(color: labelColor),
          ),
        ),
        if (checked) ...[
          const SizedBox(width: _gap),
          Icon(
            Icons.check_rounded,
            size: FormMetrics.menuIconSize,
            color: colorScheme.primary,
          ),
        ],
      ],
    );
    if (identifier case final id?) {
      return Semantics(identifier: id, child: row);
    }
    return row;
  }
}
