import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/semantics_ids.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_demo.dart';
import '../models/guide_book.dart';
import '../models/guide_share_world.dart';
import '../models/partner_look.dart';
import '../models/share_settings.dart';
import '../models/sync_guide_tries.dart';
import '../utils/settings_search.dart';
import 'form_rows.dart';
import 'guide_share_rows.dart';
import 'guide_two_phones.dart';
import 'settings_section_list.dart';
import 'share_settings_sections.dart';

/// The `look` card of the sync book (`docs/guide-hub-roadmap.md` §11.4):
/// her phone alone — one day holding her Dentist, shared with Sam, and one
/// of Sam's events — the two that show both effects — over the Sharing
/// page's own "How shared things look" rows ([shareLookSection]). A choice
/// redraws the day as her real calendar would: Sam's events outlined,
/// wearing Sam's face, or like hers; her shared event with or without its
/// sign.
///
/// The section's "Notes shared with you" row is left off: the stage holds
/// no notes, so it would change nothing she can see (design review,
/// finding 10); the page's rows tell it.
///
/// Nothing travels, so nothing is sent: the looks are this phone's own.
class GuideSyncLookDemo extends GuideTwoPhonesDemo {
  GuideSyncLookDemo(super.card, {DateTime Function() now = DateTime.now})
    : _now = now,
      super(book: GuideBook.sync.slug);

  final DateTime Function() _now;

  static const String _dentist = '${GuideDemoCalendar.idPrefix}dentist';
  static const String _lunch = '${GuideDemoCalendar.idPrefix}lunch';

  /// The control name of [eventId]'s row: its id without the demo prefix.
  static String rowControl(String eventId) =>
      'row-${eventId.replaceFirst(GuideDemoCalendar.idPrefix, '')}';

  String _control(String name) =>
      SemanticsIds.guideBookTryControl(book, slug, name);

  /// A card about her phone alone: the looks are hers, and Sam's phone has
  /// nothing to show for them.
  @override
  bool get onePhone => true;

  /// The looks a fresh install draws by — except the sign on what she
  /// shares, which ships on and starts off here, so turning it on is the
  /// lesson rather than a switch flicked off and back.
  ///
  /// Her Dentist comes after Sam's lunch, so the day's last row — the one
  /// "Mark what you share" changes — stands next to the section: at German
  /// 2.0 on a small phone the switch and that row share one screen.
  @override
  GuideShareWorld seedWorld(AppLocalizations l10n) {
    final now = _now();
    final day = DateTime.utc(now.year, now.month, now.day);
    CalendarEvent event(
      String id,
      String title,
      String categoryId,
      int startMinute, {
      String? iconKey,
    }) => CalendarEvent(
      id: id,
      title: title,
      categoryId: categoryId,
      iconKey: iconKey,
      startDate: day,
      time: EventTime(startMinute: startMinute, durationMinutes: 60),
    );
    return GuideShareWorld(
        day: day,
        events: [
          event(
            _dentist,
            l10n.calendarGuideDemoEventDentist,
            CalendarCategories.fallback.id,
            15 * 60,
            iconKey: 'medical_services',
          ),
        ],
        partnerEvents: [
          event(
            _lunch,
            l10n.calendarGuideDemoEventLunch,
            CalendarEventCategory.cardio.name,
            12 * 60 + 30,
            iconKey: 'restaurant',
          ),
        ],
        look: ShareLook(
          eventLook: ShareEventLook.fromName(
            SettingsKeys.defaultShareEventLook,
          ),
          noteLook: ShareNoteLook.fromName(SettingsKeys.defaultShareNoteLook),
          markMine: false,
        ),
      )
      ..share(_dentist, true)
      ..deliver();
  }

  @override
  String phoneLabel(AppLocalizations l10n, GuidePhone phone) =>
      l10n.syncGuidePhoneYours;

  @override
  GuidePhoneView buildPhone(BuildContext context, GuidePhone phone) {
    final l10n = AppLocalizations.of(context)!;
    return GuidePhoneView(
      mark: GuideShareLooks.herMark(context),
      area: l10n.calendar,
      list: _day(context, l10n, live: true),
      // A look changes a row's avatar inside its fixed box, never its
      // height: the day is its own tallest state.
      template: _day(context, l10n, live: false),
      control: _looks(l10n),
    );
  }

  /// Her day — her events and Sam's in time order — read through the looks
  /// as they stand, the face on Sam's rows Sam's own.
  Widget _day(
    BuildContext context,
    AppLocalizations l10n, {
    required bool live,
  }) {
    final look = world.look;
    final events = [...world.events, ...world.partnerEvents]
      ..sort((a, b) => a.time!.startMinute.compareTo(b.time!.startMinute));
    return FormRowGroup(
      trailingGap: false,
      children: guideShareDayRows(
        context,
        day: world.day,
        events: events,
        look: PartnerLook(
          look: look.eventLook,
          noteLook: look.noteLook,
          partner: GuideShareLooks.sam(l10n),
          name: l10n.syncGuideDemoPartner,
          markMine: look.markMine,
        ),
        sharedByMe: {
          for (final event in world.events)
            if (world.isShared(event.id)) event.id,
        },
        identifier: live ? (id) => _control(rowControl(id)) : null,
      ),
    );
  }

  /// The Sharing page's own section, in the settings kit, each choice
  /// written to the world at once as the page writes it to the bloc — but
  /// for the notes' row, which a stage without notes leaves out: a row of
  /// the real section may be left off, never redrawn.
  Widget _looks(AppLocalizations l10n) {
    final section = shareLookSection(
      l10n,
      look: world.look,
      onEventLook: (value) {
        world.setEventLook(value);
        settle();
      },
      onNoteLook: (_) {},
      onMarkMine: (value) {
        world.setMarkMine(value);
        settle();
      },
      identifier: _control,
    );
    return SettingsSectionList(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      query: SettingsQuery.empty,
      sections: [
        SettingsSectionData(
          icon: section.icon,
          title: section.title,
          entries: [
            for (final entry in section.entries)
              if (entry.identifier != _control('notes')) entry,
          ],
        ),
      ],
    );
  }
}
