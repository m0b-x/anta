import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_theme.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_colors.dart';
import '../constants/calendar_icons.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_guide_content.dart';
import '../models/calendar_guide_demo.dart';
import 'calendar_guide_try_card.dart';
import 'category_editor_sheet.dart';
import 'event_avatar.dart';
import 'form_menu_item.dart';
import 'form_rows.dart';

enum _RowAction { edit, delete }

/// The categories page's card: a list of three — two of the owner's
/// built-ins and one of hers — with the categories page's eye and ⋮, and
/// Create category through the real category form in its sandbox mode.
/// Every change lands in this list; the catalogue is never touched.
class GuideCategoriesDemo extends GuideCardDemo {
  GuideCategoriesDemo() : super(CalendarGuideTopic.categories.cards.single);

  static const String slug = 'categories';

  /// The most rows the list holds: past it Create category is disabled, so
  /// the list stays a demo rather than a second catalogue.
  static const int maxRows = 6;

  /// Null until the first build, which names the custom row in her
  /// language. The seed also sizes the stage.
  List<CalendarCategory>? _seedRows;
  List<CalendarCategory>? _rows;

  /// The first two visible built-ins, from the seed catalogue when the
  /// catalogue has not loaded (a relaunch onto the guide), and the book club
  /// in a colour neither of them wears.
  List<CalendarCategory> _seed(AppLocalizations l10n) {
    final builtIns = [
      for (final category in CalendarCategories.visible)
        if (category.isBuiltIn) category,
    ];
    if (builtIns.length < 2) {
      builtIns
        ..clear()
        ..addAll([
          for (final (i, seed) in CalendarCategories.builtInSeeds.indexed)
            CalendarCategory(
              id: seed.id,
              name: CalendarCategories.builtInSeedName(seed.kind),
              colorValue: seed.colorValue,
              iconKey: seed.iconKey,
              sortOrder: i,
              isBuiltIn: true,
            ),
        ]);
    }
    final shown = builtIns.take(2).toList();
    return [
      ...shown,
      CalendarCategory(
        id: '${GuideDemoCalendar.idPrefix}category',
        name: l10n.calendarGuideDemoEventBookClub,
        colorValue: CalendarColors.swatchPalette.firstWhere(
          (color) => shown.every((c) => c.colorValue != color),
        ),
        iconKey: 'menu_book',
        sortOrder: shown.length,
        isBuiltIn: false,
      ),
    ];
  }

  void _replace(CalendarCategory category) {
    _rows = [for (final c in _rows!) c.id == category.id ? category : c];
  }

  Future<void> _create(BuildContext context) async {
    final created = await CategoryEditorSheet.show(context, sandbox: true);
    if (created == null) return;
    _rows = [..._rows!, created];
    did('created');
  }

  Future<void> _edit(BuildContext context, CalendarCategory category) async {
    final edited = await CategoryEditorSheet.show(
      context,
      initial: category,
      sandbox: true,
    );
    if (edited == null) return;
    _replace(edited);
    changed();
  }

  /// Hiding is archiving: the row stays, dimmed, and showing it again is a
  /// change like any other — it has no step of its own.
  void _toggleHidden(CalendarCategory category) {
    final next = category.copyWith(isHidden: !category.isHidden);
    _replace(next);
    if (next.isHidden) {
      did('hidden');
    } else {
      changed();
    }
  }

  void _delete(CalendarCategory category) {
    _rows = [
      for (final c in _rows!)
        if (c.id != category.id) c,
    ];
    did('deleted');
  }

  /// The preset ⋮'s actions menu (`filter_preset_sheet.dart`): its items
  /// can be disabled, which a choice menu's cannot — Delete stays in place
  /// on a built-in, at 38 %, as the language wants.
  Future<void> _openActions(
    BuildContext context,
    BuildContext anchor,
    CalendarCategory category,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final canDelete = !category.isBuiltIn;
    final action = await showMenu<_RowAction>(
      context: anchor,
      positionBuilder: (_, constraints) => formMenuPosition(
        anchor,
        constraints,
        menuHeight: formMenuHeight(_RowAction.values.length),
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
        PopupMenuItem<_RowAction>(
          value: _RowAction.edit,
          height: FormMetrics.menuRowHeight,
          child: FormMenuItemRow(
            identifier: SemanticsIds.calendarGuideTryControl(slug, 'edit'),
            icon: Icons.edit_outlined,
            label: l10n.edit,
          ),
        ),
        PopupMenuItem<_RowAction>(
          value: _RowAction.delete,
          height: FormMetrics.menuRowHeight,
          enabled: canDelete,
          child: FormMenuItemRow(
            identifier: SemanticsIds.calendarGuideTryControl(slug, 'delete'),
            icon: Icons.delete_outline_rounded,
            label: l10n.delete,
            enabled: canDelete,
            color: canDelete ? colorScheme.error : null,
          ),
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _RowAction.edit:
        await _edit(context, category);
      case _RowAction.delete:
        _delete(category);
    }
  }

  Widget _row(BuildContext context, CalendarCategory category, int index) {
    final l10n = AppLocalizations.of(context)!;
    String control(String name) =>
        SemanticsIds.calendarGuideTryControl(slug, name);
    // The eye inside the row, the ⋮ beside it: a row takes one trailing
    // button. A hidden row dims whole, its buttons with it, as on the
    // categories page.
    return FormIndentedRow(
      dividerIndent: FormMetrics.dividerIndentTitle,
      child: Opacity(
        opacity: category.isHidden ? FormMetrics.disabledOpacity : 1,
        child: Row(
          children: [
            Expanded(
              child: FormPickerRow(
                leading: EventAvatar(
                  icon:
                      CalendarIcons.forKey(category.iconKey) ??
                      Icons.event_rounded,
                  color: category.color,
                ),
                // No "Built-in category" line: beside two buttons, at 2.0 on
                // a 360 phone, its German and Romanian words break mid-word.
                // A built-in shows itself by its Delete, drawn disabled.
                label: CalendarCategories.labelOf(category, l10n),
                identifier: control('row-$index'),
                onTap: () => _edit(context, category),
                trailingButton: FormTrailingButton(
                  icon: category.isHidden
                      ? Icons.visibility_off
                      : Icons.visibility,
                  tooltip: category.isHidden ? l10n.show : l10n.hide,
                  identifier: control('eye-$index'),
                  onPressed: () => _toggleHidden(category),
                ),
              ),
            ),
            Builder(
              builder: (anchor) => FormTrailingButton(
                icon: Icons.more_vert,
                // What the categories page's ⋮ says: Material's own menu
                // button words.
                tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                identifier: control('more-$index'),
                onPressed: () => _openActions(context, anchor, category),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowGroup(BuildContext context, List<CalendarCategory> rows) =>
      FormRowGroup(
        trailingGap: false,
        children: [
          for (var i = 0; i < rows.length; i++) _row(context, rows[i], i),
        ],
      );

  @override
  Widget buildStage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final seed = _seedRows ??= _seed(l10n);
    final rows = _rows ??= seed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            // The list's height: the three seed rows laid out unseen, so a
            // row created or deleted never moves the card or the page
            // under her finger. More rows scroll inside it.
            ExcludeSemantics(
              child: ExcludeFocus(
                child: IgnorePointer(
                  child: Opacity(opacity: 0, child: _rowGroup(context, seed)),
                ),
              ),
            ),
            Positioned.fill(
              child: SingleChildScrollView(child: _rowGroup(context, rows)),
            ),
          ],
        ),
        const SizedBox(height: RowMetrics.groupGap),
        FormRowGroup(
          trailingGap: false,
          children: [
            FormActionRow(
              glyph: Icons.add_rounded,
              label: l10n.createCategory,
              identifier: SemanticsIds.calendarGuideTryControl(slug, 'add'),
              onTap: rows.length < maxRows ? () => _create(context) : null,
            ),
          ],
        ),
      ],
    );
  }
}
