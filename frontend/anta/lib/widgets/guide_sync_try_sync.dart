import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/guide_share_world.dart';
import '../models/guide_sync_world.dart';
import '../models/sync_guide_tries.dart';
import 'form_rows.dart';
import 'guide_sync_phones.dart';
import 'guide_two_phones.dart';

/// The `sync` card of the sync book (`docs/guide-hub-roadmap.md` §11.4):
/// this phone's notes over the Sync section's own rows, its sync off; the
/// other phone with nothing yet. "Sync this database" sends everything here
/// over one beat; a note made with New note follows the same way, and the
/// tick made on its first line there comes back.
///
/// A note's first task line stands under its row as a line of that note
/// ([GuideSyncNoteTask]) — the browser draws no body, and the stage needs
/// one line she can tick — the same on both phones, so a tick made here is
/// a change too; only one made there completes the step.
class GuideSyncSyncDemo extends GuideSyncPhonesDemo {
  GuideSyncSyncDemo(super.card, {super.now = DateTime.now});

  @override
  bool get opensUnbound => true;

  /// Two notes on this phone, written today; its sync off, and nothing on
  /// the other phone yet.
  @override
  GuideShareWorld seedWorld(AppLocalizations l10n) =>
      syncWorld(l10n, notes: _seed(l10n), on: false, otherHasNotes: false);

  List<GuideSyncNote> _seed(AppLocalizations l10n) => [
    seedNote('lisbon', l10n.syncGuideDemoNoteLisbon),
    seedNote('pancakes', l10n.syncGuideDemoNotePancakes),
  ];

  /// The tallest list either phone shows over the steps: the seed and the
  /// one note New note makes, with its task line.
  List<GuideSyncNote> _template(AppLocalizations l10n) => [
    ..._seed(l10n),
    seedNote(
      'template',
      l10n.syncGuideDemoNoteGroceries,
      lines: [l10n.syncGuideDemoTaskMilk],
    ),
  ];

  @override
  GuidePhoneView buildPhone(BuildContext context, GuidePhone phone) {
    final l10n = AppLocalizations.of(context)!;
    final notes = sync.notesOn(phone);
    return GuidePhoneView(
      mark: markOf(context, phone),
      area: l10n.notes,
      list: notes.isEmpty
          ? null
          : notesList(
              phone,
              notes,
              live: true,
              under: (note, live) => _task(phone, note, live),
              action: phone == GuidePhone.here
                  ? _newNote(l10n, live: true)
                  : null,
            ),
      empty: l10n.syncGuideEmptyNotes,
      template: notesList(
        phone,
        _template(l10n),
        live: false,
        under: (note, live) => _task(phone, note, live),
        action: phone == GuidePhone.here ? _newNote(l10n, live: false) : null,
      ),
      control: phone == GuidePhone.here ? syncRows(context) : null,
    );
  }

  /// A note's first task line, tickable on either phone.
  List<Widget> _task(GuidePhone phone, GuideSyncNote note, bool live) => [
    if (note.lines.isNotEmpty)
      GuideSyncNoteTask(
        line: note.lines.first,
        checked: note.ticked.contains(0),
        onChanged: (done) {
          if (!live) return;
          sync.tick(phone, note.id, 0, done);
          carry();
          settle();
        },
        identifier: live
            ? control('${GuideSyncPhonesDemo.rowControl(phone, note.id)}-task')
            : null,
      ),
  ];

  /// "New note", the last row of this phone's list.
  Widget _newNote(AppLocalizations l10n, {required bool live}) => FormActionRow(
    glyph: Icons.add_rounded,
    label: l10n.newNote,
    // The template keeps the row's enabled look; it is never tapped.
    onTap: live ? () => _add(l10n) : () {},
    identifier: live ? control('new-note') : null,
  );

  /// A note made here. With sync off it stays here: nothing is queued
  /// until "Sync this database" queues everything.
  void _add(AppLocalizations l10n) {
    sync.addNote(
      GuidePhone.here,
      title: l10n.syncGuideDemoNoteGroceries,
      lines: [l10n.syncGuideDemoTaskMilk],
    );
    carry();
    settle();
  }
}
