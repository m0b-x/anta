import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart' show CalendarFormat;

import '../constants/app_theme.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import 'automation_id.dart';
import 'form_menu_item.dart';

/// The two pages of the calendar feature, which [CalendarViewMenu] switches
/// between.
enum CalendarViewPage { calendar, overview }

/// The app-bar title of the calendar and the overview, as a menu: the page it
/// names, the other page one pick away and — on the calendar only — the
/// grid's Month / 2 weeks / Week, which is how the grid is looked at rather
/// than what it shows, and so belongs here rather than in the filter sheet.
///
/// A popup route like the app's overflow menus, never a `MenuAnchor`, whose
/// items expose no semantics nodes on iOS. Focus is dropped before the menu
/// opens: its return would otherwise hand focus back to a search field on the
/// page — the agenda's, or the overview's own — and raise the keyboard again.
///
/// The title carries the header and the route name itself, so a page sets
/// `AppBar.excludeHeaderSemantics`. `AppBar` puts both on an annotation
/// around its title, and a button that is a node of its own leaves that
/// annotation without a label: Android announces the route by the first
/// named node's label, and the page would open to silence.
class CalendarViewMenu extends StatelessWidget {
  const CalendarViewMenu({
    super.key,
    required this.page,
    required this.onPageSelected,
    this.format,
    this.onFormatSelected,
  });

  /// The page this title sits on: its name is the label and its row is
  /// checked.
  final CalendarViewPage page;

  /// Called with the other page. Picking the current one only closes the
  /// menu.
  final ValueChanged<CalendarViewPage> onPageSelected;

  /// The grid's format, checked in the menu's second group. Null leaves the
  /// group out: the overview has no grid.
  final CalendarFormat? format;

  /// Called with a format other than [format]. Null while the grid cannot
  /// take one yet — the rows stay, disabled.
  final ValueChanged<CalendarFormat>? onFormatSelected;

  /// `AppBar.titleSpacing` for a page wearing this title: the ink starts
  /// [titlePadding]'s start inset before the label, which stays where a plain
  /// title's would.
  static const double titleSpacing = 8;
  static const EdgeInsetsDirectional titlePadding = EdgeInsetsDirectional.only(
    start: 8,
    end: 4,
  );
  static const double titleRadius = 24;
  static const double glyphSize = 24;

  static String _labelOf(AppLocalizations l10n, CalendarViewPage page) {
    return switch (page) {
      CalendarViewPage.calendar => l10n.calendar,
      CalendarViewPage.overview => l10n.calendarOverview,
    };
  }

  static String _formatLabel(AppLocalizations l10n, CalendarFormat format) {
    return switch (format) {
      CalendarFormat.month => l10n.calendarFormatMonth,
      CalendarFormat.twoWeeks => l10n.calendarFormatTwoWeeks,
      CalendarFormat.week => l10n.calendarFormatWeek,
    };
  }

  /// `AppBar`'s own choice, platform by platform: iOS and macOS name a route
  /// their own way.
  static bool? get _namesRoute => switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.windows => true,
    TargetPlatform.iOS || TargetPlatform.macOS => null,
  };

  /// Android 9 and later speak a tooltip that sits beside a label only on a
  /// long press, never on focus, so there its words ride in the hint too.
  /// iOS folds the tooltip into the label already; a hint would say it twice.
  static String? _hintFor(String tooltip) =>
      defaultTargetPlatform == TargetPlatform.android ? tooltip : null;

  /// One outlined family whose rows say how much of the month shows.
  static IconData _formatIcon(CalendarFormat format) {
    return switch (format) {
      CalendarFormat.month => Icons.calendar_view_month_outlined,
      CalendarFormat.twoWeeks => Icons.view_agenda_outlined,
      CalendarFormat.week => Icons.view_day_outlined,
    };
  }

  static String _formatId(CalendarFormat format) {
    return switch (format) {
      CalendarFormat.month => SemanticsIds.calendarFormatMonth,
      CalendarFormat.twoWeeks => SemanticsIds.calendarFormatTwoWeeks,
      CalendarFormat.week => SemanticsIds.calendarFormatWeek,
    };
  }

  void _select(_ViewChoice choice) {
    switch (choice) {
      case _PageChoice(page: final picked):
        if (picked != page) onPageSelected(picked);
      case _FormatChoice(format: final picked):
        if (picked != format) onFormatSelected?.call(picked);
    }
  }

  List<PopupMenuEntry<_ViewChoice>> _items(AppLocalizations l10n) {
    final format = this.format;
    return [
      FormMenuChoiceItem<_ViewChoice>(
        value: const _PageChoice(CalendarViewPage.calendar),
        checked: page == CalendarViewPage.calendar,
        child: FormMenuItemRow(
          identifier: SemanticsIds.calendarViewCalendar,
          icon: Icons.calendar_month_rounded,
          label: _labelOf(l10n, CalendarViewPage.calendar),
          checked: page == CalendarViewPage.calendar,
        ),
      ),
      FormMenuChoiceItem<_ViewChoice>(
        value: const _PageChoice(CalendarViewPage.overview),
        checked: page == CalendarViewPage.overview,
        child: FormMenuItemRow(
          identifier: SemanticsIds.calendarOverviewOpen,
          icon: Icons.grid_view_rounded,
          label: _labelOf(l10n, CalendarViewPage.overview),
          checked: page == CalendarViewPage.overview,
        ),
      ),
      if (format != null) ...[
        const PopupMenuDivider(height: AppTheme.menuDividerHeight),
        for (final option in CalendarFormat.values)
          FormMenuChoiceItem<_ViewChoice>(
            value: _FormatChoice(option),
            checked: option == format,
            enabled: onFormatSelected != null,
            child: FormMenuItemRow(
              identifier: _formatId(option),
              icon: _formatIcon(option),
              label: _formatLabel(l10n, option),
              checked: option == format,
              enabled: onFormatSelected != null,
            ),
          ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return AutomationId(
      identifier: SemanticsIds.calendarViewMenu,
      child: Semantics(
        button: true,
        header: true,
        namesRoute: _namesRoute,
        hint: _hintFor(l10n.calendarViewMenuTooltip),
        child: PopupMenuButton<_ViewChoice>(
          tooltip: l10n.calendarViewMenuTooltip,
          position: PopupMenuPosition.under,
          borderRadius: BorderRadius.circular(titleRadius),
          constraints: _menuConstraints,
          onOpened: _dropFocus,
          onSelected: _select,
          itemBuilder: (_) => _items(l10n),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kMinInteractiveDimension,
            ),
            child: Padding(
              padding: titlePadding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _labelOf(l10n, page),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: glyphSize,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The ⋮ menu of the calendar and the overview: the Alerts hub, the `.ics`
/// export and the calendar's settings — last, below a divider, like the
/// Settings row every other ⋮ in the app ends with. It is labelled
/// "Calendar settings" because those rows open the app's settings.
class CalendarOverflowMenu extends StatelessWidget {
  const CalendarOverflowMenu({
    super.key,
    required this.onAlerts,
    required this.onExport,
    required this.onSettings,
  });

  final VoidCallback onAlerts;

  /// Null disables the row: there is nothing to export yet.
  final VoidCallback? onExport;

  final VoidCallback onSettings;

  void _select(_OverflowAction action) {
    switch (action) {
      case _OverflowAction.alerts:
        onAlerts();
      case _OverflowAction.export:
        onExport?.call();
      case _OverflowAction.settings:
        onSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AutomationId(
      identifier: SemanticsIds.calendarMore,
      child: PopupMenuButton<_OverflowAction>(
        icon: const Icon(Icons.more_vert),
        constraints: _menuConstraints,
        onOpened: _dropFocus,
        onSelected: _select,
        itemBuilder: (_) => [
          PopupMenuItem<_OverflowAction>(
            value: _OverflowAction.alerts,
            height: AppTheme.menuItemHeight,
            child: FormMenuItemRow(
              identifier: SemanticsIds.calendarAlertsOpen,
              icon: Icons.notifications_active_rounded,
              label: l10n.alertsTitle,
            ),
          ),
          PopupMenuItem<_OverflowAction>(
            value: _OverflowAction.export,
            height: AppTheme.menuItemHeight,
            enabled: onExport != null,
            child: FormMenuItemRow(
              identifier: SemanticsIds.calendarExport,
              icon: Icons.share_rounded,
              label: l10n.exportEventsIcs,
              enabled: onExport != null,
            ),
          ),
          const PopupMenuDivider(height: AppTheme.menuDividerHeight),
          PopupMenuItem<_OverflowAction>(
            value: _OverflowAction.settings,
            height: AppTheme.menuItemHeight,
            child: FormMenuItemRow(
              identifier: SemanticsIds.calendarSettingsOpen,
              icon: Icons.settings_outlined,
              label: l10n.calendarSettingsRow,
            ),
          ),
        ],
      ),
    );
  }
}

enum _OverflowAction { alerts, export, settings }

/// [AppTheme.menuWidth] as the floor, as in every menu of the app, but sized
/// to the labels up to [AppTheme.menuMaxWidth]: the German export row does
/// not fit 236.
const BoxConstraints _menuConstraints = BoxConstraints(
  minWidth: AppTheme.menuWidth,
  maxWidth: AppTheme.menuMaxWidth,
);

void _dropFocus() => FocusManager.instance.primaryFocus?.unfocus();

sealed class _ViewChoice {
  const _ViewChoice();
}

final class _PageChoice extends _ViewChoice {
  const _PageChoice(this.page);

  final CalendarViewPage page;
}

final class _FormatChoice extends _ViewChoice {
  const _FormatChoice(this.format);

  final CalendarFormat format;
}
