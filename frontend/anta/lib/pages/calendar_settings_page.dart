import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import '../constants/alert_constants.dart';
import '../constants/app_spacing.dart';
import '../constants/calendar_colors.dart';
import '../constants/event_alerts.dart';
import '../constants/fasting_calendar.dart';
import '../constants/public_holidays.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../constants/calendar_icons.dart';
import '../models/alert_sound.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';
import '../models/fasting_appearance.dart';
import '../models/fasting_schedule.dart';
import '../models/recurrence_rule.dart';
import '../widgets/alert_editor_sheet.dart';
import '../widgets/alert_sound_sheet.dart';
import '../widgets/fasting_schedule_sheet.dart';
import '../widgets/fasting_style_sheet.dart';
import '../constants/semantics_ids.dart';
import '../services/alert_gateway.dart';
import '../services/alert_scheduler.dart';
import '../services/app_navigator.dart';
import '../services/calendar_event_service.dart';
import '../services/calendar_palette_service.dart';
import '../services/permission_service.dart';
import '../services/public_holiday_service.dart';
import '../services/recurrence_formatter.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/automation_id.dart';
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
  // Persisted fold state is keyed on these, so they are frozen strings, not
  // titles and not positions — renaming or reordering a section must not
  // reopen a card the user folded shut.
  static const String _sectionCalendar = 'calendar';
  static const String _sectionCategories = 'categories';
  static const String _sectionAppearance = 'appearance';
  static const String _sectionFiltering = 'filtering';
  static const String _sectionFasting = 'fasting';
  static const String _sectionEvents = 'events';
  static const String _sectionAlerts = 'alerts';

  SettingsService? _settings;
  bool _isLoading = true;
  Set<String> _collapsedSections = const {};

  final TextEditingController _searchController = TextEditingController();
  SettingsQuery _query = SettingsQuery.empty;

  CalendarAppearance _appearance = const CalendarAppearance();
  PublicHolidayService? _holidayService;
  HolidayProfile _holidayProfile = HolidayProfile.generic;
  bool _hapticFeedback = true;

  CalendarEventService? _eventService;
  int _eventCount = 0;
  int _descriptionLimit = SettingsKeys.defaultEventDescriptionLimit;

  int _snoozeMinutes = SettingsKeys.defaultAlertSnoozeMinutes;
  int _silenceAfterMinutes = SettingsKeys.defaultAlertSilenceAfterMinutes;
  int _noticeLeadMinutes = SettingsKeys.defaultAlertNoticeLeadMinutes;

  /// What a new event's first alert is seeded with, per shape. `null` is a
  /// value of its own — "no default" — and is what the rows render as
  /// `alertsDefaultNone`.
  TimedAlertDefault? _timedAlertDefault;
  AllDayAlertDefault? _allDayAlertDefault;

  /// Which sound an alarm plays when its own alert names none. `''` reads as
  /// the phone's default alarm — the setting has no "unset", unlike an alert.
  String _alertSound = SettingsKeys.defaultAlertSound;

  /// The phone's name for [_alertSound] when it is a picked one, resolved off
  /// the first frame so the row never waits on a platform round trip.
  String? _alertSoundTitle;
  bool _alertSoundTitleResolved = false;

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
    final alerts = await settings.getAlertSettings();
    final collapsedSections = await settings
        .getCalendarSettingsCollapsedSections();
    // Publishes the palette facade the fasting style sheet's swatch picker
    // reads synchronously; without it a sheet opened from here before any
    // other picker would offer zero of the colours the user does have. The
    // accent and palette rows moved to `CalendarAppearancePage`, which does
    // the same prewarm for itself.
    await CalendarPaletteService.getInstance();

    if (!mounted) return;
    setState(() {
      _settings = settings;
      _collapsedSections = collapsedSections;
      _appearance = appearance;
      _hapticFeedback = haptic;
      _holidayService = holidayService;
      _holidayProfile = holidayService.profile;
      _eventService = eventService;
      _eventCount = eventService.events.length;
      _descriptionLimit = descriptionLimit;
      _snoozeMinutes = alerts.snoozeMinutes;
      _silenceAfterMinutes = alerts.silenceAfterMinutes;
      _noticeLeadMinutes = alerts.noticeLeadMinutes;
      _timedAlertDefault = alerts.timedDefault;
      _allDayAlertDefault = alerts.allDayDefault;
      _alertSound = alerts.sound;
      _fastingTraditions = fastingTraditions;
      _fastingAppearance = fastingAppearance;
      _fastingGreatFasts = fastingGreatFasts;
      _fastingSchedule = fastingSchedule;
      _isLoading = false;
    });
    unawaited(_resolveAlertSoundTitle());
  }

  /// Asks the phone what it calls the stored sound, once per load. Best-effort
  /// and unawaited: a build with no gateway simply never answers and the row
  /// keeps its neutral name.
  Future<void> _resolveAlertSoundTitle() async {
    if (AlertSound.decode(_alertSound) is! AlertSoundUri) return;
    if (!GetIt.I.isRegistered<AlertGateway>()) return;
    final title = await GetIt.I<AlertGateway>().soundTitle(_alertSound);
    if (!mounted) return;
    setState(() {
      _alertSoundTitle = title;
      _alertSoundTitleResolved = true;
    });
  }

  /// Writes the app-wide alarm sound and makes the phone catch up.
  ///
  /// The reconcile is the point: nothing about any event changed, so no bloc
  /// dispatches and nothing else would ever re-arm the alarms already standing
  /// on the old sound. The pass re-arms exactly the registrations whose arm
  /// signature moved and leaves every other one on its fast path.
  Future<void> _editAlertSound() async {
    _onHapticFeedback();
    final l10n = AppLocalizations.of(context)!;
    final result = await AlertSoundSheet.show(context, value: _alertSound);
    if (result == null || !mounted) return;
    switch (result) {
      case AlertSoundPickerMissing():
        CustomSnackbar.showError(context, l10n.alertSoundPickerUnavailable);
      case AlertSoundPicked(:final value, :final title):
        setState(() {
          _alertSound = value ?? SettingsKeys.defaultAlertSound;
          _alertSoundTitle = title;
          _alertSoundTitleResolved = title != null;
        });
        await _settings?.setAlertSound(_alertSound);
        await AlertScheduler.reconcileAllQuietly(
          AlertReconcileReason.eventChanged,
        );
    }
  }

  PermissionService? get _permissionService =>
      GetIt.I.isRegistered<PermissionService>()
      ? GetIt.I<PermissionService>()
      : null;

  /// Optimistic like every other row on this page: the fold is a view
  /// preference, so a failed write costs nothing worth blocking the tap for.
  Future<void> _toggleSection(String id) async {
    _onHapticFeedback();
    final next = {..._collapsedSections};
    if (!next.remove(id)) next.add(id);
    setState(() => _collapsedSections = next);
    await _settings?.setCalendarSettingsCollapsedSections(next);
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
      body: SafeArea(
        top: false,
        child: _isLoading
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
                      sections: _buildSections(
                        context,
                        theme,
                        colorScheme,
                        l10n,
                      ),
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
    ThemeData theme,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    // What the calendar *is* (grid, categories) before how it *looks*:
    // categories used to sit behind a dozen appearance rows, which is a long
    // way down for the one row that opens a page of its own.
    return [
      _buildCalendarSection(colorScheme, l10n),
      _buildCategoriesSection(colorScheme, l10n),
      _buildAppearanceSection(colorScheme, l10n),
      _buildFilteringSection(colorScheme, l10n),
      _buildFastingSection(theme, colorScheme, l10n),
      _buildEventsSection(colorScheme, l10n),
      _buildAlertsSection(colorScheme, l10n),
    ];
  }

  SettingsSectionData _buildCalendarSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      id: _sectionCalendar,
      icon: Icons.calendar_month_rounded,
      title: l10n.calendarSection,
      entries: [
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

  /// One row into [CalendarAppearancePage], structurally the categories row.
  ///
  /// The fifteen appearance rows moved to a route of their own so the live
  /// preview could be pinned above them instead of scrolling away with the
  /// section's `intro:` — but settings search still runs over *this* page, so
  /// every moved row's title is declared as a keyword here. Without them,
  /// typing "day rail" or "today style" in Calendar Settings would find
  /// nothing at all.
  SettingsSectionData _buildAppearanceSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      id: _sectionAppearance,
      icon: Icons.palette_rounded,
      title: l10n.calendarAppearanceSection,
      entries: [
        SettingsEntry(
          title: l10n.calendarAppearanceSection,
          description: l10n.calendarAppearanceDesc,
          keywords: [
            l10n.calendarTodayStyleTitle,
            l10n.calendarAccentColor,
            l10n.colorPaletteTitle,
            l10n.calendarMarkerStyleTitle,
            l10n.calendarMaxDayBars,
            l10n.calendarMissedDisplayTitle,
            l10n.calendarDayRailStyleTitle,
            l10n.calendarMaxDayRailMarks,
            l10n.calendarDayRailBasePositionTitle,
            l10n.calendarHighlightWeekends,
            l10n.calendarEventTintTitle,
            l10n.calendarTintConflictTitle,
            l10n.calendarCellStyleTitle,
            l10n.calendarShowWeekNumbers,
            l10n.calendarWeekStartTitle,
            l10n.calendarShowRecurrenceLabels,
          ],
          builder: (context, title, description) => ListTile(
            leading: Icon(Icons.palette_rounded, color: colorScheme.primary),
            title: title,
            subtitle: description,
            trailing: const Icon(Icons.chevron_right_rounded),
            // The two pages hold two copies of one `CalendarAppearance`, and
            // this one still renders `showFilterChips` from its copy — so the
            // appearance page's writes have to be read back when it pops, or
            // the Filtering switch would keep showing a value that page reset
            // away from. `context` is only used before the await; after it,
            // `_loadSettings` guards on `mounted` itself.
            onTap: () async {
              await AppNavigator.toCalendarAppearance(context);
              if (mounted) await _loadSettings();
            },
          ),
        ),
      ],
    );
  }

  /// Everything about narrowing what the calendar shows — as opposed to how
  /// what is shown is drawn, which is the appearance section above.
  SettingsSectionData _buildFilteringSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      id: _sectionFiltering,
      icon: Icons.filter_alt_rounded,
      title: l10n.calendarFilteringSection,
      entries: [
        SettingsEntry(
          title: l10n.calendarShowFilterChips,
          description: l10n.calendarShowFilterChipsDesc,
          builder: (context, title, description) => SwitchListTile(
            value: _appearance.showFilterChips,
            secondary: Icon(
              Icons.filter_alt_outlined,
              color: colorScheme.primary,
            ),
            title: title,
            subtitle: description,
            onChanged: (value) async {
              _onHapticFeedback();
              setState(
                () =>
                    _appearance = _appearance.copyWith(showFilterChips: value),
              );
              await _settings?.setCalendarShowFilterChips(value);
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
      id: _sectionCategories,
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
      id: _sectionFasting,
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
      id: _sectionEvents,
      icon: Icons.event_note_rounded,
      title: l10n.calendarEventsSection,
      entries: [
        // A template is a saved event, not a category — it only ever lived
        // next to the categories row because both open a page.
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

  /// §5.7. The permissions link, two defaults, two lengths and a test ring.
  ///
  /// What the operating system allows lives on the Permissions page; the row
  /// here only says whether anything essential is missing, read **live** off
  /// the `PermissionService` snapshot and never stored.
  SettingsSectionData _buildAlertsSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final captionStyle = TextStyle(
      fontSize: 12,
      color: colorScheme.onSurfaceVariant,
    );
    return SettingsSectionData(
      id: _sectionAlerts,
      icon: Icons.alarm_rounded,
      title: l10n.calendarAlertsSection,
      entries: [
        SettingsEntry(
          title: l10n.permissionsTitle,
          description: l10n.permissionsCalendarRowDesc,
          keywords: [
            l10n.alertsNotifications,
            l10n.permissionExactAlarms,
            l10n.alertsFullScreenAlarms,
            l10n.alertsBattery,
          ],
          builder: (context, title, description) =>
              _permissionsTile(colorScheme, title, description),
        ),
        SettingsEntry(
          title: l10n.alertsDefaultTimed,
          description: l10n.alertsDefaultTimedDesc,
          builder: (context, title, description) => ListTile(
            leading: Icon(Icons.schedule_rounded, color: colorScheme.primary),
            title: title,
            subtitle: description,
            trailing: Text(
              _describeDefault(l10n, allDay: false),
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            onTap: () => _editAlertDefault(allDay: false),
          ),
        ),
        SettingsEntry(
          title: l10n.alertsDefaultAllDay,
          description: l10n.alertsDefaultAllDayDesc,
          builder: (context, title, description) => ListTile(
            leading: Icon(Icons.today_rounded, color: colorScheme.primary),
            title: title,
            subtitle: description,
            trailing: Text(
              _describeDefault(l10n, allDay: true),
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            onTap: () => _editAlertDefault(allDay: true),
          ),
        ),
        SettingsEntry(
          title: l10n.alertsSound,
          description: l10n.alertsSoundDesc,
          keywords: [l10n.alertSoundPhoneDefault, l10n.eventAlertModeRing],
          builder: (context, title, description) => ListTile(
            leading: Icon(Icons.music_note_rounded, color: colorScheme.primary),
            title: title,
            subtitle: description,
            trailing: Text(
              AlertSoundSheet.labelFor(
                l10n,
                _alertSound,
                title: _alertSoundTitle,
                titleResolved: _alertSoundTitleResolved,
              ),
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            onTap: _editAlertSound,
          ),
        ),
        SettingsEntry(
          title: l10n.alertsSnoozeLength,
          description: l10n.alertsSnoozeLengthDesc(_snoozeMinutes),
          builder: (context, title, description) => SliderSettingRow(
            title: title,
            description: description,
            value: _snoozeMinutes,
            min: SettingsKeys.minAlertSnoozeMinutes,
            max: SettingsKeys.maxAlertSnoozeMinutes,
            divisions:
                (SettingsKeys.maxAlertSnoozeMinutes -
                    SettingsKeys.minAlertSnoozeMinutes) ~/
                SettingsKeys.alertSnoozeMinutesStep,
            captionStyle: captionStyle,
            draftCaption: (draft) => l10n.alertsSnoozeLengthDesc(draft),
            onCommit: (value) async {
              _onHapticFeedback();
              setState(() => _snoozeMinutes = value);
              await _settings?.setAlertSnoozeMinutes(value);
              // Armed into every alarm-tier entry as the plugin's own Snooze
              // (OS-2), so standing alarms owe the same catch-up a changed
              // sound gets.
              await AlertScheduler.reconcileAllQuietly(
                AlertReconcileReason.eventChanged,
              );
            },
          ),
        ),
        SettingsEntry(
          title: l10n.alertsNoticeLead,
          description: _noticeLeadMinutes == 0
              ? l10n.alertsNoticeLeadOff
              : l10n.alertsNoticeLeadDesc(_noticeLeadMinutes),
          builder: (context, title, description) => SliderSettingRow(
            title: title,
            description: description,
            value: _noticeLeadMinutes,
            min: SettingsKeys.minAlertNoticeLeadMinutes,
            max: SettingsKeys.maxAlertNoticeLeadMinutes,
            divisions:
                (SettingsKeys.maxAlertNoticeLeadMinutes -
                    SettingsKeys.minAlertNoticeLeadMinutes) ~/
                SettingsKeys.alertNoticeLeadMinutesStep,
            captionStyle: captionStyle,
            draftCaption: (draft) => draft == 0
                ? l10n.alertsNoticeLeadOff
                : l10n.alertsNoticeLeadDesc(draft),
            onCommit: (value) async {
              _onHapticFeedback();
              setState(() => _noticeLeadMinutes = value);
              await _settings?.setAlertNoticeLeadMinutes(value);
              // The lead rides the arm signature, so this is what moves — or
              // removes — the notice of every alarm already standing.
              await AlertScheduler.reconcileAllQuietly(
                AlertReconcileReason.eventChanged,
              );
            },
          ),
        ),
        SettingsEntry(
          title: l10n.alertsSilenceAfter,
          description: l10n.alertsSilenceAfterDesc(_silenceAfterMinutes),
          builder: (context, title, description) => SliderSettingRow(
            title: title,
            description: description,
            value: _silenceAfterMinutes,
            min: SettingsKeys.minAlertSilenceAfterMinutes,
            max: SettingsKeys.maxAlertSilenceAfterMinutes,
            divisions:
                SettingsKeys.maxAlertSilenceAfterMinutes -
                SettingsKeys.minAlertSilenceAfterMinutes,
            captionStyle: captionStyle,
            draftCaption: (draft) => l10n.alertsSilenceAfterDesc(draft),
            onCommit: (value) async {
              _onHapticFeedback();
              setState(() => _silenceAfterMinutes = value);
              await _settings?.setAlertSilenceAfterMinutes(value);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.alertsTestAlarm,
          // The force-stop note rides this row rather than a row of its own:
          // it is the one thing about alerts nothing in the app can fix, and
          // it belongs beside the button that proves they work.
          description: l10n.alertsForceStopNote,
          builder: (context, title, description) => Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AutomationId(
                  identifier: SemanticsIds.alertsTestAlarm,
                  child: OutlinedButton.icon(
                    onPressed: _scheduleTestAlarm,
                    icon: const Icon(Icons.alarm_add_rounded),
                    label: title,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (description != null)
                  DefaultTextStyle.merge(
                    style: captionStyle,
                    child: description,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _permissionsTile(
    ColorScheme colorScheme,
    Widget title,
    Widget? description,
  ) {
    Widget tile(bool attention) => ListTile(
      leading: Icon(
        Icons.verified_user_outlined,
        color: attention ? colorScheme.error : colorScheme.primary,
      ),
      title: title,
      subtitle: description,
      trailing: Icon(
        attention ? Icons.error_outline_rounded : Icons.chevron_right_rounded,
        color: attention ? colorScheme.error : colorScheme.onSurfaceVariant,
      ),
      onTap: () {
        _onHapticFeedback();
        AppNavigator.toPermissions(context);
      },
    );
    final service = _permissionService;
    if (service == null) return tile(false);
    return ValueListenableBuilder(
      valueListenable: service.snapshot,
      builder: (context, snapshot, _) =>
          tile(snapshot?.needsAttention ?? false),
    );
  }

  /// The stand-in event the two default rows describe themselves through.
  ///
  /// [EventAlert.describe] answers for an *event*, and a default belongs to no
  /// event — so the row hands it the one property that decides the reading,
  /// the derived `allDay`. Anything else on this object is unread.
  static CalendarEvent _alertSampleEvent({required bool allDay}) =>
      CalendarEvent(
        id: '',
        title: '',
        categoryId: kDefaultCategoryId,
        startDate: DateTime.utc(2026),
        rule: const OneTimeRecurrence(),
        time: allDay ? null : const EventTime(startMinute: 9 * 60),
      );

  /// The alert a default currently stands for, as one alert-shaped object, or
  /// null when the setting says "none".
  EventAlert? _defaultAlert({required bool allDay}) {
    if (allDay) {
      final value = _allDayAlertDefault;
      if (value == null) return null;
      return EventAlert(
        id: 'default',
        eventId: '',
        mode: value.mode,
        daysBefore: value.daysBefore,
        dayMinute: value.dayMinute,
      );
    }
    final value = _timedAlertDefault;
    if (value == null) return null;
    return EventAlert(
      id: 'default',
      eventId: '',
      mode: value.mode,
      offsetMinutes: value.offsetMinutes,
    );
  }

  String _describeDefault(AppLocalizations l10n, {required bool allDay}) {
    final alert = _defaultAlert(allDay: allDay);
    if (alert == null) return l10n.alertsDefaultNone;
    final tier = alert.isAlarm
        ? l10n.eventAlertModeRing
        : l10n.eventAlertModeNotify;
    return '$tier · ${alert.describe(l10n, _alertSampleEvent(allDay: allDay))}';
  }

  /// Edits one default through the same sheet an event's own alert uses, so
  /// the timing vocabulary cannot drift between the two. Remove there means
  /// "no default" — the `none` the decoder reads as "seed nothing".
  Future<void> _editAlertDefault({required bool allDay}) async {
    _onHapticFeedback();
    final sample = _alertSampleEvent(allDay: allDay);
    final result = await AlertEditorSheet.show(
      context,
      alert:
          _defaultAlert(allDay: allDay) ??
          AlertEditorSheet.draft(eventId: '', allDay: allDay),
      event: sample,
      // A default encodes a tier and an offset, nothing else — and the Alarm
      // sound row below this one is where the sound actually lives.
      showSound: false,
    );
    if (result == null || !mounted) return;
    switch (result) {
      case AlertEditorRemoved():
        setState(() {
          if (allDay) {
            _allDayAlertDefault = null;
          } else {
            _timedAlertDefault = null;
          }
        });
        if (allDay) {
          await _settings?.setAlertDefaultAllDay(null);
        } else {
          await _settings?.setAlertDefaultTimed(null);
        }
      case AlertEditorSaved(:final alert):
        if (allDay) {
          final value = (
            mode: alert.mode,
            daysBefore: alert.daysBefore,
            dayMinute: alert.dayMinute ?? kDefaultAlertDayMinute,
          );
          setState(() => _allDayAlertDefault = value);
          await _settings?.setAlertDefaultAllDay(value);
        } else {
          final value = (mode: alert.mode, offsetMinutes: alert.offsetMinutes);
          setState(() => _timedAlertDefault = value);
          await _settings?.setAlertDefaultTimed(value);
        }
    }
  }

  Future<void> _scheduleTestAlarm() async {
    final l10n = AppLocalizations.of(context)!;
    _onHapticFeedback();
    final permissions = await _permissionService?.refresh();
    if (!mounted) return;
    if (permissions?.needsAttention ?? false) {
      CustomSnackbar.showWithAction(
        context,
        message: l10n.permissionsAlertBlocked,
        actionLabel: l10n.permissionsReview,
        onAction: () {
          if (context.mounted) AppNavigator.toPermissions(context);
        },
      );
      return;
    }
    int? osId;
    try {
      final scheduler = await AlertScheduler.getInstance();
      osId = await scheduler.scheduleTestAlarm(
        title: l10n.alertsTestAlarm,
        delay: kAlertTestAlarmDelay,
      );
    } catch (e) {
      debugPrint('[CalendarSettings] test alarm failed: $e');
    }
    if (!mounted) return;
    if (osId == null) {
      CustomSnackbar.showError(context, l10n.alertsTestAlarmFailed);
      return;
    }
    CustomSnackbar.showSuccess(context, l10n.alertsTestAlarmScheduled);
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
    // Scoped to the rows this page still owns. Every other appearance key is
    // reset by `CalendarAppearancePage`, beside the controls that set it —
    // resetting a value whose control is a route away means the user cannot
    // see what changed, which is the same argument that keeps
    // `showFilterChips` out of *that* page's reset. `showFilterChips` is the
    // one appearance field whose row stayed here.
    const defaults = CalendarAppearance();
    await _settings?.setCalendarShowFilterChips(defaults.showFilterChips);
    await _settings?.setEventDescriptionLimit(
      SettingsKeys.defaultEventDescriptionLimit,
    );
    await _settings?.setAlertSnoozeMinutes(
      SettingsKeys.defaultAlertSnoozeMinutes,
    );
    await _settings?.setAlertSilenceAfterMinutes(
      SettingsKeys.defaultAlertSilenceAfterMinutes,
    );
    await _settings?.setAlertNoticeLeadMinutes(
      SettingsKeys.defaultAlertNoticeLeadMinutes,
    );
    // The two defaults go back to what the app ships with, read through the
    // decoder rather than spelled here — and the stock behaviour is that a
    // new event carries no alert until the user adds one.
    final shipped = SettingsService.shippedAlertSettings;
    await _settings?.setAlertDefaultTimed(shipped.timedDefault);
    await _settings?.setAlertDefaultAllDay(shipped.allDayDefault);
    await _settings?.setAlertSound(shipped.sound);
    // The page resets to how it ships, and it ships open — leaving a section
    // folded after a reset hides rows the user just asked to see restored.
    await _settings?.setCalendarSettingsCollapsedSections(const {});
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
      // Only the field this page reset — claiming the whole appearance went
      // back to defaults would make this copy disagree with what is stored.
      _appearance = _appearance.copyWith(
        showFilterChips: defaults.showFilterChips,
      );
      _holidayProfile = _holidayService?.profile ?? HolidayProfile.generic;
      _fastingTraditions = const {};
      _fastingAppearance = const FastingAppearance();
      _fastingGreatFasts = true;
      _fastingSchedule = const FastingSchedule();
      _descriptionLimit = SettingsKeys.defaultEventDescriptionLimit;
      _snoozeMinutes = SettingsKeys.defaultAlertSnoozeMinutes;
      _silenceAfterMinutes = SettingsKeys.defaultAlertSilenceAfterMinutes;
      _noticeLeadMinutes = SettingsKeys.defaultAlertNoticeLeadMinutes;
      _timedAlertDefault = shipped.timedDefault;
      _allDayAlertDefault = shipped.allDayDefault;
      _alertSound = shipped.sound;
      _alertSoundTitle = null;
      _alertSoundTitleResolved = false;
      _collapsedSections = const {};
    });
    // A reset can move the sound off a picked one, so the standing alarms owe
    // the same catch-up an ordinary edit gets.
    await AlertScheduler.reconcileAllQuietly(AlertReconcileReason.eventChanged);

    if (!mounted) return;
    CustomSnackbar.showSuccess(
      context,
      AppLocalizations.of(context)!.settingsReset,
    );
  }
}
