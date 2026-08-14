import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/optimized_note/optimized_note_bloc.dart';
import '../bloc/optimized_note/optimized_note_event.dart';
import '../bloc/optimized_note/optimized_note_state.dart';
import '../l10n/app_localizations.dart';
import '../models/note_metadata.dart';
import '../services/folder_search_service.dart';
import '../services/app_navigator.dart';
import '../widgets/unified_app_bars.dart';

class SearchPage extends StatefulWidget {
  final String? folderId;

  /// When set, the search field opens pre-filled with this query and the
  /// search runs immediately (used by `#tag` taps from the preview).
  final String? initialQuery;

  const SearchPage({super.key, this.folderId, this.initialQuery});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _searchController.text = initial;
      // Run the tag query straight away. _onQuickSearchNotes queries the
      // DB itself, so pre-loading all notes would only flash the full
      // list before the filtered results replace it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<OptimizedNoteBloc>().add(
          QuickSearchNotes(query: initial, folderId: widget.folderId),
        );
      });
    } else {
      _loadAllNotes();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  void _loadAllNotes() {
    context.read<OptimizedNoteBloc>().add(
      LoadNotesPaginated(folderId: widget.folderId),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      _loadAllNotes();
      return;
    }

    context.read<OptimizedNoteBloc>().add(
      QuickSearchNotes(query: query, folderId: widget.folderId),
    );
  }

  void _onSearchSubmitted(String query) {
    if (query.trim().isEmpty) return;

    context.read<OptimizedNoteBloc>().add(
      SearchNotes(query: query, folderId: widget.folderId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SearchAppBar(
        controller: _searchController,
        focusNode: _focusNode,
        hintText: AppLocalizations.of(context)!.search,
        onChanged: _onSearchChanged,
        onSubmitted: _onSearchSubmitted,
        onClear: () {
          _searchController.clear();
          _onSearchChanged('');
        },
      ),
      body: SafeArea(
        top: false,
        child: BlocBuilder<OptimizedNoteBloc, OptimizedNoteState>(
          builder: (context, state) {
            if (state is OptimizedNoteSearchResults) {
              if (state.isSearching) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state.results.isEmpty && state.query.isNotEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!.noSearchResults,
                        style: TextStyle(
                          fontSize: 18,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: state.results.length,
                itemBuilder: (context, index) {
                  final result = state.results[index];
                  return _SearchResultCard(
                    result: result,
                    query: state.query,
                    folderId: widget.folderId,
                  );
                },
              );
            }

            if (state is OptimizedNoteLoaded) {
              final notes = state.paginatedNotes.notes;

              if (notes.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.note_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!.emptyNotesHint,
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: notes.length,
                itemBuilder: (context, index) {
                  final note = notes[index];
                  return _NoteCard(metadata: note, folderId: widget.folderId);
                },
              );
            }

            if (state is OptimizedNoteLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.searchHint,
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final SearchResult result;
  final String query;
  final String? folderId;

  const _SearchResultCard({
    required this.result,
    required this.query,
    this.folderId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: const Icon(Icons.note, size: 40, color: Colors.blue),
        title: _buildHighlightedTitle(context),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result.matches.isNotEmpty) ...[
              const SizedBox(height: 4),
              _buildMatchPreview(context),
            ],
            const SizedBox(height: 4),
            Text(
              _formatDate(result.metadata.updatedAt),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
        onTap: () => _navigateToNote(context),
      ),
    );
  }

  Widget _buildHighlightedTitle(BuildContext context) {
    final title = result.metadata.title.isEmpty
        ? AppLocalizations.of(context)!.untitledNote
        : result.metadata.title;

    return _buildHighlightedText(
      context,
      title,
      query,
      const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
    );
  }

  Widget _buildMatchPreview(BuildContext context) {
    final contentMatches = result.matches
        .where((m) => m.type == SearchMatchType.content)
        .take(2)
        .toList();

    if (contentMatches.isEmpty) {
      return Text(
        result.metadata.preview,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: contentMatches.map((match) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _buildHighlightedText(
            context,
            '...${match.text}...',
            query,
            const TextStyle(fontSize: 14),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHighlightedText(
    BuildContext context,
    String text,
    String query,
    TextStyle baseStyle,
  ) {
    if (query.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }

      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: TextStyle(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      );

      start = index + query.length;
    }

    return RichText(
      text: TextSpan(
        style: baseStyle.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
        children: spans,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _navigateToNote(BuildContext context) {
    AppNavigator.toNoteEditor(
      context,
      folderId: folderId ?? result.metadata.folderId,
      noteId: result.metadata.id,
      metadata: result.metadata,
    );
  }
}

class _NoteCard extends StatelessWidget {
  final NoteMetadata metadata;
  final String? folderId;

  const _NoteCard({required this.metadata, this.folderId});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: const Icon(Icons.note, size: 40, color: Colors.blue),
        title: Text(
          metadata.title.isEmpty ? l10n.untitledNote : metadata.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (metadata.preview.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                metadata.preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              _formatDate(metadata.updatedAt),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
        onTap: () => _navigateToNote(context),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _navigateToNote(BuildContext context) {
    AppNavigator.toNoteEditor(
      context,
      folderId: folderId ?? metadata.folderId,
      noteId: metadata.id,
      metadata: metadata,
    );
  }
}
