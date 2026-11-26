part of '../optimized_note_editor_page.dart';

/// What the page knows about sharing: the folder's name, whose note this
/// is, the partner's name and face, and the bar's sign as it follows what
/// changes while the page is open.
mixin _NoteEditorSharing on _NoteEditorLoading {
  /// A live folder only: a tombstone a pull brought without its data is
  /// stored under its id as its name, which the menu would show as is.
  Future<void> _loadFolderName() async {
    try {
      final folder = await GetIt.I<FolderStorageService>().getFolderById(
        _folderId,
        includeDeleted: false,
      );
      if (!mounted || folder == null) return;
      setState(() => _folderName = folder.name);
    } catch (e) {
      debugPrint('[NoteEditor] folder name lookup failed: $e');
    }
  }

  /// The loaded row's share flags, adopted once, before the body shows: a
  /// row drawn before the note became the partner's opened it as mine, and
  /// the load is where that is caught — the saves go off before the editor
  /// ever mounts. The other way round never happens, since the partner's
  /// notes never become mine, so it is not undone here.
  void _adoptShareFlags(NoteMetadata loaded) {
    _ownerKnown = true;
    final readOnly = _readOnly || loaded.fromPartner;
    final inShared = !readOnly && loaded.inSharedFolder;
    if (readOnly == _readOnly && inShared == _inSharedFolder) return;
    final startRead = !_readOnly && !_inSharedFolder;
    setState(() {
      if (readOnly && !_readOnly) {
        _readOnly = true;
        _shareFactsLoaded = false;
        _saves.disableSaves();
      }
      _inSharedFolder = inShared;
    });
    if (startRead || !_shareFactsLoaded) unawaited(_loadShareFacts());
  }

  /// The partner's name and face, whether a pair holds, and whether my
  /// shared rows wear their sign — read for a page that shows the line or
  /// may show the sign, never for any other. A read that fails leaves the
  /// localized stand-in for the name, and the body is let through anyway.
  Future<void> _loadShareFacts() async {
    try {
      final share = await OptimizedNoteEditorPage.shareService();
      final audience = share.availability.audience;
      // The partner's note wears no sign, so it reads no mark.
      final markMine = _readOnly ? _markMine : await share.markMine();
      if (!mounted) return;
      setState(() {
        _partnerName = audience?.displayName;
        _partner = audience?.members.firstOrNull;
        _paired = audience != null;
        _markMine = markMine;
      });
    } catch (e) {
      debugPrint('[NoteEditor] share facts not read: $e');
    } finally {
      if (mounted && !_shareFactsLoaded) {
        setState(() => _shareFactsLoaded = true);
        _markEditorReady();
      }
    }
  }

  /// "{name}" as every sharing line says it.
  String _partnerNameIn(AppLocalizations l10n) =>
      ShareCopy.partnerName(l10n, _partnerName);

  /// The bar's sign on a note of mine in a folder I share (spec F6a).
  bool get _showsSharedSign =>
      _inSharedFolder && !_readOnly && _paired && _markMine;

  /// A task box tapped in the partner's note: nothing ticks, and the first
  /// such tap of the visit says why.
  void _sayReadOnlyOnce() {
    if (_toldReadOnly || !mounted) return;
    _toldReadOnly = true;
    final l10n = AppLocalizations.of(context)!;
    OverlaySnackbar.show(
      context,
      l10n.sharedNoteReadOnly(_partnerNameIn(l10n)),
      duration: AppConstants.snackbarDuration,
    );
  }

  /// Whether a [_refreshSharedSign] is running, and whether another was
  /// asked for meanwhile: a sync run forgets the census once per page, and
  /// the sign needs one read after the last of them, not one per page.
  bool _signRefreshing = false;
  bool _signRefreshOwed = false;

  /// The sign follows what changes while the page is open (case F3): the
  /// note moved into or out of a folder I share, the folder shared or no
  /// longer, "Mark what you share" switched, the pair ended. One read of the
  /// note's row; the pair and the mark come from what the share service
  /// holds in memory. Nothing at all for an account that never paired, and
  /// nothing for the partner's note, which wears no sign.
  ///
  /// [returning] from a covering page re-evaluates from memory alone — the
  /// published look and the known availability: what changed the note's
  /// folder while it was covered forgot the census, which this page heard
  /// and read the row for then. So a return runs no statement, paired,
  /// never paired or not known.
  Future<void> _refreshSharedSign({bool returning = false}) async {
    if (_readOnly || PairingService.pairedInMemory == false) return;
    if (returning) {
      final known = OptimizedNoteEditorPage.knownShare();
      final audience = known?.audience;
      setState(() {
        if (known != null) {
          _paired = audience != null;
          _partnerName = audience?.displayName;
          _partner = audience?.members.firstOrNull;
        }
        _markMine = ShareService.publishedLook?.markMine ?? _markMine;
      });
      return;
    }
    final noteId = _saves.effectiveNoteId ?? widget.noteId;
    if (noteId == null) return;
    if (_signRefreshing) {
      _signRefreshOwed = true;
      return;
    }
    _signRefreshing = true;
    try {
      final current = await GetIt.I<NoteStorageService>().getNoteMetadata(
        noteId,
      );
      if (!mounted || current == null) return;
      final inShared = current.inSharedFolder;
      ShareService? share;
      if (inShared) {
        try {
          share = await OptimizedNoteEditorPage.shareService();
        } catch (e) {
          debugPrint('[NoteEditor] share service not opened: $e');
        }
      }
      if (!mounted) return;
      final audience = share?.availability.audience;
      setState(() {
        _inSharedFolder = inShared;
        if (share != null) {
          _paired = audience != null;
          _partnerName = audience?.displayName;
          _partner = audience?.members.firstOrNull;
        }
        _markMine = ShareService.publishedLook?.markMine ?? _markMine;
      });
    } catch (e) {
      debugPrint('[NoteEditor] share sign not read: $e');
    } finally {
      _signRefreshing = false;
      if (_signRefreshOwed && mounted) {
        _signRefreshOwed = false;
        unawaited(_refreshSharedSign());
      }
    }
  }
}
