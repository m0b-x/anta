import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../l10n/app_localizations.dart';
import '../models/folder.dart';
import '../services/app_navigator.dart';

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
  final selected = await showMenu<int>(
    context: anchorContext,
    positionBuilder: (_, constraints) =>
        _anchorUnder(anchorContext, constraints),
    items: [
      for (var i = 0; i < targets.length; i++)
        PopupMenuItem<int>(
          value: i,
          child: Row(
            children: [
              Icon(
                targets[i] == null
                    ? Icons.home_outlined
                    : Icons.folder_outlined,
                size: 20,
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

  /// The default expanded title box is 60 px tall (152 − 64 − 28), which an
  /// eyebrow above a headline does not fit.
  static const double expandedHeight = 172;

  /// The large variant's collapsed height, and the height the bar shares with
  /// the note editor's bar once scrolled.
  static const double collapsedHeight = 64;

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
    return SliverAppBar.large(
      pinned: true,
      automaticallyImplyLeading: false,
      expandedHeight: expandedHeight,
      toolbarHeight: collapsedHeight,
      leading: isRootPage ? _menuButton() : _backButton(),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: actions,
      flexibleSpace: _FolderFlexibleSpace(
        title: title,
        eyebrow: eyebrow,
        onEyebrowTap: onShowAncestors,
      ),
    );
  }

  Widget _menuButton() {
    return Builder(
      builder: (context) => IconButton(
        icon: const Icon(Icons.menu_rounded),
        tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
        onPressed: onMenuPressed ?? () => Scaffold.of(context).openDrawer(),
      ),
    );
  }

  Widget _backButton() {
    return Builder(
      builder: (context) {
        final showAncestors = onShowAncestors;
        final button = IconButton(
          icon: const BackButtonIcon(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onBackPressed ?? () => AppNavigator.pop(context),
          onLongPress: showAncestors == null
              ? null
              : () => showAncestors(context),
        );
        if (showAncestors == null) return button;
        // Without the merge the annotation would settle on whichever node
        // encloses the button rather than on the button itself, and the
        // action would be offered for the whole bar.
        return MergeSemantics(
          child: Semantics(
            customSemanticsActions: {
              CustomSemanticsAction(
                label: AppLocalizations.of(context)!.showAncestors,
              ): () =>
                  showAncestors(context),
            },
            child: button,
          ),
        );
      },
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
class _FolderFlexibleSpace extends StatelessWidget {
  const _FolderFlexibleSpace({
    required this.title,
    this.eyebrow,
    this.onEyebrowTap,
  });

  final String title;
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
              child: AnimatedOpacity(
                opacity: (settings.isScrolledUnder ?? false) ? 0 : 1,
                duration: const Duration(milliseconds: 500),
                curve: const Cubic(0.2, 0.0, 0.0, 1.0),
                child: OverflowBox(
                  alignment: AlignmentDirectional.bottomStart,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (parent != null)
                          _Eyebrow(
                            label: parent,
                            onTap: onEyebrowTap,
                            color: colorScheme.onSurfaceVariant,
                            style: theme.textTheme.labelLarge,
                          ),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
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
  const _Eyebrow({
    required this.label,
    required this.color,
    this.style,
    this.onTap,
  });

  final String label;
  final Color color;
  final TextStyle? style;
  final void Function(BuildContext anchorContext)? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style?.copyWith(color: color) ?? TextStyle(color: color),
    );
    final tap = onTap;
    if (tap == null) {
      return Padding(padding: const EdgeInsets.only(bottom: 2), child: text);
    }
    return Builder(
      builder: (anchorContext) => InkWell(
        onTap: () => tap(anchorContext),
        borderRadius: BorderRadius.circular(6),
        child: Semantics(
          button: true,
          hint: AppLocalizations.of(anchorContext)!.showAncestors,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2, right: 4),
            child: text,
          ),
        ),
      ),
    );
  }
}
