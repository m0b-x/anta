import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_demo.dart';
import '../models/folder.dart';
import '../models/guide_book.dart';
import '../models/guide_share_world.dart';
import '../models/note_metadata.dart';
import '../models/sync_guide_tries.dart';
import '../services/day_summary_resolver.dart';
import '../services/event_time_formatter.dart';
import '../utils/settings_search.dart';
import 'agenda_list_view.dart' show AgendaListView;
import 'app_dialogs.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'guide_share_rows.dart';
import 'guide_two_phones.dart';
import 'row_share_mark.dart';
import 'settings_section_list.dart';

/// The `stop` card of the sync book (`docs/guide-hub-roadmap.md` §11.4):
/// her phone holds what she shares — a category, an event and a folder —
/// as the Sharing page's own lists draw them, each row with its ✕, over the
/// page's own Pairing rows; Sam's phone lists what reached it from her.
/// Each way out is read off Sam's phone one beat later.
///
/// Both of the page's confirmations run here, as the page asks them: a
/// dialog returns to the page, so the stage keeps its coach.
class GuideSyncStopDemo extends GuideTwoPhonesDemo {
  GuideSyncStopDemo(super.card, {DateTime Function() now = DateTime.now})
    : _now = now,
      super(book: GuideBook.sync.slug);

  final DateTime Function() _now;

  static const String _category = 'gym';
  static const String _pilates = '${GuideDemoCalendar.idPrefix}pilates';
  static const String _dentist = SyncGuideTries.stopEvent;
  static const String _trips = '${GuideDemoCalendar.idPrefix}trips';

  /// The control name of a row on [phone]: its id without the demo prefix,
  /// under the phone it stands on.
  static String rowControl(GuidePhone phone, String id) =>
      '${phone.name}-${id.replaceFirst(GuideDemoCalendar.idPrefix, '')}';

  /// The control name of the ✕ on her row for [id].
  static String unshareControl(String id) =>
      'unshare-${id.replaceFirst(GuideDemoCalendar.idPrefix, '')}';

  String _control(String name) =>
      SemanticsIds.guideBookTryControl(book, slug, name);

  static String _report(AppLocalizations l10n) =>
      l10n.syncGuideReportStopUnpair(l10n.syncGuideDemoPartner);

  /// The category's ✕ is the stage's, not the app's: used, it says where
  /// the real control lives (design review, finding 9), as a report rather
  /// than a second instruction in the `all` step's line.
  static String _pickerReport(AppLocalizations l10n) =>
      l10n.syncGuideTryStopCategoryPicker(l10n.shareRowCategories);

  @override
  List<String> reports(AppLocalizations l10n) => [
    _report(l10n),
    _pickerReport(l10n),
  ];

  /// Paired, and sharing one category with its event, one event on its own
  /// and one folder with its notes — all of it already on Sam's phone.
  @override
  GuideShareWorld seedWorld(AppLocalizations l10n) {
    final now = _now();
    final day = DateTime.utc(now.year, now.month, now.day);
    final seed = CalendarCategories.builtInSeeds.firstWhere(
      (seed) => seed.id == _category,
    );
    final world = GuideShareWorld(
      day: day,
      categories: [
        CalendarCategory(
          id: seed.id,
          name: CalendarCategories.builtInSeedName(seed.kind),
          colorValue: seed.colorValue,
          iconKey: seed.iconKey,
          sortOrder: 0,
          isBuiltIn: true,
        ),
      ],
      events: [
        CalendarEvent(
          id: _pilates,
          title: l10n.calendarGuideDemoEventPilates,
          categoryId: _category,
          startDate: day,
          time: const EventTime(startMinute: 7 * 60 + 30, durationMinutes: 60),
        ),
        CalendarEvent(
          id: _dentist,
          title: l10n.calendarGuideDemoEventDentist,
          categoryId: CalendarCategories.fallback.id,
          iconKey: 'medical_services',
          startDate: day,
          time: const EventTime(startMinute: 9 * 60, durationMinutes: 45),
        ),
      ],
      folders: [
        Folder(id: _trips, name: l10n.syncGuideDemoFolderTrips, createdAt: day),
      ],
      notes: [
        for (final (id, title) in [
          ('lisbon', l10n.syncGuideDemoNoteLisbon),
          ('packing', l10n.syncGuideDemoNotePacking),
        ])
          NoteMetadata(
            id: '${GuideDemoCalendar.idPrefix}$id',
            folderId: _trips,
            title: title,
            preview: '',
            contentLength: 0,
            chunkCount: 0,
            isCompressed: false,
            createdAt: day,
            updatedAt: day,
          ),
      ],
    );
    return world
      ..shareCategory(_category, true)
      ..share(_dentist, true)
      ..shareFolder(_trips, true)
      ..deliver();
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
      // Once unpaired a phone shares with no one: its bar names the area
      // alone and its list the app's own "Not paired" (§11.4, `unpair`).
      case GuidePhone.here:
        return GuidePhoneView(
          mark: GuideShareLooks.herMark(context),
          area: world.paired
              ? l10n.sharingWithTitle(l10n.syncGuideDemoPartner)
              : l10n.shareSectionLabel,
          list: world.paired ? _hers(context, l10n, live: true) : null,
          // Her list never changes height: every row stays for the card's
          // life, in a slot as tall as its taller caption.
          template: _hers(context, l10n, live: false),
          empty: l10n.pairingNotPaired,
          control: _pairing(context, l10n),
        );
      case GuidePhone.there:
        final shown = world.theirs.isNotEmpty || world.theirFolders.isNotEmpty;
        return GuidePhoneView(
          mark: GuideShareLooks.samMark(l10n),
          area: world.theirPaired
              ? l10n.sharingWithTitle(l10n.syncGuideDemoYou)
              : l10n.shareSectionLabel,
          list: shown
              ? _sams(
                  context,
                  l10n,
                  world.theirs,
                  world.theirFolders,
                  live: true,
                )
              : null,
          // The seed is Sam's tallest: everything she shares has arrived.
          template: _sams(
            context,
            l10n,
            [for (final event in world.events) GuideShareWorld.asTheirs(event)],
            [
              for (final folder in world.folders)
                folder.copyWith(fromPartner: true),
            ],
            live: false,
          ),
          empty: world.theirPaired
              ? l10n.syncGuideEmptyFromYou
              : l10n.pairingNotPaired,
        );
    }
  }

  /// What she shares, as the Sharing page's "You share" lists draw it
  /// (`MySharedEventsSheet`, `MySharedFoldersSheet`): each thing a row with
  /// its ✕, which takes that one share back. The categories have no such
  /// list in the app — they are ticked in a picker — so theirs takes the
  /// event rows' shape.
  ///
  /// Where the page drops a row once its share is taken back, the stage
  /// keeps it, its ✕ off and its caption saying so, in a slot as tall as
  /// either caption: a ✕ that slid up into the finger's place would take a
  /// second thing back on a double tap (design review, finding 1).
  Widget _hers(
    BuildContext context,
    AppLocalizations l10n, {
    required bool live,
  }) {
    final category = world.categories.single;
    final event = world.events.firstWhere((event) => event.id == _dentist);
    final folder = world.folders.single;
    final summary = EventSummaryProvider(
      l10n,
      showRecurrence: false,
    ).entryFor(event, world.day);
    final time = event.time!;
    final dimmed = Theme.of(
      context,
    ).colorScheme.outline.withValues(alpha: FormMetrics.disabledOpacity);
    Widget row({
      required String id,
      required bool shared,
      Widget? leading,
      IconData? glyph,
      required String label,
      required String caption,
      required VoidCallback onUnshare,
    }) {
      FormPickerRow drawn({required bool on, bool live = false}) =>
          FormPickerRow(
            leading: leading,
            glyph: glyph,
            label: label,
            caption: on ? caption : l10n.syncGuideTryStopNotShared,
            // The events sheet's rows wrap their line; the folders sheet's
            // take the check row's shape.
            captionWraps: leading != null,
            checkRowShape: glyph != null,
            showChevron: false,
            enabled: on,
            identifier: live ? _control(rowControl(GuidePhone.here, id)) : null,
            onTap: null,
            trailingButton: FormTrailingButton(
              icon: Icons.close_rounded,
              tooltip: l10n.shareStopSharingTooltip,
              identifier: live ? _control(unshareControl(id)) : null,
              onPressed: on ? onUnshare : null,
              disabledColor: dimmed,
            ),
          );
      final shown = drawn(on: !live || shared, live: live);
      return FormIndentedRow(
        dividerIndent: shown.dividerIndent,
        // Centred, so the ✕ — centred on its row — keeps its place in a slot
        // taller than the caption standing now.
        child: FormCaptionSlot(
          alignment: AlignmentDirectional.centerStart,
          candidates: [drawn(on: true), drawn(on: false)],
          child: shown,
        ),
      );
    }

    return FormRowGroup(
      trailingGap: false,
      children: [
        row(
          id: category.id,
          shared: world.isCategoryShared(category.id),
          leading: EventAvatar(
            icon: CalendarIcons.forKey(category.iconKey) ?? Icons.event_rounded,
            color: category.color,
          ),
          label: CalendarCategories.labelOf(category, l10n),
          caption: l10n.categoryEventCount(world.eventCountOf(category.id)),
          onUnshare: () {
            _unshare(() => world.shareCategory(category.id, false));
            say(_pickerReport);
          },
        ),
        row(
          id: event.id,
          shared: world.isShared(event.id),
          leading: EventAvatar.ofRow(
            icon: summary.icon,
            color: summary.color,
            partner: null,
            l10n: l10n,
          ),
          label: event.title,
          caption:
              '${AgendaListView.shortDayLabel(l10n, world.day, world.day)}'
              ' · ${EventTimeFormatter.formatRangeOfContext(time, context)}',
          onUnshare: () => _unshare(() => world.share(event.id, false)),
        ),
        row(
          id: folder.id,
          shared: world.isFolderShared(folder.id),
          glyph: Icons.folder_outlined,
          label: folder.name,
          caption: l10n.shareFolderNotes(world.notesIn(folder.id).length),
          onUnshare: () => _unshare(() => world.shareFolder(folder.id, false)),
        ),
      ],
    );
  }

  /// A ✕: that one share is taken back, and leaves Sam's phone with the
  /// beat.
  void _unshare(VoidCallback takeBack) {
    takeBack();
    send(GuidePhone.there);
    settle();
  }

  /// What Sam's phone shows from her: her events as a partner's are drawn
  /// and her folder marked as from her, then the category's events under
  /// the category's name, so "the category remains" can be read there.
  Widget _sams(
    BuildContext context,
    AppLocalizations l10n,
    List<CalendarEvent> events,
    List<Folder> folders, {
    required bool live,
  }) {
    final look = GuideShareLooks.fromYou(l10n);
    final category = world.categories.single;
    List<Widget> dayRows(Iterable<CalendarEvent> shown) => guideShareDayRows(
      context,
      day: world.day,
      events: shown.toList(),
      look: look,
      identifier: live
          ? (id) => _control(rowControl(GuidePhone.there, id))
          : null,
    );
    final inCategory = events.where((e) => e.categoryId == category.id);
    final rest = [
      ...dayRows(events.where((e) => e.categoryId != category.id)),
      for (final folder in folders)
        GuideShareFolderRow(
          folder: folder,
          mark: RowShareMark.forFolder(folder, look, l10n),
          count: world.notesIn(folder.id).length,
          identifier: live
              ? _control(rowControl(GuidePhone.there, folder.id))
              : null,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rest.isNotEmpty)
          FormRowGroup(trailingGap: inCategory.isNotEmpty, children: rest),
        if (inCategory.isNotEmpty) ...[
          FormSectionLabel(text: CalendarCategories.labelOf(category, l10n)),
          FormRowGroup(trailingGap: false, children: dayRows(inCategory)),
        ],
      ],
    );
  }

  /// The Sharing page's Pairing section (`SharingPage._pairingSection`) in
  /// the settings kit, each row enabled as the page enables it: Stop
  /// sharing everything while something is shared, Unpair while paired.
  Widget _pairing(BuildContext context, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final canStop = world.sharesAnything;
    final canUnpair = world.paired;
    return SettingsSectionList(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      query: SettingsQuery.empty,
      sections: [
        SettingsSectionData(
          icon: Icons.link_rounded,
          title: l10n.pairingSection,
          entries: [
            SettingsEntry(
              title: l10n.shareStopAll,
              description: l10n.shareStopAllDesc,
              identifier: _control('stop-all'),
              builder: (context, title, description) => ListTile(
                enabled: canStop,
                leading: Icon(
                  Icons.group_off_rounded,
                  color: canStop ? colorScheme.primary : null,
                ),
                title: title,
                subtitle: description,
                onTap: () => _stopAll(context),
              ),
            ),
            SettingsEntry(
              title: l10n.unpair,
              description: l10n.shareUnpairDesc,
              titleStyle: canUnpair
                  ? TextStyle(color: colorScheme.error)
                  : null,
              identifier: _control('unpair'),
              builder: (context, title, description) => ListTile(
                enabled: canUnpair,
                leading: Icon(
                  Icons.link_off_rounded,
                  color: canUnpair ? colorScheme.error : null,
                ),
                title: title,
                subtitle: description,
                onTap: () => _unpair(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The page's own confirmation (`SharingPage._stopAll`), then everything
  /// she shares leaves Sam's phone with the beat; the pair stays.
  Future<void> _stopAll(BuildContext context) => openOnce(() async {
    final l10n = AppLocalizations.of(context)!;
    final name = l10n.syncGuideDemoPartner;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.shareStopAllConfirmTitle(name),
      content: l10n.shareStopAllConfirm(name),
      confirmText: l10n.shareStopAll,
      icon: Icons.group_off_rounded,
      confirmIdentifier: _control('stop-all-confirm'),
    );
    if (!confirmed || !context.mounted) return;
    world.stopAll();
    send(GuidePhone.there);
    settle();
  });

  /// The page's own confirmation (`SharingPage._unpair`), then the pair
  /// ends here at once and on Sam's phone with the beat. The report says
  /// what that takes from Sam's phone; the beat's landing marks its step
  /// and leaves the report standing.
  Future<void> _unpair(BuildContext context) => openOnce(() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.unpair,
      content:
          '${l10n.pairingUnpairConfirm(l10n.syncGuideDemoPartner)} '
          '${l10n.pairingRepairHint}',
      confirmText: l10n.unpair,
      isDestructive: true,
      icon: Icons.link_off_rounded,
      confirmIdentifier: _control('unpair-confirm'),
    );
    if (!confirmed || !context.mounted) return;
    world.unpair();
    send(GuidePhone.there);
    settle();
    say(_report);
  });
}
