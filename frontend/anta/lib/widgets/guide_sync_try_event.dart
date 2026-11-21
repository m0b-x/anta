import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_demo.dart';
import '../models/guide_book.dart';
import '../models/guide_share_world.dart';
import '../models/sync_guide_tries.dart';
import '../services/day_summary_resolver.dart';
import 'event_avatar.dart';
import 'event_share_row.dart';
import 'form_rows.dart';
import 'guide_share_rows.dart';
import 'guide_two_phones.dart';
import 'shared_event_sheet.dart';

/// The `event` card of the sync book (`docs/guide-hub-roadmap.md` §11.4):
/// her day of two events with the event editor's own pair under it — the
/// selected event's title over its share row — and Sam's day, where what
/// she shares arrives one beat later, drawn as a partner's events are drawn
/// and opened in the real read sheet.
///
/// Nothing leaves the page: the switch writes the demo's world, the read
/// sheet's copy makes a report, and the sheet offers no alert editor and no
/// note (D56).
class GuideSyncEventDemo extends GuideTwoPhonesDemo {
  GuideSyncEventDemo(super.card, {DateTime Function() now = DateTime.now})
    : _now = now,
      super(book: GuideBook.sync.slug);

  final DateTime Function() _now;

  /// Her selected event, whose pair stands under the list.
  String _selected = _dentist;

  static const String _dentist = '${GuideDemoCalendar.idPrefix}dentist';
  static const String _yoga = '${GuideDemoCalendar.idPrefix}yoga';

  /// The control name of [eventId]'s row on [phone]: its id without the
  /// demo prefix, under the phone it stands on.
  static String rowControl(GuidePhone phone, String eventId) =>
      '${phone.name}-${eventId.replaceFirst(GuideDemoCalendar.idPrefix, '')}';

  String _control(String name) =>
      SemanticsIds.guideBookTryControl(book, slug, name);

  static String _report(AppLocalizations l10n) =>
      l10n.syncGuideReportEventCopy(l10n.syncGuideDemoPartner);

  @override
  List<String> reports(AppLocalizations l10n) => [_report(l10n)];

  /// What the open read sheet follows on Sam's phone, while one is open.
  StreamController<CalendarEvent?>? _theirChanges;

  /// Two events of today in two categories' looks — the calendar guide's
  /// demo titles — so the one she shares is told from the other.
  @override
  GuideShareWorld seedWorld(AppLocalizations l10n) {
    final now = _now();
    final day = DateTime.utc(now.year, now.month, now.day);
    return GuideShareWorld(
      day: day,
      events: [
        CalendarEvent(
          id: _dentist,
          title: l10n.calendarGuideDemoEventDentist,
          categoryId: CalendarCategories.fallback.id,
          iconKey: 'medical_services',
          startDate: day,
          time: const EventTime(startMinute: 9 * 60, durationMinutes: 45),
        ),
        CalendarEvent(
          id: _yoga,
          title: l10n.calendarGuideDemoEventYoga,
          categoryId: CalendarEventCategory.mobility.name,
          startDate: day,
          time: const EventTime(startMinute: 18 * 60, durationMinutes: 60),
        ),
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
          area: l10n.calendar,
          list: _hers(context, l10n, live: true),
          template: _hers(context, l10n, live: false),
          control: FormRowGroup(
            trailingGap: false,
            children: [_titleRow(context, l10n), _shareRow(l10n)],
          ),
        );
      case GuidePhone.there:
        final theirs = world.theirs;
        return GuidePhoneView(
          mark: GuideShareLooks.samMark(l10n),
          area: l10n.calendar,
          list: theirs.isEmpty
              ? null
              : _theirs(context, l10n, theirs, live: true),
          // At its tallest Sam's day holds every event she could share.
          template: _theirs(context, l10n, [
            for (final event in world.events) GuideShareWorld.asTheirs(event),
          ], live: false),
          empty: l10n.syncGuideEmptyFromYou,
        );
    }
  }

  /// Her day: the selected event on the selected-row wash, every event she
  /// shares wearing the share sign, as her real day list draws it.
  Widget _hers(
    BuildContext context,
    AppLocalizations l10n, {
    required bool live,
  }) {
    return FormRowGroup(
      trailingGap: false,
      children: guideShareDayRows(
        context,
        day: world.day,
        events: world.events,
        look: GuideShareLooks.toSam(l10n),
        sharedByMe: {
          for (final event in world.events)
            if (world.isShared(event.id)) event.id,
        },
        identifier: live
            ? (id) => _control(rowControl(GuidePhone.here, id))
            : null,
        onTap: live ? _select : null,
        selected: _selected,
      ),
    );
  }

  /// Sam's day: her shared events as a partner's are drawn on a real phone
  /// — the default look, read as from her ("you", D45).
  Widget _theirs(
    BuildContext context,
    AppLocalizations l10n,
    List<CalendarEvent> events, {
    required bool live,
  }) {
    return FormRowGroup(
      trailingGap: false,
      children: guideShareDayRows(
        context,
        day: world.day,
        events: events,
        look: GuideShareLooks.fromYou(l10n),
        identifier: live
            ? (id) => _control(rowControl(GuidePhone.there, id))
            : null,
        onTap: live
            ? (id) =>
                  _open(context, events.firstWhere((event) => event.id == id))
            : null,
      ),
    );
  }

  /// The editor's title row, read-only, naming the event the share row
  /// under it belongs to. Every event's title is laid out unseen beneath
  /// the selected one's, so picking another never changes the phone's
  /// height.
  Widget _titleRow(BuildContext context, AppLocalizations l10n) {
    final summaries = EventSummaryProvider(l10n, showRecurrence: false);
    FormReadTitleRow rowOf(CalendarEvent event) {
      final summary = summaries.entryFor(event, world.day);
      return FormReadTitleRow(
        leading: EventAvatar(icon: summary.icon, color: summary.color),
        title: summary.title,
      );
    }

    final selected = rowOf(
      world.events.firstWhere((event) => event.id == _selected),
    );
    return FormIndentedRow(
      dividerIndent: selected.dividerIndent,
      child: Stack(
        children: [
          for (final event in world.events)
            if (event.id != _selected)
              ExcludeSemantics(
                child: Visibility(
                  visible: false,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: rowOf(event),
                ),
              ),
          selected,
        ],
      ),
    );
  }

  /// The event editor's own share row, as a paired phone shows it; its
  /// slot reserves only the two readings this card shows.
  Widget _shareRow(AppLocalizations l10n) {
    return EventShareRow(
      partnerName: l10n.syncGuideDemoPartner,
      ready: true,
      value: world.isShared(_selected),
      reserve: const [EventShareReading.off, EventShareReading.on],
      identifier: _control('share'),
      onChanged: (value) {
        world.share(_selected, value);
        send(GuidePhone.there);
        settle();
      },
    );
  }

  void _select(String eventId) {
    if (eventId == _selected) return;
    _selected = eventId;
    changed();
  }

  /// A landing that takes the event Sam has open off Sam's phone closes
  /// its read sheet, as the real sheet closes when its event leaves.
  @override
  void land() {
    super.land();
    final open = world.theirOpen;
    if (open != null && world.theirs.every((event) => event.id != open)) {
      _theirChanges?.add(null);
    }
  }

  /// Sam opens [event] in the app's read sheet. Its copy is made in memory
  /// and only reported; the sheet offers no alerts and no note (D56).
  Future<void> _open(BuildContext context, CalendarEvent event) => openOnce(
    () async {
      final l10n = AppLocalizations.of(context)!;
      world.openTheirs(event.id);
      settle();
      final changes = _theirChanges = StreamController<CalendarEvent?>();
      try {
        final exit = await SharedEventSheet.show(
          context,
          event: event,
          day: world.day,
          partner: GuideShareLooks.fromYou(l10n),
          changes: changes.stream,
          onCopy: () async => CalendarEvent(
            id: '${event.id}-copy',
            title: event.title,
            categoryId: event.categoryId,
            startDate: event.startDate,
            time: event.time,
            iconKey: event.iconKey,
          ),
          ownAlerts: false,
          caption: l10n.syncGuideSharedEventCaption(l10n.syncGuideDemoPartner),
        );
        world.closeTheirs();
        switch (exit) {
          case SharedEventCopied():
            say(_report);
          // The landing closed it: no act of hers.
          case SharedEventGone():
            redraw();
          default:
            changed();
        }
      } finally {
        _theirChanges = null;
        unawaited(changes.close());
      }
    },
  );
}
