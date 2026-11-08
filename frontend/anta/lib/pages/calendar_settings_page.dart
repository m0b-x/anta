import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/fasting_calendar.dart';
import '../constants/form_metrics.dart';
import '../constants/public_holidays.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/event_alert.dart';
import '../models/fasting_appearance.dart';
import '../models/report_cards.dart';
import '../constants/semantics_ids.dart';
import '../services/app_navigator.dart';
import '../services/calendar_event_service.dart';
import '../services/public_holiday_service.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/form_menu_item.dart';
import '../widgets/removed_holidays_sheet.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/slider_setting_row.dart';
import '../widgets/unified_app_bars.dart';
import '../widgets/value_change_highlight.dart';
import 'alert_settings_page.dart';
import 'calendar_report_settings_page.dart';
import 'fasting_settings_page.dart';

/// Calendar settings: the holidays, filtering and events options, and one row
/// each into the calendar's own settings pages (D7).
class CalendarSettingsPage extends StatefulWidget {
  const CalendarSettingsPage({super.key});

  @override
  State<CalendarSettingsPage> createState() => _CalendarSettingsPageState();
}

class _CalendarSettingsPageState extends State<CalendarSettingsPage>
    with RouteAware {
  // Persisted fold state is keyed on these, so they are frozen strings, not
  // titles and not positions — renaming or reordering a section must not
  // reopen a card the user folded shut. The holidays section kept the id it
  // had as "Calendar"; `pages` replaced the four single-row sections
  // (`appearance`, `categories`, `fasting`, `alerts`), whose ids a stored set
  // may still hold harmlessly.
  static const String _sectionCalendar = 'calendar';
  static const String _sectionPages = 'pages';
  static const String _sectionFiltering = 'filtering';
  static const String _sectionEvents = 'events';

  SettingsService? _settings;
  bool _isLoading = true;
  Set<String> _collapsedSections = const {};
  int _foldEdits = 0;

  final TextEditingController _searchController = TextEditingController();
  SettingsQuery _query = SettingsQuery.empty;

  CalendarAppearance _appearance = const CalendarAppearance();
  PublicHolidayService? _holidayService;
  HolidayProfile _holidayProfile = HolidayProfile.generic;
  bool _hapticFeedback = true;

  CalendarEventService? _eventService;
  int _eventCount = 0;
  int _descriptionLimit = SettingsKeys.defaultEventDescriptionLimit;

  /// What a new event's first alert is seeded with, per shape — read here
  /// only for the Alert settings row's value line. `null` is a value of its
  /// own, "no default".
  TimedAlertDefault? _timedAlertDefault;
  AllDayAlertDefault? _allDayAlertDefault;

  /// Read here only for the Fasting row's value line.
  Set<FastingTradition> _fastingTraditions = const {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppNavigator.routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    AppNavigator.routeObserver.unsubscribe(this);
    _searchController.dispose();
    super.dispose();
  }

  /// Called when a page pushed above this one is popped. The rows' own tap
  /// continuations read their page's writes back only for a page they
  /// pushed; a relaunch that restores `[calendarSettings, fastingSettings]`
  /// pushed the page above with no tap here, and without this its writes
  /// would leave the row stale and a fold toggled next would write a stale
  /// fold set.
  @override
  void didPopNext() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    final appearance = await settings.getCalendarAppearance();
    final haptic = await settings.getHapticFeedback();
    final holidayService = await PublicHolidayService.getInstance();
    final eventService = await CalendarEventService.getInstance();
    final fastingTraditions = await settings.getFastingTraditions();
    final descriptionLimit = await settings.getEventDescriptionLimit();
    final alerts = await settings.getAlertSettings();
    final collapsedSections = await settings
        .getCalendarSettingsCollapsedSections();

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
      _timedAlertDefault = alerts.timedDefault;
      _allDayAlertDefault = alerts.allDayDefault;
      _fastingTraditions = fastingTraditions;
      _isLoading = false;
    });
  }

  /// Optimistic like every other row on this page: the fold is a view
  /// preference, so a failed write costs nothing worth blocking the tap for.
  /// The stored set also holds the child pages' folds, which this copy may
  /// not have read yet, so the write edits the stored row and the page adopts
  /// what it wrote — only the last tap's answer, which holds every earlier
  /// one, so a quick second fold never flicks back open.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.pageGround,
      appBar: SettingsAppBar(
        title: l10n.calendarSettings,
        identifier: SemanticsIds.settingsBarCalendar,
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: FormMetrics.settingsSearchPadding,
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
    return [
      _buildCalendarSection(colorScheme, l10n),
      _buildPagesSection(context, colorScheme, l10n),
      _buildFilteringSection(colorScheme, l10n),
      _buildEventsSection(colorScheme, l10n),
    ];
  }

  /// The rows into the calendar's own settings pages, in one group (N118):
  /// as four sections of one row each, every row repeated its section's title
  /// as a header over it.
  SettingsSectionData _buildPagesSection(
    BuildContext context,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      id: _sectionPages,
      icon: Icons.tune_rounded,
      title: l10n.calendarSettingsPagesSection,
      entries: [
        _appearanceEntry(colorScheme, l10n),
        _categoriesEntry(colorScheme, l10n),
        _fastingEntry(colorScheme, l10n),
        _alertsEntry(context, colorScheme, l10n),
        _reportEntry(colorScheme, l10n),
      ],
    );
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
        // The set's name is the row's value, so the description says what
        // the set is for (N99); the name stays a keyword, as searchable as it
        // was when it was the description. A value with a menu rather than a
        // dropdown in the trailing: the tile measures the name, so the
        // description is never crushed into the column beside it.
        SettingsEntry(
          title: l10n.holidayProfileTitle,
          description: l10n.holidayProfileDesc,
          keywords: [PublicHolidays.profileNameOf(_holidayProfile, l10n)],
          identifier: SemanticsIds.calendarHolidayProfile,
          builder: (context, title, description) {
            final value = PublicHolidays.profileNameOf(_holidayProfile, l10n);
            // A `Builder` so the menu hangs from the row's own box.
            return Builder(
              builder: (rowContext) => SettingsYieldingTile(
                leading: Icon(Icons.public_rounded, color: colorScheme.primary),
                title: title,
                subtitle: description,
                value: value,
                trailing: (maxWidth) => ValueChangeHighlight(
                  value: _holidayProfile,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Text(
                      value,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
                onTap: () => _pickHolidayProfile(rowContext, l10n),
              ),
            );
          },
        ),
        SettingsEntry(
          title: l10n.removedHolidays,
          identifier: SemanticsIds.calendarRemovedHolidaysOpen,
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

  Future<void> _pickHolidayProfile(
    BuildContext anchor,
    AppLocalizations l10n,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final next = await showFormMenu<HolidayProfile>(
      anchor,
      items: [
        for (final profile in HolidayProfile.values)
          FormMenuItem(
            value: profile,
            label: PublicHolidays.profileNameOf(profile, l10n),
            identifier: SemanticsIds.calendarHolidayProfileItem(profile.name),
          ),
      ],
      selected: _holidayProfile,
      menuWidth: FormMetrics.menuWidth,
    );
    if (next == null || !mounted || next == _holidayProfile) return;
    _onHapticFeedback();
    // Optimistic UI update — the service mutation is
    // transactional so a failure leaves the cache in a
    // consistent state and we can resync from it.
    setState(() => _holidayProfile = next);
    try {
      await _holidayService?.setProfile(next);
    } catch (e) {
      debugPrint('[CalendarSettings] holiday profile switch failed: $e');
      if (!mounted) return;
      setState(() => _holidayProfile = _holidayService?.profile ?? next);
      CustomSnackbar.showError(context, l10n.holidayProfileSwitchFailed);
    }
  }

  /// One row into [CalendarAppearancePage], structurally the categories row.
  ///
  /// The fifteen appearance rows moved to a route of their own so the live
  /// preview could be pinned above them instead of scrolling away with the
  /// section's `intro:` — but settings search still runs over *this* page, so
  /// every moved row's title is declared as a keyword here. Without them,
  /// typing "day rail" or "today style" in Calendar Settings would find
  /// nothing at all.
  SettingsEntry _appearanceEntry(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsEntry(
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
      identifier: SemanticsIds.calendarAppearanceOpen,
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
          identifier: SemanticsIds.calendarShowFilterChips,
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

  SettingsEntry _categoriesEntry(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsEntry(
      title: l10n.calendarCategories,
      description: l10n.calendarCategoriesDesc,
      identifier: SemanticsIds.calendarCategoriesOpen,
      builder: (context, title, description) => ListTile(
        leading: Icon(Icons.category_rounded, color: colorScheme.primary),
        title: title,
        subtitle: description,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => AppNavigator.toCalendarCategories(context),
      ),
    );
  }

  /// The one row left where the fasting section was (D6): every fasting
  /// option moved to [FastingSettingsPage], and the row reads the traditions
  /// on back.
  SettingsEntry _fastingEntry(ColorScheme colorScheme, AppLocalizations l10n) {
    return SettingsEntry(
      title: l10n.fastingSettingsTitle,
      description: FastingSettingsPage.summary(
        l10n,
        traditions: _fastingTraditions,
      ),
      // The moved rows' own words, so this page's search still finds the
      // way to them.
      keywords: [
        l10n.fastingSectionTitle,
        for (final tradition in FastingTradition.values)
          FastingCalendar.traditionNameOf(tradition, l10n),
        l10n.fastingLookRow,
        l10n.fastingOrthodoxGreatFasts,
        l10n.fastingPracticeRow,
        l10n.fastingWeekdayDaysTitle,
        l10n.fastingMonthsTitle,
        l10n.fastingExceptionsSkipTitle,
      ],
      identifier: SemanticsIds.calendarSettingsFastingOpen,
      builder: (context, title, description) => ListTile(
        leading: Icon(
          Icons.restaurant_menu_rounded,
          color: colorScheme.primary,
        ),
        title: title,
        subtitle: description,
        trailing: const Icon(Icons.chevron_right_rounded),
        // The value line is this page's copy of the traditions, so it is
        // read back when the fasting page pops, as the alerts row reads
        // its page's writes back.
        onTap: () async {
          _onHapticFeedback();
          await AppNavigator.toFastingSettings(context);
          if (mounted) await _loadSettings();
        },
      ),
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
          identifier: SemanticsIds.calendarEventTemplatesOpen,
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
          identifier: SemanticsIds.calendarDescriptionLimit,
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
          identifier: SemanticsIds.calendarDeleteAllEvents,
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

  /// The one row left where the alerts section was (D5): every alert option
  /// moved to [AlertSettingsPage], and the row reads the two defaults back so
  /// the page still answers "what does a new event start with" at a glance.
  SettingsEntry _alertsEntry(
    BuildContext context,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsEntry(
      title: l10n.alertSettingsTitle,
      description: AlertSettingsPage.defaultsSummary(
        context,
        timed: _timedAlertDefault,
        allDay: _allDayAlertDefault,
      ),
      keywords: [
        l10n.alertsDefaultTimed,
        l10n.alertsDefaultAllDay,
        l10n.alertsSound,
        l10n.alertsSnoozeLength,
        l10n.alertsNoticeLead,
        l10n.alertsSilenceAfter,
        // The permissions row's own words, as its entry here listed them
        // before it moved, so this page's search still finds the way.
        l10n.permissionsTitle,
        l10n.alertsNotifications,
        l10n.permissionExactAlarms,
        l10n.alertsFullScreenAlarms,
        l10n.alertsBattery,
        l10n.alertsTestAlarm,
      ],
      identifier: SemanticsIds.calendarSettingsAlertsOpen,
      builder: (context, title, description) => ListTile(
        leading: Icon(Icons.alarm_rounded, color: colorScheme.primary),
        title: title,
        subtitle: description,
        trailing: const Icon(Icons.chevron_right_rounded),
        // The value line is this page's copy of the two defaults, so it
        // is read back when the alert page pops, as the appearance row
        // reads its page's writes back.
        onTap: () async {
          _onHapticFeedback();
          await AppNavigator.toAlertSettings(context);
          if (mounted) await _loadSettings();
        },
      ),
    );
  }

  /// The row into [CalendarReportSettingsPage] (W). Its value line is the
  /// page's description rather than a summary of the cards: nothing on this
  /// page reads the report's setting, so nothing here goes stale.
  SettingsEntry _reportEntry(ColorScheme colorScheme, AppLocalizations l10n) {
    return SettingsEntry(
      title: l10n.calendarSettingsReportTitle,
      description: l10n.calendarSettingsReportDescription,
      // The cards' own names, so this page's search finds the way to them.
      keywords: [
        for (final kind in ReportCardKind.values)
          CalendarReportSettingsPage.cardName(kind, l10n),
      ],
      identifier: SemanticsIds.calendarSettingsReportOpen,
      builder: (context, title, description) => ListTile(
        leading: Icon(Icons.bar_chart_rounded, color: colorScheme.primary),
        title: title,
        subtitle: description,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          _onHapticFeedback();
          AppNavigator.toCalendarReportSettings(context);
        },
      ),
    );
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

    var failed = false;
    if (_eventService != null) {
      try {
        await _eventService!.tombstoneAll();
      } catch (e, st) {
        debugPrint('[CalendarSettings] delete all failed: $e\n$st');
        failed = true;
      } finally {
        // No bloc drove this wipe, so nothing has emitted: a `CalendarBloc`
        // loaded before the trip here keeps serving the wiped events, and
        // saving one of them hits the DAO's update branch and resurrects it.
        // The external change is the one way a page below the bloc says the
        // store moved — told after a failure too, which may come once the
        // transaction committed; a reload over an untouched store is
        // harmless. Un-flagged on purpose: a re-read failing after the wipe
        // leaves the service's cache as it was before it (`lastLoadFailed`),
        // and only the bloc's own read replaces it.
        CalendarEventService.notifyExternalChange();
      }
    }
    if (!mounted) return;
    // Another account's events survive the wipe, so the count is re-read —
    // after a failure too, which may come once the transaction committed.
    setState(() => _eventCount = _eventService?.events.length ?? 0);
    if (failed) {
      CustomSnackbar.showError(context, l10n.deleteAllEventsFailed);
    } else {
      CustomSnackbar.showSuccess(context, l10n.allEventsDeleted);
    }
  }
}
