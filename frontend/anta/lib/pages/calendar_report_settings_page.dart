import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/report_cards.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/automation_id.dart';
import '../widgets/form_rows.dart';
import '../widgets/settings_reorder.dart';
import '../widgets/settings_section_list.dart' show settingsCaptionStyle;
import '../widgets/unified_app_bars.dart';

/// Settings → Calendar → Report cards (W of
/// `docs/calendar-analytics-roadmap.md`): the report's cards in the order the
/// page draws them, each with a switch. An off card keeps its row, so it is
/// turned back on where it will sit; the report re-reads the setting when it
/// is shown again, so every change here is live there.
///
/// The cards are a reorderable sliver, which the kit's `ListView` of groups
/// cannot hold, so the page draws the kit's group by hand: its ground, its
/// intro line inside the group's top, its rows on the same tokens.
class CalendarReportSettingsPage extends StatefulWidget {
  const CalendarReportSettingsPage({super.key});

  /// A card's name — the section label the report heads it with, so a row
  /// here reads as the card it moves.
  static String cardName(ReportCardKind kind, AppLocalizations l10n) =>
      switch (kind) {
        ReportCardKind.goals => l10n.reportSectionGoals,
        ReportCardKind.insights => l10n.reportSectionInsights,
        ReportCardKind.dueSoon => l10n.reportSectionDueSoon,
        ReportCardKind.totals => l10n.reportSectionTotals,
        ReportCardKind.records => l10n.reportSectionRecords,
        ReportCardKind.months => l10n.reportSectionMonths,
        ReportCardKind.categories => l10n.reportSectionCategories,
        ReportCardKind.tags => l10n.reportSectionTags,
        ReportCardKind.overTime => l10n.reportSectionOverTime,
        ReportCardKind.when => l10n.reportSectionWhen,
        ReportCardKind.balance => l10n.reportSectionBalance,
        ReportCardKind.missed => l10n.reportSectionMissed,
        ReportCardKind.ahead => l10n.reportSectionAhead,
      };

  @override
  State<CalendarReportSettingsPage> createState() =>
      _CalendarReportSettingsPageState();
}

class _CalendarReportSettingsPageState
    extends State<CalendarReportSettingsPage> {
  SettingsService? _settings;
  bool _isLoading = true;
  bool _hapticFeedback = true;
  ReportCards _cards = ReportCards.defaults;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    final loaded = await settings.getCalendarReportSettings(
      today: DateUtils.dateOnly(DateTime.now()),
    );
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _hapticFeedback = loaded.hapticFeedback;
      _cards = loaded.cards;
      _isLoading = false;
    });
  }

  /// Optimistic like every settings row: the list moves at once and the
  /// write follows, so a drag never snaps back while the database answers.
  Future<void> _apply(ReportCards next) async {
    if (next == _cards) return;
    setState(() => _cards = next);
    await _settings?.setReportCards(next);
  }

  void _move(int oldIndex, int newIndex) {
    _onHapticFeedback();
    _apply(_cards.moved(oldIndex, newIndex));
  }

  void _toggle(ReportCardKind kind, bool on) {
    _onHapticFeedback();
    _apply(_cards.toggled(kind, on));
  }

  Future<void> _reset() async {
    _onHapticFeedback();
    final message = AppLocalizations.of(context)!.reportCardsResetDone;
    await _apply(ReportCards.defaults);
    if (!mounted) return;
    CustomSnackbar.showSuccess(context, message);
  }

  void _onHapticFeedback() {
    if (_hapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  /// The lifted row: the shared proxy over a clip, since a middle row of the
  /// group paints square corners of its own (the palette sheet's rows).
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: colorScheme.pageGround,
      appBar: SettingsAppBar(
        title: l10n.calendarSettingsReportTitle,
        identifier: SemanticsIds.settingsBarReportCards,
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildList(colorScheme, l10n),
      ),
    );
  }

  Widget _buildList(ColorScheme colorScheme, AppLocalizations l10n) {
    final order = _cards.order;
    // The list owns the nearest `Scrollable`, which is what binds the
    // reorderable sliver's edge auto-scroller to the thing that scrolls: at
    // text scale 2.0 the thirteen rows run past the fold.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            RowMetrics.groupInset,
            RowMetrics.groupInset,
            RowMetrics.groupInset,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _GroupIntro(text: l10n.calendarSettingsReportDescription),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: RowMetrics.groupInset,
          ),
          sliver: SliverReorderableList(
            itemCount: order.length,
            proxyDecorator: _liftedRow,
            onReorderItem: _move,
            itemBuilder: (context, index) {
              final kind = order[index];
              return ReorderableDelayedDragStartListener(
                key: ValueKey(kind),
                index: index,
                child: FormRowShell(
                  first: false,
                  last: index == order.length - 1,
                  child: _CardRow(
                    name: CalendarReportSettingsPage.cardName(kind, l10n),
                    kind: kind,
                    index: index,
                    on: !_cards.off.contains(kind),
                    onChanged: (on) => _toggle(kind, on),
                    onMoveUp: index == 0 ? null : () => _move(index, index - 1),
                    onMoveDown: index == order.length - 1
                        ? null
                        : () => _move(index, index + 1),
                  ),
                ),
              );
            },
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            RowMetrics.groupInset,
            0,
            RowMetrics.groupInset,
            RowMetrics.groupInset,
          ),
          sliver: SliverToBoxAdapter(
            child: FormRowGroup(
              trailingGap: false,
              children: [
                FormActionRow(
                  glyph: Icons.refresh_rounded,
                  label: l10n.reportCardsReset,
                  identifier: SemanticsIds.reportCardsReset,
                  onTap: _cards == ReportCards.defaults ? null : _reset,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The group's top: the kit's intro line, inset as a row's text and set in
/// the caption role, with no hairline under it — the rows below continue
/// the same group.
class _GroupIntro extends StatelessWidget {
  final String text;

  const _GroupIntro({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.card,
      color: colorScheme.rowGroup,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(RowMetrics.groupRadius),
      ),
      child: Padding(
        padding: FormMetrics.settingsRowPadding.copyWith(
          top: FormMetrics.settingsRowVerticalPadding,
          bottom: FormMetrics.settingsRowVerticalPadding,
        ),
        child: Text(
          text,
          style: settingsCaptionStyle.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// `≡ name ⟷` — one card: the handle at the row's start and the switch at
/// its end, so neither moves with the name, which wraps rather than cuts.
/// Two nodes besides the row's: the handle, named "Reorder …", and the
/// switch, named by the card. The handle's name promises a reorder and a
/// screen reader cannot drag, so its node carries the move as two actions,
/// each absent where the row cannot go. An off card's name dims to
/// [FormMetrics.switchedOffOpacity] — off, not disabled: the switch stays
/// full, and the row stays a control to hold and drag.
class _CardRow extends FormDividedRow {
  final String name;
  final ReportCardKind kind;
  final int index;
  final bool on;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _CardRow({
    required this.name,
    required this.kind,
    required this.index,
    required this.on,
    required this.onChanged,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    Widget label = Text(
      name,
      style: TextStyle(
        fontSize: RowMetrics.titleFontSize,
        height: FormMetrics.labelLineHeight / RowMetrics.titleFontSize,
        fontWeight: FontWeight.w400,
        color: colorScheme.onSurface,
      ),
    );
    if (!on) {
      label = Opacity(opacity: FormMetrics.switchedOffOpacity, child: label);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
      child: Row(
        children: [
          AutomationId(
            identifier: SemanticsIds.reportCardHandle(kind.name),
            child: Semantics(
              customSemanticsActions: {
                CustomSemanticsAction(label: l10n.categoryMoveUp): ?onMoveUp,
                CustomSemanticsAction(label: l10n.categoryMoveDown):
                    ?onMoveDown,
              },
              child: FormDragHandle(
                index: index,
                label: l10n.categoryReorderLabel(name),
              ),
            ),
          ),
          const SizedBox(
            width: FormMetrics.dividerIndentGlyph - FormMetrics.dragHandleSlot,
          ),
          // The whole span past the handle toggles, as a kit switch row
          // does; the switch alone carries the node, so a screen reader
          // hears the card once.
          Expanded(
            child: InkWell(
              excludeFromSemantics: true,
              onTap: () => onChanged(!on),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: FormMetrics.settingsRowVerticalPadding,
                ),
                child: ExcludeSemantics(child: label),
              ),
            ),
          ),
          const SizedBox(width: FormMetrics.gap),
          AutomationId(
            identifier: SemanticsIds.reportCardSwitch(kind.name),
            child: Semantics(
              label: name,
              child: Switch(
                value: on,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
            ),
          ),
          const SizedBox(width: FormMetrics.rowEndPadding),
        ],
      ),
    );
  }
}
