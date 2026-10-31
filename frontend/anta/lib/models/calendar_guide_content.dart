import 'package:flutter/material.dart';

import '../constants/report_metrics.dart';
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

/// One "Try it" card of a guide page (D58): its coach's steps and the title
/// of the section it sits in.
///
/// [slug] is frozen like a page's: the card's ids are built on it
/// (`SemanticsIds.calendarGuideTry` and its kin). A page with one card uses
/// the page's own slug, so a card's ids outlived the page growing more.
@immutable
class GuideCardSpec {
  const GuideCardSpec(this.slug, this.steps, this.title);

  final String slug;
  final List<GuideCoachStep> steps;
  final GuideLine title;

  /// The screen page's three (D58). The grid card kept the page's slug, so
  /// the ids it shipped with still find it.
  static const String screenGrid = 'screen';
  static const String screenPanel = 'panel';
  static const String screenOverview = 'overview';
}

/// The practice calendar's glyph, and the one mark of "tap here, nothing is
/// saved" wherever the guide says it (D35): the hub row and the practice
/// page's band.
const IconData calendarGuidePracticeIcon = Icons.touch_app_rounded;

/// The practice calendar's lessons (D53, D54): one page over two seeds and
/// two tours, so the screen they teach on is built once.
enum GuidePracticeLesson {
  events('practice'),
  filtering('practice-filtering');

  /// Frozen like a page's: the hub row's id is built on it. The events
  /// lesson keeps the practice calendar's slug from before there were two.
  final String slug;

  const GuidePracticeLesson(this.slug);

  /// Both lessons wear the practice glyph: each is the same calendar.
  IconData get icon => calendarGuidePracticeIcon;

  String title(AppLocalizations l10n) => switch (this) {
    events => l10n.calendarGuidePagePractice,
    filtering => l10n.calendarGuidePagePracticeFiltering,
  };

  String caption(AppLocalizations l10n) => switch (this) {
    events => l10n.calendarGuidePagePracticeCaption,
    filtering => l10n.calendarGuidePagePracticeFilteringCaption,
  };

  /// The band's tour (D42, D56), in the order it asks for each tap. A getter
  /// for [CalendarGuideTopic.cards]' reason: the coach is built before the
  /// page has a language.
  ///
  /// The filtering tour's first action is `funnel`, not `opened`: the page
  /// reports every action to whichever tour is running, and `opened` is
  /// already the events tour's word for an event's sheet.
  List<GuideCoachStep> get steps => switch (this) {
    events => [
      GuideCoachStep('picked', (l10n) => l10n.calendarGuideTourPick),
      GuideCoachStep('opened', (l10n) => l10n.calendarGuideTourOpen),
      GuideCoachStep(
        'changed',
        (l10n) => l10n.calendarGuideTourEdit(l10n.edit, l10n.save),
      ),
      GuideCoachStep('added', (l10n) => l10n.calendarGuideTourAdd),
      GuideCoachStep(
        'filtered',
        (l10n) => l10n.calendarGuideTourFilter(l10n.apply),
      ),
    ],
    filtering => [
      GuideCoachStep('funnel', (l10n) => l10n.calendarGuideTourFilterOpen),
      GuideCoachStep(
        'category',
        (l10n) => l10n.calendarGuideTourFilterCategory(
          l10n.calendarCategories,
          l10n.apply,
        ),
      ),
      GuideCoachStep(
        'trait',
        (l10n) => l10n.calendarGuideTourFilterTrait(
          l10n.calendarFilterOnlyShow,
          l10n.apply,
        ),
      ),
      GuideCoachStep(
        'reset',
        (l10n) => l10n.calendarGuideTourFilterReset(
          l10n.calendarFilterReset,
          l10n.apply,
        ),
      ),
    ],
  };

  /// The tour's closing line, for its coach's `closing`.
  String closing(AppLocalizations l10n) => switch (this) {
    events => l10n.calendarGuideTourDone,
    filtering => l10n.calendarGuideTourFilterDone,
  };
}

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

  /// Right after attendance: the report answers "what did I do" once "did I
  /// go" is understood.
  report('report', Icons.bar_chart_rounded),
  categories('categories', Icons.category_rounded),
  finding('finding', Icons.search_rounded),
  setup('setup', Icons.tune_rounded),
  fasting('fasting', Icons.restaurant_menu_rounded),
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
    report => l10n.calendarGuidePageReport,
    categories => l10n.calendarGuidePageCategories,
    finding => l10n.calendarGuidePageFinding,
    setup => l10n.calendarGuidePageSetup,
    fasting => l10n.calendarGuidePageFasting,
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
    report => l10n.calendarGuidePageReportCaption,
    categories => l10n.calendarGuidePageCategoriesCaption,
    finding => l10n.calendarGuidePageFindingCaption(l10n.calendarOverview),
    setup => l10n.calendarGuidePageSetupCaption,
    fasting => l10n.calendarGuidePageFastingCaption,
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
    report => l10n.calendarGuideReportLead(l10n.reportTitle),
    categories => l10n.calendarGuideCategoriesLead,
    finding => l10n.calendarGuideFindingLead,
    setup => l10n.calendarGuideSetupLead,
    fasting => l10n.calendarGuideFastingLead,
    good => null,
  };

  /// The page's "Try it" cards, top to bottom; none for Good to know, which
  /// has nothing to try. Here rather than in the demos so the hub's search
  /// and the cards' coaches read one source. A getter, not a call per
  /// language: a demo's coach is built before the page has a language and
  /// outlives a change of it, so each line is written when it is drawn.
  ///
  /// The screen page has three (D58): the grid, the panel and the overview
  /// each under their own title, over one demo calendar. A single stage
  /// holding all three would stand some 900 px tall and reach the overview
  /// only through the title menu.
  List<GuideCardSpec> get cards => switch (this) {
    screen => [
      GuideCardSpec(GuideCardSpec.screenGrid, [
        GuideCoachStep(
          'title',
          (l10n) => l10n.calendarGuideCoachScreenTitle(l10n.calendar),
        ),
        GuideCoachStep('more', (l10n) => l10n.calendarGuideCoachScreenMore),
      ], (l10n) => l10n.calendarGuideCardGrid),
      GuideCardSpec(GuideCardSpec.screenPanel, [
        GuideCoachStep(
          'panel',
          (l10n) => l10n.calendarGuideCoachScreenPanel(
            l10n.panelModeDay,
            l10n.panelModeTimeline,
            l10n.upcomingEvents,
          ),
        ),
      ], (l10n) => l10n.calendarGuideCardPanel),
      GuideCardSpec(GuideCardSpec.screenOverview, [
        GuideCoachStep(
          'mode',
          (l10n) => l10n.calendarGuideCoachOverviewMode(
            l10n.dayListModeYear,
            l10n.dayListModeMonth,
            l10n.dayListModeList,
          ),
        ),
        GuideCoachStep(
          'period',
          (l10n) => l10n.calendarGuideCoachOverviewPeriod,
        ),
      ], (l10n) => l10n.calendarGuideCardOverview),
    ],
    // The report has no stage: a fold over her own calendar is what it
    // shows, and a demo calendar's numbers would teach nothing.
    report || good => const [],
    _ => [
      GuideCardSpec(slug, _soleCardSteps, (l10n) => l10n.calendarGuideTryIt),
    ],
  };

  /// The single card's steps of a page that has one, in the order she is
  /// asked for them.
  List<GuideCoachStep> get _soleCardSteps => switch (this) {
    screen || report || good => const [],
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
    fasting => [
      GuideCoachStep(
        'tradition',
        (l10n) => l10n.calendarGuideCoachFastingTradition,
      ),
      GuideCoachStep(
        'style',
        (l10n) =>
            l10n.calendarGuideCoachFastingStyle(l10n.fastingAppearanceTitle),
      ),
      GuideCoachStep(
        'practice',
        (l10n) =>
            l10n.calendarGuideCoachFastingPractice(l10n.fastingScheduleTitle),
      ),
    ],
  };

  /// The card [slug] names — a page's demos are built per card by slug,
  /// never by place, so a card moved in [cards] keeps its demo.
  GuideCardSpec card(String slug) =>
      cards.firstWhere((card) => card.slug == slug);

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
        l10n.calendarGuideViewsBody(l10n.calendarFormatMonth),
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
          l10n.settingsHubTitle,
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
    report => [
      CalendarGuideRow(
        'report-open',
        Icons.swap_horiz_rounded,
        l10n.calendarGuideReportOpenTitle,
        l10n.calendarGuideReportOpenBody(
          l10n.calendar,
          l10n.calendarOverview,
          l10n.reportTitle,
          l10n.overviewPeriodThisWeek,
          l10n.reportPeriodLastMonth,
          l10n.upcomingPeriodCustom,
        ),
      ),
      CalendarGuideRow(
        'report-categories',
        Icons.filter_alt_outlined,
        l10n.calendarGuideReportCategoriesTitle,
        // Real counts: the "more" rows' labels carry their numbers.
        l10n.calendarGuideReportCategoriesBody(
          l10n.calendarCategories,
          ReportMetrics.maxCategoryRows,
          l10n.reportMoreCategories(3),
          ReportMetrics.groupPreviewRows,
          l10n.reportGroupMore(3),
        ),
      ),
      CalendarGuideRow(
        'report-missed',
        Icons.event_busy_outlined,
        l10n.calendarGuideReportMissedTitle,
        l10n.calendarGuideReportMissedBody(
          l10n.reportSectionMissed,
          l10n.eventMarkPresent,
        ),
      ),
      CalendarGuideRow(
        'report-digest',
        Icons.notifications_rounded,
        l10n.calendarGuideReportDigestTitle,
        l10n.calendarGuideReportDigestBody(
          l10n.reportSendWeekly,
          l10n.reportSendMonthly,
          l10n.digestShows,
          l10n.digestShowsWeekReport,
          l10n.digestShowsMonthReport,
          l10n.reportShare,
        ),
      ),
    ],
    categories => [
      CalendarGuideRow(
        'category',
        Icons.category_rounded,
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
          l10n.settingsHubTitle,
          l10n.languageSettings,
          l10n.settingsRowTheme,
        ),
      ),
    ],
    fasting => [
      CalendarGuideRow(
        'fasting-where',
        Icons.settings_outlined,
        l10n.calendarGuideFastingWhereTitle,
        l10n.calendarGuideFastingWhereBody(
          l10n.calendarSettingsRow,
          l10n.fastingSectionTitle,
        ),
      ),
      CalendarGuideRow(
        'fasting-rules',
        Icons.rule_rounded,
        l10n.calendarGuideFastingRulesTitle,
        l10n.calendarGuideFastingRulesBody,
      ),
      CalendarGuideRow(
        'fasting-practice',
        Icons.event_repeat_rounded,
        l10n.calendarGuideFastingPracticeTitle,
        l10n.calendarGuideFastingPracticeBody(
          l10n.fastingScheduleTitle,
          l10n.fastingWeekdayScopeTitle,
          l10n.fastingWeekdayScopeAll,
        ),
      ),
      CalendarGuideRow(
        'fasting-hide',
        Icons.filter_alt_outlined,
        l10n.calendarGuideFastingHideTitle,
        l10n.calendarGuideFastingHideBody(l10n.upcomingShowFasting, l10n.apply),
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
