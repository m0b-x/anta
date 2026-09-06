import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/auto_save_service.dart';
import '../services/app_navigator.dart';

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

  const UnifiedAppBar({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.elevation,
    this.toolbarHeight,
    this.leadingWidth,
    this.style = AppBarStyle.main,
  });

  const UnifiedAppBar.main({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.elevation,
    this.toolbarHeight,
    this.leadingWidth,
  }) : style = AppBarStyle.main;

  const UnifiedAppBar.settings({
    super.key,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.title,
    this.actions,
    this.elevation,
    this.toolbarHeight,
    this.leadingWidth,
  }) : style = AppBarStyle.settings;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight ?? kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // The browser's bar is a `SliverAppBar.large` that a gradient cannot
    // follow across 172 px of collapse, and the editor's bar is the shape it
    // settles into — so the main style is flat Material 3 surface, and the
    // scrolled-under tint is the only colour change either bar makes. The
    // settings pages keep the gradient until they are redesigned.
    if (style == AppBarStyle.main) {
      return AppBar(
        leading: leading,
        leadingWidth: leadingWidth,
        automaticallyImplyLeading: automaticallyImplyLeading,
        title: title,
        actions: actions,
        elevation: elevation,
      );
    }

    final (startColor, endColor) = isDark
        ? (
            colorScheme.surfaceContainerHigh,
            colorScheme.surfaceContainerHighest,
          )
        : (
            colorScheme.primaryContainer,
            colorScheme.primary.withValues(alpha: 0.5),
          );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [startColor, endColor],
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: AppBar(
        leading: leading,
        leadingWidth: leadingWidth,
        automaticallyImplyLeading: automaticallyImplyLeading,
        title: title,
        actions: actions,
        backgroundColor: Colors.transparent,
        elevation: elevation ?? 0,
      ),
    );
  }
}

class _IntegratedNavButtons extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onMenu;

  const _IntegratedNavButtons({required this.onBack, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavButton(icon: Icons.arrow_back_rounded, onPressed: onBack),
          Container(
            width: 1,
            height: 20,
            color: isDark
                ? colorScheme.outline.withValues(alpha: 0.3)
                : colorScheme.onSurface.withValues(alpha: 0.15),
          ),
          _NavButton(icon: Icons.menu_rounded, onPressed: onMenu),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _NavButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
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
  final VoidCallback? onTitleTap;

  const NoteAppBar({
    super.key,
    required this.title,
    this.hasChanges = false,
    this.saveStatusNotifier,
    this.actions,
    this.onBackPressed,
    this.onTitleTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return UnifiedAppBar.main(
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const BackButtonIcon(),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: onBackPressed ?? () => AppNavigator.maybePop(context),
      ),
      title: GestureDetector(
        onTap: onTitleTap,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
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
      actions: actions,
    );
  }
}

/// Animated save-status chip shown next to the note title.
///
/// Listens to the [SaveStatus] value notifier and cross-fades between
/// states.  Keeps the widget tree lightweight – only rebuilds this subtree
/// when the status actually changes.
class _SaveStatusIndicator extends StatelessWidget {
  final bool hasChanges;
  final ValueListenable<SaveStatus>? saveStatusNotifier;

  const _SaveStatusIndicator({
    required this.hasChanges,
    this.saveStatusNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final notifier = saveStatusNotifier;
    if (notifier == null) {
      // Fallback: no notifier → show simple dot when unsaved
      return hasChanges ? _dot(context) : const SizedBox.shrink();
    }

    return ValueListenableBuilder<SaveStatus>(
      valueListenable: notifier,
      builder: (context, status, _) {
        final effective = hasChanges && status == SaveStatus.saved
            ? SaveStatus.unsaved
            : status;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          layoutBuilder: (currentChild, previousChildren) {
            // Deduplicate all children by key - current child takes precedence
            final allChildren = [...previousChildren, ?currentChild];
            final seenKeys = <Key>{};
            final uniqueChildren = <Widget>[];

            // Process in reverse so current child wins over previous
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
        );
      },
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
        return _icon(
          key: const ValueKey('unsaved'),
          icon: Icons.circle,
          color: colorScheme.primary,
          size: 8,
        );
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
    double size = 14,
    bool spinning = false,
  }) {
    Widget child = Icon(icon, size: size, color: color);
    if (spinning) {
      child = _SpinningIcon(icon: icon, size: size, color: color);
    }
    return Padding(
      key: key,
      padding: const EdgeInsets.only(left: 8),
      child: child,
    );
  }

  Widget _dot(BuildContext context) {
    return Container(
      key: const ValueKey('dot'),
      margin: const EdgeInsets.only(left: 8),
      width: 8,
      height: 8,
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
  final bool showMenuButton;

  const SettingsAppBar({
    super.key,
    required this.title,
    this.actions,
    this.showMenuButton = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return UnifiedAppBar.settings(
      leadingWidth: showMenuButton ? 100 : null,
      leading: showMenuButton
          ? Builder(
              builder: (ctx) => _IntegratedNavButtons(
                onBack: () =>
                    AppNavigator.pop(context, SettingsResult.openDrawer),
                onMenu: () => Scaffold.of(ctx).openDrawer(),
              ),
            )
          : null,
      title: Text(title),
      actions: actions,
    );
  }
}

class SearchAppBar extends StatefulWidget implements PreferredSizeWidget {
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
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<SearchAppBar> createState() => _SearchAppBarState();
}

class _SearchAppBarState extends State<SearchAppBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppBar(
      title: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        decoration: InputDecoration(
          hintText: widget.hintText,
          border: InputBorder.none,
          hintStyle: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        style: const TextStyle(fontSize: 18),
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      ),
      actions: [
        if (widget.controller.text.isNotEmpty)
          IconButton(icon: const Icon(Icons.clear), onPressed: widget.onClear),
      ],
    );
  }
}
