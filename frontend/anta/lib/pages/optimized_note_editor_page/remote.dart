part of '../optimized_note_editor_page.dart';

/// The open-editor rule for a change a sync pull brings (record §3.9):
/// holding writes while it is handled, filing what must be kept and
/// retrying what did not land, adopting a remote edit, and leaving — or
/// keeping the text — when the note was deleted elsewhere.
mixin _NoteEditorRemote on _NoteEditorSharing {
  /// The engine's claim ([OpenNoteRegistry]): a pulled page files no conflict
  /// copy for a note whose body this page holds unsaved, because
  /// [_adoptRemoteUpdate] files the arriving body itself and the next save
  /// puts the live text back on the row (record §3.9, R99).
  ///
  /// Latched, not re-derived at the event: the merge asks inside its
  /// transaction and stands back on the answer, while this page hears of the
  /// change only once that page committed. A save landing in between would
  /// make [_adoptRemoteUpdate] read the body clean and file nothing, and the
  /// local body the merge overwrote would be kept nowhere (A7 review R129).
  bool _claimsConflictFiling(String noteId) {
    // A read-only page holds no text of its own — [_bodyIsUnsaved] says so
    // too; this is the belt for a claim the partner's folder would refuse.
    if (_readOnly) return false;
    if (noteId != (_saves.effectiveNoteId ?? widget.noteId)) return false;
    if (!_bodyIsUnsaved) return false;
    _owesConflictCopy = true;
    return true;
  }

  /// The claim [_claimsConflictFiling] made, until [_adoptRemoteUpdate] has
  /// filed on it.
  bool _owesConflictCopy = false;

  /// The remote changes still being handled, chained so each reads the row
  /// after the one before it. Every write the save coordinator makes waits
  /// for the chain ([_writesMayProceed]): that is what lets a handler read
  /// the merged row after an await without a debounced auto-save having
  /// overwritten it first (record §3.9, M4).
  Future<void> _remoteWork = Future<void>.value();

  /// The links of [_remoteWork] not yet finished: [_writesMayProceed]
  /// answers synchronously at zero, and otherwise waits until it is zero
  /// again — a change arriving during that wait is waited for too.
  int _remoteBusy = 0;

  /// What remote changes left to file and could not (M3), oldest first: an
  /// arriving text's conflict copy, or the text of a note deleted elsewhere
  /// as a new note. Each is retried, in order, at the head of the next
  /// remote change and before the next write; writes stay held until all
  /// are filed (S4b-1 review L7).
  final List<_Filing> _unfiled = [];

  /// The retry of [_unfiled] in flight, shared so a write and a change event
  /// arriving together file once.
  Future<void>? _filing;

  /// A remote delete that reached this page while another route covered it:
  /// acted on once the page is current again (H2).
  NoteChange? _deletedWhileCovered;

  /// The open-editor rule (record §3.9) for a change a sync pull merged
  /// into this page's note. Filtered here, off the typing path: only a
  /// remote `updated` or `deleted` of this note reaches the handlers.
  void _onStorageChange(NoteChange change) {
    if (!change.remote) return;
    if (change.noteId != (_saves.effectiveNoteId ?? widget.noteId)) return;
    switch (change.type) {
      case NoteChangeType.updated:
        // Before the first load lands the handler has no text to defend or
        // replace, and the load may carry the body from before the merge:
        // kept, and replayed once the load is in ([_adoptFirstLoad]).
        if (!_contentLoaded) _updatedWhileLoading = change;
        _queueRemote(() => _adoptRemoteUpdate(change));
      case NoteChangeType.deleted:
        _queueRemote(() => _onRemoteDelete(change));
      case NoteChangeType.created:
      case NoteChangeType.moved:
      case NoteChangeType.labelled:
        break;
    }
  }

  /// Holds writes from this moment — synchronously, inside the change event
  /// — until [handle] has run; nothing it throws escapes to the zone.
  @override
  void _queueRemote(Future<void> Function() handle) {
    _remoteBusy++;
    _remoteWork = _remoteWork.then((_) async {
      try {
        if (mounted) await _retryUnfiled();
        if (mounted) await handle();
      } catch (error, stack) {
        debugPrint('[NoteEditor] synced change not handled: $error\n$stack');
      } finally {
        _remoteBusy--;
      }
    });
  }

  /// The save coordinator's gate: true at once while no remote change is
  /// pending and nothing is unfiled; otherwise once no remote change is
  /// pending at all — not merely the ones pending when the write asked, or a
  /// merge arriving during the wait lets the write overwrite the row it just
  /// wrote before its handler reads it (S4b-1 review H2) — and every filing
  /// has had its retry.
  ///
  /// An exit or pause flush ([leaving]) still passes a failed conflict copy
  /// — the other device's text is lost then, but holding would lose the
  /// user's, the one on screen and about to be gone — never a failed
  /// keep-as-new filing: the write would land on the tombstone, which
  /// refuses it silently, and the text would be gone (M3).
  FutureOr<bool> _writesMayProceed({required bool leaving}) {
    if (_remoteBusy == 0 && _unfiled.isEmpty) return true;
    return _awaitRemoteWork(leaving: leaving);
  }

  Future<bool> _awaitRemoteWork({required bool leaving}) async {
    do {
      while (_remoteBusy > 0) {
        await _remoteWork;
      }
      await _retryUnfiled();
    } while (_remoteBusy > 0);
    return _unfiled.isEmpty || (leaving && !_holdsDeletedNotesText);
  }

  /// Whether the text of a note deleted elsewhere is still waiting to be
  /// filed as a new note.
  bool get _holdsDeletedNotesText => _unfiled.any((f) => f.keepsText);

  Future<void> _retryUnfiled() {
    if (_unfiled.isEmpty) return Future<void>.value();
    return _filing ??= _retryEachUnfiled().whenComplete(() => _filing = null);
  }

  Future<void> _retryEachUnfiled() async {
    for (final filing in List.of(_unfiled)) {
      if (!mounted) return;
      // A filing that completed during the iteration is off the list, and its
      // `attempt` is null again: running it a second time would file a second
      // copy, or retarget a second time over a title typed since (L4).
      if (!_unfiled.contains(filing)) continue;
      await _attempt(filing);
      // Oldest first, and no further than the first failure: a later filing
      // landing before an earlier one moves the baseline backwards through
      // `adoptStoredContent` (L5).
      if (_unfiled.contains(filing)) return;
    }
  }

  /// Files [run] now; when it fails, keeps it in [_unfiled] — writes held —
  /// rather than letting the error reach the zone and the next auto-save
  /// write over the text it was keeping (M3). [keepsText] marks the filing
  /// that keeps the text of a note deleted elsewhere.
  Future<void> _fileOrHold(
    Future<void> Function() run, {
    bool keepsText = false,
  }) {
    final filing = _Filing(run, keepsText: keepsText);
    // Listed before it runs: a write asking meanwhile is held by it.
    _unfiled.add(filing);
    return _attempt(filing);
  }

  /// Runs [filing] once — a retry asked while an attempt is still running
  /// joins that attempt, so one filing never creates its note twice.
  Future<void> _attempt(_Filing filing) =>
      filing.attempt ??= _run(filing).whenComplete(() => filing.attempt = null);

  Future<void> _run(_Filing filing) async {
    try {
      await filing.run();
      _unfiled.remove(filing);
    } catch (error, stack) {
      debugPrint('[NoteEditor] filing the synced text failed: $error\n$stack');
      _raiseFilingFailure(filing);
    }
  }

  /// Says that [filing] did not land, once: now when the page is on top, else
  /// when it is again ([_showFilingNoticeOwed]) — a failure under a dialog is
  /// still news once the dialog is gone (L8).
  ///
  /// The exit and the menu rows call it too, as a backstop for a retry that
  /// joined an attempt which had already failed this filing and so said
  /// nothing (A6 review R110/R111/R127).
  void _raiseFilingFailure(_Filing filing) {
    if (filing.failed) return;
    filing.failed = true;
    if (mounted && _isCurrentRoute) {
      _showFilingFailed(filing);
    } else {
      filing.noticeOwed = true;
    }
  }

  void _showFilingFailed(_Filing filing) {
    final l10n = AppLocalizations.of(context)!;
    CustomSnackbar.showError(
      context,
      filing.keepsText
          ? l10n.syncNoteKeptAsNewFailed
          : l10n.syncNoteConflictCopyFailed,
      withToolbarOffset: true,
    );
  }

  /// Shows the failure a filing hit while the page was covered, once the
  /// page is current again — the deleted note's text first, the more urgent
  /// of the two — and only while it is still unfiled.
  void _showFilingNoticeOwed() {
    final owed = _unfiled.where((f) => f.noticeOwed).toList();
    if (owed.isEmpty || !_isCurrentRoute) return;
    for (final filing in owed) {
      filing.noticeOwed = false;
    }
    final shown = owed.firstWhere((f) => f.keepsText, orElse: () => owed.first);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _unfiled.contains(shown)) _showFilingFailed(shown);
    });
  }

  /// A clean page reloads the merged text in place, the caret kept where it
  /// still fits. A dirty one keeps what the user typed — its next auto-save
  /// wins and pushes — and files the arriving text as a conflict copy, so
  /// the other device's text is not lost either; but only when the merge
  /// changed the body. The arriving body is judged against the text the
  /// page last loaded or saved, never the live text, which differs by
  /// definition while the page is dirty: a remote move, rename, label or
  /// re-save files nothing (H1). The arriving body is the one the merge
  /// announced ([NoteChange.remoteContent]), never a re-read: a save already
  /// in flight at the event may have overwritten the row since. A page whose
  /// only pending edit is its title has no body to defend: the body reloads
  /// in place and the title stays pending (S4b-1 review M6), and the engine
  /// files the losing body it overwrote. The engine stands back only for a
  /// page that claimed the filing while the merge ran
  /// ([_claimsConflictFiling]); such a page files here whatever it reads
  /// now, since a save landing in the window would otherwise leave the
  /// overwritten body nowhere (A7 review R129).
  ///
  /// That reload is last-writer-wins on the title, by design: the merge's own
  /// title is not applied, because the pending local one is written next and
  /// with a newer HLC, so it would win the very next merge anyway. The undo
  /// history restarts at the merged body, as every reload does
  /// ([_adoptLoadedContent]) — splicing the body in instead would mean a
  /// second whole-document edit path on the typing path (R9).
  @override
  Future<void> _adoptRemoteUpdate(NoteChange change) async {
    final folderId = change.note?.folderId;
    if (folderId != null && folderId != _folderId) {
      setState(() {
        _folderId = folderId;
        _folderName = null;
      });
      unawaited(_loadFolderName());
      unawaited(_refreshSharedSign());
    }
    // The claim this page made to the merge ([_claimsConflictFiling]),
    // consumed here: it files even when the save it was racing landed in the
    // meantime and left the page reading clean (R129).
    final owed = _owesConflictCopy;
    _owesConflictCopy = false;
    if (!owed && !_hasUnsavedText) {
      final reloaded = await _reloadContentIfChanged();
      if (!mounted || reloaded == false) return;
      if (reloaded == true) {
        // The partner's change simply shows: there is no edit of mine on
        // the page for it to have overtaken.
        if (_isCurrentRoute && !_readOnly) {
          CustomSnackbar.show(
            context,
            AppLocalizations.of(context)!.syncNoteUpdatedElsewhere,
            withToolbarOffset: true,
          );
        }
        return;
      }
      // Nothing was read, or a keystroke landed during the read.
      if (!_hasUnsavedText) return;
    }
    final arriving = change.remoteContent;
    // An unreadable body gives nothing to compare or to keep.
    if (arriving == null) return;
    // Equal to the live text too: the user typed what the other device
    // wrote, and a copy of it would be a duplicate.
    if (_saves.isSavedContent(arriving) ||
        arriving == _contentController.text) {
      return;
    }
    if (!owed && _saves.isSavedContent(_contentController.text)) {
      _adoptLoadedContent(arriving, keepCaret: true, titlePending: true);
      if (_isCurrentRoute) {
        CustomSnackbar.show(
          context,
          AppLocalizations.of(context)!.syncNoteUpdatedElsewhere,
          withToolbarOffset: true,
        );
      }
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final merged = change.note;
    final at = DateTime.now();
    await _fileOrHold(() async {
      await _createWithFreeTitle(
        folderId: merged?.folderId ?? _folderId,
        title: (copy) => conflictCopyTitle(
          l10n,
          merged?.title ?? _titleController.text,
          at,
          copy: copy,
        ),
        content: arriving,
        label: ItemLabel.fromStorage(merged?.label ?? 0),
      );
      _saves.adoptStoredContent(arriving);
      if (mounted && _isCurrentRoute) {
        CustomSnackbar.show(
          context,
          l10n.syncNoteConflictCopyFiled,
          withToolbarOffset: true,
        );
      }
    });
  }

  /// How many numbered forms of a filing's title are tried before the filing
  /// is failed. A folder holding twenty copies of one title is already past
  /// anything the numbering explains; spinning on past it would cost a
  /// database round trip per turn with every write on the page held behind it
  /// (R16).
  static const int _freeTitleAttempts = 20;

  /// Creates a note through the storage service's normal create — a local
  /// write like any other, so it is announced and synced — taking the first
  /// of [title]'s numbered forms the folder does not hold yet.
  ///
  /// The last attempt's [DuplicateNameException] is the filing's failure: it
  /// holds the text and the page's writes, and tries again.
  Future<NoteMetadata> _createWithFreeTitle({
    required String folderId,
    required String Function(int copy) title,
    required String content,
    required ItemLabel label,
  }) async {
    final storage = GetIt.I<NoteStorageService>();
    for (var copy = 1; copy < _freeTitleAttempts; copy++) {
      try {
        return await storage.createNote(
          folderId: folderId,
          title: title(copy),
          content: content,
          label: label,
        );
      } on DuplicateNameException {
        continue;
      }
    }
    return storage.createNote(
      folderId: folderId,
      title: title(_freeTitleAttempts),
      content: content,
      label: label,
    );
  }

  /// A clean page closes; a dirty one keeps its text as a new note — a save
  /// into the deleted one is refused by design, so the text cannot ride the
  /// next auto-save. Even while the page is already leaving: its last write,
  /// held behind this handler, would otherwise land on the tombstone (M3).
  Future<void> _onRemoteDelete(NoteChange change) async {
    if (_hasUnsavedText) {
      await _keepTextAsNewNote(change);
    } else if (!_isExiting) {
      _leaveRemotelyDeleted(change);
    }
  }

  /// Files the editor's title and text as a new note — the deleted one's
  /// label, in its folder while that is live, else the nearest live ancestor,
  /// else the root — and points the page's saves, reading position and
  /// counters at it, so editing simply continues there.
  Future<void> _keepTextAsNewNote(NoteChange change) async {
    final storage = GetIt.I<NoteStorageService>();
    // The tombstone, read past the cache the merge announcement dropped.
    final deleted = (await storage.loadNoteWithContent(
      change.noteId,
    ))?.metadata;
    final folderId = await GetIt.I<FolderStorageService>().nearestLiveFolderId(
      deleted?.folderId ?? change.folderId ?? _folderId,
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    // Kept across retries: a step after the create that throws must not
    // make the retry create a second note (S4b-1 review L11).
    NoteMetadata? created;
    late String content;
    await _fileOrHold(keepsText: true, () async {
      if (created == null) {
        final title = _titleController.text;
        content = _contentController.text;
        created = await _createWithFreeTitle(
          folderId: folderId,
          title: (copy) => _numberedTitle(title, copy),
          content: content,
          label: deleted?.label ?? ItemLabel.none,
        );
      }
      final kept = created!;
      if (!mounted) return;
      // Before the retarget: the title listener marks the old id dirty, and
      // the retarget re-baselines on what the create wrote.
      if (_titleController.text != kept.title) {
        _titleController.text = kept.title;
      }
      _saves.retarget(kept.id, title: kept.title, content: content);
      _position.noteId = kept.id;
      _counterBloc.add(SetNoteContext(noteId: kept.id));
      ShortcutHandlerFactory.counterHandler.setActiveNoteId(kept.id);
      setState(() {
        _folderId = kept.folderId;
        _folderName = null;
      });
      unawaited(_loadFolderName());
      if (_isCurrentRoute) {
        CustomSnackbar.show(
          context,
          l10n.syncNoteKeptAsNew,
          withToolbarOffset: true,
        );
      }
    });
  }

  /// [title], then ` (n)` from the second try on, cut so the whole fits the
  /// title column.
  static String _numberedTitle(String title, int copy) {
    if (copy < 2) return title;
    final suffix = ' ($copy)';
    final room = AppConstants.maxNoteTitleLength - suffix.length;
    return '${title.length > room ? title.substring(0, room) : title}$suffix';
  }

  /// A clean page has nothing left to show and closes, the message raised
  /// before the pop so it stays up over the page beneath — but only from the
  /// top of its navigator. Every pop here takes whatever route is on top —
  /// `AppNavigator.pop` is `Navigator.pop`, so the call used changes nothing
  /// — and under a dialog or another page that would close *that* one and
  /// strand this page with its saves off (H2). The [_isCurrentRoute] guard is
  /// the whole fix: the delete waits until the page is current again
  /// ([didChangeDependencies], [didPopNext]), and nothing is switched off
  /// before the pop really targets this page.
  void _leaveRemotelyDeleted(NoteChange change) {
    if (!mounted || _isExiting) return;
    if (!_isCurrentRoute) {
      _deletedWhileCovered = change;
      return;
    }
    _deletedWhileCovered = null;
    _isExiting = true;
    _saves.disableSaves();
    final l10n = AppLocalizations.of(context)!;
    // The partner's note leaves when it is un-shared, deleted or the pair
    // ends; each reaches here as a removal, and all read as one thing. One
    // bar per leave (ShareLeaveVoice): this page in front speaks, the pages
    // under it that leave with it are silent — in the share's words when
    // the note is hers, or when this page never learned whose it was and
    // the share ended under it; in its own words when it is mine.
    final hers = _readOnly;
    final ownerKnown = _ownerKnown;
    final shareLine = ShareCopy.sentence(
      l10n.shareGoneNote(_partnerNameIn(l10n)),
    );
    final ownLine = _goneAtLoad
        ? l10n.noteNotFound
        : l10n.syncNoteDeletedElsewhere;
    final page = context;
    final navigator = Navigator.of(context);
    unawaited(
      ShareLeaveVoice.leave(this, ownerUnknown: !ownerKnown, (forShare) {
        // Said after the pop when the pages around had to be asked.
        final host = page.mounted ? page : navigator.context;
        if (!host.mounted) return;
        CustomSnackbar.show(
          host,
          hers || (!ownerKnown && forShare) ? shareLine : ownLine,
        );
      }),
    );
    navigator.pop();
  }

  /// The note's own load answered that it is gone ([_leaveRemotelyDeleted]
  /// says "Note not found" for a note of mine then, not "deleted elsewhere").
  bool _goneAtLoad = false;

  /// Whether this page closes on the run being announced now, asked by
  /// [ShareLeaveVoice] when a page under it leaves: its note is gone and
  /// nothing typed keeps the page open ([_onRemoteDelete]).
  Future<bool> _leavesWithThisRun() async {
    final noteId = _saves.effectiveNoteId ?? widget.noteId;
    if (!mounted || noteId == null || _hasUnsavedText) return false;
    final note = await GetIt.I<NoteStorageService>().getNoteMetadata(noteId);
    return note == null;
  }

  /// Runs a delete [_leaveRemotelyDeleted] deferred, after the frame that
  /// made this page current again — never from inside the navigator's own
  /// update. The page is asked again whether it is clean: the route that
  /// covered it may have edited it as it closed — a heading menu, the
  /// rename dialog — and closing would lose that edit; its text is kept as
  /// a new note instead (S4b-1 review M5).
  void _leaveIfDeletedWhileCovered() {
    if (_deletedWhileCovered == null || !_isCurrentRoute) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final change = _deletedWhileCovered;
      if (!mounted || change == null) return;
      if (_hasUnsavedText) {
        _deletedWhileCovered = null;
        _queueRemote(() => _keepTextAsNewNote(change));
      } else {
        _leaveRemotelyDeleted(change);
      }
    });
  }
}
