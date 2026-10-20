import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../constants/markdown_bar_metrics.dart';
import '../controllers/vocabulary_suggestion_controller.dart';
import '../l10n/app_localizations.dart';
import '../utils/vocabulary_matcher.dart';
import 'markdown_bar.dart';

/// The suggestion pills, shown in place of the markdown toolbar while a
/// vocabulary session is open.
///
/// Deliberately the *same* height as [MarkdownBar]'s normal mode, so a
/// session opening never shifts the editor: the bar lays this over its own
/// hidden normal row, and on its own it is one [MarkdownBar.rowHeight] row
/// inside [MarkdownBarMetrics.verticalPadding]. Capture speed is the whole
/// point of the feature; a toolbar that jumps would cost more than the
/// autocomplete saves. A scoped session's leading label rides inside that
/// budget, shorter than the pills beside it.
class VocabularySuggestionBar extends StatelessWidget {
  final VocabularySuggestionSession session;
  final ValueChanged<VocabularyCandidate> onAccept;
  final VoidCallback onDismiss;
  final bool showBackground;

  const VocabularySuggestionBar({
    super.key,
    required this.session,
    required this.onAccept,
    required this.onDismiss,
    this.showBackground = true,
  });

  static const double _pillHeight = MarkdownBar.rowHeight;

  /// The largest text scale whose two pill lines (the term and its list's
  /// name) still fit the pill, kept at what the 40 px pill allowed. Past it
  /// the pill would clip its text or, unpinned, grow the row the markdown
  /// bar shares.
  static const double _maxTextScale = 1.4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final vocabularyIds = <String>{
      for (final candidate in session.suggestions) candidate.vocabularyId,
    };
    final showSource = vocabularyIds.length > 1;

    return Container(
      decoration: showBackground
          ? AppTheme.editorBarDecoration(theme.colorScheme)
          : null,
      padding: const EdgeInsets.symmetric(
        vertical: MarkdownBarMetrics.verticalPadding,
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: _maxTextScale,
        child: SizedBox(
          height: _pillHeight,
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: MarkdownBarMetrics.sidePadding,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (session.scopeNames.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                            right: MarkdownBarMetrics.suggestionScopeGap,
                          ),
                          child: Text(
                            session.scopeNames.join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      for (final candidate in session.suggestions)
                        Padding(
                          padding: const EdgeInsets.only(
                            right: MarkdownBarMetrics.suggestionPillGap,
                          ),
                          child: _SuggestionPill(
                            candidate: candidate,
                            showSource: showSource,
                            onTap: () => onAccept(candidate),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                width: 1,
                height: MarkdownBarMetrics.dividerHeight,
                color: theme.colorScheme.outlineVariant,
              ),
              // A button to a screen reader, as every bar button is: this
              // row stands in for the bar.
              Semantics(
                container: true,
                button: true,
                child: Tooltip(
                  message: l10n.vocabularySuggestionsDismiss,
                  preferBelow: false,
                  child: InkWell(
                    onTap: onDismiss,
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: _pillHeight,
                      height: _pillHeight,
                      child: Icon(
                        Icons.close,
                        size: MarkdownBarMetrics.glyphSize,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionPill extends StatelessWidget {
  final VocabularyCandidate candidate;
  final bool showSource;
  final VoidCallback onTap;

  const _SuggestionPill({
    required this.candidate,
    required this.showSource,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(
      VocabularySuggestionBar._pillHeight / 2,
    );

    return Semantics(
      container: true,
      button: true,
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            height: VocabularySuggestionBar._pillHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: MarkdownBarMetrics.suggestionPillPadding,
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.term,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
                if (showSource)
                  Text(
                    candidate.vocabularyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer.withValues(
                        alpha: MarkdownBarMetrics.suggestionSourceAlpha,
                      ),
                      height: 1.1,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
