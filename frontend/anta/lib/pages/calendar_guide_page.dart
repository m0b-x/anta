import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_guide_content.dart';
import '../services/app_navigator.dart';
import '../utils/settings_search.dart';
import '../widgets/calendar_guide_rows.dart';
import '../widgets/guide_hub_list.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/unified_app_bars.dart';
import 'calendar_guide_practice_page.dart';

/// "Start here": the pages to read before anything else.
const List<CalendarGuideTopic> _startHere = [
  CalendarGuideTopic.screen,
  CalendarGuideTopic.good,
];

/// The row that opens a practice lesson, first in "Start here" (D23, D54):
/// trying the calendar is where a newcomer begins.
GuideHubItem _lessonItem(AppLocalizations l10n, GuidePracticeLesson lesson) {
  return GuideHubItem(
    slug: lesson.slug,
    icon: lesson.icon,
    title: lesson.title(l10n),
    caption: lesson.caption(l10n),
    // The tour's first line, as a page's row takes its card's: what the
    // lesson asks her to try is a reason to open it.
    keywords: [lesson.steps.first.line(l10n)],
    identifier: SemanticsIds.calendarGuidePage(lesson.slug),
    open: (context) => AppNavigator.push<void>(
      context,
      CalendarGuidePracticePage(lesson: lesson),
    ),
  );
}

/// The row that opens [topic]'s page.
GuideHubItem _topicItem(AppLocalizations l10n, CalendarGuideTopic topic) {
  return GuideHubItem(
    slug: topic.slug,
    icon: topic.icon,
    title: topic.title(l10n),
    caption: topic.caption(l10n),
    // Every instruction of every card too (D58): what the page lets her
    // try is a reason to open it, and one stage's tour names several
    // controls — "Year" is the screen page's fourth step.
    keywords: [
      for (final card in topic.cards)
        for (final step in card.steps) step.line(l10n),
    ],
    rows: topic.rows(l10n),
    identifier: SemanticsIds.calendarGuidePage(topic.slug),
    open: (context) => AppNavigator.toCalendarGuideTopic(context, topic),
  );
}

/// The calendar guide's hub cards: the two practice lessons and the pages
/// to read first, then every task.
List<GuideHubSection> calendarGuideHubSections(AppLocalizations l10n) {
  return [
    GuideHubSection(
      icon: Icons.flag_rounded,
      title: l10n.calendarGuideStartHere,
      items: [
        for (final lesson in GuidePracticeLesson.values)
          _lessonItem(l10n, lesson),
        for (final topic in _startHere) _topicItem(l10n, topic),
      ],
    ),
    GuideHubSection(
      icon: Icons.help_outline_rounded,
      title: l10n.calendarGuideHowDoI,
      items: [
        for (final topic in CalendarGuideTopic.values)
          if (!_startHere.contains(topic)) _topicItem(l10n, topic),
      ],
    ),
  ];
}

/// Every page of the calendar guide in the order its search lists them —
/// the lessons, then the pages in catalogue order — for its own hub and for
/// the "How to use ANTA" hub's search (D2 of `docs/guide-hub-roadmap.md`).
List<GuideHubItem> calendarGuideSearchItems(AppLocalizations l10n) {
  return [
    for (final lesson in GuidePracticeLesson.values) _lessonItem(l10n, lesson),
    for (final topic in CalendarGuideTopic.values) _topicItem(l10n, topic),
  ];
}

/// How the calendar works, for someone who has never used a calendar app.
///
/// Reached from the calendar's ⋮ beside Calendar settings, and like that page
/// it speaks the settings kit. It is a hub: one row per task, each opening a
/// page of read rows (`CalendarGuideTopicPage`), so a newcomer reads only the
/// task in hand. Its search reaches into every page, because someone who
/// knows the word they are after should not have to guess the page first.
/// It reads nothing and writes nothing.
class CalendarGuidePage extends StatefulWidget {
  const CalendarGuidePage({super.key});

  @override
  State<CalendarGuidePage> createState() => _CalendarGuidePageState();
}

class _CalendarGuidePageState extends State<CalendarGuidePage> {
  final TextEditingController _searchController = TextEditingController();
  SettingsQuery _query = SettingsQuery.empty;

  /// The hub's cards and its search's pages, built once per locale: the
  /// search reads every page's rows on every keystroke, and they can only
  /// change with the language.
  List<GuideHubSection> _sections = const [];
  List<GuideHubItem> _searchItems = const [];
  Locale? _itemsLocale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (locale == _itemsLocale) return;
    _itemsLocale = locale;
    final l10n = AppLocalizations.of(context)!;
    _sections = calendarGuideHubSections(l10n);
    _searchItems = calendarGuideSearchItems(l10n);
  }

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
      backgroundColor: Theme.of(context).colorScheme.pageGround,
      appBar: SettingsAppBar(title: l10n.calendarGuideTitle),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: GuideMetrics.searchFieldPadding,
              child: SettingsSearchField(
                controller: _searchController,
                hint: l10n.calendarGuideSearchHint,
                onChanged: (value) =>
                    setState(() => _query = SettingsQuery.parse(value)),
              ),
            ),
            Expanded(
              child: GuideHubList(
                query: _query,
                sections: _sections,
                searchItems: _searchItems,
                listIdentifier: SemanticsIds.calendarGuide,
                header: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GuideMetrics.headingInset,
                    ),
                    child: Text(
                      l10n.calendarGuideIntro,
                      style: calendarGuideParagraphStyle.copyWith(
                        color: colorScheme.onSurfaceVariant,
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
}
