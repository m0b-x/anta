import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_palette.dart';
import '../constants/form_metrics.dart';
import '../constants/semantics_ids.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../services/calendar_palette_service.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/calendar_appearance_preview.dart';
import '../widgets/color_palette_sheet.dart';
import '../widgets/color_swatch_picker.dart';
import '../widgets/form_menu_item.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/slider_setting_row.dart';
import '../widgets/unified_app_bars.dart';
import '../widgets/value_change_highlight.dart';

/// Every calendar look & feel option, on its own route with the live preview
/// **pinned** above the scroll view.
///
/// The rows used to be one section of [CalendarSettingsPage], with the preview
/// in that section's `intro:` — which meant it scrolled away exactly as the
/// user reached the day-rail rows at the bottom, the settings furthest from
/// the thing they change. Here the preview is a fixed `Column` child: it stays
/// on screen while the list scrolls and while the keyboard is up for search,
/// so every control on the page is directly manipulable.
///
/// Reached from Calendar Settings, like [CalendarCategoriesPage], not from the
/// drawer — which is why its [NavDestinationKind] does not reopen the drawer
/// on pop.
class CalendarAppearancePage extends StatefulWidget {
  const CalendarAppearancePage({super.key});

  @override
  State<CalendarAppearancePage> createState() => _CalendarAppearancePageState();
}

class _CalendarAppearancePageState extends State<CalendarAppearancePage> {
  // Persisted fold state is keyed on these, so they are frozen strings, not
  // titles and not positions — renaming or reordering a section must not
  // reopen a card the user folded shut. They share the calendar settings
  // page's stored set; the two pages' ids never collide, and each renders
  // only its own.
  static const String _sectionCell = 'appearance_cell';
  static const String _sectionMarkers = 'appearance_markers';
  static const String _sectionRail = 'appearance_rail';
  static const String _sectionWeek = 'appearance_week';
  static const String _sectionColor = 'appearance_color';
  static const String _sectionLabels = 'appearance_labels';

  SettingsService? _settings;
  bool _isLoading = true;
  Set<String> _collapsedSections = const {};
  int _foldEdits = 0;

  final TextEditingController _searchController = TextEditingController();
  SettingsQuery _query = SettingsQuery.empty;

  CalendarAppearance _appearance = const CalendarAppearance();
  bool _hapticFeedback = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    final appearance = await settings.getCalendarAppearance();
    final haptic = await settings.getHapticFeedback();
    final collapsedSections = await settings
        .getCalendarSettingsCollapsedSections();
    // Publishes the palette facade the accent row and the palette row both
    // read synchronously; without it a page opened before any picker would
    // count zero colours the user does have.
    await CalendarPaletteService.getInstance();

    if (!mounted) return;
    setState(() {
      _settings = settings;
      _collapsedSections = collapsedSections;
      _appearance = appearance;
      _hapticFeedback = haptic;
      _isLoading = false;
    });
  }

  /// Optimistic like every other row on this page: the fold is a view
  /// preference, so a failed write costs nothing worth blocking the tap for.
  /// The write edits the stored row, which the other calendar pages share,
  /// and the last tap's answer is adopted (`CalendarSettingsPage`'s toggle
  /// says why).
  Future<void> _toggleSection(String id) async {
    _onHapticFeedback();
    final next = {..._collapsedSections};
    final collapsed = !next.remove(id);
    if (collapsed) next.add(id);
    final edit = ++_foldEdits;
    setState(() => _collapsedSections = next);
    final stored = await _settings?.setCalendarSettingsSectionCollapsed(
      id,
      collapsed: collapsed,
    );
    if (stored != null && mounted && edit == _foldEdits) {
      setState(() => _collapsedSections = stored);
    }
  }

  void _onHapticFeedback() {
    if (_hapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  /// Localized weekday name for a [CalendarWeekStart] option, derived via
  /// `intl` from an anchor date (2024-01-01 is a Monday) — never an ARB
  /// weekday matrix.
  String _weekStartLabel(CalendarWeekStart start, String localeName) {
    final anchor = DateTime.utc(2024, 1, start.weekday);
    final name = DateFormat.EEEE(localeName).format(anchor);
    return toBeginningOfSentenceCase(name, localeName) ?? name;
  }

  Future<void> _pickWeekStart(
    BuildContext anchor,
    AppLocalizations l10n,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final next = await showFormMenu<CalendarWeekStart>(
      anchor,
      items: [
        for (final start in CalendarWeekStart.values)
          FormMenuItem(
            value: start,
            label: _weekStartLabel(start, l10n.localeName),
            identifier: SemanticsIds.appearanceWeekStartItem(start.name),
          ),
      ],
      selected: _appearance.weekStart,
      menuWidth: FormMetrics.menuWidth,
    );
    if (next == null || !mounted || next == _appearance.weekStart) return;
    _onHapticFeedback();
    setState(() => _appearance = _appearance.copyWith(weekStart: next));
    await _settings?.setCalendarWeekStart(next);
  }

  /// One handler for every dot in the accent row: a swatch, a colour just
  /// mixed on the wheel, and "follow the theme" all land here, because
  /// [ColorSwatchPicker] reports the *result* rather than which affordance
  /// produced it.
  Future<void> _onAccentChanged(int? value) async {
    _onHapticFeedback();
    setState(
      () => _appearance = value == null
          ? _appearance.copyWith(clearAccentColor: true)
          : _appearance.copyWith(accentColorValue: value),
    );
    await _settings?.setCalendarAccentColor(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.pageGround,
      appBar: SettingsAppBar(
        title: l10n.calendarAppearanceSection,
        identifier: SemanticsIds.settingsBarAppearance,
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // The whole point of this route: a fixed `Column` child, not
                  // a section `intro:` and not a sliver, so it survives every
                  // scroll position and the keyboard being up for search.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: CalendarAppearancePreview(appearance: _appearance),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: SettingsSearchField(
                      controller: _searchController,
                      hint: l10n.searchSettings,
                      onChanged: (value) =>
                          setState(() => _query = SettingsQuery.parse(value)),
                    ),
                  ),
                  Expanded(
                    child: SettingsSectionList(
                      query: _query,
                      sections: _buildSections(context, colorScheme, l10n),
                      collapsedSections: _collapsedSections,
                      onToggleSection: _toggleSection,
                      footer: [
                        Center(
                          child: TextButton.icon(
                            onPressed: _showResetConfirmation,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(l10n.resetToDefaults),
                            style: TextButton.styleFrom(
                              foregroundColor: colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<SettingsSectionData> _buildSections(
    BuildContext context,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    // The cell first, because it is the largest thing the preview draws and
    // the one every other section decorates; the labels section last, because
    // it is the only one that changes text rather than the grid.
    return [
      _buildDayCellSection(colorScheme, l10n),
      _buildMarkersSection(colorScheme, l10n),
      _buildRailSection(colorScheme, l10n),
      _buildWeekSection(colorScheme, l10n),
      _buildColorSection(colorScheme, l10n),
      _buildLabelsSection(colorScheme, l10n),
    ];
  }

  SettingsSectionData _buildDayCellSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final tintOffStyle = _appearance.eventTint
        ? null
        : TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.38));
    return SettingsSectionData(
      id: _sectionCell,
      icon: Icons.calendar_view_day_rounded,
      title: l10n.calendarAppearanceDayCellSection,
      entries: [
        SettingsEntry(
          title: l10n.calendarTodayStyleTitle,
          identifier: SemanticsIds.appearanceTodayStyle,
          builder: (context, title, description) => settingsChoiceRow(
            title: title,
            description: description,
            value: _appearance.todayStyle,
            labels: {
              CalendarTodayStyle.tonal: l10n.todayStyleTonal,
              CalendarTodayStyle.ring: l10n.todayStyleRing,
              CalendarTodayStyle.filled: l10n.todayStyleFilled,
            },
            onChanged: (value) async {
              _onHapticFeedback();
              setState(
                () => _appearance = _appearance.copyWith(todayStyle: value),
              );
              await _settings?.setCalendarTodayStyle(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.calendarHighlightWeekends,
          description: l10n.calendarHighlightWeekendsDesc,
          builder: (context, title, description) => SwitchListTile(
            value: _appearance.highlightWeekends,
            secondary: Icon(Icons.weekend_outlined, color: colorScheme.primary),
            title: title,
            subtitle: description,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(
                () => _appearance = _appearance.copyWith(
                  highlightWeekends: value,
                ),
              );
              await _settings?.setCalendarHighlightWeekends(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.calendarEventTintTitle,
          description: l10n.calendarEventTintDesc,
          // "Priority" never appears in the visible copy, but it is what the
          // tint encodes and what the user would search for.
          keywords: [l10n.eventPriority],
          builder: (context, title, description) => SwitchListTile(
            value: _appearance.eventTint,
            secondary: Icon(
              Icons.format_color_fill_rounded,
              color: colorScheme.primary,
            ),
            title: title,
            subtitle: description,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(
                () => _appearance = _appearance.copyWith(eventTint: value),
              );
              await _settings?.setCalendarEventTint(value);
            },
          ),
        ),
        // Only meaningful with the tint on — with it off there is no event
        // wash to style — and disabled rather than hidden then (S14), like
        // the tint conflict under it.
        SettingsEntry(
          title: l10n.calendarCellStyleTitle,
          description: l10n.calendarCellStyleDesc,
          // Neither word appears in the visible copy, but the setting exists
          // because the same priority alpha reads differently on the two
          // grounds — so both are what someone would search for.
          keywords: [l10n.eventPriority, l10n.themeSettings],
          titleStyle: tintOffStyle,
          descriptionStyle: tintOffStyle,
          builder: (context, title, description) {
            final cellStyles = {
              CalendarCellStyle.solid: l10n.calendarCellStyleSolid,
              CalendarCellStyle.fade: l10n.calendarCellStyleFade,
              CalendarCellStyle.outline: l10n.calendarCellStyleOutline,
            };
            final themeLabelStyle = Theme.of(
              context,
            ).textTheme.labelMedium?.merge(tintOffStyle);
            // One entry, two choices: the light and the dark ground are
            // searched and read as one setting, so the kit's choice row is
            // nested under the entry's own text, padded once.
            return Padding(
              padding: FormMetrics.settingsControlRowPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  ?description,
                  const SizedBox(height: FormMetrics.settingsControlGap),
                  settingsChoiceRow(
                    title: Text(
                      l10n.calendarCellStyleLight,
                      style: themeLabelStyle,
                    ),
                    description: null,
                    value: _appearance.cellStyleLight,
                    labels: cellStyles,
                    enabled: _appearance.eventTint,
                    padding: EdgeInsets.zero,
                    onChanged: (value) async {
                      _onHapticFeedback();
                      setState(
                        () => _appearance = _appearance.copyWith(
                          cellStyleLight: value,
                        ),
                      );
                      await _settings?.setCalendarCellStyleLight(value);
                    },
                  ),
                  const SizedBox(height: FormMetrics.settingsControlGap),
                  settingsChoiceRow(
                    title: Text(
                      l10n.calendarCellStyleDark,
                      style: themeLabelStyle,
                    ),
                    description: null,
                    value: _appearance.cellStyleDark,
                    labels: cellStyles,
                    enabled: _appearance.eventTint,
                    padding: EdgeInsets.zero,
                    onChanged: (value) async {
                      _onHapticFeedback();
                      setState(
                        () => _appearance = _appearance.copyWith(
                          cellStyleDark: value,
                        ),
                      );
                      await _settings?.setCalendarCellStyleDark(value);
                    },
                  ),
                ],
              ),
            );
          },
        ),
        // Only meaningful with the tint on — with it off there is exactly one
        // wash source, so nothing to resolve — and disabled rather than
        // hidden then (S14), so the switch above never moves the page.
        SettingsEntry(
          title: l10n.calendarTintConflictTitle,
          description: l10n.calendarTintConflictDesc,
          keywords: [l10n.fastingSectionTitle],
          identifier: SemanticsIds.appearanceTintConflict,
          titleStyle: tintOffStyle,
          descriptionStyle: tintOffStyle,
          builder: (context, title, description) => settingsChoiceRow(
            title: title,
            description: description,
            value: _appearance.tintConflict,
            labels: {
              CalendarTintConflict.eventWins: l10n.calendarTintConflictEvent,
              CalendarTintConflict.fastingWins:
                  l10n.calendarTintConflictFasting,
              CalendarTintConflict.both: l10n.calendarTintConflictBoth,
            },
            enabled: _appearance.eventTint,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(
                () => _appearance = _appearance.copyWith(tintConflict: value),
              );
              await _settings?.setCalendarTintConflict(value);
            },
          ),
        ),
      ],
    );
  }

  SettingsSectionData _buildMarkersSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      id: _sectionMarkers,
      icon: Icons.view_agenda_rounded,
      title: l10n.calendarAppearanceMarkersSection,
      entries: [
        SettingsEntry(
          title: l10n.calendarMarkerStyleTitle,
          builder: (context, title, description) => settingsChoiceRow(
            title: title,
            description: description,
            value: _appearance.markerStyle,
            labels: {
              CalendarMarkerStyle.bars: l10n.markerStyleBars,
              CalendarMarkerStyle.dots: l10n.markerStyleDots,
            },
            icons: const {
              CalendarMarkerStyle.bars: Icons.view_agenda_outlined,
              CalendarMarkerStyle.dots: Icons.more_horiz_rounded,
            },
            onChanged: (value) async {
              _onHapticFeedback();
              setState(
                () => _appearance = _appearance.copyWith(markerStyle: value),
              );
              await _settings?.setCalendarMarkerStyle(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.calendarMaxDayBars,
          description: l10n.calendarMaxDayBarsDesc(_appearance.maxDayBars),
          builder: (context, title, description) => SliderSettingRow(
            title: title,
            description: description,
            value: _appearance.maxDayBars,
            min: SettingsKeys.minCalendarMaxDayBars,
            max: SettingsKeys.maxCalendarMaxDayBars,
            divisions:
                SettingsKeys.maxCalendarMaxDayBars -
                SettingsKeys.minCalendarMaxDayBars,
            captionStyle: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
            draftCaption: (draft) => l10n.calendarMaxDayBarsDesc(draft),
            onCommit: (value) async {
              _onHapticFeedback();
              setState(
                () => _appearance = _appearance.copyWith(maxDayBars: value),
              );
              await _settings?.setCalendarMaxDayBars(value);
            },
          ),
        ),
        // A drawing rule for the markers above and the rail below, not an
        // event property: it decides whether a missed one is dimmed or gone,
        // and it is read together with the two rows it sits between.
        SettingsEntry(
          title: l10n.calendarMissedDisplayTitle,
          description: l10n.calendarMissedDisplayDesc,
          // The visible title says nothing about presence, so the words the
          // user would actually search for are declared here.
          keywords: [l10n.eventTrackPresence, l10n.eventPresenceMissed],
          builder: (context, title, description) => settingsChoiceRow(
            title: title,
            description: description,
            value: _appearance.missedDisplay,
            labels: {
              CalendarMissedDisplay.faded: l10n.calendarMissedDisplayFaded,
              CalendarMissedDisplay.hidden: l10n.calendarMissedDisplayHidden,
            },
            icons: const {
              CalendarMissedDisplay.faded: Icons.opacity_rounded,
              CalendarMissedDisplay.hidden: Icons.visibility_off_outlined,
            },
            identifiers: const {
              CalendarMissedDisplay.faded: SemanticsIds.missedDisplayFaded,
              CalendarMissedDisplay.hidden: SemanticsIds.missedDisplayHidden,
            },
            onChanged: (value) async {
              _onHapticFeedback();
              setState(
                () => _appearance = _appearance.copyWith(missedDisplay: value),
              );
              await _settings?.setCalendarMissedDisplay(value);
            },
          ),
        ),
      ],
    );
  }

  SettingsSectionData _buildRailSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      id: _sectionRail,
      icon: Icons.vertical_split_rounded,
      title: l10n.calendarAppearanceRailSection,
      entries: [
        SettingsEntry(
          title: l10n.calendarDayRailStyleTitle,
          description: l10n.calendarDayRailStyleDesc,
          // Neither word appears in the copy, but the rail is the answer to
          // "several tracked events on one day" and that is what someone
          // looking for it would type.
          keywords: [l10n.eventTrackPresence, l10n.eventPresenceMissed],
          builder: (context, title, description) => settingsChoiceRow(
            title: title,
            description: description,
            value: _appearance.dayRailStyle,
            labels: {
              DayRailStyle.none: l10n.dayRailStyleNone,
              DayRailStyle.line: l10n.dayRailStyleLine,
              DayRailStyle.dot: l10n.dayRailStyleDot,
            },
            onChanged: (value) async {
              _onHapticFeedback();
              setState(
                () => _appearance = _appearance.copyWith(dayRailStyle: value),
              );
              await _settings?.setCalendarDayRailStyle(value);
            },
          ),
        ),
        // Only reachable with the rail on, like the tint-conflict row: there
        // is nothing to cap while nothing is drawn.
        if (_appearance.dayRailStyle != DayRailStyle.none)
          SettingsEntry(
            title: l10n.calendarMaxDayRailMarks,
            description: l10n.calendarMaxDayRailMarksDesc(
              _appearance.maxDayRailMarks,
            ),
            builder: (context, title, description) => SliderSettingRow(
              title: title,
              description: description,
              value: _appearance.maxDayRailMarks,
              min: SettingsKeys.minCalendarMaxDayRailMarks,
              max: SettingsKeys.maxCalendarMaxDayRailMarks,
              divisions:
                  SettingsKeys.maxCalendarMaxDayRailMarks -
                  SettingsKeys.minCalendarMaxDayRailMarks,
              captionStyle: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
              draftCaption: (draft) => l10n.calendarMaxDayRailMarksDesc(draft),
              onCommit: (value) async {
                _onHapticFeedback();
                setState(
                  () => _appearance = _appearance.copyWith(
                    maxDayRailMarks: value,
                  ),
                );
                await _settings?.setCalendarMaxDayRailMarks(value);
              },
            ),
          ),
        // Revealed only where the band can actually exist, which takes all
        // three: `line` (the one style that shares its lane with the tint
        // stripe — `dot` keeps its own and leaves the stripe to the cell),
        // `eventTint` (with it off, fasting wins the wash outright and
        // `CellTintResolver` has no runner-up to hand over) and `both` (the
        // only conflict setting that paints a runner-up at all). In any other
        // configuration this control would move a band nothing draws, and a
        // switch that visibly does nothing is worse than one you have to turn
        // something else on to reach. The pinned preview above is showing the
        // band whenever this row is visible, for exactly the same reason.
        if (_appearance.dayRailStyle == DayRailStyle.line &&
            _appearance.eventTint &&
            _appearance.tintConflict == CalendarTintConflict.both)
          SettingsEntry(
            title: l10n.calendarDayRailBasePositionTitle,
            description: l10n.calendarDayRailBasePositionDesc,
            keywords: [l10n.calendarTintConflictFasting],
            builder: (context, title, description) => settingsChoiceRow(
              title: title,
              description: description,
              value: _appearance.dayRailBasePosition,
              labels: {
                DayRailBasePosition.top: l10n.dayRailBasePositionTop,
                DayRailBasePosition.bottom: l10n.dayRailBasePositionBottom,
              },
              onChanged: (value) async {
                _onHapticFeedback();
                setState(
                  () => _appearance = _appearance.copyWith(
                    dayRailBasePosition: value,
                  ),
                );
                await _settings?.setCalendarDayRailBasePosition(value);
              },
            ),
          ),
      ],
    );
  }

  SettingsSectionData _buildWeekSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      id: _sectionWeek,
      icon: Icons.view_week_rounded,
      title: l10n.calendarAppearanceWeekSection,
      entries: [
        // A value row with a menu, not a dropdown in the trailing (S5): the
        // tile measures the day's name, so at a large scale it goes under
        // the title instead of crushing it.
        SettingsEntry(
          title: l10n.calendarWeekStartTitle,
          identifier: SemanticsIds.appearanceWeekStart,
          builder: (context, title, description) {
            final value = _weekStartLabel(
              _appearance.weekStart,
              l10n.localeName,
            );
            // A `Builder` so the menu hangs from the row's own box.
            return Builder(
              builder: (rowContext) => SettingsYieldingTile(
                leading: Icon(
                  Icons.view_week_outlined,
                  color: colorScheme.primary,
                ),
                title: title,
                value: value,
                trailing: (maxWidth) => ValueChangeHighlight(
                  value: _appearance.weekStart,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Text(
                      value,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
                onTap: () => _pickWeekStart(rowContext, l10n),
              ),
            );
          },
        ),
        SettingsEntry(
          title: l10n.calendarShowWeekNumbers,
          description: l10n.calendarShowWeekNumbersDesc,
          builder: (context, title, description) => SwitchListTile(
            value: _appearance.showWeekNumbers,
            secondary: Icon(Icons.tag_rounded, color: colorScheme.primary),
            title: title,
            subtitle: description,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(
                () =>
                    _appearance = _appearance.copyWith(showWeekNumbers: value),
              );
              await _settings?.setCalendarShowWeekNumbers(value);
            },
          ),
        ),
      ],
    );
  }

  SettingsSectionData _buildColorSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      id: _sectionColor,
      icon: Icons.palette_rounded,
      title: l10n.calendarAppearanceColorSection,
      entries: [
        SettingsEntry(
          title: l10n.calendarAccentColor,
          description: l10n.calendarAccentColorDesc,
          identifier: SemanticsIds.appearanceAccentColor,
          builder: (context, title, description) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 4),
                ?description,
                const SizedBox(height: 12),
                ColorSwatchPicker(
                  value: _appearance.accentColorValue,
                  onChanged: _onAccentChanged,
                  spacing: 10,
                  defaultOption: ColorSwatchDefault(
                    color: colorScheme.primary,
                    icon: Icons.format_color_reset_rounded,
                    tooltip: l10n.calendarAccentThemeDefault,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Sits under the accent row because that is where a user first meets
        // the palette; the sheet it opens is the same one every picker in the
        // app reaches through its palette dot.
        SettingsEntry(
          title: l10n.colorPaletteTitle,
          // The subtitle is the count, so the count is what `description`
          // carries: `SettingsEntry` pre-renders that text with the search
          // query highlighted, and rendering a different string in the
          // builder would leave a matched row with nothing highlighted.
          description: l10n.colorPaletteCount(CalendarPalette.custom.length),
          keywords: [l10n.colorPaletteDesc, l10n.addColor, l10n.manageColors],
          builder: (context, title, description) => ListTile(
            leading: Icon(Icons.palette_outlined, color: colorScheme.primary),
            title: title,
            subtitle: description,
            trailing: const Icon(Icons.chevron_right_rounded),
            // The row reports a count, so it has to be rebuilt when the
            // sheet has finished changing one — the entry text is resolved
            // once per page build, not per palette revision.
            onTap: () async {
              await ColorPaletteSheet.show(context);
              if (mounted) setState(() {});
            },
          ),
        ),
      ],
    );
  }

  SettingsSectionData _buildLabelsSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      id: _sectionLabels,
      icon: Icons.subtitles_outlined,
      title: l10n.calendarAppearanceLabelsSection,
      entries: [
        SettingsEntry(
          title: l10n.calendarShowRecurrenceLabels,
          description: l10n.calendarShowRecurrenceLabelsDesc,
          // The editor's word for it: the German row says "Rhythmus".
          keywords: [l10n.eventRepeat],
          builder: (context, title, description) => SwitchListTile(
            value: _appearance.showRecurrenceLabels,
            secondary: Icon(Icons.repeat_rounded, color: colorScheme.primary),
            title: title,
            subtitle: description,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(
                () => _appearance = _appearance.copyWith(
                  showRecurrenceLabels: value,
                ),
              );
              await _settings?.setCalendarShowRecurrenceLabels(value);
            },
          ),
        ),
      ],
    );
  }

  void _showResetConfirmation() async {
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.resetToDefaults,
      content: l10n.resetToDefaultsConfirm,
      confirmText: l10n.reset,
      icon: Icons.refresh_rounded,
    );
    if (!confirmed) return;
    await _resetToDefaults();
  }

  /// Resets **only** the appearance keys whose rows are on this page.
  ///
  /// `calendarShowFilterChips` is part of the same [CalendarAppearance] bundle
  /// but its row lives on the calendar settings page's Filtering section, so
  /// it is deliberately left alone: resetting a key whose control the user
  /// cannot see from here is worse than not offering it. The page above keeps
  /// its own reset, which still covers everything.
  Future<void> _resetToDefaults() async {
    const defaults = CalendarAppearance(
      maxDayBars: SettingsKeys.defaultCalendarMaxDayBars,
      maxDayRailMarks: SettingsKeys.defaultCalendarMaxDayRailMarks,
    );
    await _settings?.setCalendarTodayStyle(defaults.todayStyle);
    await _settings?.setCalendarMarkerStyle(defaults.markerStyle);
    await _settings?.setCalendarWeekStart(defaults.weekStart);
    await _settings?.setCalendarAccentColor(defaults.accentColorValue);
    await _settings?.setCalendarHighlightWeekends(defaults.highlightWeekends);
    await _settings?.setCalendarShowWeekNumbers(defaults.showWeekNumbers);
    await _settings?.setCalendarMaxDayBars(defaults.maxDayBars);
    await _settings?.setCalendarShowRecurrenceLabels(
      defaults.showRecurrenceLabels,
    );
    await _settings?.setCalendarMissedDisplay(defaults.missedDisplay);
    await _settings?.setCalendarEventTint(defaults.eventTint);
    await _settings?.setCalendarTintConflict(defaults.tintConflict);
    await _settings?.setCalendarCellStyleLight(defaults.cellStyleLight);
    await _settings?.setCalendarCellStyleDark(defaults.cellStyleDark);
    // Through `SettingsKeys`, like `maxDayBars` above: the model's field
    // initializers and the settings defaults are two sources for one value,
    // and reset is where they would silently drift apart.
    await _settings?.setCalendarDayRailStyle(
      DayRailStyle.fromName(SettingsKeys.defaultCalendarDayRailStyle),
    );
    await _settings?.setCalendarMaxDayRailMarks(defaults.maxDayRailMarks);
    await _settings?.setCalendarDayRailBasePosition(
      DayRailBasePosition.fromName(
        SettingsKeys.defaultCalendarDayRailBasePosition,
      ),
    );

    if (!mounted) return;
    setState(() {
      // The one field of the bundle this page does not own keeps its stored
      // value, so the preview and the page above stay in agreement.
      _appearance = defaults.copyWith(
        showFilterChips: _appearance.showFilterChips,
      );
    });

    if (!mounted) return;
    CustomSnackbar.showSuccess(
      context,
      AppLocalizations.of(context)!.settingsReset,
    );
  }
}
