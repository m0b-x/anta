import 'package:equatable/equatable.dart';

import '../../models/item_label.dart';
import '../../models/search_scope.dart';

sealed class SearchEvent extends Equatable {
  const SearchEvent();

  @override
  List<Object?> get props => [];
}

/// Opens the surface on [scope], as a blank one: no query, no results and no
/// colour filter, showing the idle recents.
///
/// [keepLabels] is for the hosts that re-dispatch this as a *refresh* rather
/// than as an opening — coming back from a note with the field empty — where
/// the colours are what is on screen and dropping them would silently answer
/// a different question than the one the surface is showing.
final class SearchOpened extends SearchEvent {
  final SearchScope scope;

  /// Whether the colour filter survives. False for a real open: leaving
  /// search and coming back must not bring a filter the user cannot see.
  final bool keepLabels;

  const SearchOpened({
    this.scope = const SearchScope.everywhere(),
    this.keepLabels = false,
  });

  @override
  List<Object?> get props => [scope, keepLabels];
}

/// Reads the colours in use without touching anything else on screen.
///
/// For a host that builds its bloc when the page mounts and only opens search
/// later: the chip row is part of the search bar's committed height, so
/// reading the colours at open time grows the bar a frame after it appears.
/// Priming at mount means the row is there on the first frame search is up.
final class SearchLabelsPrimed extends SearchEvent {
  const SearchLabelsPrimed();
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

/// The whole colour filter after a chip was toggled, not the one chip that
/// moved: the chip row already knows the set it is drawing, and an event
/// carrying a delta would have to be applied against whichever set the bloc
/// happened to hold when it landed.
///
/// Not debounced — a chip tap is deliberate, and one tap is one pass.
final class SearchLabelsChanged extends SearchEvent {
  final Set<ItemLabel> labels;

  const SearchLabelsChanged(this.labels);

  @override
  List<Object?> get props => [labels];
}

/// Back to whatever an empty field means, keeping the scope.
///
/// Keeps the colour filter too: emptying the field with a colour picked is
/// how the user asks for "everything red", not how they cancel it — so this
/// lands on the idle recents only when no colour is picked. Cancelling the
/// filter is [SearchOpened]'s job, which is what leaving search dispatches.
final class SearchCleared extends SearchEvent {
  const SearchCleared();
}
