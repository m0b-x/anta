import 'package:flutter/material.dart';

import 'unified_app_bars.dart';

/// App bar shown while the folder content page is in selection mode.
///
/// It is a box app bar, not a sliver: selection mode drops
/// `FolderSliverAppBar` entirely, because a large title that scrolls away
/// would take the selection count with it. [UnifiedAppBar.main] keeps its
/// background and icon colours identical to the collapsed browser bar, so the
/// swap is visually seamless.
class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int count;
  final bool allSelected;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;

  const SelectionAppBar({
    super.key,
    required this.count,
    required this.allSelected,
    required this.onCancel,
    required this.onSelectAll,
    required this.onDeselectAll,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return UnifiedAppBar.main(
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: onCancel,
        tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
      ),
      title: Text(
        '$count',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: [
        IconButton(
          icon: Icon(
            allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
          ),
          onPressed: allSelected ? onDeselectAll : onSelectAll,
        ),
      ],
    );
  }
}
