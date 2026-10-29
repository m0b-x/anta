import 'package:flutter/material.dart';

import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';

/// One read row of the calendar guide.
///
/// [slug] is frozen: a device flow targets the row by it
/// (`SemanticsIds.calendarGuideRow`), whatever the wording or the locale.
@immutable
class CalendarGuideRow {
  final String slug;
  final IconData icon;
  final String title;
  final String body;

  const CalendarGuideRow(this.slug, this.icon, this.title, this.body);
}

/// The practice calendar's glyph, and the one mark of "tap here, nothing is
/// saved" wherever the guide says it (D35): the hub row and the practice
/// page's band.
const IconData calendarGuidePracticeIcon = Icons.touch_app_rounded;

/// The practice calendar's slug, frozen like a page's: its hub row's id is
/// built on it.
const String calendarGuidePracticeSlug = 'practice';

/// The guide's pages, in the hub's order.
///
/// The one catalogue of what the guide says: the hub lists the pages and
/// searches every page's rows, and a page shows its own, so a row is written
/// once and found from both. Every label a row names is the app's own string
/// passed through a placeholder, so the guide cannot drift from the screens
/// it describes in any language.
enum CalendarGuideTopic {
  screen('screen', Icons.calendar_month_rounded),
  events('events', Icons.event_rounded),
  kinds('kinds', Icons.event_repeat_rounded),
  alerts('alerts', Icons.notifications_active_rounded),
  attendance('attendance', Icons.how_to_reg_rounded),
  categories('categories', Icons.category_rounded),
  finding('finding', Icons.search_rounded),
  setup('setup', Icons.tune_rounded),
  good('good', Icons.info_outline_rounded);

  /// Frozen like a row's: the hub row's and the page's ids are built on it.
  final String slug;
  final IconData icon;

  const CalendarGuideTopic(this.slug, this.icon);

  String title(AppLocalizations l10n) => switch (this) {
    screen => l10n.calendarGuideSectionCalendar,
    events => l10n.calendarGuidePageEvents,
    kinds => l10n.calendarGuidePageKinds,
    alerts => l10n.calendarGuidePageAlerts,
    attendance => l10n.calendarGuidePageAttendance,
    categories => l10n.calendarGuidePageCategories,
    finding => l10n.calendarGuidePageFinding,
    setup => l10n.calendarGuidePageSetup,
    good => l10n.calendarGuideSectionGood,
  };

  String caption(AppLocalizations l10n) => switch (this) {
    screen => l10n.calendarGuidePageScreenCaption,
    events => l10n.calendarGuidePageEventsCaption,
    kinds => l10n.calendarGuidePageKindsCaption,
    alerts => l10n.calendarGuidePageAlertsCaption,
    attendance => l10n.calendarGuidePageAttendanceCaption(
      l10n.eventPresencePresent,
      l10n.eventPresenceMissed,
      l10n.eventShowInDayRail,
    ),
    categories => l10n.calendarGuidePageCategoriesCaption,
    finding => l10n.calendarGuidePageFindingCaption(l10n.calendarOverview),
    setup => l10n.calendarGuidePageSetupCaption,
    good => l10n.calendarGuidePageGoodCaption,
  };

  /// The one line under the page's heading; Good to know is a list of loose
  /// ends and has none.
  String? lead(AppLocalizations l10n) => switch (this) {
    screen => l10n.calendarGuideScreenLead,
    events => l10n.calendarGuideEventsLead,
    kinds => l10n.calendarGuideKindsLead,
    alerts => l10n.calendarGuideAlertsLead,
    attendance => l10n.calendarGuideAttendanceLead,
    categories => l10n.calendarGuideCategoriesLead,
    finding => l10n.calendarGuideFindingLead,
    setup => l10n.calendarGuideSetupLead,
    good => null,
  };

  /// The lead-in of the page's "Try it" card, which is also the card's one
  /// searchable line. Good to know has nothing to try.
  String? tryLead(AppLocalizations l10n) => switch (this) {
    screen => l10n.calendarGuideTryScreen,
    events => l10n.calendarGuideTryEvents,
    kinds => l10n.calendarGuideTryKinds,
    alerts => l10n.calendarGuideTryAlerts,
    attendance => l10n.calendarGuideTryAttendance(
      l10n.eventPresencePresent,
      l10n.eventPresenceMissed,
    ),
    categories => l10n.calendarGuideTryCategories,
    finding => l10n.calendarGuideTryFinding,
    setup => l10n.calendarGuideTrySetup,
    good => null,
  };

  /// The page's read rows, in page order.
  List<CalendarGuideRow> rows(AppLocalizations l10n) => switch (this) {
    screen => [
      CalendarGuideRow(
        'month',
        Icons.today_rounded,
        l10n.calendarGuideMonthTitle,
        l10n.calendarGuideMonthBody,
      ),
      CalendarGuideRow(
        'marks',
        Icons.color_lens_outlined,
        l10n.calendarGuideMarksTitle,
        l10n.calendarGuideMarksBody,
      ),
      CalendarGuideRow(
        'panel',
        Icons.view_day_outlined,
        l10n.calendarGuidePanelTitle,
        l10n.calendarGuidePanelBody(
          l10n.panelModeDay,
          l10n.panelModeTimeline,
          l10n.upcomingEvents,
        ),
      ),
      CalendarGuideRow(
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
    events => [
      CalendarGuideRow(
        'add-event',
        Icons.add_circle_outline_rounded,
        l10n.calendarGuideAddTitle,
        l10n.calendarGuideAddBody(l10n.save),
      ),
      CalendarGuideRow(
        'time',
        Icons.schedule_outlined,
        l10n.calendarGuideTimeTitle,
        l10n.calendarGuideTimeBody(
          l10n.eventAllDay,
          l10n.eventStarts,
          l10n.eventEnds,
        ),
      ),
      CalendarGuideRow(
        'open',
        Icons.edit_outlined,
        l10n.calendarGuideOpenTitle,
        l10n.calendarGuideOpenBody(
          l10n.edit,
          l10n.deleteEvent,
          l10n.eventSkipOccurrence,
        ),
      ),
      CalendarGuideRow(
        'description',
        Icons.notes_rounded,
        l10n.calendarGuideDescriptionTitle,
        l10n.calendarGuideDescriptionBody,
      ),
      CalendarGuideRow(
        'priority',
        Icons.flag_outlined,
        l10n.calendarGuidePriorityTitle(l10n.eventPriority),
        l10n.calendarGuidePriorityBody(
          l10n.eventPriority,
          l10n.eventAppearance,
        ),
      ),
      CalendarGuideRow(
        'unsaved',
        Icons.save_outlined,
        l10n.calendarGuideUnsavedTitle(l10n.save),
        l10n.calendarGuideUnsavedBody,
      ),
      CalendarGuideRow(
        'templates',
        Icons.bookmark_border_rounded,
        l10n.calendarGuideTemplatesTitle,
        l10n.calendarGuideTemplatesBody(l10n.saveAsTemplate),
      ),
    ],
    kinds => [
      CalendarGuideRow(
        'repeat',
        Icons.repeat_rounded,
        l10n.calendarGuideRepeatTitle,
        l10n.calendarGuideRepeatBody(
          l10n.eventRepeat,
          l10n.eventDescriptionDone,
        ),
      ),
      CalendarGuideRow(
        'kinds-one',
        Icons.looks_one_outlined,
        l10n.calendarGuideKindsOneTitle,
        l10n.calendarGuideKindsOneBody(
          l10n.eventRepeat,
          l10n.recurrenceDoesNotRepeat,
        ),
      ),
      CalendarGuideRow(
        'kinds-dates',
        Icons.event_repeat_outlined,
        l10n.calendarGuideKindsDatesTitle,
        l10n.calendarGuideKindsDatesBody(
          l10n.eventAddDate,
          l10n.eventRepeat,
          l10n.recurrenceSpecificDates(3),
          l10n.eventDatesLabel,
          l10n.eventSkipOccurrence,
        ),
      ),
      CalendarGuideRow(
        'kinds-only-one',
        Icons.filter_1_outlined,
        l10n.calendarGuideKindsOnlyOneTitle,
        l10n.calendarGuideKindsOnlyOneBody(
          l10n.eventAlertRemoveAfter,
          l10n.alertsSkipAction,
        ),
      ),
      CalendarGuideRow(
        'kinds-only-repeat',
        Icons.all_inclusive_rounded,
        l10n.calendarGuideKindsOnlyRepeatTitle,
        l10n.calendarGuideKindsOnlyRepeatBody(
          l10n.eventTrackPresence,
          l10n.eventCountOccurrences,
          l10n.eventSkipOccurrence,
          l10n.eventSkippedDays,
        ),
      ),
      CalendarGuideRow(
        'kinds-one-change',
        Icons.sync_alt_rounded,
        l10n.calendarGuideKindsOneChangeTitle,
        l10n.calendarGuideKindsOneChangeBody,
      ),
      CalendarGuideRow(
        'kinds-tricky',
        Icons.warning_amber_rounded,
        l10n.calendarGuideKindsTrickyTitle,
        l10n.calendarGuideKindsTrickyBody(
          l10n.recurrenceEnds,
          l10n.eventRepeat,
          l10n.recurrenceBeforeStart,
        ),
      ),
      CalendarGuideRow(
        'kinds-birthday',
        Icons.cake_outlined,
        l10n.calendarGuideKindsBirthdayTitle,
        l10n.calendarGuideKindsBirthdayBody(l10n.eventCategoryBirthday),
      ),
      CalendarGuideRow(
        'skipped',
        Icons.event_busy_rounded,
        l10n.calendarGuideSkippedTitle,
        l10n.calendarGuideSkippedBody(
          l10n.eventSkipOccurrence,
          l10n.eventSkippedDays,
        ),
      ),
    ],
    alerts => [
      CalendarGuideRow(
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
      CalendarGuideRow(
        'alert-kinds',
        Icons.alarm_rounded,
        l10n.calendarGuideAlertKindsTitle,
        l10n.calendarGuideAlertKindsBody(
          l10n.eventAlertModeNotify,
          l10n.eventAlertModeRing,
          l10n.eventAllDay,
        ),
      ),
      CalendarGuideRow(
        'permissions',
        Icons.verified_user_outlined,
        l10n.calendarGuidePermissionsTitle,
        l10n.calendarGuidePermissionsBody(
          l10n.alertsBattery,
          l10n.permissionsTitle,
        ),
      ),
      CalendarGuideRow(
        'ring',
        Icons.notifications_rounded,
        l10n.calendarGuideRingTitle,
        l10n.calendarGuideRingBody(
          l10n.alertsDoneAction,
          l10n.alarmSnoozeMinutes(SettingsKeys.defaultAlertSnoozeMinutes),
          l10n.alarmStop,
        ),
      ),
      CalendarGuideRow(
        'open-often',
        Icons.update_rounded,
        l10n.calendarGuideOpenOftenTitle,
        l10n.calendarGuideOpenOftenBody,
      ),
      CalendarGuideRow(
        'quick-alarm',
        Icons.alarm_add_rounded,
        l10n.calendarGuideQuickAlarmTitle,
        l10n.calendarGuideQuickAlarmBody(l10n.quickAlarmRow),
      ),
      CalendarGuideRow(
        'hub',
        Icons.list_alt_rounded,
        l10n.calendarGuideHubTitle,
        l10n.calendarGuideHubBody(l10n.alertsTitle),
      ),
    ],
    attendance => [
      CalendarGuideRow(
        'attendance',
        Icons.how_to_reg_outlined,
        l10n.calendarGuideTrackTitle,
        l10n.calendarGuideTrackBody(
          l10n.eventTrackPresence,
          l10n.eventPresencePresent,
          l10n.eventPresenceMissed,
        ),
      ),
      CalendarGuideRow(
        'assume',
        Icons.event_busy_outlined,
        l10n.calendarGuideAssumeTitle,
        l10n.calendarGuideAssumeBody(
          l10n.eventTrackPresence,
          l10n.eventPresencePresent,
          l10n.eventPresenceMissed,
          l10n.eventAssumeAbsent,
        ),
      ),
      CalendarGuideRow(
        'count',
        Icons.tag_rounded,
        l10n.calendarGuideCountTitle,
        l10n.calendarGuideCountBody(
          l10n.eventCountOccurrences,
          l10n.eventCountStyleNumbered,
          l10n.eventCountStyleElapsed,
          l10n.eventNumberedDays(1),
          l10n.eventNumberedDays(2),
          l10n.eventNumberedWeeks(3),
          l10n.eventElapsedYears(1),
          l10n.eventElapsedYears(2),
        ),
      ),
      CalendarGuideRow(
        'rail',
        Icons.vertical_split_rounded,
        l10n.calendarGuideRailTitle(l10n.eventShowInDayRail),
        l10n.calendarGuideRailBody(
          l10n.eventShowInDayRail,
          l10n.calendarSettingsRow,
          l10n.calendarAppearanceSection,
          l10n.eventShowInDayRailAuto,
          l10n.eventShowInDayRailAlways,
          l10n.eventShowInDayRailNever,
        ),
      ),
      CalendarGuideRow(
        'per-day',
        Icons.edit_calendar_outlined,
        l10n.calendarGuidePerDayTitle,
        l10n.calendarGuidePerDayBody(
          l10n.eventPerOccurrenceDescriptions,
          l10n.eventDescriptionScopeThisDay,
          l10n.eventDescriptionScopeAllDays,
        ),
      ),
    ],
    categories => [
      CalendarGuideRow(
        'category',
        Icons.label_outlined,
        l10n.calendarGuideCategoryTitle,
        l10n.calendarGuideCategoryBody(l10n.eventCategory),
      ),
      CalendarGuideRow(
        'cat-create',
        Icons.add_circle_outline_rounded,
        l10n.calendarGuideCatCreateTitle,
        l10n.calendarGuideCatCreateBody(
          l10n.calendarSettingsRow,
          l10n.calendarCategories,
          l10n.createCategory,
          l10n.save,
        ),
      ),
      CalendarGuideRow(
        'cat-change',
        Icons.edit_outlined,
        l10n.calendarGuideCatChangeTitle,
        l10n.calendarGuideCatChangeBody,
      ),
      CalendarGuideRow(
        'cat-hide',
        Icons.visibility_off_outlined,
        l10n.calendarGuideCatHideTitle,
        l10n.calendarGuideCatHideBody(l10n.hide, l10n.show),
      ),
      CalendarGuideRow(
        'cat-delete',
        Icons.delete_outline_rounded,
        l10n.calendarGuideCatDeleteTitle,
        l10n.calendarGuideCatDeleteBody(l10n.delete, l10n.eventCategoryOther),
      ),
      CalendarGuideRow(
        'cat-alerts',
        Icons.notifications_none_rounded,
        l10n.calendarGuideCatAlertsTitle,
        l10n.calendarGuideCatAlertsBody(
          l10n.eventAlertAdd,
          l10n.eventCategoryAlerts,
        ),
      ),
    ],
    finding => [
      CalendarGuideRow(
        'search',
        Icons.search_rounded,
        l10n.calendarGuideSearchTitle,
        l10n.calendarGuideSearchBody(l10n.upcomingEvents),
      ),
      CalendarGuideRow(
        'filters',
        Icons.filter_alt_outlined,
        l10n.calendarGuideFiltersTitle,
        l10n.calendarGuideFiltersBody(l10n.calendarFilterReset, l10n.apply),
      ),
      CalendarGuideRow(
        'overview',
        Icons.grid_view_rounded,
        l10n.calendarGuideOverviewTitle,
        l10n.calendarGuideOverviewBody(
          l10n.calendarOverview,
          l10n.dayListModeYear,
          l10n.dayListModeList,
        ),
      ),
    ],
    setup => [
      CalendarGuideRow(
        'settings',
        Icons.settings_outlined,
        l10n.calendarGuideSettingsTitle,
        l10n.calendarGuideSettingsBody(l10n.calendarSettingsRow, l10n.save),
      ),
      CalendarGuideRow(
        'holidays',
        Icons.public_rounded,
        l10n.calendarGuideHolidaysTitle,
        l10n.calendarGuideHolidaysBody(
          l10n.calendarSettingsRow,
          l10n.holidayProfileTitle,
        ),
      ),
      CalendarGuideRow(
        'week-start',
        Icons.date_range_rounded,
        l10n.calendarGuideWeekStartTitle,
        l10n.calendarGuideWeekStartBody(
          l10n.calendarSettingsRow,
          l10n.calendarAppearanceSection,
          l10n.calendarWeekStartTitle,
        ),
      ),
      CalendarGuideRow(
        'language',
        Icons.translate_rounded,
        l10n.calendarGuideLanguageTitle,
        l10n.calendarGuideLanguageBody(
          l10n.languageSettings,
          l10n.themeSettings,
        ),
      ),
    ],
    good => [
      CalendarGuideRow(
        'opening',
        Icons.menu_rounded,
        l10n.calendarGuideOpeningTitle,
        l10n.calendarGuideOpeningBody(l10n.calendar, l10n.calendarGuideTitle),
      ),
      CalendarGuideRow(
        'back',
        Icons.arrow_back_rounded,
        l10n.calendarGuideBackTitle,
        l10n.calendarGuideBackBody,
      ),
      CalendarGuideRow(
        'notes',
        Icons.folder_outlined,
        l10n.calendarGuideNotesTitle,
        l10n.calendarGuideNotesBody(l10n.eventLinkedNote),
      ),
    ],
  };
}
