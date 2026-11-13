import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/share_overview.dart';
import 'calendar_icons.dart';

/// Definition of a seeded built-in category.
class BuiltInCategorySeed {
  final CalendarEventCategory kind;
  final String iconKey;
  final int colorValue;

  const BuiltInCategorySeed(this.kind, this.iconKey, this.colorValue);

  /// Stable id == enum name, which matches the value already stored in
  /// `calendar_events.category` for existing events.
  String get id => kind.name;
}

/// Synchronous, in-memory facade over the persisted category set, populated
/// by `CategoryService` at startup. Mirrors the `PublicHolidays` pattern so
/// calendar render paths (`markerBuilder`, day summary, pickers) resolve a
/// category in O(1) with no `await` and no per-build allocation.
abstract final class CalendarCategories {
  /// Built-in seed catalog. Order defines the default sort order (0..N) so
  /// built-ins lead the list ahead of user-created categories. Colors mirror
  /// the historical `CalendarColors` palette; every icon key must exist in
  /// [CalendarIcons].
  static const List<BuiltInCategorySeed> builtInSeeds = [
    BuiltInCategorySeed(
      CalendarEventCategory.gym,
      'fitness_center',
      0xFF1E88E5,
    ),
    BuiltInCategorySeed(
      CalendarEventCategory.cardio,
      'directions_run',
      0xFFE53935,
    ),
    BuiltInCategorySeed(CalendarEventCategory.rest, 'bedtime', 0xFF43A047),
    BuiltInCategorySeed(
      CalendarEventCategory.holiday,
      'flight_takeoff',
      0xFFFFA000,
    ),
    BuiltInCategorySeed(
      CalendarEventCategory.competition,
      'emoji_events',
      0xFF8E24AA,
    ),
    BuiltInCategorySeed(
      CalendarEventCategory.measurement,
      'straighten',
      0xFF00897B,
    ),
    BuiltInCategorySeed(
      CalendarEventCategory.mobility,
      'self_improvement',
      0xFFEC407A,
    ),
    BuiltInCategorySeed(CalendarEventCategory.birthday, 'cake', 0xFFD81B60),
    BuiltInCategorySeed(CalendarEventCategory.other, 'event', 0xFF757575),
  ];

  static Map<String, CalendarCategory> _byId = const {};
  static List<CalendarCategory> _ordered = const [];
  static List<CalendarCategory> _visible = const [];
  static List<CalendarCategory> _partner = const [];
  static List<CalendarCategory> _partnerShown = const [];
  static Set<String> _partnerHidden = const {};
  static int _revision = 0;

  /// Bumped on every [updateCache] call. There is no reset method to mirror
  /// — `CategoryService` has no `DatabaseLifecycle` cache-drop of its own
  /// (unlike `PublicHolidays`/`FastingCalendar`), so `updateCache` is the
  /// single point that can change what a category resolves to, and the
  /// single point this counter needs to bump from. Read by
  /// `_CalendarViewState`'s per-day resolver-output memo (3.3): a recoloured
  /// or renamed category changes what `DayBarsResolver`/`CellTintResolver`
  /// paint without any event row changing, so the generation that memo keys
  /// on must see it.
  static int get revision => _revision;

  /// The last resort of [resolve]: an empty cache (the first frames, a reset
  /// service before its next load, an isolate that never loaded one) or a
  /// cache without an Other. An id that no longer resolves goes to the stored
  /// Other first, so the user's colour and icon for it are what an orphan
  /// wears. Keeps render paths total.
  static const CalendarCategory fallback = CalendarCategory(
    id: 'other',
    name: 'Other',
    colorValue: 0xFF757575,
    iconKey: 'event',
    sortOrder: 1 << 20,
    isBuiltIn: true,
  );

  /// Replaces the cache. Called by `CategoryService` after every load/mutation.
  ///
  /// Builds [visible] as a *second* list rather than filtering [all]: dropping
  /// a hidden category from the lookup would make [resolve] fall through to
  /// the stored Other and repaint every one of its events as Other, which is
  /// the exact opposite of what hiding means.
  ///
  /// A partner's category ([CalendarCategory.fromPartner]) is kept out of
  /// [visible] for the same reason it stays in the lookup: its events must
  /// draw in its name, colour and icon, but no event of this person's may
  /// take it — the database would turn that write into nothing.
  static void updateCache(List<CalendarCategory> categories) {
    final sorted = [...categories]..sort(_byOrder);
    _ordered = List.unmodifiable(sorted);
    _byId = Map.unmodifiable({for (final c in sorted) c.id: c});
    _visible = List.unmodifiable([
      for (final c in sorted)
        if (!c.isHidden && !c.fromPartner) c,
    ]);
    _partner = List.unmodifiable([
      for (final c in sorted)
        if (c.fromPartner) c,
    ]);
    _partnerShown = _shownOf(_partner, _partnerHidden);
    _anySharedByMe = sorted.any((c) => c.sharedByMe && !c.fromPartner);
    _revision++;
  }

  static bool _anySharedByMe = false;

  /// Whether one of the person's own categories is shared — taken where the
  /// catalogue is published, so a reader asking "is anything shared through
  /// a category?" walks no event list when nothing is.
  static bool get anySharedByMe => _anySharedByMe;

  /// Takes the receiver's hidden set (`shareHiddenCategories`, §6.4 of
  /// `docs/cloud-share-surfaces-roadmap.md`) — `CategoryService` with each
  /// load, `ShareService` the moment it writes one — and narrows
  /// [partnerShown] by it. [revision] stays: hiding changes which events
  /// exist (the event service drops them), never what an id resolves to.
  static void updatePartnerHidden(Set<String> ids) {
    _partnerHidden = ids;
    _partnerShown = _shownOf(_partner, ids);
  }

  static List<CalendarCategory> _shownOf(
    List<CalendarCategory> partner,
    Set<String> hidden,
  ) {
    if (hidden.isEmpty) return partner;
    return List.unmodifiable([
      for (final c in partner)
        if (!hidden.contains(c.id)) c,
    ]);
  }

  /// The person's own by their order, then a partner's by name: the reader
  /// stores a partner's at order 0, which is not a place in this person's
  /// list, and [all] is the order the report and the overview fold by — a
  /// partner's category must not move the person's own there.
  static int _byOrder(CalendarCategory a, CalendarCategory b) {
    if (a.fromPartner != b.fromPartner) return a.fromPartner ? 1 : -1;
    if (a.fromPartner) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    }
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
  }

  /// All categories in display order, hidden ones and a partner's included.
  /// Every resolution path reads this; never narrow it.
  static List<CalendarCategory> get all => _ordered;

  /// The person's own unhidden categories, in display order. The list every
  /// *choosing* surface renders — pickers, the calendar filter sheet, the
  /// agenda chips. Never a partner's ([partner]).
  static List<CalendarCategory> get visible => _visible;

  /// The categories another account shares with this one, by name — for
  /// the surfaces that list them apart, under the partner's name, and
  /// read-only. Empty for an account that never paired.
  static List<CalendarCategory> get partner => _partner;

  /// [partner] without the ones this person hid on this phone — what the
  /// Categories page's "From {name}" section and the filter lists offer: a
  /// hidden category has no events here to draw or to filter. [resolve]
  /// still knows a hidden one. A shared built-in is never in it: it is the
  /// person's own row ([visible]).
  static List<CalendarCategory> get partnerShown => _partnerShown;

  /// [visible] plus any of [keep] that is hidden, in display order. A
  /// partner's category is never added back: it is no selection of this
  /// person's to undo.
  ///
  /// The one helper behind a rule every selection-holding surface needs: an
  /// event editor must still list the category its event already carries, and
  /// a filter must still show a hidden id sitting in its own selection, or
  /// the user cannot un-select a filter they can no longer see.
  ///
  /// Returns [visible] itself when nothing hidden is kept, so the common case
  /// allocates nothing and stays identity-stable for widget memos.
  static List<CalendarCategory> visiblePlus(Iterable<String> keep) {
    if (_visible.length + _partner.length == _ordered.length) return _visible;
    final kept = keep is Set<String> ? keep : keep.toSet();
    if (kept.isEmpty) return _visible;
    final extra = [
      for (final c in _ordered)
        if (c.isHidden && !c.fromPartner && kept.contains(c.id)) c,
    ];
    if (extra.isEmpty) return _visible;
    return List.unmodifiable([
      for (final c in _ordered)
        if (!c.fromPartner && (!c.isHidden || kept.contains(c.id))) c,
    ]);
  }

  /// O(1) lookup; null when unknown.
  static CalendarCategory? byId(String id) => _byId[id];

  /// Whether [event] is one of this person's that the partner sees, and
  /// through what — the grant as the database decides it
  /// (`CalendarEventDao.sharedPairsOf`): its own mark, else its category's.
  /// The stored id, never [resolve]: an event on an id no category holds
  /// draws under Other but takes no grant from it. Null for a private event
  /// and for a partner's.
  static EventShareVia? shareOf(CalendarEvent event) {
    if (event.fromPartner) return null;
    if (event.markedShared) return EventShareVia.own;
    return (_byId[event.categoryId]?.sharedByMe ?? false)
        ? EventShareVia.category
        : null;
  }

  /// O(1) lookup that always yields a usable category.
  ///
  /// An unknown id (a sync race, a categories-only restore) resolves to the
  /// stored Other, so an orphan draws in the user's own Other colour and
  /// icon — the category whose alerts it already inherits; [fallback] only
  /// when the cache holds no Other at all.
  static CalendarCategory resolve(String id) =>
      _byId[id] ?? _byId[kFallbackCategoryId] ?? fallback;

  /// The category a brand-new event or template opens on: the first
  /// unarchived one in the user's order, so the order the user keeps is the
  /// default they get and an archived category is never handed out;
  /// [kFallbackCategoryId] when every category is archived, or while the
  /// cache is empty (a reset service until its next load).
  static String get defaultForNewEvent =>
      _visible.isEmpty ? kFallbackCategoryId : _visible.first.id;

  /// Resolves the display icon for [event]: an explicit per-event override
  /// wins, otherwise the event's category icon, otherwise a safe default.
  static IconData iconFor(CalendarEvent event) =>
      CalendarIcons.forKey(iconKeyFor(event)) ?? Icons.event_rounded;

  /// The key behind [iconFor], or null when neither the event's own key nor
  /// its category's names an icon.
  ///
  /// The key rather than the glyph for whatever has to carry the answer
  /// across a process boundary: an alert payload is armed here and drawn in
  /// a process where this facade may hold nothing at all.
  static String? iconKeyFor(CalendarEvent event) {
    final own = event.iconKey;
    if (CalendarIcons.forKey(own) != null) return own;
    final ofCategory = resolve(event.categoryId).iconKey;
    return CalendarIcons.forKey(ofCategory) != null ? ofCategory : null;
  }

  /// Localized label: built-ins resolve via their stable id; customs show
  /// their stored [CalendarCategory.name] verbatim.
  static String labelOf(CalendarCategory category, AppLocalizations l10n) {
    if (category.isBuiltIn) {
      final builtIn = _builtInById[category.id];
      if (builtIn != null) return builtInLabel(builtIn, l10n);
    }
    return category.name;
  }

  static final Map<String, CalendarEventCategory> _builtInById = {
    for (final c in CalendarEventCategory.values) c.name: c,
  };

  static String builtInLabel(CalendarEventCategory c, AppLocalizations l10n) {
    return switch (c) {
      CalendarEventCategory.gym => l10n.eventCategoryGym,
      CalendarEventCategory.cardio => l10n.eventCategoryCardio,
      CalendarEventCategory.rest => l10n.eventCategoryRest,
      CalendarEventCategory.holiday => l10n.eventCategoryHoliday,
      CalendarEventCategory.competition => l10n.eventCategoryCompetition,
      CalendarEventCategory.measurement => l10n.eventCategoryMeasurement,
      CalendarEventCategory.mobility => l10n.eventCategoryMobility,
      CalendarEventCategory.birthday => l10n.eventCategoryBirthday,
      CalendarEventCategory.other => l10n.eventCategoryOther,
    };
  }

  /// English fallback name persisted in a built-in row's `name` column. The
  /// UI never shows this directly — it uses [labelOf] — but it keeps the row
  /// self-describing in backups and raw DB inspection.
  static String builtInSeedName(CalendarEventCategory c) {
    return switch (c) {
      CalendarEventCategory.gym => 'Gym',
      CalendarEventCategory.cardio => 'Cardio',
      CalendarEventCategory.rest => 'Rest',
      CalendarEventCategory.holiday => 'Holiday',
      CalendarEventCategory.competition => 'Competition',
      CalendarEventCategory.measurement => 'Measurement',
      CalendarEventCategory.mobility => 'Mobility',
      CalendarEventCategory.birthday => 'Birthday',
      CalendarEventCategory.other => 'Other',
    };
  }
}
