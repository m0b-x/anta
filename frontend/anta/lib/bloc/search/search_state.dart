import 'package:equatable/equatable.dart';

import '../../models/note_metadata.dart';
import '../../models/search_scope.dart';
import '../../services/folder_search_service.dart';

/// Which pass produced what is on screen.
enum SearchPhase {
  /// Nothing typed: the surface shows recently edited notes.
  idle,

  /// Per-keystroke title-and-preview pass.
  quick,

  /// Submitted: the indexed search over note bodies.
  full,
}

/// One state object rather than a sealed hierarchy: the surface renders the
/// same three regions in every phase (scope chips, a section of title hits, a
/// section of body hits), and a hierarchy would have every case re-declaring
/// the scope and query that persist across all of them.
final class SearchState extends Equatable {
  final SearchScope scope;
  final String query;
  final SearchPhase phase;

  /// Recently edited notes, shown while [phase] is [SearchPhase.idle].
  /// Deliberately unscoped — recents answer "what was I just in", which the
  /// scope chips have no bearing on.
  final List<NoteMetadata> recents;

  /// Hits whose match is in the title. A note matching in both places is
  /// listed here only, so nothing appears twice.
  final List<SearchResult> titleHits;

  /// Hits whose match is only in the body (or the preview, in the quick pass).
  final List<SearchResult> contentHits;

  /// Folder id -> path segments, root-first and including the folder's own
  /// name, for every row currently listed.
  final Map<String, List<String>> folderPaths;

  final bool isSearching;

  const SearchState({
    this.scope = const SearchScope.everywhere(),
    this.query = '',
    this.phase = SearchPhase.idle,
    this.recents = const [],
    this.titleHits = const [],
    this.contentHits = const [],
    this.folderPaths = const {},
    this.isSearching = false,
  });

  bool get hasResults => titleHits.isNotEmpty || contentHits.isNotEmpty;

  SearchState copyWith({
    SearchScope? scope,
    String? query,
    SearchPhase? phase,
    List<NoteMetadata>? recents,
    List<SearchResult>? titleHits,
    List<SearchResult>? contentHits,
    Map<String, List<String>>? folderPaths,
    bool? isSearching,
  }) {
    return SearchState(
      scope: scope ?? this.scope,
      query: query ?? this.query,
      phase: phase ?? this.phase,
      recents: recents ?? this.recents,
      titleHits: titleHits ?? this.titleHits,
      contentHits: contentHits ?? this.contentHits,
      folderPaths: folderPaths ?? this.folderPaths,
      isSearching: isSearching ?? this.isSearching,
    );
  }

  @override
  List<Object?> get props => [
    scope,
    query,
    phase,
    recents,
    titleHits,
    contentHits,
    folderPaths,
    isSearching,
  ];
}
