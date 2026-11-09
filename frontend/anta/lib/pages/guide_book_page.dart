import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/guide_book.dart';
import '../models/guide_content.dart';
import '../services/app_navigator.dart';
import '../utils/settings_search.dart';
import '../widgets/calendar_guide_rows.dart';
import '../widgets/guide_hub_list.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/unified_app_bars.dart';

/// The hub row that opens [topic]'s page of [book], for the book's own hub
/// and the "How to use ANTA" hub's search (D2): found by its read rows, by
/// its examples' captions and sources, and by its editor cards' coach lines.
GuideHubItem guideTopicHubItem(
  AppLocalizations l10n,
  GuideBook book,
  GuideTopic topic,
) {
  final entries = topic.entries(l10n);
  return GuideHubItem(
    slug: topic.slug,
    icon: topic.icon,
    title: topic.title(l10n),
    caption: topic.caption(l10n),
    keywords: [
      for (final entry in entries)
        if (entry case GuideExampleEntry(:final caption, :final source)) ...[
          caption,
          source,
        ],
      // Every coach line of every card too, as the calendar's hub (D58):
      // what the page lets her try is a reason to open it.
      for (final card in topic.editorCards)
        for (final step in card.steps) step.line(l10n),
    ],
    rows: [
      for (final entry in entries)
        if (entry case GuideReadEntry(:final row)) row,
    ],
    rowIdentifier: (slug) => SemanticsIds.guideBookRow(book.slug, slug),
    identifier: SemanticsIds.guideBookPage(book.slug, topic.slug),
    open: (context) => AppNavigator.toGuideTopic(context, book, topic),
  );
}

/// One guide book's hub — the notes or the app book (D3): the calendar
/// guide's shape, with "Start here" and "How do I…" cards over the book's
/// pages and a search that reaches into every one of them.
///
/// It reads nothing and writes nothing.
class GuideBookPage extends StatefulWidget {
  const GuideBookPage({super.key, required this.book})
    : assert(book != GuideBook.calendar);

  /// Never [GuideBook.calendar]: its pages are `CalendarGuideTopic`s with
  /// practice lessons and "Try it" cards, reached through
  /// `CalendarGuidePage`, and this hub has no place for them.
  final GuideBook book;

  @override
  State<GuideBookPage> createState() => _GuideBookPageState();
}

class _GuideBookPageState extends State<GuideBookPage> {
  final TextEditingController _searchController = TextEditingController();
  SettingsQuery _query = SettingsQuery.empty;

  /// The hub's cards, built once per locale: the search reads every page's
  /// rows on every keystroke, and they can only change with the language.
  List<GuideHubSection> _sections = const [];
  Locale? _sectionsLocale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (locale == _sectionsLocale) return;
    _sectionsLocale = locale;
    final l10n = AppLocalizations.of(context)!;
    final book = widget.book;
    _sections = [
      GuideHubSection(
        icon: Icons.flag_rounded,
        title: l10n.calendarGuideStartHere,
        items: [
          for (final topic in book.startHere)
            guideTopicHubItem(l10n, book, topic),
        ],
      ),
      GuideHubSection(
        icon: Icons.help_outline_rounded,
        title: l10n.calendarGuideHowDoI,
        items: [
          for (final topic in book.topics)
            if (!book.startHere.contains(topic))
              guideTopicHubItem(l10n, book, topic),
        ],
      ),
    ];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.pageGround,
      appBar: SettingsAppBar(title: book.title(l10n)),
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
                listIdentifier: SemanticsIds.guideBook(book.slug),
                header: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GuideMetrics.headingInset,
                    ),
                    child: Text(
                      book.intro(l10n),
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
