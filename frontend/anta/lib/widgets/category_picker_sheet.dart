import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../utils/calendar_filter_summary.dart';
import '../utils/category_search.dart';
import '../utils/settings_search.dart';
import 'category_editor_sheet.dart';
import 'event_avatar.dart';
import 'form_rows.dart';

/// How many categories a single [CategoryPickerSheet] pass may return.
enum CategoryPickerMode { single, multi }

/// Bottom-sheet selector for event categories, in the two arities
/// `CalendarDatePickerSheet` established: [pickSingle] returns one id, and
/// [pickMulti] edits a whole set in one pass.
///
/// A sub-sheet of the editor's grouped-row language since the 2026-09-27
/// filter redesign (`docs/calendar-filters-redesign-roadmap.md`, D13): one
/// group of check rows wearing each category's avatar, a search row past the
/// threshold, two bulk action rows in multi mode, a Create category row last;
/// ✕ · title · Done in multi mode, ✕ · title and a pick-on-tap list in single
/// mode. Content-tall, clamped at the editor's height, the route's own drag.
///
/// Rows come from `CalendarCategories.visiblePlus(initialSelection)` — the
/// archive flag hides a category from every choosing surface, but a selection
/// that already carries a hidden id must still list it or the user cannot
/// un-select what they can no longer see. The *opening* selection, not the
/// live one, so a row cannot vanish the moment it is un-ticked.
///
/// Search runs on the shared `rankCategories`, so this sheet and the
/// management page can never answer the same query differently. There is
/// deliberately **no autofocus**: the sheet's job is picking, and raising the
/// keyboard on every open pushes the list up and costs a tap to dismiss.
class CategoryPickerSheet extends StatefulWidget {
  final CategoryPickerMode mode;

  /// Ids selected when the sheet opens. Single mode uses it only to mark the
  /// current row and to keep a hidden category listed.
  final Set<String> initialSelection;

  const CategoryPickerSheet({
    super.key,
    required this.mode,
    required this.initialSelection,
  });

  /// Picks one category. Returns its id, or `null` when dismissed.
  static Future<String?> pickSingle(
    BuildContext context, {
    required String selectedId,
  }) async {
    final picked = await _show(
      context,
      mode: CategoryPickerMode.single,
      initialSelection: {selectedId},
    );
    if (picked == null || picked.isEmpty) return null;
    return picked.first;
  }

  /// Edits a whole set of categories in one pass. Returns `null` when
  /// dismissed.
  ///
  /// Like its date twin this is **semantics-free** — a set goes in, a set
  /// comes out — so it serves the agenda's allowlist and the calendar
  /// filter's denylist without knowing which it is; the caller inverts.
  /// **Unlike `CalendarDatePickerSheet.pickMulti` an empty result is not
  /// collapsed to `null`**: empty is a real, meaningful state on both sides
  /// here (no allowlist, nothing hidden), and swallowing it would make
  /// clearing the last category look like a dismissal.
  static Future<Set<String>?> pickMulti(
    BuildContext context, {
    required Set<String> selected,
  }) {
    return _show(
      context,
      mode: CategoryPickerMode.multi,
      initialSelection: selected,
    );
  }

  static Future<Set<String>?> _show(
    BuildContext context, {
    required CategoryPickerMode mode,
    required Set<String> initialSelection,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: colorScheme.pageGround,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FormMetrics.sheetRadius),
        ),
      ),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * FormMetrics.sheetHeightFactor,
        ),
        child: CategoryPickerSheet(
          mode: mode,
          initialSelection: initialSelection,
        ),
      ),
    );
  }

  @override
  State<CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<CategoryPickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  late final Set<String> _selected = {...widget.initialSelection};

  SettingsQuery _query = SettingsQuery.empty;

  /// The body's scroll position feeds the header's hairline (a form sheet's
  /// rule): a notifier, never `setState`, so a scroll frame rebuilds a 1 px
  /// line and not the sheet.
  final ScrollController _bodyScroll = ScrollController();
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);

  bool get _isMulti => widget.mode == CategoryPickerMode.multi;
  bool get _isFiltering => _query.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _bodyScroll.addListener(_onBodyScroll);
  }

  @override
  void dispose() {
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    _headerScrolled.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onBodyScroll() {
    final scrolled = _bodyScroll.hasClients && _bodyScroll.offset > 0;
    if (_headerScrolled.value != scrolled) _headerScrolled.value = scrolled;
  }

  void _onQueryChanged(String raw) {
    setState(() => _query = SettingsQuery.parse(raw));
  }

  /// Selects or clears every row **currently listed**, which is the filtered
  /// set while a query is live. Bulk-editing rows the search has hidden would
  /// change what the user cannot see; bulk-editing what is on screen is the
  /// only reading the buttons can honestly carry.
  ///
  /// Multi mode only — there is nothing to select all *of* when the answer is
  /// one category. Without these, narrowing fifty categories down to two
  /// costs forty-eight taps, because the allowlist inversion opens every row
  /// already checked.
  void _setAll(List<CalendarCategory> rows, bool selected) {
    setState(() {
      for (final category in rows) {
        if (selected) {
          _selected.add(category.id);
        } else {
          _selected.remove(category.id);
        }
      }
    });
  }

  void _onTapCategory(CalendarCategory category) {
    if (!_isMulti) {
      Navigator.of(context).pop({category.id});
      return;
    }
    setState(() {
      if (!_selected.remove(category.id)) _selected.add(category.id);
    });
  }

  /// Creates a category without leaving the sheet. In single mode the new
  /// category is the answer, so the sheet returns it; in multi mode it joins
  /// the selection and the list stays open.
  Future<void> _createCategory({String? initialName}) async {
    final created = await CategoryEditorSheet.show(
      context,
      initialName: initialName,
    );
    if (created == null || !mounted) return;
    if (!_isMulti) {
      Navigator.of(context).pop({created.id});
      return;
    }
    _searchController.clear();
    setState(() {
      _selected.add(created.id);
      _query = SettingsQuery.empty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Read on every build so a database switch (which clears the facade)
    // cannot leave a stale list here, and so a category created from this
    // sheet appears the moment the facade republishes.
    //
    // The kept set is the selection the sheet **opened with**, not the live
    // one: an archived category is listed because the selection carries it,
    // and de-selecting it mid-pass must not delete the row out from under the
    // finger that just un-ticked it — leaving the user unable to change their
    // mind, and shrinking the offered set (and with it the search field's
    // threshold) mid-interaction. Invariant 8 is "visible plus its own
    // selected ids"; for a sheet that edits a selection, those are the ids it
    // was handed.
    final categories = CalendarCategories.visiblePlus(widget.initialSelection);
    final rows = _isFiltering
        ? [
            for (final ranked in rankCategories(_query, categories, l10n))
              ranked.category,
          ]
        : categories;
    // Short lists carry no search chrome; the threshold trips on its own as
    // the set grows. `_isFiltering` holds the field open once it is in use,
    // the same rule the management page follows: a list that is filtered with
    // no field left to clear it is stranded, and the two searchable category
    // surfaces must not disagree about when the field is there.
    final showSearch =
        _isFiltering || categories.length > AppConstants.listSearchThreshold;
    // Nothing matched: the typed text is almost certainly the name the user
    // wants, so the one row left offers to create it rather than to start
    // over.
    final typed = _searchController.text.trim();
    final createTyped = rows.isEmpty && typed.isNotEmpty;
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view, never the whole body — the clearance rule every calendar
    // sheet follows (`sheet_bottom_clearance_test.dart`).
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.categoryPickClose,
          onLeading: () => Navigator.of(context).pop(),
          title: _isMulti ? l10n.calendarCategories : l10n.eventType,
          scrolled: _headerScrolled,
          trailingInset: FormMetrics.headerActionInset,
          // Single mode picks on tap and has nothing to confirm.
          trailing: _isMulti
              ? FormHeaderTextButton(
                  label: l10n.eventDescriptionDone,
                  identifier: SemanticsIds.categoryPickDone,
                  // Pops the set as-is, empty included — see [pickMulti].
                  onPressed: () => Navigator.of(context).pop({..._selected}),
                )
              : const SizedBox.shrink(),
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: _bodyScroll,
            padding: EdgeInsets.fromLTRB(
              RowMetrics.groupInset,
              FormMetrics.bodyTop,
              RowMetrics.groupInset,
              FormMetrics.bodyBottom + clearance,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FormRowGroup(
                  trailingGap: false,
                  children: [
                    if (showSearch)
                      FormSearchRow(
                        controller: _searchController,
                        hint: l10n.searchCategories,
                        clearTooltip: l10n.upcomingClearSearch,
                        identifier: SemanticsIds.categoryPickSearch,
                        onChanged: _onQueryChanged,
                      ),
                    // Disabled where they would be no-ops, or the enabled
                    // tint promises a change that costs a tap to discover is
                    // absent. Over the rows currently listed — see [_setAll].
                    if (_isMulti && rows.isNotEmpty) ...[
                      FormActionRow(
                        glyph: Icons.done_all_rounded,
                        label: l10n.categoriesSelectAll,
                        identifier: SemanticsIds.categoryPickSelectAll,
                        onTap: rows.every((c) => _selected.contains(c.id))
                            ? null
                            : () => _setAll(rows, true),
                      ),
                      FormActionRow(
                        glyph: Icons.remove_done_rounded,
                        label: l10n.categoriesSelectNone,
                        identifier: SemanticsIds.categoryPickSelectNone,
                        onTap: rows.every((c) => !_selected.contains(c.id))
                            ? null
                            : () => _setAll(rows, false),
                      ),
                    ],
                    for (final category in rows)
                      FormCheckRow(
                        leading: EventAvatar(
                          icon:
                              CalendarIcons.forKey(category.iconKey) ??
                              Icons.event_rounded,
                          color: category.color,
                        ),
                        label: CalendarCategories.labelOf(category, l10n),
                        // A hidden category only reaches this list by already
                        // being selected; say so, or it reads as an ordinary
                        // row the user forgot about.
                        caption: category.isHidden ? l10n.categoryHidden : null,
                        checked: _selected.contains(category.id),
                        exclusive: !_isMulti,
                        identifier: SemanticsIds.categoryPickRow(category.id),
                        onChanged: (_) => _onTapCategory(category),
                      ),
                    FormActionRow(
                      glyph: Icons.add_rounded,
                      label: createTyped
                          ? l10n.createCategoryNamed(typed)
                          : l10n.createCategory,
                      identifier: SemanticsIds.categoryPickCreate,
                      onTap: () => _createCategory(
                        initialName: createTyped ? typed : null,
                      ),
                    ),
                  ],
                ),
                if (rows.isEmpty && _isFiltering)
                  FormCaption(
                    text: l10n.noCategoriesMatch,
                    padding: FormMetrics.groupCaptionPadding,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The stand-in for a per-category chip `Wrap`, shared by the two filter
/// sheets so they cannot describe a selection differently.
///
/// One row naming what is included — *All categories*, or the first names
/// plus *+N more* — opening [CategoryPickerSheet.pickMulti]. It is the
/// pattern the agenda panel's own `Categories (3)` chip already follows: a
/// wall of chips over the whole set is what breaks at forty categories, and
/// re-adding a chip row for the *selection* beneath this tile would rebuild
/// exactly the wall it removes.
///
/// **The row does not repeat the section label above it.** Both callers head
/// the section with one (*Categories* / *Event categories*), and a card
/// titled the same thing 35dp below reads as a rendering bug — it was the
/// only section in either sheet that named itself twice. So the *state* is
/// the title line here, and there is no subtitle: the label says what the
/// section is, the row says what it is set to.
class CategoryFilterTile extends StatelessWidget {
  /// Every category the filter is choosing among, in display order — the
  /// denominator [selectsAll] is measured against, and the avatars shown when
  /// it holds.
  final List<CalendarCategory> offered;

  /// The included categories, in display order. Empty means the filter
  /// currently excludes every one of them.
  final List<CalendarCategory> selected;

  /// Whether [selected] covers the whole offered set — an allowlist that is
  /// empty by convention says this too.
  final bool selectsAll;

  final VoidCallback onTap;

  const CategoryFilterTile({
    super.key,
    required this.offered,
    required this.selected,
    required this.selectsAll,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Everything included means every offered category is what the avatars
    // stand for; an explicit subset shows its own. Both are honest, and both
    // keep the row in the colour-coded language every other category surface
    // speaks — a lone monochrome glyph made this the one place categories
    // looked like generic settings furniture.
    final shown = selectsAll ? offered : selected;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: shown.isEmpty
            ? const Icon(Icons.category_rounded)
            : _CategoryAvatarCluster(categories: shown),
        title: Text(
          _subtitle(l10n),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }

  /// The names through the shared read-back rule, so this tile and the filter
  /// sheet's Categories row fold a long selection the same way.
  String _subtitle(AppLocalizations l10n) {
    if (selectsAll) return l10n.categoriesAllSelected;
    if (selected.isEmpty) return l10n.categoriesNSelected(0);
    return CalendarFilterSummary.namesReadBack(
      [for (final c in selected) CalendarCategories.labelOf(c, l10n)],
      l10n,
    );
  }
}

/// The first few categories of a selection as overlapping colour discs.
///
/// Painted back-to-front so the leading category sits on top, and ringed in
/// the surface colour so two adjacent discs of similar hue still read as two.
class _CategoryAvatarCluster extends StatelessWidget {
  final List<CalendarCategory> categories;

  static const int maxShown = 3;
  static const double _diameter = 24;
  static const double _step = 13;

  const _CategoryAvatarCluster({required this.categories});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = categories.take(maxShown).toList();

    return SizedBox(
      width: _diameter + _step * (shown.length - 1),
      height: 40,
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          for (var i = shown.length - 1; i >= 0; i--)
            PositionedDirectional(
              start: i * _step,
              child: Container(
                width: _diameter,
                height: _diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.alphaBlend(
                    shown[i].color.withValues(alpha: 0.18),
                    theme.colorScheme.surfaceContainerLow,
                  ),
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  CalendarIcons.forKey(shown[i].iconKey) ?? Icons.event_rounded,
                  size: 14,
                  color: shown[i].color,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

