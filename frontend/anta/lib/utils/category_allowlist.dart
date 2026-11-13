import '../constants/calendar_categories.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';

/// The one reader of a category allowlist — the agenda's, the overview's
/// (live and saved), a digest's and the report's (D29, §16.3 of
/// `docs/cloud-share-surfaces-roadmap.md`).
///
/// An allowlist is a set of category ids where empty admits everything.
/// Beside the ids it may hold two entries: [mineEntry], every category of
/// mine whenever made, and [partnerEntry], every category the partner shares
/// that this phone shows. A list of today's ids cannot know a category made
/// tomorrow; the entry can.
///
/// **A picker changes only the part of a list it could show.** What it did
/// not list — the partner's group where the surface or the setting lists
/// none of it, a category of theirs hidden on this phone — is carried over
/// as it stood; only an id no category holds any more is dropped at a
/// store. **A label, a count and a look are taken from the listed
/// categories that are ticked**, never from the raw set. An account that
/// never paired lists and knows nothing of a partner's, so it stores the
/// plain lists it always did.
///
/// "Listed" is this person's categories (an archived one while the list
/// holds its id) and, where the surface offers them (`partnerListed` on each
/// call), the partner's shown ones.
///
/// The entries start with `*`, which neither a built-in id (an enum name)
/// nor a custom one (a UUID) can, and hold no comma, so they ride the
/// agenda's CSV and a saved view's JSON list as one more string.
abstract final class CategoryAllowlist {
  /// Every category of mine, a category made after the pick included.
  static const String mineEntry = '*mine';

  /// Every category the partner shares that this phone shows, one shared
  /// after the pick included.
  static const String partnerEntry = '*partner';

  static bool isEntry(String id) => id == mineEntry || id == partnerEntry;

  /// Whether [event] is on the partner's side of an allowlist: theirs, and
  /// drawn under a category of their own. Every other event is on mine — my
  /// own whatever their category, and a partner's that joins a built-in of
  /// mine or draws as Other ([CalendarCategories.drawnIdOf]).
  ///
  /// While no catalogue is published a partner's event is on their side:
  /// nothing says it joins a category of mine, and unknown is never "mine".
  static bool isPartnerSide(CalendarEvent event) {
    if (!event.fromPartner) return false;
    if (CalendarCategories.all.isEmpty) return true;
    return CalendarCategories.byId(
          CalendarCategories.drawnIdOf(event.categoryId),
        )?.fromPartner ??
        false;
  }

  /// Whether [ids] lets [event] through. An event of mine meets an id by the
  /// one it stores — an archived category's, or one no category holds (the
  /// report's D32) — and a partner's by the one it draws under.
  static bool admits(CalendarEvent event, Set<String> ids) {
    if (ids.isEmpty) return true;
    if (!event.fromPartner) {
      return ids.contains(mineEntry) || ids.contains(event.categoryId);
    }
    return ids.contains(isPartnerSide(event) ? partnerEntry : mineEntry) ||
        ids.contains(CalendarCategories.drawnIdOf(event.categoryId));
  }

  /// The categories a surface lists for [ids]: mine (an archived one only
  /// while [ids] holds it), then the partner's shown ones when
  /// [partnerListed].
  static List<CalendarCategory> listed(
    Set<String> ids, {
    bool partnerListed = true,
  }) {
    final mine = CalendarCategories.visiblePlus(ids);
    final partner = _partnerOf(partnerListed);
    return partner.isEmpty ? mine : [...mine, ...partner];
  }

  static List<CalendarCategory> _partnerOf(bool partnerListed) =>
      partnerListed ? CalendarCategories.partnerShown : const [];

  /// Whether [ids] filters nothing and reads as off: empty, both entries,
  /// or [mineEntry] while no category of the partner's is listed — the pair
  /// ended, everything of theirs is hidden here, or the surface lists none
  /// of theirs. It filters again the moment one is listed.
  static bool filtersNothing(Set<String> ids, {bool partnerListed = true}) {
    if (ids.isEmpty) return true;
    if (!ids.contains(mineEntry)) return false;
    return ids.contains(partnerEntry) || _partnerOf(partnerListed).isEmpty;
  }

  /// Whether [ids] ticks [category]'s row: by its group's entry or by its id.
  /// Meaningful only while [filtersNothing] is false — a list that filters
  /// nothing ticks every row.
  static bool ticks(Set<String> ids, CalendarCategory category) =>
      ids.contains(category.id) ||
      ids.contains(category.fromPartner ? partnerEntry : mineEntry);

  /// The listed categories [ids] ticks, in list order — every one when it
  /// filters nothing. What a chip counts, a row names and a label reads.
  static List<CalendarCategory> tickedListed(
    Set<String> ids, {
    bool partnerListed = true,
  }) {
    final all = listed(ids, partnerListed: partnerListed);
    if (filtersNothing(ids, partnerListed: partnerListed)) return all;
    return [
      for (final category in all)
        if (ticks(ids, category)) category,
    ];
  }

  /// The one listed category [ids] ticks, or null — for a surface that
  /// wears a single category's name, colour or glyph. A list that filters
  /// nothing names none.
  static CalendarCategory? soleTicked(
    Set<String> ids, {
    bool partnerListed = true,
  }) {
    if (filtersNothing(ids, partnerListed: partnerListed)) return null;
    final ticked = tickedListed(ids, partnerListed: partnerListed);
    return ticked.length == 1 ? ticked.single : null;
  }

  /// What the picker opens with for a stored [ids]: every listed row when
  /// it filters nothing, an entry's listed group, an id itself. A plain list
  /// is handed over as it is — an id without a row ticks nothing.
  static Set<String> ticked(Set<String> ids, {bool partnerListed = true}) {
    final mine = CalendarCategories.visiblePlus(ids);
    final partner = _partnerOf(partnerListed);
    if (filtersNothing(ids, partnerListed: partnerListed)) {
      return {for (final c in mine) c.id, for (final c in partner) c.id};
    }
    final hasMine = ids.contains(mineEntry);
    final hasPartner = ids.contains(partnerEntry);
    if (!hasMine && !hasPartner) return ids;
    return {
      for (final id in ids)
        if (!isEntry(id)) id,
      if (hasMine)
        for (final c in mine) c.id,
      if (hasPartner)
        for (final c in partner) c.id,
    };
  }

  /// What a pick stores: the picker's answer [picked] over the list it was
  /// opened on, [previous]. The catalogue is read here, at the store, so a
  /// category created inside the picker is listed, and one left un-ticked
  /// keeps the list from collapsing to "all".
  ///
  /// With nothing of a partner's listed or known and no entry held, today's
  /// rule byte for byte: every row of mine ticked is empty, else [picked] as
  /// it came. Otherwise a whole listed group is its entry, a part of one its
  /// ticked ids, and both groups whole is empty; the partner's part of
  /// [previous] the picker did not list — their whole group (an empty list
  /// held all of it), or a category of theirs hidden here — is carried; an
  /// id no category holds is dropped. A group that lists nothing counts as
  /// whole but never writes its entry: it was not on offer.
  static Set<String> fromPicker(
    Set<String> previous,
    Set<String> picked, {
    bool partnerListed = true,
  }) {
    final mineIds = {
      for (final c in CalendarCategories.visiblePlus(previous)) c.id,
    };
    final listedPartner = {for (final c in _partnerOf(partnerListed)) c.id};
    final knownPartner = {for (final c in CalendarCategories.partner) c.id};
    if (listedPartner.isEmpty &&
        knownPartner.isEmpty &&
        !previous.any(isEntry)) {
      return picked.containsAll(mineIds) ? const <String>{} : picked;
    }

    final mineWhole = picked.containsAll(mineIds);
    final bool partnerWhole;
    final Set<String> partnerPart;
    if (listedPartner.isNotEmpty) {
      partnerWhole = picked.containsAll(listedPartner);
      partnerPart = {
        ...picked.where(listedPartner.contains),
        // Hidden here: no row, so the pick could not have changed it.
        ...previous.where(
          (id) => knownPartner.contains(id) && !listedPartner.contains(id),
        ),
      };
    } else {
      // An empty list held all of theirs — unless nothing at all is ticked
      // now, which every picker has always read as "every category" again.
      partnerWhole =
          previous.contains(partnerEntry) ||
          (previous.isEmpty && picked.any(mineIds.contains));
      partnerPart = previous.where(knownPartner.contains).toSet();
    }
    if (mineWhole && partnerWhole) return const <String>{};
    return {
      if (mineWhole && mineIds.isNotEmpty)
        mineEntry
      else
        ...picked.where(mineIds.contains),
      if (partnerWhole) partnerEntry else ...partnerPart,
    };
  }

  /// The part of [ids] the report can hold: it never counts a partner's
  /// event (D15), so their part is dropped and my entry is every category;
  /// my ids stay as they are. Applied where a list reaches the report — a
  /// digest's tap, the overview's switch — and to its own pick.
  static Set<String> forReport(Set<String> ids) {
    if (ids.contains(mineEntry)) return const <String>{};
    final knownPartner = {for (final c in CalendarCategories.partner) c.id};
    if (!ids.any((id) => isEntry(id) || knownPartner.contains(id))) {
      return ids;
    }
    return {
      for (final id in ids)
        if (!isEntry(id) && !knownPartner.contains(id)) id,
    };
  }
}
