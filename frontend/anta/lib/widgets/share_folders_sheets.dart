import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../bloc/share/share_bloc.dart';
import '../constants/app_constants.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/share_overview.dart';
import '../services/app_navigator.dart';
import '../services/folder_storage_service.dart';
import '../services/share_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/share_copy.dart';
import 'folder_picker_dialog.dart';
import 'form_rows.dart';
import 'overlay_snackbar.dart';
import 'share_list_frame.dart';

/// Picks a folder of mine to share with [partnerName], whom the confirm
/// button names; null when the pick was cancelled.
typedef ShareFolderPicker =
    Future<String?> Function(BuildContext context, String partnerName);

/// Opens one of the partner's folders as the browser's page, from
/// [context] — the navigator's, the sheet that asked having gone.
typedef SharedFolderOpener =
    Future<void> Function(BuildContext context, PartnerSharedFolder folder);

/// The folder picker in its share shape: from the root, which is no
/// destination, and its confirm button saying who the folder goes to.
Future<String?> _pickFolderToShare(BuildContext context, String partnerName) =>
    showFolderPickerDialog(
      context,
      currentFolderId: '',
      allowRoot: false,
      purpose: FolderPickPurpose.share,
      partnerName: partnerName,
    );

Future<String?> _folderName(String id) async =>
    (await GetIt.I<FolderStorageService>().getFolderById(id))?.name;

/// Said to be the partner's by the opener: this list holds nothing else,
/// and the page it opens must be read-only from its first frame, whether or
/// not the folder caches are warm.
Future<void> _openFolder(BuildContext context, PartnerSharedFolder folder) =>
    AppNavigator.toFolder(
      context,
      folderId: folder.id,
      title: folder.name,
      fromPartner: true,
    );

/// The folders I share, from the Sharing page's YOU SHARE section
/// (`docs/cloud-share-surfaces-roadmap.md` §6.2, D37; the slice F spec F8):
/// each row's ✕ takes the folder's mark away at once, with Undo, and the
/// row leaves; "Share a folder" ends the list and shares one more. The
/// sibling of `MySharedEventsSheet`, which it behaves as: while it is up it
/// alone says what its acts and their Undos did, over itself.
class MySharedFoldersSheet extends StatefulWidget {
  final ShareBloc bloc;

  /// Resolves the service an Undo writes through once [bloc] has closed;
  /// [ShareService.getInstance] unless a test passes its own.
  final Future<ShareService> Function() shareService;

  /// The folder picker; a test passes its own.
  final ShareFolderPicker pickFolder;

  /// A folder's name by its id, for a pick that wrote nothing — the act
  /// names only what it wrote.
  final Future<String?> Function(String id) folderName;

  const MySharedFoldersSheet({
    super.key,
    required this.bloc,
    this.shareService = ShareService.getInstance,
    this.pickFolder = _pickFolderToShare,
    this.folderName = _folderName,
  });

  /// [bloc] is the Sharing page's, which lists the folders and takes the ✕
  /// and the pick.
  static Future<void> show(BuildContext context, {required ShareBloc bloc}) =>
      showShareListSheet(context, MySharedFoldersSheet(bloc: bloc));

  @override
  State<MySharedFoldersSheet> createState() => _MySharedFoldersSheetState();
}

class _MySharedFoldersSheetState extends State<MySharedFoldersSheet> {
  /// Rows whose ✕ was tapped and that the overview still lists: hidden at
  /// once, so the row leaves under the finger rather than when the reload
  /// lands, and shown again by an Undo that was written or a ✕ that failed.
  final Set<String> _leaving = {};

  /// The Undos the bloc was asked for, oldest first: the folder an un-share
  /// Undo brings back, null for a share's, which brings nothing back. The
  /// bloc runs its acts in order and none but this sheet's can be asked for
  /// while it is up, so each undo outcome answers the oldest.
  final List<String?> _undoing = [];

  /// The folders picked to share, oldest first, each answered by the next
  /// share outcome.
  final List<String> _sharing = [];

  /// While the picker is up, so a second tap opens no second picker.
  bool _picking = false;

  /// The last outcome this sheet has seen, so each is answered once.
  int? _seenOutcome;

  /// The acts this sheet asked for whose outcome it has not seen: if it is
  /// dismissed first, their failures are said past it.
  int _pending = 0;

  /// The app's messenger and words, read while the sheet stands, for what
  /// is said once it has gone.
  ScaffoldMessengerState? _messenger;
  AppLocalizations? _l10n;

  static const Set<ShareAct> _acts = {
    ShareAct.folderUnshared,
    ShareAct.folderShared,
    ShareAct.undo,
  };

  @override
  void initState() {
    super.initState();
    final state = widget.bloc.state;
    if (state is ShareLoaded) _seenOutcome = state.outcome?.sequence;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
    _l10n = AppLocalizations.of(context);
  }

  @override
  void dispose() {
    final l10n = _l10n;
    if (l10n != null) {
      sayShareFailuresPastSheet(
        bloc: widget.bloc,
        acts: _acts,
        pending: _pending,
        seen: _seenOutcome,
        messenger: _messenger,
        l10n: l10n,
      );
    }
    super.dispose();
  }

  /// The partner as the copy names them, from the bloc's last read.
  String _partnerName(AppLocalizations l10n) {
    final state = widget.bloc.state;
    return ShareCopy.partnerName(
      l10n,
      state is ShareLoaded ? state.availability.audience?.displayName : null,
    );
  }

  void _unshare(MySharedFolder folder) {
    final bloc = widget.bloc;
    // A sheet left up past the page's close acts on nothing.
    if (!mounted || bloc.isClosed) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _leaving.add(folder.id));
    _pending++;
    bloc.add(ShareFolderUnshared(folder.id));
    // Said at the tap, as the events sheet says it: the reload that drops
    // the row may land after the finger has moved on.
    final change = ShareChange(
      unsharedFolders: [ShareFolderRef(id: folder.id, name: folder.name)],
    );
    _offerUndo(
      l10n,
      ShareCopy.folderAct(l10n, change, partnerName: null)!,
      change,
      restores: folder.id,
    );
  }

  Future<void> _add() async {
    final bloc = widget.bloc;
    if (_picking || !mounted || bloc.isClosed) return;
    final l10n = AppLocalizations.of(context)!;
    _picking = true;
    final String? picked;
    try {
      picked = await widget.pickFolder(context, _partnerName(l10n));
    } finally {
      _picking = false;
    }
    if (picked == null || picked.isEmpty || !mounted || bloc.isClosed) return;
    _sharing.add(picked);
    _pending++;
    bloc.add(ShareFolderShared(picked));
  }

  /// The bar with Undo for [change], over the sheet. Its Undo may be tapped
  /// after this sheet and the page that owns the bloc are gone, so it reads
  /// nothing of the sheet's but [mounted]: while the bloc is open the undo
  /// goes through it, queued behind the act, and [restores] — the row a ✕
  /// hid — comes back on its outcome; once it is closed the undo writes
  /// through [undoSharePastBloc]. Tapped under another database it writes
  /// nothing, as the events sheet's.
  void _offerUndo(
    AppLocalizations l10n,
    String message,
    ShareChange change, {
    String? restores,
  }) {
    final bloc = widget.bloc;
    // The app's own, which outlives this sheet and the page under it: where
    // an Undo tapped after both have gone says that it failed.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final shareService = widget.shareService;
    final generation = ShareService.databaseGeneration;
    CustomSnackbar.showWithAction(
      context,
      message: message,
      actionLabel: l10n.undo,
      actionIdentifier: SemanticsIds.snackbarUndo,
      overSheet: true,
      onAction: () {
        if (ShareService.databaseGeneration != generation) return;
        Future<void> pastBloc(ShareChange change) => undoSharePastBloc(
          change,
          shareService: shareService,
          messenger: messenger,
          l10n: l10n,
        );
        if (!bloc.isClosed) {
          if (mounted) {
            _undoing.add(restores);
            _pending++;
          }
          bloc.add(ShareUndoRequested(change, pastBloc: pastBloc));
          return;
        }
        unawaited(pastBloc(change));
      },
    );
  }

  /// A ✕ that failed brings its row back and says why; one that worked
  /// needs nothing — the overview stops listing the folder. A pick says
  /// what it did — shared, shared over a folder inside it, or already
  /// shared — or why it did nothing. An Undo's row comes back once its undo
  /// was written, and an Undo that was not is said over the sheet.
  void _onState(BuildContext context, ShareState state) {
    if (state is! ShareLoaded) return;
    final outcome = state.outcome;
    if (outcome == null || outcome.sequence == _seenOutcome) return;
    _seenOutcome = outcome.sequence;
    if (_acts.contains(outcome.act) && _pending > 0) _pending--;
    final failure = outcome.failure;
    switch (outcome.act) {
      case ShareAct.folderUnshared:
        if (failure == null || _leaving.isEmpty) return;
        setState(_leaving.clear);
      case ShareAct.folderShared:
        if (_sharing.isEmpty) return;
        final picked = _sharing.removeAt(0);
        if (failure == null) {
          unawaited(_sayShared(outcome.change, picked));
          return;
        }
      case ShareAct.undo:
        if (_undoing.isEmpty) return;
        final id = _undoing.removeAt(0);
        if (failure == null) {
          if (id != null) setState(() => _leaving.remove(id));
          return;
        }
      case ShareAct.categoriesSet || ShareAct.eventUnshared || ShareAct.stopAll:
        return;
    }
    final l10n = AppLocalizations.of(context)!;
    OverlaySnackbar.show(
      context,
      failure == ShareFailure.refused
          ? l10n.shareNeedsSync
          : l10n.shareChangeFailed,
      duration: AppConstants.snackbarErrorDuration,
    );
  }

  /// One sentence per pick: an inner folder the share now covers is told
  /// as covered — the first of several — since its own row leaves the list;
  /// a pick that wrote nothing was shared already.
  Future<void> _sayShared(ShareChange change, String picked) async {
    final l10n = AppLocalizations.of(context)!;
    final message = ShareCopy.folderAct(
      l10n,
      change,
      partnerName: _partnerName(l10n),
    );
    if (message == null) {
      final name = await widget.folderName(picked);
      if (!mounted || name == null) return;
      OverlaySnackbar.show(context, l10n.shareFolderAlready(name));
      return;
    }
    _offerUndo(l10n, message, change);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocConsumer<ShareBloc, ShareState>(
      bloc: widget.bloc,
      listener: _onState,
      builder: (context, state) {
        final folders = [
          if (state is ShareLoaded)
            for (final folder in state.overview.folders)
              if (!_leaving.contains(folder.id)) folder,
        ];
        return ShareListFrame(
          identifier: SemanticsIds.shareFoldersSheet,
          title: l10n.shareRowFolders,
          empty: l10n.shareFoldersEmpty,
          rows: [for (final folder in folders) _row(l10n, folder)],
          footer: [
            FormActionRow(
              glyph: Icons.add_rounded,
              label: l10n.shareAddFolder,
              identifier: SemanticsIds.shareFoldersAdd,
              onTap: _add,
            ),
          ],
        );
      },
    );
  }

  Widget _row(AppLocalizations l10n, MySharedFolder folder) {
    final notes = l10n.shareFolderNotes(folder.noteCount);
    final parent = folder.parentName;
    return FormPickerRow(
      glyph: Icons.folder_outlined,
      label: folder.name,
      // Where it lies, so two folders of one name tell apart.
      caption: parent == null ? notes : ShareCopy.caption([parent, notes]),
      checkRowShape: true,
      showChevron: false,
      onTap: null,
      trailingButton: FormTrailingButton(
        icon: Icons.close_rounded,
        tooltip: l10n.shareStopSharingTooltip,
        identifier: SemanticsIds.shareFolderUnshare(folder.id),
        onPressed: () => _unshare(folder),
      ),
    );
  }
}

/// The partner's folders at the top of what they share, from the Sharing
/// page's "{name} shares with you" section (D37): read-only rows, each a
/// tap that leaves the sheet for the folder's page — Back returns to the
/// Sharing page — hence a chevron, as on every folder row.
class PartnerSharedFoldersSheet extends StatelessWidget {
  final ShareBloc bloc;

  /// The partner's name as the account has it (null when unread): the
  /// caption under the title names them.
  final String? partnerName;

  /// Opens a folder; [AppNavigator.toFolder] unless a test passes its own.
  final SharedFolderOpener onOpen;

  const PartnerSharedFoldersSheet({
    super.key,
    required this.bloc,
    required this.partnerName,
    this.onOpen = _openFolder,
  });

  static Future<void> show(
    BuildContext context, {
    required ShareBloc bloc,
    required String? partnerName,
  }) => showShareListSheet(
    context,
    PartnerSharedFoldersSheet(bloc: bloc, partnerName: partnerName),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<ShareBloc, ShareState>(
      bloc: bloc,
      builder: (context, state) {
        final folders = state is ShareLoaded
            ? state.overview.partnerFolders
            : const <PartnerSharedFolder>[];
        return ShareListFrame(
          identifier: SemanticsIds.sharedFoldersSheet,
          title: l10n.shareRowFolders,
          // The name goes under the title, never into it, as the events
          // sibling's: a long one cut the title at large text.
          caption: l10n.shareFromPartner(
            ShareCopy.partnerName(l10n, partnerName),
          ),
          empty: l10n.shareNone,
          rows: [
            for (final folder in folders)
              FormPickerRow(
                glyph: Icons.folder_outlined,
                label: folder.name,
                caption: l10n.shareFolderNotes(folder.noteCount),
                checkRowShape: true,
                identifier: SemanticsIds.sharedFolderOpen(folder.id),
                onTap: () => _open(context, folder),
              ),
          ],
        );
      },
    );
  }

  /// The sheet goes first, so Back from the folder lands on the Sharing
  /// page; the folder opens from the navigator, which outlives the sheet.
  void _open(BuildContext context, PartnerSharedFolder folder) {
    final navigator = Navigator.of(context);
    navigator.pop();
    unawaited(onOpen(navigator.context, folder));
  }
}
