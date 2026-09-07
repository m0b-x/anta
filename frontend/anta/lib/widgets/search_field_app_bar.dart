import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../controllers/in_place_search_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/search_scope.dart';
import 'search_surface.dart';

/// The bar a page wears while it is searching in place: a field where its
/// title was, the scope chips under it, and a back arrow that leaves search
/// rather than the page.
///
/// It replaces the host's whole first sliver instead of dressing up a large
/// title bar: `SliverAppBar.large` builds its `title` twice, so a [TextField]
/// there would be duplicated, and two of them would fight over one
/// [FocusNode].
class SearchFieldAppBar extends StatelessWidget {
  const SearchFieldAppBar({
    super.key,
    required this.search,
    required this.hintText,
    required this.selectedScope,
    required this.onLeave,
    this.folderScope,
  });

  final InPlaceSearchController search;

  final String hintText;

  /// Which scope the bloc is currently searching under, for the chips.
  final SearchScope selectedScope;

  final VoidCallback onLeave;

  /// The folder half of the scope choice. Null on a host that has no second
  /// scope to offer — the root browser and the note lists are already
  /// searching everywhere — and the chip row is then dropped entirely.
  final FolderScope? folderScope;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final scope = folderScope;

    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      backgroundColor: colorScheme.pageGround,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const BackButtonIcon(),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: onLeave,
      ),
      title: TextField(
        controller: search.textController,
        focusNode: search.focusNode,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hintText,
          border: InputBorder.none,
          hintStyle: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        style: const TextStyle(fontSize: 18),
        onChanged: search.onChanged,
        onSubmitted: search.onSubmitted,
      ),
      actions: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: search.textController,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.clear),
              tooltip: l10n.clearSearch,
              onPressed: search.clearQuery,
            );
          },
        ),
      ],
      bottom: scope == null
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(
                SearchScopeChips.preferredHeight,
              ),
              child: SearchScopeChips(
                folderScope: scope,
                selected: selectedScope,
              ),
            ),
    );
  }
}
