import 'package:flutter/material.dart';

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
import 'content_rows.dart';
import 'event_avatar.dart';
import 'form_menu_item.dart';
import 'form_rows.dart';
import 'settings_reorder.dart';
import 'value_change_highlight.dart';

enum _RowAction { moveToTop, edit, archive, delete }

/// The categories page's card: a list of three — two of the owner's
/// built-ins and one of hers — drawn as the categories page draws its rows
/// (the handle, the avatar, the name over its caption, the ⋮ with the
/// page's four items, archived rows under an Archived header), and Create
/// category through the real category form in its sandbox mode. Every
/// change lands in this list; the catalogue is never touched.
///
/// The rows sit in the card's own groups rather than on `ContentRowShell`:
/// the shell's 16 dp side insets are the page's margin to the screen edge,
/// which the stage already gives, and from 1.3 up — where the stage runs
/// edge to edge — they would narrow every row by 32 dp against the page's.
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

  /// How many times each row has flashed, as the page counts them.
  final Map<String, int> _flashes = {};

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
    // The page's flash after its reveal (K20). A fresh highlight never
    // flashes, so the count moves once the new row is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flashes[created.id] = (_flashes[created.id] ?? 0) + 1;
      changed();
    });
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

  /// The page's Move to top, within the row's own section. An archived row
  /// keeps its slot in the list through it, as the page pins archived slots.
  void _moveToTop(CalendarCategory category) {
    final rows = [
      for (final c in _rows!)
        if (c.id != category.id) c,
    ];
    final top = rows.indexWhere((c) => c.isHidden == category.isHidden);
    rows.insert(top < 0 ? rows.length : top, category);
    _rows = rows;
    changed();
  }

  /// Hiding is archiving: the row moves under the Archived header and keeps
  /// its slot in the list, so Restore brings it back where it was, as on the
  /// page. Restoring is a change like any other — it has no step of its own.
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

  /// The categories page's row menu, item for item and in its order, each
  /// disabled in place where the page disables it: Move to top on a
  /// section's first row, Archive on the last category in use, Delete on a
  /// built-in. Delete removes the row at once — the page's sheet asks where
  /// the events go, and nothing is filed under a sandbox category.
  Future<void> _openActions(
    BuildContext context,
    BuildContext anchor,
    CalendarCategory category, {
    required bool firstInSection,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    String control(String name) =>
        SemanticsIds.calendarGuideTryControl(slug, name);
    final inUse = _rows!.where((c) => !c.isHidden).length;
    final action = await showFormMenu<_RowAction>(
      anchor,
      items: [
        FormMenuItem(
          value: _RowAction.moveToTop,
          label: l10n.moveToTop,
          icon: Icons.vertical_align_top_rounded,
          identifier: control('move-to-top'),
          enabled: !firstInSection,
        ),
        FormMenuItem(
          value: _RowAction.edit,
          label: l10n.edit,
          icon: Icons.edit_rounded,
          identifier: control('edit'),
        ),
        FormMenuItem(
          value: _RowAction.archive,
          label: category.isHidden
              ? l10n.categoryRestore
              : l10n.categoryArchive,
          icon: category.isHidden
              ? Icons.unarchive_rounded
              : Icons.archive_rounded,
          identifier: control('archive'),
          enabled: category.isHidden || inUse > 1,
        ),
        FormMenuItem(
          value: _RowAction.delete,
          label: l10n.categoryDeleteEllipsis,
          icon: Icons.delete_rounded,
          identifier: control('delete'),
          enabled: !category.isBuiltIn,
          color: colorScheme.error,
        ),
      ],
      selected: null,
      menuWidth: FormMetrics.menuWidth,
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _RowAction.moveToTop:
        _moveToTop(category);
      case _RowAction.edit:
        await _edit(context, category);
      case _RowAction.archive:
        _toggleHidden(category);
      case _RowAction.delete:
        _delete(category);
    }
  }

  /// The page's caption with nothing to count: no event is ever filed under
  /// a sandbox category, and none of these carries an alert. The no-break
  /// space before each dot keeps a wrapped line from starting with it.
  static String _caption(AppLocalizations l10n, CalendarCategory category) => [
    l10n.categoryEventCount(0),
    if (category.isBuiltIn) l10n.categoryCaptionBuiltIn,
  ].join(' · ');

  /// The page's handle, drawn as the page draws it while reorder is on, but
  /// inert: the sandbox keeps no order to drag. Never dimmed — a dimmed
  /// handle says reorder is off for a reason she could undo. A tap on it is
  /// swallowed, as on the page, so it never opens the editor.
  static Widget _handle() => GestureDetector(
    onTap: () {},
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    child: const ReorderHandle(),
  );

  /// One row as the categories page lays it out — handle, avatar (the bare
  /// glyph from [RowMetrics.compactLeadingTextScale] up), the name over its
  /// caption, the ⋮ — with the page's one node per row and the ⋮ a sibling.
  /// An archived row dims only its leading, as the page's does.
  Widget _row(
    BuildContext context,
    CalendarCategory category,
    int index, {
    required bool firstInSection,
    required bool lastInSection,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    String control(String name) =>
        SemanticsIds.calendarGuideTryControl(slug, name);
    final name = CalendarCategories.labelOf(category, l10n);
    final caption = _caption(l10n, category);
    final archived = category.isHidden;
    final scaler = MediaQuery.textScalerOf(context);
    final compact =
        scaler.scale(RowMetrics.titleFontSize) / RowMetrics.titleFontSize >=
        RowMetrics.compactLeadingTextScale;
    final icon = CalendarIcons.forKey(category.iconKey) ?? Icons.event_rounded;
    Widget leading = compact
        ? ExcludeSemantics(
            child: Icon(
              icon,
              size: RowMetrics.glyphSize,
              color: category.color,
            ),
          )
        : EventAvatar(icon: icon, color: category.color);
    if (archived) {
      leading = Opacity(opacity: FormMetrics.disabledOpacity, child: leading);
    }
    void edit() => _edit(context, category);

    final texts = Padding(
      padding: EdgeInsets.symmetric(
        vertical: RowMetrics.twoLinePadding.vertical / 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: RowMetrics.titleFontSize,
              fontWeight: FontWeight.w400,
              height: FormMetrics.labelLineHeight / RowMetrics.titleFontSize,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: RowMetrics.lineGap),
          Text(
            caption,
            style: TextStyle(
              fontSize: RowMetrics.secondLineFontSize,
              height:
                  FormMetrics.captionLineHeight / RowMetrics.secondLineFontSize,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    final radius = Radius.circular(RowMetrics.groupRadius);
    // Keyed by the category, so a row's highlight never takes another
    // row's count when the list shifts under it.
    return FormIndentedRow(
      key: ValueKey(category.id),
      dividerIndent: compact
          ? RowMetrics.reorderGlyphTextInset
          : RowMetrics.reorderAvatarTextInset,
      child: ValueChangeHighlight(
        value: _flashes[category.id] ?? 0,
        borderRadius: BorderRadius.vertical(
          top: firstInSection ? radius : Radius.zero,
          bottom: lastInSection ? radius : Radius.zero,
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                container: true,
                identifier: control('row-$index'),
                button: true,
                excludeSemantics: true,
                label: [
                  name,
                  caption,
                  if (archived) l10n.categoryRowArchived,
                ].join('\n'),
                onTap: edit,
                child: InkWell(
                  onTap: edit,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: RowMetrics.twoLineMinHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: RowMetrics.reorderHandleLead,
                      ),
                      child: Row(
                        children: [
                          _handle(),
                          leading,
                          const SizedBox(width: RowMetrics.gap),
                          Expanded(child: texts),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Builder(
              builder: (anchor) => FormTrailingButton(
                icon: Icons.more_vert_rounded,
                tooltip: l10n.categoryActions,
                identifier: control('more-$index'),
                onPressed: () => _openActions(
                  context,
                  anchor,
                  category,
                  firstInSection: firstInSection,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The page's two sections: In use, then — only while a row is archived —
  /// the Archived header over its own group. Ids number the rows top to
  /// bottom across both.
  Widget _rowGroups(BuildContext context, List<CalendarCategory> rows) {
    final l10n = AppLocalizations.of(context)!;
    final inUse = [
      for (final c in rows)
        if (!c.isHidden) c,
    ];
    final archived = [
      for (final c in rows)
        if (c.isHidden) c,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Empty only when she deleted the last one in use.
        if (inUse.isNotEmpty)
          FormRowGroup(
            trailingGap: archived.isNotEmpty,
            children: [
              for (var i = 0; i < inUse.length; i++)
                _row(
                  context,
                  inUse[i],
                  i,
                  firstInSection: i == 0,
                  lastInSection: i == inUse.length - 1,
                ),
            ],
          ),
        if (archived.isNotEmpty) ...[
          ContentSectionHeader(
            label: l10n.categorySectionArchived,
            identifier: SemanticsIds.calendarGuideTryControl(slug, 'archived'),
          ),
          FormRowGroup(
            trailingGap: false,
            children: [
              for (var i = 0; i < archived.length; i++)
                _row(
                  context,
                  archived[i],
                  inUse.length + i,
                  firstInSection: i == 0,
                  lastInSection: i == archived.length - 1,
                ),
            ],
          ),
        ],
      ],
    );
  }

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
            // The list's height: the three seed rows laid out unseen with
            // the last one archived — the Archived header and its gap
            // counted — so a row archived, restored, created or deleted
            // never moves the card or the page under her finger. More rows
            // scroll inside it.
            ExcludeSemantics(
              child: ExcludeFocus(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0,
                    child: _rowGroups(context, [
                      ...seed.take(seed.length - 1),
                      seed.last.copyWith(isHidden: true),
                    ]),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: SingleChildScrollView(child: _rowGroups(context, rows)),
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
