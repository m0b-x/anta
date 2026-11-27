import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'dart:math' as math;
import '../l10n/app_localizations.dart';
import '../bloc/import_export/import_export_bloc.dart';
import '../bloc/import_export/import_export_event.dart';
import '../bloc/import_export/import_export_state.dart';
import '../bloc/optimized_folder/optimized_folder_bloc.dart';
import '../bloc/optimized_folder/optimized_folder_event.dart';
import '../bloc/optimized_folder/optimized_folder_state.dart';
import '../bloc/optimized_note/optimized_note_bloc.dart';
import '../bloc/optimized_note/optimized_note_event.dart';
import '../bloc/optimized_note/optimized_note_state.dart';
import '../bloc/search/search_bloc.dart';
import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../constants/settings_keys.dart';
import '../controllers/in_place_search_controller.dart';
import '../controllers/partner_look_reader.dart';
import '../controllers/selection_controller.dart';
import '../models/content_item.dart';
import '../models/export_format.dart';
import '../models/folder.dart';
import '../models/folder_change.dart';
import '../models/item_label.dart';
import '../models/movable_item.dart';
import '../models/note_metadata.dart';
import '../models/search_scope.dart';
import '../models/share_overview.dart' show ShareChange;
import '../repositories/note_repository.dart';
import '../services/folder_search_service.dart';
import '../services/folder_storage_service.dart';
import '../services/label_appearance_service.dart';
import '../services/mixed_reorder_service.dart';
import '../services/move_coordinator.dart';
import '../services/move_history_service.dart';
import '../services/note_storage_service.dart';
import '../services/settings_service.dart';
import '../services/share_service.dart';
import '../widgets/infinite_scroll_list.dart';
import '../widgets/app_drawer.dart';
import '../widgets/automation_id.dart';
import '../widgets/content_rows.dart';
import '../widgets/folder_overflow_menu.dart';
import '../widgets/folder_row.dart';
import '../widgets/folder_sliver_app_bar.dart';
import '../widgets/label_swatch_strip.dart';
import '../widgets/note_row.dart';
import '../widgets/search_field_app_bar.dart';
import '../widgets/search_surface.dart';
import '../widgets/share_list_frame.dart' show undoSharePastBloc;
import '../widgets/selection_action_bar.dart';
import '../widgets/selection_app_bar.dart';
import '../utils/bloc_helpers.dart';
import '../utils/custom_snackbar.dart';
import '../utils/share_copy.dart';
import '../utils/share_leave_voice.dart';
import '../widgets/app_dialogs.dart';
import '../services/app_navigator.dart';
import '../widgets/move_history_sheet.dart';

/// One row of the browser's list: either a section label or a content item.
///
/// Both kinds live in the same sequence because there is exactly one
/// reorderable sliver over the whole list; a label is simply a row nothing
/// can pick up.
sealed class _RowEntry {
  const _RowEntry();
}

class _SectionEntry extends _RowEntry {
  final String label;

  /// The header's `SemanticsIds` value, for one whose words a flow cannot
  /// spell — the root's "From {name}".
  final String? identifier;
  const _SectionEntry(this.label, {this.identifier});
}

class _ItemEntry extends _RowEntry {
  final ContentItem item;
  final RowGroupPosition position;
  const _ItemEntry(this.item, this.position);
}

/// One of the partner's folders in the root's "From {name}" group: a row
/// apart from [_ItemEntry], so the reorder, which reads only those, can
/// neither lift one nor land a row of mine among them.
class _PartnerEntry extends _RowEntry {
  final Folder folder;
  final RowGroupPosition position;
  const _PartnerEntry(this.folder, this.position);
}

/// Which bar is occupying the top of the page, and therefore how much scroll
/// extent the list underneath has lost or regained.
///
/// The three are mutually exclusive by construction: search is reachable only
/// from the normal bar, and selection replaces whichever of the other two is
/// showing.
enum _BarMode { normal, selection, search }

/// One of the root's smart rows: a destination that is not a folder, drawn
/// in the same shell as the rows below it so the whole page reads as one
/// kind of list.
///
/// The count rides the trailing slot rather than a second line, in the
/// reserved-width box every folder row uses: a count that arrives late
/// changes nothing about the row it lands in, so the rows below it never
/// move.
class _SmartRow extends StatelessWidget {
  const _SmartRow({
    required this.icon,
    required this.label,
    required this.position,
    required this.identifier,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final int? count;
  final RowGroupPosition position;

  /// The automation id, on a node of its own above the row so the row's own
  /// merged label and tap action are left exactly as they were.
  final String identifier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(identifier: identifier, child: _buildRow(context));
  }

  Widget _buildRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ContentRowShell(
      position: position,
      dividerIndent: RowMetrics.dividerIndentWithGlyph,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RowMetrics.singleLineMinHeight,
          ),
          child: Padding(
            padding: RowMetrics.singleLinePadding,
            child: Row(
              children: [
                Icon(
                  icon,
                  size: RowMetrics.glyphSize,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: RowMetrics.gap),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: RowMetrics.titleFontSize,
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: RowMetrics.gap),
                RowCountChevron(count: count),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OptimizedFolderContentPage extends StatefulWidget {
  final String? folderId;
  final String title;

  /// Whether the folder is the partner's, as the opener knew it — a row
  /// does; null when it could not say (launch restore, a list of ids).
  /// What makes the page read-only from its first frame, before its own
  /// folder is read.
  final bool? fromPartner;

  const OptimizedFolderContentPage({
    super.key,
    this.folderId,
    required this.title,
    this.fromPartner,
  });

  @override
  State<OptimizedFolderContentPage> createState() =>
      _OptimizedFolderContentPageState();
}

class _OptimizedFolderContentPageState extends State<OptimizedFolderContentPage>
    with RouteAware {
  /// The bar's ⋮ Settings item opens the drawer through this key: its tap
  /// runs once the menu route is gone, from a context under no Scaffold of
  /// this page, so `Scaffold.of` cannot reach it.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  NotesSortOrder _notesSortOrder = NotesSortOrder.updatedDesc;
  FoldersSortOrder _foldersSortOrder = FoldersSortOrder.nameAsc;
  bool _folderSwipeEnabled = true;
  bool _showNotePreview = SettingsKeys.defaultShowNotePreview;

  /// This page's own folder, for the overflow menu's rename/move/share/
  /// delete rows. Null on the root page, and until the first read answers.
  Folder? _folder;

  /// Whose each row is, as this page draws it: read once the database is
  /// known to hold something shared, never per row, and null — today's
  /// rows — for an account that shares nothing.
  late final PartnerLookReader _partnerLook = PartnerLookReader()
    ..addListener(_onPartnerLook);

  /// The root's folders the partner shares, drawn under "From {name}" after
  /// the person's own: never part of [_localMixed], so no reorder, select
  /// all or drop can reach one. Read whole, apart from the root's paged
  /// folders, once the census says the database holds a shared row.
  List<Folder> _partnerFolders = const [];
  bool _partnerAsked = false;
  int _partnerFoldersGeneration = 0;

  /// Root → direct parent, excluding this folder. Feeds both the eyebrow
  /// above the large title and the ancestor menu behind it. Null until the
  /// walk answers, so the eyebrow appears once rather than saying "Folders"
  /// and then correcting itself; empty for a folder directly under the root.
  List<Folder>? _ancestors;

  // Per-page selection state. Long-press a card to enter selection mode,
  // tap to toggle, then act on the whole batch (move, delete, drag-and-drop).
  late final SelectionController _selection = SelectionController();
  StreamSubscription<Set<MovableItemRef>>? _selectionSub;

  /// Both of the bars that can replace the tall sliver one are shorter than
  /// it, so keeping the scroll offset across a swap would carry every row up
  /// by the difference — a 68 px jump on every long press. These remember
  /// where the folder list was so the swap can be paid for in the same frame:
  /// [_barMode] against [_lastBarMode] detects the edge,
  /// [_offsetBeforeSwap] is what to return to, and [_offsetOnEnterSwap] is
  /// what was jumped to, so scrolling done in selection mode is added back
  /// rather than thrown away.
  _BarMode _lastBarMode = _BarMode.normal;
  double _offsetBeforeSwap = 0;
  double _offsetOnEnterSwap = 0;

  /// What the expanded bar is worth over the bar that replaces it. Measured
  /// against [SelectionAppBar]'s own height rather than the framework's
  /// default toolbar, and against this page's own expanded height, which the
  /// root and a nested folder do not share.
  double get _barSwapShift =>
      FolderSliverAppBar.expandedHeightFor(
        widget.folderId == null,
        MediaQuery.textScalerOf(context),
      ) -
      SelectionAppBar.height;

  /// Search runs on a bloc of this page's own, so results never touch the
  /// folder list underneath and query, scope and scroll all survive pushing
  /// a note and coming back — the page stays mounted below it.
  late final InPlaceSearchController _search = InPlaceSearchController(
    bloc: SearchBloc(
      searchService: GetIt.I<FolderSearchService>(),
      noteService: GetIt.I<NoteStorageService>(),
      folderService: _folderStorageService,
    ),
  );

  bool get _searching => _search.isSearching;

  // Latest visible items, kept up to date by [_buildFoldersSection] and
  // [_buildNotesSection] so SelectAll can act on them without re-querying.
  List<Folder> _visibleFolders = const [];
  List<NoteMetadata> _visibleNotes = const [];

  // Optimistic reorder state for the unified mixed (folders + notes)
  // sliver. SliverReorderableList only calls onReorderItem; it does not
  // mutate the data itself, so without an immediate local update the list
  // would visually "snap back" while the bloc round-trip (DB write ->
  // refresh -> reload) completes. We render from this list during selection
  // mode and mutate it synchronously inside onReorderItem.
  List<ContentItem>? _localMixed;

  /// Set by a drag, cleared by the load that serves its order back:
  /// [_syncLocal] keeps the optimistic order only in between.
  bool _reorderPending = false;

  // Drag-in-progress tracking for multi-selection visual feedback. While a
  // drag is active, other selected cards are dimmed so the user sees the
  // whole batch is travelling along with the lifted card.
  bool _isDraggingMulti = false;

  // Tracks whether an in-progress export/import loading dialog is currently
  // mounted, so the [ImportExportBloc] listener can pop it exactly once on
  // the terminal state transition.
  bool _ioLoadingDialogOpen = false;

  /// Up from the first await of [_deleteSelected] until it returns, so a
  /// second tap during the settings read neither stacks a second dialog nor
  /// dispatches the delete twice.
  bool _deletingSelected = false;

  /// Set when [_inFront] turned a reload away because another page was in
  /// front: what the skipped reload would have shown is read when this page
  /// is back in front ([didPopNext]).
  bool _staleWhileCovered = false;

  /// This page's route, kept from [didChangeDependencies] so [_inFront] can
  /// ask for it where a lookup is not allowed — inside initState — and
  /// without making every caller depend on the route.
  ModalRoute<dynamic>? _route;

  /// This page's rows as read while it was covered ([_readWhileCovered]),
  /// drawn until the blocs bring its own: a page launch restore builds under
  /// another would otherwise be revealed as a spinner.
  OptimizedFolderLoaded? _coveredFolders;
  OptimizedNoteLoaded? _coveredNotes;

  /// How many pages of notes this page last drew, so a return re-reads that
  /// deep rather than starting the list over at page one.
  int _notePages = 1;

  /// Descendant-inclusive note count per visible folder id. Read for the
  /// whole page in one statement rather than two per row, which is what a
  /// row could do when it owned its own counts.
  Map<String, int> _folderNoteCounts = const {};

  /// The id set the counts in [_folderNoteCounts] were read for, so a rebuild
  /// that shows the same folders does not re-query.
  List<String> _countedFolderIds = const [];

  /// Guards against a slow per-folder count landing on top of a newer one.
  int _folderCountsGeneration = 0;

  /// Every live note in the database, for the root's "All notes" row. Null
  /// until the first read answers, which the row draws as no trailing label
  /// rather than as a zero — a count that corrected itself would be worse
  /// than one that arrives.
  int? _allNotesCount;

  /// Guards against a slow global count landing on top of a newer one.
  int _allNotesCountGeneration = 0;

  /// Coalesces bursts of folder/note changes — a bulk move, a cascade delete,
  /// a batch reorder — into one trailing-edge count read for the page.
  Timer? _countDebounce;
  static const _countDebounceDuration = Duration(milliseconds: 120);
  StreamSubscription<FolderChange>? _folderChangesSub;
  StreamSubscription<NoteChange>? _noteChangesSub;
  StreamSubscription<void>? _shareFactsSub;
  Timer? _shareRefreshDebounce;

  /// Whether the census held a shared row or a mark when the list last
  /// read it: the "before" of a share-facts change.
  bool _heldShared = false;

  /// Whether the census said a pair is stored when the list last read it:
  /// a pairing made or ended under the page changes only this.
  bool _heldPair = false;

  /// The rows as the list renders them: section labels and content items in
  /// one flat sequence, rebuilt whenever the displayed items change. The
  /// reorder handler reads it to translate a row index into a content index.
  List<_RowEntry> _entries = const [];

  /// Sync the local list from the bloc list, preserving local order if it
  /// contains exactly the same set of ids (covers the case where we just
  /// reordered locally and the bloc refresh confirms with the same items).
  List<T> _syncLocal<T>(
    List<T>? local,
    List<T> incoming,
    String Function(T) idOf,
  ) {
    final localIds = local?.map(idOf).toSet();
    final incomingIds = incoming.map(idOf).toSet();
    if (local == null ||
        local.length != incoming.length ||
        localIds!.length != incomingIds.length ||
        !localIds.containsAll(incomingIds)) {
      // Another list now: whatever drag was pending is not on it.
      _reorderPending = false;
      return List<T>.from(incoming);
    }
    // Same ids: the local order wins only while a drag of this page is still
    // unconfirmed — the load that serves that order back ends it. Kept
    // longer, a page remounted on a stale list would never adopt the stored
    // order, and its next drag would write the stale one back.
    if (!_reorderPending ||
        listEquals(local.map(idOf).toList(), incoming.map(idOf).toList())) {
      _reorderPending = false;
      return List<T>.from(incoming);
    }
    // Replace each local entry with the latest incoming object (so other
    // fields like updatedAt are fresh) but keep the drag's order.
    final byId = {for (final item in incoming) idOf(item): item};
    return [for (final item in local) byId[idOf(item)] as T];
  }

  FolderStorageService get _folderStorageService =>
      GetIt.I<FolderStorageService>();
  MixedReorderService get _mixedReorderService =>
      GetIt.I<MixedReorderService>();

  @override
  void initState() {
    super.initState();
    _selectionSub = _selection.changes.listen((_) {
      if (mounted) {
        // Drop optimistic state when leaving selection mode so the next
        // entry starts fresh from bloc data.
        if (!_selection.isActive) {
          _localMixed = null;
          _reorderPending = false;
        }
        if (_selection.isActive) _leaveSearch();
        _compensateBarSwap();
        setState(() {});
      }
    });
    _subscribeToContentChanges();
    ShareLeaveVoice.open(this, _leavesWithThisRun);
    _loadSettings();
    _loadSortPreferencesAndData();
    if (widget.folderId == null) _loadAllNotesCount();
    if (_openedAsPartners) _partnerLook.start();
  }

  /// One subscription for the whole page, not one per row: any folder or note
  /// write can change a descendant-inclusive count, and the debounce collapses
  /// a burst into a single re-read of every visible folder.
  void _subscribeToContentChanges() {
    _folderChangesSub = _folderStorageService.changes.listen((change) {
      _leaveIfPartnerFolderGone(change);
      _scheduleCountRefresh();
    });
    _noteChangesSub = GetIt.I<NoteStorageService>().changes.listen(
      (_) => _scheduleCountRefresh(),
    );
    _shareFactsSub = GetIt.I<NoteStorageService>().shareFactsChanged.listen(
      (_) => _scheduleShareRefresh(),
    );
  }

  void _onPartnerLook() {
    if (mounted) setState(() {});
  }

  /// The share facts changed under the page — an act from the Sharing page,
  /// an Undo tapped after its page left, another device's merge, a shared
  /// read — which no folder change announces: the signs on the rows and the
  /// menu's entry are read again, once per burst. A database whose census
  /// held nothing before and holds nothing after reloads nothing; a pairing
  /// made or ended with nothing shared only rebuilds, so the builder starts
  /// the look reader the menu's entry follows.
  void _scheduleShareRefresh() {
    if (!mounted) return;
    _shareRefreshDebounce?.cancel();
    _shareRefreshDebounce = Timer(_countDebounceDuration, () async {
      final before = _heldShared;
      final after = await _folderStorageService.holdsSharedRead();
      if (!mounted) return;
      final pairBefore = _heldPair;
      _heldPair = _folderStorageService.holdsPair;
      if (!before && !after) {
        if (_heldPair != pairBefore) setState(() {});
        return;
      }
      _heldShared = after;
      await _reloadShares();
    });
  }

  /// The root's "From {name}" group, in one read; again after a folder
  /// change, as the counts are.
  Future<void> _loadPartnerFolders() async {
    final generation = ++_partnerFoldersGeneration;
    try {
      final folders = await _folderStorageService.loadPartnerTopFolders();
      if (!mounted || generation != _partnerFoldersGeneration) return;
      if (listEquals(folders, _partnerFolders)) return;
      setState(() => _partnerFolders = folders);
    } catch (e, stackTrace) {
      debugPrint('[FolderPage] partner folders not read: $e\n$stackTrace');
    }
  }

  /// The partner's folder this page shows stopped being shared while open
  /// (share surfaces §6.12, case N6): the shared reader removed it and
  /// announced it gone ([FolderRepository.announceRemoved]). The page closes
  /// with the menus and sheets it opened above itself, and the bar says why
  /// once however deep the visit went. Only this page's own routes: a page
  /// of the partner's above it closes itself the same way, and one under it
  /// — the root, the Sharing page it was opened from — is left alone.
  void _leaveIfPartnerFolderGone(FolderChange change) {
    if (change.type != FolderChangeType.deleted ||
        !change.remote ||
        change.folderId != widget.folderId ||
        !(_folder?.fromPartner ?? false) ||
        !mounted) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive || route.isFirst) return;
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context)!;
    final message = ShareCopy.sentence(
      l10n.shareGoneFolder(
        ShareCopy.partnerName(l10n, _partnerLook.value?.name),
      ),
    );
    final pages = AppNavigator.routeObserver.pageRoutes
        .where((page) => page.navigator == navigator && page.isActive)
        .toList();
    final at = pages.indexOf(route);
    // One voice per leave (ShareLeaveVoice): said unless a page in front of
    // this one leaves too — on this page when it is on top, else from the
    // navigator, which outlives it, over pages that stay; from the
    // navigator too when the answer comes after this page is gone.
    final host = at == pages.length - 1 ? context : navigator.context;
    unawaited(
      ShareLeaveVoice.leave(this, (_) {
        final speaker = host.mounted ? host : navigator.context;
        if (speaker.mounted) CustomSnackbar.show(speaker, message);
      }),
    );
    if (at < 0) {
      // Unrecorded, so what lies above is unknown: this route alone.
      navigator.removeRoute(route);
      return;
    }
    if (at < pages.length - 1) {
      // A page above this one is still open — it is not this page's to
      // close. What lies between the two is this page's own: a sheet or a
      // dialog it opened, then the page that sheet pushed. Each goes from
      // under that page, down to and with this one.
      final above = pages[at + 1];
      for (var guard = 0; route.isActive && guard < _ownRoutesLimit; guard++) {
        navigator.removeRouteBelow(above);
      }
      return;
    }
    navigator.popUntil((above) => above == route);
    navigator.pop();
  }

  /// Whether this page closes on the run being announced now, asked by
  /// [ShareLeaveVoice] when a page under it leaves: the predicate
  /// [_leaveIfPartnerFolderGone] closes by — the partner's folder it shows,
  /// no longer here — read through the storage service past its cache: a
  /// run announces its notes' removals before its folders', so an editor
  /// above can ask before this folder's announcement dropped its cached row.
  Future<bool> _leavesWithThisRun() async {
    final folderId = widget.folderId;
    if (!mounted || folderId == null || !(_folder?.fromPartner ?? false)) {
      return false;
    }
    if (ModalRoute.of(context)?.isFirst ?? true) return false;
    final folder = await _folderStorageService.getFolderById(
      folderId,
      includeDeleted: false,
      forceRefresh: true,
    );
    return folder == null;
  }

  /// A bound on the routes [_leaveIfPartnerFolderGone] removes from under
  /// an upper page — a sheet, a dialog over it — so a stack it misreads
  /// never loses more than a page's own.
  static const int _ownRoutesLimit = 8;

  void _scheduleCountRefresh() {
    if (!mounted) return;
    _countDebounce?.cancel();
    _countDebounce = Timer(_countDebounceDuration, () {
      if (!mounted) return;
      _loadFolderCounts(_countedFolderIds, force: true);
      if (widget.folderId == null) _loadAllNotesCount();
      if (_partnerAsked) unawaited(_loadPartnerFolders());
    });
  }

  /// The global note count behind the root's "All notes" row.
  ///
  /// The generation guard is what keeps a slow read from painting a stale
  /// total over a newer one: a bulk delete answers this twice, and the two
  /// reads can land in either order.
  Future<void> _loadAllNotesCount() async {
    final generation = ++_allNotesCountGeneration;
    try {
      final count = await GetIt.I<NoteStorageService>().getNoteCount(null);
      if (!mounted || generation != _allNotesCountGeneration) return;
      setState(() => _allNotesCount = count);
    } catch (e, stackTrace) {
      debugPrint('[FolderPage] Failed to count all notes: $e\n$stackTrace');
    }
  }

  /// Reads every visible folder's count in one statement. Skips the read when
  /// the same ids were already answered, which is what keeps a rebuild from
  /// re-querying on every scroll frame.
  ///
  /// Called from the list's own builder, so the empty case assigns without a
  /// `setState`: with no folder rows on screen there is nothing whose count
  /// could repaint, and asking for a rebuild there is a rebuild during build.
  Future<void> _loadFolderCounts(
    List<String> folderIds, {
    bool force = false,
  }) async {
    if (folderIds.isEmpty) {
      _countedFolderIds = const [];
      _folderNoteCounts = const {};
      return;
    }
    if (!force && _sameIds(folderIds, _countedFolderIds)) return;
    // The id check alone cannot order two reads of the *same* ids, which is
    // exactly what a forced refresh issues: a bulk delete answers this twice
    // and the two can land in either order. Same guard as
    // [_loadAllNotesCount].
    final generation = ++_folderCountsGeneration;
    _countedFolderIds = List<String>.unmodifiable(folderIds);
    try {
      final counts = await _folderStorageService.getNoteCountsWithDescendants(
        folderIds,
      );
      if (!mounted ||
          generation != _folderCountsGeneration ||
          !_sameIds(folderIds, _countedFolderIds)) {
        return;
      }
      setState(() {
        _folderNoteCounts = {for (final id in folderIds) id: counts[id] ?? 0};
      });
    } catch (e, stackTrace) {
      debugPrint('[FolderPage] Failed to load folder counts: $e\n$stackTrace');
    }
  }

  bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  _BarMode get _barMode {
    if (_selection.isActive) return _BarMode.selection;
    return _searching ? _BarMode.search : _BarMode.normal;
  }

  /// Pays for the app-bar swap in the same tick the rebuild is scheduled, so
  /// the jump and the new bar land in one frame. A post-frame callback would
  /// paint one frame at the wrong offset first, which is the jump this
  /// exists to remove.
  ///
  /// Selection keeps the same rows under a shorter bar, so entering shifts by
  /// the height the bar gave back and leaving is its exact inverse. Entering
  /// near the top is the case worth naming: the shift clamps at zero there,
  /// and adding the clamped-away pixels back on the way out would drop the
  /// list below where it started, so a selection that never scrolled returns
  /// to the offset it entered from and one that did pays the full shift back.
  /// Search replaces the rows outright, so it opens its results at the top and
  /// gives the folder list back the offset it had, untouched by any scrolling
  /// done through results.
  ///
  /// The result is deliberately not clamped against `maxScrollExtent`: the
  /// new extent is not known until the swap has been laid out, and the
  /// physics settle the rare case where the list shrank.
  ///
  /// A caller tearing one mode down on the way into another passes the
  /// intermediate [target] so the two swaps are paid for one at a time: the
  /// folder list gets its offset back first, and the next swap measures from
  /// there rather than from the offset the outgoing mode had.
  void _compensateBarSwap([_BarMode? target]) {
    final mode = target ?? _barMode;
    if (mode == _lastBarMode) return;
    final previous = _lastBarMode;
    _lastBarMode = mode;
    if (!_scrollController.hasClients) {
      _offsetBeforeSwap = 0;
      _offsetOnEnterSwap = 0;
      return;
    }
    final offset = _scrollController.offset;
    if (mode != _BarMode.normal) {
      _offsetBeforeSwap = offset;
      _offsetOnEnterSwap = mode == _BarMode.selection
          ? math.max(0, offset - _barSwapShift)
          : 0;
      _scrollController.jumpTo(_offsetOnEnterSwap);
      return;
    }
    final restored = previous == _BarMode.selection
        ? (offset > _offsetOnEnterSwap
              ? offset + _barSwapShift
              : _offsetBeforeSwap)
        : _offsetBeforeSwap;
    _scrollController.jumpTo(math.max(0, restored));
  }

  FolderScope? get _folderScope {
    final folderId = widget.folderId;
    if (folderId == null) return null;
    return FolderScope(folderId: folderId, name: _folder?.name ?? widget.title);
  }

  void _openSearch() {
    if (_selection.isActive) {
      _selection.clear();
      _compensateBarSwap(_BarMode.normal);
    }
    if (!_search.open(_folderScope ?? const SearchScope.everywhere())) return;
    _compensateBarSwap();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searching) _search.requestFocus();
    });
  }

  /// Tears search down without asking for a frame, so the selection listener
  /// can run it and its own swap back to back in one tick. The swap is paid
  /// for as search → normal explicitly: by the time the listener runs,
  /// selection is already active and [_barMode] would report it, which would
  /// skip giving the folder list its offset back before the selection swap
  /// measures from it. Selection and search are mutually exclusive.
  void _leaveSearch() {
    if (!_search.leave()) return;
    _compensateBarSwap(_BarMode.normal);
  }

  void _exitSearch() {
    if (!_searching) return;
    _leaveSearch();
    setState(() {});
  }

  Future<void> _loadSortPreferencesAndData() async {
    // Load sort preferences from DB for this folder
    if (widget.folderId != null) {
      final folder = await _folderStorageService.getFolderById(
        widget.folderId!,
      );
      if (folder != null && mounted) {
        setState(() {
          _folder = folder;
          _notesSortOrder = _parseNotesSortOrder(folder.noteSortOrder);
          _foldersSortOrder = _parseFoldersSortOrder(folder.subfolderSortOrder);
        });
      }
      await _loadAncestors();
    }
    if (_inFront()) {
      _loadData();
    } else {
      _readWhileCovered();
    }
  }

  /// This page's first rows, read for it while another page is in front —
  /// launch restore builds a whole stack at once — through the blocs'
  /// answer-only events, which move neither bloc off the page in front. The
  /// reveal re-aims both blocs at this folder and replaces what this read.
  void _readWhileCovered() {
    if (!mounted || !(_route?.isActive ?? false)) return;
    final folderId = widget.folderId;
    final folders = Completer<PaginatedFolders>();
    context.read<OptimizedFolderBloc>().add(
      PeekFolders(
        parentId: folderId,
        sortOrder: _foldersSortOrder,
        done: folders,
      ),
    );
    final notes = folderId == null ? null : Completer<PaginatedNotes>();
    if (folderId != null) {
      context.read<OptimizedNoteBloc>().add(
        PeekNotes(folderId: folderId, sortOrder: _notesSortOrder, done: notes!),
      );
    }
    unawaited(() async {
      try {
        final readFolders = await folders.future;
        final readNotes = await notes?.future;
        if (!mounted) return;
        setState(() {
          _coveredFolders = OptimizedFolderLoaded(
            paginatedFolders: readFolders,
            parentId: folderId,
          );
          if (readNotes != null) {
            _coveredNotes = OptimizedNoteLoaded(
              paginatedNotes: readNotes,
              folderId: folderId,
            );
          }
        });
      } catch (e, st) {
        debugPrint('[FolderContent] covered read failed: $e\n$st');
      }
    }());
  }

  /// [state] as this page may draw it: its own, else what it read while
  /// covered, else nothing. The builders' first build takes the bloc's state
  /// whatever its parent, so a pushed page drew its parent's rows — tappable —
  /// until its own load arrived. An Initial state is nobody's yet — the
  /// context helpers answer true for it — and at a cold launch the note bloc
  /// is still Initial when a restored page is revealed: the root loads no
  /// notes, and the page over it never passes this page's filter.
  ///
  /// The covered read is dropped once the page's own Loaded state arrives,
  /// so a builder made again later never draws rows as old as the launch.
  OptimizedFolderState _ownFolders(OptimizedFolderState state) {
    if (state is! OptimizedFolderInitial &&
        state.matchesParentContext(widget.folderId)) {
      if (state is OptimizedFolderLoaded) _coveredFolders = null;
      return state;
    }
    return _coveredFolders ?? const OptimizedFolderInitial();
  }

  /// The note twin of [_ownFolders].
  OptimizedNoteState _ownNotes(OptimizedNoteState state) {
    if (widget.folderId == null) return state;
    if (state is! OptimizedNoteInitial &&
        state.matchesFolderContext(widget.folderId)) {
      if (state is OptimizedNoteLoaded) _coveredNotes = null;
      return state;
    }
    return _coveredNotes ?? const OptimizedNoteInitial();
  }

  /// Cut at the first tombstone: this page can show a live folder that still
  /// sits under a deleted one (opened before the pull, or rebuilt by launch
  /// restore while the sync folder repair waits), and the eyebrow and the
  /// ancestor menu must neither name the tombstone nor open it.
  Future<void> _loadAncestors() async {
    final folderId = widget.folderId;
    if (folderId == null) return;
    final ancestors = await _folderStorageService.getAncestors(
      folderId,
      stopAtDeleted: true,
    );
    if (!mounted) return;
    setState(() => _ancestors = ancestors);
  }

  NotesSortOrder _parseNotesSortOrder(String? value) {
    if (value == null) return NotesSortOrder.updatedDesc;
    return NotesSortOrder.values.firstWhere(
      (e) => e.name == value,
      orElse: () => NotesSortOrder.updatedDesc,
    );
  }

  FoldersSortOrder _parseFoldersSortOrder(String? value) {
    if (value == null) return FoldersSortOrder.nameAsc;
    return FoldersSortOrder.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FoldersSortOrder.nameAsc,
    );
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
    // Idempotent and cheap, and the one place that re-primes the label style
    // after a database switch drops every singleton: the browser is the
    // screen the switch lands on, and its rows read the facade synchronously.
    await LabelAppearanceService.getInstance();
    final folderSwipe = await settings.getFolderSwipeEnabled();
    final showPreview = await settings.getShowNotePreview();
    if (!mounted) return;
    if (folderSwipe == _folderSwipeEnabled && showPreview == _showNotePreview) {
      return;
    }
    setState(() {
      _folderSwipeEnabled = folderSwipe;
      _showNotePreview = showPreview;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    _route = route;
    if (route is PageRoute) {
      AppNavigator.routeObserver.subscribe(this, route);
    }
  }

  /// The note-preview switch lives in the settings page the drawer opens over
  /// this one, so the only moment it can have changed is the pop back — and
  /// so do the notes look and the mark switch, on the Sharing page.
  ///
  /// Search is deliberately left standing: the page was never unmounted, so
  /// query, scope and scroll are still there. Only the hits are re-run, so a
  /// note edited through a result comes back with a fresh snippet.
  ///
  /// The page is in front again, so both app-wide blocs are aimed back at its
  /// folder, in its orders: a folder opened above it moved them, and each
  /// answers changes only for what it is aimed at. Both reads go straight to
  /// Loaded, so the rows and the count stay drawn while they run, and the
  /// notes come back as deep as the page had them.
  ///
  /// A bloc already aimed here is skipped, unless a reload was turned away
  /// while the page was covered ([_staleWhileCovered]): then nothing it
  /// should show has gone unread, and a pop from the settings page or the
  /// editor costs no read. Every path that turns a reload away goes through
  /// [_inFront], which marks the page stale.
  @override
  void didPopNext() {
    final stale = _staleWhileCovered;
    _staleWhileCovered = false;
    final folderBloc = context.read<OptimizedFolderBloc>();
    if (stale || !folderBloc.isAimedAt(widget.folderId, _foldersSortOrder)) {
      folderBloc.add(
        RefreshFolders(parentId: widget.folderId, sortOrder: _foldersSortOrder),
      );
    }
    final folderId = widget.folderId;
    final noteBloc = context.read<OptimizedNoteBloc>();
    if (folderId != null &&
        (stale || !noteBloc.isAimedAt(folderId, _notesSortOrder))) {
      noteBloc.add(
        ReturnToNotes(
          folderId: folderId,
          sortOrder: _notesSortOrder,
          pages: _notePages,
        ),
      );
    }
    _loadSettings();
    unawaited(_partnerLook.refresh());
    if (_searching) _search.refresh();
  }

  /// A route regaining focus hands it back to the child that had it, and a
  /// field regaining focus reopens the keyboard — so coming back from a
  /// result would cover the results it returns to. Letting go of the field
  /// on the way out leaves the query and the hits where they were, with the
  /// keyboard down until the field is tapped again.
  @override
  void didPushNext() {
    if (_searching) _search.unfocus();
  }

  /// Gone from in front the moment it is popped, not when its closing ends:
  /// a leave heard meanwhile on a page of hers under it is said there.
  @override
  void didPop() => ShareLeaveVoice.popped(this);

  @override
  void dispose() {
    AppNavigator.routeObserver.unsubscribe(this);
    _selectionSub?.cancel();
    _folderChangesSub?.cancel();
    _noteChangesSub?.cancel();
    _shareFactsSub?.cancel();
    _shareRefreshDebounce?.cancel();
    _countDebounce?.cancel();
    ShareLeaveVoice.exit(this);
    _partnerLook.dispose();
    _selection.dispose();
    _search.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Selection mode helpers ─────────────────────────────────────────────

  MovableItemRef _refForFolder(Folder f) => MovableItemRef(
    kind: MovableItemKind.folder,
    id: f.id,
    name: f.name,
    currentParentId: widget.folderId,
  );

  MovableItemRef _refForNote(NoteMetadata n) {
    final l10n = AppLocalizations.of(context)!;
    return MovableItemRef(
      kind: MovableItemKind.note,
      id: n.id,
      name: n.title.isEmpty ? l10n.untitledNote : n.title,
      currentParentId: widget.folderId,
    );
  }

  void _onCardLongPress(MovableItemRef ref) {
    _selection.add(ref);
  }

  void _onCardTapInSelection(MovableItemRef ref) {
    _selection.toggle(ref);
  }

  /// Multi-item reorder.
  ///
  /// `SliverReorderableList` only knows about the single dragged item, but
  /// the user expects all selected items to travel as a group when they drag
  /// any one of them. This helper:
  ///
  ///   1. Detects whether the dragged item belongs to a multi-selection.
  ///   2. If so, removes every selected item from the list (preserving their
  ///      original relative order) and inserts them as a contiguous block at
  ///      the drop target — adjusted for the items removed before it.
  ///   3. Falls back to a plain single-item reorder when only one item (or
  ///      none) is selected, or when the dragged item is not in the
  ///      selection.
  ///
  /// This is O(n) in the visible list size, runs synchronously, and produces
  /// a single ordered list to hand to the bloc — no per-item bloc events.
  List<T> _applyMultiReorder<T>({
    required List<T> source,
    required int oldIndex,
    required int newIndex,
    required MovableItemRef Function(T) refOf,
  }) {
    final draggedItem = source[oldIndex];
    final draggedRef = refOf(draggedItem);
    final selectionContainsDragged = _selection.contains(draggedRef);
    final isMulti = selectionContainsDragged && _selection.count > 1;

    if (!isMulti) {
      // `onReorderItem` hands over the post-removal index, so it can be used
      // directly as the insertion point.
      final result = List<T>.from(source);
      final item = result.removeAt(oldIndex);
      result.insert(newIndex, item);
      return result;
    }

    // Multi: split selected vs. unselected while preserving the visible
    // order, then re-insert the selected block at the right position among
    // the unselected items.
    final selected = <T>[];
    final unselected = <T>[];
    // Track how many unselected items live strictly before the drop target.
    // `newIndex` addresses the list *without* the dragged item, so each
    // unselected item is compared via its position in that same list (the
    // dragged item itself is selected here and never reaches this branch).
    var unselectedBeforeTarget = 0;
    for (var i = 0; i < source.length; i++) {
      final item = source[i];
      final inSelection = _selection.contains(refOf(item));
      if (inSelection) {
        selected.add(item);
      } else {
        final positionWithoutDragged = i < oldIndex ? i : i - 1;
        if (positionWithoutDragged < newIndex) unselectedBeforeTarget += 1;
        unselected.add(item);
      }
    }

    final insertIndex = unselectedBeforeTarget.clamp(0, unselected.length);
    final result = List<T>.from(unselected)..insertAll(insertIndex, selected);
    debugPrint(
      '[Reorder] multi: dragged ${selected.length} items, oldIndex=$oldIndex '
      'newIndex=$newIndex insertIndex=$insertIndex',
    );
    return result;
  }

  void _selectAll() {
    _selection.addAll([
      for (final f in _visibleFolders) _refForFolder(f),
      for (final n in _visibleNotes) _refForNote(n),
    ]);
  }

  /// Called when SliverReorderableList starts a drag. We only flip the multi
  /// flag if there's an actual multi-selection — single-item drags get the
  /// default behavior with no extra rebuilds.
  void _onReorderStart() {
    if (_selection.count > 1) {
      setState(() => _isDraggingMulti = true);
    }
  }

  void _onReorderEnd() {
    if (_isDraggingMulti) {
      setState(() => _isDraggingMulti = false);
    }
  }

  /// Decorates the dragged card with a count badge when the user is moving a
  /// multi-selection, so it's visually obvious that the whole batch will move
  /// even though only one card lifts off.
  Widget _buildReorderProxy(
    Widget child,
    Animation<double> animation,
    int selectionCount,
  ) {
    if (selectionCount <= 1) return child;
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: 0,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '$selectionCount',
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The label every picked item already carries, or [ItemLabel.none] when
  /// they disagree — what the bulk sheet rings, so a selection that is
  /// uniformly red does not open on "no label".
  ItemLabel _commonLabelOf(List<MovableItemRef> items) {
    ItemLabel? common;
    for (final ref in items) {
      final label = switch (ref.kind) {
        MovableItemKind.folder =>
          _visibleFolders.where((f) => f.id == ref.id).firstOrNull?.label,
        MovableItemKind.note =>
          _visibleNotes.where((n) => n.id == ref.id).firstOrNull?.label,
      };
      if (label == null) return ItemLabel.none;
      if (common != null && common != label) return ItemLabel.none;
      common = label;
    }
    return common ?? ItemLabel.none;
  }

  /// The bulk colour-label pick: the shared picker sheet, applied to every
  /// picked note and folder in one write per kind.
  Future<void> _labelSelected() async {
    final items = _selection.items.toList(growable: false);
    if (items.isEmpty) return;

    final picked = await showLabelPickerSheet(
      context,
      value: _commonLabelOf(items),
    );

    if (picked == null || !mounted) return;

    final folderIds = <String>[];
    final noteIds = <String>[];
    for (final ref in items) {
      (ref.kind == MovableItemKind.folder ? folderIds : noteIds).add(ref.id);
    }

    if (folderIds.isNotEmpty) {
      context.read<OptimizedFolderBloc>().add(
        SetOptimizedFoldersLabel(folderIds: folderIds, label: picked),
      );
    }
    if (noteIds.isNotEmpty) {
      context.read<OptimizedNoteBloc>().add(
        SetOptimizedNotesLabel(noteIds: noteIds, label: picked),
      );
    }
    _selection.clear();
  }

  Future<void> _moveSelected() async {
    final items = _selection.items.toList(growable: false);
    if (items.isEmpty) return;
    await MoveCoordinator.moveItems(context, items: items);
    if (mounted) {
      _selection.clear();
      _refreshData();
    }
  }

  /// Multi-select export: ask for the note format, then ship the whole
  /// selection (notes + folders) through the bloc as a single zip. Folders
  /// are zipped recursively; loose notes land at the archive root. Selection
  /// stays active so the user can retry on failure; on success the listener
  /// shows the share sheet and we clear it.
  Future<void> _shareSelected() async {
    final items = _selection.items.toList(growable: false);
    if (items.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    final hasNotes = items.any((r) => r.kind == MovableItemKind.note);

    // Format only matters when at least one note will be written. If the
    // selection is folders-only, default to JSON for round-trip fidelity
    // and skip the prompt entirely.
    ExportFormat format = ExportFormat.json;
    if (hasNotes) {
      final picked = await AppDialogs.choose<ExportFormat>(
        context,
        title: l10n.chooseExportFormat,
        options: [
          (
            value: ExportFormat.markdown,
            label: l10n.exportAsMarkdown,
            icon: Icons.description_rounded,
          ),
          (
            value: ExportFormat.json,
            label: l10n.exportAsJson,
            icon: Icons.data_object_rounded,
          ),
          (
            value: ExportFormat.text,
            label: l10n.exportAsText,
            icon: Icons.text_snippet_rounded,
          ),
        ],
      );
      if (picked == null || !mounted) return;
      format = picked;
    }

    final noteIds = <String>{};
    final folderIds = <String>{};
    for (final ref in items) {
      if (ref.kind == MovableItemKind.note) {
        noteIds.add(ref.id);
      } else {
        folderIds.add(ref.id);
      }
    }

    context.read<ImportExportBloc>().add(
      ExportItemsRequested(
        noteIds: noteIds,
        folderIds: folderIds,
        noteFormat: format,
        share: true,
      ),
    );
    _selection.clear();
  }

  /// Asks first unless "Confirm before delete" is off (record D24).
  Future<void> _deleteSelected() async {
    if (_deletingSelected) return;
    final l10n = AppLocalizations.of(context)!;
    final items = _selection.items.toList(growable: false);
    if (items.isEmpty) return;

    _deletingSelected = true;
    try {
      final settings = await SettingsService.getInstance();
      final confirm = await settings.getConfirmDelete();
      if (!mounted) return;
      if (confirm) {
        final confirmed = await AppDialogs.confirm(
          context,
          title: l10n.delete,
          content: l10n.deleteSelectedConfirm(items.length),
          confirmText: l10n.delete,
          isDestructive: true,
        );
        if (!confirmed || !mounted) return;
      }

      final folderIds = <String>[];
      final noteIds = <String>[];
      for (final ref in items) {
        (ref.kind == MovableItemKind.folder ? folderIds : noteIds).add(ref.id);
      }

      if (folderIds.isNotEmpty) {
        context.read<OptimizedFolderBloc>().add(
          DeleteOptimizedFolders(
            folderIds: folderIds,
            parentId: widget.folderId,
          ),
        );
      }
      if (noteIds.isNotEmpty) {
        context.read<OptimizedNoteBloc>().add(DeleteOptimizedNotes(noteIds));
      }
      _selection.clear();
    } finally {
      _deletingSelected = false;
    }
  }

  Future<void> _onDropOnFolder(
    Folder targetFolder,
    Set<MovableItemRef> dropped,
  ) async {
    // Filter out the target itself if it was selected; can't move a folder into itself.
    final filtered = dropped
        .where(
          (r) => !(r.kind == MovableItemKind.folder && r.id == targetFolder.id),
        )
        .toList(growable: false);
    if (filtered.isEmpty) return;
    await MoveCoordinator.moveItemsTo(
      context,
      items: filtered,
      targetParentId: targetFolder.id,
    );
    if (mounted) {
      _selection.clear();
      _refreshData();
    }
  }

  void _preloadNoteContent(List<String> noteIds) {
    context.read<OptimizedNoteBloc>().add(PreloadNoteContent(noteIds));
  }

  /// Re-reads the list without starting it over.
  ///
  /// [_loadData] goes through `LoadFoldersPaginated`, which emits a Loading
  /// state first — and a move made from selection mode has just dropped
  /// [_localMixed], so that frame renders the cold-start spinner and throws
  /// the scroll offset away with it. A refresh keeps every page the list had
  /// and emits straight to Loaded.
  void _refreshData() {
    if (!_inFront()) return;
    context.read<OptimizedFolderBloc>().add(
      RefreshFolders(parentId: widget.folderId, sortOrder: _foldersSortOrder),
    );
    if (widget.folderId != null) {
      context.read<OptimizedNoteBloc>().add(
        RefreshNotes(folderId: widget.folderId),
      );
    }
  }

  /// Whether this page may aim the app-wide folder and note blocs at its own
  /// folder now; a page under another one may not.
  ///
  /// One bloc serves every stacked browser page and reloads only the parent
  /// it has open, so a covered page that loads its own — the import listener
  /// and the share refresh run on every mounted page, a first load can end
  /// after a child was pushed over it or after it was popped — takes the
  /// bloc from the page in front, which then stops hearing its own changes.
  /// A dialog, a menu or a sheet over the page leaves it in front: they are
  /// popup routes, and the observer records page routes only. A reload
  /// turned away marks the page stale for [didPopNext].
  bool _inFront() {
    if (!mounted) return false;
    // Unknown only inside initState — the root's first load runs there —
    // when the page is the one being pushed.
    final route = _route;
    if (route == null || route.isCurrent) return true;
    if (route.isActive) {
      final navigator = route.navigator;
      final pages = AppNavigator.routeObserver.pageRoutes.where(
        (page) => page.isActive && identical(page.navigator, navigator),
      );
      if (pages.isNotEmpty && identical(pages.last, route)) return true;
    }
    _staleWhileCovered = true;
    return false;
  }

  void _loadData() {
    if (!_inFront()) return;
    context.read<OptimizedFolderBloc>().add(
      LoadFoldersPaginated(
        parentId: widget.folderId,
        sortOrder: _foldersSortOrder,
      ),
    );
    if (widget.folderId != null) {
      context.read<OptimizedNoteBloc>().add(
        LoadNotesPaginated(
          folderId: widget.folderId,
          sortOrder: _notesSortOrder,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRootPage = widget.folderId == null;
    final isSelecting = _selection.isActive;
    final colorScheme = Theme.of(context).colorScheme;
    final holding = _holdsForLook;

    final scaffold = Scaffold(
      key: _scaffoldKey,
      backgroundColor: colorScheme.pageGround,
      drawer: isSelecting || _searching ? null : const AppDrawer(),
      drawerEnableOpenDragGesture:
          !isSelecting && !_searching && _folderSwipeEnabled,
      appBar: isSelecting
          ? SelectionAppBar(
              count: _selection.count,
              allSelected:
                  _selection.count > 0 &&
                  _selection.count ==
                      _visibleFolders.length + _visibleNotes.length,
              onCancel: _selection.clear,
              onSelectAll: _selectAll,
              onDeselectAll: _selection.deselectAll,
            )
          : null,
      body: RefreshIndicator(
        // Without this the spinner would drop from the very top of the body,
        // which the expanded bar covers.
        edgeOffset: isSelecting || _searching
            ? 0
            : MediaQuery.paddingOf(context).top +
                  FolderSliverAppBar.expandedHeightFor(
                    isRootPage,
                    MediaQuery.textScalerOf(context),
                  ),
        notificationPredicate: (notification) =>
            !_searching && defaultScrollNotificationPredicate(notification),
        onRefresh: () async {
          _refreshData();
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
                      hintText: isRootPage
                          ? AppLocalizations.of(context)!.searchAll
                          : AppLocalizations.of(context)!.searchInFolder,
                      selectedScope: searchState.scope,
                      folderScope: _folderScope,
                      labelsInUse: searchState.labelsInUse,
                      selectedLabels: searchState.labels,
                      onLeave: _exitSearch,
                    ),
                    ...SearchSurface.resultSlivers(
                      context,
                      searchState,
                      partnerLook: _partnerLook.value,
                    ),
                  ]
                : [
                    if (!isSelecting)
                      FolderSliverAppBar(
                        title: isRootPage
                            ? AppLocalizations.of(context)!.folders
                            : (_folder?.name ?? widget.title),
                        isRootPage: isRootPage,
                        eyebrow: isRootPage ? null : _eyebrowLabel(context),
                        onShowAncestors: isRootPage ? null : _showAncestorMenu,
                        actions: [
                          AutomationId(
                            identifier: SemanticsIds.searchOpen,
                            child: IconButton(
                              icon: const Icon(Icons.search),
                              tooltip: widget.folderId != null
                                  ? AppLocalizations.of(context)!.searchInFolder
                                  : AppLocalizations.of(context)!.searchAll,
                              onPressed: _openSearch,
                            ),
                          ),
                          StreamBuilder<int>(
                            stream: GetIt.I<MoveHistoryService>().changes,
                            initialData:
                                GetIt.I<MoveHistoryService>().undoableCount,
                            builder: (context, snapshot) => FolderOverflowMenu(
                              isRootPage: isRootPage,
                              sortLabel: _sortLabel(
                                AppLocalizations.of(context)!,
                              ),
                              moveHistoryCount: snapshot.data ?? 0,
                              onSortBy: _showQuickSortOptions,
                              onSelect: _selection.activate,
                              onMoveHistory: () =>
                                  showMoveHistorySheet(context),
                              onImport: _pickAndImport,
                              onSettings: () =>
                                  _scaffoldKey.currentState?.openDrawer(),
                              onRenameFolder: isRootPage
                                  ? null
                                  : _renameCurrentFolder,
                              onMoveFolder: isRootPage
                                  ? null
                                  : _moveCurrentFolder,
                              onShareFolder: isRootPage
                                  ? null
                                  : _shareCurrentFolder,
                              onDeleteFolder: isRootPage
                                  ? null
                                  : _deleteCurrentFolder,
                              readOnly: _readOnly,
                              partnerShare: _folder == null
                                  ? null
                                  : _shareEntryFor(_folder!),
                              onPartnerShare: () => _toggleShared(_folder!),
                            ),
                          ),
                        ],
                      ),
                    if (_readOnly && !isSelecting && !holding) ...[
                      PinnedHeaderSliver(child: _buildPartnerLine(context)),
                      // The air one group leaves the next, so the band does
                      // not sit tight on the first section's label.
                      const SliverToBoxAdapter(
                        child: SizedBox(height: RowMetrics.groupGap),
                      ),
                    ],
                    if (!holding) ...[
                      ..._buildContentSlivers(isSelecting: isSelecting),
                      _buildEmptyStateSection(),
                    ],
                  ],
          ),
        ),
      ),
      bottomNavigationBar: isSelecting
          ? SelectionActionBar(
              count: _selection.count,
              onLabel: _labelSelected,
              onMove: _moveSelected,
              onShare: _shareSelected,
              onDelete: _deleteSelected,
            )
          : _searching
          ? null
          : _buildBottomBar(context, isRootPage: isRootPage),
    );

    return BlocProvider<SearchBloc>.value(
      value: _search.bloc,
      child: _wrapWithImportExportListener(
        PopScope(
          canPop: !_backIsHandled(isRootPage: isRootPage),
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _onBackIntercepted();
          },
          child: scaffold,
        ),
      ),
    );
  }

  /// Whether Back means something on this page before it means leaving it.
  ///
  /// There is exactly one [PopScope] on the browser and deliberately not one
  /// per mode: a route calls **every** registered `PopEntry`'s callback, so
  /// nesting them would run two handlers for a single gesture, and swapping
  /// between sibling ones changes the tree shape above the [Scaffold] —
  /// which rebuilds it and takes the scroll position with it.
  bool _backIsHandled({required bool isRootPage}) {
    if (_selection.isActive || _searching) return true;
    return !isRootPage && _folderSwipeEnabled;
  }

  /// The three meanings of Back, in priority order: leave selection, leave
  /// search, and only once neither is up the nested-folder case — the one
  /// that exists so the swipe-back gesture cannot steal the drawer's edge
  /// drag.
  void _onBackIntercepted() {
    if (_selection.isActive) {
      _selection.clear();
      return;
    }
    if (_searching) {
      _exitSearch();
      return;
    }
    AppNavigator.pop(context);
  }

  /// The create bar that replaced the floating action button and its sheet.
  ///
  /// One tap per action instead of two, and the row that used to be hidden
  /// behind the `+` is now readable at a glance: what is here, and what the
  /// two buttons will add to it. The second button is Import at the root,
  /// where a note has no folder to live in.
  ///
  /// Both buttons cluster at the left behind [RowMetrics.bottomBarInset] so
  /// one hand reaches them; the count still rides the bar's own centre line,
  /// held clear of the buttons by symmetric padding rather than by a slot,
  /// and truncated instead of ever running under them.
  ///
  /// The padding is `max(viewInsets, viewPadding)` on purpose: either alone
  /// leaves the bar under the keyboard or under the gesture bar.
  Widget _buildBottomBar(BuildContext context, {required bool isRootPage}) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );

    return Material(
      color: colorScheme.rowGroup,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          height: RowMetrics.bottomBarHeight,
          foregroundDecoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colorScheme.rowDivider, width: 1),
            ),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: RowMetrics.bottomBarInset),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    _barButton(
                      icon: Icons.create_new_folder_outlined,
                      tooltip: l10n.newFolder,
                      identifier: SemanticsIds.createFolder,
                      onPressed: _readOnly ? null : _showCreateFolderDialog,
                    ),
                    if (isRootPage)
                      _barButton(
                        icon: Icons.file_download_outlined,
                        tooltip: l10n.importNoteOrFolder,
                        onPressed: _pickAndImport,
                      )
                    else
                      _barButton(
                        icon: Icons.note_add_outlined,
                        tooltip: l10n.newNote,
                        identifier: SemanticsIds.createNote,
                        onPressed: _readOnly ? null : _createNewNote,
                      ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal:
                          RowMetrics.bottomBarInset +
                          2 * RowMetrics.bottomBarButtonSize,
                    ),
                    child: Center(child: _buildCountLabel(context)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One of the create bar's two buttons: a 54 dp target around a 28 dp
  /// glyph in the page's one accent, sized explicitly because the default
  /// [IconButton] target is taller than the 60 dp bar it sits in.
  ///
  /// Inside the partner's folder both stay, disabled, in their place: the
  /// line under the bar says why (§16.8 fd).
  Widget _barButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    String? identifier,
  }) {
    final button = IconButton(
      icon: Icon(icon),
      iconSize: RowMetrics.bottomBarGlyphSize,
      color: Theme.of(context).colorScheme.primary,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: RowMetrics.bottomBarButtonSize,
        height: RowMetrics.bottomBarButtonSize,
      ),
      tooltip: tooltip,
      onPressed: onPressed,
    );
    if (identifier == null) return button;
    return AutomationId(identifier: identifier, child: button);
  }

  /// What this folder holds, read off the same paginated states the list
  /// renders from — the totals they already carry, so the bar costs no query
  /// of its own. Its own builders, because the bar is constructed before the
  /// list's and would otherwise trail it by a frame.
  Widget _buildCountLabel(BuildContext context) {
    return BlocBuilder<OptimizedFolderBloc, OptimizedFolderState>(
      buildWhen: FolderBlocFilters.forParentFolder(widget.folderId),
      builder: (context, blocFolderState) {
        return BlocBuilder<OptimizedNoteBloc, OptimizedNoteState>(
          buildWhen: NoteBlocFilters.forFolder(widget.folderId),
          builder: (context, blocNoteState) {
            final folderState = _ownFolders(blocFolderState);
            final noteState = _ownNotes(blocNoteState);
            final folderCount = folderState is OptimizedFolderLoaded
                ? folderState.paginatedFolders.totalCount
                : 0;
            final noteCount = _noteTotalCount(noteState);
            final label = _countText(
              AppLocalizations.of(context)!,
              folderCount: folderCount,
              noteCount: noteCount,
            );
            if (label.isEmpty) return const SizedBox.shrink();
            return Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: RowMetrics.bottomBarCountFontSize,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            );
          },
        );
      },
    );
  }

  int _noteTotalCount(OptimizedNoteState state) {
    if (widget.folderId == null) return 0;
    if (state is OptimizedNoteLoaded) return state.paginatedNotes.totalCount;
    if (state is OptimizedNoteContentLoaded &&
        state.previousPaginatedNotes != null) {
      return state.previousPaginatedNotes!.totalCount;
    }
    return 0;
  }

  /// "3 folders, 5 notes", or whichever half is non-empty. Two plural keys
  /// plus a joiner rather than one nested-plural message, so each half stays
  /// a translatable sentence in its own right.
  String _countText(
    AppLocalizations l10n, {
    required int folderCount,
    required int noteCount,
  }) {
    if (folderCount > 0 && noteCount > 0) {
      return l10n.folderAndNoteCount(
        l10n.folderCountLabel(folderCount),
        l10n.noteCountLabel(noteCount),
      );
    }
    if (folderCount > 0) return l10n.folderCountLabel(folderCount);
    if (noteCount > 0) return l10n.noteCountLabel(noteCount);
    return '';
  }

  /// Listens to [ImportExportBloc] from anywhere in the page subtree and
  /// surfaces a single loading dialog plus snackbars for export/import
  /// success and failure. The note and folder cards just dispatch events;
  /// all UI feedback funnels through here so behavior stays consistent
  /// whether the trigger came from a folder card or a note card.
  Widget _wrapWithImportExportListener(Widget child) {
    return BlocListener<ImportExportBloc, ImportExportState>(
      listener: _onImportExportState,
      child: child,
    );
  }

  void _onImportExportState(BuildContext context, ImportExportState state) {
    final operation = switch (state) {
      ImportExportInitial() => null,
      ImportExportInProgress() => state.operation,
      ImportExportExportSuccess() => state.operation,
      ImportExportImportSuccess() => state.operation,
      ImportExportFailure() => state.operation,
    };
    // The calendar's and the report's exports are answered by the page that
    // started them (`CalendarExportController`, D46): this page stays under
    // them on the stack, and its dialog and bar would stack over theirs.
    if (operation == ImportExportOperation.exportCalendar ||
        operation == ImportExportOperation.exportText) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    if (state is ImportExportInProgress) {
      if (_ioLoadingDialogOpen) return;
      _ioLoadingDialogOpen = true;
      AppDialogs.showLoading(
        context,
        message: _progressMessage(state.operation, l10n),
      );
      return;
    }

    if (state is ImportExportInitial) return;

    // Terminal state: pop the loading dialog once if it's still up.
    if (_ioLoadingDialogOpen) {
      _ioLoadingDialogOpen = false;
      AppNavigator.pop(context);
    }

    if (state is ImportExportFailure) {
      CustomSnackbar.showError(
        context,
        '${_failureMessage(state.operation, l10n)}: ${state.message}',
      );
    } else if (state is ImportExportImportSuccess) {
      final summary = l10n.importedSummary(
        state.result.foldersImported,
        state.result.notesImported,
      );
      final skipped = state.result.notesSkipped;
      // A file the import could not read is left out; without this line
      // the loss would read as a clean import.
      CustomSnackbar.showSuccess(
        context,
        skipped == 0
            ? summary
            : '$summary\n${l10n.importSkippedFiles(skipped)}',
      );
      // The import wrote new folders/notes; refresh the visible list so
      // the user sees them immediately.
      _refreshData();
    }
    // Reset the bloc back to Initial so the next operation starts from a
    // clean slate (also so the next InProgress emission triggers).
    context.read<ImportExportBloc>().add(const ImportExportReset());
  }

  String _progressMessage(ImportExportOperation op, AppLocalizations l10n) {
    switch (op) {
      case ImportExportOperation.exportNote:
        return l10n.exportingNote;
      case ImportExportOperation.exportFolder:
        return l10n.exportingFolder;
      case ImportExportOperation.exportItems:
        return l10n.exportingSelection;
      case ImportExportOperation.exportCalendar:
        return l10n.exportingEvents;
      case ImportExportOperation.exportText:
        return l10n.exportingReport;
      case ImportExportOperation.importFile:
      case ImportExportOperation.importArchive:
        return l10n.importingFile;
    }
  }

  String _failureMessage(ImportExportOperation op, AppLocalizations l10n) {
    switch (op) {
      case ImportExportOperation.exportNote:
        return l10n.noteExportError;
      case ImportExportOperation.exportFolder:
        return l10n.folderExportError;
      case ImportExportOperation.exportItems:
        return l10n.selectionExportError;
      case ImportExportOperation.exportCalendar:
        return l10n.eventsExportError;
      case ImportExportOperation.exportText:
        return l10n.reportExportError;
      case ImportExportOperation.importFile:
      case ImportExportOperation.importArchive:
        return l10n.importFileError;
    }
  }

  void _showQuickSortOptions() {
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              container: true,
              identifier: SemanticsIds.browserSortOpenFolders,
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(l10n.sortFolders),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  AppNavigator.pop(context);
                  _showFolderSortOptions();
                },
              ),
            ),
            if (widget.folderId != null)
              Semantics(
                container: true,
                identifier: SemanticsIds.browserSortOpenNotes,
                child: ListTile(
                  leading: const Icon(Icons.note_outlined),
                  title: Text(l10n.sortNotes),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    AppNavigator.pop(context);
                    _showNoteSortOptions();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The two sort sheets are twins and scroll for the same reason: seven
  /// note orders plus a header come to roughly 450 dp, which is over
  /// [showModalBottomSheet]'s 9/16 cap on a 360x800 phone and well over it on
  /// a 360x640 one. Scrolling is how every other tall sheet in the app copes
  /// (see `showRowActionSheet`); a fixed [Column] simply overflows.
  void _showFolderSortOptions() {
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.folder_outlined),
                    const SizedBox(width: 12),
                    Text(
                      l10n.sortFolders,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              _buildSortOption(
                identifier: SemanticsIds.browserSortFolderNameAsc,
                icon: Icons.sort_by_alpha,
                title: '${l10n.sortByName} (A-Z)',
                isSelected: _foldersSortOrder == FoldersSortOrder.nameAsc,
                onTap: () {
                  AppNavigator.pop(context);
                  _sortFoldersBy(FoldersSortOrder.nameAsc);
                },
              ),
              _buildSortOption(
                identifier: SemanticsIds.browserSortFolderNameDesc,
                icon: Icons.sort_by_alpha,
                title: '${l10n.sortByName} (Z-A)',
                isSelected: _foldersSortOrder == FoldersSortOrder.nameDesc,
                onTap: () {
                  AppNavigator.pop(context);
                  _sortFoldersBy(FoldersSortOrder.nameDesc);
                },
              ),
              _buildSortOption(
                identifier: SemanticsIds.browserSortFolderCreatedDesc,
                icon: Icons.calendar_today,
                title: '${l10n.sortByCreated} (${l10n.descending})',
                isSelected: _foldersSortOrder == FoldersSortOrder.createdDesc,
                onTap: () {
                  AppNavigator.pop(context);
                  _sortFoldersBy(FoldersSortOrder.createdDesc);
                },
              ),
              _buildSortOption(
                identifier: SemanticsIds.browserSortFolderCreatedAsc,
                icon: Icons.calendar_today,
                title: '${l10n.sortByCreated} (${l10n.ascending})',
                isSelected: _foldersSortOrder == FoldersSortOrder.createdAsc,
                onTap: () {
                  AppNavigator.pop(context);
                  _sortFoldersBy(FoldersSortOrder.createdAsc);
                },
              ),
              _buildSortOption(
                identifier: SemanticsIds.browserSortFolderLabel,
                icon: Icons.label_outline,
                title: l10n.sortByLabel,
                isSelected: _foldersSortOrder == FoldersSortOrder.labelAsc,
                onTap: () {
                  AppNavigator.pop(context);
                  _sortFoldersBy(FoldersSortOrder.labelAsc);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Scrolls for the reason [_showFolderSortOptions] gives — this is the
  /// taller of the twins.
  void _showNoteSortOptions() {
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.note_outlined),
                    const SizedBox(width: 12),
                    Text(
                      l10n.sortNotes,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              _buildSortOption(
                identifier: SemanticsIds.browserSortNoteTitleAsc,
                icon: Icons.sort_by_alpha,
                title: '${l10n.sortByTitle} (A-Z)',
                isSelected: _notesSortOrder == NotesSortOrder.titleAsc,
                onTap: () {
                  AppNavigator.pop(context);
                  _sortNotesBy(NotesSortOrder.titleAsc);
                },
              ),
              _buildSortOption(
                identifier: SemanticsIds.browserSortNoteTitleDesc,
                icon: Icons.sort_by_alpha,
                title: '${l10n.sortByTitle} (Z-A)',
                isSelected: _notesSortOrder == NotesSortOrder.titleDesc,
                onTap: () {
                  AppNavigator.pop(context);
                  _sortNotesBy(NotesSortOrder.titleDesc);
                },
              ),
              _buildSortOption(
                identifier: SemanticsIds.browserSortNoteUpdatedDesc,
                icon: Icons.update,
                title: '${l10n.sortByUpdated} (${l10n.descending})',
                isSelected: _notesSortOrder == NotesSortOrder.updatedDesc,
                onTap: () {
                  AppNavigator.pop(context);
                  _sortNotesBy(NotesSortOrder.updatedDesc);
                },
              ),
              _buildSortOption(
                identifier: SemanticsIds.browserSortNoteUpdatedAsc,
                icon: Icons.update,
                title: '${l10n.sortByUpdated} (${l10n.ascending})',
                isSelected: _notesSortOrder == NotesSortOrder.updatedAsc,
                onTap: () {
                  AppNavigator.pop(context);
                  _sortNotesBy(NotesSortOrder.updatedAsc);
                },
              ),
              _buildSortOption(
                identifier: SemanticsIds.browserSortNoteCreatedDesc,
                icon: Icons.calendar_today,
                title: '${l10n.sortByCreated} (${l10n.descending})',
                isSelected: _notesSortOrder == NotesSortOrder.createdDesc,
                onTap: () {
                  AppNavigator.pop(context);
                  _sortNotesBy(NotesSortOrder.createdDesc);
                },
              ),
              _buildSortOption(
                identifier: SemanticsIds.browserSortNoteCreatedAsc,
                icon: Icons.calendar_today,
                title: '${l10n.sortByCreated} (${l10n.ascending})',
                isSelected: _notesSortOrder == NotesSortOrder.createdAsc,
                onTap: () {
                  AppNavigator.pop(context);
                  _sortNotesBy(NotesSortOrder.createdAsc);
                },
              ),
              _buildSortOption(
                identifier: SemanticsIds.browserSortNoteLabel,
                icon: Icons.label_outline,
                title: l10n.sortByLabel,
                isSelected: _notesSortOrder == NotesSortOrder.labelAsc,
                onTap: () {
                  AppNavigator.pop(context);
                  _sortNotesBy(NotesSortOrder.labelAsc);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortOption({
    required String identifier,
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final tile = ListTile(
      leading: Icon(icon, color: isSelected ? colorScheme.primary : null),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? colorScheme.primary : null,
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: colorScheme.primary)
          : null,
      onTap: onTap,
    );
    return Semantics(container: true, identifier: identifier, child: tile);
  }

  void _sortFoldersBy(FoldersSortOrder order) {
    setState(() {
      _foldersSortOrder = order;
      _localMixed = null;
    });
    context.read<OptimizedFolderBloc>().add(
      LoadFoldersPaginated(parentId: widget.folderId, sortOrder: order),
    );
    // Persist sort preference
    if (widget.folderId != null) {
      _folderStorageService.updateFolderSortPreferences(
        folderId: widget.folderId!,
        subfolderSortOrder: order.name,
      );
    }
  }

  void _sortNotesBy(NotesSortOrder order) {
    setState(() {
      _notesSortOrder = order;
      _localMixed = null;
    });
    context.read<OptimizedNoteBloc>().add(
      LoadNotesPaginated(folderId: widget.folderId, sortOrder: order),
    );
    // Persist sort preference
    if (widget.folderId != null) {
      _folderStorageService.updateFolderSortPreferences(
        folderId: widget.folderId!,
        noteSortOrder: order.name,
      );
    }
  }

  // ─── This folder's own actions (app-bar overflow menu) ──────────────────

  /// The active ordering, for the menu's sort row. A folder's notes are what
  /// the user reorders; the root has none, so it reports its folder order.
  String _sortLabel(AppLocalizations l10n) {
    if (widget.folderId == null) {
      return switch (_foldersSortOrder) {
        FoldersSortOrder.nameAsc ||
        FoldersSortOrder.nameDesc => l10n.sortByName,
        FoldersSortOrder.createdAsc ||
        FoldersSortOrder.createdDesc => l10n.sortByCreated,
        FoldersSortOrder.positionAsc ||
        FoldersSortOrder.positionDesc => l10n.sortByCustom,
        FoldersSortOrder.labelAsc => l10n.sortByLabel,
      };
    }
    return switch (_notesSortOrder) {
      NotesSortOrder.updatedAsc ||
      NotesSortOrder.updatedDesc => l10n.sortByUpdated,
      NotesSortOrder.createdAsc ||
      NotesSortOrder.createdDesc => l10n.sortByCreated,
      NotesSortOrder.titleAsc || NotesSortOrder.titleDesc => l10n.sortByTitle,
      NotesSortOrder.positionAsc ||
      NotesSortOrder.positionDesc => l10n.sortByCustom,
      NotesSortOrder.labelAsc => l10n.sortByLabel,
    };
  }

  String? _eyebrowLabel(BuildContext context) {
    final ancestors = _ancestors;
    if (ancestors == null) return null;
    if (ancestors.isEmpty) return AppLocalizations.of(context)!.folders;
    return ancestors.last.name;
  }

  void _showAncestorMenu(BuildContext anchorContext) {
    final ancestors = _ancestors;
    if (ancestors == null) return;
    showFolderAncestorMenu(
      anchorContext,
      ancestors: ancestors,
      rootLabel: AppLocalizations.of(context)!.folders,
      onSelected: (folder) {
        if (!mounted) return;
        AppNavigator.popToAncestor(
          context,
          folderId: folder?.id,
          title: folder?.name,
          fromPartner: folder?.fromPartner,
        );
      },
    );
  }

  Future<void> _renameCurrentFolder() async {
    final folder = _folder;
    if (folder == null) return;
    final l10n = AppLocalizations.of(context)!;
    final name = await AppDialogs.textInput(
      context,
      title: l10n.renameFolder,
      hintText: l10n.enterNewName,
      initialValue: folder.name,
    );
    if (name == null || !mounted) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed.toLowerCase() == folder.name.trim().toLowerCase()) {
      return;
    }
    final exists = await _folderStorageService.folderNameExistsInParent(
      parentId: folder.parentId,
      name: trimmed,
      excludeId: folder.id,
    );
    if (!mounted) return;
    if (exists) {
      CustomSnackbar.showError(context, l10n.folderNameAlreadyExists(trimmed));
      return;
    }
    context.read<OptimizedFolderBloc>().add(
      UpdateOptimizedFolder(folderId: folder.id, name: trimmed),
    );
    setState(() => _folder = folder.copyWith(name: trimmed));
  }

  Future<void> _moveCurrentFolder() async {
    final folder = _folder;
    if (folder == null) return;
    await MoveCoordinator.moveFolder(
      context,
      folder: folder,
      currentParentId: folder.parentId,
    );
    if (!mounted) return;
    final moved = await _folderStorageService.getFolderById(folder.id);
    if (!mounted || moved == null) return;
    setState(() => _folder = moved);
    await _loadAncestors();
  }

  void _shareCurrentFolder() {
    final folder = _folder;
    if (folder == null) return;
    context.read<ImportExportBloc>().add(
      ExportFolderRequested(folderId: folder.id, share: true),
    );
  }

  // ─── Sharing with the partner (share surfaces §6.11–§6.12) ──────────────

  /// This page shows the partner's folder, at any depth: nothing on it
  /// writes, and the line under the bar says so.
  ///
  /// Known before the folder is read — from the opener, else from the
  /// warm caches ([_openedAsPartners]) — so neither the create bar nor the
  /// line changes after the first frame; a folder of mine waits for nothing.
  bool get _readOnly => _folder?.fromPartner ?? _openedAsPartners;

  /// Whose the folder is as the page could tell at its first frame: the
  /// opener's word, or the census and folder cache when they are warm.
  late final bool _openedAsPartners =
      widget.fromPartner ??
      (widget.folderId == null
          ? false
          : _folderStorageService.knownFromPartner(widget.folderId!) ?? false);

  /// A partner's page holds the line and the rows under it until the line's
  /// words — the partner's name and face — are known, as the read-only note
  /// editor does: with a long name the line would otherwise grow under the
  /// finger. The bar above them is drawn meanwhile, back button and all, so
  /// the hold is never a bare ground with no way back. A folder of mine
  /// never holds.
  bool get _holdsForLook =>
      _readOnly && _partnerLook.value == null && _partnerLook.pending;

  /// "From {name} · Read only", pinned under the bar (§16.8 fd).
  Widget _buildPartnerLine(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final look = _partnerLook.value;
    return SharedReadOnlyLine(
      partner: look?.partner,
      text: ShareCopy.sentence(
        l10n.sharedNoteLine(ShareCopy.partnerName(l10n, look?.name)),
      ),
      identifier: SemanticsIds.browserPartnerLine,
    );
  }

  /// [folder]'s share entry, from what the page last heard of sharing; the
  /// folder whose mark covers it is this page's own or one above it.
  FolderShareEntry? _shareEntryFor(Folder folder) => FolderShareEntry.resolve(
    AppLocalizations.of(context)!,
    folder,
    availability: _partnerLook.availability,
    folderName: (id) => [
      ?_folder,
      ...?_ancestors,
    ].where((ancestor) => ancestor.id == id).firstOrNull?.name,
  );

  /// Shares [folder], or stops its own mark, and says what that did in the
  /// Sharing page's words, with an Undo that still works once this page is
  /// gone — a failure of it is said on the app's messenger.
  ///
  /// Fenced by the database the tap was made under: a switch before the
  /// write writes nothing, and an answer that lands after one says nothing
  /// here. An act that wrote nothing says what
  /// is true of what was asked — a share found it shared already; a stop
  /// that found no mark (another device cleared it) says nothing.
  ///
  /// Neither the act nor its Undo reloads the page itself: the service
  /// forgets the share census as it writes, and that forget reloads every
  /// open folder page, this one with them ([_scheduleShareRefresh]) — once.
  Future<void> _toggleShared(Folder folder) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final name = _partnerLook.value?.name;
    final generation = ShareService.databaseGeneration;
    final on = !folder.share.isByMark;
    final ShareChange change;
    try {
      final service = await PartnerLookReader.service();
      // A switch while the service was fetched hands back the new
      // database's, which must not take an act tapped under the old one.
      if (ShareService.databaseGeneration != generation) return;
      change = await service.setFolderShared(folder.id, on);
    } on ShareRefused {
      if (mounted && ShareService.databaseGeneration == generation) {
        CustomSnackbar.showError(context, l10n.shareNeedsSync);
      }
      return;
    } catch (e, st) {
      debugPrint('[FolderPage] share not written: $e\n$st');
      if (mounted && ShareService.databaseGeneration == generation) {
        CustomSnackbar.showError(context, l10n.shareChangeFailed);
      }
      return;
    }
    if (!mounted || ShareService.databaseGeneration != generation) return;
    final message = ShareCopy.folderAct(l10n, change, partnerName: name);
    if (message == null) {
      if (on) {
        CustomSnackbar.show(context, l10n.shareFolderAlready(folder.name));
      }
      return;
    }
    CustomSnackbar.showWithAction(
      context,
      message: message,
      actionLabel: l10n.undo,
      actionIdentifier: SemanticsIds.snackbarUndo,
      onAction: () async {
        if (ShareService.databaseGeneration != generation) return;
        await undoSharePastBloc(
          change,
          shareService: PartnerLookReader.service,
          messenger: messenger,
          l10n: l10n,
        );
      },
    );
  }

  /// The signs follow a forget of the share census: the rows and this
  /// page's own folder are read again, past the caches the forget dropped.
  /// It forgets nothing itself — a forget is what [_scheduleShareRefresh]
  /// hears, and a second would loop.
  Future<void> _reloadShares() async {
    _loadData();
    if (_partnerAsked) unawaited(_loadPartnerFolders());
    final folderId = widget.folderId;
    if (folderId == null) return;
    final folder = await _folderStorageService.getFolderById(folderId);
    if (!mounted || folder == null) return;
    setState(() => _folder = folder);
    await _loadAncestors();
  }

  /// Asks first unless "Confirm before delete" is off, as the folder row does
  /// (record D24a); off, the note count only the dialog shows is not looked
  /// up either.
  Future<void> _deleteCurrentFolder() async {
    final folder = _folder;
    if (folder == null) return;
    final l10n = AppLocalizations.of(context)!;
    final settings = await SettingsService.getInstance();
    final confirm = await settings.getConfirmDelete();
    if (!mounted) return;
    if (confirm) {
      // Popped through the navigator taken now, as the folder row does: a
      // count that throws, or a page unmounted during it, must not leave the
      // undismissable dialog up for good.
      final navigator = Navigator.of(context);
      AppDialogs.showLoading(context, message: l10n.loadingContent);
      int? noteCount;
      Object? failure;
      try {
        noteCount = await _folderStorageService.getNoteCountForDeletion(
          folder.id,
        );
      } catch (e, st) {
        debugPrint('[FolderContent] delete note count failed: $e\n$st');
        failure = e;
      } finally {
        navigator.pop();
      }
      if (!mounted) return;
      if (noteCount == null) {
        CustomSnackbar.showError(context, l10n.error('$failure'));
        return;
      }

      final confirmed = await AppDialogs.confirm(
        context,
        title: l10n.deleteFolder,
        content: noteCount > 0
            ? l10n.deleteFolderWithNotesConfirm(folder.name, noteCount)
            : l10n.deleteFolderConfirm(folder.name),
        confirmText: l10n.delete,
        isDestructive: true,
      );
      if (!confirmed || !mounted) return;
    }
    context.read<OptimizedFolderBloc>().add(
      DeleteOptimizedFolder(folderId: folder.id, parentId: folder.parentId),
    );
    AppNavigator.pop(context);
  }

  // ─── Unified mixed (folders + notes) sliver ─────────────────────────────

  /// Top-level slivers list selector. The mixed sliver is the *only* visible
  /// list in both modes — it just toggles between a reorderable list (in
  /// selection mode) and an infinite-scroll list (otherwise), over the same
  /// rows in the same order, so nothing moves when selection starts.
  ///
  /// Ordering is grouped, not interleaved: every folder, then every note,
  /// each in its own sort order, with a section label above each group when
  /// both are present. The two `position` columns still share one index
  /// space, so a drag inside either group persists exactly as before — the
  /// cross-kind orderings that space could express are simply no longer
  /// drawn.
  List<Widget> _buildContentSlivers({required bool isSelecting}) {
    return [
      if (widget.folderId == null)
        _buildSmartRowsSliver(isSelecting: isSelecting),
      _buildMixedSliver(isSelecting: isSelecting),
    ];
  }

  /// The root's two ways into the notes underneath its folders: every note
  /// there is, and the handful touched most recently.
  ///
  /// They are their own group above the folders, not entries in the list: a
  /// smart row has no position, cannot be selected, renamed or dragged, and
  /// giving it a slot in the reorderable sliver would offer all four.
  ///
  /// Selection mode disables them where it used to drop them. Removing two
  /// rows and their label from above the list is a height the bar swap does
  /// not pay for, so the folders underneath jumped; dimmed and unreachable
  /// they hold their space and stay outside the reorderable sliver, which is
  /// what kept them unselectable in the first place.
  Widget _buildSmartRowsSliver({required bool isSelecting}) {
    final l10n = AppLocalizations.of(context)!;
    final count = _allNotesCount;
    final rows = Column(
      children: [
        _SmartRow(
          icon: Icons.description_outlined,
          label: l10n.allNotes,
          count: count,
          position: RowGroupPosition.first,
          identifier: SemanticsIds.drawerAllNotes,
          onTap: () => AppNavigator.toAllNotes(context),
        ),
        _SmartRow(
          icon: Icons.schedule_outlined,
          label: l10n.recent,
          position: RowGroupPosition.last,
          identifier: SemanticsIds.drawerRecent,
          onTap: () => AppNavigator.toRecentNotes(context),
        ),
      ],
    );
    return SliverToBoxAdapter(
      child: isSelecting
          ? ExcludeSemantics(
              child: IgnorePointer(child: Opacity(opacity: 0.38, child: rows)),
            )
          : rows,
    );
  }

  MovableItemRef _refForContentItem(ContentItem item) => switch (item) {
    FolderItem(:final folder) => _refForFolder(folder),
    NoteItem(:final metadata) => _refForNote(metadata),
  };

  Widget _buildMixedSliver({required bool isSelecting}) {
    return BlocBuilder<OptimizedFolderBloc, OptimizedFolderState>(
      buildWhen: FolderBlocFilters.forParentFolder(widget.folderId),
      builder: (context, blocFolderState) {
        return BlocBuilder<OptimizedNoteBloc, OptimizedNoteState>(
          buildWhen: NoteBlocFilters.forFolder(widget.folderId),
          builder: (context, blocNoteState) {
            final folderState = _ownFolders(blocFolderState);
            final noteState = _ownNotes(blocNoteState);
            if (noteState is OptimizedNoteLoaded &&
                noteState.folderId == widget.folderId) {
              _notePages = noteState.paginatedNotes.currentPage;
            }
            // Kick the bloc on cold-start only. After the first load, the
            // bloc transitions through Loading on every refresh / sort
            // change; we deliberately do NOT clear our cached [_localMixed]
            // in that window so the UI keeps showing the last known list
            // instead of flashing to a spinner.
            // A stack restored at launch builds every page in one frame;
            // only the one in front may take the bloc.
            // Asked of the bloc, not of the state this builder holds: a
            // page built before the bloc answered anything holds Initial
            // for good — later states fail its `buildWhen` — and once
            // revealed it would load through Loading on top of the quiet
            // refresh its return already sent, emptying the count for the
            // frames between.
            if (context.read<OptimizedFolderBloc>().state
                    is OptimizedFolderInitial &&
                _inFront()) {
              context.read<OptimizedFolderBloc>().add(
                LoadFoldersPaginated(
                  parentId: widget.folderId,
                  sortOrder: _foldersSortOrder,
                ),
              );
            }

            // Surface errors prominently — but only if we have no prior data
            // to show. With cached data, a transient error mid-refresh would
            // wipe the screen which is worse UX than just keeping the stale
            // list visible.
            if (folderState is OptimizedFolderError && _localMixed == null) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      AppLocalizations.of(context)!.error(folderState.message),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              );
            }

            final folders = folderState is OptimizedFolderLoaded
                ? folderState.paginatedFolders.folders
                : const <Folder>[];
            final notes = widget.folderId == null
                ? const <NoteMetadata>[]
                : (NoteStateHelper.getNotesForFolder(
                        noteState,
                        widget.folderId,
                      ) ??
                      const <NoteMetadata>[]);

            // Detect the "this state has no fresh data" case (Loading,
            // Initial, Error). Without this, a reorder dispatch that
            // triggers Loading would feed empty lists into the grouping
            // and we would render an empty sliver for one frame — exactly
            // the white flash this method exists to prevent.
            final folderHasData = folderState is OptimizedFolderLoaded;
            final noteHasData =
                widget.folderId == null ||
                noteState is OptimizedNoteLoaded ||
                noteState is OptimizedNoteContentLoaded;

            if (!folderHasData || !noteHasData) {
              // No fresh data this build. If we have a previous render,
              // reuse it verbatim; otherwise show the cold-start spinner.
              if (_localMixed != null &&
                  (_localMixed!.isNotEmpty || _partnerFolders.isNotEmpty)) {
                return _buildMixedListFromDisplay(
                  display: _localMixed!,
                  isSelecting: isSelecting,
                  hasMore: false,
                  isLoadingMore: false,
                );
              }
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final holdsShared = _folderStorageService.holdsShared;
            final holdsPair = _folderStorageService.holdsPair;
            if (_folderStorageService.censusKnown) {
              _heldShared = holdsShared;
              _heldPair = holdsPair;
            }
            if (PartnerLookReader.mayShare(
              holdsShared: holdsShared,
              paired: holdsPair,
            )) {
              _partnerLook.start(asker: (folderState, noteState));
            }
            if (widget.folderId == null && holdsShared && !_partnerAsked) {
              _partnerAsked = true;
              unawaited(_loadPartnerFolders());
            }

            // Keep the SelectAll source-of-truth in sync with what's visible.
            _visibleFolders = folders;
            _visibleNotes = notes;
            _loadFolderCounts([
              for (final f in folders) f.id,
              for (final f in _partnerFolders) f.id,
            ]);

            // Kick off a small content preload for the first few notes so
            // tapping in feels instant. Was previously done by the notes
            // section; keep behavior parity here.
            if (notes.isNotEmpty) {
              _preloadNoteContent(notes.take(3).map((n) => n.id).toList());
            }

            if (folders.isEmpty && notes.isEmpty && _partnerFolders.isEmpty) {
              _localMixed = null;
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            }

            final grouped = groupFoldersThenNotes(
              folders: folders,
              notes: notes,
            );
            final display = _syncLocal<ContentItem>(
              _localMixed,
              grouped,
              (i) => i.id,
            );
            _localMixed = display;

            final hasMore = widget.folderId != null
                ? NoteStateHelper.hasMoreForFolder(noteState, widget.folderId)
                : false;
            final isLoadingMore = noteState is OptimizedNoteLoaded
                ? NoteStateHelper.isLoadingMore(noteState)
                : false;

            return _buildMixedListFromDisplay(
              display: display,
              isSelecting: isSelecting,
              hasMore: hasMore,
              isLoadingMore: isLoadingMore,
            );
          },
        );
      },
    );
  }

  /// The flat row sequence for [items]: a section label above each group,
  /// then that group's rows carrying the corner and divider treatment that
  /// makes a run of them read as one card.
  ///
  /// Labels appear when both groups are present. A folder full of notes does
  /// not need to be told they are notes — except at the root, where the smart
  /// rows sit above and the label is what separates them from the folders
  /// rather than the folders from the notes, which is why the root always
  /// labels, selection mode included: the smart rows stay drawn there.
  List<_RowEntry> _buildEntries(
    List<ContentItem> items,
    AppLocalizations l10n,
  ) {
    final folders = [
      for (final item in items)
        if (item is FolderItem) item,
    ];
    final notes = [
      for (final item in items)
        if (item is NoteItem) item,
    ];
    final labelled =
        (folders.isNotEmpty && notes.isNotEmpty) || widget.folderId == null;
    final entries = <_RowEntry>[];

    void addGroup(List<ContentItem> group, String label) {
      if (group.isEmpty) return;
      if (labelled) entries.add(_SectionEntry(label));
      for (var i = 0; i < group.length; i++) {
        entries.add(
          _ItemEntry(group[i], _positionIn(index: i, length: group.length)),
        );
      }
    }

    addGroup(folders, l10n.folders);
    final partner = _partnerFolders;
    if (partner.isNotEmpty) {
      entries.add(
        _SectionEntry(
          l10n.shareFromPartner(
            ShareCopy.partnerName(l10n, _partnerLook.value?.name),
          ),
          identifier: SemanticsIds.browserSectionPartner,
        ),
      );
      for (var i = 0; i < partner.length; i++) {
        entries.add(
          _PartnerEntry(
            partner[i],
            _positionIn(index: i, length: partner.length),
          ),
        );
      }
    }
    addGroup(notes, l10n.notes);
    return entries;
  }

  RowGroupPosition _positionIn({required int index, required int length}) {
    if (length == 1) return RowGroupPosition.single;
    if (index == 0) return RowGroupPosition.first;
    if (index == length - 1) return RowGroupPosition.last;
    return RowGroupPosition.middle;
  }

  /// Render the actual sliver (reorderable in selection mode, otherwise
  /// infinite-scroll) from a final [display] list. Extracted so the
  /// "reuse cached list during a transient Loading state" path and the
  /// fresh-data path produce the same widget tree (no re-creation jank).
  ///
  /// There is exactly one reorderable sliver over the whole sequence,
  /// headers included: two would let a drag leave one and never arrive in
  /// the other. Headers carry no drag listener, so they cannot be lifted,
  /// and [_onReorderEntry] refuses to let a row land outside its own group.
  Widget _buildMixedListFromDisplay({
    required List<ContentItem> display,
    required bool isSelecting,
    required bool hasMore,
    required bool isLoadingMore,
  }) {
    final entries = _buildEntries(display, AppLocalizations.of(context)!);
    _entries = entries;

    if (isSelecting) {
      return SliverReorderableList(
        itemCount: entries.length,
        proxyDecorator: (child, index, animation) =>
            _buildReorderProxy(child, animation, _selection.count),
        onReorderStart: (_) => _onReorderStart(),
        onReorderEnd: (_) => _onReorderEnd(),
        onReorderItem: _onReorderEntry,
        itemBuilder: (context, index) =>
            _buildEntry(entries[index], index, isSelecting: true),
      );
    }

    return InfiniteScrollSliver<_RowEntry>(
      items: entries,
      hasMore: hasMore,
      isLoadingMore: isLoadingMore,
      controller: _scrollController,
      onLoadMore: () {
        context.read<OptimizedNoteBloc>().add(
          LoadMoreNotes(folderId: widget.folderId),
        );
      },
      itemBuilder: (context, entry, index) =>
          _buildEntry(entry, index, isSelecting: false),
    );
  }

  /// Single source of truth for rendering a row, used by both the reorderable
  /// and the infinite-scroll branches. [isSelecting] toggles the drag handle
  /// (`isReorderMode`) — outside of selection the rows show their menu.
  Widget _buildEntry(_RowEntry entry, int index, {required bool isSelecting}) {
    switch (entry) {
      case _SectionEntry(:final label, :final identifier):
        return KeyedSubtree(
          key: ValueKey('section:$label'),
          child: ContentSectionHeader(label: label, identifier: identifier),
        );
      case _PartnerEntry(:final folder, :final position):
        final row = FolderRow(
          key: isSelecting ? null : ValueKey('folder:${folder.id}'),
          folder: folder,
          noteCount: _folderNoteCounts[folder.id],
          groupPosition: position,
          onReturn: _loadData,
          partnerLook: _partnerLook.value,
        );
        if (!isSelecting) return row;
        // Drawn, so the root keeps its shape, but out of reach: the
        // partner's folder takes part in no selection, drop or reorder.
        return Opacity(
          key: ValueKey('folder:${folder.id}'),
          opacity: FormMetrics.disabledOpacity,
          child: IgnorePointer(child: row),
        );
      case _ItemEntry(:final item, :final position):
        switch (item) {
          case FolderItem(:final folder):
            return FolderRow(
              key: ValueKey('folder:${folder.id}'),
              folder: folder,
              parentId: widget.folderId,
              noteCount: _folderNoteCounts[folder.id],
              groupPosition: position,
              onReturn: _loadData,
              isReorderMode: isSelecting,
              index: isSelecting ? index : null,
              isMultiDragging: _isDraggingMulti,
              selection: _selection,
              onLongPressItem: _onCardLongPress,
              onTapInSelection: _onCardTapInSelection,
              onAcceptDrop: _onDropOnFolder,
              partnerLook: _partnerLook.value,
              partnerShare: () => _shareEntryFor(folder),
              onPartnerShare: () => _toggleShared(folder),
            );
          case NoteItem(:final metadata):
            return NoteRow(
              key: ValueKey('note:${metadata.id}'),
              metadata: metadata,
              folderId: widget.folderId!,
              groupPosition: position,
              showPreview: _showNotePreview,
              onReturn: _loadData,
              isReorderMode: isSelecting,
              index: isSelecting ? index : null,
              isMultiDragging: _isDraggingMulti,
              selection: _selection,
              onLongPressItem: _onCardLongPress,
              onTapInSelection: _onCardTapInSelection,
              partnerLook: _partnerLook.value,
            );
        }
    }
  }

  /// Turns a drop on the flat row list into a reorder of the content items,
  /// clamped to the dragged row's own group.
  ///
  /// `onReorderItem` reports [newIndex] against the list with the dragged row
  /// already removed, so the group's bounds are measured there too: the
  /// insertion point may sit anywhere from the group's first row to just past
  /// its last. A drop aimed at a header, or across the boundary into the
  /// other group, lands at the nearest edge of the group it started in.
  void _onReorderEntry(int oldIndex, int newIndex) {
    final entries = _entries;
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    final moved = entries[oldIndex];
    if (moved is! _ItemEntry) return;

    final remaining = [...entries]..removeAt(oldIndex);
    final kind = moved.item.kind;
    var lower = -1;
    var upper = -1;
    for (var i = 0; i < remaining.length; i++) {
      final entry = remaining[i];
      if (entry is _ItemEntry && entry.item.kind == kind) {
        if (lower < 0) lower = i;
        upper = i;
      }
    }
    final target = lower < 0 ? newIndex : newIndex.clamp(lower, upper + 1);

    final source = [
      for (final entry in entries)
        if (entry is _ItemEntry) entry.item,
    ];
    final contentOld = _contentIndexBefore(entries, oldIndex);
    final contentNew = _contentIndexBefore(remaining, target);
    if (contentOld >= source.length) return;

    final reordered = _applyMultiReorder<ContentItem>(
      source: source,
      oldIndex: contentOld,
      newIndex: contentNew,
      refOf: _refForContentItem,
    );
    _handleReorderMixed(regroupFoldersThenNotes(reordered));
  }

  int _contentIndexBefore(List<_RowEntry> entries, int rowIndex) {
    var count = 0;
    for (var i = 0; i < rowIndex && i < entries.length; i++) {
      if (entries[i] is _ItemEntry) count++;
    }
    return count;
  }

  /// Persist a unified folder+note ordering: flips the sort of each kind the
  /// drag reordered to position-based (so the next refresh preserves what the
  /// user just did), persists the preference, then writes those kinds via
  /// [MixedReorderService]. A kind the drag left alone keeps its sort and its
  /// rows.
  void _handleReorderMixed(List<ContentItem> reordered) {
    debugPrint(
      '[Reorder] mixed: applying optimistic order '
      '${reordered.map((i) => '${i.kind.name}:${i.displayName('')}').toList()}',
    );
    List<String> idsOf(List<ContentItem> items, MovableItemKind kind) => [
      for (final item in items)
        if (item.kind == kind) item.id,
    ];
    final before = _localMixed ?? const <ContentItem>[];
    final changed = {
      for (final kind in MovableItemKind.values)
        if (!listEquals(idsOf(before, kind), idsOf(reordered, kind))) kind,
    };
    setState(() {
      _localMixed = List<ContentItem>.from(reordered);
      // A drop that changed nothing writes nothing, so no load would ever
      // confirm it and end the pending state.
      _reorderPending = changed.isNotEmpty;
    });
    if (changed.isEmpty) return;

    // Drags are written one after another. A drop made while an earlier
    // write is still in flight is queued and decides its sort flip, its
    // rollback point and its `windowAtTop` only when its turn comes; if the
    // earlier write failed, the page has rolled back to the stored order and
    // the queued drop — made on top of the failed one — is dropped with it.
    // A queued drop is written even after the page is popped: the write
    // touches only plain fields until it lands, and [_writeOrder] checks
    // `mounted` before it reloads.
    final epoch = _dragEpoch;
    final previous = _dragChain ?? Future<void>.value();
    final run = previous.then((_) {
      if (epoch != _dragEpoch) return null;
      return _commitDrag(reordered, changed);
    });
    // The chain carries on past a throw, so one bad drop cannot strand every
    // drop queued after it — the shape of `MixedReorderService._serialised`.
    // Reported, not swallowed: a bug here shows in debug and fails a test.
    _dragChain = run.catchError((Object e, StackTrace st) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: e, stack: st, library: 'browser'),
      );
    });
  }

  /// The tail of the drags waiting to be written, in drop order.
  Future<void>? _dragChain;

  /// Moved on by a failed write, so drops queued behind it are discarded.
  int _dragEpoch = 0;

  /// Flips the sort of each [changed] kind still sorted otherwise to Custom,
  /// saves it, and writes the drag ([_writeOrder]).
  Future<void> _commitDrag(
    List<ContentItem> reordered,
    Set<MovableItemKind> changed,
  ) {
    final previousSorts = (folders: _foldersSortOrder, notes: _notesSortOrder);
    final flipped = <MovableItemKind>{};
    if (changed.contains(MovableItemKind.folder) &&
        _foldersSortOrder != FoldersSortOrder.positionAsc &&
        _foldersSortOrder != FoldersSortOrder.positionDesc) {
      _foldersSortOrder = FoldersSortOrder.positionAsc;
      flipped.add(MovableItemKind.folder);
    }
    if (widget.folderId != null &&
        changed.contains(MovableItemKind.note) &&
        _notesSortOrder != NotesSortOrder.positionAsc &&
        _notesSortOrder != NotesSortOrder.positionDesc) {
      _notesSortOrder = NotesSortOrder.positionAsc;
      flipped.add(MovableItemKind.note);
    }
    if (flipped.isNotEmpty && widget.folderId != null) {
      _folderStorageService.updateFolderSortPreferences(
        folderId: widget.folderId!,
        subfolderSortOrder: _foldersSortOrder.name,
        noteSortOrder: _notesSortOrder.name,
      );
    }

    return _writeOrder(
      reordered,
      changed: changed,
      flipped: flipped,
      previousSorts: previousSorts,
    );
  }

  /// Writes a drag's [changed] kinds, then reloads them — in the new Custom
  /// sort for the [flipped] kinds, whose loaded window goes on top of the
  /// group, the way the user saw it.
  ///
  /// The reload is dispatched only once the write has landed: sent at the
  /// drop, it raced the write's own refresh, and when the pre-write read
  /// arrived last the page adopted the pre-drag order. It is also what ends
  /// [_reorderPending] when the write moved no row and so announced nothing.
  /// A failed write ends it too, puts back the sorts the drag turned to
  /// Custom ([previousSorts]) — an order the user never chose and nothing
  /// stored — and reloads.
  Future<void> _writeOrder(
    List<ContentItem> reordered, {
    required Set<MovableItemKind> changed,
    required Set<MovableItemKind> flipped,
    required ({FoldersSortOrder folders, NotesSortOrder notes}) previousSorts,
  }) async {
    try {
      await _mixedReorderService.reorderMixed(
        parentId: widget.folderId,
        items: [
          for (final item in reordered)
            if (changed.contains(item.kind)) item,
        ],
        foldersDescending: _foldersSortOrder == FoldersSortOrder.positionDesc,
        notesDescending: _notesSortOrder == NotesSortOrder.positionDesc,
        windowAtTop: flipped,
      );
    } catch (e, st) {
      debugPrint('[Reorder] write failed: $e\n$st');
      _dragEpoch++;
      _foldersSortOrder = previousSorts.folders;
      _notesSortOrder = previousSorts.notes;
      // Saved back even when the page is gone: the flip to Custom was already
      // stored, and the folder would reopen under it over the old positions.
      if (flipped.isNotEmpty && widget.folderId != null) {
        // The reload below must run even if this save fails too.
        try {
          await _folderStorageService.updateFolderSortPreferences(
            folderId: widget.folderId!,
            subfolderSortOrder: _foldersSortOrder.name,
            noteSortOrder: _notesSortOrder.name,
          );
        } catch (e, st) {
          debugPrint('[Reorder] sort rollback failed: $e\n$st');
        }
      }
      if (!mounted) return;
      setState(() {
        _reorderPending = false;
        _localMixed = null;
      });
      _loadData();
      return;
    }
    if (!mounted) return;
    // Covered by now, the page reads its rows when it is back in front.
    if (!_inFront()) return;
    if (changed.contains(MovableItemKind.folder)) {
      context.read<OptimizedFolderBloc>().add(
        flipped.contains(MovableItemKind.folder)
            ? LoadFoldersPaginated(
                parentId: widget.folderId,
                sortOrder: FoldersSortOrder.positionAsc,
              )
            : RefreshFolders(
                parentId: widget.folderId,
                sortOrder: _foldersSortOrder,
              ),
      );
    }
    if (widget.folderId != null && changed.contains(MovableItemKind.note)) {
      context.read<OptimizedNoteBloc>().add(
        flipped.contains(MovableItemKind.note)
            ? LoadNotesPaginated(
                folderId: widget.folderId,
                sortOrder: NotesSortOrder.positionAsc,
              )
            : RefreshNotes(folderId: widget.folderId),
      );
    }
  }

  Widget _buildEmptyStateSection() {
    return BlocBuilder<OptimizedFolderBloc, OptimizedFolderState>(
      buildWhen: FolderBlocFilters.forParentFolder(widget.folderId),
      builder: (context, blocFolderState) {
        return BlocBuilder<OptimizedNoteBloc, OptimizedNoteState>(
          buildWhen: NoteBlocFilters.forEmptyState(widget.folderId),
          builder: (context, blocNoteState) {
            final folderState = _ownFolders(blocFolderState);
            final noteState = _ownNotes(blocNoteState);
            bool foldersEmpty = true;
            if (folderState is OptimizedFolderLoaded) {
              foldersEmpty = folderState.paginatedFolders.folders.isEmpty;
            }

            bool notesEmpty = true;
            if (widget.folderId != null) {
              final notes = NoteStateHelper.getNotesForFolder(
                noteState,
                widget.folderId,
              );
              notesEmpty = notes == null || notes.isEmpty;
            }

            if (foldersEmpty &&
                notesEmpty &&
                folderState is OptimizedFolderLoaded &&
                (widget.folderId == null ||
                    noteState is OptimizedNoteLoaded ||
                    noteState is OptimizedNoteContentLoaded)) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.folderId != null
                              ? Icons.note_add
                              : Icons.folder_open,
                          size: 80,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          widget.folderId != null
                              ? AppLocalizations.of(context)!.emptyNotesHint
                              : AppLocalizations.of(context)!.emptyFoldersHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppLocalizations.of(context)!.createFromBarBelow,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return const SliverToBoxAdapter(child: SizedBox.shrink());
          },
        );
      },
    );
  }

  /// Opens the platform file picker, then dispatches the appropriate
  /// import event. Routing by extension keeps the UI thin: the bloc and
  /// service decide how to actually parse the file.
  Future<void> _pickAndImport() async {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'json', 'md', 'txt'],
    );
    if (result == null) return;
    final path = result.path;
    if (path == null || !mounted) return;
    final isArchive = path.toLowerCase().endsWith('.zip');
    final bloc = context.read<ImportExportBloc>();
    if (isArchive) {
      bloc.add(
        ImportArchiveRequested(
          filePath: path,
          targetParentFolderId: widget.folderId,
        ),
      );
    } else {
      // Importing a single note requires a destination folder.
      if (widget.folderId == null) {
        CustomSnackbar.showError(
          context,
          AppLocalizations.of(context)!.importFileError,
        );
        return;
      }
      bloc.add(
        ImportFileRequested(filePath: path, targetFolderId: widget.folderId!),
      );
    }
  }

  void _showCreateFolderDialog() async {
    final name = await AppDialogs.textInput(
      context,
      title: AppLocalizations.of(context)!.createFolder,
      hintText: AppLocalizations.of(context)!.enterFolderName,
      confirmText: AppLocalizations.of(context)!.create,
    );
    if (name == null || name.trim().isEmpty) return;
    if (!mounted) return;
    final trimmed = name.trim();
    // Per-parent name uniqueness: prevent two sibling folders sharing a
    // name. Comparison is case-insensitive + whitespace-trimmed.
    final exists = await _folderStorageService.folderNameExistsInParent(
      parentId: widget.folderId,
      name: trimmed,
    );
    if (!mounted) return;
    if (exists) {
      CustomSnackbar.showError(
        context,
        AppLocalizations.of(context)!.folderNameAlreadyExists(trimmed),
      );
      return;
    }
    context.read<OptimizedFolderBloc>().add(
      CreateOptimizedFolder(name: trimmed, parentId: widget.folderId),
    );
  }

  void _createNewNote() {
    AppNavigator.toNoteEditor(context, folderId: widget.folderId!).then((_) {
      if (mounted) {
        _refreshData();
      }
    });
  }
}
