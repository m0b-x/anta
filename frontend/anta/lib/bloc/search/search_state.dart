import 'package:equatable/equatable.dart';

import '../../models/item_label.dart';
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

  /// The colour labels currently filtering the results, OR-ed together.
  /// Empty is no filter.
  ///
  /// A label filter outlives a query: it is the one part of the surface that
  /// survives clearing the field, because "everything red" is itself a
  /// question and clearing the text is how the user asks it.
  final Set<ItemLabel> labels;

  /// The colours at least one note in the current scope actually carries, in
  /// palette order — the chips the surface offers. A chip for a colour
  /// nothing wears would be a guaranteed empty result.
  final List<ItemLabel> labelsInUse;

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

  /// How many notes the picked colours gather in all, which is not how many
  /// are listed: the label-only listing is capped, and its header counts the
  /// colours' notes rather than the rows that fitted. Zero unless a
  /// label-only pass produced what is on screen.
  final int labelledTotal;

  final bool isSearching;

  const SearchState({
    this.scope = const SearchScope.everywhere(),
    this.query = '',
    this.phase = SearchPhase.idle,
    this.labels = const {},
    this.labelsInUse = const [],
    this.recents = const [],
    this.titleHits = const [],
    this.contentHits = const [],
    this.folderPaths = const {},
    this.labelledTotal = 0,
    this.isSearching = false,
  });

  bool get hasResults => titleHits.isNotEmpty || contentHits.isNotEmpty;

  /// A label filter with nothing typed: what is on screen is "everything
  /// red", not the answer to a query, so the section header names the
  /// colours instead of saying Titles.
  bool get isLabelOnly => labels.isNotEmpty && query.trim().isEmpty;

  SearchState copyWith({
    SearchScope? scope,
    String? query,
    SearchPhase? phase,
    Set<ItemLabel>? labels,
    List<ItemLabel>? labelsInUse,
    List<NoteMetadata>? recents,
    List<SearchResult>? titleHits,
    List<SearchResult>? contentHits,
    Map<String, List<String>>? folderPaths,
    int? labelledTotal,
    bool? isSearching,
  }) {
    return SearchState(
      scope: scope ?? this.scope,
      query: query ?? this.query,
      phase: phase ?? this.phase,
      labels: labels ?? this.labels,
      labelsInUse: labelsInUse ?? this.labelsInUse,
      recents: recents ?? this.recents,
      titleHits: titleHits ?? this.titleHits,
      contentHits: contentHits ?? this.contentHits,
      folderPaths: folderPaths ?? this.folderPaths,
      labelledTotal: labelledTotal ?? this.labelledTotal,
      isSearching: isSearching ?? this.isSearching,
    );
  }

  @override
  List<Object?> get props => [
    scope,
    query,
    phase,
    labels,
    labelsInUse,
    recents,
    titleHits,
    contentHits,
    folderPaths,
    labelledTotal,
    isSearching,
  ];
}
