import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/guide_book.dart';
import '../services/app_navigator.dart';
import '../utils/settings_search.dart';
import '../widgets/calendar_guide_rows.dart';
import '../widgets/guide_hub_list.dart';
import '../widgets/settings_search_field.dart';
import '../widgets/unified_app_bars.dart';
import 'calendar_guide_page.dart';
import 'guide_book_page.dart';

/// "How to use ANTA" (`docs/guide-hub-roadmap.md` D1): the drawer's way into
/// every guide — the calendar's, the notes and editor book and the backup,
/// sync and settings book.
///
/// Its search reaches every page of every guide (D2), each match under the
/// name of the page that holds it, so someone who knows the word they are
/// after never has to pick a guide first. It reads nothing and writes
/// nothing.
class GuideHubPage extends StatefulWidget {
  const GuideHubPage({super.key});

  @override
  State<GuideHubPage> createState() => _GuideHubPageState();
}

class _GuideHubPageState extends State<GuideHubPage> {
  final TextEditingController _searchController = TextEditingController();
  SettingsQuery _query = SettingsQuery.empty;

  /// The three guides' rows and every guide's pages, built once per locale:
  /// the search reads every page's rows on every keystroke, and they can
  /// only change with the language.
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
    _sections = [
      GuideHubSection(
        icon: Icons.school_rounded,
        title: l10n.guideHubSectionGuides,
        items: [for (final book in GuideBook.values) _bookItem(l10n, book)],
      ),
    ];
    _searchItems = [
      ...calendarGuideSearchItems(l10n),
      for (final book in GuideBook.values)
        for (final topic in book.topics) guideTopicHubItem(l10n, book, topic),
    ];
  }

  /// The row that opens [book]'s hub. It carries no keywords: the book rows
  /// show only with an empty query, and a query reaches the books' pages
  /// through [_searchItems] instead. The calendar's opens its own hub, which
  /// keeps its practice lessons and "Try it" cards (D7).
  GuideHubItem _bookItem(AppLocalizations l10n, GuideBook book) {
    return GuideHubItem(
      slug: book.slug,
      icon: book.icon,
      title: book.title(l10n),
      caption: book.caption(l10n),
      identifier: SemanticsIds.guideHubBook(book.slug),
      open: (context) => switch (book) {
        GuideBook.calendar => AppNavigator.toCalendarGuide(context),
        _ => AppNavigator.toGuideBook(context, book),
      },
    );
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
      backgroundColor: colorScheme.pageGround,
      appBar: SettingsAppBar(title: l10n.howToUseAnta),
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
                listIdentifier: SemanticsIds.guideHub,
                header: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GuideMetrics.headingInset,
                    ),
                    child: Text(
                      l10n.guideHubIntro,
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
