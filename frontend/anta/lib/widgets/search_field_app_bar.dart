import 'package:flutter/material.dart';

import '../constants/app_bar_metrics.dart';
import '../constants/app_colors.dart';
import '../controllers/in_place_search_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/item_label.dart';
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
    this.labelsInUse = const [],
    this.selectedLabels = const {},
  });

  final InPlaceSearchController search;

  final String hintText;

  /// Which scope the bloc is currently searching under, for the chips.
  final SearchScope selectedScope;

  final VoidCallback onLeave;

  /// The folder half of the scope choice. Null on a host that has no second
  /// scope to offer — the root browser and the note lists are already
  /// searching everywhere — where the row is dropped entirely unless there
  /// are colour chips to carry on their own.
  final FolderScope? folderScope;

  /// The colours notes in the current scope carry, for the label chips.
  final List<ItemLabel> labelsInUse;

  /// The colours currently filtering the results.
  final Set<ItemLabel> selectedLabels;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showsChips = SearchScopeChips.shows(
      folderScope: folderScope,
      labelsInUse: labelsInUse,
    );

    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      toolbarHeight: AppBarMetrics.toolbarHeight,
      backgroundColor: colorScheme.pageGround,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const BackButtonIcon(),
        iconSize: AppBarMetrics.glyphSize,
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: onLeave,
      ),
      title: SearchBarField(
        controller: search.textController,
        focusNode: search.focusNode,
        hintText: hintText,
        onChanged: search.onChanged,
        onSubmitted: search.onSubmitted,
      ),
      actions: [
        SearchBarClearAction(
          controller: search.textController,
          onClear: search.clearQuery,
        ),
      ],
      bottom: !showsChips
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(
                SearchScopeChips.preferredHeight,
              ),
              child: SearchScopeChips(
                folderScope: folderScope,
                selected: selectedScope,
                labelsInUse: labelsInUse,
                selectedLabels: selectedLabels,
              ),
            ),
    );
  }
}

/// The query field both search bars wear: the in-place one on the browser and
/// the note lists, and the standalone search page's.
///
/// One widget rather than two look-alikes, because the two used to drift —
/// different sizes, different hint colours, one of them without a submit
/// action.
class SearchBarField extends StatelessWidget {
  const SearchBarField({
    super.key,
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        hintStyle: TextStyle(
          color: colorScheme.outline,
          fontSize: AppBarMetrics.titleFontSize,
        ),
      ),
      style: const TextStyle(fontSize: AppBarMetrics.titleFontSize),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// The clear button that appears once the field has something in it.
///
/// It listens to the controller itself, so a keystroke rebuilds one icon
/// rather than the whole bar.
class SearchBarClearAction extends StatelessWidget {
  const SearchBarClearAction({
    super.key,
    required this.controller,
    required this.onClear,
  });

  final TextEditingController controller;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.text.isEmpty) return const SizedBox.shrink();
        return IconButton(
          icon: const Icon(Icons.clear),
          iconSize: AppBarMetrics.glyphSize,
          tooltip: l10n.clearSearch,
          onPressed: onClear,
        );
      },
    );
  }
}
