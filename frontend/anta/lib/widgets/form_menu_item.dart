import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_theme.dart';
import '../constants/form_metrics.dart';
import '../constants/row_metrics.dart';

class FormMenuItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  /// A `SemanticsIds` value for an item a device script picks by id.
  final String? identifier;

  /// False dims the item to 38 % in place and makes it inert, never hidden:
  /// a menu whose rows come and go with the state moves every row under the
  /// finger (the categories page's Move to top under a live query).
  final bool enabled;

  /// Glyph and label together — `error` on a destructive item. A disabled
  /// item draws without it: it reads as off, not as dangerous.
  final Color? color;

  const FormMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.identifier,
    this.enabled = true,
    this.color,
  });
}

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

/// The tallest a menu opened from [anchor] may be and still clear the status
/// bar and the bottom inset (the keyboard or the system bar, whichever is
/// taller) on the roomier side of the anchor. The route itself only keeps a
/// menu inside the screen's padding, which ignores the keyboard: a menu
/// taller than this, given it as its height cap, scrolls its rows instead of
/// spilling behind the keyboard. Read once, when the menu opens.
double formMenuMaxHeight(BuildContext anchor) {
  final overlayContext = Navigator.of(anchor).overlay?.context;
  final box = anchor.findRenderObject();
  final overlayBox = overlayContext?.findRenderObject();
  final media = overlayContext
      ?.getInheritedWidgetOfExactType<MediaQuery>()
      ?.data;
  if (media == null ||
      box is! RenderBox ||
      overlayBox is! RenderBox ||
      !box.attached ||
      !overlayBox.attached) {
    return double.infinity;
  }
  final rect = box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
  final bottomInset = math.max(
    media.viewInsets.bottom,
    media.viewPadding.bottom,
  );
  final above = rect.top - media.padding.top - _routeScreenMargin;
  final below =
      overlayBox.size.height - bottomInset - rect.bottom - _routeScreenMargin;
  return math.max(0, math.max(above, below));
}

/// The margin the popup route keeps between a menu and the screen's padding
/// (its private `_kMenuScreenPadding`).
const double _routeScreenMargin = 8;

/// The side of its anchor an open menu took, decided at its first layout and
/// kept for as long as it stays open. A row that drops focus to open its
/// menu watches the keyboard close under it: read live, the falling inset
/// would flip the menu from above the row to below it while the finger is
/// on its way to an item. One per open, never shared between two menus.
class FormMenuSide {
  bool? _below;
}

/// How a menu sits against its anchor horizontally.
///
/// A row's menu hangs from the row's right edge ([end]). A centred anchor —
/// the overview's period title — cannot use that rule: the popup layout
/// right-aligns a menu to an anchor right of the screen's centre, and a
/// title whose right edge leaves no room for the menu's width was pushed to
/// the screen's left edge, far from the title it opened from. [center] puts
/// the menu's centre under the anchor's, kept inside the screen's margins.
enum FormMenuAlignment { end, center }

/// Where a menu opened from [anchor] goes, for `showMenu`'s `positionBuilder`:
/// under the anchor while [menuHeight] fits above the screen's bottom inset
/// (the keyboard or the system bar, whichever is taller), else above it —
/// what `MenuAnchor`'s `bottomEnd` did.
///
/// With [FormMenuAlignment.end] the menu's right edge is on the anchor's: the
/// anchor rect is zero-width at the anchor's right edge, which is the
/// closeness rule the popup layout right-aligns a menu of any width to. With
/// [FormMenuAlignment.center] the rect is [menuWidth] wide, centred on the
/// anchor and clamped to `RowMetrics.groupInset` from the overlay's edges,
/// so the layout places a menu of that width exactly on it. The route still
/// clamps the result to the screen.
///
/// [anchor] is the row or the button the menu belongs to: in a form group
/// every row is stretched to the group's width, so a row's right edge is the
/// group's.
///
/// The route lays the menu out again on every frame its `MediaQuery`
/// changes; a [side] passed once per open keeps the side the first layout
/// chose (see [FormMenuSide]).
RelativeRect formMenuPosition(
  BuildContext anchor,
  BoxConstraints overlay, {
  required double menuHeight,
  FormMenuAlignment alignment = FormMenuAlignment.end,
  double menuWidth = FormMetrics.menuWidth,
  FormMenuSide? side,
}) {
  final overlaySize = overlay.biggest;
  final fallback = RelativeRect.fromSize(Rect.zero, overlaySize);
  if (!anchor.mounted) return fallback;
  final box = anchor.findRenderObject();
  final overlayContext = Navigator.of(anchor).overlay?.context;
  final overlayBox = overlayContext?.findRenderObject();
  if (overlayContext == null ||
      box is! RenderBox ||
      overlayBox is! RenderBox ||
      !box.attached ||
      !overlayBox.attached) {
    return fallback;
  }
  final rect = box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
  // The app's clearance rule: an open keyboard covers the bottom as surely
  // as the system bar does, and a menu below the markdown bar would open
  // behind it. Read from the overlay the menu is laid out in: a Scaffold
  // that resizes for the keyboard strips the inset from its body, where
  // the anchor sits, while the overlay still reaches behind the keyboard.
  // Read without subscribing: this runs in the route's layout, and a
  // dependency would tie the app's root overlay to every keyboard frame.
  final media = overlayContext
      .getInheritedWidgetOfExactType<MediaQuery>()
      ?.data;
  final bottomInset = media == null
      ? 0.0
      : math.max(media.viewInsets.bottom, media.viewPadding.bottom);
  final fitsNow = rect.bottom + menuHeight <= overlaySize.height - bottomInset;
  final fitsBelow = side == null ? fitsNow : (side._below ??= fitsNow);
  final top = fitsBelow ? rect.bottom : rect.top - menuHeight;
  final Rect menuRect;
  switch (alignment) {
    case FormMenuAlignment.end:
      menuRect = Rect.fromLTWH(rect.right, top, 0, 0);
    case FormMenuAlignment.center:
      const margin = RowMetrics.groupInset;
      final maxLeft = math.max(margin, overlaySize.width - menuWidth - margin);
      final left = (rect.center.dx - menuWidth / 2).clamp(margin, maxLeft);
      menuRect = Rect.fromLTWH(left, top, menuWidth, 0);
  }
  return RelativeRect.fromRect(menuRect, Offset.zero & overlaySize);
}

/// Opens the language's choice menu of [items] at [anchor] and completes
/// with the picked value, null when dismissed — `FormMenuRow`'s menu, for a
/// control that is not a row (the overview's period title).
///
/// [menuWidth] is the floor; a label that needs more widens the menu up to
/// `FormMetrics.menuMaxWidth` rather than breaking mid-word, which it did at
/// 200 % in German. With [FormMenuAlignment.end] the right edge stays on the
/// anchor's whatever the width; [FormMenuAlignment.center] centres the floor
/// under the anchor.
Future<T?> showFormMenu<T>(
  BuildContext anchor, {
  required List<FormMenuItem<T>> items,
  required T? selected,
  required double menuWidth,
  FormMenuAlignment alignment = FormMenuAlignment.end,
}) {
  final colorScheme = Theme.of(anchor).colorScheme;
  final side = FormMenuSide();
  return showMenu<T>(
    context: anchor,
    positionBuilder: (_, constraints) => formMenuPosition(
      anchor,
      constraints,
      menuHeight: formMenuHeight(items.length),
      alignment: alignment,
      menuWidth: menuWidth,
      side: side,
    ),
    color: colorScheme.menuSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(FormMetrics.menuRadius),
    ),
    menuPadding: FormMetrics.menuPadding,
    constraints: BoxConstraints(
      minWidth: menuWidth,
      maxWidth: FormMetrics.menuMaxWidth,
    ),
    items: [
      for (final item in items)
        FormMenuChoiceItem<T>(
          value: item.value,
          checked: item.value == selected,
          enabled: item.enabled,
          child: FormMenuItemRow(
            identifier: item.identifier,
            icon: item.icon,
            label: item.label,
            checked: item.value == selected,
            enabled: item.enabled,
            color: item.enabled ? item.color : null,
          ),
        ),
    ],
  );
}

/// Opens the language's menu of [items] standing on [anchor] — its bottom
/// edge [gap] above the anchor's top, centred on the anchor — and completes
/// with the picked value, null when dismissed.
///
/// `showMenu`'s route places a menu by its top edge and reveals it from
/// that edge, so a menu that must open above its anchor (the markdown bar's
/// heading menu, the keyboard below it) is placed from an estimate of its
/// height and grows down from the top of the screen toward the button,
/// stopping short of it wherever a scaled label wraps past the estimate.
/// This route's layout knows the menu's real size: the menu meets the
/// anchor at every text scale and locale, is capped to the room on its side
/// (its rows scroll past that), and grows out of the anchor as it opens.
///
/// Above is the preference because the anchor it was made for is a bar
/// standing on the keyboard. A host without one may lack the room there —
/// the settings page's preview bar scrolled up under the app bar — so when
/// the room above cannot hold the rows at text scale 1 the menu opens on
/// the roomier side, its top edge [gap] below the anchor's bottom. The side
/// is decided once per open, so a keyboard closing under the open menu
/// never flips it; the anchor is followed while the menu is open, so the
/// menu rides a bar the keyboard lets fall.
///
/// [requestFocus] is the caller's choice: on a touch screen a menu that
/// takes focus closes the keyboard of the editor it was opened from.
/// [menuWidth] is the floor, widened by a label up to
/// `FormMetrics.menuMaxWidth`, as [showFormMenu]'s is. [gap] is the space
/// kept between the menu's edge and the anchor's, for an anchor drawn
/// inside chrome the menu should not cut. Every other menu still opens
/// through [showFormMenu] or `showMenu`.
Future<T?> showFormMenuAbove<T>(
  BuildContext anchor, {
  required List<PopupMenuEntry<T>> items,
  required bool requestFocus,
  double menuWidth = FormMetrics.menuWidth,
  double gap = 0,
}) {
  final navigator = Navigator.of(anchor);
  final localizations = MaterialLocalizations.of(anchor);
  return navigator.push(
    _FormMenuAboveRoute<T>(
      anchor: anchor,
      items: items,
      menuWidth: menuWidth,
      gap: gap,
      barrierLabel: localizations.menuDismissLabel,
      // As `showMenu`: VoiceOver names a menu by its role alone.
      menuLabel: switch (defaultTargetPlatform) {
        TargetPlatform.iOS || TargetPlatform.macOS => null,
        TargetPlatform.android ||
        TargetPlatform.fuchsia ||
        TargetPlatform.linux ||
        TargetPlatform.windows => localizations.popupMenuLabel,
      },
      capturedThemes: InheritedTheme.capture(
        from: anchor,
        to: navigator.context,
      ),
      requestFocus: requestFocus,
    ),
  );
}

/// The popup route's own proportions of its animation: the menu fades in
/// over the first third and grows to its height over the first two, and
/// closing runs the whole curve within the first two thirds (its private
/// `_kMenuCloseIntervalEnd`).
const Curve _menuFadeCurve = Interval(0, 1 / 3);
const Curve _menuGrowCurve = Interval(0, 2 / 3);
const Curve _menuCloseCurve = Interval(0, 2 / 3);

class _FormMenuAboveRoute<T> extends PopupRoute<T> {
  _FormMenuAboveRoute({
    required this.anchor,
    required this.items,
    required this.menuWidth,
    required this.gap,
    required this.barrierLabel,
    required this.menuLabel,
    required this.capturedThemes,
    required super.requestFocus,
  }) : super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  final BuildContext anchor;
  final List<PopupMenuEntry<T>> items;
  final double menuWidth;
  final double gap;
  final String? menuLabel;
  final CapturedThemes capturedThemes;

  /// The anchor's rect in the overlay at the last read that could reach
  /// it, kept for the frames after the anchor leaves the tree.
  Rect? _anchorRect;

  /// The rect the last layout stood the menu on, which the follow compares
  /// the settled anchor against.
  Rect? _laidOutRect;

  /// Whether the menu opened below its anchor, decided at the first layout
  /// that could read the anchor and kept until it closes.
  bool? _below;

  bool _followScheduled = false;

  /// Bumped to lay the menu out again once the anchor settled somewhere
  /// the last layout did not see. The overlay lays this route out before
  /// a deeper dirty node of the page beneath, so on a keyboard frame the
  /// layout reads the anchor where it was a frame earlier. The page this
  /// route builds is cached by its scope, so neither `setState` nor
  /// `changedInternalState` reaches the layout; a listenable inside it does.
  final ValueNotifier<int> _relayout = ValueNotifier<int>(0);

  CurvedAnimation? _animation;

  @override
  Animation<double> createAnimation() => _animation ??= CurvedAnimation(
    parent: super.createAnimation(),
    curve: Curves.linear,
    reverseCurve: _menuCloseCurve,
  );

  @override
  Duration get transitionDuration => FormMetrics.menuTransition;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  final String barrierLabel;

  Rect? _readAnchorRect() {
    if (anchor.mounted) {
      final box = anchor.findRenderObject();
      final overlayBox = navigator?.overlay?.context.findRenderObject();
      if (box is RenderBox &&
          overlayBox is RenderBox &&
          box.attached &&
          overlayBox.attached &&
          box.hasSize) {
        _anchorRect =
            box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
      }
    }
    return _anchorRect;
  }

  /// Above while the room there holds the rows at text scale 1, else the
  /// roomier side.
  bool _opensBelow(Rect anchor, Size overlay, EdgeInsets bounds) {
    final above = anchor.top - gap - bounds.top;
    if (above >= formMenuHeight(items.length)) return false;
    final below = overlay.height - bounds.bottom - anchor.bottom - gap;
    return below > above;
  }

  /// Once the frame is laid out the anchor is where it settled: a menu laid
  /// out against an older rect is laid out again, and only then, so the
  /// follow stops one frame after the anchor does and never loops.
  void _scheduleFollow() {
    if (_followScheduled) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (!isActive) return;
      final laidOut = _laidOutRect;
      if (_readAnchorRect() != laidOut) _relayout.value++;
    });
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // Subscribed to the whole MediaQuery, as the popup route is: a keyboard
    // frame moves the anchor without touching the padding, and each one
    // must lay the menu out again against the anchor's new rect.
    final media = MediaQuery.of(context);
    // The screen's padding plus the route's margin, the clearance rule's
    // bottom inset (the keyboard or the system bar, whichever is taller),
    // and the language's inset at the sides.
    final bounds = EdgeInsets.fromLTRB(
      media.padding.left + RowMetrics.groupInset,
      media.padding.top + _routeScreenMargin,
      media.padding.right + RowMetrics.groupInset,
      math.max(media.viewInsets.bottom, media.viewPadding.bottom) +
          _routeScreenMargin,
    );
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: ValueListenableBuilder<int>(
        valueListenable: _relayout,
        builder: (context, _, _) => LayoutBuilder(
          builder: (context, constraints) {
            final overlay = constraints.biggest;
            final read = _readAnchorRect();
            final anchor =
                read ?? Rect.fromLTWH(overlay.width / 2, overlay.height, 0, 0);
            final below = read == null
                ? false
                : _below ??= _opensBelow(read, overlay, bounds);
            _laidOutRect = read;
            _scheduleFollow();
            return CustomSingleChildLayout(
              delegate: _FormMenuAboveLayout(
                anchor: anchor,
                bounds: bounds,
                below: below,
                gap: gap,
                menuWidth: menuWidth,
              ),
              child: capturedThemes.wrap(
                _FormMenuAbove<T>(route: this, below: below),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _relayout.dispose();
    _animation?.dispose();
    super.dispose();
  }
}

/// Stands the menu on its anchor with the size it has this frame, so the
/// growing menu's edge stays on the anchor while the far edge moves away.
class _FormMenuAboveLayout extends SingleChildLayoutDelegate {
  _FormMenuAboveLayout({
    required this.anchor,
    required this.bounds,
    required this.below,
    required this.gap,
    required this.menuWidth,
  });

  final Rect anchor;

  /// How far the menu keeps from each edge of the overlay.
  final EdgeInsets bounds;

  final bool below;
  final double gap;
  final double menuWidth;

  /// The top of a menu below the anchor, kept on screen when the anchor's
  /// bottom has scrolled under the status bar.
  double get _belowTop => math.max(bounds.top, anchor.bottom + gap);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxWidth = math.min(
      FormMetrics.menuMaxWidth,
      math.max(0.0, constraints.maxWidth - bounds.horizontal),
    );
    final room = below
        ? constraints.maxHeight - bounds.bottom - _belowTop
        : anchor.top - gap - bounds.top;
    return BoxConstraints(
      minWidth: math.min(menuWidth, maxWidth),
      maxWidth: maxWidth,
      maxHeight: math.max(0.0, room),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = math.max(
      bounds.left,
      size.width - childSize.width - bounds.right,
    );
    return Offset(
      (anchor.center.dx - childSize.width / 2).clamp(bounds.left, maxLeft),
      below
          ? _belowTop
          : math.max(bounds.top, anchor.top - gap - childSize.height),
    );
  }

  @override
  bool shouldRelayout(_FormMenuAboveLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      bounds != oldDelegate.bounds ||
      below != oldDelegate.below ||
      gap != oldDelegate.gap ||
      menuWidth != oldDelegate.menuWidth;
}

/// The menu's surface and the reveal: the rows sit where they will settle
/// and the surface's far edge moves away from the anchor over them, so
/// nothing slides under a finger on its way to an item.
class _FormMenuAbove<T> extends StatelessWidget {
  const _FormMenuAbove({required this.route, required this.below});

  final _FormMenuAboveRoute<T> route;
  final bool below;

  @override
  Widget build(BuildContext context) {
    final animation = route.animation!;
    return FadeTransition(
      opacity: animation.drive(CurveTween(curve: _menuFadeCurve)),
      child: IntrinsicWidth(
        stepWidth: FormMetrics.menuWidthStep,
        child: Semantics(
          role: SemanticsRole.menu,
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: route.menuLabel,
          child: Material(
            color: Theme.of(context).colorScheme.menuSurface,
            elevation: AppTheme.menuElevation,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FormMetrics.menuRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, rows) => Align(
                alignment: below ? Alignment.topCenter : Alignment.bottomCenter,
                heightFactor: _menuGrowCurve.transform(animation.value),
                child: rows,
              ),
              child: SingleChildScrollView(
                padding: FormMetrics.menuPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: route.items,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
