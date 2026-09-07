import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/calendar_colors.dart';
import '../constants/fasting_calendar.dart';
import '../constants/public_holidays.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../constants/calendar_icons.dart';
import '../models/calendar_appearance.dart';
import '../models/fasting_appearance.dart';
import '../models/fasting_schedule.dart';
import '../widgets/fasting_schedule_sheet.dart';
import '../widgets/fasting_style_sheet.dart';
import '../services/app_navigator.dart';
import '../services/calendar_event_service.dart';
import '../services/calendar_palette_service.dart';
import '../services/public_holiday_service.dart';
import '../services/recurrence_formatter.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../widgets/app_dialogs.dart';
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
      _fastingTraditions = fastingTraditions;
      _fastingAppearance = fastingAppearance;
      _fastingGreatFasts = fastingGreatFasts;
      _fastingSchedule = fastingSchedule;
      _isLoading = false;
    });
  }

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
      _collapsedSections = const {};
    });

    if (!mounted) return;
    CustomSnackbar.showSuccess(
      context,
      AppLocalizations.of(context)!.settingsReset,
    );
  }
}
