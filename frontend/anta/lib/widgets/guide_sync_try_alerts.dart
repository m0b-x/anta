import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/semantics_ids.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_demo.dart';
import '../models/event_alert.dart';
import '../models/guide_book.dart';
import '../models/guide_share_world.dart';
import '../models/partner_look.dart';
import '../models/share_settings.dart';
import '../models/sync_guide_tries.dart';
import '../services/event_time_formatter.dart';
import '../utils/settings_search.dart';
import 'form_rows.dart';
import 'guide_share_rows.dart';
import 'guide_two_phones.dart';
import 'settings_section_list.dart';
import 'share_settings_sections.dart';

/// The `alerts` card of the sync book (`docs/guide-hub-roadmap.md` §11.4):
/// her phone alone — one event of Sam's in a category of hers, an alert of
/// her own on it and an alarm on the category — over the Sharing page's
/// own "Alerts for shared events" row ([shareAlertsSection]) and its menu.
/// A line under the event says what would ring, read off the app's own
/// rule ([ShareAlerts.inheritsOn]) through the world, never retyped.
///
/// Nothing travels, so nothing is sent; nothing is armed either — the line
/// is all a choice changes.
class GuideSyncAlertsDemo extends GuideTwoPhonesDemo {
  GuideSyncAlertsDemo(super.card, {DateTime Function() now = DateTime.now})
    : _now = now,
      super(book: GuideBook.sync.slug);

  final DateTime Function() _now;

  static const String _flight = '${GuideDemoCalendar.idPrefix}flight';
  static const String _travel = '${GuideDemoCalendar.idPrefix}travel';

  /// The category's look: a holiday's colour, the flight's glyph.
  static const String _travelIcon = 'flight_takeoff';

  /// What the caption names: the alert she added to the flight and the
  /// alarm Travel hands down — drawn only, never armed.
  static const EventAlert _ownAlert = EventAlert(
    id: '${GuideDemoCalendar.idPrefix}flight-own',
    eventId: _flight,
    offsetMinutes: 30,
  );
  static const EventAlert _travelAlarm = EventAlert(
    id: '${GuideDemoCalendar.idPrefix}travel-alarm',
    eventId: _flight,
    mode: AlertMode.ring,
    offsetMinutes: 3 * 60,
    categoryId: _travel,
  );

  String _control(String name) =>
      SemanticsIds.guideBookTryControl(book, slug, name);

  /// A card about her phone alone: what rings is this phone's choice.
  @override
  bool get onePhone => true;

  /// Sam's flight at 14:30 in her Travel, her own alert on it, an alarm on
  /// Travel, and the choice a fresh install makes.
  @override
  GuideShareWorld seedWorld(AppLocalizations l10n) {
    final now = _now();
    final day = DateTime.utc(now.year, now.month, now.day);
    final colorValue = CalendarCategories.builtInSeeds
        .firstWhere((seed) => seed.id == CalendarEventCategory.holiday.name)
        .colorValue;
    return GuideShareWorld(
      day: day,
      events: const [],
      categories: [
        CalendarCategory(
          id: _travel,
          name: l10n.syncGuideDemoCategoryTravel,
          colorValue: colorValue,
          iconKey: _travelIcon,
          sortOrder: 0,
          isBuiltIn: false,
        ),
      ],
      partnerEvents: [
        // Drawn in Travel's look by its own colour: the stage registers no
        // category with the app.
        CalendarEvent(
          id: _flight,
          title: l10n.calendarGuideDemoEventFlight,
          categoryId: _travel,
          iconKey: _travelIcon,
          colorValue: colorValue,
          tintIcon: true,
          startDate: day,
          time: const EventTime(startMinute: 14 * 60 + 30),
        ),
      ],
      shareAlerts: ShareAlerts.fromName(SettingsKeys.defaultShareAlerts),
      ownAlerts: {_flight},
      alarmedCategories: {_travel},
    );
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
      list: _flightAndLine(context, l10n, live: true),
      // The line's slot is sized for all three sentences: its own tallest.
      template: _flightAndLine(context, l10n, live: false),
      control: _alertsRow(context, l10n),
    );
  }

  /// What would ring for the flight under the choice as it stands. Her own
  /// alert is always on it, so the category's alarm never rings alone.
  String _rings(AppLocalizations l10n) {
    final rings = world.ringsFor(world.partnerEvents.single);
    if (rings.categoryAlarm) {
      return l10n.syncGuideRingsBoth(world.categories.single.name);
    }
    return rings.own ? l10n.syncGuideRingsOwn : l10n.syncGuideRingsNothing;
  }

  /// Whose the flight is and the two alerts on it, named as the app names
  /// them: the read sheet's "From {name}" and the alert formatter's timing.
  String _facts(BuildContext context, AppLocalizations l10n) {
    final flight = world.partnerEvents.single;
    String timing(EventAlert alert) => alert.describe(
      l10n,
      flight,
      formatMinute: (minute) =>
          EventTimeFormatter.formatMinute(minute, context),
    );
    return l10n.syncGuideTryAlertsFlightCaption(
      l10n.shareFromPartner(l10n.syncGuideDemoPartner),
      timing(_ownAlert),
      world.categories.single.name,
      timing(_travelAlarm),
    );
  }

  /// Sam's flight as her day list draws a partner's event; under it what
  /// stands on it, which no choice changes, then the line in a slot as tall
  /// as its longest sentence, so a choice moves nothing.
  Widget _flightAndLine(
    BuildContext context,
    AppLocalizations l10n, {
    required bool live,
  }) {
    FormCaption caption(String text) =>
        FormCaption(text: text, padding: FormMetrics.groupCaptionPadding);
    final line = caption(_rings(l10n));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormRowGroup(
          trailingGap: false,
          children: guideShareDayRows(
            context,
            day: world.day,
            events: world.partnerEvents,
            look: PartnerLook(
              look: world.look.eventLook,
              partner: GuideShareLooks.sam(l10n),
              name: l10n.syncGuideDemoPartner,
            ),
            identifier: live ? (_) => _control('row-flight') : null,
          ),
        ),
        caption(_facts(context, l10n)),
        FormCaptionSlot(
          candidates: [
            caption(l10n.syncGuideRingsNothing),
            caption(l10n.syncGuideRingsOwn),
            caption(l10n.syncGuideRingsBoth(world.categories.single.name)),
          ],
          // No live region of its own: the coach line's announces the step
          // the choice completed (§11.8 D's rule for the stage's marks).
          child: live
              ? Semantics(identifier: _control('rings'), child: line)
              : line,
        ),
      ],
    );
  }

  /// The Sharing page's own alerts section in the settings kit; its row
  /// opens the page's own menu, and the choice is written to the world as
  /// the page writes it to the bloc. Laid out unseen with every choice, as
  /// the line is: German's "own" takes two lines at 2.0 where "Off" takes
  /// one, and the stage would change height with the choice (D55).
  Widget _alertsRow(BuildContext context, AppLocalizations l10n) {
    Widget section(ShareAlerts alerts, {bool live = false}) =>
        SettingsSectionList(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          query: SettingsQuery.empty,
          sections: [
            shareAlertsSection(
              l10n,
              alerts: alerts,
              onPick: live ? _pick : (_, _) {},
              identifier: _control,
            ),
          ],
        );
    return FormCaptionSlot(
      candidates: [for (final value in ShareAlerts.values) section(value)],
      child: section(world.shareAlerts, live: true),
    );
  }

  /// The menu at the row, as the page opens it; the same choice again
  /// changes nothing, as on the page.
  void _pick(BuildContext anchor, ShareAlerts current) => openOnce(() async {
    final l10n = AppLocalizations.of(anchor)!;
    final next = await showShareAlertsMenu(
      anchor,
      l10n,
      current,
      identifier: _control,
    );
    if (next == null || next == current) return;
    world.setShareAlerts(next);
    settle();
  });
}
