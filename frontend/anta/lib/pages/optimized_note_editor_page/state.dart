part of '../optimized_note_editor_page.dart';

/// What the editor page holds between builds, and the small things read
/// straight off it. The page's State is this class with the mixins of the
/// sibling files applied in the order [_OptimizedNoteEditorPageState] lists
/// them, and each of them sees only the ones before it — a member that an
/// earlier one needs from a later one is declared at the end of this class
/// and defined where it belongs.
abstract class _NoteEditorState extends State<OptimizedNoteEditorPage>
    with WidgetsBindingObserver, RouteAware {
  /// The bar's menu button and its ⋮ Settings item open the drawer through
  /// this key: the item's tap runs once the menu route is gone, from a
  /// context under no Scaffold of this page, so `Scaffold.of` cannot reach
  /// it.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Reaches the mounted find bar so the app-bar toggle can leave through
  /// the bar's own close, rather than a second path that skips its exit
  /// animation.
  final GlobalKey<NoteSearchBarState> _searchBarKey =
      GlobalKey<NoteSearchBarState>();
  late TextEditingController _titleController;
  late CodeLineEditingController _contentController;
  late FocusNode _contentFocusNode;
  late CodeScrollController _editorScrollController;
  late TextHistoryObserver _historyObserver;
  late ReEditorSearchController _searchController;
  late final VocabularySuggestionController _vocabularySuggestions;

  /// The two vocabulary settings [_refreshVocabularies] last applied, or
  /// null before the first load. The settings bundle notifies on every
  /// font-size tap too, and re-running the refresh there would await the
  /// vocabulary service once per tap — on the typing path's own listener.
  ({bool enabled, String trigger})? _appliedVocabularySettings;

  final GlobalKey _editorWrapperKey = GlobalKey();
  final GlobalKey _lineNumbersKey = GlobalKey();
  final GlobalKey _scrollIndicatorKey = GlobalKey();

  /// Every setting this page reads, as one listenable bundle, plus the
  /// font-size taps. Also half of the editor-mount gate: the skeleton
  /// stays up until it has loaded, so the `CodeEditor`'s [ValueKey] is
  /// already final the first time it is built (B4).
  final EditorSettingsController _editorSettings = EditorSettingsController();

  /// The note's persisted reading position, and the join that decides
  /// when it may be applied (B2).
  late final NoteEditorPositionController _position;

  /// Auto-save, the early create for brand-new notes, and the
  /// duplicate-title rules.
  late final NoteSaveCoordinator _saves;

  /// The paste reflow, the Enter list continuation, and the re-entrancy
  /// guard every programmatic edit runs under.
  late final EditorEditTracker _edits;

  /// Line and character counts for the stats bar.
  late final NoteEditorStatsTracker _stats;

  /// The span builder plus the two resolved render settings (money
  /// display, colour palette) both surfaces have to agree on.
  final EditorRenderController _render = EditorRenderController();

  /// Whether the in-note find session is open, mirrored from
  /// [_searchController] in [_onSearchChanged]. The span builder and the
  /// wrapper both read it as the second reveal input: find selects its
  /// match while the search field holds focus, and a match inside
  /// concealed syntax must still show.
  final ValueNotifier<bool> _findActive = ValueNotifier<bool>(false);

  /// Cached reference so we can dispatch [SetNoteContext] during [dispose].
  late final CounterBloc _counterBloc;

  /// The storage service's change events, for the merges a sync pull brings
  /// into this note ([_onStorageChange]).
  late final StreamSubscription<NoteChange> _storageChanges;

  /// The census dropped — a share act, a merge, the shared reader — for the
  /// sign on a note of mine ([_refreshSharedSign]).
  late final StreamSubscription<void> _shareFactsChanges;

  /// Owns the markdown preview render pipeline (parse, chunk cache,
  /// scroll progress, search highlights). Created in [initState] and
  /// disposed in [dispose]. Provided to descendants via
  /// [BlocProvider.value] in [build]. Preview font size and lines-per-chunk
  /// live in this bloc's state — read via getters below.
  late final MarkdownPreviewBloc _previewBloc;

  /// The toolbar's resolved profile and shortcuts, or null until the bar
  /// bloc first answers.
  MarkdownBarLoaded? _bar;

  bool _isPreviewMode = false;
  bool _isTogglingPreview = false;
  Timer? _livePreviewDebounce;

  /// Whether the note's text has reached the editor — one part of
  /// [_isLoading].
  bool _contentLoaded = false;

  /// Whether the initial [_reloadSettings] has resolved the money config
  /// and the colour palette on top of the settings bundle. Part of
  /// [_isLoading]: both are render inputs, and applying either after the
  /// editor's first frame restyles every money row or coloured run in
  /// front of the reader.
  bool _renderConfigLoaded = false;

  /// Whether the toolbar bloc has answered this page's [LoadMarkdownBar]
  /// — with a profile or with an error. Part of [_isLoading]: the bar is
  /// built from the answer, and a bar that lands after the mount reflows
  /// under the editor.
  bool _barSettled = false;

  /// Whether [_focusNewNoteOnce] has already asked for focus.
  bool _newNoteFocusRequested = false;

  /// Whether [_applyTargetHeadingOnce] has run — the gate's callers run
  /// again on every settings reload, and a second jump would drag the
  /// caret back after the reader moved it.
  bool _targetHeadingApplied = false;

  /// Latched by the first Back the page handles, and released only when the
  /// pop it led to did not take the page (a drawer's local-history entry
  /// consumed it).
  ///
  /// The handler awaits the exit save, and a second Back arriving inside
  /// that await used to run the whole exit again — the second pop taking
  /// the folder page underneath with it. A Back with the drawer open never
  /// reaches the save at all: `PopScope(canPop: false)` outranks the
  /// route's local history in `popDisposition`, so the handler closes the
  /// drawer itself, otherwise the latch would stay set on a page that is
  /// still there (found on the emulator, 2026-09-07).
  bool _isExiting = false;

  /// Whether the [LoadNoteContent] *this page* dispatched is still
  /// unanswered.
  ///
  /// One app-wide [OptimizedNoteBloc] serves every editor, and two editors
  /// can be open over the same note at once — a `[[wiki link]]` from B back
  /// to A, or the same note reached twice through search. The id guard in
  /// the content listener cannot tell those two pages apart; this flag can,
  /// because only the page that asked has it raised (C1).
  bool _awaitingContentLoad = false;

  /// The folder the note lives in *now*: `widget.folderId` until the note is
  /// moved from the page's own menu, which is why it is not read straight
  /// off the widget.
  late String _folderId = widget.folderId;

  /// That folder's name, for the menu's first row. Null until the read
  /// answers, and at root — where a note cannot live, so the fallback is
  /// only ever defensive.
  String? _folderName;

  /// A note the partner shares (share surfaces §6.13): no keyboard, no bar,
  /// no save of any kind — the database refuses a write of it. Decided from
  /// the metadata the page is opened with, every door hands it flagged, so
  /// the first frame is already the right one; the load sets it once more
  /// should the row on screen have been stale. Never cleared: a page that
  /// read the note as the partner's has turned its saves off for good.
  late bool _readOnly = widget.metadata?.fromPartner ?? false;

  /// The note is mine and lies in a folder I share: the bar's sign (§6.7).
  late bool _inSharedFolder = widget.metadata?.inSharedFolder ?? false;

  /// The partner's name and face, read once for a page that says either.
  /// Seeded from what the share service already holds, so the bar's sign
  /// names her from the first frame instead of "your partner" until the
  /// read answers.
  String? _partnerName =
      OptimizedNoteEditorPage.knownShare()?.audience?.displayName;
  AppUser? _partner =
      OptimizedNoteEditorPage.knownShare()?.audience?.members.firstOrNull;

  /// Whether the partner's name has been read; a read-only page's body
  /// waits for it, since its line is fixed for the visit.
  late bool _shareFactsLoaded = !_readOnly;

  /// Whether a pair holds and my shared rows wear their sign, as last read.
  /// Seeded from what the services already hold for this database, so a
  /// note of mine opens with its sign already right; for one never paired
  /// the pairing cache answers false and nothing is read at all.
  bool _paired = PairingService.pairedInMemory != false;
  bool _markMine = ShareService.publishedLook?.markMine ?? true;

  /// The read-only line has said once this visit why a box did not tick.
  bool _toldReadOnly = false;

  double _previousKeyboardHeight = 0;

  /// Last keyboard-visibility decision taken by [build], mirrored so
  /// callbacks outside the build phase can read [_showPreview].
  bool _lastKeyboardVisible = false;

  /// The preview's scroll controller, owned by [_previewBloc]. The
  /// bloc-view binds its own view key to it on mount, so the page holds
  /// no key of its own.
  PreviewScrollController get _previewController =>
      _previewBloc.scrollController;

  /// Whether the loading skeleton is still up.
  ///
  /// Every input the first frame is built from. The note's text is the
  /// obvious one; the settings bundle is the subtle one (B4), because the
  /// editor's [ValueKey] is derived from `liveMarkdownRendering` —
  /// mounting before that landed would remount the `CodeEditor` the moment
  /// it arrived, mid initialization. The stored position is applied before
  /// the editor's first layout, so that frame is already scrolled to it.
  /// The money config, the colour palette and the toolbar profile are the
  /// rest: each used to land a frame or two after the mount and restyle or
  /// reflow what was already on screen. With all of them gated, the body
  /// appears exactly once, fully formed — the loading state is a blank
  /// body, never half-built chrome that then shifts.
  bool get _isLoading =>
      !_contentLoaded ||
      !_editorSettings.loaded ||
      !_position.loaded ||
      !_renderConfigLoaded ||
      !_barSettled ||
      !_shareFactsLoaded;

  /// Convenience accessor for the current preview font size, sourced
  /// from [_previewBloc.state.fontSize]. Used by the toolbar build.
  double get _previewFontSize => _previewBloc.state.fontSize;

  /// Convenience accessor for the current preview chunk size,
  /// sourced from [_previewBloc.state.linesPerChunk]. Used by the
  /// editor's chunk debug visualization so editor and preview always
  /// agree on chunk boundaries.
  int get _previewLinesPerChunk => _previewBloc.state.linesPerChunk;

  /// Whether the (deprecated) preview surface is reachable at all: either
  /// the user opted back in, or live markdown rendering is off and the raw
  /// editor still needs a way to see rendered output.
  bool get _canPreview => _editorSettings.canPreview;

  /// The stored auto-reveal flag, gated on reachability: a `true` left
  /// over from before the preview was deprecated must not resurrect a
  /// surface the user can no longer reach.
  bool get _previewWhenKeyboardHidden =>
      _canPreview && _editorSettings.value.previewWhenKeyboardHidden;

  /// Whether the preview surface is what the user is looking at *right now*
  /// — the manual toggle, or the keyboard-hidden auto-reveal.
  bool get _showPreview =>
      _canPreview &&
      (_isPreviewMode || (_previewWhenKeyboardHidden && !_lastKeyboardVisible));

  /// The toolbar's shortcuts for the active profile, empty until the bar
  /// bloc answers.
  List<CustomMarkdownShortcut> get _shortcuts =>
      _bar?.currentShortcuts ?? const [];

  /// The bar profile currently active for this note.
  String get _activeBarProfileId =>
      _bar?.activeProfileId ?? MarkdownBarProfile.defaultProfileId;

  /// Whether this page knows whose its note is: the opener said it is hers,
  /// it is a new note, or its load was adopted ([_adoptShareFlags]). An
  /// editor opened over cold caches does not until then, and a leave
  /// before it is said in the share's words when the share ended under it.
  late bool _ownerKnown = _readOnly || widget.noteId == null;

  /// Whether nothing has been pushed over this page yet. Both tap handlers
  /// take it after their awaits, because the tap interceptor fires on every
  /// re-tap by design: without it two quick taps on one `[[wiki link]]` (or
  /// one `#tag`) each finish their round trip and push their own page (B2).
  bool get _isCurrentRoute => ModalRoute.of(context)?.isCurrent ?? false;

  // A first load replays a remote update that arrived before it landed
  // through these two, which the remote-change mixin defines further down.
  void _queueRemote(Future<void> Function() handle);
  Future<void> _adoptRemoteUpdate(NoteChange change);
}
