import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/guide_share_world.dart';
import '../models/guide_sync_world.dart';
import '../models/sync_guide_tries.dart';
import '../services/sync/conflict_copy_title.dart';
import 'form_rows.dart';
import 'guide_sync_phones.dart';
import 'guide_two_phones.dart';

/// The `conflict` card of the sync book (`docs/guide-hub-roadmap.md`
/// §11.4), the second on the offline page: both phones in airplane mode,
/// each holding "Packing list" with its lines and an "Add a line" row. A
/// line added on each, then both phones online: one beat later both hold
/// the note with the later edit, and beside it the other edit as the app
/// files it — a note titled by [conflictCopyTitle] — so no line is lost.
///
/// Each phone carries its own airplane toggle, since each phone has its own
/// connection: the merge waits for both, and comes out the same whichever
/// goes online first.
class GuideSyncConflictDemo extends GuideSyncPhonesDemo {
  GuideSyncConflictDemo(super.card, {super.now = DateTime.now});

  @override
  GuideShareWorld seedWorld(AppLocalizations l10n) {
    syncedAt = now();
    return syncWorld(
      l10n,
      notes: [
        _packing(l10n, [l10n.syncGuideDemoLinePassport]),
      ],
      offline: GuidePhone.values.toSet(),
    );
  }

  GuideSyncNote _packing(AppLocalizations l10n, List<String> lines) =>
      seedNote('packing', l10n.syncGuideDemoNotePacking, lines: lines);

  /// The line each phone adds: a different one, so the two edits differ.
  static String _lineOf(AppLocalizations l10n, GuidePhone phone) =>
      switch (phone) {
        GuidePhone.here => l10n.syncGuideDemoLineSunscreen,
        GuidePhone.there => l10n.syncGuideDemoLineUmbrella,
      };

  /// The tallest state of either phone: the note with one added line, and
  /// the copy beside it holding the other.
  List<GuideSyncNote> _template(AppLocalizations l10n) {
    final passport = l10n.syncGuideDemoLinePassport;
    final copy = _packing(l10n, [passport, l10n.syncGuideDemoLineSunscreen]);
    return [
      _packing(l10n, [passport, l10n.syncGuideDemoLineUmbrella]),
      GuideSyncNote(
        id: '${copy.id}-copy',
        title: conflictCopyTitle(l10n, copy.title, now()),
        updatedAt: copy.updatedAt,
        lines: copy.lines,
      ),
    ];
  }

  @override
  List<String> reports(AppLocalizations l10n) => [
    ...super.reports(l10n),
    _reportThere(l10n),
    _reportHere(l10n),
  ];

  static String _reportThere(AppLocalizations l10n) =>
      l10n.syncGuideReportConflict;

  static String _reportHere(AppLocalizations l10n) =>
      l10n.syncGuideReportConflictHere;

  /// The landing that filed a copy says what became of the two edits, each
  /// by the phone it was made on (design review B, finding 9): the note
  /// holds the later one, whichever phone she edited last.
  @override
  void landed(List<String> copies) {
    if (copies.isEmpty) return;
    final note = sync.noteOn(GuidePhone.here, SyncGuideTries.packingNote);
    say(note?.editedOn == GuidePhone.here ? _reportHere : _reportThere);
  }

  @override
  GuidePhoneView buildPhone(BuildContext context, GuidePhone phone) {
    final l10n = AppLocalizations.of(context)!;
    return GuidePhoneView(
      mark: markOf(context, phone),
      area: l10n.notes,
      list: notesList(
        phone,
        sync.notesOn(phone),
        live: true,
        under: _lines,
        wrapTitles: true,
        action: _addLine(l10n, phone, live: true),
      ),
      template: notesList(
        phone,
        _template(l10n),
        live: false,
        under: _lines,
        wrapTitles: true,
        action: _addLine(l10n, phone, live: false),
      ),
      trailing: airplaneToggle(
        context,
        phone,
        phone == GuidePhone.here ? 'airplane' : 'there-airplane',
      ),
    );
  }

  List<Widget> _lines(GuideSyncNote note, bool live) => [
    GuideSyncNoteLines(lines: note.lines),
  ];

  /// "Add a line": this phone's line, once — held while the note already
  /// holds it, as a row is dimmed rather than hidden.
  Widget _addLine(
    AppLocalizations l10n,
    GuidePhone phone, {
    required bool live,
  }) {
    final line = _lineOf(l10n, phone);
    final note = sync.noteOn(phone, SyncGuideTries.packingNote);
    final held = note == null || note.lines.contains(line);
    return FormActionRow(
      glyph: Icons.add_rounded,
      label: l10n.syncGuideAddLine,
      // The template keeps the row's enabled look; it is never tapped.
      onTap: !live
          ? () {}
          : held
          ? null
          : () {
              sync.addLine(phone, SyncGuideTries.packingNote, line);
              carry();
              settle();
            },
      identifier: live
          ? control(phone == GuidePhone.here ? 'add-line' : 'there-add-line')
          : null,
    );
  }
}
