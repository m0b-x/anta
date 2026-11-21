import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_colors.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_demo.dart';
import '../models/guide_book.dart';
import '../models/guide_share_world.dart';
import '../models/sync_guide_tries.dart';
import '../utils/share_copy.dart';
import 'form_menu_item.dart';
import 'form_rows.dart';
import 'guide_share_rows.dart';
import 'guide_two_phones.dart';

/// The `category` card of the sync book (`docs/guide-hub-roadmap.md` §11.4):
/// her Categories page of three, each row's ⋮ holding the page's own share
/// item, and an action row that adds an event to the shared one; Sam's day,
/// where the category's events arrive one beat after the share — and the
/// event she adds later follows with no switch of its own.
class GuideSyncCategoryDemo extends GuideTwoPhonesDemo {
  GuideSyncCategoryDemo(super.card, {DateTime Function() now = DateTime.now})
    : _now = now,
      super(book: GuideBook.sync.slug);

  final DateTime Function() _now;

  /// The category every step is about, a built-in by its stable id.
  static const String sharedCategory = 'gym';

  static const String _cardio = 'cardio';
  static const String _bookClub = '${GuideDemoCalendar.idPrefix}book-club';
  static const String _pilates = '${GuideDemoCalendar.idPrefix}pilates';
  static const String _bookClubEvent =
      '${GuideDemoCalendar.idPrefix}book-club-event';
  static const String _added = '${GuideDemoCalendar.idPrefix}yoga';

  /// The control name of a row on [phone]: its id without the demo prefix,
  /// under the phone it stands on.
  static String rowControl(GuidePhone phone, String id) =>
      '${phone.name}-${id.replaceFirst(GuideDemoCalendar.idPrefix, '')}';

  /// The control name of a category row's ⋮.
  static String menuControl(String categoryId) =>
      'more-${categoryId.replaceFirst(GuideDemoCalendar.idPrefix, '')}';

  String _control(String name) =>
      SemanticsIds.guideBookTryControl(book, slug, name);

  /// Two of the app's built-ins and one of hers, the first the one she
  /// shares; one event of the shared category and one of hers, so Sam's day
  /// holds something the moment the share lands.
  @override
  GuideShareWorld seedWorld(AppLocalizations l10n) {
    final now = _now();
    final day = DateTime.utc(now.year, now.month, now.day);
    CalendarCategory builtIn(String id, int order) {
      final seed = CalendarCategories.builtInSeeds.firstWhere(
        (seed) => seed.id == id,
      );
      return CalendarCategory(
        id: seed.id,
        name: CalendarCategories.builtInSeedName(seed.kind),
        colorValue: seed.colorValue,
        iconKey: seed.iconKey,
        sortOrder: order,
        isBuiltIn: true,
      );
    }

    final builtIns = [builtIn(sharedCategory, 0), builtIn(_cardio, 1)];
    return GuideShareWorld(
      day: day,
      categories: [
        ...builtIns,
        CalendarCategory(
          id: _bookClub,
          name: l10n.calendarGuideDemoEventBookClub,
          colorValue: CalendarColors.swatchPalette.firstWhere(
            (color) => builtIns.every((c) => c.colorValue != color),
          ),
          iconKey: 'menu_book',
          sortOrder: 2,
          isBuiltIn: false,
        ),
      ],
      events: [
        CalendarEvent(
          id: _pilates,
          title: l10n.calendarGuideDemoEventPilates,
          categoryId: sharedCategory,
          startDate: day,
          time: const EventTime(startMinute: 7 * 60 + 30, durationMinutes: 60),
        ),
        CalendarEvent(
          id: _bookClubEvent,
          title: l10n.calendarGuideDemoEventBookClub,
          categoryId: _bookClub,
          startDate: day,
          time: const EventTime(startMinute: 19 * 60, durationMinutes: 90),
        ),
      ],
    );
  }

  /// The one event the action row adds: later in the day, in the shared
  /// category.
  CalendarEvent _addedEvent(AppLocalizations l10n) => CalendarEvent(
    id: _added,
    title: l10n.calendarGuideDemoEventYoga,
    categoryId: sharedCategory,
    startDate: world.day,
    time: const EventTime(startMinute: 18 * 60, durationMinutes: 60),
  );

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
          area: l10n.calendarCategories,
          list: _categories(context, l10n, live: true),
          template: _categories(context, l10n, live: false),
          control: FormRowGroup(
            trailingGap: false,
            children: [
              FormActionRow(
                glyph: Icons.add_rounded,
                label: l10n.syncGuideAddEventTo(
                  SyncGuideTries.categoryName(l10n),
                ),
                identifier: _control('add'),
                // One event shows the lesson; the row stays, disabled.
                onTap: world.addedAny ? null : () => _add(l10n),
              ),
            ],
          ),
        );
      case GuidePhone.there:
        final theirs = world.theirs;
        return GuidePhoneView(
          mark: GuideShareLooks.samMark(l10n),
          area: l10n.calendar,
          list: theirs.isEmpty ? null : _day(context, l10n, theirs, live: true),
          // At its tallest Sam's day holds the shared category's events and
          // the one she adds to it.
          template: _day(context, l10n, [
            for (final event in world.events)
              if (event.categoryId == sharedCategory && event.id != _added)
                GuideShareWorld.asTheirs(event),
            GuideShareWorld.asTheirs(_addedEvent(l10n)),
          ], live: false),
          empty: l10n.syncGuideEmptyFromYou,
        );
    }
  }

  /// Her Categories page: each row's caption as the page writes it, its
  /// avatar wearing the share sign while shared. The template counts every
  /// category shared and the added event filed, its longest captions, and
  /// every row keeps its longest caption's room from the first frame.
  Widget _categories(
    BuildContext context,
    AppLocalizations l10n, {
    required bool live,
  }) {
    final partner = l10n.syncGuideDemoPartner;
    Widget row(CalendarCategory category) {
      final shared = !live || world.isCategoryShared(category.id);
      final count = world.eventCountOf(category.id);
      // The added event filed, which the template and the reserve count.
      final most =
          count + (category.id == sharedCategory && !world.addedAny ? 1 : 0);
      String caption(int count, {required bool shared, required bool spoken}) =>
          ShareCopy.caption([
            l10n.categoryEventCount(count),
            if (category.isBuiltIn) l10n.categoryCaptionBuiltIn,
            if (shared)
              spoken
                  ? l10n.sharedWithPartner(partner)
                  : l10n.categoryCaptionShared,
          ]);
      final shown = live ? count : most;
      return GuideShareCategoryRow(
        category: category,
        caption: caption(shown, shared: shared, spoken: false),
        spokenCaption: caption(shown, shared: shared, spoken: true),
        captionReserve: caption(most, shared: true, spoken: false),
        shared: shared,
        identifier: live
            ? _control(rowControl(GuidePhone.here, category.id))
            : null,
        // The template keeps the ⋮'s room, so the caption wraps as it will.
        onMenu: live
            ? (anchor) => _openMenu(context, anchor, category)
            : (_) {},
        menuIdentifier: live ? _control(menuControl(category.id)) : null,
      );
    }

    return FormRowGroup(
      trailingGap: false,
      children: [for (final category in world.categories) row(category)],
    );
  }

  /// Sam's day: what arrived from her, as a partner's events are drawn.
  Widget _day(
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
      ),
    );
  }

  /// The Categories page's row menu down to its one share item
  /// (`CalendarCategoriesPage._openRowMenu`): "Share with Sam", or
  /// "Shared with Sam" ticked — a second pick takes the share back.
  Future<void> _openMenu(
    BuildContext context,
    BuildContext anchor,
    CalendarCategory category,
  ) => openOnce(() async {
    final l10n = AppLocalizations.of(context)!;
    final partner = l10n.syncGuideDemoPartner;
    final shared = world.isCategoryShared(category.id);
    final picked = await showFormMenu<bool>(
      anchor,
      items: [
        FormMenuItem(
          value: true,
          label: shared
              ? l10n.sharedWithPartner(partner)
              : l10n.shareWithPartner(partner),
          icon: Icons.group_rounded,
          identifier: _control('share'),
        ),
      ],
      selected: shared ? true : null,
      menuWidth: FormMetrics.menuWidth,
    );
    if (picked == null || !context.mounted) return;
    world.shareCategory(category.id, !shared);
    send(GuidePhone.there);
    settle();
  });

  void _add(AppLocalizations l10n) {
    world.addEvent(_addedEvent(l10n));
    send(GuidePhone.there);
    settle();
  }
}
