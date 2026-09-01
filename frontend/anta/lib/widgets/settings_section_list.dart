import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/settings_search.dart';

/// Builds one settings row. [title] and [description] arrive pre-rendered
/// with the current search highlighted, so the row keeps its own widget type
/// — `SwitchListTile`, a `ListTile` with a dropdown, anything — instead of
/// being flattened into a common shape. Rows with no text slot (a preview,
/// a cluster of controls) simply ignore both and still stay searchable
/// through [SettingsEntry.title].
typedef SettingsRowBuilder =
    Widget Function(BuildContext context, Widget title, Widget? description);

class SettingsEntry {
  /// Searchable, and rendered into [SettingsRowBuilder]'s `title`.
  final String title;

  /// Searchable, and rendered into [SettingsRowBuilder]'s `description`.
  final String? description;

  /// Extra search terms that are matched but never shown — the thing that
  /// lets "vibration" find "Haptic feedback".
  final List<String> keywords;

  final SettingsRowBuilder builder;

  /// Merged over the default title style — lets a destructive row stay red,
  /// or a sub-heading stay muted, without giving up highlighting.
  final TextStyle? titleStyle;
  final TextStyle? descriptionStyle;

  const SettingsEntry({
    required this.title,
    required this.builder,
    this.description,
    this.keywords = const [],
    this.titleStyle,
    this.descriptionStyle,
  });
}

class SettingsSectionData {
  final IconData icon;
  final String title;
  final List<SettingsEntry> entries;

  /// Section chrome rather than a row — a preview, an explanatory line.
  /// Shown whenever the section itself is visible, never filtered on its own.
  final Widget? intro;

  /// Stable, unlocalized identity used to remember whether the section is
  /// folded. It is persisted, so it must outlive title rewrites and
  /// reordering — never derive it from [title] or from the list index. A
  /// section without one simply cannot fold.
  final String? id;

  const SettingsSectionData({
    required this.icon,
    required this.title,
    required this.entries,
    this.intro,
    this.id,
  });
}

/// The two settings card looks already in the app. Sharing one renderer must
/// not silently restyle a page, so each keeps its own chrome.
enum SettingsSectionStyle {
  /// Controls and Calendar: filled `surfaceContainer` card, radius 16, icon
  /// in a tinted chip, `onSurface` heading.
  standard,

  /// Developer options: bordered `surfaceContainerHigh` card, radius 12,
  /// bare icon, `primary` heading, denser rows.
  compact,
}

/// Renders settings section cards, filtered by [query].
///
/// Dividers are inserted between *visible* rows only, so filtering can never
/// leave an orphan rule; sections whose rows all filter out disappear.
class SettingsSectionList extends StatelessWidget {
  final List<SettingsSectionData> sections;
  final SettingsQuery query;

  /// Trailing content (reset buttons and the like). Hidden while filtering —
  /// a "reset everything" button under three matched rows reads as if it
  /// applies to them.
  final List<Widget> footer;

  /// Content rendered above the first section, filtered out while searching
  /// (a warning banner has nothing to do with the rows you searched for).
  final List<Widget> header;

  final EdgeInsets padding;

  final SettingsSectionStyle style;

  /// Ids of the sections currently folded shut. Held by the page, which also
  /// persists it — the list itself is stateless so a rebuild can never lose
  /// or invent a fold.
  final Set<String> collapsedSections;

  /// Called with a section's id when its header is tapped. Folding is off
  /// entirely while this is null, which is what keeps the pages that never
  /// asked for it rendering exactly as before.
  final ValueChanged<String>? onToggleSection;

  const SettingsSectionList({
    super.key,
    required this.sections,
    required this.query,
    this.footer = const [],
    this.header = const [],
    this.padding = const EdgeInsets.all(16),
    this.style = SettingsSectionStyle.standard,
    this.collapsedSections = const {},
    this.onToggleSection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final cards = <Widget>[];
    for (final section in sections) {
      final sectionMatched = matchesSettingsQuery(query, [section.title]);
      final visible = <_VisibleEntry>[];
      for (final entry in section.entries) {
        final match = matchSettingsEntry(
          query,
          title: entry.title,
          description: entry.description,
          keywords: entry.keywords,
          sectionMatched: sectionMatched,
        );
        if (match != null) visible.add(_VisibleEntry(entry, match));
      }
      if (visible.isEmpty) continue;

      final id = section.id;
      final foldable = onToggleSection != null && id != null;
      // A fold may never swallow a search hit: while filtering, every
      // surviving section renders open and loses its chevron. The stored
      // fold is untouched, so it comes back when the query is cleared.
      final canFold = foldable && query.isEmpty;

      cards.add(
        _SectionCard(
          section: section,
          entries: visible,
          style: style,
          collapsed: canFold && collapsedSections.contains(id),
          onToggle: canFold ? () => onToggleSection!(id) : null,
          titleSpans: sectionMatched && query.isNotEmpty
              ? (matchSettingsEntry(query, title: section.title)?.titleSpans ??
                    const [])
              : const [],
        ),
      );
    }

    if (cards.isEmpty) {
      return ListView(
        padding: padding,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 48,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.noMatchesFound,
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: padding,
      children: [
        if (query.isEmpty && header.isNotEmpty) ...[
          ...header,
          const SizedBox(height: 16),
        ],
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          cards[i],
        ],
        if (query.isEmpty && footer.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...footer,
        ],
      ],
    );
  }
}

/// Long enough to read as one motion, short enough that a fold never feels
/// like waiting for the row you were reaching for.
const Duration _foldDuration = Duration(milliseconds: 180);

class _VisibleEntry {
  final SettingsEntry entry;
  final SettingsMatch match;

  const _VisibleEntry(this.entry, this.match);
}

class _SectionCard extends StatelessWidget {
  final SettingsSectionData section;
  final List<_VisibleEntry> entries;
  final List<TextRange> titleSpans;
  final SettingsSectionStyle style;
  final bool collapsed;

  /// Null when this section cannot fold — no chevron, no ink, header not a
  /// button.
  final VoidCallback? onToggle;

  const _SectionCard({
    required this.section,
    required this.entries,
    required this.titleSpans,
    required this.style,
    this.collapsed = false,
    this.onToggle,
  });

  bool get _isCompact => style == SettingsSectionStyle.compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final radius = _isCompact ? 12.0 : 16.0;

    Widget header = Padding(
      padding: _isCompact
          ? const EdgeInsets.fromLTRB(16, 16, 16, 8)
          : const EdgeInsets.all(16),
      child: Row(
        children: [
          if (_isCompact)
            Icon(section.icon, size: 20, color: colorScheme.primary)
          else
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(section.icon, size: 20, color: colorScheme.primary),
            ),
          SizedBox(width: _isCompact ? 8 : 12),
          Expanded(
            child: HighlightedText(
              text: section.title,
              spans: titleSpans,
              style: _isCompact
                  ? TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    )
                  : TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
            ),
          ),
          if (onToggle != null) ...[
            // Only while shut: a folded title says nothing about how much is
            // behind it, an open one is already showing you.
            if (collapsed)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  l10n.settingsSectionCollapsedCount(entries.length),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            AnimatedRotation(
              turns: collapsed ? 0.0 : 0.5,
              duration: _foldDuration,
              curve: Curves.easeOutCubic,
              child: Icon(
                Icons.expand_more_rounded,
                size: 22,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );

    if (onToggle != null) {
      header = Semantics(
        button: true,
        expanded: !collapsed,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
          child: header,
        ),
      );
    }

    // A folded section builds nothing below its header — the point is to get
    // the rows out of the way, not to hide them while still paying for the
    // previews and sliders inside.
    final Widget body = collapsed
        ? const SizedBox(width: double.infinity)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ?section.intro,
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _buildRow(context, entries[i], colorScheme),
              ],
              if (_isCompact) const SizedBox(height: 8),
            ],
          );

    return Card(
      elevation: 0,
      color: _isCompact
          ? colorScheme.surfaceContainerHigh
          : colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: _isCompact
            ? BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              )
            : BorderSide.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          if (onToggle == null)
            body
          else
            AnimatedSize(
              duration: _foldDuration,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: body,
            ),
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    _VisibleEntry visible,
    ColorScheme colorScheme,
  ) {
    final entry = visible.entry;
    final baseTitleStyle = _isCompact
        ? const TextStyle(fontSize: 14)
        : const TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
    final baseDescriptionStyle = TextStyle(
      fontSize: 12,
      color: colorScheme.onSurfaceVariant,
    );

    final title = HighlightedText(
      text: entry.title,
      spans: visible.match.titleSpans,
      style: baseTitleStyle.merge(entry.titleStyle),
    );
    final description = entry.description == null
        ? null
        : HighlightedText(
            text: entry.description!,
            spans: visible.match.descriptionSpans,
            style: baseDescriptionStyle.merge(entry.descriptionStyle),
          );
    return entry.builder(context, title, description);
  }
}

/// Text with the matched ranges tinted. [spans] are source offsets, already
/// merged and mapped back through the diacritics fold by `settings_search`.
class HighlightedText extends StatelessWidget {
  final String text;
  final List<TextRange> spans;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const HighlightedText({
    super.key,
    required this.text,
    this.spans = const [],
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    if (spans.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final colorScheme = Theme.of(context).colorScheme;
    final highlight = TextStyle(
      backgroundColor: colorScheme.primaryContainer,
      color: colorScheme.onPrimaryContainer,
      fontWeight: FontWeight.w700,
    );

    final children = <TextSpan>[];
    var cursor = 0;
    for (final span in spans) {
      final start = span.start.clamp(0, text.length);
      final end = span.end.clamp(0, text.length);
      if (start >= end || start < cursor) continue;
      if (start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, start)));
      }
      children.add(
        TextSpan(text: text.substring(start, end), style: highlight),
      );
      cursor = end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(children: children),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
