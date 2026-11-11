import 'package:flutter/material.dart';

import '../constants/guide_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/guide_book.dart';
import '../models/guide_content.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/money_display_config.dart';
import 'calendar_guide_rows.dart';
import 'settings_section_list.dart';
import 'simple_markdown_preview.dart';

/// [example] as a kit entry of [book]'s page (`docs/guide-hub-roadmap.md`
/// §4), found by its caption and by its source.
///
/// [moneyConfig] and [colorPalette] are the page's: the preview draws the
/// example the way her notes draw it.
SettingsEntry guideExampleEntry(
  GuideExampleEntry example, {
  required GuideBook book,
  required MoneyDisplayConfig moneyConfig,
  required MarkdownColorPalette colorPalette,
}) {
  return SettingsEntry(
    // The caption is running text under the example, not a row's title: it
    // travels as the description, the read row's paragraph path, so it
    // paints in the paragraph's colour and keeps the search's highlight. The
    // row has no title to show, and the builder draws none.
    title: '',
    description: example.caption,
    descriptionStyle: calendarGuideParagraphStyle,
    keywords: [example.source],
    identifier: SemanticsIds.guideBookExample(book.slug, example.slug),
    builder: (context, title, description) => GuideExampleRow(
      source: example.source,
      caption: description!,
      moneyConfig: moneyConfig,
      colorPalette: colorPalette,
      typedLabel: example.typedLabel,
      shownLabel: example.shownLabel,
    ),
  );
}

/// An example of the markdown: what she types over what the note shows,
/// and a sentence under both (D14).
///
/// The preview is the app's own [SimpleMarkdownPreview], so the guide cannot
/// drift from the renderer. Nothing in it is pressed: every tap callback is
/// left null, so a checkbox or a link in an example is inert.
class GuideExampleRow extends StatelessWidget {
  const GuideExampleRow({
    super.key,
    required this.source,
    required this.caption,
    required this.moneyConfig,
    required this.colorPalette,
    this.typedLabel,
    this.shownLabel,
  });

  final String source;

  /// The kit's description widget in the paragraph style, so the search's
  /// highlight reaches it.
  final Widget caption;

  final MoneyDisplayConfig moneyConfig;
  final MarkdownColorPalette colorPalette;

  /// The two blocks' labels for an example that is not typed into a note
  /// (`docs/guide-hub-roadmap.md` D35); "You type" and "You get" when null.
  final String? typedLabel;
  final String? shownLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Padding(
        padding: GuideMetrics.readRowPadding,
        // A read row's glyph column, so the blocks and the caption start on
        // the edge a read row's title starts on in the same card.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.code_rounded, color: colorScheme.primary),
            ),
            const SizedBox(width: GuideMetrics.readRowGlyphGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Eyebrow(typedLabel ?? l10n.guideExampleTyped),
                  const SizedBox(height: GuideMetrics.exampleLabelGap),
                  _SourceBlock(source),
                  const SizedBox(height: GuideMetrics.exampleBlockGap),
                  _Eyebrow(shownLabel ?? l10n.guideExampleShown),
                  const SizedBox(height: GuideMetrics.exampleLabelGap),
                  _Block(
                    color: colorScheme.surfaceContainerLow,
                    // In dark the low container is 1.05:1 on the card, a
                    // faint hole rather than a box; the shortcut editor's
                    // hairline draws its edge.
                    border: Border.all(color: colorScheme.outlineVariant),
                    child: SimpleMarkdownPreview(
                      data: source,
                      fontSize: GuideMetrics.paragraphFontSize,
                      padding: EdgeInsets.zero,
                      scrollable: false,
                      moneyConfig: moneyConfig,
                      colorPalette: colorPalette,
                    ),
                  ),
                  const SizedBox(height: GuideMetrics.exampleBlockGap),
                  caption,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A block's label in the kit's section-label type, so it sits under the
/// card's header rather than competing with it, and spoken as written.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: RowMetrics.sectionLabelFontSize,
            fontWeight: RowMetrics.sectionLabelFontWeight,
            letterSpacing: RowMetrics.sectionLabelLetterSpacing,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// The markdown as typed, one typed line to one drawn line: a line wider than
/// the block scrolls sideways, since a soft wrap would show a line break
/// that is not in the source.
///
/// It is read as its text; the scroll view stays out of the row's merged
/// node, where it would add scroll actions to a row that is only read.
class _SourceBlock extends StatelessWidget {
  const _SourceBlock(this.source);

  final String source;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: source,
      child: ExcludeSemantics(
        child: _Block(
          color: colorScheme.surfaceContainerHighest,
          // The air moves into the scroll view, so a scrolled line runs to
          // the block's edge instead of being cut inside it.
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(GuideMetrics.examplePadding),
            child: Text(
              source,
              softWrap: false,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: GuideMetrics.exampleSourceFontSize,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One half of the example in the shortcut editor's preview box.
class _Block extends StatelessWidget {
  const _Block({
    required this.color,
    required this.child,
    this.border,
    this.padding = const EdgeInsets.all(GuideMetrics.examplePadding),
  });

  final Color color;
  final BoxBorder? border;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: border,
        borderRadius: BorderRadius.circular(GuideMetrics.exampleRadius),
      ),
      child: child,
    );
  }
}
