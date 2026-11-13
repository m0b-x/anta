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
import '../models/partner_look.dart';
import '../utils/category_search.dart';
import '../utils/settings_search.dart';
import '../utils/share_copy.dart';
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

  /// The calendar guide's demos open the real sheet over throwaway state:
  /// the Create row is the one path from here into a category write, so it
  /// is left out; search and picking stay as they are.
  final bool sandbox;

  /// Ids never listed, whatever the selection keeps: the delete sheet's own
  /// category, which cannot be where its events move.
  final Set<String> exclude;

  /// A title in place of the mode's own, for a use whose tick means more
  /// than a filter's — the Sharing page's "Share categories". A titled sheet
  /// stacks its title under the ✕ and Done rather than cut it.
  final String? title;

  /// A line under the header, outside the scroll: what a tick does, said
  /// once rather than per row.
  final String? caption;

  /// Each category's event count by id, read back as its row's second line.
  /// Null keeps the rows as the picker's other uses draw them.
  final Map<String, int>? counts;

  /// Whether a category made through Create category joins the selection.
  /// False for a set whose tick acts on Done — the Sharing page's, where a
  /// tick shares — so Done never hands over a category nobody ticked.
  final bool tickCreated;

  /// A partner's own categories, listed in a second group under "From
  /// {name}" after this person's (share surfaces §6.10): only the filter
  /// sheets pass them, since a partner's category filters a view but is
  /// never one an event of this person's may take. Empty leaves the sheet as
  /// every other caller opens it.
  final List<CalendarCategory> partner;

  /// How the partner's rows draw their avatars and whose name heads their
  /// group — the look the page hands its event rows.
  final PartnerLook partnerLook;

  const CategoryPickerSheet({
    super.key,
    required this.mode,
    required this.initialSelection,
    this.sandbox = false,
    this.exclude = const {},
    this.title,
    this.caption,
    this.counts,
    this.tickCreated = true,
    this.partner = const [],
    this.partnerLook = const PartnerLook(),
  });

  /// Picks one category. Returns its id, or `null` when dismissed.
  static Future<String?> pickSingle(
    BuildContext context, {
    required String selectedId,
    bool sandbox = false,
    Set<String> exclude = const {},
  }) async {
    final picked = await _show(
      context,
      mode: CategoryPickerMode.single,
      initialSelection: {selectedId},
      sandbox: sandbox,
      exclude: exclude,
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
  ///
  /// [title], [caption] and [counts] are the Sharing page's tick sheet's
  /// (share surfaces §6.3), and so is [tickCreated] false (case C9);
  /// [identifier] names the sheet's root for a flow. [partner] and
  /// [partnerLook] are the filter sheets' (§6.10): the returned set then
  /// holds both kinds of ids, and the caller's "every listed row" check
  /// must count the partner's too.
  static Future<Set<String>?> pickMulti(
    BuildContext context, {
    required Set<String> selected,
    bool sandbox = false,
    String? title,
    String? caption,
    Map<String, int>? counts,
    String? identifier,
    bool tickCreated = true,
    List<CalendarCategory> partner = const [],
    PartnerLook partnerLook = const PartnerLook(),
  }) {
    return _show(
      context,
      mode: CategoryPickerMode.multi,
      initialSelection: selected,
      sandbox: sandbox,
      title: title,
      caption: caption,
      counts: counts,
      identifier: identifier,
      tickCreated: tickCreated,
      partner: partner,
      partnerLook: partnerLook,
    );
  }

  static Future<Set<String>?> _show(
    BuildContext context, {
    required CategoryPickerMode mode,
    required Set<String> initialSelection,
    required bool sandbox,
    Set<String> exclude = const {},
    String? title,
    String? caption,
    Map<String, int>? counts,
    String? identifier,
    bool tickCreated = true,
    List<CalendarCategory> partner = const [],
    PartnerLook partnerLook = const PartnerLook(),
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
      builder: (context) {
        final sheet = ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.sizeOf(context).height *
                FormMetrics.sheetHeightFactor,
          ),
          child: CategoryPickerSheet(
            mode: mode,
            initialSelection: initialSelection,
            sandbox: sandbox,
            exclude: exclude,
            title: title,
            caption: caption,
            counts: counts,
            tickCreated: tickCreated,
            partner: partner,
            partnerLook: partnerLook,
          ),
        );
        return identifier == null
            ? sheet
            : Semantics(container: true, identifier: identifier, child: sheet);
      },
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
  /// category is the answer, so the sheet returns it; in multi mode the list
  /// stays open and the new row joins the selection unless
  /// [CategoryPickerSheet.tickCreated] says otherwise.
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
      if (widget.tickCreated) _selected.add(created.id);
      _query = SettingsQuery.empty;
    });
  }

  /// The row's second line: its event count when the sheet was given counts
  /// — what a tick hands over — then "Hidden", joined as the Categories
  /// page joins its captions.
  String? _captionFor(CalendarCategory category, AppLocalizations l10n) {
    final counts = widget.counts;
    if (counts == null) {
      return category.isHidden ? l10n.categoryHidden : null;
    }
    return [
      l10n.categoryEventCount(counts[category.id] ?? 0),
      if (category.isHidden) l10n.categoryHidden,
    ].join(' · ');
  }

  /// A partner's row wears the look their events wear, but stays silent:
  /// the group's "From {name}" already says whose every row is, and a
  /// screen reader would otherwise hear it once per row (spec decision dk).
  Widget _partnerAvatar(CalendarCategory category) {
    final look = widget.partnerLook;
    return EventAvatar(
      icon: CalendarIcons.forKey(category.iconKey) ?? Icons.event_rounded,
      color: category.color,
      outlined: look.outlined,
      badge: look.avatar ? EventAvatarBadge.partner(look.partner) : null,
    );
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
    final listed = CalendarCategories.visiblePlus(widget.initialSelection);
    final exclude = widget.exclude;
    final categories = exclude.isEmpty
        ? listed
        : [
            for (final category in listed)
              if (!exclude.contains(category.id)) category,
          ];
    final rows = _isFiltering
        ? [
            for (final ranked in rankCategories(_query, categories, l10n))
              ranked.category,
          ]
        : categories;
    // The partner's group answers a query by the same ranking, apart, so
    // their rows never interleave with this person's.
    final partner = widget.partner;
    final partnerRows = _isFiltering && partner.isNotEmpty
        ? [
            for (final ranked in rankCategories(_query, partner, l10n))
              ranked.category,
          ]
        : partner;
    // Every row on screen, both groups: what Select all and Select none act
    // on, since they stand above both.
    final onScreen = partnerRows.isEmpty ? rows : [...rows, ...partnerRows];
    // Short lists carry no search chrome; the threshold trips on its own as
    // the set grows. `_isFiltering` holds the field open once it is in use,
    // the same rule the management page follows: a list that is filtered with
    // no field left to clear it is stranded, and the two searchable category
    // surfaces must not disagree about when the field is there.
    final showSearch =
        _isFiltering ||
        categories.length + partner.length > AppConstants.listSearchThreshold;
    // Nothing matched: the typed text is almost certainly the name the user
    // wants, so the one row left offers to create it rather than to start
    // over. A partner's row that matched means the name exists already.
    final typed = _searchController.text.trim();
    final createTyped = onScreen.isEmpty && typed.isNotEmpty;
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
          title:
              widget.title ??
              (_isMulti ? l10n.calendarCategories : l10n.eventCategory),
          scrolled: _headerScrolled,
          trailingInset: FormMetrics.headerActionInset,
          stackTitleAtLargeText: widget.title != null,
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
        if (widget.caption case final caption?)
          FormCaption(
            text: caption,
            padding: const EdgeInsets.fromLTRB(
              RowMetrics.groupInset,
              0,
              RowMetrics.groupInset,
              FormMetrics.headerCaptionBottomPadding,
            ),
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
                  // The section label below carries no top space of its own.
                  trailingGap: partnerRows.isNotEmpty,
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
                    if (_isMulti && onScreen.isNotEmpty) ...[
                      FormActionRow(
                        glyph: Icons.done_all_rounded,
                        label: l10n.categoriesSelectAll,
                        identifier: SemanticsIds.categoryPickSelectAll,
                        onTap: onScreen.every((c) => _selected.contains(c.id))
                            ? null
                            : () => _setAll(onScreen, true),
                      ),
                      FormActionRow(
                        glyph: Icons.remove_done_rounded,
                        label: l10n.categoriesSelectNone,
                        identifier: SemanticsIds.categoryPickSelectNone,
                        onTap: onScreen.every((c) => !_selected.contains(c.id))
                            ? null
                            : () => _setAll(onScreen, false),
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
                        caption: _captionFor(category, l10n),
                        checked: _selected.contains(category.id),
                        exclusive: !_isMulti,
                        identifier: SemanticsIds.categoryPickRow(category.id),
                        onChanged: (_) => _onTapCategory(category),
                      ),
                    if (!widget.sandbox)
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
                if (partnerRows.isNotEmpty) ...[
                  FormSectionLabel(
                    text: l10n.shareFromPartner(
                      ShareCopy.partnerName(l10n, widget.partnerLook.name),
                    ),
                  ),
                  FormRowGroup(
                    trailingGap: false,
                    children: [
                      for (final category in partnerRows)
                        FormCheckRow(
                          leading: _partnerAvatar(category),
                          label: CalendarCategories.labelOf(category, l10n),
                          checked: _selected.contains(category.id),
                          exclusive: !_isMulti,
                          identifier: SemanticsIds.categoryPickRow(category.id),
                          onChanged: (_) => _onTapCategory(category),
                        ),
                    ],
                  ),
                ],
                if (onScreen.isEmpty && _isFiltering)
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
