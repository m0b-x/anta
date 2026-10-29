import 'package:flutter/material.dart';

import '../constants/form_metrics.dart';
import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_guide_content.dart';
import '../services/settings_service.dart';
import '../utils/settings_search.dart';
import '../widgets/calendar_guide_rows.dart';
import '../widgets/calendar_guide_try_alerts.dart';
import '../widgets/calendar_guide_try_card.dart';
import '../widgets/calendar_guide_try_events.dart';
import '../widgets/calendar_guide_try_kinds.dart';
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
  const CalendarGuideTopicPage({super.key, required this.topic});

  final CalendarGuideTopic topic;

  @override
  State<CalendarGuideTopicPage> createState() => _CalendarGuideTopicPageState();
}

/// The demo of [topic]'s card, or null for a page without one.
GuideCardDemo? _demoFor(CalendarGuideTopic topic) => switch (topic) {
  CalendarGuideTopic.screen => GuideScreenDemo(),
  CalendarGuideTopic.events => GuideEventsDemo(),
  CalendarGuideTopic.kinds => GuideKindsDemo(),
  CalendarGuideTopic.alerts => GuideAlertsDemo(),
  _ => null,
};

class _CalendarGuideTopicPageState extends State<CalendarGuideTopicPage> {
  /// The card's demo, here rather than in the card: the list disposes a card
  /// scrolled out of view, and what she did on it must survive that.
  late final GuideCardDemo? _demo = _demoFor(widget.topic);

  /// The caption slot's candidates, built once per locale.
  List<String> _candidates = const [];
  Locale? _candidatesLocale;

  @override
  void initState() {
    super.initState();
    if (_demo?.needsAppearance ?? false) _loadAppearance();
  }

  /// The owner's calendar look for the stage's pickers and add button, read
  /// once, as the practice page reads it; the defaults stand until then.
  Future<void> _loadAppearance() async {
    try {
      final settings = await SettingsService.getInstance();
      final loaded = await settings.getCalendarPageSettings();
      if (!mounted) return;
      _demo?.appearance = loaded.appearance;
    } catch (e, st) {
      debugPrint('[CalendarGuideTopicPage] Settings load failed: $e\n$st');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final demo = _demo;
    final locale = Localizations.localeOf(context);
    if (demo == null || locale == _candidatesLocale) return;
    _candidatesLocale = locale;
    _candidates = demo.candidates(AppLocalizations.of(context)!);
  }

  @override
  void dispose() {
    _demo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topic = widget.topic;
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final lead = topic.lead(l10n);
    final demo = _demo;
    final tryLead = topic.tryLead(l10n);

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
              if (demo != null && tryLead != null)
                calendarGuideTrySection(
                  l10n: l10n,
                  topic: topic,
                  lead: tryLead,
                  demo: demo,
                  candidates: _candidates,
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
