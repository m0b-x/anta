import 'package:equatable/equatable.dart';

import '../../models/search_scope.dart';

sealed class SearchEvent extends Equatable {
  const SearchEvent();

  @override
  List<Object?> get props => [];
}

/// Opens the surface on [scope] and loads the idle recents.
final class SearchOpened extends SearchEvent {
  final SearchScope scope;

  const SearchOpened({this.scope = const SearchScope.everywhere()});

  @override
  List<Object?> get props => [scope];
}

/// One keystroke. Debounced, so the quick pass runs once the typing stops.
final class SearchQueryChanged extends SearchEvent {
  final String query;

  const SearchQueryChanged(this.query);

  @override
  List<Object?> get props => [query];
}

/// The full indexed search. Carries its own [query] rather than reading the
/// one in state: the field is the source of truth for what was submitted, and
/// [SearchQueryChanged]'s debounce may not have landed yet.
final class SearchSubmitted extends SearchEvent {
  final String query;

  const SearchSubmitted(this.query);

  @override
  List<Object?> get props => [query];
}

/// Re-runs whatever pass is showing against a different scope.
final class SearchScopeChanged extends SearchEvent {
  final SearchScope scope;

  const SearchScopeChanged(this.scope);

  @override
  List<Object?> get props => [scope];
}

/// Back to idle recents, keeping the scope.
final class SearchCleared extends SearchEvent {
  const SearchCleared();
}
