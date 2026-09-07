import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/search/search_bloc.dart';
import '../constants/app_icon_sizes.dart';
import '../constants/app_spacing.dart';
import '../l10n/app_localizations.dart';
import '../models/note_metadata.dart';
import '../models/search_scope.dart';
import '../services/app_navigator.dart';
import '../services/folder_search_service.dart';
import 'content_rows.dart';

const String _pathSeparator = ' › ';

/// The body of the search surface: scope chips, then whatever the current
/// phase has to show.
///
/// Everything below is built as **slivers** even though the standalone route
/// only needs a box, so hosting the same content under the browser's sliver
/// app bar costs a different outer scroll view and nothing else. The chips
/// are a widget of their own for the same reason: in place they belong beside
/// the field, not at the top of the list.
class SearchSurface extends StatelessWidget {
  /// The folder half of the scope choice, or null for the two hosts that have
  /// no second scope to offer — the root, and a `#tag` tap, both of which are
  /// already searching everywhere. Held here rather than read off the state
  /// so the folder chip survives switching to Everywhere and back.
  final FolderScope? folderScope;

  const SearchSurface({super.key, this.folderScope});

  @override
  Widget build(BuildContext context) {
    final folderScope = this.folderScope;
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        return CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          slivers: [
            if (folderScope != null)
              SliverToBoxAdapter(
                child: SearchScopeChips(
                  folderScope: folderScope,
                  selected: state.scope,
                ),
              ),
            ...resultSlivers(context, state),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
          ],
        );
      },
    );
  }

  /// The result region on its own, so a host that supplies its own app bar
  /// sliver and chip placement can splice it into that scroll view.
  static List<Widget> resultSlivers(BuildContext context, SearchState state) {
    final l10n = AppLocalizations.of(context)!;

    // Before the "nothing found" check, so a pass that is still running never
    // flashes an empty-result message on its way to results.
    if (state.isSearching && !state.hasResults) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (state.phase == SearchPhase.idle) {
      if (state.recents.isEmpty) {
        return [_messageSliver(context, Icons.search, l10n.searchHint)];
      }
      return [
        SliverToBoxAdapter(child: ContentSectionHeader(label: l10n.recent)),
        _rowsSliver(
          state.recents.length,
          (index) => SearchResultRow(
            metadata: state.recents[index],
            groupPosition: _positionFor(index, state.recents.length),
            path: state.folderPaths[state.recents[index].folderId],
          ),
        ),
      ];
    }

    if (!state.hasResults) {
      return [_messageSliver(context, Icons.search_off, l10n.noSearchResults)];
    }

    final showLabels =
        state.titleHits.isNotEmpty && state.contentHits.isNotEmpty;

    return [
      if (showLabels && state.titleHits.isNotEmpty)
        SliverToBoxAdapter(
          child: ContentSectionHeader(label: l10n.titlesSection),
        ),
      if (state.titleHits.isNotEmpty)
        _hitsSliver(state, state.titleHits, matchType: SearchMatchType.title),
      if (showLabels && state.contentHits.isNotEmpty)
        SliverToBoxAdapter(
          child: ContentSectionHeader(label: l10n.inTextSection),
        ),
      if (state.contentHits.isNotEmpty)
        _hitsSliver(
          state,
          state.contentHits,
          matchType: SearchMatchType.content,
        ),
    ];
  }

  static Widget _hitsSliver(
    SearchState state,
    List<SearchResult> hits, {
    required SearchMatchType matchType,
  }) {
    return _rowsSliver(hits.length, (index) {
      final hit = hits[index];
      return SearchResultRow(
        metadata: hit.metadata,
        groupPosition: _positionFor(index, hits.length),
        path: state.folderPaths[hit.metadata.folderId],
        titleMatch: _firstMatch(hit, SearchMatchType.title),
        snippet: matchType == SearchMatchType.content
            ? _firstMatch(hit, SearchMatchType.content)
            : null,
      );
    });
  }

  static Widget _rowsSliver(int count, Widget Function(int index) builder) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => builder(index),
        childCount: count,
      ),
    );
  }

  static SearchMatch? _firstMatch(SearchResult result, SearchMatchType type) {
    for (final match in result.matches) {
      if (match.type == type) return match;
    }
    return null;
  }

  static RowGroupPosition _positionFor(int index, int count) {
    if (count == 1) return RowGroupPosition.single;
    if (index == 0) return RowGroupPosition.first;
    if (index == count - 1) return RowGroupPosition.last;
    return RowGroupPosition.middle;
  }

  static Widget _messageSliver(
    BuildContext context,
    IconData icon,
    String message,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: AppIconSizes.extraLarge,
              color: colorScheme.outline,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(message, style: TextStyle(color: colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}

/// The folder's name and "Everywhere". Only ever two chips: the scope the
/// surface was opened on, and the whole app.
class SearchScopeChips extends StatelessWidget {
  /// What a host with a fixed box to fill has to reserve — the browser's
  /// in-place bar puts this row in its `bottom`, which wants a height up
  /// front. One chip at the default padded tap target plus the row's own top
  /// padding.
  static const double preferredHeight = 48 + AppSpacing.md;

  /// The folder chip's scope, fixed for the life of the surface.
  final FolderScope folderScope;

  /// Which of the two is currently searching.
  final SearchScope selected;

  const SearchScopeChips({
    super.key,
    required this.folderScope,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isFolder = selected is FolderScope;
    final label = folderScope.name.trim().isEmpty
        ? l10n.thisFolder
        : folderScope.name;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          ChoiceChip(
            label: Text(label),
            selected: isFolder,
            onSelected: (_) =>
                context.read<SearchBloc>().add(SearchScopeChanged(folderScope)),
          ),
          ChoiceChip(
            label: Text(l10n.everywhere),
            selected: !isFolder,
            onSelected: (_) => context.read<SearchBloc>().add(
              const SearchScopeChanged(SearchScope.everywhere()),
            ),
          ),
        ],
      ),
    );
  }
}

/// A note in the search surface, in the browser's row shell so a result reads
/// like the same object the list below it shows.
///
/// The extra line search needs — where the note lives, and the text that
/// matched — is why this is not [NoteRow] itself: that row's second line is
/// the edit date joined to the stored preview, and a result has two more
/// things to say in the same space.
class SearchResultRow extends StatelessWidget {
  final NoteMetadata metadata;
  final RowGroupPosition groupPosition;

  /// Folder path segments, root-first, or null when the folder is unknown.
  final List<String>? path;

  /// Where the query hit the title, for highlighting it in place.
  final SearchMatch? titleMatch;

  /// The body excerpt to show under the title, with its own highlight.
  final SearchMatch? snippet;

  const SearchResultRow({
    super.key,
    required this.metadata,
    required this.groupPosition,
    this.path,
    this.titleMatch,
    this.snippet,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final title = metadata.title.isEmpty ? l10n.untitledNote : metadata.title;
    final pathLabel = path == null || path!.isEmpty
        ? null
        : path!.join(_pathSeparator);

    return ContentRowShell(
      position: groupPosition,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        leading: Icon(
          Icons.description_outlined,
          color: colorScheme.onSurfaceVariant,
        ),
        title: _highlighted(
          context,
          text: title,
          match: metadata.title.isEmpty ? null : titleMatch,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          maxLines: 1,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pathLabel != null)
              Text(
                pathLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            if (snippet != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: _highlighted(
                  context,
                  text: snippet!.text,
                  match: snippet,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                  maxLines: 2,
                ),
              ),
          ],
        ),
        onTap: () => AppNavigator.toNoteEditorInstant(
          context,
          folderId: metadata.folderId,
          noteId: metadata.id,
          metadata: metadata,
        ),
      ),
    );
  }

  /// Paints [text] with the span [match] covers picked out.
  ///
  /// The offsets come straight off the grammar-free [SearchMatch] the service
  /// produced, so nothing here re-scans the text for the query — that is what
  /// used to let the title highlight and the body highlight disagree about
  /// diacritics.
  Widget _highlighted(
    BuildContext context, {
    required String text,
    required SearchMatch? match,
    required TextStyle style,
    required int maxLines,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolved = style.copyWith(
      color: style.color ?? colorScheme.onSurface,
    );

    if (match == null ||
        match.startIndex < 0 ||
        match.endIndex > text.length ||
        match.startIndex >= match.endIndex) {
      return Text(
        text,
        style: resolved,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Text.rich(
      TextSpan(
        style: resolved,
        children: [
          TextSpan(text: text.substring(0, match.startIndex)),
          TextSpan(
            text: text.substring(match.startIndex, match.endIndex),
            style: TextStyle(
              backgroundColor: colorScheme.primaryContainer,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          TextSpan(text: text.substring(match.endIndex)),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
