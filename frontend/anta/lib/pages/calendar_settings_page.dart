import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../constants/calendar_colors.dart';
import '../constants/fasting_calendar.dart';
import '../constants/public_holidays.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../constants/calendar_icons.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/day_bar.dart';
import '../models/day_cell_tint.dart';
import '../models/fasting_appearance.dart';
import '../models/fasting_schedule.dart';
import '../widgets/fasting_schedule_sheet.dart';
import '../widgets/fasting_style_sheet.dart';
import '../services/app_navigator.dart';
import '../services/calendar_event_service.dart';
import '../services/public_holiday_service.dart';
import '../services/recurrence_formatter.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/calendar_day_bars.dart';
import '../widgets/calendar_day_cell.dart';
import '../widgets/color_wheel_picker.dart';
import '../widgets/removed_holidays_sheet.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/slider_setting_row.dart';
import '../widgets/unified_app_bars.dart';

/// Calendar settings page grouping every calendar-specific option
/// (week start, holiday set, appearance, day-bar density, …) in one place.
class CalendarSettingsPage extends StatefulWidget {
  const CalendarSettingsPage({super.key});

  @override
  State<CalendarSettingsPage> createState() => _CalendarSettingsPageState();
}

class _CalendarSettingsPageState extends State<CalendarSettingsPage> {
  SettingsService? _settings;
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  SettingsQuery _query = SettingsQuery.empty;

  CalendarAppearance _appearance = const CalendarAppearance();
  PublicHolidayService? _holidayService;
  HolidayProfile _holidayProfile = HolidayProfile.generic;
  bool _hapticFeedback = true;

  CalendarEventService? _eventService;
  int _eventCount = 0;
  int _descriptionLimit = SettingsKeys.defaultEventDescriptionLimit;

  Set<FastingTradition> _fastingTraditions = const {};
  FastingAppearance _fastingAppearance = const FastingAppearance();
  bool _fastingGreatFasts = true;
  FastingSchedule _fastingSchedule = const FastingSchedule();

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
    final holidayService = await PublicHolidayService.getInstance();
    final eventService = await CalendarEventService.getInstance();
    final fastingTraditions = await settings.getFastingTraditions();
    final fastingAppearance = await settings.getFastingAppearance();
    final fastingGreatFasts = await settings.getFastingOrthodoxGreatFasts();
    final fastingSchedule = await settings.getFastingSchedule();
    final descriptionLimit = await settings.getEventDescriptionLimit();

    if (!mounted) return;
    setState(() {
      _settings = settings;
      _appearance = appearance;
      _hapticFeedback = haptic;
      _holidayService = holidayService;
      _holidayProfile = holidayService.profile;
      _eventService = eventService;
      _eventCount = eventService.events.length;
      _descriptionLimit = descriptionLimit;
      _fastingTraditions = fastingTraditions;
      _fastingAppearance = fastingAppearance;
      _fastingGreatFasts = fastingGreatFasts;
      _fastingSchedule = fastingSchedule;
      _isLoading = false;
    });
  }

  Future<void> _toggleFastingTradition(
    FastingTradition tradition,
    bool enabled,
  ) async {
    _onHapticFeedback();
    setState(() {
      final next = {..._fastingTraditions};
      enabled ? next.add(tradition) : next.remove(tradition);
      _fastingTraditions = next;
    });
    await _settings?.setFastingTraditions(_fastingTraditions);
  }

  FastingTraditionStyle _fastingStyleOf(FastingTradition tradition) =>
      _fastingAppearance.styleFor(tradition);

  /// "Subtle tint · After holidays" — the two choices that actually change
  /// where the user will see the fast.
  String _fastingStyleSummary(
    FastingTradition tradition,
    AppLocalizations l10n,
  ) {
    final style = _fastingStyleOf(tradition);
    return '${FastingCalendar.styleNameOf(style.style, l10n)} · '
        '${FastingCalendar.placementNameOf(style.placement, l10n)}';
  }

  /// Opens the per-tradition appearance sheet. Edits arrive live through
  /// `onChanged`, so each tap persists and repaints the row behind the
  /// sheet — closing is never a "discard".
  Future<void> _editFastingStyle(FastingTradition tradition) async {
    await FastingStyleSheet.show(
      context,
      tradition: tradition,
      initialStyle: _fastingStyleOf(tradition),
      onChanged: (style) async {
        setState(() {
          _fastingAppearance = _fastingAppearance.withStyle(tradition, style);
        });
        await _settings?.setFastingAppearance(_fastingAppearance);
      },
    );
  }

  /// Opens the personal schedule sheet. Like the appearance sheet, edits
  /// arrive live through `onChanged`, so each tap persists and the summary
  /// row behind the sheet repaints — closing is never a "discard".
  Future<void> _editFastingSchedule() async {
    await FastingScheduleSheet.show(
      context,
      initialSchedule: _fastingSchedule,
      appearance: _appearance,
      onChanged: (schedule) async {
        setState(() => _fastingSchedule = schedule);
        await _settings?.setFastingSchedule(schedule);
      },
    );
  }

  /// "Wed, Fri · All year · 3 exceptions" — the three facts that decide which
  /// days get marked, in the order the engine applies them.
  String _fastingScheduleSummary(AppLocalizations l10n) {
    final parts = <String>[
      _fastingSchedule.weekdays.isEmpty
          ? l10n.fastingScheduleNoDays
          : RecurrenceFormatter.formatWeekdays(
              _fastingSchedule.weekdays,
              l10n.localeName,
            ),
      if (_fastingSchedule.keepsEveryMonth)
        l10n.fastingScheduleAllYear
      else if (_fastingSchedule.months.isEmpty)
        l10n.fastingScheduleNoMonths
      else
        l10n.fastingMonthsCount(_fastingSchedule.months.length),
      if (_fastingSchedule.exceptionCount > 0)
        l10n.fastingExceptionsCount(_fastingSchedule.exceptionCount),
    ];
    return parts.join(' · ');
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

  Future<void> _pickCustomAccent() async {
    final picked = await ColorWheelDialog.show(
      context,
      initialColor: _appearance.accentColorValue,
    );
    if (picked == null || !mounted) return;
    _onHapticFeedback();
    setState(
      () => _appearance = _appearance.copyWith(accentColorValue: picked),
    );
    await _settings?.setCalendarAccentColor(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: SettingsAppBar(
        title: l10n.calendarSettings,
        showMenuButton: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
                    sections: _buildSections(context, theme, colorScheme, l10n),
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
    );
  }

  List<SettingsSectionData> _buildSections(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return [
      _buildCalendarSection(colorScheme, l10n),
      _buildAppearanceSection(colorScheme, l10n),
      _buildCategoriesSection(colorScheme, l10n),
      _buildFastingSection(theme, colorScheme, l10n),
      _buildEventsSection(colorScheme, l10n),
    ];
  }

  SettingsSectionData _buildCalendarSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      icon: Icons.calendar_month_rounded,
      title: l10n.calendarSection,
      entries: [
        SettingsEntry(
          title: l10n.calendarWeekStartTitle,
          builder: (context, title, description) => ListTile(
            leading: Icon(Icons.view_week_outlined, color: colorScheme.primary),
            title: title,
            trailing: DropdownButton<CalendarWeekStart>(
              value: _appearance.weekStart,
              underline: const SizedBox.shrink(),
              onChanged: (next) async {
                if (next == null || next == _appearance.weekStart) {
                  return;
                }
                _onHapticFeedback();
                setState(
                  () => _appearance = _appearance.copyWith(weekStart: next),
                );
                await _settings?.setCalendarWeekStart(next);
              },
              items: [
                for (final start in CalendarWeekStart.values)
                  DropdownMenuItem(
                    value: start,
                    child: Text(_weekStartLabel(start, l10n.localeName)),
                  ),
              ],
            ),
          ),
        ),
        SettingsEntry(
          title: l10n.holidayProfileTitle,
          description: PublicHolidays.profileNameOf(_holidayProfile, l10n),
          builder: (context, title, description) => ListTile(
            leading: Icon(Icons.public_rounded, color: colorScheme.primary),
            title: title,
            subtitle: description,
            trailing: DropdownButton<HolidayProfile>(
              value: _holidayProfile,
              underline: const SizedBox.shrink(),
              onChanged: (next) async {
                if (next == null || next == _holidayProfile) {
                  return;
                }
                _onHapticFeedback();
                // Optimistic UI update — the service mutation is
                // transactional so a failure leaves the cache in a
                // consistent state and we can resync from it.
                setState(() => _holidayProfile = next);
                try {
                  await _holidayService?.setProfile(next);
                } catch (e) {
                  if (!context.mounted) return;
                  setState(
                    () => _holidayProfile = _holidayService?.profile ?? next,
                  );
                  CustomSnackbar.showError(
                    context,
                    'Failed to switch holiday profile: $e',
                  );
                }
              },
              items: [
                for (final profile in HolidayProfile.values)
                  DropdownMenuItem(
                    value: profile,
                    child: Text(PublicHolidays.profileNameOf(profile, l10n)),
                  ),
              ],
            ),
          ),
        ),
        SettingsEntry(
          title: l10n.removedHolidays,
          builder: (context, title, description) => ListTile(
            leading: Icon(Icons.restore_rounded, color: colorScheme.primary),
            title: title,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _holidayService == null
                ? null
                : () => RemovedHolidaysSheet.show(context, _holidayService!),
          ),
        ),
      ],
    );
  }

  SettingsSectionData _buildAppearanceSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      icon: Icons.palette_rounded,
      title: l10n.calendarAppearanceSection,
      intro: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: _AppearancePreview(appearance: _appearance),
      ),
      entries: [
        SettingsEntry(
          title: l10n.calendarTodayStyleTitle,
          builder: (context, title, description) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 8),
                SegmentedButton<CalendarTodayStyle>(
                  segments: [
                    ButtonSegment(
                      value: CalendarTodayStyle.tonal,
                      label: Text(l10n.todayStyleTonal),
                    ),
                    ButtonSegment(
                      value: CalendarTodayStyle.ring,
                      label: Text(l10n.todayStyleRing),
                    ),
                    ButtonSegment(
                      value: CalendarTodayStyle.filled,
                      label: Text(l10n.todayStyleFilled),
                    ),
                  ],
                  selected: {_appearance.todayStyle},
                  showSelectedIcon: false,
                  onSelectionChanged: (sel) async {
                    _onHapticFeedback();
                    setState(
                      () => _appearance = _appearance.copyWith(
                        todayStyle: sel.first,
                      ),
                    );
                    await _settings?.setCalendarTodayStyle(sel.first);
                  },
                ),
              ],
            ),
          ),
        ),
        SettingsEntry(
          title: l10n.calendarAccentColor,
          description: l10n.calendarAccentColorDesc,
          builder: (context, title, description) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 4),
                ?description,
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _AccentColorDot(
                      color: colorScheme.primary,
                      icon: Icons.format_color_reset_rounded,
                      tooltip: l10n.calendarAccentThemeDefault,
                      selected: _appearance.accentColorValue == null,
                      onTap: () async {
                        _onHapticFeedback();
                        setState(
                          () => _appearance = _appearance.copyWith(
                            clearAccentColor: true,
                          ),
                        );
                        await _settings?.setCalendarAccentColor(null);
                      },
                    ),
                    for (final swatch in CalendarColors.swatchPalette)
                      _AccentColorDot(
                        color: Color(swatch),
                        selected: _appearance.accentColorValue == swatch,
                        onTap: () async {
                          _onHapticFeedback();
                          setState(
                            () => _appearance = _appearance.copyWith(
                              accentColorValue: swatch,
                            ),
                          );
                          await _settings?.setCalendarAccentColor(swatch);
                        },
                      ),
                    if (_appearance.accentColorValue != null &&
                        !CalendarColors.swatchPalette.contains(
                          _appearance.accentColorValue,
                        ))
                      _AccentColorDot(
                        color: Color(_appearance.accentColorValue!),
                        selected: true,
                        onTap: _pickCustomAccent,
                      ),
                    _AccentColorDot(
                      color: colorScheme.surfaceContainerHighest,
                      icon: Icons.colorize_rounded,
                      tooltip: l10n.eventColorCustomTitle,
                      selected: false,
                      onTap: _pickCustomAccent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SettingsEntry(
          title: l10n.calendarMarkerStyleTitle,
          builder: (context, title, description) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 8),
                SegmentedButton<CalendarMarkerStyle>(
                  segments: [
                    ButtonSegment(
                      value: CalendarMarkerStyle.bars,
                      icon: const Icon(Icons.view_agenda_outlined),
                      label: Text(l10n.markerStyleBars),
                    ),
                    ButtonSegment(
                      value: CalendarMarkerStyle.dots,
                      icon: const Icon(Icons.more_horiz_rounded),
                      label: Text(l10n.markerStyleDots),
                    ),
                  ],
                  selected: {_appearance.markerStyle},
                  showSelectedIcon: false,
                  onSelectionChanged: (sel) async {
                    _onHapticFeedback();
                    setState(
                      () => _appearance = _appearance.copyWith(
                        markerStyle: sel.first,
                      ),
                    );
                    await _settings?.setCalendarMarkerStyle(sel.first);
                  },
                ),
              ],
            ),
          ),
        ),
        SettingsEntry(
          title: l10n.calendarMaxDayBars,
          description: l10n.calendarMaxDayBarsDesc(_appearance.maxDayBars),
          builder: (context, title, description) => SliderSettingRow(
            title: title,
            description: description,
            value: _appearance.maxDayBars,
            min: 1,
            max: 6,
            divisions: 5,
            captionStyle: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
            draftCaption: (draft) => l10n.calendarMaxDayBarsDesc(draft),
            onCommit: (value) async {
              _onHapticFeedback();
              setState(
                () =>
                    _appearance = _appearance.copyWith(maxDayBars: value),
              );
              await _settings?.setCalendarMaxDayBars(value);
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
        // Only reachable with the tint on: with it off there is exactly one
        // wash source, so there is nothing to resolve.
        if (_appearance.eventTint)
          SettingsEntry(
            title: l10n.calendarTintConflictTitle,
            description: l10n.calendarTintConflictDesc,
            keywords: [l10n.fastingSectionTitle],
            builder: (context, title, description) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: 4),
                  ?description,
                  const SizedBox(height: 8),
                  SegmentedButton<CalendarTintConflict>(
                    segments: [
                      ButtonSegment(
                        value: CalendarTintConflict.eventWins,
                        label: Text(l10n.calendarTintConflictEvent),
                      ),
                      ButtonSegment(
                        value: CalendarTintConflict.fastingWins,
                        label: Text(l10n.calendarTintConflictFasting),
                      ),
                      ButtonSegment(
                        value: CalendarTintConflict.both,
                        label: Text(l10n.calendarTintConflictBoth),
                      ),
                    ],
                    selected: {_appearance.tintConflict},
                    showSelectedIcon: false,
                    onSelectionChanged: (sel) async {
                      _onHapticFeedback();
                      setState(
                        () => _appearance = _appearance.copyWith(
                          tintConflict: sel.first,
                        ),
                      );
                      await _settings?.setCalendarTintConflict(sel.first);
                    },
                  ),
                ],
              ),
            ),
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
        SettingsEntry(
          title: l10n.calendarShowRecurrenceLabels,
          description: l10n.calendarShowRecurrenceLabelsDesc,
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

  SettingsSectionData _buildCategoriesSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      icon: Icons.category_rounded,
      title: l10n.calendarCategories,
      entries: [
        SettingsEntry(
          title: l10n.calendarCategories,
          description: l10n.calendarCategoriesDesc,
          builder: (context, title, description) => ListTile(
            leading: Icon(Icons.palette_outlined, color: colorScheme.primary),
            title: title,
            subtitle: description,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => AppNavigator.toCalendarCategories(context),
          ),
        ),
        SettingsEntry(
          title: l10n.eventTemplates,
          description: l10n.eventTemplatesDesc,
          // The page is reached from here, but the feature is used by
          // long-pressing a day — declare that word so settings search finds
          // it either way.
          keywords: [l10n.addFromTemplate],
          builder: (context, title, description) => ListTile(
            leading: Icon(
              Icons.bookmark_border_rounded,
              color: colorScheme.primary,
            ),
            title: title,
            subtitle: description,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => AppNavigator.toEventTemplates(context),
          ),
        ),
      ],
    );
  }

  SettingsSectionData _buildFastingSection(
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final entries = <SettingsEntry>[];

    for (final tradition in FastingTradition.values) {
      final traditionName = FastingCalendar.traditionNameOf(tradition, l10n);
      entries.add(
        SettingsEntry(
          title: traditionName,
          builder: (context, title, description) => SwitchListTile(
            value: _fastingTraditions.contains(tradition),
            secondary: Icon(
              _fastingStyleOf(tradition).iconKey == null
                  ? FastingCalendar.defaultIconOf(tradition)
                  : (CalendarIcons.forKey(_fastingStyleOf(tradition).iconKey) ??
                        FastingCalendar.defaultIconOf(tradition)),
              color: _fastingTraditions.contains(tradition)
                  ? _fastingStyleOf(tradition).colorOr(CalendarColors.fasting)
                  : colorScheme.onSurfaceVariant,
            ),
            title: title,
            onChanged: (value) => _toggleFastingTradition(tradition, value),
          ),
        ),
      );
      // The appearance row only exists for enabled traditions — configuring
      // the look of something that draws nothing is noise.
      if (_fastingTraditions.contains(tradition)) {
        entries.add(
          SettingsEntry(
            title: l10n.fastingAppearanceTitle,
            description: _fastingStyleSummary(tradition, l10n),
            // Searchable by the tradition it belongs to, since the visible
            // title is the same word for every one of them.
            keywords: [traditionName],
            builder: (context, title, description) => Padding(
              padding: const EdgeInsets.only(left: 32),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.tune_rounded, color: colorScheme.primary),
                title: title,
                subtitle: description,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editFastingStyle(tradition),
              ),
            ),
          ),
        );
      }
    }

    if (_fastingTraditions.contains(FastingTradition.orthodox)) {
      entries.add(
        SettingsEntry(
          title: l10n.fastingOrthodoxGreatFasts,
          description: l10n.fastingOrthodoxGreatFastsDesc,
          builder: (context, title, description) => SwitchListTile(
            value: _fastingGreatFasts,
            secondary: Icon(
              Icons.date_range_rounded,
              color: colorScheme.primary,
            ),
            title: title,
            subtitle: description,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(() => _fastingGreatFasts = value);
              await _settings?.setFastingOrthodoxGreatFasts(value);
            },
          ),
        ),
      );
    }

    // Gated on *any* tradition, not just Orthodox: the schedule subtracts
    // from every tradition's weekly rule, so hiding it behind Orthodox would
    // leave a Catholic-only install unable to reach the Friday it controls.
    if (_fastingTraditions.isNotEmpty) {
      entries.add(
        SettingsEntry(
          title: l10n.fastingScheduleTitle,
          description: _fastingScheduleSummary(l10n),
          // The weekday, month and exception labels live inside the sheet
          // now, so settings search needs them declared here to stay findable.
          keywords: [
            l10n.fastingWeekdayDaysTitle,
            l10n.fastingMonthsTitle,
            l10n.fastingExceptionsSkipTitle,
          ],
          builder: (context, title, description) => ListTile(
            leading: Icon(
              Icons.event_repeat_rounded,
              color: colorScheme.primary,
            ),
            title: title,
            subtitle: description,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _editFastingSchedule,
          ),
        ),
      );
    }

    return SettingsSectionData(
      icon: Icons.restaurant_menu_rounded,
      title: l10n.fastingSectionTitle,
      intro: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          l10n.fastingSectionDesc,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      entries: entries,
    );
  }

  SettingsSectionData _buildEventsSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      icon: Icons.event_note_rounded,
      title: l10n.calendarEventsSection,
      entries: [
        SettingsEntry(
          title: l10n.calendarMissedDisplayTitle,
          description: l10n.calendarMissedDisplayDesc,
          // The visible title says nothing about presence, so the words the
          // user would actually search for are declared here.
          keywords: [l10n.eventTrackPresence, l10n.eventPresenceMissed],
          builder: (context, title, description) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 4),
                ?description,
                const SizedBox(height: 8),
                SegmentedButton<CalendarMissedDisplay>(
                  segments: [
                    ButtonSegment(
                      value: CalendarMissedDisplay.faded,
                      icon: const Icon(Icons.opacity_rounded),
                      label: Text(l10n.calendarMissedDisplayFaded),
                    ),
                    ButtonSegment(
                      value: CalendarMissedDisplay.hidden,
                      icon: const Icon(Icons.visibility_off_outlined),
                      label: Text(l10n.calendarMissedDisplayHidden),
                    ),
                  ],
                  selected: {_appearance.missedDisplay},
                  showSelectedIcon: false,
                  onSelectionChanged: (sel) async {
                    _onHapticFeedback();
                    setState(
                      () => _appearance = _appearance.copyWith(
                        missedDisplay: sel.first,
                      ),
                    );
                    await _settings?.setCalendarMissedDisplay(sel.first);
                  },
                ),
              ],
            ),
          ),
        ),
        SettingsEntry(
          title: l10n.eventDescriptionLimit,
          description: l10n.eventDescriptionLimitDesc(_descriptionLimit),
          builder: (context, title, description) => SliderSettingRow(
            title: title,
            description: description,
            value: _descriptionLimit,
            min: SettingsKeys.minEventDescriptionLimit,
            max: SettingsKeys.maxEventDescriptionLimit,
            divisions:
                (SettingsKeys.maxEventDescriptionLimit -
                    SettingsKeys.minEventDescriptionLimit) ~/
                SettingsKeys.eventDescriptionLimitStep,
            captionStyle: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
            draftCaption: (draft) => l10n.eventDescriptionLimitDesc(draft),
            onCommit: (value) async {
              _onHapticFeedback();
              setState(() => _descriptionLimit = value);
              await _settings?.setEventDescriptionLimit(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.deleteAllEvents,
          description: _eventCount > 0
              ? l10n.deleteAllEventsDesc
              : l10n.noEventsToDelete,
          titleStyle: TextStyle(
            color: _eventCount > 0 ? colorScheme.error : null,
          ),
          builder: (context, title, description) => ListTile(
            enabled: _eventCount > 0,
            leading: Icon(
              Icons.delete_sweep_outlined,
              color: _eventCount > 0
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
            title: title,
            subtitle: description,
            onTap: _eventCount > 0 ? _confirmDeleteAllEvents : null,
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

  Future<void> _confirmDeleteAllEvents() async {
    final l10n = AppLocalizations.of(context)!;
    _onHapticFeedback();

    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.deleteAllEvents,
      content: l10n.deleteAllEventsConfirm,
      confirmText: l10n.delete,
      icon: Icons.delete_sweep_rounded,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    await _eventService?.deleteAll();
    if (!mounted) return;
    setState(() => _eventCount = 0);
    CustomSnackbar.showSuccess(context, l10n.allEventsDeleted);
  }

  Future<void> _resetToDefaults() async {
    const defaults = CalendarAppearance(
      maxDayBars: SettingsKeys.defaultCalendarMaxDayBars,
    );
    await _settings?.setCalendarMaxDayBars(defaults.maxDayBars);
    await _settings?.setCalendarTodayStyle(defaults.todayStyle);
    await _settings?.setCalendarMarkerStyle(defaults.markerStyle);
    await _settings?.setCalendarWeekStart(defaults.weekStart);
    await _settings?.setCalendarAccentColor(defaults.accentColorValue);
    await _settings?.setCalendarHighlightWeekends(defaults.highlightWeekends);
    await _settings?.setCalendarShowWeekNumbers(defaults.showWeekNumbers);
    await _settings?.setCalendarShowRecurrenceLabels(
      defaults.showRecurrenceLabels,
    );
    await _settings?.setCalendarMissedDisplay(defaults.missedDisplay);
    await _settings?.setCalendarEventTint(defaults.eventTint);
    await _settings?.setCalendarTintConflict(defaults.tintConflict);
    await _settings?.setEventDescriptionLimit(
      SettingsKeys.defaultEventDescriptionLimit,
    );
    await _settings?.setFastingTraditions(const {});
    await _settings?.setFastingAppearance(const FastingAppearance());
    await _settings?.setFastingOrthodoxGreatFasts(true);
    await _settings?.setFastingSchedule(const FastingSchedule());
    try {
      await _holidayService?.setProfile(HolidayProfile.generic);
    } catch (_) {
      // Keep the previously persisted profile on failure; the dropdown
      // resyncs from the service below.
    }

    if (!mounted) return;
    setState(() {
      _appearance = defaults;
      _holidayProfile = _holidayService?.profile ?? HolidayProfile.generic;
      _fastingTraditions = const {};
      _fastingAppearance = const FastingAppearance();
      _fastingGreatFasts = true;
      _fastingSchedule = const FastingSchedule();
      _descriptionLimit = SettingsKeys.defaultEventDescriptionLimit;
    });

    if (!mounted) return;
    CustomSnackbar.showSuccess(
      context,
      AppLocalizations.of(context)!.settingsReset,
    );
  }
}

/// Live preview strip: five sample day cells (weekend, plain, today,
/// selected, busy day with overflowing markers) rendered with the exact
/// widgets the calendar grid uses, so every appearance option is visible
/// before leaving the settings page.
class _AppearancePreview extends StatelessWidget {
  final CalendarAppearance appearance;

  const _AppearancePreview({required this.appearance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = appearance.accentOr(colorScheme.primary);
    final today = DateTime.now();

    final palette = [
      for (final value in CalendarColors.swatchPalette) Color(value),
    ];
    final overflowBars = [
      for (var i = 0; i <= appearance.maxDayBars; i++)
        _previewBar('overflow$i', palette[(i * 3) % palette.length]),
    ];
    final cellHeight =
        CalendarDayCell.chipZoneHeight +
        CalendarDayBars.stripHeight(
          appearance.maxDayBars,
          appearance.markerStyle,
        ) +
        6;

    // Samples the real alpha ramp rather than picked-by-eye values, so the
    // preview cannot drift from the grid. `priority` is 1-based like the
    // event field; a null one means the day carries no event.
    DayCellTint previewTint(Color color, {int? priority}) {
      if (!appearance.eventTint) {
        return priority == null
            ? DayCellTint.empty
            // With the tint off, a fasting day is the only wash there is.
            : DayCellTint(
                wash: CalendarColors.fasting.withValues(
                  alpha: CalendarColors.fastingTintAlpha,
                ),
              );
      }
      if (priority == null) return DayCellTint.empty;
      final eventWash = color.withValues(
        alpha: CalendarColors.eventTintAlphaByPriority[priority - 1],
      );
      final fastingWash = CalendarColors.fasting.withValues(
        alpha: CalendarColors.fastingTintAlpha,
      );
      return switch (appearance.tintConflict) {
        CalendarTintConflict.eventWins => DayCellTint(wash: eventWash),
        CalendarTintConflict.fastingWins => DayCellTint(wash: fastingWash),
        CalendarTintConflict.both => DayCellTint(
          wash: eventWash,
          edge: CalendarColors.fasting.withValues(
            alpha: CalendarColors.cellEdgeAlpha,
          ),
        ),
      };
    }

    Widget cell(
      DateTime day, {
      bool isToday = false,
      bool isSelected = false,
      bool isWeekend = false,
      List<DayBar> bars = const [],
      DayCellTint tint = DayCellTint.empty,
    }) {
      return Expanded(
        child: SizedBox(
          height: cellHeight < 52 ? 52 : cellHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: CalendarDayCell(
                  day: day,
                  isToday: isToday,
                  isSelected: isSelected,
                  isOutside: false,
                  isWeekend: isWeekend,
                  todayStyle: appearance.todayStyle,
                  highlightWeekends: appearance.highlightWeekends,
                  accent: accent,
                  tint: tint,
                ),
              ),
              if (bars.isNotEmpty)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: CalendarDayBars(
                      bars: bars,
                      maxBars: appearance.maxDayBars,
                      style: appearance.markerStyle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          cell(
            today.subtract(const Duration(days: 2)),
            isWeekend: true,
            bars: [_previewBar('weekend', CalendarColors.weekend)],
          ),
          cell(today.subtract(const Duration(days: 1))),
          // The two tinted samples sit at opposite ends of the priority ramp
          // so the "stronger means higher priority" claim is visible.
          cell(
            today,
            isToday: true,
            bars: [_previewBar('a', palette[0])],
            tint: previewTint(palette[0], priority: kMinEventPriority),
          ),
          cell(
            today.add(const Duration(days: 1)),
            isSelected: true,
            bars: [_previewBar('b', palette[3]), _previewBar('c', palette[7])],
            tint: previewTint(palette[3], priority: kMaxEventPriority),
          ),
          cell(today.add(const Duration(days: 2)), bars: overflowBars),
        ],
      ),
    );
  }

  static DayBar _previewBar(String key, Color color) {
    return DayBar(key: key, color: color, priority: 0, semanticLabel: '');
  }
}

/// Tappable color swatch used by the accent-color picker row. Mirrors the
/// event editor's color dots for a consistent picking experience.
class _AccentColorDot extends StatelessWidget {
  final Color color;
  final IconData? icon;
  final String? tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _AccentColorDot({
    required this.color,
    this.icon,
    this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final dot = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? colorScheme.onSurface
                : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected && icon == null
            ? Icon(Icons.check_rounded, size: 20, color: onColor)
            : icon != null
            ? Icon(icon, size: 20, color: onColor)
            : null,
      ),
    );
    if (tooltip == null) return dot;
    return Tooltip(message: tooltip!, child: dot);
  }
}
