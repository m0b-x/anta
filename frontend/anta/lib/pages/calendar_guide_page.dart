import 'package:flutter/material.dart';

import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_guide_content.dart';
import '../services/app_navigator.dart';
import '../utils/settings_search.dart';
import '../widgets/calendar_guide_rows.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/unified_app_bars.dart';
import 'calendar_guide_practice_page.dart';
import 'calendar_guide_topic_page.dart';

/// How the calendar works, for someone who has never used a calendar app.
///
/// Reached from the calendar's ⋮ beside Calendar settings, and like that page
/// it speaks the settings kit. It is a hub: one row per task, each opening a
/// page of read rows ([CalendarGuideTopicPage]), so a newcomer reads only the
/// task in hand. Its search reaches into every page, because someone who
/// knows the word they are after should not have to guess the page first.
/// It reads nothing and writes nothing.
class CalendarGuidePage extends StatefulWidget {
  const CalendarGuidePage({super.key});

  @override
  State<CalendarGuidePage> createState() => _CalendarGuidePageState();
}

class _CalendarGuidePageState extends State<CalendarGuidePage> {
  /// "Start here": the pages to read before anything else.
  static const List<CalendarGuideTopic> _startHere = [
    CalendarGuideTopic.screen,
    CalendarGuideTopic.good,
  ];

  /// The spaces the line breaker breaks at: the no-break ones (U+00A0,
  /// U+2007, U+202F) hold their words together, so a word is measured with
  /// them.
  static final RegExp _breakingSpaces = RegExp(
    '[ \\t\\n\\u1680\\u2000-\\u2006\\u2008-\\u200A\\u205F\\u3000]+',
  );

  final TextEditingController _searchController = TextEditingController();
  SettingsQuery _query = SettingsQuery.empty;

  /// The last [_glyphsFit] answer, with the inputs it was measured on. Every
  /// hub row asks on every layout, and the answer can only move with the
  /// row's width, the text scaler, the locale or the density, so it is
  /// measured once for as long as those hold.
  ({double width, TextScaler scaler, String locale, double density})?
  _fitInputs;
  bool _fitAnswer = true;

  /// Every page's read rows, built once per locale: the search reads all of
  /// them on every keystroke, and they can only change with the language.
  Map<CalendarGuideTopic, List<CalendarGuideRow>> _rows = const {};
  Locale? _rowsLocale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (locale == _rowsLocale) return;
    _rowsLocale = locale;
    final l10n = AppLocalizations.of(context)!;
    _rows = {
      for (final topic in CalendarGuideTopic.values) topic: topic.rows(l10n),
    };
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
                  sections: _query.isEmpty
                      ? _hubSections(l10n)
                      : _searchSections(l10n),
                  header: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: GuideMetrics.headingInset,
                      ),
                      child: Text(
                        l10n.calendarGuideIntro(l10n.calendarGuideTryIt),
                        style: calendarGuideParagraphStyle.copyWith(
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

  List<SettingsSectionData> _hubSections(AppLocalizations l10n) {
    return [
      SettingsSectionData(
        icon: Icons.flag_rounded,
        title: l10n.calendarGuideStartHere,
        entries: [
          _practiceEntry(l10n),
          for (final topic in _startHere) _pageEntry(l10n, topic),
        ],
      ),
      SettingsSectionData(
        icon: Icons.help_outline_rounded,
        title: l10n.calendarGuideHowDoI,
        entries: [
          for (final topic in CalendarGuideTopic.values)
            if (!_startHere.contains(topic)) _pageEntry(l10n, topic),
        ],
      ),
    ];
  }

  /// While a query is live the hub cards give way to one section per page,
  /// its own row first and then its matching read rows: a match is shown
  /// under the name of the page that holds it, one tap from the rest of that
  /// page. The kit drops a section with nothing matching. The practice
  /// calendar has no read rows, so its section holds its own row alone.
  List<SettingsSectionData> _searchSections(AppLocalizations l10n) {
    return [
      SettingsSectionData(
        icon: calendarGuidePracticeIcon,
        title: l10n.calendarGuidePagePractice,
        entries: [_practiceEntry(l10n)],
      ),
      for (final topic in CalendarGuideTopic.values)
        _searchSection(l10n, topic, _rows[topic] ?? const []),
    ];
  }

  /// The rows are filtered here rather than by the kit: the section is titled
  /// with the page's name, and a query that hits a section title makes the
  /// kit show the whole section, so "delete" would list every events row.
  SettingsSectionData _searchSection(
    AppLocalizations l10n,
    CalendarGuideTopic topic,
    List<CalendarGuideRow> rows,
  ) {
    final matching = [
      for (final row in rows)
        if (matchSettingsEntry(
              _query,
              title: row.title,
              description: row.body,
            ) !=
            null)
          row,
    ];
    return SettingsSectionData(
      icon: topic.icon,
      title: topic.title(l10n),
      entries: [
        _pageEntry(l10n, topic, rows: matching),
        for (final row in matching) calendarGuideReadEntry(row),
      ],
    );
  }

  /// The row that opens [topic]'s page. Given the page's [rows], it matches
  /// whatever any of them matches, so a search hit never shows without the
  /// way to its page.
  SettingsEntry _pageEntry(
    AppLocalizations l10n,
    CalendarGuideTopic topic, {
    List<CalendarGuideRow> rows = const [],
  }) {
    return SettingsEntry(
      title: topic.title(l10n),
      description: topic.caption(l10n),
      keywords: [
        for (final row in rows) ...[row.title, row.body],
      ],
      identifier: SemanticsIds.calendarGuidePage(topic.slug),
      builder: (context, title, description) => LayoutBuilder(
        builder: (context, constraints) => _HubRow(
          icon: _glyphsFit(context, l10n, constraints.maxWidth)
              ? topic.icon
              : null,
          title: title,
          description: description,
          onTap: () => AppNavigator.push<void>(
            context,
            CalendarGuideTopicPage(topic: topic),
          ),
        ),
      ),
    );
  }

  /// The row that opens the practice calendar, first in "Start here" (D23):
  /// trying the calendar is where a newcomer begins.
  SettingsEntry _practiceEntry(AppLocalizations l10n) {
    return SettingsEntry(
      title: l10n.calendarGuidePagePractice,
      description: l10n.calendarGuidePagePracticeCaption,
      identifier: SemanticsIds.calendarGuidePage(calendarGuidePracticeSlug),
      builder: (context, title, description) => LayoutBuilder(
        builder: (context, constraints) => _HubRow(
          icon: _glyphsFit(context, l10n, constraints.maxWidth)
              ? calendarGuidePracticeIcon
              : null,
          title: title,
          description: description,
          onTap: () => AppNavigator.push<void>(
            context,
            const CalendarGuidePracticePage(),
          ),
        ),
      ),
    );
  }

  /// [_measureGlyphsFit] for the layout path: measured once per set of
  /// inputs.
  bool _glyphsFit(BuildContext context, AppLocalizations l10n, double width) {
    final inputs = (
      width: width,
      scaler: MediaQuery.textScalerOf(context),
      locale: l10n.localeName,
      density: Theme.of(context).visualDensity.horizontal,
    );
    if (inputs == _fitInputs) return _fitAnswer;
    _fitInputs = inputs;
    return _fitAnswer = _measureGlyphsFit(context, l10n, width);
  }

  /// Whether the longest word of every hub title fits the title column a row
  /// [width] wide leaves beside the glyph and the chevron. When one does not,
  /// every row drops its glyph together — a word broken mid-way reads worse
  /// than a missing icon, and rows with and without one would not line up.
  /// The Practice calendar's title is measured too, so the row it adds
  /// changes nothing.
  bool _measureGlyphsFit(
    BuildContext context,
    AppLocalizations l10n,
    double width,
  ) {
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // The kit's title over the text style a ListTile gives its title.
    final style = theme.textTheme.bodyLarge?.merge(
      const TextStyle(
        fontSize: GuideMetrics.hubTitleFontSize,
        fontWeight: GuideMetrics.hubTitleFontWeight,
      ),
    );
    final gap = GuideMetrics.hubTitleGap + theme.visualDensity.horizontal * 2;
    final column = GuideMetrics.hubGlyphSize + gap;
    final room =
        width -
        GuideMetrics.hubRowPadding.horizontal -
        column /* the glyph */ -
        column /* the chevron */;
    final titles = [
      l10n.calendarGuidePagePractice,
      for (final topic in CalendarGuideTopic.values) topic.title(l10n),
    ];
    final painter = TextPainter(
      textDirection: direction,
      textScaler: textScaler,
      maxLines: 1,
    );
    try {
      for (final title in titles) {
        for (final word in title.split(_breakingSpaces)) {
          painter
            ..text = TextSpan(text: word, style: style)
            ..layout();
          // An exact fit can still wrap in the engine, so a word needs half
          // a pixel to spare.
          if (room - painter.width < 0.5) return false;
        }
      }
      return true;
    } finally {
      painter.dispose();
    }
  }
}

/// A hub row: the page's glyph, its title and what it covers, and a chevron —
/// the one guide row that is pressed, so it is a button and reads as one.
class _HubRow extends StatelessWidget {
  const _HubRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  /// Null when the glyph gives way to a long title word.
  final IconData? icon;
  final Widget title;
  final Widget? description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: ListTile(
        contentPadding: GuideMetrics.hubRowPadding,
        minLeadingWidth: GuideMetrics.hubGlyphSize,
        horizontalTitleGap: GuideMetrics.hubTitleGap,
        leading: icon == null
            ? null
            : ExcludeSemantics(
                child: Icon(
                  icon,
                  size: GuideMetrics.hubGlyphSize,
                  color: colorScheme.primary,
                ),
              ),
        title: title,
        subtitle: description,
        trailing: Icon(
          Icons.chevron_right_rounded,
          size: GuideMetrics.hubGlyphSize,
          color: colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
    );
  }
}
