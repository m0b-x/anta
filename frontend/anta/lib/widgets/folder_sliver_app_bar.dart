import 'package:flutter/material.dart';

import '../constants/app_bar_metrics.dart';
import '../constants/app_colors.dart';
import '../constants/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/folder.dart';
import '../services/app_navigator.dart';
import 'leading_nav_pair.dart';

/// Opens the ancestor breadcrumb under [anchorContext]'s widget.
///
/// Rows run from the nearest parent upwards and always end with the root
/// browser, so the list reads the way the taps that built it did — the same
/// order a long-press on a browser's Back button implies.
///
/// [onSelected] receives the chosen ancestor, or `null` for the root. A
/// dismissed menu calls nothing.
Future<void> showFolderAncestorMenu(
  BuildContext anchorContext, {
  required List<Folder> ancestors,
  required String rootLabel,
  required void Function(Folder? folder) onSelected,
}) async {
  final targets = <Folder?>[...ancestors.reversed, null];
  final glyphColor = Theme.of(anchorContext).colorScheme.onSurfaceVariant;
  final selected = await showMenu<int>(
    context: anchorContext,
    constraints: const BoxConstraints.tightFor(width: AppTheme.menuWidth),
    positionBuilder: (_, constraints) =>
        _anchorUnder(anchorContext, constraints),
    items: [
      for (var i = 0; i < targets.length; i++)
        PopupMenuItem<int>(
          value: i,
          height: AppTheme.menuItemHeight,
          child: Row(
            children: [
              Icon(
                targets[i] == null
                    ? Icons.home_outlined
                    : Icons.folder_outlined,
                size: AppTheme.menuIconSize,
                color: glyphColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  targets[i]?.name ?? rootLabel,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ],
  );
  if (selected == null) return;
  onSelected(targets[selected]);
}

RelativeRect _anchorUnder(BuildContext context, BoxConstraints constraints) {
  final fallback = RelativeRect.fromSize(Rect.zero, constraints.biggest);
  if (!context.mounted) return fallback;
  final anchor = context.findRenderObject();
  final overlay = Navigator.of(context).overlay?.context.findRenderObject();
  if (anchor is! RenderBox ||
      overlay is! RenderBox ||
      !anchor.attached ||
      !overlay.attached) {
    return fallback;
  }
  final under = Offset(0, anchor.size.height);
  return RelativeRect.fromRect(
    Rect.fromPoints(
      anchor.localToGlobal(under, ancestor: overlay),
      anchor.localToGlobal(
        anchor.size.bottomRight(Offset.zero) + under,
        ancestor: overlay,
      ),
    ),
    Offset.zero & overlay.size,
  );
}

/// The browser's app bar: a Material 3 large top app bar that opens tall with
/// the folder name and settles into the compact bar the note editor uses.
///
/// `SliverAppBar.large` builds [title] **twice** — once in the toolbar and
/// once inside the flexible space it supplies by default — so [title] stays a
/// single [Text] for the collapsed state and this widget draws the expanded
/// eyebrow-plus-headline itself. A second line, a `GlobalKey` or a `FocusNode`
/// in [title] would be duplicated or throw.
///
/// The root draws the drawer button alone, having nowhere to go back to;
/// every other folder draws a [LeadingNavPair], which is why [title] has
/// [LeadingNavPair.width] less room there once the bar is collapsed.
class FolderSliverAppBar extends StatelessWidget {
  const FolderSliverAppBar({
    super.key,
    required this.title,
    required this.isRootPage,
    this.eyebrow,
    this.actions,
    this.onMenuPressed,
    this.onBackPressed,
    this.onShowAncestors,
  });

  /// Toolbar, the eyebrow's own line, the large title's line and the space
  /// below it — nothing between the toolbar and the eyebrow.
  static const double expandedHeightNested = 116;

  /// The root has no parent to name, so the eyebrow's line becomes the space
  /// the mock puts above a title that opens a screen.
  static const double expandedHeightRoot = 102;

  /// The status bar is added on top of this by the framework; every caller
  /// that reasons about the bar's extent — the swap compensation and the
  /// refresh indicator's inset — measures from here.
  static double expandedHeightFor(bool isRootPage) =>
      isRootPage ? expandedHeightRoot : expandedHeightNested;

  /// The height the bar shares with every other bar in the app once
  /// collapsed, status bar excluded.
  ///
  /// `SliverAppBar.large` sizes its collapsed extent from its own 64 px
  /// default and ignores `toolbarHeight`, so this is handed to it explicitly
  /// — with the status bar added, which the large variant does not do for a
  /// supplied value — or the toolbar would float above a dead band.
  static const double collapsedHeight = AppBarMetrics.toolbarHeight;

  final String title;
  final bool isRootPage;

  /// The parent folder's name, drawn above the large title. Null at the root
  /// and while the ancestor chain is still loading.
  final String? eyebrow;

  final List<Widget>? actions;
  final VoidCallback? onMenuPressed;
  final VoidCallback? onBackPressed;

  /// Opens the ancestor breadcrumb. It is handed the context of whichever
  /// control raised it, so the menu is anchored under the thing that was
  /// touched.
  final void Function(BuildContext anchorContext)? onShowAncestors;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SliverAppBar.large(
      pinned: true,
      automaticallyImplyLeading: false,
      expandedHeight: expandedHeightFor(isRootPage),
      toolbarHeight: AppBarMetrics.toolbarHeight,
      collapsedHeight:
          MediaQuery.paddingOf(context).top + AppBarMetrics.toolbarHeight,
      backgroundColor: colorScheme.pageGround,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      actionsIconTheme: IconThemeData(
        size: AppBarMetrics.glyphSize,
        color: colorScheme.onSurface,
      ),
      leadingWidth: isRootPage ? null : LeadingNavPair.width,
      leading: isRootPage ? _menuButton() : _leadingPair(),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: AppBarMetrics.titleFontSize,
          fontWeight: AppBarMetrics.titleFontWeight,
        ),
      ),
      actions: actions,
      flexibleSpace: _FolderFlexibleSpace(
        title: title,
        eyebrow: eyebrow,
        isRootPage: isRootPage,
        onEyebrowTap: onShowAncestors,
      ),
    );
  }

  Widget _menuButton() {
    return Builder(
      builder: (context) => IconButton(
        icon: const Icon(Icons.menu_rounded),
        iconSize: AppBarMetrics.glyphSize,
        tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
        onPressed: onMenuPressed ?? () => Scaffold.of(context).openDrawer(),
      ),
    );
  }

  Widget _leadingPair() {
    return Builder(
      builder: (context) => LeadingNavPair(
        onBack: onBackPressed ?? () => AppNavigator.pop(context),
        onMenu: onMenuPressed ?? () => Scaffold.of(context).openDrawer(),
        onBackLongPress: onShowAncestors,
        backLongPressLabel: AppLocalizations.of(context)!.showAncestors,
      ),
    );
  }
}

/// The expanded half of [FolderSliverAppBar].
///
/// Laid out the way the framework lays out its own large title: the toolbar's
/// height is reserved at the top, the rest is bottom-aligned and clipped, so
/// the headline slides up under the toolbar as the bar collapses. The child is
/// measured unconstrained ([OverflowBox]) because a shrinking flex child would
/// otherwise overflow rather than slide.
///
/// The eyebrow owns the first line under the toolbar and nothing separates
/// the two: a page names its parent immediately or not at all. Where there is
/// no parent to name, that line becomes the space above the title instead.
class _FolderFlexibleSpace extends StatelessWidget {
  const _FolderFlexibleSpace({
    required this.title,
    required this.isRootPage,
    this.eyebrow,
    this.onEyebrowTap,
  });

  final String title;
  final bool isRootPage;
  final String? eyebrow;
  final void Function(BuildContext anchorContext)? onEyebrowTap;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final parent = eyebrow;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.34,
      child: Column(
        children: [
          SizedBox(height: settings.minExtent),
          Expanded(
            child: ClipRect(
              child: OverflowBox(
                alignment: AlignmentDirectional.bottomStart,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (parent != null)
                      _Eyebrow(
                        label: parent,
                        onTap: onEyebrowTap,
                        color: colorScheme.onSurfaceVariant,
                      )
                    else if (isRootPage)
                      const SizedBox(
                        height: AppBarMetrics.largeTitleTopPaddingAtRoot,
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppBarMetrics.largeTitlePadding,
                        0,
                        AppBarMetrics.largeTitlePadding,
                        AppBarMetrics.largeTitleBottomPadding,
                      ),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: AppBarMetrics.largeTitleFontSize,
                          fontWeight: FontWeight.w500,
                          height: AppBarMetrics.largeTitleHeight,
                          letterSpacing: AppBarMetrics.largeTitleLetterSpacing,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The parent folder's name above the large title, and the screen-reader
/// reachable twin of the Back button's long-press: a long press alone is
/// invisible to TalkBack.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.label, required this.color, this.onTap});

  final String label;
  final Color color;
  final void Function(BuildContext anchorContext)? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: AppBarMetrics.eyebrowFontSize),
    );
    final tap = onTap;
    if (tap == null) {
      return SizedBox(
        height: AppBarMetrics.eyebrowHeight,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppBarMetrics.eyebrowPadding,
            ),
            child: text,
          ),
        ),
      );
    }
    return Builder(
      builder: (anchorContext) => SizedBox(
        height: AppBarMetrics.eyebrowHeight,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: InkWell(
            onTap: () => tap(anchorContext),
            borderRadius: BorderRadius.circular(6),
            child: Semantics(
              button: true,
              hint: AppLocalizations.of(anchorContext)!.showAncestors,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppBarMetrics.eyebrowPadding,
                ),
                child: text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
