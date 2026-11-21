import 'package:flutter/material.dart';

import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_guide_demo.dart';
import '../models/folder.dart';
import '../models/guide_book.dart';
import '../models/guide_share_world.dart';
import '../models/note_metadata.dart';
import '../models/sync_guide_tries.dart';
import '../utils/share_copy.dart';
import 'content_rows.dart';
import 'folder_overflow_menu.dart' show FolderShareEntry;
import 'form_menu_item.dart';
import 'form_rows.dart';
import 'guide_share_rows.dart';
import 'guide_two_phones.dart';
import 'row_share_mark.dart';

/// The `folder` card of the sync book (`docs/guide-hub-roadmap.md` §11.4):
/// her two folders in the browser's rows, each ⋮ holding the folder menu's
/// own share item; the top of Sam's notes, where the folder arrives one beat
/// later marked as from her, opens under the app's "From you · Read only"
/// line, and each of its notes offers the partner's note sheet with its one
/// act, "Copy to my notes" — the copy landing in Sam's own folder.
///
/// Nothing leaves the page: the sheet's copy writes the demo's world, and
/// every other act of that sheet is disabled, as on a partner's note.
class GuideSyncFolderDemo extends GuideTwoPhonesDemo {
  GuideSyncFolderDemo(super.card, {DateTime Function() now = DateTime.now})
    : _now = now,
      super(book: GuideBook.sync.slug);

  final DateTime Function() _now;

  static const String _trips = '${GuideDemoCalendar.idPrefix}trips';
  static const String _recipes = '${GuideDemoCalendar.idPrefix}recipes';
  static const String _ideas = '${GuideDemoCalendar.idPrefix}ideas';

  /// The control name of a row on [phone]: its id without the demo prefix,
  /// under the phone it stands on.
  static String rowControl(GuidePhone phone, String id) =>
      '${phone.name}-${id.replaceFirst(GuideDemoCalendar.idPrefix, '')}';

  /// The control name of a folder row's ⋮ on her phone.
  static String menuControl(String folderId) =>
      'more-${folderId.replaceFirst(GuideDemoCalendar.idPrefix, '')}';

  String _control(String name) =>
      SemanticsIds.guideBookTryControl(book, slug, name);

  static String _report(AppLocalizations l10n) =>
      l10n.syncGuideReportFolderCopy(
        l10n.syncGuideDemoPartner,
        l10n.syncGuideDemoFolderIdeas,
      );

  @override
  List<String> reports(AppLocalizations l10n) => [_report(l10n)];

  /// Two folders of hers — Trips with two notes, Recipes with one — written
  /// today.
  @override
  GuideShareWorld seedWorld(AppLocalizations l10n) {
    final now = _now();
    final day = DateTime.utc(now.year, now.month, now.day);
    final today = DateTime(now.year, now.month, now.day, now.hour);
    NoteMetadata note(String id, String folderId, String title) => NoteMetadata(
      id: '${GuideDemoCalendar.idPrefix}$id',
      folderId: folderId,
      title: title,
      preview: '',
      contentLength: 0,
      chunkCount: 0,
      isCompressed: false,
      createdAt: today,
      updatedAt: today,
    );
    return GuideShareWorld(
      day: day,
      events: const [],
      folders: [
        Folder(id: _trips, name: l10n.syncGuideDemoFolderTrips, createdAt: day),
        Folder(
          id: _recipes,
          name: l10n.syncGuideDemoFolderRecipes,
          createdAt: day,
          position: 1,
        ),
      ],
      notes: [
        note('lisbon', _trips, l10n.syncGuideDemoNoteLisbon),
        note('packing', _trips, l10n.syncGuideDemoNotePacking),
        note('pancakes', _recipes, l10n.syncGuideDemoNotePancakes),
      ],
    );
  }

  @override
  String phoneLabel(AppLocalizations l10n, GuidePhone phone) => switch (phone) {
    GuidePhone.here => l10n.syncGuidePhoneYours,
    GuidePhone.there => l10n.syncGuidePhoneTheirs(l10n.syncGuideDemoPartner),
  };

  @override
  GuidePhoneView buildPhone(BuildContext context, GuidePhone phone) {
    final l10n = AppLocalizations.of(context)!;
    switch (phone) {
      case GuidePhone.here:
        return GuidePhoneView(
          mark: GuideShareLooks.herMark(context),
          area: l10n.notes,
          list: _hers(context, l10n, live: true),
          template: _hers(context, l10n, live: false),
        );
      case GuidePhone.there:
        final open = world.theirFolderOpen;
        final opened = open == null
            ? null
            : world.theirFolders.firstWhere((folder) => folder.id == open);
        final copies = world.copies;
        return GuidePhoneView(
          mark: GuideShareLooks.samMark(l10n),
          area:
              opened?.name ??
              (_ideasOpen ? l10n.syncGuideDemoFolderIdeas : l10n.notes),
          list: opened != null
              ? _samsFolder(context, l10n, opened, live: true)
              : !_ideasOpen
              ? _samsTop(context, l10n, live: true)
              : copies.isEmpty
              ? null
              : _samsIdeas(context, copies, live: true),
          empty: l10n.syncGuideEmptyNotes,
          // Sam's tallest top — both her folders arrived beside Sam's own —
          // the fullest folder opened, and Sam's own holding a copy, one
          // over the other: the phone is as tall as the tallest.
          template: Stack(
            children: [
              _samsTop(context, l10n, live: false),
              _samsFolder(context, l10n, _fullest(), live: false),
              _samsIdeas(context, [world.notes.first], live: false),
            ],
          ),
          backSlot: true,
          onBack: opened != null
              ? _closeFolder
              : _ideasOpen
              ? _closeIdeas
              : null,
          backIdentifier: _control('back'),
        );
    }
  }

  /// Her folder with the share mark the world gives it.
  Folder _herFolder(Folder folder, {required bool shared}) =>
      shared ? folder.copyWith(share: FolderShare.byMark) : folder;

  /// Her top of the browser: each folder with its share sign while shared
  /// and its ⋮. The template draws both shared.
  Widget _hers(
    BuildContext context,
    AppLocalizations l10n, {
    required bool live,
  }) {
    final look = GuideShareLooks.toSam(l10n);
    Widget row(Folder folder) {
      final shown = _herFolder(
        folder,
        shared: !live || world.isFolderShared(folder.id),
      );
      return GuideShareFolderRow(
        folder: shown,
        mark: RowShareMark.forFolder(shown, look, l10n),
        identifier: live
            ? _control(rowControl(GuidePhone.here, folder.id))
            : null,
        // The template keeps the ⋮'s room, so the name wraps as it will.
        onMenu: live ? (anchor) => _openMenu(context, anchor, folder) : (_) {},
        menuIdentifier: live ? _control(menuControl(folder.id)) : null,
      );
    }

    return FormRowGroup(
      trailingGap: false,
      children: [for (final folder in world.folders) row(folder)],
    );
  }

  /// The top of Sam's notes: her folders as they arrived, marked as from
  /// her, over Sam's own folder, where a copy goes.
  Widget _samsTop(
    BuildContext context,
    AppLocalizations l10n, {
    required bool live,
  }) {
    final look = GuideShareLooks.fromYou(l10n);
    final folders = live
        ? world.theirFolders
        : [
            for (final folder in world.folders)
              folder.copyWith(fromPartner: true),
          ];
    return FormRowGroup(
      trailingGap: false,
      children: [
        for (final folder in folders)
          GuideShareFolderRow(
            folder: folder,
            mark: RowShareMark.forFolder(folder, look, l10n),
            count: world.notesIn(folder.id).length,
            onTap: live ? () => _openFolder(folder.id) : null,
            identifier: live
                ? _control(rowControl(GuidePhone.there, folder.id))
                : null,
          ),
        GuideShareFolderRow(
          folder: Folder(
            id: _ideas,
            name: l10n.syncGuideDemoFolderIdeas,
            createdAt: world.day,
          ),
          mark: null,
          count: world.copyCount,
          onTap: live ? _openIdeas : null,
          identifier: live
              ? _control(rowControl(GuidePhone.there, _ideas))
              : null,
        ),
      ],
    );
  }

  /// Sam's own folder opened: the copies made there, Sam's own notes, under
  /// no read-only line. The stage opens no editor, so a copy opens nothing.
  Widget _samsIdeas(
    BuildContext context,
    List<NoteMetadata> copies, {
    required bool live,
  }) {
    final now = _now();
    return FormRowGroup(
      trailingGap: false,
      children: [
        for (final (index, note) in copies.indexed)
          GuideShareNoteRow(
            note: note,
            mark: null,
            now: now,
            identifier: live
                ? _control(rowControl(GuidePhone.there, '$_ideas-$index'))
                : null,
          ),
      ],
    );
  }

  /// Her folder with the most notes, the opened state the template draws.
  Folder _fullest() => world.folders.reduce(
    (a, b) => world.notesIn(b.id).length > world.notesIn(a.id).length ? b : a,
  );

  /// One of her folders opened on Sam's phone: the browser's read-only line
  /// over its notes, each opening the partner's note sheet.
  Widget _samsFolder(
    BuildContext context,
    AppLocalizations l10n,
    Folder folder, {
    required bool live,
  }) {
    final look = GuideShareLooks.fromYou(l10n);
    final now = _now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SharedReadOnlyLine(
          partner: null,
          text: ShareCopy.sentence(l10n.sharedNoteLine(l10n.syncGuideDemoYou)),
          identifier: live ? _control('read-only') : null,
        ),
        const SizedBox(height: RowMetrics.groupGap),
        FormRowGroup(
          trailingGap: false,
          children: [
            for (final note in world.theirNotesIn(folder.id))
              GuideShareNoteRow(
                note: note,
                mark: RowShareMark.forNote(note, look, l10n),
                now: now,
                onTap: live ? () => _openNote(context, note) : null,
                identifier: live
                    ? _control(rowControl(GuidePhone.there, note.id))
                    : null,
              ),
          ],
        ),
      ],
    );
  }

  /// The folder menu's share item (`FolderOverflowMenu._partnerShareRow`,
  /// resolved as `FolderShareEntry` resolves a folder shared by its own
  /// mark): "Share with Sam", or "Shared with Sam" ticked — a second pick
  /// takes the share back.
  Future<void> _openMenu(
    BuildContext context,
    BuildContext anchor,
    Folder folder,
  ) => openOnce(() async {
    final l10n = AppLocalizations.of(context)!;
    final partner = l10n.syncGuideDemoPartner;
    final shared = world.isFolderShared(folder.id);
    final entry = FolderShareEntry(
      label: shared
          ? l10n.sharedWithPartner(partner)
          : l10n.shareWithPartner(partner),
      checked: shared,
    );
    final picked = await showFormMenu<bool>(
      anchor,
      items: [
        FormMenuItem(
          value: true,
          label: entry.label,
          icon: Icons.group_rounded,
          identifier: _control('share'),
        ),
      ],
      selected: entry.checked ? true : null,
      menuWidth: FormMetrics.menuWidth,
    );
    if (picked == null || !context.mounted) return;
    world.shareFolder(folder.id, !shared);
    send(GuidePhone.there);
    settle();
  });

  void _openFolder(String folderId) {
    world.openTheirFolder(folderId);
    settle();
  }

  void _closeFolder() {
    world.closeTheirFolder();
    settle();
  }

  /// Sam's own folder is open on Sam's phone. A look of hers, no step and
  /// no change to the world (D44): it only redraws, and a standing report —
  /// the copy's, which names this folder — stays.
  bool _ideasOpen = false;

  void _openIdeas() {
    _ideasOpen = true;
    redraw();
  }

  void _closeIdeas() {
    _ideasOpen = false;
    redraw();
  }

  /// A partner's note row's long-press sheet (`NoteRow._showActionSheet`),
  /// raised by a tap here since the stage opens no editor: every act that
  /// would write disabled, and "Copy to my notes", whose copy lands in Sam's
  /// own folder. Sam's phone then shows its top, where that folder counts
  /// it.
  Future<void> _openNote(BuildContext context, NoteMetadata note) =>
      openOnce(() => _showNoteSheet(context, note));

  Future<void> _showNoteSheet(BuildContext context, NoteMetadata note) async {
    final l10n = AppLocalizations.of(context)!;
    RowAction off(IconData icon, String label, String identifier) => RowAction(
      icon: icon,
      label: label,
      identifier: identifier,
      enabled: false,
      onSelected: () {},
    );
    await showRowActionSheet(
      context,
      title: note.title,
      headerBuilder: (_) => SharedReadOnlyLine(
        partner: null,
        text: l10n.syncGuideSharedNoteCaption(l10n.syncGuideDemoPartner),
        banded: false,
      ),
      actions: [
        off(
          Icons.check_circle_outline,
          l10n.select,
          SemanticsIds.rowActionSelect,
        ),
        off(Icons.edit_rounded, l10n.rename, SemanticsIds.rowActionRename),
        off(
          Icons.drive_file_move_outlined,
          l10n.moveToFolder,
          SemanticsIds.rowActionMove,
        ),
        off(
          Icons.share_rounded,
          l10n.shareNote,
          SemanticsIds.rowActionSendCopy,
        ),
        RowAction(
          icon: Icons.content_copy_rounded,
          label: l10n.sharedNoteCopy,
          identifier: SemanticsIds.rowActionCopyToMine,
          onSelected: () => _copy(note.id),
        ),
        RowAction(
          icon: Icons.delete_rounded,
          label: l10n.delete,
          identifier: SemanticsIds.rowActionDelete,
          isDestructive: true,
          enabled: false,
          onSelected: () {},
        ),
      ],
    );
  }

  void _copy(String noteId) {
    world
      ..copyTheirs(noteId)
      ..closeTheirFolder();
    settle();
    say(_report);
  }
}
