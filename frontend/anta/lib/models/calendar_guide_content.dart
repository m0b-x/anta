import 'package:flutter/material.dart';

import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import 'calendar_guide_coach.dart';

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

/// The practice calendar's tour (D42), in the order its band asks for each
/// tap; the band ends on [calendarGuideTourDone]. Beside the slug, as a
/// page's steps sit on its topic.
final List<GuideCoachStep> calendarGuideTourSteps = List.unmodifiable([
  GuideCoachStep('picked', (l10n) => l10n.calendarGuideTourPick),
  GuideCoachStep('opened', (l10n) => l10n.calendarGuideTourOpen),
  GuideCoachStep(
    'changed',
    (l10n) => l10n.calendarGuideTourEdit(l10n.edit, l10n.save),
  ),
  GuideCoachStep('added', (l10n) => l10n.calendarGuideTourAdd),
  GuideCoachStep('filtered', (l10n) => l10n.calendarGuideTourFilter(l10n.apply)),
]);

/// The tour's closing line, for its coach's `closing`.
String calendarGuideTourDone(AppLocalizations l10n) =>
    l10n.calendarGuideTourDone;

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

  /// The coach steps of the page's "Try it" card, in the order she is asked
  /// for them; empty for Good to know, which has nothing to try. Here rather
  /// than in the demo so the hub's search and the card's coach read one
  /// source. A getter, not a call per language: the demo's coach is built
  /// before the page has a language and outlives a change of it, so each
  /// line is written when it is drawn.
  List<GuideCoachStep> get steps => switch (this) {
    screen => [
      GuideCoachStep(
        'title',
        (l10n) => l10n.calendarGuideCoachScreenTitle(l10n.calendar),
      ),
      GuideCoachStep('more', (l10n) => l10n.calendarGuideCoachScreenMore),
      GuideCoachStep(
        'panel',
        (l10n) => l10n.calendarGuideCoachScreenPanel(
          l10n.panelModeDay,
          l10n.panelModeTimeline,
          l10n.upcomingEvents,
        ),
      ),
    ],
    events => [
      GuideCoachStep(
        'added',
        (l10n) => l10n.calendarGuideCoachEventsAdd(l10n.save),
      ),
      GuideCoachStep('opened', (l10n) => l10n.calendarGuideCoachEventsOpen),
      GuideCoachStep(
        'changed',
        (l10n) => l10n.calendarGuideCoachEventsChange(l10n.edit, l10n.save),
      ),
      GuideCoachStep(
        'deleted',
        (l10n) =>
            l10n.calendarGuideCoachEventsDelete(l10n.edit, l10n.deleteEvent),
      ),
    ],
    kinds => [
      GuideCoachStep(
        'repeat',
        (l10n) => l10n.calendarGuideCoachKindsRepeat(
          l10n.eventRepeat,
          l10n.recurrenceWeekly,
          l10n.eventDescriptionDone,
        ),
      ),
      GuideCoachStep(
        'skipped',
        (l10n) => l10n.calendarGuideCoachKindsSkip(
          l10n.eventDateLabel,
          l10n.eventSkipOccurrence,
        ),
      ),
      GuideCoachStep(
        'once',
        (l10n) => l10n.calendarGuideCoachKindsOnce(
          l10n.eventRepeat,
          l10n.recurrenceDoesNotRepeat,
        ),
      ),
      GuideCoachStep(
        'addDate',
        (l10n) => l10n.calendarGuideCoachKindsAddDate(l10n.eventAddDate),
      ),
    ],
    alerts => [
      GuideCoachStep(
        'alert',
        (l10n) => l10n.calendarGuideCoachAlertsAdd(
          l10n.eventAlertAdd,
          l10n.eventDescriptionDone,
        ),
      ),
      GuideCoachStep(
        'alarm',
        (l10n) =>
            l10n.calendarGuideCoachAlertsShow(l10n.calendarGuideShowAlarm),
      ),
    ],
    attendance => [
      GuideCoachStep(
        'flipped',
        (l10n) => l10n.calendarGuideCoachAttendanceMark,
      ),
      GuideCoachStep(
        'counting',
        (l10n) =>
            l10n.calendarGuideCoachAttendanceCount(l10n.eventCountOccurrences),
      ),
    ],
    categories => [
      GuideCoachStep(
        'created',
        (l10n) => l10n.calendarGuideCoachCategoriesCreate(
          l10n.createCategory,
          l10n.save,
        ),
      ),
      GuideCoachStep('hidden', (l10n) => l10n.calendarGuideCoachCategoriesHide),
      GuideCoachStep(
        'deleted',
        (l10n) => l10n.calendarGuideCoachCategoriesDelete(
          l10n.delete,
          l10n.eventCategoryOther,
        ),
      ),
    ],
    finding => [
      GuideCoachStep('query', (l10n) => l10n.calendarGuideCoachFindingSearch),
      GuideCoachStep(
        'filtered',
        (l10n) => l10n.calendarGuideCoachFindingFilter(l10n.apply),
      ),
    ],
    setup => [
      GuideCoachStep(
        'holidays',
        (l10n) =>
            l10n.calendarGuideCoachSetupHolidays(l10n.holidayProfileTitle),
      ),
      GuideCoachStep(
        'week',
        (l10n) => l10n.calendarGuideCoachSetupWeek(l10n.calendarWeekStartTitle),
      ),
    ],
    good => const [],
  };

  /// The card's searchable line: its first instruction, which the card
  /// draws as the coach line until she acts (D48). Good to know has none.
  String? tryLead(AppLocalizations l10n) {
    final steps = this.steps;
    return steps.isEmpty ? null : steps.first.line(l10n);
  }

  /// The page's read rows, in page order.
  List<CalendarGuideRow> rows(AppLocalizations l10n) => switch (this) {
    screen => [
      CalendarGuideRow(
        'marks',
        Icons.color_lens_outlined,
        l10n.calendarGuideMarksTitle,
        l10n.calendarGuideMarksBody,
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
        ),
      ),
      CalendarGuideRow(
        'kinds-birthday',
        Icons.cake_outlined,
        l10n.calendarGuideKindsBirthdayTitle,
        l10n.calendarGuideKindsBirthdayBody(l10n.eventCategoryBirthday),
      ),
      CalendarGuideRow(
        'kinds-only-repeat',
        Icons.all_inclusive_rounded,
        l10n.calendarGuideKindsOnlyRepeatTitle,
        l10n.calendarGuideKindsOnlyRepeatBody(
          l10n.eventTrackPresence,
          l10n.eventCountOccurrences,
          l10n.eventSkippedDays,
        ),
      ),
    ],
    alerts => [
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
    ],
    attendance => [
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
        'cat-change',
        Icons.edit_outlined,
        l10n.calendarGuideCatChangeTitle,
        l10n.calendarGuideCatChangeBody,
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
