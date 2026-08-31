import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../controllers/vocabulary_suggestion_controller.dart';
import '../l10n/app_localizations.dart';
import '../utils/vocabulary_matcher.dart';

/// The suggestion pills, shown in place of the markdown toolbar while a
/// vocabulary session is open.
///
/// Deliberately the *same* height as [MarkdownBar]'s normal mode — 40 px of
/// content inside 8 px of vertical padding — so a session opening never shifts
/// the editor. Capture speed is the whole point of the feature; a toolbar that
/// jumps would cost more than the autocomplete saves. A scoped session's
/// leading label rides inside that budget, shorter than the pills beside it.
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

  static const double _pillHeight = 40.0;

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
          ? BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            )
          : null,
      padding: const EdgeInsets.symmetric(
        vertical: AppConstants.markdownToolbarPadding,
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (session.scopeNames.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
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
                      padding: const EdgeInsets.only(right: 6),
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
            height: 24,
            color: theme.colorScheme.outlineVariant,
          ),
          Tooltip(
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
                  size: AppConstants.markdownToolbarIconSize,
                ),
              ),
            ),
          ),
        ],
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

    return Material(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          height: VocabularySuggestionBar._pillHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
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
                      alpha: 0.7,
                    ),
                    height: 1.1,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
