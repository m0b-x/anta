import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../constants/app_bar_metrics.dart';
import '../constants/app_colors.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../services/auto_save_service.dart';
import '../services/app_navigator.dart';
import 'automation_id.dart';
import 'leading_nav_pair.dart';
import 'search_field_app_bar.dart';

enum AppBarStyle { main, settings }

class UnifiedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final Widget? title;
  final List<Widget>? actions;
  final double? elevation;
  final double? toolbarHeight;
  final double? leadingWidth;
  final AppBarStyle style;

  /// What the main-style bar sits on, for a host that owns a ground of its
  /// own. Supplying it also switches the scroll tint off, so the bar cannot
  /// drift off its page's colour the moment the list moves under it. Null
  /// leaves the bar on the theme's default surface, which is what the editor
  /// wants.
  final Color? backgroundColor;

  /// Set by a settings bar whose [title] carries its own heading semantics:
  /// `AppBar`'s wrapper would otherwise stay behind as a second, unlabelled
  /// heading.
  final bool excludeHeaderSemantics;

  const UnifiedAppBar({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.elevation,
    this.toolbarHeight,
    this.leadingWidth,
    this.backgroundColor,
    this.style = AppBarStyle.main,
  }) : excludeHeaderSemantics = false;

  const UnifiedAppBar.main({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.elevation,
    this.toolbarHeight,
    this.leadingWidth,
    this.backgroundColor,
  }) : style = AppBarStyle.main,
       excludeHeaderSemantics = false;

  /// The settings family's bar: flat on [backgroundColor], or on
  /// `pageGround` — the ground the settings kit's list paints — when none is
  /// given.
  const UnifiedAppBar.settings({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.elevation,
    this.toolbarHeight,
    this.leadingWidth,
    this.backgroundColor,
    this.excludeHeaderSemantics = false,
  }) : style = AppBarStyle.settings;

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight ?? AppBarMetrics.toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // The browser's bar is a `SliverAppBar.large` that a gradient cannot
    // follow across 116 px of collapse, and the editor's bar is the shape it
    // settles into — so every bar is flat Material 3: the main style on the
    // surface unless its host hands over a ground of its own, the settings
    // style on the settings kit's `pageGround`. A ground also switches the
    // scrolled-under tint off, so the bar cannot drift off its page's colour.
    final ground =
        backgroundColor ??
        (style == AppBarStyle.settings ? colorScheme.pageGround : null);
    return AppBar(
      leading: leading,
      leadingWidth: leadingWidth,
      automaticallyImplyLeading: automaticallyImplyLeading,
      toolbarHeight: preferredSize.height,
      actionsIconTheme: IconThemeData(
        size: AppBarMetrics.glyphSize,
        color: colorScheme.onSurface,
      ),
      title: title,
      excludeHeaderSemantics: excludeHeaderSemantics,
      actions: actions,
      elevation: elevation,
      backgroundColor: ground,
      surfaceTintColor: ground == null ? null : Colors.transparent,
      scrolledUnderElevation: ground == null ? null : 0,
    );
  }
}

class NoteAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool hasChanges;

  /// Read-only by contract: the bar only listens. Typed as a
  /// [ValueListenable] so a coordinator can expose its status without
  /// handing the widget tree a notifier it could write to.
  final ValueListenable<SaveStatus>? saveStatusNotifier;
  final List<Widget>? actions;
  final VoidCallback? onBackPressed;

  /// Defaults to the enclosing [Scaffold]'s drawer, which is the editor's own.
  final VoidCallback? onMenuPressed;
  final VoidCallback? onTitleTap;

  const NoteAppBar({
    super.key,
    required this.title,
    this.hasChanges = false,
    this.saveStatusNotifier,
    this.actions,
    this.onBackPressed,
    this.onMenuPressed,
    this.onTitleTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(AppBarMetrics.toolbarHeight);

  @override
  Widget build(BuildContext context) {
    return UnifiedAppBar.main(
      automaticallyImplyLeading: false,
      toolbarHeight: AppBarMetrics.toolbarHeight,
      backgroundColor: Theme.of(context).colorScheme.pageGround,
      leadingWidth: LeadingNavPair.width,
      leading: Builder(
        builder: (context) => LeadingNavPair(
          onBack: onBackPressed ?? () => AppNavigator.maybePop(context),
          onMenu: onMenuPressed ?? () => Scaffold.of(context).openDrawer(),
        ),
      ),
      // The title is the rename button, and says so to a screen reader.
      title: Semantics(
        button: onTitleTap != null,
        label: onTitleTap == null
            ? null
            : AppLocalizations.of(context)!.editTitle,
        child: GestureDetector(
          onTap: onTitleTap,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppBarMetrics.titleFontSize,
                    fontWeight: AppBarMetrics.titleFontWeight,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _SaveStatusIndicator(
                hasChanges: hasChanges,
                saveStatusNotifier: saveStatusNotifier,
              ),
            ],
          ),
        ),
      ),
      actions: actions,
    );
  }
}

/// Animated save-status chip shown next to the note title.
///
/// Listens to the [SaveStatus] value notifier and cross-fades between
/// states.  Keeps the widget tree lightweight – only rebuilds this subtree
/// when the status actually changes.
///
/// The slot is a fixed square whatever the status: an 8 dp dot becoming a
/// 14 dp cloud would otherwise re-measure the title beside it and reflow a
/// long name mid-keystroke.
class _SaveStatusIndicator extends StatelessWidget {
  final bool hasChanges;
  final ValueListenable<SaveStatus>? saveStatusNotifier;

  /// Addresses the slot from a test that measures whether the title's room
  /// is really constant.
  static const Key slotKey = ValueKey('note-app-bar-save-status');

  const _SaveStatusIndicator({
    required this.hasChanges,
    this.saveStatusNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final notifier = saveStatusNotifier;
    if (notifier == null) {
      return _spoken(
        context,
        hasChanges ? SaveStatus.unsaved : null,
        _slot(hasChanges ? _dot(context) : const SizedBox.shrink()),
      );
    }

    return ValueListenableBuilder<SaveStatus>(
      valueListenable: notifier,
      builder: (context, status, _) {
        final effective = hasChanges && status == SaveStatus.saved
            ? SaveStatus.unsaved
            : status;
        return _spoken(
          context,
          effective,
          _slot(
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              layoutBuilder: (currentChild, previousChildren) {
                final allChildren = [...previousChildren, ?currentChild];
                final seenKeys = <Key>{};
                final uniqueChildren = <Widget>[];

                for (final child in allChildren.reversed) {
                  final key = child.key;
                  if (key != null && !seenKeys.contains(key)) {
                    seenKeys.add(key);
                    uniqueChildren.insert(0, child);
                  } else if (key == null) {
                    uniqueChildren.insert(0, child);
                  }
                }

                return Stack(
                  fit: StackFit.passthrough,
                  alignment: Alignment.center,
                  children: uniqueChildren,
                );
              },
              child: _buildIcon(context, effective),
            ),
          ),
        );
      },
    );
  }

  /// The glyph's spoken state — a glyph alone says nothing to TalkBack.
  /// Only a failed save is a live region: the others change on every
  /// pause in typing and would interrupt the reader each time.
  Widget _spoken(BuildContext context, SaveStatus? status, Widget child) {
    if (status == null) return child;
    final l10n = AppLocalizations.of(context)!;
    final label = switch (status) {
      SaveStatus.saved => l10n.saveStateSaved,
      SaveStatus.unsaved => l10n.saveStateUnsaved,
      SaveStatus.saving => l10n.saveStateSaving,
      SaveStatus.error => l10n.saveStateError,
    };
    return Semantics(
      container: true,
      label: label,
      liveRegion: status == SaveStatus.error,
      child: ExcludeSemantics(child: child),
    );
  }

  Widget _slot(Widget child) {
    return Padding(
      key: slotKey,
      padding: const EdgeInsets.only(left: AppBarMetrics.saveStatusGap),
      child: SizedBox.square(
        dimension: AppBarMetrics.saveStatusSlotSize,
        child: Center(child: child),
      ),
    );
  }

  Widget _buildIcon(BuildContext context, SaveStatus status) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (status) {
      case SaveStatus.saved:
        return _icon(
          key: const ValueKey('saved'),
          icon: Icons.cloud_done_outlined,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        );
      case SaveStatus.unsaved:
        return _dot(context);
      case SaveStatus.saving:
        return _icon(
          key: const ValueKey('saving'),
          icon: Icons.sync,
          color: colorScheme.tertiary,
          spinning: true,
        );
      case SaveStatus.error:
        return _icon(
          key: const ValueKey('error'),
          icon: Icons.error_outline,
          color: colorScheme.error,
        );
    }
  }

  Widget _icon({
    required Key key,
    required IconData icon,
    required Color color,
    double size = AppBarMetrics.saveStatusSlotSize,
    bool spinning = false,
  }) {
    if (spinning) {
      return KeyedSubtree(
        key: key,
        child: _SpinningIcon(icon: icon, size: size, color: color),
      );
    }
    return Icon(icon, key: key, size: size, color: color);
  }

  Widget _dot(BuildContext context) {
    return Container(
      key: const ValueKey('dot'),
      width: AppBarMetrics.saveStatusDotSize,
      height: AppBarMetrics.saveStatusDotSize,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// A continuously rotating icon used for the "Saving…" state.
class _SpinningIcon extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color color;

  const _SpinningIcon({
    required this.icon,
    required this.size,
    required this.color,
  });

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(widget.icon, size: widget.size, color: widget.color),
    );
  }
}

class SettingsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;

  /// Off by default: a settings-family page carries no drawer and draws the
  /// arrow alone, so back always lands on the route beneath (D3).
  final bool showMenuButton;

  /// The page's own ground, for a page that paints one; null puts the bar
  /// on `pageGround`, the settings kit's ground ([UnifiedAppBar.settings]).
  final Color? backgroundColor;

  /// A `SemanticsIds` entry put on the title, so a device script can tell
  /// which page is on top without reading translated text.
  final String? identifier;

  const SettingsAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showMenuButton = false,
    this.backgroundColor,
    this.identifier,
  });

  @override
  Size get preferredSize => const Size.fromHeight(AppBarMetrics.toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold.maybeOf(context);
    final drawsPair = showMenuButton && (scaffold?.hasDrawer ?? false);
    final Widget titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: AppBarMetrics.titleFontSize,
        fontWeight: AppBarMetrics.titleFontWeight,
      ),
    );
    final id = identifier;
    return UnifiedAppBar.settings(
      backgroundColor: backgroundColor,
      toolbarHeight: AppBarMetrics.toolbarHeight,
      leadingWidth: drawsPair ? LeadingNavPair.width : null,
      leading: showMenuButton
          ? _buildLeading(context, scaffold)
          : _impliedBack(context, scaffold),
      title: id == null ? titleText : _identifiedTitle(id, titleText),
      excludeHeaderSemantics: id != null,
      actions: actions,
    );
  }

  /// An identifier always starts a semantics node of its own, so the label
  /// would leave the node `AppBar` marks as the heading that names the route;
  /// this node carries both flags instead, and the bar drops its own wrapper
  /// (`excludeHeaderSemantics`) so no unlabelled heading is left beside it.
  /// `AppBar` names routes everywhere but on Apple platforms, and so does
  /// this. The level is what Android reads (its bridge marks a heading from
  /// `headingLevel` alone) and the flag what VoiceOver reads; level 1 puts
  /// the kit's level-2 section headers under the page's name.
  static Widget _identifiedTitle(String id, Widget text) {
    final namesRoute = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => null,
      _ => true,
    };
    return Semantics(
      identifier: id,
      header: true,
      headingLevel: 1,
      namesRoute: namesRoute,
      child: text,
    );
  }

  /// The pair needs a drawer to open. A settings-family page pushed onto a
  /// `Scaffold` without one — the per-note pages are the four — draws the
  /// arrow alone rather than a button that does nothing.
  Widget _buildLeading(BuildContext context, ScaffoldState? scaffold) {
    void back() => AppNavigator.pop(context);
    if (scaffold == null || !scaffold.hasDrawer) {
      return IconButton(
        icon: const BackButtonIcon(),
        iconSize: AppBarMetrics.glyphSize,
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: back,
      );
    }
    return LeadingNavPair(onBack: back, onMenu: scaffold.openDrawer);
  }

  /// The arrow `AppBar` would imply for a page without the menu button, drawn
  /// here so it carries [SemanticsIds.navBack] — a device script then leaves
  /// every settings page by one id. Only where `AppBar` would draw a back
  /// arrow (a drawer implies its menu button, a full-screen dialog its close
  /// button, and both stay `AppBar`'s); it pops `null`, as that arrow does.
  static Widget? _impliedBack(BuildContext context, ScaffoldState? scaffold) {
    if (scaffold?.hasDrawer ?? false) return null;
    final route = ModalRoute.of(context);
    if (!(route?.impliesAppBarDismissal ?? false)) return null;
    if (route is PageRoute && route.fullscreenDialog) return null;
    return const AutomationId(
      identifier: SemanticsIds.navBack,
      child: BackButton(),
    );
  }
}

/// The standalone search route's bar.
///
/// Field and clear button are [SearchBarField] and [SearchBarClearAction],
/// the same two the in-place `SearchFieldAppBar` wears, so the two search
/// surfaces cannot drift apart again.
class SearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;

  const SearchAppBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
  });

  @override
  Size get preferredSize => const Size.fromHeight(AppBarMetrics.toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final clear = onClear;

    return AppBar(
      toolbarHeight: AppBarMetrics.toolbarHeight,
      backgroundColor: colorScheme.pageGround,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      actionsIconTheme: IconThemeData(
        size: AppBarMetrics.glyphSize,
        color: colorScheme.onSurface,
      ),
      title: SearchBarField(
        controller: controller,
        focusNode: focusNode,
        hintText: hintText,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
      actions: [
        if (clear != null)
          SearchBarClearAction(controller: controller, onClear: clear),
      ],
    );
  }
}
