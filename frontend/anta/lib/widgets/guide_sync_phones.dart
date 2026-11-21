import 'package:flutter/material.dart';

import '../constants/guide_metrics.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_guide_demo.dart';
import '../models/guide_book.dart';
import '../models/guide_share_world.dart';
import '../models/guide_sync_world.dart';
import '../models/note_metadata.dart';
import '../models/sync_guide_tries.dart';
import '../services/sync/conflict_copy_title.dart';
import '../services/sync/sync_gateway.dart';
import '../services/sync/sync_status.dart';
import '../utils/settings_search.dart';
import 'automation_id.dart';
import 'form_rows.dart';
import 'guide_share_rows.dart';
import 'guide_two_phones.dart';
import 'settings_section_list.dart';
import 'sync_settings_sections.dart';

/// The base of the sync book's cards about two phones of her own
/// (`docs/guide-hub-roadmap.md` §11.4 `sync`, `offline`; D46): "This phone"
/// and "Your other phone", their notes in the browser's note rows, the Sync
/// section's own rows ([syncStatusEntry], [syncNowEntry],
/// [syncThisDatabaseEntry], D43) on this phone, and airplane mode as a
/// toggle in a phone's bar (spec §5 K).
///
/// The world's [GuideShareWorld.sync] carries the notes both ways, so a
/// phone is "in flight" by what waits for it there ([inFlightTo]), and a
/// change held by airplane mode rings without a beat ([waitsFor]). The beat
/// starts only when something can move ([carry]).
abstract class GuideSyncPhonesDemo extends GuideTwoPhonesDemo {
  GuideSyncPhonesDemo(super.card, {required this.now})
    : super(book: GuideBook.sync.slug);

  /// The clock the card reads its times from: a note's date, the status
  /// row's last sync and a conflict copy's title.
  @protected
  final DateTime Function() now;

  GuideSyncWorld get sync => world.sync!;

  /// When this phone last finished a sync, for the status row's details;
  /// null before its first.
  DateTime? _syncedAt;

  @protected
  set syncedAt(DateTime? value) => _syncedAt = value;

  String control(String name) =>
      SemanticsIds.guideBookTryControl(book, slug, name);

  /// The control name of [noteId]'s row on [phone]: its id without the demo
  /// prefix, under the phone it stands on.
  static String rowControl(GuidePhone phone, String noteId) =>
      '${phone.name}-${noteId.replaceFirst(GuideDemoCalendar.idPrefix, '')}';

  /// A world of her two phones over [notes], each at the seed's stamp.
  @protected
  GuideShareWorld syncWorld(
    AppLocalizations l10n, {
    required List<GuideSyncNote> notes,
    bool on = true,
    bool otherHasNotes = true,
    Set<GuidePhone> offline = const {},
  }) {
    final today = now();
    return GuideShareWorld(
      day: DateTime.utc(today.year, today.month, today.day),
      events: const [],
      sync: GuideSyncWorld(
        notes: notes,
        copyTitle: (title, at) => conflictCopyTitle(l10n, title, at),
        now: now,
        on: on,
        otherHasNotes: otherHasNotes,
        offline: offline,
      ),
    );
  }

  /// A note of the seed, written today.
  @protected
  GuideSyncNote seedNote(
    String id,
    String title, {
    List<String> lines = const [],
  }) => GuideSyncNote(
    id: '${GuideDemoCalendar.idPrefix}$id',
    title: title,
    updatedAt: now(),
    lines: lines,
    stamp: 1,
  );

  @override
  String phoneLabel(AppLocalizations l10n, GuidePhone phone) => switch (phone) {
    GuidePhone.here => l10n.syncGuidePhoneThis,
    GuidePhone.there => l10n.syncGuidePhoneOther,
  };

  /// Her phone's glyph, or her other phone's linked-phones glyph (§11.8 G).
  @protected
  Widget markOf(BuildContext context, GuidePhone phone) => switch (phone) {
    GuidePhone.here => GuideShareLooks.herMark(context),
    GuidePhone.there => Icon(
      Icons.phonelink_rounded,
      size: GuideMetrics.phoneMarkSize,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  };

  /// Both phones are her own and changes travel both ways: a phone is in
  /// flight while anything for it waits, on the other phone or the account.
  @override
  bool inFlightTo(GuidePhone phone) => sync.inFlightTo(phone);

  /// Whatever is on its way rings, held by airplane mode or travelling.
  @override
  bool waitsFor(GuidePhone phone) => true;

  /// Sets out what can move now: a beat toward every phone something waits
  /// for — none while every phone that could send or take it in is offline,
  /// where the ring alone says it waits (spec §4).
  @protected
  void carry() {
    if (!sync.canMove) return;
    for (final phone in GuidePhone.values) {
      if (sync.inFlightTo(phone)) send(phone);
    }
  }

  @override
  void land() {
    super.land();
    landed(sync.deliver());
    if (sync.isOnline(GuidePhone.here) && sync.on) _syncedAt = now();
  }

  /// What a landing did, for a card that says it: the conflict copies it
  /// filed.
  @protected
  void landed(List<String> copies) {}

  /// This phone's sync as its status row reads it: offline with what waits,
  /// sending what it made or receiving what the other made while the beat
  /// runs, else idle.
  SyncStatus statusOf() {
    final waiting = sync.waitingOn(GuidePhone.here);
    final at = _syncedAt;
    if (!sync.isOnline(GuidePhone.here)) {
      return SyncStatus(
        pendingCount: waiting,
        lastPullAt: at,
        lastPushAt: at,
        lastFailure: SyncFailureInfo(SyncGatewayFailure.offline, at: now()),
      );
    }
    final activity = !beating
        ? SyncActivity.idle
        : waiting > 0
        ? SyncActivity.pushing
        : sync.inFlightTo(GuidePhone.here)
        ? SyncActivity.pulling
        : SyncActivity.idle;
    return SyncStatus(
      pendingCount: waiting,
      lastPullAt: at,
      lastPushAt: at,
      activity: activity,
    );
  }

  /// The Sync section as the page draws it for a database that syncs — the
  /// status row over Sync now — or, while this phone does not sync yet, its
  /// one "Sync this database" row; as tall as the bound section in either,
  /// so turning it on moves nothing under the finger (D55).
  @protected
  Widget syncRows(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    SettingsSectionData section({required bool bound, required bool live}) {
      final status = statusOf();
      return SettingsSectionData(
        icon: Icons.sync_rounded,
        title: l10n.syncSection,
        entries: bound
            ? [
                syncStatusEntry(
                  context,
                  l10n,
                  status: status,
                  identifier: live ? control : null,
                  now: now(),
                ),
                syncNowEntry(
                  l10n,
                  enabled: status.activity == SyncActivity.idle,
                  onTap: live ? syncNow : () {},
                  identifier: live ? control : null,
                ),
              ]
            : [
                syncThisDatabaseEntry(
                  l10n,
                  description: l10n.syncThisDatabaseDesc,
                  identifier: live ? control : null,
                  row: (context, title, slot) => SyncBindTile(
                    title: title,
                    description: slot,
                    onTap: live ? turnOn : () {},
                  ),
                ),
              ],
      );
    }

    Widget list(SettingsSectionData data) => SettingsSectionList(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      query: SettingsQuery.empty,
      sections: [data],
    );

    final live = list(section(bound: sync.on, live: true));
    if (!opensUnbound) return live;
    return GuideTallest(
      templates: [list(section(bound: true, live: false))],
      child: live,
    );
  }

  /// The card opens with this phone's sync off, so its Sync section has
  /// two shapes to keep one height across.
  @protected
  bool get opensUnbound => false;

  /// "Sync this database": this phone syncs from now, everything on it
  /// queued, as a bind queues every row.
  @protected
  void turnOn() {
    sync.turnOn();
    carry();
    settle();
  }

  /// "Sync now": nothing waits while a phone is online, since every change
  /// sets out at once — so online it says both phones already match; in
  /// airplane mode the run fails as the engine's does, and the line stays.
  @protected
  void syncNow() {
    if (sync.isOnline(GuidePhone.here) && !sync.canMove) {
      say(_matchReport);
      return;
    }
    carry();
    settle();
  }

  static String _matchReport(AppLocalizations l10n) =>
      l10n.syncGuideReportSyncNow;

  @override
  List<String> reports(AppLocalizations l10n) => [_matchReport(l10n)];

  /// Airplane mode on [phone]'s bar (spec §5 K): a toggle, never a row — it
  /// is the phone's setting, not the app's. Off it, what waited sets out.
  /// One node carries the id, the label, the tap and the toggled state: the
  /// button's own node says "selected", never on or off (design review B,
  /// finding 4).
  @protected
  Widget airplaneToggle(BuildContext context, GuidePhone phone, String name) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = AppLocalizations.of(context)!.syncGuideAirplaneMode;
    final on = !sync.isOnline(phone);
    void toggle() {
      sync.setOnline(phone, on);
      carry();
      settle();
    }

    return Semantics(
      identifier: control(name),
      container: true,
      button: true,
      toggled: on,
      label: label,
      onTap: toggle,
      excludeSemantics: true,
      child: IconButton(
        isSelected: on,
        icon: Icon(
          Icons.airplanemode_inactive_rounded,
          color: colorScheme.onSurfaceVariant,
        ),
        selectedIcon: Icon(
          Icons.airplanemode_active_rounded,
          color: colorScheme.primary,
        ),
        tooltip: label,
        onPressed: toggle,
      ),
    );
  }

  /// [notes] in the browser's note rows, each followed by what [under]
  /// draws of it, and [action] — the card's "New note" or "Add a line" —
  /// as the group's last row. [live] off draws the unseen template: no ids,
  /// no taps. [wrapTitles] for a list whose titles are the lesson — a
  /// conflict copy's, longer than a row's one line.
  @protected
  Widget notesList(
    GuidePhone phone,
    List<GuideSyncNote> notes, {
    required bool live,
    List<Widget> Function(GuideSyncNote note, bool live)? under,
    Widget? action,
    bool wrapTitles = false,
  }) {
    final today = now();
    return FormRowGroup(
      trailingGap: false,
      children: [
        for (final note in notes) ...[
          GuideShareNoteRow(
            note: NoteMetadata(
              id: note.id,
              folderId: '',
              title: note.title,
              preview: '',
              contentLength: 0,
              chunkCount: 0,
              isCompressed: false,
              createdAt: note.updatedAt,
              updatedAt: note.updatedAt,
            ),
            mark: null,
            now: today,
            identifier: live ? control(rowControl(phone, note.id)) : null,
            wrapTitle: wrapTitles,
          ),
          ...?under?.call(note, live),
        ],
        ?action,
      ],
    );
  }
}

/// [child] in a box as tall as the tallest of [templates] — its states,
/// the tallest among them — laid out unseen beneath it: the frame's
/// template rule (D55) for a control whose states differ in height, so a
/// state change moves nothing under the finger.
class GuideTallest extends StatelessWidget {
  const GuideTallest({super.key, required this.templates, required this.child});

  final List<Widget> templates;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        ExcludeSemantics(
          child: ExcludeFocus(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0,
                child: Stack(fit: StackFit.passthrough, children: templates),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Align(alignment: AlignmentDirectional.topStart, child: child),
        ),
      ],
    );
  }
}

/// The lines of a note under its row, in the note row's second-line type:
/// what the conflict card shows of each version of "Packing list". The
/// browser's note row shows no body, so this row is the stage's own: it
/// reads the lines and taps nothing.
class GuideSyncNoteLines extends FormDividedRow {
  const GuideSyncNoteLines({super.key, required this.lines});

  final List<String> lines;

  @override
  double get dividerIndent => RowMetrics.dividerIndentPlain;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: RowMetrics.twoLinePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Text(
              '• $line',
              style: TextStyle(
                fontSize: RowMetrics.secondLineFontSize,
                height:
                    FormMetrics.captionLineHeight /
                    RowMetrics.secondLineFontSize,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// A note's task line under its row, in [GuideSyncNoteLines]' type behind
/// the checkbox a note's task line carries: the `sync` card's one line she
/// ticks, so it reads as a line of the note above it and not as a note of
/// its own (design review B, finding 6). The whole row is one 48 dp target
/// and one node, as [FormCheckRow]'s is.
class GuideSyncNoteTask extends FormDividedRow {
  const GuideSyncNoteTask({
    super.key,
    required this.line,
    required this.checked,
    required this.onChanged,
    this.identifier,
  });

  final String line;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final String? identifier;

  @override
  double get dividerIndent => RowMetrics.dividerIndentPlain;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    void toggle() => onChanged(!checked);
    final Widget well = InkWell(
      onTap: toggle,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: RowMetrics.groupInset,
            end: RowMetrics.groupInset,
          ),
          child: Row(
            children: [
              Checkbox(
                value: checked,
                onChanged: (_) => toggle(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: FormMetrics.gap),
              Expanded(
                child: Text(
                  line,
                  style: TextStyle(
                    fontSize: RowMetrics.secondLineFontSize,
                    height:
                        FormMetrics.captionLineHeight /
                        RowMetrics.secondLineFontSize,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (identifier case final id?) {
      return AutomationId(identifier: id, child: well);
    }
    return MergeSemantics(child: well);
  }
}
