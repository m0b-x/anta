import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/app_theme.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/overview_view.dart';
import '../services/folder_search_service.dart' show normalizeForSearch;
import '../services/overview_view_service.dart';
import 'app_dialogs.dart';
import 'filter_preset_sheet.dart' show FilterPresetNameDialog;
import 'form_menu_item.dart';
import 'form_rows.dart';
import 'overlay_snackbar.dart';
import 'settings_reorder.dart';

/// Bottom sheet listing the overview's saved views (D17 · A): one two-line
/// row per view with its drag handle and its ⋮, then the row that saves the
/// list as shown — [FilterPresetSheet]'s chrome one for one, opened from the
/// overview bar's bookmarks button.
///
/// No "None" row: a view is applied, never cleared — the overview always
/// shows some list. A row tap hands the view to [onApply] and closes; a
/// rename, an update, a delete or a reorder happens in place and keeps the
/// sheet open, so tidying the list never applies anything.
///
/// The body is one `ReorderableListView` that owns its scrolling, the search
/// row, the views and the save row drawn as one group — the preset sheet's
/// reasons hold here unchanged.
class OverviewViewSheet extends StatefulWidget {
  /// The list the overview shows right now: what "Save the current list" and
  /// "Update to current list" write, and what puts the ✓ on its row. Its id
  /// and name are unused.
  final OverviewView current;

  final ValueChanged<OverviewView> onApply;

  const OverviewViewSheet({
    super.key,
    required this.current,
    required this.onApply,
  });

  /// The sub-sheet shape: as tall as its content, clamped at the editor's
  /// height, the route's own drag, no guard.
  static Future<void> show(
    BuildContext context, {
    required OverviewView current,
    required ValueChanged<OverviewView> onApply,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<void>(
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
      // Every save and delete resizes the sheet on a dialog's answer.
      builder: (context) => FormSheetSemanticsRefresh(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                MediaQuery.sizeOf(context).height *
                FormMetrics.sheetHeightFactor,
          ),
          child: OverviewViewSheet(current: current, onApply: onApply),
        ),
      ),
    );
  }

  @override
  State<OverviewViewSheet> createState() => _OverviewViewSheetState();
}

class _OverviewViewSheetState extends State<OverviewViewSheet> {
  final TextEditingController _search = TextEditingController();

  OverviewViewService? _service;
  List<OverviewView> _views = const [];
  bool _loading = true;

  /// Folded once per keystroke rather than once per row.
  String _query = '';

  /// Feeds the header's hairline through a notifier, so a scroll frame
  /// rebuilds a 1 px line and not the sheet.
  final ScrollController _bodyScroll = ScrollController();
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _bodyScroll.addListener(_onBodyScroll);
    _load();
  }

  @override
  void dispose() {
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    _headerScrolled.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onBodyScroll() {
    final scrolled = _bodyScroll.hasClients && _bodyScroll.offset > 0;
    if (_headerScrolled.value != scrolled) _headerScrolled.value = scrolled;
  }

  Future<void> _load() async {
    try {
      final service = await OverviewViewService.getInstance();
      if (!mounted) return;
      setState(() {
        _service = service;
        _views = service.views;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[OverviewViewSheet] View load failed: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = normalizeForSearch(value));
  }

  /// Never autofocused, kept while a query is live — the preset sheet's rule.
  bool get _showSearch =>
      _views.length > AppConstants.listSearchThreshold || _query.isNotEmpty;

  /// Off while a query is live: a filtered run's render index no longer maps
  /// to a stored position.
  bool get _canReorder => _query.isEmpty;

  bool _inUse(OverviewView view) => view.matches(
    widget.current.period,
    widget.current.options,
    widget.current.categoryIds,
  );

  /// Applies [ordered] optimistically, then persists it; reconciling with the
  /// service afterwards makes a failed write visibly spring back.
  Future<void> _persistOrder(List<OverviewView> ordered) async {
    final service = _service;
    if (service == null) return;
    setState(() => _views = ordered);
    try {
      await service.reorder([for (final view in ordered) view.id]);
    } catch (e) {
      debugPrint('[OverviewViewSheet] Reorder failed: $e');
    } finally {
      if (mounted) setState(() => _views = service.views);
    }
  }

  /// A drop mapped into the view run and clamped to its ends, so a view can
  /// never land above the search row or below the save row.
  void _onReorder(int oldIndex, int newIndex) {
    if (!_canReorder) return;
    final offset = _showSearch ? 1 : 0;
    final count = _views.length;
    final from = oldIndex - offset;
    if (from < 0 || from >= count) return;
    final to = (newIndex - offset).clamp(0, count - 1);
    if (from == to) return;
    final ordered = List<OverviewView>.from(_views);
    final moved = ordered.removeAt(from);
    ordered.insert(to, moved);
    _persistOrder(ordered);
  }

  Future<void> _moveToTop(OverviewView view) {
    final ordered = List<OverviewView>.from(_views)
      ..removeWhere((v) => v.id == view.id)
      ..insert(0, view);
    return _persistOrder(ordered);
  }

  Widget _liftedRow(Widget child, int index, Animation<double> animation) {
    return reorderDragProxy(
      ClipRRect(
        borderRadius: BorderRadius.circular(reorderProxyRadius),
        child: child,
      ),
      index,
      animation,
    );
  }

  /// The row's caption: the period in the Period menu's own words, so a view
  /// is findable by its span as well as by its name.
  String _caption(OverviewView view, AppLocalizations l10n) =>
      view.period.menuValue(l10n);

  List<OverviewView> _visible(AppLocalizations l10n) {
    if (_query.isEmpty) return _views;
    return [
      for (final view in _views)
        if (normalizeForSearch(view.name).contains(_query) ||
            normalizeForSearch(_caption(view, l10n)).contains(_query))
          view,
    ];
  }

  /// Folded names of every view except [excluding], for the naming dialog's
  /// soft duplicate warning.
  Set<String> _otherNames({String? excluding}) {
    return {
      for (final view in _views)
        if (view.id != excluding) normalizeForSearch(view.name),
    };
  }

  Future<void> _saveCurrent() async {
    final service = _service;
    if (service == null) return;
    final l10n = AppLocalizations.of(context)!;
    if (service.isFull) {
      _report(l10n.overviewViewLimitReached(OverviewViewService.maxViews));
      return;
    }
    final current = widget.current;
    final name = await FilterPresetNameDialog.show(
      context,
      title: l10n.overviewViewSaveCurrent,
      initialName: _caption(current, l10n),
      existingNames: _otherNames(),
    );
    if (name == null || !mounted) return;
    final saved = await service.create(
      name: name,
      period: current.period,
      options: current.options,
      categoryIds: current.categoryIds,
    );
    if (!mounted) return;
    if (saved == null) {
      _report(l10n.overviewViewLimitReached(OverviewViewService.maxViews));
      return;
    }
    // Stays open: the list is already shown, so there is nothing to apply —
    // the new row, marked in use, and the message are the confirmation.
    setState(() => _views = service.views);
    _report(l10n.overviewViewSaved(saved.name));
  }

  Future<void> _rename(OverviewView view) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await FilterPresetNameDialog.show(
      context,
      title: l10n.filterPresetRename,
      initialName: view.name,
      existingNames: _otherNames(excluding: view.id),
    );
    if (name == null || !mounted) return;
    await _service?.update(view.copyWith(name: name));
    if (!mounted) return;
    setState(() => _views = _service?.views ?? const []);
  }

  /// In the overlay, not the page's `Scaffold`: a bar raised there is drawn
  /// under this sheet.
  void _report(String message) {
    if (!mounted) return;
    OverlaySnackbar.show(
      context,
      message,
      duration: AppConstants.snackbarDuration,
    );
  }

  /// Re-points a view at the list shown now — "I tweaked this and want to
  /// keep the tweak" without deleting and re-saving under the same name.
  Future<void> _updateToCurrent(OverviewView view) async {
    final current = widget.current;
    await _service?.update(
      view.copyWith(
        period: current.period,
        options: current.options,
        categoryIds: current.categoryIds,
      ),
    );
    if (!mounted) return;
    setState(() => _views = _service?.views ?? const []);
  }

  Future<void> _delete(OverviewView view) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.overviewViewDelete,
      content: l10n.overviewViewDeleteConfirm(view.name),
      confirmText: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await _service?.delete(view.id);
    if (!mounted) return;
    setState(() => _views = _service?.views ?? const []);
  }

  /// The row's ⋮: Rename · Update to current list · Move to top · Delete.
  /// Focus is dropped first, or the route's return would raise the keyboard
  /// under the menu's answer.
  Future<void> _openActions(
    BuildContext anchor,
    OverviewView view, {
    required bool inUse,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final canUpdate = !inUse;
    final canMoveToTop =
        _canReorder && _views.isNotEmpty && _views.first.id != view.id;
    FocusManager.instance.primaryFocus?.unfocus();
    final action = await showMenu<_ViewAction>(
      context: anchor,
      positionBuilder: (_, constraints) => formMenuPosition(
        anchor,
        constraints,
        menuHeight: formMenuHeight(_ViewAction.values.length),
      ),
      color: colorScheme.menuSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FormMetrics.menuRadius),
      ),
      menuPadding: FormMetrics.menuPadding,
      constraints: const BoxConstraints(
        minWidth: AppTheme.menuWidth,
        maxWidth: AppTheme.menuMaxWidth,
      ),
      items: [
        PopupMenuItem<_ViewAction>(
          value: _ViewAction.rename,
          height: FormMetrics.menuRowHeight,
          child: FormMenuItemRow(
            identifier: SemanticsIds.overviewViewsRename,
            icon: Icons.drive_file_rename_outline_rounded,
            label: l10n.filterPresetRename,
          ),
        ),
        PopupMenuItem<_ViewAction>(
          value: _ViewAction.update,
          height: FormMetrics.menuRowHeight,
          enabled: canUpdate,
          child: FormMenuItemRow(
            identifier: SemanticsIds.overviewViewsUpdate,
            icon: Icons.sync_rounded,
            label: l10n.overviewViewUpdate,
            enabled: canUpdate,
          ),
        ),
        PopupMenuItem<_ViewAction>(
          value: _ViewAction.moveToTop,
          height: FormMetrics.menuRowHeight,
          enabled: canMoveToTop,
          child: FormMenuItemRow(
            identifier: SemanticsIds.overviewViewsMoveTop,
            icon: Icons.vertical_align_top_rounded,
            label: l10n.moveToTop,
            enabled: canMoveToTop,
          ),
        ),
        PopupMenuItem<_ViewAction>(
          value: _ViewAction.delete,
          height: FormMetrics.menuRowHeight,
          child: FormMenuItemRow(
            identifier: SemanticsIds.overviewViewsDelete,
            icon: Icons.delete_outline_rounded,
            label: l10n.delete,
            color: colorScheme.error,
          ),
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _ViewAction.rename:
        await _rename(view);
      case _ViewAction.update:
        await _updateToCurrent(view);
      case _ViewAction.moveToTop:
        await _moveToTop(view);
      case _ViewAction.delete:
        await _delete(view);
    }
  }

  void _apply(OverviewView view) {
    widget.onApply(view);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final visible = _visible(l10n);
    final canReorder = _canReorder;
    // Disabled, never hidden: while the list shown is already saved, and
    // while a query is live.
    final canSave =
        !_loading && _query.isEmpty && _service != null && !_views.any(_inUse);
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    final items = <_Item>[
      if (_showSearch) const _SearchItem(),
      for (final view in visible) _ViewItem(view),
      const _SaveItem(),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.overviewViewsClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.overviewViewsTitle,
          scrolled: _headerScrolled,
          trailingInset: FormMetrics.headerActionInset,
          // A pick-on-tap list confirms nothing.
          trailing: const SizedBox.shrink(),
        ),
        Flexible(
          child: ReorderableListView.builder(
            scrollController: _bodyScroll,
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            padding: EdgeInsets.fromLTRB(
              RowMetrics.groupInset,
              FormMetrics.bodyTop,
              RowMetrics.groupInset,
              FormMetrics.bodyBottom + clearance,
            ),
            footer: visible.isEmpty && _query.isNotEmpty
                ? FormCaption(
                    text: l10n.overviewViewNoMatches,
                    padding: FormMetrics.groupCaptionPadding,
                  )
                : null,
            itemCount: items.length,
            itemBuilder: (context, index) => _buildItem(
              items,
              index,
              l10n,
              canReorder: canReorder,
              canSave: canSave,
            ),
            onReorderStart: (_) =>
                FocusManager.instance.primaryFocus?.unfocus(),
            onReorderItem: _onReorder,
            proxyDecorator: _liftedRow,
          ),
        ),
      ],
    );
  }

  Widget _buildItem(
    List<_Item> items,
    int index,
    AppLocalizations l10n, {
    required bool canReorder,
    required bool canSave,
  }) {
    final item = items[index];
    final Widget row = switch (item) {
      _SearchItem() => FormSearchRow(
        controller: _search,
        hint: l10n.overviewViewSearchHint,
        clearTooltip: l10n.upcomingClearSearch,
        identifier: SemanticsIds.overviewViewsSearch,
        onChanged: _onQueryChanged,
      ),
      _ViewItem(:final view) => _ViewRow(
        view: view,
        index: index,
        canReorder: canReorder,
        inUse: _inUse(view),
        caption: _caption(view, l10n),
        reorderLabel: l10n.filterPresetReorder,
        actionsTooltip: l10n.overviewViewActions,
        onPick: () => _apply(view),
        onActions: (anchor, inUse) => _openActions(anchor, view, inUse: inUse),
      ),
      _SaveItem() => FormActionRow(
        glyph: Icons.bookmark_add_outlined,
        label: l10n.overviewViewSaveCurrent,
        identifier: SemanticsIds.overviewViewsSave,
        onTap: canSave ? _saveCurrent : null,
      ),
    };
    final shell = FormRowShell(
      first: index == 0,
      last: index == items.length - 1,
      trailingGap: false,
      child: row,
    );
    if (item case _ViewItem()) {
      return ReorderableDelayedDragStartListener(
        key: item.key,
        index: index,
        enabled: canReorder,
        child: shell,
      );
    }
    return KeyedSubtree(key: item.key, child: shell);
  }
}

enum _ViewAction { rename, update, moveToTop, delete }

/// One entry of the sheet's reorderable list; the search and save rows are
/// items of the same list so the run draws as one group.
sealed class _Item {
  const _Item();

  Key get key;
}

class _SearchItem extends _Item {
  const _SearchItem();

  @override
  Key get key => const _FixedRowKey('search');
}

class _ViewItem extends _Item {
  final OverviewView view;

  const _ViewItem(this.view);

  @override
  Key get key => ValueKey(view.id);
}

class _SaveItem extends _Item {
  const _SaveItem();

  @override
  Key get key => const _FixedRowKey('save');
}

/// Its own key type, so a view id reading "search" or "save" (a hand-edited
/// backup) can never collide with a fixed row.
class _FixedRowKey extends ValueKey<String> {
  const _FixedRowKey(super.value);
}

/// One view as a two-line check row — the name over its period, the ✓ while
/// it is the list shown — with its drag handle at the start and its ⋮ at the
/// end, a `FormDividedRow` of its own so the ⋮ anchors its menu to the row.
class _ViewRow extends FormDividedRow {
  final OverviewView view;
  final int index;
  final bool canReorder;
  final bool inUse;
  final String caption;
  final String reorderLabel;
  final String actionsTooltip;
  final VoidCallback onPick;
  final void Function(BuildContext anchor, bool inUse) onActions;

  const _ViewRow({
    required this.view,
    required this.index,
    required this.canReorder,
    required this.inUse,
    required this.caption,
    required this.reorderLabel,
    required this.actionsTooltip,
    required this.onPick,
    required this.onActions,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    return FormCheckRow(
      exclusive: true,
      handle: FormDragHandle(
        index: index,
        enabled: canReorder,
        label: reorderLabel,
        identifier: SemanticsIds.overviewViewHandle(view.id),
      ),
      label: view.name,
      caption: caption,
      checked: inUse,
      identifier: SemanticsIds.overviewViewRow(view.id),
      onChanged: (_) => onPick(),
      trailingButton: FormTrailingButton(
        icon: Icons.more_vert_rounded,
        tooltip: actionsTooltip,
        identifier: SemanticsIds.overviewViewOptions(view.id),
        onPressed: () => onActions(context, inUse),
      ),
    );
  }
}
