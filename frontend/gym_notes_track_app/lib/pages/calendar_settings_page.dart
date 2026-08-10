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
import '../models/day_bar.dart';
import '../models/fasting_appearance.dart';
import '../widgets/fasting_style_sheet.dart';
import '../services/app_navigator.dart';
import '../services/calendar_event_service.dart';
import '../services/event_occurrence_service.dart';
import '../services/public_holiday_service.dart';
import '../services/recurrence_formatter.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/calendar_day_bars.dart';
import '../widgets/calendar_day_cell.dart';
import '../widgets/color_wheel_picker.dart';
import '../widgets/removed_holidays_sheet.dart';
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

  CalendarAppearance _appearance = const CalendarAppearance();
  PublicHolidayService? _holidayService;
  HolidayProfile _holidayProfile = HolidayProfile.generic;
  bool _hapticFeedback = true;

  CalendarEventService? _eventService;
  int _eventCount = 0;
  int _descriptionLimit = SettingsKeys.defaultEventDescriptionLimit;

  /// Owned by the service, not by `SettingsService`: writing the flag and
  /// republishing the static facade have to happen together, so there is
  /// deliberately no settable path that could leave them disagreeing.
  EventOccurrenceService? _occurrenceService;
  bool _perOccurrenceDescriptions =
      SettingsKeys.defaultEventPerOccurrenceDescriptions;

  Set<FastingTradition> _fastingTraditions = const {};
  FastingAppearance _fastingAppearance = const FastingAppearance();
  bool _fastingGreatFasts = true;
  Set<int> _fastingWeekdays = FastingCalendar.defaultWeekdayFastDays;

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
    final fastingWeekdays = await settings.getFastingWeekdays();
    final descriptionLimit = await settings.getEventDescriptionLimit();
    final occurrenceService = await EventOccurrenceService.getInstance();

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
      _occurrenceService = occurrenceService;
      _perOccurrenceDescriptions = occurrenceService.enabled;
      _fastingTraditions = fastingTraditions;
      _fastingAppearance = fastingAppearance;
      _fastingGreatFasts = fastingGreatFasts;
      _fastingWeekdays = fastingWeekdays;
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

  Future<void> _toggleFastingWeekday(int weekday) async {
    _onHapticFeedback();
    setState(() {
      final next = {..._fastingWeekdays};
      next.contains(weekday) ? next.remove(weekday) : next.add(weekday);
      _fastingWeekdays = next;
    });
    await _settings?.setFastingWeekdays(_fastingWeekdays);
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
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionCard(
                  context: context,
                  colorScheme: colorScheme,
                  icon: Icons.calendar_month_rounded,
                  title: l10n.calendarSection,
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.view_week_outlined,
                        color: colorScheme.primary,
                      ),
                      title: Text(l10n.calendarWeekStartTitle),
                      trailing: DropdownButton<CalendarWeekStart>(
                        value: _appearance.weekStart,
                        underline: const SizedBox.shrink(),
                        onChanged: (next) async {
                          if (next == null || next == _appearance.weekStart) {
                            return;
                          }
                          _onHapticFeedback();
                          setState(
                            () => _appearance = _appearance.copyWith(
                              weekStart: next,
                            ),
                          );
                          await _settings?.setCalendarWeekStart(next);
                        },
                        items: [
                          for (final start in CalendarWeekStart.values)
                            DropdownMenuItem(
                              value: start,
                              child: Text(
                                _weekStartLabel(start, l10n.localeName),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.public_rounded,
                        color: colorScheme.primary,
                      ),
                      title: Text(l10n.holidayProfileTitle),
                      subtitle: Text(
                        PublicHolidays.profileNameOf(_holidayProfile, l10n),
                      ),
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
                              () => _holidayProfile =
                                  _holidayService?.profile ?? next,
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
                              child: Text(
                                PublicHolidays.profileNameOf(profile, l10n),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.restore_rounded,
                        color: colorScheme.primary,
                      ),
                      title: Text(l10n.removedHolidays),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _holidayService == null
                          ? null
                          : () => RemovedHolidaysSheet.show(
                              context,
                              _holidayService!,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  context: context,
                  colorScheme: colorScheme,
                  icon: Icons.palette_rounded,
                  title: l10n.calendarAppearanceSection,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: _AppearancePreview(appearance: _appearance),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.calendarTodayStyleTitle,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
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
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.calendarAccentColor,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.calendarAccentColorDesc,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
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
                                  selected:
                                      _appearance.accentColorValue == swatch,
                                  onTap: () async {
                                    _onHapticFeedback();
                                    setState(
                                      () => _appearance = _appearance.copyWith(
                                        accentColorValue: swatch,
                                      ),
                                    );
                                    await _settings?.setCalendarAccentColor(
                                      swatch,
                                    );
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
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.calendarMarkerStyleTitle,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
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
                              await _settings?.setCalendarMarkerStyle(
                                sel.first,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    _buildSliderTile(
                      context: context,
                      colorScheme: colorScheme,
                      title: l10n.calendarMaxDayBars,
                      subtitle: l10n.calendarMaxDayBarsDesc(
                        _appearance.maxDayBars,
                      ),
                      value: _appearance.maxDayBars.toDouble(),
                      min: 1,
                      max: 6,
                      divisions: 5,
                      onChanged: (value) async {
                        _onHapticFeedback();
                        setState(
                          () => _appearance = _appearance.copyWith(
                            maxDayBars: value.round(),
                          ),
                        );
                        await _settings?.setCalendarMaxDayBars(value.round());
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _appearance.highlightWeekends,
                      secondary: Icon(
                        Icons.weekend_outlined,
                        color: colorScheme.primary,
                      ),
                      title: Text(l10n.calendarHighlightWeekends),
                      subtitle: Text(l10n.calendarHighlightWeekendsDesc),
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
                    SwitchListTile(
                      value: _appearance.showWeekNumbers,
                      secondary: Icon(
                        Icons.tag_rounded,
                        color: colorScheme.primary,
                      ),
                      title: Text(l10n.calendarShowWeekNumbers),
                      subtitle: Text(l10n.calendarShowWeekNumbersDesc),
                      onChanged: (value) async {
                        _onHapticFeedback();
                        setState(
                          () => _appearance = _appearance.copyWith(
                            showWeekNumbers: value,
                          ),
                        );
                        await _settings?.setCalendarShowWeekNumbers(value);
                      },
                    ),
                    SwitchListTile(
                      value: _appearance.showRecurrenceLabels,
                      secondary: Icon(
                        Icons.repeat_rounded,
                        color: colorScheme.primary,
                      ),
                      title: Text(l10n.calendarShowRecurrenceLabels),
                      subtitle: Text(l10n.calendarShowRecurrenceLabelsDesc),
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
                  ],
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  context: context,
                  colorScheme: colorScheme,
                  icon: Icons.category_rounded,
                  title: l10n.calendarCategories,
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.palette_outlined,
                        color: colorScheme.primary,
                      ),
                      title: Text(l10n.calendarCategories),
                      subtitle: Text(l10n.calendarCategoriesDesc),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => AppNavigator.toCalendarCategories(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  context: context,
                  colorScheme: colorScheme,
                  icon: Icons.restaurant_menu_rounded,
                  title: l10n.fastingSectionTitle,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        l10n.fastingSectionDesc,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final tradition in FastingTradition.values) ...[
                      SwitchListTile(
                        value: _fastingTraditions.contains(tradition),
                        secondary: Icon(
                          _fastingStyleOf(tradition).iconKey == null
                              ? FastingCalendar.defaultIconOf(tradition)
                              : (CalendarIcons.forKey(
                                      _fastingStyleOf(tradition).iconKey,
                                    ) ??
                                    FastingCalendar.defaultIconOf(tradition)),
                          color: _fastingTraditions.contains(tradition)
                              ? _fastingStyleOf(
                                  tradition,
                                ).colorOr(CalendarColors.fasting)
                              : colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          FastingCalendar.traditionNameOf(tradition, l10n),
                        ),
                        onChanged: (value) =>
                            _toggleFastingTradition(tradition, value),
                      ),
                      // The appearance row only exists for enabled
                      // traditions — configuring the look of something that
                      // draws nothing is noise.
                      if (_fastingTraditions.contains(tradition))
                        Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              Icons.tune_rounded,
                              color: colorScheme.primary,
                            ),
                            title: Text(l10n.fastingAppearanceTitle),
                            subtitle: Text(
                              _fastingStyleSummary(tradition, l10n),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _editFastingStyle(tradition),
                          ),
                        ),
                    ],
                    if (_fastingTraditions.contains(
                      FastingTradition.orthodox,
                    )) ...[
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _fastingGreatFasts,
                        secondary: Icon(
                          Icons.date_range_rounded,
                          color: colorScheme.primary,
                        ),
                        title: Text(l10n.fastingOrthodoxGreatFasts),
                        subtitle: Text(l10n.fastingOrthodoxGreatFastsDesc),
                        onChanged: (value) async {
                          _onHapticFeedback();
                          setState(() => _fastingGreatFasts = value);
                          await _settings?.setFastingOrthodoxGreatFasts(value);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.fastingWeekdayDaysTitle,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (var w = 1; w <= 7; w++)
                                  FilterChip(
                                    label: Text(
                                      RecurrenceFormatter.weekdayShort(
                                        w,
                                        l10n.localeName,
                                      ),
                                    ),
                                    selected: _fastingWeekdays.contains(w),
                                    onSelected: (_) => _toggleFastingWeekday(w),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.fastingWeekdayDaysDesc,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  context: context,
                  colorScheme: colorScheme,
                  icon: Icons.event_note_rounded,
                  title: l10n.calendarEventsSection,
                  children: [
                    SwitchListTile(
                      value: _perOccurrenceDescriptions,
                      secondary: Icon(
                        Icons.event_note_outlined,
                        color: colorScheme.primary,
                      ),
                      title: Text(l10n.eventPerOccurrenceDescriptions),
                      subtitle: Text(l10n.eventPerOccurrenceDescriptionsDesc),
                      onChanged: (value) async {
                        _onHapticFeedback();
                        setState(() => _perOccurrenceDescriptions = value);
                        // Through the service, never SettingsService: the
                        // write and the facade republish must be one step.
                        // Existing per-day rows are never touched, so turning
                        // this off is dormancy rather than deletion.
                        await _occurrenceService?.setEnabled(value);
                      },
                    ),
                    const Divider(height: 1),
                    _buildSliderTile(
                      context: context,
                      colorScheme: colorScheme,
                      title: l10n.eventDescriptionLimit,
                      subtitle: l10n.eventDescriptionLimitDesc(
                        _descriptionLimit,
                      ),
                      value: _descriptionLimit.toDouble(),
                      min: SettingsKeys.minEventDescriptionLimit.toDouble(),
                      max: SettingsKeys.maxEventDescriptionLimit.toDouble(),
                      divisions:
                          (SettingsKeys.maxEventDescriptionLimit -
                              SettingsKeys.minEventDescriptionLimit) ~/
                          SettingsKeys.eventDescriptionLimitStep,
                      onChanged: (value) async {
                        _onHapticFeedback();
                        setState(() => _descriptionLimit = value.round());
                        await _settings?.setEventDescriptionLimit(
                          value.round(),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      enabled: _eventCount > 0,
                      leading: Icon(
                        Icons.delete_sweep_outlined,
                        color: _eventCount > 0
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        l10n.deleteAllEvents,
                        style: TextStyle(
                          color: _eventCount > 0 ? colorScheme.error : null,
                        ),
                      ),
                      subtitle: Text(
                        _eventCount > 0
                            ? l10n.deleteAllEventsDesc
                            : l10n.noEventsToDelete,
                      ),
                      onTap: _eventCount > 0 ? _confirmDeleteAllEvents : null,
                    ),
                  ],
                ),
                const SizedBox(height: 32),
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
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required ColorScheme colorScheme,
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSliderTile({
    required BuildContext context,
    required ColorScheme colorScheme,
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: '${value.round()}',
            onChanged: onChanged,
          ),
        ],
      ),
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
    await _settings?.setEventDescriptionLimit(
      SettingsKeys.defaultEventDescriptionLimit,
    );
    // Routed through the service (like the holiday profile) so the static
    // facade is republished too. Per-day rows survive a settings reset —
    // resetting preferences must not delete content.
    await _occurrenceService?.setEnabled(
      SettingsKeys.defaultEventPerOccurrenceDescriptions,
    );
    await _settings?.setFastingTraditions(const {});
    await _settings?.setFastingAppearance(const FastingAppearance());
    await _settings?.setFastingOrthodoxGreatFasts(true);
    await _settings?.setFastingWeekdays(
      FastingCalendar.defaultWeekdayFastDays,
    );
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
      _fastingWeekdays = FastingCalendar.defaultWeekdayFastDays;
      _descriptionLimit = SettingsKeys.defaultEventDescriptionLimit;
      _perOccurrenceDescriptions =
          SettingsKeys.defaultEventPerOccurrenceDescriptions;
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

    Widget cell(
      DateTime day, {
      bool isToday = false,
      bool isSelected = false,
      bool isWeekend = false,
      List<DayBar> bars = const [],
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
          cell(today, isToday: true, bars: [_previewBar('a', palette[0])]),
          cell(
            today.add(const Duration(days: 1)),
            isSelected: true,
            bars: [_previewBar('b', palette[3]), _previewBar('c', palette[7])],
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
