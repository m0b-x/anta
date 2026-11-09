import 'package:flutter/material.dart';

import '../constants/guide_metrics.dart';
import '../models/calendar_guide_content.dart';
import '../utils/settings_search.dart';
import 'calendar_guide_rows.dart';
import 'settings_section_list.dart';

/// One row of a guide hub: a page, a practice lesson or a whole guide
/// (`docs/guide-hub-roadmap.md` D7).
@immutable
class GuideHubItem {
  const GuideHubItem({
    required this.slug,
    required this.icon,
    required this.title,
    required this.caption,
    required this.identifier,
    required this.open,
    this.keywords = const [],
    this.rows = const [],
    this.rowIdentifier,
  });

  /// Frozen like a page's: the row's [identifier] is built on it.
  final String slug;
  final IconData icon;
  final String title;
  final String caption;

  /// What the page lets her try or holds beyond its read rows: a reason to
  /// open it that the search should find.
  final List<String> keywords;

  /// The page's read rows: the search reaches into them and shows the
  /// matching ones under the page's row, one tap from the rest of the page.
  final List<CalendarGuideRow> rows;

  /// The id of one of [rows] by its slug, so a read row found by the search
  /// carries the id it has on its own page; the calendar guide's when null.
  final String Function(String slug)? rowIdentifier;

  final String identifier;

  /// Pushes the page, from the row's own context.
  final void Function(BuildContext context) open;
}

/// One card of a guide hub in hub mode.
@immutable
class GuideHubSection {
  const GuideHubSection({
    required this.icon,
    required this.title,
    required this.items,
  });

  final IconData icon;
  final String title;
  final List<GuideHubItem> items;
}

/// A guide hub's list, shared by the calendar guide, the two books and the
/// "How to use ANTA" hub so the four cannot drift apart (D7).
///
/// With no query it shows [sections], one card each. With a query the cards
/// give way to one section per item of [searchItems], its own row first and
/// then its matching read rows: a match is shown under the name of the page
/// that holds it. The kit drops a section with nothing matching.
class GuideHubList extends StatefulWidget {
  const GuideHubList({
    super.key,
    required this.query,
    required this.sections,
    required this.listIdentifier,
    this.searchItems,
    this.header = const [],
  });

  final SettingsQuery query;
  final List<GuideHubSection> sections;

  /// The pages a query reaches, in result order; the [sections]' items when
  /// null. The top hub lists three guides but searches every guide's pages.
  final List<GuideHubItem>? searchItems;

  final List<Widget> header;

  /// The list's id, which a flow waits on and scrolls inside.
  final String listIdentifier;

  @override
  State<GuideHubList> createState() => _GuideHubListState();
}

class _GuideHubListState extends State<GuideHubList> {
  /// The spaces the line breaker breaks at: the no-break ones (U+00A0,
  /// U+2007, U+202F) hold their words together, so a word is measured with
  /// them.
  static final RegExp _breakingSpaces = RegExp(
    '[ \\t\\n\\u1680\\u2000-\\u2006\\u2008-\\u200A\\u205F\\u3000]+',
  );

  /// The last [_glyphsFit] answer, with the inputs it was measured on. Every
  /// hub row asks on every layout, and the answer can only move with the
  /// row's width, the text scaler, the locale, the density or whether the
  /// hub or the search results are shown, so it is measured once for as long
  /// as those hold.
  ({
    double width,
    TextScaler scaler,
    String locale,
    double density,
    bool searching,
  })?
  _fitInputs;
  bool _fitAnswer = true;

  List<GuideHubItem> get _hubItems => [
    for (final section in widget.sections) ...section.items,
  ];

  List<GuideHubItem> get _searchItems => widget.searchItems ?? _hubItems;

  @override
  Widget build(BuildContext context) {
    final query = widget.query;
    return Semantics(
      container: true,
      identifier: widget.listIdentifier,
      child: SettingsSectionList(
        query: query,
        sections: query.isEmpty ? _hubSections() : _searchSections(),
        header: widget.header,
      ),
    );
  }

  List<SettingsSectionData> _hubSections() {
    return [
      for (final section in widget.sections)
        SettingsSectionData(
          icon: section.icon,
          title: section.title,
          entries: [for (final item in section.items) _itemEntry(item)],
        ),
    ];
  }

  List<SettingsSectionData> _searchSections() {
    return [for (final item in _searchItems) _searchSection(item)];
  }

  /// The rows are filtered here rather than by the kit: the section is titled
  /// with the page's name, and a query that hits a section title makes the
  /// kit show the whole section, so "delete" would list every events row.
  /// An item without read rows (a practice lesson) holds its own row alone.
  SettingsSectionData _searchSection(GuideHubItem item) {
    final matching = [
      for (final row in item.rows)
        if (matchSettingsEntry(
              widget.query,
              title: row.title,
              description: row.body,
            ) !=
            null)
          row,
    ];
    return SettingsSectionData(
      icon: item.icon,
      title: item.title,
      entries: [
        _itemEntry(item, rows: matching),
        for (final row in matching)
          calendarGuideReadEntry(
            row,
            identifier: item.rowIdentifier?.call(row.slug),
          ),
      ],
    );
  }

  /// The row that opens [item]'s page. Given the page's [rows], it matches
  /// whatever any of them matches, so a search hit never shows without the
  /// way to its page.
  SettingsEntry _itemEntry(
    GuideHubItem item, {
    List<CalendarGuideRow> rows = const [],
  }) {
    return SettingsEntry(
      title: item.title,
      description: item.caption,
      keywords: [
        ...item.keywords,
        for (final row in rows) ...[row.title, row.body],
      ],
      identifier: item.identifier,
      builder: (context, title, description) => LayoutBuilder(
        builder: (context, constraints) => _HubRow(
          icon: _glyphsFit(context, constraints.maxWidth) ? item.icon : null,
          title: title,
          description: description,
          onTap: () => item.open(context),
        ),
      ),
    );
  }

  /// [_measureGlyphsFit] for the layout path: measured once per set of
  /// inputs.
  bool _glyphsFit(BuildContext context, double width) {
    final searching = widget.query.isNotEmpty;
    final inputs = (
      width: width,
      scaler: MediaQuery.textScalerOf(context),
      locale: Localizations.localeOf(context).toString(),
      density: Theme.of(context).visualDensity.horizontal,
      searching: searching,
    );
    if (inputs == _fitInputs) return _fitAnswer;
    _fitInputs = inputs;
    final titles = [
      for (final item in searching ? _searchItems : _hubItems) item.title,
    ];
    return _fitAnswer = _measureGlyphsFit(context, titles, width);
  }

  /// Whether the longest word of every title shown together fits the title
  /// column a row [width] wide leaves beside the glyph and the chevron. When
  /// one does not, every row drops its glyph together — a word broken
  /// mid-way reads worse than a missing icon, and rows with and without one
  /// would not line up. Every title of the hub's cards is measured, so a row
  /// added to one card changes nothing in the others.
  bool _measureGlyphsFit(
    BuildContext context,
    List<String> titles,
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
