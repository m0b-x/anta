import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../bloc/optimized_note/optimized_note_bloc.dart';
import '../bloc/optimized_note/optimized_note_event.dart';
import '../bloc/optimized_note/optimized_note_state.dart';
import '../bloc/search/search_bloc.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/settings_keys.dart';
import '../controllers/in_place_search_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/note_change.dart';
import '../models/note_metadata.dart';
import '../models/search_scope.dart';
import '../services/app_navigator.dart';
import '../services/drawer_host_registry.dart';
import '../services/folder_search_service.dart';
import '../services/folder_storage_service.dart';
import '../services/note_storage_service.dart';
import '../services/label_appearance_service.dart';
import '../services/settings_service.dart';
import '../utils/bloc_helpers.dart';
import '../widgets/app_drawer.dart';
import '../widgets/content_rows.dart';
import '../widgets/folder_sliver_app_bar.dart';
import '../widgets/infinite_scroll_list.dart';
import '../widgets/note_row.dart';
import '../widgets/search_field_app_bar.dart';
import '../widgets/search_surface.dart';

/// Which of the two note lists the page is being: every note there is, or
/// only the ones touched most recently.
///
/// One page rather than two, because the difference is a cap and a title —
/// the rows, the paths, the card menus and the in-place search are the same
/// list either way, and a copy of it would drift within a slice.
enum AllNotesMode {
  /// Every note in every folder, paginated, searchable in place.
  all,

  /// The [AllNotesPage.recentLimit] most recently edited notes, no more.
  recent,
}

/// A flat list of notes drawn from every folder at once.
///
/// It is the root browser's two smart rows made into a page. There are no
/// folders here, no reordering and no create bar: a note has to already exist
/// somewhere to be listed, and every row carries the folder path it lives
/// under so the flattening does not lose where things are.
class AllNotesPage extends StatefulWidget {
  const AllNotesPage({super.key, this.mode = AllNotesMode.all});

  /// How many notes [AllNotesMode.recent] shows. A jump list, not an archive:
  /// past this the answer to "what was I just in" is no longer useful, and
  /// All notes is one row away.
  ///
  /// The same number the search surface's idle recents use — one "recent",
  /// one cap.
  static const int recentLimit = AppConstants.recentNotesLimit;

  final AllNotesMode mode;

  @override
  State<AllNotesPage> createState() => _AllNotesPageState();
}

class _AllNotesPageState extends State<AllNotesPage> with RouteAware {
  /// Lets a restored settings page raise this page's drawer when it is popped
  /// — see [DrawerHostRegistry].
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();

  late final InPlaceSearchController _search = InPlaceSearchController(
    bloc: SearchBloc(
      searchService: GetIt.I<FolderSearchService>(),
      noteService: GetIt.I<NoteStorageService>(),
      folderService: GetIt.I<FolderStorageService>(),
    ),
  );

  bool get _searching => _search.isSearching;

  bool _swipeEnabled = true;
  bool _showNotePreview = SettingsKeys.defaultShowNotePreview;

  /// The search bar is a plain toolbar and the normal one is a large title,
  /// so swapping them moves the list by the difference. Remembered here and
  /// paid for in the same tick as the `setState`, exactly as the browser
  /// pays for its own three-way swap.
  double _offsetBeforeSwap = 0;

  /// The rows the last state carrying data produced, so a transient Loading
  /// on the shared bloc does not blank the list on its way back.
  List<NoteMetadata> _lastNotes = const [];

  /// Folder id → path segments, root-first, for every row on screen.
  Map<String, List<String>> _folderPaths = const {};

  /// The id set [_folderPaths] was read for, so a rebuild showing the same
  /// folders does not re-walk their ancestors.
  Set<String> _pathedFolderIds = const {};

  /// The id set a walk is in flight for, so a rebuild during it does not
  /// start a second one.
  Set<String> _walkingFolderIds = const {};

  /// Guards against a slow ancestor walk landing on top of a newer one.
  int _pathGeneration = 0;

  StreamSubscription<NoteChange>? _noteChangesSub;
  Timer? _reloadDebounce;
  static const _reloadDebounceDuration = Duration(milliseconds: 120);

  NotesSortOrder get _sortOrder => NotesSortOrder.updatedDesc;

  int get _pageSize => widget.mode == AllNotesMode.recent
      ? AllNotesPage.recentLimit
      : NoteStorageService.defaultPageSize;

  @override
  void initState() {
    super.initState();
    DrawerHostRegistry.register(_scaffoldKey);
    _noteChangesSub = GetIt.I<NoteStorageService>().changes.listen(
      (_) => _scheduleReload(),
    );
    _loadSettings();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppNavigator.routeObserver.subscribe(this, route);
    }
  }

  /// The note-preview switch lives in a settings page the drawer opens over
  /// this one. Search is deliberately left standing — the page was never
  /// unmounted — and only its hits are re-run, so a note edited through a
  /// result comes back with a fresh snippet.
  @override
  void didPopNext() {
    _loadSettings();
    _loadData();
    if (_searching) _search.refresh();
  }

  @override
  void didPushNext() {
    if (_searching) _search.unfocus();
  }

  @override
  void dispose() {
    AppNavigator.routeObserver.unsubscribe(this);
    DrawerHostRegistry.unregister(_scaffoldKey);
    _noteChangesSub?.cancel();
    _reloadDebounce?.cancel();
    _search.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Reads the two page-level switches, and repaints only if one moved.
  ///
  /// Both callers are moments the values can actually have changed — first
  /// build and the pop back from the settings page that owns them. It used to
  /// run from [didChangeDependencies] as well, which fires on every
  /// MediaQuery change: two preference reads and a page `setState` per
  /// keyboard animation frame.
  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    // Re-primes the label style after a database switch, the way the folder
    // browser does: this page is just as likely to be the one on screen when
    // the switch lands, and its rows read the facade synchronously.
    await LabelAppearanceService.getInstance();
    final swipe = await settings.getFolderSwipeEnabled();
    final showPreview = await settings.getShowNotePreview();
    if (!mounted) return;
    if (swipe == _swipeEnabled && showPreview == _showNotePreview) return;
    setState(() {
      _swipeEnabled = swipe;
      _showNotePreview = showPreview;
    });
  }

  /// A note written anywhere changes this list, and the shared bloc's own
  /// refresh reloads at its default page size rather than at this page's, so
  /// the reload is dispatched here instead of relied on.
  void _scheduleReload() {
    if (!mounted) return;
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(_reloadDebounceDuration, () {
      if (mounted) _loadData();
    });
  }

  void _loadData() {
    context.read<OptimizedNoteBloc>().add(
      LoadNotesPaginated(
        folderId: null,
        pageSize: _pageSize,
        sortOrder: _sortOrder,
      ),
    );
  }

  // ─── Search ─────────────────────────────────────────────────────────────

  void _openSearch() {
    if (!_search.open(const SearchScope.everywhere())) return;
    _compensateBarSwap(searching: true);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searching) _search.requestFocus();
    });
  }

  void _exitSearch() {
    if (!_search.leave()) return;
    _compensateBarSwap(searching: false);
    setState(() {});
  }

  /// Results open at their own top and the list gets back the offset it had,
  /// untouched by anything scrolled through the hits. Clamped at zero only:
  /// the new extent is not laid out yet, so there is nothing to clamp the
  /// other end against.
  void _compensateBarSwap({required bool searching}) {
    if (!_scrollController.hasClients) {
      _offsetBeforeSwap = 0;
      return;
    }
    if (searching) {
      _offsetBeforeSwap = _scrollController.offset;
      _scrollController.jumpTo(0);
      return;
    }
    _scrollController.jumpTo(math.max(0, _offsetBeforeSwap));
  }

  // ─── Rows ───────────────────────────────────────────────────────────────

  /// The notes the state carries, or null when it carries none.
  ///
  /// [NoteStateHelper] is deliberately not used: its folder-scoped accessors
  /// answer null for a null folder id, which here means "everything" rather
  /// than "no context".
  List<NoteMetadata>? _notesFrom(OptimizedNoteState state) {
    if (state is OptimizedNoteLoaded) return state.paginatedNotes.notes;
    if (state is OptimizedNoteContentLoaded &&
        state.previousPaginatedNotes != null) {
      return state.previousPaginatedNotes!.notes;
    }
    return null;
  }

  bool _hasMore(OptimizedNoteState state) {
    if (widget.mode == AllNotesMode.recent) return false;
    if (state is OptimizedNoteLoaded) return state.paginatedNotes.hasMore;
    return false;
  }

  /// Reads the folder chain of every folder on screen in one batched pass,
  /// deduplicated by folder id. Skipped when the same folders are already
  /// answered, which is what keeps a scroll frame from re-walking the tree.
  Future<void> _loadPaths(List<NoteMetadata> notes) async {
    final ids = {for (final note in notes) note.folderId};
    // Answered already, or being answered right now. The second check is why
    // the ids are not recorded as answered up front any more: doing that
    // before the await meant a walk that threw was never retried, and the
    // rows it was for kept an empty path lane for the life of the page.
    if (_sameFolderIds(ids, _pathedFolderIds)) return;
    if (_sameFolderIds(ids, _walkingFolderIds)) return;

    final generation = ++_pathGeneration;
    _walkingFolderIds = ids;
    try {
      final paths = await GetIt.I<FolderStorageService>().folderPathSegments(
        ids,
      );
      if (!mounted || generation != _pathGeneration) return;
      _pathedFolderIds = ids;
      setState(() => _folderPaths = paths);
    } catch (e, stackTrace) {
      debugPrint('[AllNotesPage] Failed to load folder paths: $e\n$stackTrace');
      if (generation == _pathGeneration) _walkingFolderIds = const {};
    }
  }

  bool _sameFolderIds(Set<String> a, Set<String> b) =>
      a.length == b.length && a.every(b.contains);

  /// The path lane's text for a row: the folder chain once it is known, and
  /// an empty string until then. Empty is not the same as absent — it keeps
  /// the lane reserved so a late answer does not resize the row.
  String _pathLabelFor(NoteMetadata metadata) {
    final segments = _folderPaths[metadata.folderId];
    if (segments == null || segments.isEmpty) return '';
    return segments.join(' › ');
  }

  RowGroupPosition _positionIn({required int index, required int length}) {
    if (length == 1) return RowGroupPosition.single;
    if (index == 0) return RowGroupPosition.first;
    if (index == length - 1) return RowGroupPosition.last;
    return RowGroupPosition.middle;
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = widget.mode == AllNotesMode.recent
        ? l10n.recent
        : l10n.allNotes;

    final scaffold = Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).colorScheme.pageGround,
      drawer: _searching ? null : const AppDrawer(),
      drawerEnableOpenDragGesture: !_searching && _swipeEnabled,
      body: RefreshIndicator(
        edgeOffset: _searching
            ? 0
            : MediaQuery.paddingOf(context).top +
                  FolderSliverAppBar.expandedHeightFor(false),
        notificationPredicate: (notification) =>
            !_searching && defaultScrollNotificationPredicate(notification),
        onRefresh: () async {
          _loadData();
        },
        child: BlocBuilder<SearchBloc, SearchState>(
          bloc: _search.bloc,
          buildWhen: (previous, current) => _searching,
          builder: (context, searchState) => CustomScrollView(
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            slivers: _searching
                ? [
                    SearchFieldAppBar(
                      search: _search,
                      hintText: l10n.searchAll,
                      selectedScope: searchState.scope,
                      labelsInUse: searchState.labelsInUse,
                      selectedLabels: searchState.labels,
                      onLeave: _exitSearch,
                    ),
                    ...SearchSurface.resultSlivers(context, searchState),
                  ]
                : [
                    FolderSliverAppBar(
                      title: title,
                      isRootPage: false,
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: l10n.searchAll,
                          onPressed: _openSearch,
                        ),
                        _buildOverflowMenu(context),
                      ],
                    ),
                    _buildNotesSliver(),
                  ],
          ),
        ),
      ),
    );

    return BlocProvider<SearchBloc>.value(
      value: _search.bloc,
      child: PopScope(
        canPop: !_searching,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _exitSearch();
        },
        child: scaffold,
      ),
    );
  }

  /// One row, because there is one thing this page can do that its bar does
  /// not already show. It exists at all so the drawer keeps the third of its
  /// three routes here — the app-bar convention ends every overflow menu with
  /// Settings, and `PopupMenuButton.onSelected` runs after the menu route is
  /// gone, so the drawer opens through this page's own key.
  Widget _buildOverflowMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<void>(
      icon: const Icon(Icons.more_vert),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          onTap: () => _scaffoldKey.currentState?.openDrawer(),
          child: Row(
            children: [
              const Icon(Icons.settings_outlined, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.settings)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotesSliver() {
    return BlocBuilder<OptimizedNoteBloc, OptimizedNoteState>(
      buildWhen: NoteBlocFilters.forFolder(null),
      builder: (context, state) {
        final fresh = _notesFrom(state);
        if (fresh == null) {
          if (_lastNotes.isEmpty) {
            return const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          return _buildList(_lastNotes, hasMore: false, isLoadingMore: false);
        }

        final notes = widget.mode == AllNotesMode.recent
            ? fresh.take(AllNotesPage.recentLimit).toList(growable: false)
            : fresh;
        _lastNotes = notes;
        unawaited(_loadPaths(notes));

        if (notes.isEmpty) return _buildEmptyState(context);

        return _buildList(
          notes,
          hasMore: _hasMore(state),
          isLoadingMore: NoteStateHelper.isLoadingMore(state),
        );
      },
    );
  }

  Widget _buildList(
    List<NoteMetadata> notes, {
    required bool hasMore,
    required bool isLoadingMore,
  }) {
    return InfiniteScrollSliver<NoteMetadata>(
      items: notes,
      hasMore: hasMore,
      isLoadingMore: isLoadingMore,
      controller: _scrollController,
      onLoadMore: () {
        context.read<OptimizedNoteBloc>().add(
          const LoadMoreNotes(folderId: null),
        );
      },
      itemBuilder: (context, metadata, index) => NoteRow(
        key: ValueKey('note:${metadata.id}'),
        metadata: metadata,
        folderId: metadata.folderId,
        groupPosition: _positionIn(index: index, length: notes.length),
        showPreview: _showNotePreview,
        pathLabel: _pathLabelFor(metadata),
        onReturn: _loadData,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.description_outlined,
                size: 80,
                color: colorScheme.onSurface.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context)!.emptyNotesHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
