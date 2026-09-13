import 'package:flutter/widgets.dart';

import '../bloc/search/search_bloc.dart';
import '../models/search_scope.dart';

/// The half of in-place search that is the same on every host: the bloc, the
/// field's controller and focus node, and the flag saying whether the field
/// is up at all.
///
/// It owns no layout and no scroll compensation, because those are exactly
/// what differs — the browser pays for a three-way bar swap it shares with
/// selection mode, the note lists for a two-way one. What is left over is
/// identical on both, and was a screen of duplication before this existed.
///
/// A plain class rather than a `ChangeNotifier`: every transition here is
/// driven by a page callback that is already calling `setState` for its own
/// bar swap, and a second notification would rebuild the page twice for one
/// tap.
class InPlaceSearchController {
  /// Primes the chip row as the host is built rather than when search opens.
  ///
  /// The in-place hosts build their bloc at page mount and keep it for the
  /// life of the page, and the chip row is part of the search bar's committed
  /// height — so reading the colours at open time grew an already-visible bar
  /// by 60 dp a frame later. Priming here means the row is there on the frame
  /// the field appears on, or not at all.
  InPlaceSearchController({required this.bloc}) {
    bloc.add(const SearchLabelsPrimed());
  }

  final SearchBloc bloc;
  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();

  bool _searching = false;

  /// Whether the search field has replaced the page's normal bar.
  ///
  /// Search is screen state, not a route: it is deliberately never stamped as
  /// a `NavDestination`, so opening and closing it leaves the recorded
  /// location stack exactly as it was.
  bool get isSearching => _searching;

  /// Opens search on [scope], returning false if it was already open.
  ///
  /// [SearchOpened] is dispatched before the flag flips for a reason: the
  /// hosts guard their `BlocBuilder` with `buildWhen: (_, __) => isSearching`
  /// to keep the results out of the list underneath, and that is only safe
  /// because the bloc's open handler emits before its first await.
  bool open(SearchScope scope) {
    if (_searching) return false;
    textController.clear();
    bloc.add(SearchOpened(scope: scope));
    _searching = true;
    return true;
  }

  /// Tears search down without asking for a frame, so a caller can run it and
  /// its own bar-swap compensation back to back in one tick. Returns false if
  /// search was not up.
  ///
  /// [SearchCleared] rather than a reset: the bloc outlives the field, and
  /// the next [open] is what blanks it — including the colour filter, which
  /// this deliberately leaves standing so the surface is not repainted on its
  /// way off screen.
  bool leave() {
    if (!_searching) return false;
    _searching = false;
    focusNode.unfocus();
    textController.clear();
    bloc.add(const SearchCleared());
    return true;
  }

  void onChanged(String query) {
    if (query.trim().isEmpty) {
      bloc.add(const SearchCleared());
      return;
    }
    bloc.add(SearchQueryChanged(query));
  }

  void onSubmitted(String query) {
    if (query.trim().isEmpty) return;
    bloc.add(SearchSubmitted(query));
  }

  /// Clears the field without leaving search, and hands the keyboard back.
  void clearQuery() {
    textController.clear();
    onChanged('');
    focusNode.requestFocus();
  }

  /// Re-runs whichever pass is on screen so a note edited through a result
  /// comes back with a fresh title and snippet.
  ///
  /// `keepLabels` because this is a refresh and not an opening: the colours
  /// are part of what is on screen here, and an open deliberately drops them.
  void refresh() {
    final state = bloc.state;
    final query = state.query.trim();
    if (query.isEmpty) {
      bloc.add(SearchOpened(scope: state.scope, keepLabels: true));
      return;
    }
    if (state.phase == SearchPhase.full) {
      bloc.add(SearchSubmitted(state.query));
      return;
    }
    bloc.add(SearchQueryChanged(state.query));
  }

  /// A route regaining focus hands it back to the child that had it, and a
  /// field regaining focus reopens the keyboard — which would cover the very
  /// results the user came back to.
  void unfocus() => focusNode.unfocus();

  void requestFocus() => focusNode.requestFocus();

  void dispose() {
    bloc.close();
    textController.dispose();
    focusNode.dispose();
  }
}
