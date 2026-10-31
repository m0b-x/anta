import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';
import '../constants/row_metrics.dart';
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

  /// A `SemanticsIds` value for a row a device flow targets, so neither a
  /// copy change nor the locale moves it. The row becomes a container node
  /// rather than a merged one: a tile's tap and text still land on that one
  /// node, while a row holding several controls (a segmented button, a
  /// swatch strip) keeps each control as its own node.
  final String? identifier;

  const SettingsEntry({
    required this.title,
    required this.builder,
    this.description,
    this.keywords = const [],
    this.titleStyle,
    this.descriptionStyle,
    this.identifier,
  });
}

class SettingsSectionData {
  /// Kept for the call sites; the browser's section header draws no glyph,
  /// so the kit no longer shows it.
  final IconData icon;
  final String title;
  final List<SettingsEntry> entries;

  /// Section chrome rather than a row — a preview, an explanatory line.
  /// Shown whenever the section itself is visible, never filtered on its own.
  /// The kit insets it from the group's top edge and sets its text in the
  /// caption role; its sides and its foot are the intro's own.
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

/// How densely the kit sets its rows. Both draw the same groups on the same
/// ground, so a page never looks like a different app for its density.
enum SettingsSectionStyle {
  /// Every settings page but one: 48 dp one-line and 62 dp two-line rows.
  standard,

  /// Developer options: tighter row padding for a page of debugging flags.
  compact,
}

/// Renders settings sections as the browser draws its lists — `rowGroup`
/// groups under the browser's section header on the page ground — filtered
/// by [query].
///
/// One `ListTileTheme` scope styles every entry, so the pages' own
/// `ListTile`s and `SwitchListTile`s take the browser's row heights and
/// type without a page being edited.
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

  /// A semantics id on the list's scrollable, for a device flow that swipes
  /// inside it to reach a row past the cache extent — the page's first
  /// scrollable may be its search field instead.
  final String? listIdentifier;

  const SettingsSectionList({
    super.key,
    required this.sections,
    required this.query,
    this.footer = const [],
    this.header = const [],
    this.padding = const EdgeInsets.all(RowMetrics.groupInset),
    this.style = SettingsSectionStyle.standard,
    this.collapsedSections = const {},
    this.onToggleSection,
    this.listIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final l10n = AppLocalizations.of(context)!;

    final cards = <SettingsSectionCard>[];
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
        SettingsSectionCard._(
          section: section,
          entries: visible,
          collapsed: canFold && collapsedSections.contains(id),
          onToggle: canFold ? () => onToggleSection!(id) : null,
          titleSpans: sectionMatched && query.isNotEmpty
              ? (matchSettingsEntry(query, title: section.title)?.titleSpans ??
                    const [])
              : const [],
        ),
      );
    }

    final Widget list;
    if (cards.isEmpty) {
      list = ListView(
        padding: padding,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: RowMetrics.emptyStatePadding,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_off,
                    size: RowMetrics.emptyStateGlyphSize,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: RowMetrics.gap),
                  Text(
                    l10n.noMatchesFound,
                    style: TextStyle(
                      fontSize: RowMetrics.titleFontSize,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      list = ListView(
        padding: padding,
        children: [
          if (query.isEmpty && header.isNotEmpty) ...[
            ...header,
            const SizedBox(height: RowMetrics.groupGap),
          ],
          // Every header is a 48 dp box whose label sits at its bottom edge,
          // so its own height is the air above it.
          ...cards,
          if (query.isEmpty && footer.isNotEmpty) ...[
            const SizedBox(height: RowMetrics.groupGap),
            ...footer,
          ],
        ],
      );
    }

    final compact = style == SettingsSectionStyle.compact;
    // A `Material`, not a coloured box: the headers' and the rows' ink is
    // drawn on the nearest one, and a box above the scaffold's would hide it.
    return Material(
      color: colorScheme.pageGround,
      child: ListTileTheme(
        data: ListTileThemeData(
          contentPadding: FormMetrics.settingsRowPadding,
          minVerticalPadding: compact
              ? FormMetrics.settingsCompactRowVerticalPadding
              : FormMetrics.settingsRowVerticalPadding,
          minTileHeight: RowMetrics.singleLineMinHeight,
          minLeadingWidth: FormMetrics.settingsLeadingWidth,
          horizontalTitleGap: FormMetrics.settingsTitleGap,
          // Over the theme's body styles: a tile sets these as its text
          // style outright, so a bare style would lose the app's font.
          titleTextStyle: textTheme.bodyLarge
              ?.merge(_entryTitleStyle)
              .copyWith(color: colorScheme.onSurface),
          subtitleTextStyle: textTheme.bodyMedium
              ?.merge(settingsCaptionStyle)
              .copyWith(color: colorScheme.onSurfaceVariant),
          // A value read back beside a title is the caption role, never
          // Material's 11 / 500 label.
          leadingAndTrailingTextStyle: textTheme.bodyMedium
              ?.merge(settingsCaptionStyle)
              .copyWith(color: colorScheme.onSurfaceVariant),
        ),
        child: listIdentifier == null
            ? list
            : Semantics(identifier: listIdentifier, child: list),
      ),
    );
  }
}

/// A settings row's title: the browser's 15 / 400 on the form label's line.
/// Colourless, so a disabled tile's grey still reaches it.
const TextStyle _entryTitleStyle = TextStyle(
  fontSize: RowMetrics.titleFontSize,
  height: FormMetrics.labelLineHeight / RowMetrics.titleFontSize,
  fontWeight: FontWeight.w400,
);

/// A settings row's description, the caption role: 13 / 400 on an 18 px
/// line, colourless. Public for a row that draws a caption of its own beside
/// the kit's descriptions — a slider's draft reading — so the two never
/// differ in size or line.
const TextStyle settingsCaptionStyle = TextStyle(
  fontSize: RowMetrics.secondLineFontSize,
  height: FormMetrics.captionLineHeight / RowMetrics.secondLineFontSize,
  fontWeight: FontWeight.w400,
);

class _VisibleEntry {
  final SettingsEntry entry;
  final SettingsMatch match;

  const _VisibleEntry(this.entry, this.match);
}

/// The kit's group: one section's header over its `rowGroup` rows. Built
/// only by [SettingsSectionList]; public so a test can find a page's groups
/// by type.
class SettingsSectionCard extends StatelessWidget {
  final SettingsSectionData section;
  final List<_VisibleEntry> _entries;
  final List<TextRange> titleSpans;
  final bool collapsed;

  /// Null when this section cannot fold — no chevron, no ink, header not a
  /// button.
  final VoidCallback? onToggle;

  const SettingsSectionCard._({
    required this.section,
    required List<_VisibleEntry> entries,
    required this.titleSpans,
    this.collapsed = false,
    this.onToggle,
  }) : _entries = entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // A folded section builds nothing below its header — the point is to get
    // the rows out of the way, not to hide them while still paying for the
    // previews and sliders inside.
    final Widget body = collapsed
        ? const SizedBox(width: double.infinity)
        : Material(
            type: MaterialType.card,
            clipBehavior: Clip.antiAlias,
            color: colorScheme.rowGroup,
            borderRadius: BorderRadius.circular(RowMetrics.groupRadius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (section.intro case final intro?)
                  // Inset from the group's edge as a row's text is, in the
                  // caption role its descriptions read in.
                  Padding(
                    padding: const EdgeInsets.only(
                      top: FormMetrics.settingsRowVerticalPadding,
                    ),
                    child: DefaultTextStyle.merge(
                      style: settingsCaptionStyle.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      child: intro,
                    ),
                  ),
                for (var i = 0; i < _entries.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: RowMetrics.dividerThickness,
                      thickness: RowMetrics.dividerThickness,
                      indent: RowMetrics.dividerIndentPlain,
                      endIndent: 0,
                      color: colorScheme.rowDivider,
                    ),
                  _buildRow(context, _entries[i], colorScheme),
                ],
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context, theme),
        if (onToggle == null)
          body
        else
          AnimatedSize(
            duration: FormMetrics.settingsFoldDuration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: body,
          ),
      ],
    );
  }

  /// The browser's section label above the group, on the bottom edge of a
  /// 48 dp box whether or not the section folds: the box is the air above
  /// the label, so the gap after a group is one number on every kit page, and
  /// folding only makes the box a target. Heading level 2 is what Android
  /// reads, the header flag what VoiceOver reads.
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      fontSize: RowMetrics.sectionLabelFontSize,
      fontWeight: RowMetrics.sectionLabelFontWeight,
      letterSpacing: RowMetrics.sectionLabelLetterSpacing,
      color: colorScheme.onSurfaceVariant,
    );
    final shown = section.title.toUpperCase();
    // The search's spans are offsets into the title as written; an
    // uppercasing that changes the length ("ß" → "SS") would shift them, so
    // the tint is dropped there rather than painted on the wrong letters.
    final title = Semantics(
      label: section.title,
      child: ExcludeSemantics(
        child: HighlightedText(
          text: shown,
          spans: shown.length == section.title.length ? titleSpans : const [],
          style: labelStyle,
        ),
      ),
    );
    const labelPadding = EdgeInsetsDirectional.only(
      start: RowMetrics.sectionLabelInset,
      bottom: RowMetrics.sectionLabelBottomPadding,
    );

    Widget box(Widget child) => Container(
      constraints: const BoxConstraints(
        minHeight: RowMetrics.singleLineMinHeight,
      ),
      alignment: AlignmentDirectional.bottomStart,
      padding: labelPadding,
      child: child,
    );

    final toggle = onToggle;
    if (toggle == null) {
      return Semantics(
        container: true,
        header: true,
        headingLevel: 2,
        child: box(
          Row(
            children: [
              Expanded(child: title),
              // The chevron's height without its width, so a label that
              // cannot fold sits on the line a folding one does.
              const SizedBox(height: RowMetrics.glyphSize),
            ],
          ),
        ),
      );
    }

    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      container: true,
      button: true,
      expanded: !collapsed,
      header: true,
      headingLevel: 2,
      child: InkWell(
        onTap: toggle,
        borderRadius: BorderRadius.circular(RowMetrics.groupRadius),
        child: box(
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(child: title),
                // Only while shut: a folded title says nothing about how much
                // is behind it, an open one is already showing you.
                if (collapsed)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: RowMetrics.gap,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth:
                            constraints.maxWidth *
                            RowMetrics.settingsCountMaxShare,
                      ),
                      // One line, centred with the chevron: wrapped beside a
                      // two-line title at 2.0 it sat low against both.
                      child: Text(
                        l10n.settingsSectionCollapsedCount(_entries.length),
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: RowMetrics.sectionLabelInset,
                  ),
                  child: AnimatedRotation(
                    turns: collapsed ? 0.0 : 0.5,
                    duration: FormMetrics.settingsFoldDuration,
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: RowMetrics.glyphSize,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    _VisibleEntry visible,
    ColorScheme colorScheme,
  ) {
    final entry = visible.entry;
    final baseDescriptionStyle = settingsCaptionStyle.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    final title = HighlightedText(
      text: entry.title,
      spans: visible.match.titleSpans,
      style: _entryTitleStyle.merge(entry.titleStyle),
    );
    final description = entry.description == null
        ? null
        : HighlightedText(
            text: entry.description!,
            spans: visible.match.descriptionSpans,
            style: baseDescriptionStyle.merge(entry.descriptionStyle),
            followsDisabledTile: true,
          );
    final row = entry.builder(context, title, description);
    final identifier = entry.identifier;
    return identifier == null
        ? row
        : Semantics(container: true, identifier: identifier, child: row);
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

  /// A settings row's description carries the caption's colour, because a
  /// row the kit draws without a tile (a slider, a choice) has no tile to
  /// give it one; inside a disabled `ListTile` that colour would cover the
  /// tile's grey, so here the tile's `disabledColor`, when it is what the
  /// ambient text style holds, wins.
  final bool followsDisabledTile;

  const HighlightedText({
    super.key,
    required this.text,
    this.spans = const [],
    this.style,
    this.maxLines,
    this.overflow,
    this.followsDisabledTile = false,
  });

  @override
  Widget build(BuildContext context) {
    var style = this.style;
    if (followsDisabledTile) {
      final ambient = DefaultTextStyle.of(context).style.color;
      if (ambient != null && ambient == Theme.of(context).disabledColor) {
        style = (style ?? const TextStyle()).copyWith(color: ambient);
      }
    }
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

/// The kit's row for a bounded trailing — a settings tile whose trailing
/// yields to its title.
///
/// `ListTile` lays its trailing out first and gives the title what is left,
/// so a trailing as wide as a sentence — a default alert read back, the
/// holiday set's dropdown, as wide as the widest profile's name — squeezed
/// the title to a letter a line at a large text scale, and at 200 % in
/// German the dropdown took the whole tile and the page would not lay out at
/// all (the Tier 2 device pass). Here the text column's longest word — the
/// title's or the subtitle's — is measured first: [trailing] gets what that
/// leaves beside the title, to wrap or ellipsize in, and goes under the
/// description with the text column's whole width instead when that is under
/// [FormMetrics.settingsValueMinBesideWidth], scaled with the text, or when
/// the value, laid out there, is taller than the
/// tile lets a trailing be ([listTileTrailingCap]). Where everything fits —
/// every row at the scales the page was drawn at — the tile is the stock one
/// it was. A raw `trailing:` wider than a third of the row is the defect this
/// row exists to replace.
class SettingsYieldingTile extends StatelessWidget {
  final Widget leading;
  final Widget title;
  final Widget? subtitle;

  /// The text [trailing] shows, when it shows one — measured for the height
  /// it would take beside the title. Null for a trailing that is one line
  /// whatever its room (the holiday set's dropdown).
  final String? value;

  /// Builds the trailing for the width it may take: what is left beside the
  /// title, or the text column's width under the description.
  final Widget Function(double maxWidth) trailing;
  final VoidCallback? onTap;

  /// `ListTile`'s own geometry, passed to it explicitly so the arithmetic
  /// below reads off the numbers the tile lays out with — the kit's row
  /// padding and its tile theme's leading slot, so this row's edges and
  /// title line up with its neighbours'.
  static const EdgeInsetsDirectional _contentPadding =
      FormMetrics.settingsRowPadding;
  static const double _minLeadingWidth = FormMetrics.settingsLeadingWidth;
  static const double _titleGap = FormMetrics.settingsTitleGap;

  const SettingsYieldingTile({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.value,
    required this.trailing,
    this.onTap,
  });

  /// [text] as the tile lays it out in [style]: the bold-text setting, the
  /// text scale, the direction. The caller lays it out and disposes it.
  static TextPainter _painter(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    var effective = style;
    if (MediaQuery.boldTextOf(context)) {
      effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    return TextPainter(
      text: TextSpan(text: text, style: effective),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    );
  }

  /// The widest run [text] cannot break — its longest word — in [style].
  static double _longestWord(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final painter = _painter(context, text, style)..layout();
    final width = painter.minIntrinsicWidth;
    painter.dispose();
    return width;
  }

  /// The widest run the text column cannot break: the longest word of the
  /// title and of the subtitle, each laid out as the tile lays it out — the
  /// tile's own style under the kit's. The subtitle counts too: a column cut
  /// to the title's word broke "Erinnerung" in the line under it.
  double _columnWordWidth(BuildContext context) {
    final theme = Theme.of(context);
    final tileTheme = ListTileTheme.of(context);
    var widest = 0.0;
    final title = this.title;
    if (title is HighlightedText) {
      widest = _longestWord(
        context,
        title.text,
        (tileTheme.titleTextStyle ??
                theme.textTheme.bodyLarge ??
                const TextStyle())
            .merge(title.style),
      );
    }
    final subtitle = this.subtitle;
    if (subtitle is HighlightedText) {
      final word = _longestWord(
        context,
        subtitle.text,
        (tileTheme.subtitleTextStyle ??
                theme.textTheme.bodyMedium ??
                const TextStyle())
            .merge(subtitle.style),
      );
      if (word > widest) widest = word;
    }
    return widest;
  }

  /// The style the tile gives a trailing, which is what [value] is drawn in
  /// beside the title and, under the description, through
  /// `DefaultTextStyle.merge`.
  static TextStyle? _trailingStyle(BuildContext context) {
    final theme = Theme.of(context);
    return ListTileTheme.of(context).leadingAndTrailingTextStyle ??
        theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
  }

  /// The height [value] takes laid out in [width] beside the title, in the
  /// style the tile gives a trailing; nothing for a trailing with no text.
  double _valueHeight(BuildContext context, double width) {
    final value = this.value;
    if (value == null) return 0;
    final painter = _painter(
      context,
      value,
      _trailingStyle(context) ?? const TextStyle(),
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final column =
            constraints.maxWidth -
            _contentPadding.horizontal -
            _minLeadingWidth -
            _titleGap;
        final beside = column - _columnWordWidth(context) - _titleGap;
        // Beside the title only while the value fits the height the tile
        // gives a trailing: a taller one is cut there, and a line's
        // descenders went first — "Alarm · 7 Tage vorher, 09:00" lost its
        // time at 200 % on the device.
        final minBeside = MediaQuery.textScalerOf(
          context,
        ).scale(FormMetrics.settingsValueMinBesideWidth);
        if (beside >= minBeside &&
            _valueHeight(context, beside) <=
                listTileTrailingCap(context) +
                    FormMetrics.settingsValueCapTolerance) {
          return ListTile(
            contentPadding: _contentPadding,
            minLeadingWidth: _minLeadingWidth,
            horizontalTitleGap: _titleGap,
            leading: leading,
            title: title,
            subtitle: subtitle,
            trailing: trailing(beside),
            onTap: onTap,
          );
        }
        // The style the tile gives a trailing, so the value reads the same
        // under the description as it does beside the title.
        final trailingStyle = _trailingStyle(context);
        return ListTile(
          contentPadding: _contentPadding,
          minLeadingWidth: _minLeadingWidth,
          horizontalTitleGap: _titleGap,
          leading: leading,
          title: title,
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ?subtitle,
              Padding(
                padding: const EdgeInsets.only(
                  top: FormMetrics.settingsValueUnderGap,
                ),
                child: trailingStyle == null
                    ? trailing(column)
                    : DefaultTextStyle.merge(
                        style: trailingStyle,
                        child: trailing(column),
                      ),
              ),
            ],
          ),
          onTap: onTap,
        );
      },
    );
  }
}

/// The tallest `ListTile` lets a trailing be: the one-line tile's height —
/// 48 dense, 56 otherwise — under the theme's visual density. That is the
/// tile's own `_RenderListTile.maxIconHeightConstraint`, which has no public
/// name, so the numbers are copied from it and
/// `calendar_settings_large_text_test` holds them to the constraint a laid-out
/// tile hands its trailing.
@visibleForTesting
double listTileTrailingCap(BuildContext context) {
  final tileTheme = ListTileTheme.of(context);
  final density = tileTheme.visualDensity ?? Theme.of(context).visualDensity;
  final dense = tileTheme.dense ?? false;
  return (dense ? _denseTileHeight : _tileHeight) +
      density.baseSizeAdjustment.dy;
}

/// `ListTile`'s one-line heights, as its `_defaultTileHeight` and the
/// trailing cap both read them.
const double _tileHeight = 56;
const double _denseTileHeight = 48;

/// The kit's one-of-N row. The options sit under the title rather than
/// beside it so three labels still fit on a narrow phone without the row
/// reflowing as the locale changes; side by side while every word fits its
/// segment, stacked otherwise.
Widget settingsChoiceRow<T extends Enum>({
  required Widget title,
  required Widget? description,
  required T value,
  required Map<T, String> labels,
  required ValueChanged<T> onChanged,
}) {
  return Padding(
    padding: FormMetrics.settingsControlRowPadding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        ?description,
        const SizedBox(height: FormMetrics.settingsControlGap),
        LayoutBuilder(
          builder: (context, constraints) {
            // Side by side while every word fits its segment; a segmented
            // button never moves a word to another segment, so a word
            // wider than its third ("Ordner und Notizen" at 200 %) broke
            // mid-word. Stacked, each choice has the row's full width.
            final horizontal = _choiceWordsFit(
              context,
              labels.values,
              constraints.maxWidth / labels.length,
            );
            return SizedBox(
              width: double.infinity,
              child: SegmentedButton<T>(
                direction: horizontal ? Axis.horizontal : Axis.vertical,
                // A stadium as tall as three stacked choices reads as one
                // big pill; stacked, the group takes the menu's corners.
                style: horizontal
                    ? null
                    : const ButtonStyle(
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(
                              Radius.circular(FormMetrics.menuRadius),
                            ),
                          ),
                        ),
                      ),
                showSelectedIcon: false,
                segments: [
                  for (final entry in labels.entries)
                    ButtonSegment<T>(
                      value: entry.key,
                      label: Text(entry.value, textAlign: TextAlign.center),
                    ),
                ],
                selected: {value},
                onSelectionChanged: (selection) => onChanged(selection.first),
              ),
            );
          },
        ),
      ],
    ),
  );
}

/// The spaces the line breaker breaks at: the no-break ones (U+00A0,
/// U+2007, U+202F) hold their words together, so a word is measured with
/// them.
final RegExp _breakingSpaces = RegExp(
  '[ \\t\\n\\u1680\\u2000-\\u2006\\u2008-\\u200A\\u205F\\u3000]+',
);

/// Material's padding around a text button's label at 1×, 2× and 3× its
/// label size (`ButtonStyleButton.scaledPadding`), which a label-only
/// segment draws inside, and the label size those steps scale from.
const EdgeInsets _segmentPadding1x = EdgeInsets.symmetric(horizontal: 12);
const EdgeInsets _segmentPadding2x = EdgeInsets.symmetric(horizontal: 8);
const EdgeInsets _segmentPadding3x = EdgeInsets.symmetric(horizontal: 4);
const double _segmentLabelSize = 14;

/// An exact fit can still wrap in the engine, so a word needs this much to
/// spare.
const double _wordFitTolerance = 0.5;

/// Whether every word of [labels] fits a segment [segmentWidth] wide on one
/// line, measured as a label-only segment draws it: the theme's `labelLarge`
/// inside the text button padding Material scales with the text size.
bool _choiceWordsFit(
  BuildContext context,
  Iterable<String> labels,
  double segmentWidth,
) {
  final style = Theme.of(context).textTheme.labelLarge;
  final textScaler = MediaQuery.textScalerOf(context);
  final fontSize = style?.fontSize ?? _segmentLabelSize;
  final padding = ButtonStyleButton.scaledPadding(
    _segmentPadding1x,
    _segmentPadding2x,
    _segmentPadding3x,
    textScaler.scale(fontSize) / _segmentLabelSize,
  ).resolve(Directionality.of(context));
  final room = segmentWidth - padding.horizontal;
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: textScaler,
    maxLines: 1,
  );
  try {
    for (final label in labels) {
      for (final word in label.split(_breakingSpaces)) {
        painter
          ..text = TextSpan(text: word, style: style)
          ..layout();
        if (room - painter.width < _wordFitTolerance) return false;
      }
    }
    return true;
  } finally {
    painter.dispose();
  }
}

/// The kit's slider row for a value written on every tick (App settings'
/// auto-save interval and preview chunk size; `SliderSettingRow` is the one
/// that holds a draft). One node to a screen reader — the title and the
/// slider merged — whose value is [semanticValue], the number with its unit,
/// where the slider alone would say a percentage. The caption says the same
/// sentence, so it is left out of the node rather than read twice.
Widget settingsSliderRow({
  required Widget title,
  required Widget? description,
  required double value,
  required double min,
  required double max,
  required int divisions,
  required ValueChanged<double> onChanged,
  required String Function(int value) semanticValue,
  String Function(int)? labelBuilder,
  bool enabled = true,
}) {
  return MergeSemantics(
    child: Padding(
      padding: FormMetrics.settingsControlRowPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          if (description != null) ExcludeSemantics(child: description),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: labelBuilder != null
                ? labelBuilder(value.round())
                : '${value.round()}',
            semanticFormatterCallback: (value) => semanticValue(value.round()),
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    ),
  );
}
