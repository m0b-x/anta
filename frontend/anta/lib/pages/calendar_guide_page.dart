import 'package:flutter/material.dart';

import '../constants/semantics_ids.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../utils/settings_search.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/unified_app_bars.dart';

/// A paragraph someone reads rather than a caption under a control: the
/// kit's 12 px description is too small for that, and running text needs
/// more line spacing than a one-line row.
const TextStyle _paragraphStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w400,
  height: 1.4,
);

/// How the calendar works, for someone who has never used a calendar app.
///
/// Reached from the calendar's ⋮ beside Calendar settings, and like that page
/// it is a page of sections, so it speaks the settings kit: the search field,
/// the cards and the chrome come for free. Every label the text names is the
/// app's own string passed through a placeholder, so the guide cannot drift
/// from the screens it describes in any language. It reads nothing and writes
/// nothing.
class CalendarGuidePage extends StatefulWidget {
  const CalendarGuidePage({super.key});

  @override
  State<CalendarGuidePage> createState() => _CalendarGuidePageState();
}

class _CalendarGuidePageState extends State<CalendarGuidePage> {
  final TextEditingController _searchController = TextEditingController();
  SettingsQuery _query = SettingsQuery.empty;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: SettingsAppBar(
        title: l10n.calendarGuideTitle,
        showMenuButton: false,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: SettingsSearchField(
                controller: _searchController,
                hint: l10n.calendarGuideSearchHint,
                onChanged: (value) =>
                    setState(() => _query = SettingsQuery.parse(value)),
              ),
            ),
            Expanded(
              child: Semantics(
                container: true,
                identifier: SemanticsIds.calendarGuide,
                child: SettingsSectionList(
                  query: _query,
                  sections: _buildSections(l10n),
                  header: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        l10n.calendarGuideIntro(l10n.calendarGuideTitle),
                        style: _paragraphStyle.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<SettingsSectionData> _buildSections(AppLocalizations l10n) {
    final snooze = l10n.alarmSnoozeMinutes(
      SettingsKeys.defaultAlertSnoozeMinutes,
    );
    return [
      SettingsSectionData(
        icon: Icons.calendar_month_rounded,
        title: l10n.calendarGuideSectionCalendar,
        entries: [
          _entry(
            'month',
            Icons.today_rounded,
            l10n.calendarGuideMonthTitle,
            l10n.calendarGuideMonthBody,
          ),
          _entry(
            'marks',
            Icons.color_lens_outlined,
            l10n.calendarGuideMarksTitle,
            l10n.calendarGuideMarksBody,
          ),
          _entry(
            'panel',
            Icons.view_day_outlined,
            l10n.calendarGuidePanelTitle,
            l10n.calendarGuidePanelBody(
              l10n.panelModeDay,
              l10n.panelModeTimeline,
              l10n.upcomingEvents,
            ),
          ),
          _entry(
            'views',
            Icons.view_week_outlined,
            l10n.calendarGuideViewsTitle,
            l10n.calendarGuideViewsBody(
              l10n.calendar,
              l10n.calendarOverview,
              l10n.calendarFormatMonth,
            ),
          ),
        ],
      ),
      SettingsSectionData(
        icon: Icons.event_rounded,
        title: l10n.calendarGuideSectionEvents,
        entries: [
          _entry(
            'add-event',
            Icons.add_circle_outline_rounded,
            l10n.calendarGuideAddTitle,
            l10n.calendarGuideAddBody(l10n.save),
          ),
          _entry(
            'time',
            Icons.schedule_outlined,
            l10n.calendarGuideTimeTitle,
            l10n.calendarGuideTimeBody(
              l10n.eventAllDay,
              l10n.eventStarts,
              l10n.eventEnds,
            ),
          ),
          _entry(
            'category',
            Icons.label_outlined,
            l10n.calendarGuideCategoryTitle,
            l10n.calendarGuideCategoryBody(l10n.eventCategory),
          ),
          _entry(
            'repeat',
            Icons.repeat_rounded,
            l10n.calendarGuideRepeatTitle,
            l10n.calendarGuideRepeatBody(
              l10n.eventRepeat,
              l10n.eventDescriptionDone,
            ),
          ),
          _entry(
            'open',
            Icons.edit_outlined,
            l10n.calendarGuideOpenTitle,
            l10n.calendarGuideOpenBody(
              l10n.edit,
              l10n.deleteEvent,
              l10n.eventSkipOccurrence,
            ),
          ),
          _entry(
            'description',
            Icons.notes_rounded,
            l10n.calendarGuideDescriptionTitle,
            l10n.calendarGuideDescriptionBody,
          ),
          _entry(
            'unsaved',
            Icons.save_outlined,
            l10n.calendarGuideUnsavedTitle(l10n.save),
            l10n.calendarGuideUnsavedBody,
          ),
          _entry(
            'attendance',
            Icons.how_to_reg_outlined,
            l10n.calendarGuideTrackTitle,
            l10n.calendarGuideTrackBody(
              l10n.eventTrackPresence,
              l10n.eventPresencePresent,
              l10n.eventPresenceMissed,
            ),
          ),
          _entry(
            'templates',
            Icons.bookmark_border_rounded,
            l10n.calendarGuideTemplatesTitle,
            l10n.calendarGuideTemplatesBody(l10n.saveAsTemplate),
          ),
        ],
      ),
      SettingsSectionData(
        icon: Icons.notifications_active_rounded,
        title: l10n.calendarGuideSectionAlerts,
        entries: [
          _entry(
            'add-alert',
            Icons.add_alert_outlined,
            l10n.calendarGuideAlertAddTitle,
            l10n.calendarGuideAlertAddBody(
              l10n.eventAlerts,
              l10n.eventAlertAdd,
              l10n.eventDescriptionDone,
              l10n.save,
            ),
          ),
          _entry(
            'alert-kinds',
            Icons.alarm_rounded,
            l10n.calendarGuideAlertKindsTitle,
            l10n.calendarGuideAlertKindsBody(
              l10n.eventAlertModeNotify,
              l10n.eventAlertModeRing,
              l10n.eventAllDay,
            ),
          ),
          _entry(
            'permissions',
            Icons.verified_user_outlined,
            l10n.calendarGuidePermissionsTitle,
            l10n.calendarGuidePermissionsBody(l10n.permissionsTitle),
          ),
          _entry(
            'ring',
            Icons.notifications_rounded,
            l10n.calendarGuideRingTitle,
            l10n.calendarGuideRingBody(
              l10n.alertsDoneAction,
              snooze,
              l10n.alarmStop,
            ),
          ),
          _entry(
            'open-often',
            Icons.update_rounded,
            l10n.calendarGuideOpenOftenTitle,
            l10n.calendarGuideOpenOftenBody,
          ),
          _entry(
            'quick-alarm',
            Icons.alarm_add_rounded,
            l10n.calendarGuideQuickAlarmTitle,
            l10n.calendarGuideQuickAlarmBody(l10n.quickAlarmRow),
          ),
          _entry(
            'hub',
            Icons.list_alt_rounded,
            l10n.calendarGuideHubTitle,
            l10n.calendarGuideHubBody(l10n.alertsTitle),
          ),
        ],
      ),
      SettingsSectionData(
        icon: Icons.search_rounded,
        title: l10n.calendarGuideSectionFinding,
        entries: [
          _entry(
            'search',
            Icons.search_rounded,
            l10n.calendarGuideSearchTitle,
            l10n.calendarGuideSearchBody(l10n.upcomingEvents),
          ),
          _entry(
            'overview',
            Icons.grid_view_rounded,
            l10n.calendarGuideOverviewTitle,
            l10n.calendarGuideOverviewBody(
              l10n.calendarOverview,
              l10n.dayListModeYear,
              l10n.dayListModeList,
            ),
          ),
          _entry(
            'filters',
            Icons.filter_alt_outlined,
            l10n.calendarGuideFiltersTitle,
            l10n.calendarGuideFiltersBody(l10n.calendarFilterReset, l10n.apply),
          ),
        ],
      ),
      SettingsSectionData(
        icon: Icons.tune_rounded,
        title: l10n.calendarGuideSectionSettings,
        entries: [
          _entry(
            'settings',
            Icons.settings_outlined,
            l10n.calendarGuideSettingsTitle,
            l10n.calendarGuideSettingsBody(l10n.calendarSettingsRow, l10n.save),
          ),
          _entry(
            'holidays',
            Icons.public_rounded,
            l10n.calendarGuideHolidaysTitle,
            l10n.calendarGuideHolidaysBody(
              l10n.calendarSettingsRow,
              l10n.holidayProfileTitle,
            ),
          ),
          _entry(
            'week-start',
            Icons.date_range_rounded,
            l10n.calendarGuideWeekStartTitle,
            l10n.calendarGuideWeekStartBody(
              l10n.calendarSettingsRow,
              l10n.calendarAppearanceSection,
              l10n.calendarWeekStartTitle,
            ),
          ),
          _entry(
            'categories',
            Icons.category_rounded,
            l10n.calendarGuideCategoriesTitle,
            l10n.calendarGuideCategoriesBody(
              l10n.calendarSettingsRow,
              l10n.calendarCategories,
            ),
          ),
          _entry(
            'language',
            Icons.translate_rounded,
            l10n.calendarGuideLanguageTitle,
            l10n.calendarGuideLanguageBody(
              l10n.languageSettings,
              l10n.themeSettings,
            ),
          ),
        ],
      ),
      SettingsSectionData(
        icon: Icons.info_outline_rounded,
        title: l10n.calendarGuideSectionGood,
        entries: [
          _entry(
            'opening',
            Icons.menu_rounded,
            l10n.calendarGuideOpeningTitle,
            l10n.calendarGuideOpeningBody(l10n.calendar),
          ),
          _entry(
            'back',
            Icons.arrow_back_rounded,
            l10n.calendarGuideBackTitle,
            l10n.calendarGuideBackBody,
          ),
          _entry(
            'notes',
            Icons.folder_outlined,
            l10n.calendarGuideNotesTitle,
            l10n.calendarGuideNotesBody(l10n.eventLinkedNote),
          ),
        ],
      ),
    ];
  }

  /// [slug] is frozen: a device flow targets the row by it, whatever the
  /// wording or the locale.
  SettingsEntry _entry(
    String slug,
    IconData icon,
    String title,
    String description,
  ) {
    return SettingsEntry(
      title: title,
      description: description,
      identifier: SemanticsIds.calendarGuideRow(slug),
      descriptionStyle: _paragraphStyle,
      builder: (context, title, description) =>
          _GuideRow(icon: icon, title: title, description: description),
    );
  }
}

/// A guide row is read, never pressed: no ink, no tap, no chevron. Its title
/// and paragraph merge so TalkBack reads the row as one stop.
class _GuideRow extends StatelessWidget {
  const _GuideRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Widget title;
  final Widget? description;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icon, color: colorScheme.primary)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  if (description != null) ...[
                    const SizedBox(height: 4),
                    description!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
