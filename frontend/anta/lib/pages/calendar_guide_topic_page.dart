import 'package:flutter/material.dart';

import '../constants/form_metrics.dart';
import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_guide_content.dart';
import '../services/category_service.dart';
import '../services/public_holiday_service.dart';
import '../services/settings_service.dart';
import '../utils/settings_search.dart';
import '../widgets/calendar_guide_rows.dart';
import '../widgets/calendar_guide_try_alerts.dart';
import '../widgets/calendar_guide_try_attendance.dart';
import '../widgets/calendar_guide_try_categories.dart';
import '../widgets/calendar_guide_try_finding.dart';
import '../widgets/calendar_guide_try_setup.dart';
import '../widgets/calendar_guide_try_card.dart';
import '../widgets/calendar_guide_try_events.dart';
import '../widgets/calendar_guide_try_fasting.dart';
import '../widgets/calendar_guide_try_kinds.dart';
import '../widgets/calendar_guide_try_overview.dart';
import '../widgets/calendar_guide_try_screen.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/unified_app_bars.dart';

/// One page of the calendar guide: a task, the line that says what it is,
/// a "Try it" card where she can do it for real without saving anything, and
/// its steps as read rows.
///
/// Pushed from the hub without a destination stamp: a page is a few seconds'
/// reading, so a relaunch lands on the hub rather than restoring it. The bar
/// names the guide, not the page, because the German page titles do not fit
/// a bar; the page title is the list's heading instead. No search field — the
/// hub searches every page.
class CalendarGuideTopicPage extends StatefulWidget {
  const CalendarGuideTopicPage({
    super.key,
    required this.topic,
    this.now = DateTime.now,
  });

  final CalendarGuideTopic topic;

  /// The clock the card's demo reads today from, once: a seam for a suite
  /// that needs a particular day (the last days of a year).
  final DateTime Function() now;

  @override
  State<CalendarGuideTopicPage> createState() => _CalendarGuideTopicPageState();
}

/// The demos of [topic]'s cards by card slug; none for a page without one.
/// The screen page's three share [world].
Map<String, GuideCardDemo> _demosFor(
  CalendarGuideTopic topic,
  DateTime Function() now,
  GuideScreenWorld? world,
) => switch (topic) {
  CalendarGuideTopic.screen => {
    GuideCardSpec.screenGrid: GuideScreenDemo(world!),
    GuideCardSpec.screenPanel: GuidePanelDemo(world),
    GuideCardSpec.screenOverview: GuideOverviewDemo(world),
  },
  CalendarGuideTopic.events => {topic.slug: GuideEventsDemo(now: now)},
  CalendarGuideTopic.kinds => {topic.slug: GuideKindsDemo(now: now)},
  CalendarGuideTopic.alerts => {topic.slug: GuideAlertsDemo(now: now)},
  CalendarGuideTopic.attendance => {topic.slug: GuideAttendanceDemo(now: now)},
  CalendarGuideTopic.categories => {topic.slug: GuideCategoriesDemo()},
  CalendarGuideTopic.finding => {topic.slug: GuideFindingDemo(now: now)},
  CalendarGuideTopic.setup => {topic.slug: GuideSetupDemo(now: now)},
  CalendarGuideTopic.fasting => {topic.slug: GuideFastingDemo(now: now)},
  CalendarGuideTopic.good => const {},
};

class _CalendarGuideTopicPageState extends State<CalendarGuideTopicPage> {
  /// The screen page's demo calendar, which its three cards share.
  late final GuideScreenWorld? _world =
      widget.topic == CalendarGuideTopic.screen
      ? GuideScreenWorld(now: widget.now)
      : null;

  /// The cards' demos, here rather than in the cards: the list disposes a
  /// card scrolled out of view, and what she did on it must survive that.
  late final Map<String, GuideCardDemo> _demos = _demosFor(
    widget.topic,
    widget.now,
    _world,
  );

  /// Each card's caption slot candidates by card slug, built once per
  /// locale.
  Map<String, List<String>> _candidates = const {};
  Locale? _candidatesLocale;

  @override
  void initState() {
    super.initState();
    for (final demo in _demos.values) {
      if (demo.needsAppearance) _loadAppearance(demo);
    }
    if (_world case final world?) _loadWorld(world);
  }

  /// The screen page's look, palette and categories, read once, as the
  /// practice page reads them; the demo stands on the defaults and the
  /// cached categories until then. Her look arriving can change the grid's
  /// row height once, within the first frames, before she can have touched
  /// anything; her categories only recolour. Each read on its own: one that
  /// throws leaves the others.
  Future<void> _loadWorld(GuideScreenWorld world) async {
    try {
      final settings = await SettingsService.getInstance();
      final loaded = await settings.getCalendarPageSettings();
      if (!mounted) return;
      world.adopt(appearance: loaded.appearance, palette: loaded.palette);
    } catch (e, st) {
      debugPrint('[CalendarGuideTopicPage] Settings load failed: $e\n$st');
    }
    try {
      final categories = (await CategoryService.getInstance()).categories;
      if (!mounted) return;
      world.adopt(categories: categories);
    } catch (e, st) {
      debugPrint('[CalendarGuideTopicPage] Categories load failed: $e\n$st');
    }
  }

  /// The owner's calendar look for the stage's pickers and add button, read
  /// once, as the practice page reads it; the defaults stand until then. The
  /// setup card also starts from her holiday set, read after it and on its
  /// own: a holiday read that throws still leaves her look on the stage, and
  /// the menu shows Generic until the service answers (its row is sized for
  /// every set, so the answer moves nothing).
  Future<void> _loadAppearance(GuideCardDemo demo) async {
    try {
      final settings = await SettingsService.getInstance();
      final loaded = await settings.getCalendarPageSettings();
      if (!mounted) return;
      demo.appearance = loaded.appearance;
    } catch (e, st) {
      debugPrint('[CalendarGuideTopicPage] Settings load failed: $e\n$st');
    }
    if (demo is! GuideSetupDemo) return;
    try {
      final holidays = await PublicHolidayService.getInstance();
      if (!mounted) return;
      demo.holidayProfile = holidays.profile;
    } catch (e, st) {
      debugPrint('[CalendarGuideTopicPage] Holiday set load failed: $e\n$st');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context)!;
    // Before the first frame: the stages draw the demo calendar.
    _world?.ensureCalendar(l10n);
    final locale = Localizations.localeOf(context);
    if (locale == _candidatesLocale) return;
    _candidatesLocale = locale;
    _candidates = {
      for (final MapEntry(key: slug, value: demo) in _demos.entries)
        slug: demo.candidates(l10n),
    };
  }

  @override
  void dispose() {
    for (final demo in _demos.values) {
      demo.dispose();
    }
    _world?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topic = widget.topic;
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final lead = topic.lead(l10n);
    final cards = topic.cards;

    return Scaffold(
      appBar: SettingsAppBar(
        title: l10n.calendarGuideTitle,
        showMenuButton: false,
      ),
      body: SafeArea(
        top: false,
        child: Semantics(
          container: true,
          identifier: SemanticsIds.calendarGuideTopic(topic.slug),
          child: SettingsSectionList(
            query: SettingsQuery.empty,
            header: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  GuideMetrics.headingInset,
                  0,
                  GuideMetrics.headingInset,
                  GuideMetrics.headingGap,
                ),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: GuideMetrics.headingMaxTextScale,
                  child: Semantics(
                    header: true,
                    headingLevel: 1,
                    child: Text(
                      topic.title(l10n),
                      style: TextStyle(
                        fontSize: FormMetrics.titleFontSize,
                        height: FormMetrics.titleLineHeight,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
              if (lead != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GuideMetrics.headingInset,
                  ),
                  child: Text(
                    lead,
                    style: calendarGuideParagraphStyle.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
            sections: [
              for (final card in cards)
                calendarGuideTrySection(
                  l10n: l10n,
                  card: card,
                  demo: _demos[card.slug]!,
                  candidates: _candidates[card.slug]!,
                ),
              SettingsSectionData(
                icon: topic.icon,
                title: l10n.calendarGuideHowItWorks,
                entries: [
                  for (final row in topic.rows(l10n))
                    calendarGuideReadEntry(row),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
