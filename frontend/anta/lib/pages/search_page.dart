import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../bloc/search/search_bloc.dart';
import '../constants/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../models/search_scope.dart';
import '../services/app_navigator.dart';
import '../services/folder_search_service.dart';
import '../services/folder_storage_service.dart';
import '../services/note_storage_service.dart';
import '../widgets/search_surface.dart';
import '../widgets/unified_app_bars.dart';

/// The standalone search route: a field, a [SearchBloc] of its own, and
/// [SearchSurface] for a body.
///
/// The bloc is page-scoped on purpose. Search used to run on the browser's
/// `OptimizedNoteBloc`, so results replaced the folder list underneath and
/// the page had to reload itself on the way back.
class SearchPage extends StatelessWidget {
  final String? folderId;

  /// The scoped folder's name, for the chip. Optional because a caller may
  /// not have it; the chip then reads "This folder".
  final String? folderName;

  /// When set, the search field opens pre-filled with this query and the full
  /// search runs immediately (used by `#tag` taps from the editor).
  final String? initialQuery;

  const SearchPage({
    super.key,
    this.folderId,
    this.folderName,
    this.initialQuery,
  });

  @override
  Widget build(BuildContext context) {
    final query = initialQuery?.trim() ?? '';
    // A tag is a global filter, so it overrides the folder it was tapped in.
    final folderScope = (folderId == null || query.isNotEmpty)
        ? null
        : FolderScope(folderId: folderId!, name: folderName ?? '');

    return BlocProvider<SearchBloc>(
      create: (_) => _openBloc(folderScope, query),
      child: _SearchView(folderScope: folderScope, initialQuery: query),
    );
  }

  SearchBloc _openBloc(FolderScope? folderScope, String query) {
    final bloc = SearchBloc(
      searchService: GetIt.I<FolderSearchService>(),
      noteService: GetIt.I<NoteStorageService>(),
      folderService: GetIt.I<FolderStorageService>(),
    )..add(SearchOpened(scope: folderScope ?? const SearchScope.everywhere()));
    // Submitted rather than typed: the tag is already complete, and going
    // through the debounced path would show recents for 200 ms first.
    if (query.isNotEmpty) bloc.add(SearchSubmitted(query));
    return bloc;
  }
}

class _SearchView extends StatefulWidget {
  final FolderScope? folderScope;
  final String initialQuery;

  const _SearchView({required this.folderScope, required this.initialQuery});

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> with RouteAware {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) {
      _searchController.text = widget.initialQuery;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppNavigator.routeObserver.subscribe(this, route);
    }
  }

  /// A route regaining focus hands it back to the child that had it, and a
  /// field regaining focus reopens the keyboard over the results the user
  /// came back to. Letting go on the way out leaves the query and the hits
  /// standing with the keyboard down.
  @override
  void didPushNext() {
    _focusNode.unfocus();
  }

  /// A note opened from a hit can come back renamed, re-tagged or deleted, so
  /// whichever pass is on screen runs again rather than repainting the
  /// snapshot the push was made from.
  @override
  void didPopNext() {
    if (!mounted) return;
    final bloc = context.read<SearchBloc>();
    final state = bloc.state;
    if (state.query.trim().isEmpty) {
      bloc.add(SearchOpened(scope: state.scope));
      return;
    }
    if (state.phase == SearchPhase.full) {
      bloc.add(SearchSubmitted(state.query));
      return;
    }
    bloc.add(SearchQueryChanged(state.query));
  }

  @override
  void dispose() {
    AppNavigator.routeObserver.unsubscribe(this);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    final bloc = context.read<SearchBloc>();
    if (query.trim().isEmpty) {
      bloc.add(const SearchCleared());
      return;
    }
    bloc.add(SearchQueryChanged(query));
  }

  void _onSubmitted(String query) {
    if (query.trim().isEmpty) return;
    context.read<SearchBloc>().add(SearchSubmitted(query));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.pageGround,
      appBar: SearchAppBar(
        controller: _searchController,
        focusNode: _focusNode,
        hintText: AppLocalizations.of(context)!.search,
        onChanged: _onChanged,
        onSubmitted: _onSubmitted,
        onClear: () {
          _searchController.clear();
          _onChanged('');
        },
      ),
      body: SafeArea(
        top: false,
        child: SearchSurface(folderScope: widget.folderScope),
      ),
    );
  }
}
