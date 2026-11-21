import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/guide_share_world.dart';
import '../models/guide_sync_world.dart';
import '../models/sync_guide_tries.dart';
import 'form_rows.dart';
import 'guide_sync_phones.dart';
import 'guide_two_phones.dart';

/// The `offline` card of the sync book (`docs/guide-hub-roadmap.md` §11.4),
/// the first on its page: both phones in step, this phone's sync on, and
/// airplane mode in its bar. In airplane mode the status row reads the
/// app's own "Offline — will retry" and a new note waits — the row's
/// details count it, as the page's do — while the other phone shows nothing
/// new and its dot rings; airplane mode off sends it over one beat.
class GuideSyncOfflineDemo extends GuideSyncPhonesDemo {
  GuideSyncOfflineDemo(super.card, {super.now = DateTime.now});

  /// The phones in step since the page opened.
  @override
  GuideShareWorld seedWorld(AppLocalizations l10n) {
    syncedAt = now();
    return syncWorld(l10n, notes: _seed(l10n));
  }

  List<GuideSyncNote> _seed(AppLocalizations l10n) => [
    seedNote('lisbon', l10n.syncGuideDemoNoteLisbon),
    seedNote('pancakes', l10n.syncGuideDemoNotePancakes),
  ];

  /// The seed and the one note New note makes, on either phone.
  List<GuideSyncNote> _template(AppLocalizations l10n) => [
    ..._seed(l10n),
    seedNote('template', l10n.syncGuideDemoNoteGroceries),
  ];

  @override
  GuidePhoneView buildPhone(BuildContext context, GuidePhone phone) {
    final l10n = AppLocalizations.of(context)!;
    final here = phone == GuidePhone.here;
    return GuidePhoneView(
      mark: markOf(context, phone),
      area: l10n.notes,
      list: notesList(
        phone,
        sync.notesOn(phone),
        live: true,
        action: here ? _newNote(l10n, live: true) : null,
      ),
      template: notesList(
        phone,
        _template(l10n),
        live: false,
        action: here ? _newNote(l10n, live: false) : null,
      ),
      control: here ? syncRows(context) : null,
      trailing: here ? airplaneToggle(context, phone, 'airplane') : null,
    );
  }

  /// "New note", the last row of this phone's list.
  Widget _newNote(AppLocalizations l10n, {required bool live}) => FormActionRow(
    glyph: Icons.add_rounded,
    label: l10n.newNote,
    // The template keeps the row's enabled look; it is never tapped.
    onTap: live ? () => _add(l10n) : () {},
    identifier: live ? control('new-note') : null,
  );

  /// A note made here: sent at once online, held here in airplane mode.
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
