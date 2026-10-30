import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../constants/markdown_bar_metrics.dart';
import '../controllers/vocabulary_suggestion_controller.dart';
import '../l10n/app_localizations.dart';
import '../utils/markdown_chip_span.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/vocabulary_matcher.dart';
import 'form_rows.dart' show TapTargetPadding;
import 'markdown_bar.dart';

/// The suggestion pills, shown in place of the markdown toolbar while a
/// vocabulary session is open.
///
/// Deliberately the *same* height as [MarkdownBar]'s normal mode, so a
/// session opening never shifts the editor: the bar lays this over its own
/// hidden normal row, and on its own it is one [MarkdownBar.rowHeight] row
/// inside [MarkdownBarMetrics.verticalPadding]. Capture speed is the whole
/// point of the feature; a toolbar that jumps would cost more than the
/// autocomplete saves. A single-list scope's leading label rides inside that
/// budget, no taller than the pills beside it.
class VocabularySuggestionBar extends StatelessWidget {
  final VocabularySuggestionSession session;
  final ValueChanged<VocabularyCandidate> onAccept;
  final VoidCallback onDismiss;
  final bool showBackground;

  /// The ground under the strip's edge fade, as [MarkdownBar] passes its
  /// own strips: the theme's surface when null.
  final Color? fadeGround;

  /// The colour palette a pill renders its term's markdown with, as the
  /// live editor will once the term is accepted. Null leaves the pills raw:
  /// the editor is showing raw markdown, and a pill should read like the
  /// note it inserts into.
  final MarkdownColorPalette? palette;

  const VocabularySuggestionBar({
    super.key,
    required this.session,
    required this.onAccept,
    required this.onDismiss,
    this.showBackground = true,
    this.fadeGround,
    this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final vocabularyIds = <String>{
      for (final candidate in session.suggestions) candidate.vocabularyId,
    };
    final showSource = vocabularyIds.length > 1;
    // Decided by the typed scope, never by the current matches: a label that
    // came and went as a multi-list scope's matches narrowed would slide
    // every pill sideways between keystrokes. A multi-list scope leans on
    // the pills' second line instead.
    final showScope = session.scopeNames.length == 1;

    return Container(
      decoration: showBackground
          ? AppTheme.editorBarDecoration(theme.colorScheme)
          : null,
      padding: const EdgeInsets.symmetric(
        vertical: MarkdownBarMetrics.verticalPadding,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: MarkdownBarMetrics.suggestionMaxTextScale,
        child: SizedBox(
          height: MarkdownBar.rowHeight,
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => MarkdownBarEdgeFade(
                    ground: fadeGround,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: MarkdownBarMetrics.sidePadding,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showScope)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: MarkdownBarMetrics.suggestionScopeGap,
                              ),
                              child: _ScopeLabel(
                                name: session.scopeNames.single,
                                maxWidth:
                                    constraints.maxWidth *
                                    MarkdownBarMetrics.suggestionScopeMaxShare,
                              ),
                            ),
                          // The gap goes before every pill but the first, so
                          // the strip ends on the side padding alone, as it
                          // starts. Every locale the app ships is LTR.
                          for (final (index, candidate)
                              in session.suggestions.indexed)
                            Padding(
                              padding: EdgeInsets.only(
                                left: index == 0
                                    ? 0
                                    : MarkdownBarMetrics.suggestionPillGap,
                              ),
                              child: _SuggestionPill(
                                candidate: candidate,
                                showSource: showSource,
                                palette: palette,
                                headings: session.atLineStart,
                                onTap: () => onAccept(candidate),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MarkdownBarMetrics.dividerGap,
                ),
                child: const MarkdownBarDivider(),
              ),
              MarkdownBarIconButton(
                icon: Icons.close,
                tooltip: l10n.vocabularySuggestionsDismiss,
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single-list scope's lead: the Lists page's glyph and the list's name
/// at the pills' own size, so the scope reads as part of the strip rather
/// than a caption beside it.
class _ScopeLabel extends StatelessWidget {
  final String name;
  final double maxWidth;

  const _ScopeLabel({required this.name, required this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Icon(
            Icons.format_list_bulleted_rounded,
            size: MarkdownBarMetrics.suggestionScopeGlyphSize,
            color: color,
          ),
        ),
        const SizedBox(width: MarkdownBarMetrics.suggestionScopeGlyphGap),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              height: MarkdownBarMetrics.suggestionLineHeight,
            ),
          ),
        ),
      ],
    );
  }
}

class _SuggestionPill extends StatelessWidget {
  final VocabularyCandidate candidate;
  final bool showSource;
  final MarkdownColorPalette? palette;
  final bool headings;
  final VoidCallback onTap;

  const _SuggestionPill({
    required this.candidate,
    required this.showSource,
    required this.palette,
    required this.headings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // The term at the body's own weight on the bar's own surface, so the
    // chip span's bold, tags, colours and ghosts read as in the note.
    final termStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(
          color: colorScheme.onSurface,
          height: MarkdownBarMetrics.suggestionLineHeight,
        );
    final palette = this.palette;

    return Semantics(
      container: true,
      button: true,
      child: TapTargetPadding(
        minHeight: MarkdownBar.rowHeight,
        // Outlined, not filled: a filled stadium is the app's selected chip.
        child: Material(
          color: Colors.transparent,
          shape: StadiumBorder(
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: MarkdownBarMetrics.suggestionPillMinHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: MarkdownBarMetrics.suggestionPillPadding,
                  vertical: MarkdownBarMetrics.suggestionPillVerticalPadding,
                ),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (palette == null)
                        Text(
                          candidate.term,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: termStyle,
                        )
                      else
                        _RenderedTerm(
                          chip: MarkdownChipSpan.build(
                            term: candidate.term,
                            style: termStyle,
                            theme: theme,
                            palette: palette,
                            headings: headings,
                          ),
                        ),
                      if (showSource)
                        Text(
                          candidate.vocabularyName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: MarkdownBarMetrics.suggestionLineHeight,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill's term line rendered as the live editor will show it. The pill
/// sits in an unbounded horizontal scroller, so the row takes the term's
/// intrinsic width and no flex child; the heading label sits on the term's
/// baseline at a smaller size and the same line height, so it never adds
/// height.
class _RenderedTerm extends StatelessWidget {
  final MarkdownChipSpan chip;

  const _RenderedTerm({required this.chip});

  @override
  Widget build(BuildContext context) {
    final level = chip.headingLevel;
    final term = Text.rich(
      chip.span,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (level == null) return term;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          'H$level',
          semanticsLabel: switch (level) {
            1 => l10n.header1,
            2 => l10n.header2,
            3 => l10n.header3,
            4 => l10n.header4,
            5 => l10n.header5,
            _ => l10n.header6,
          },
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: MarkdownBarMetrics.suggestionLineHeight,
          ),
        ),
        const SizedBox(width: MarkdownBarMetrics.suggestionHeadingLabelGap),
        term,
      ],
    );
  }
}
