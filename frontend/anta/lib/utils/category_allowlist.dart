import '../constants/calendar_categories.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/event_digest.dart';

/// What a category picker showed when it opened: the rows it `listed` and
/// the ones `ticked` ([CategoryAllowlist.opening]).
typedef PickerOpening = ({Set<String> ticked, Set<String> listed});

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
  ///
  /// While no category is known at all — before the first load, the moment
  /// after a database switch — nothing is claimed: a list that holds
  /// anything reads as in force, as [admits] treats it.
  static bool filtersNothing(Set<String> ids, {bool partnerListed = true}) {
    if (ids.isEmpty) return true;
    if (CalendarCategories.all.isEmpty) return false;
    if (!ids.contains(mineEntry)) return false;
    return ids.contains(partnerEntry) || _partnerOf(partnerListed).isEmpty;
  }

  /// How many listed categories [ids] ticks — [tickedListed]'s length — or
  /// null while no category is known and [ids] holds an entry, when no
  /// count is true; a plain list is then counted by its own ids. A chip or a
  /// label reads null as "Categories", never as "No categories".
  static int? tickedCount(Set<String> ids, {bool partnerListed = true}) {
    if (CalendarCategories.all.isNotEmpty) {
      return tickedListed(ids, partnerListed: partnerListed).length;
    }
    return ids.any(isEntry) ? null : ids.length;
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

  /// What a picker over [ids] opens with, taken by the sheet before it
  /// shows the picker and handed back to [fromPicker] with the answer: the
  /// catalogue can change while a picker is open, and what the person
  /// changed is judged against what they were shown.
  static PickerOpening opening(Set<String> ids, {bool partnerListed = true}) =>
      (
        ticked: ticked(ids, partnerListed: partnerListed),
        listed: {
          for (final c in listed(ids, partnerListed: partnerListed)) c.id,
        },
      );

  /// What a pick stores: the picker's answer [picked] over the list it was
  /// opened on, [previous]. [opening] is what the picker showed when it
  /// opened ([CategoryAllowlist.opening]); left out, it is worked out here,
  /// from the catalogue as it stands now.
  ///
  /// Four answers come before any deriving:
  ///
  /// 1. **A pick CHANGED into one that ticks none of the listed rows** —
  ///    "Select none", or the last row un-ticked — is every category, `{}`,
  ///    as an empty pick has always been, for an account that never paired
  ///    too. A carried part, or an id no category holds (the picker hands
  ///    back what it has no row for), never turns "I ticked nothing" into a
  ///    filter of its own, one that would show nothing.
  /// 2. **With nothing of a partner's listed or known and no entry held**,
  ///    the rule from before sharing, byte for byte: every row of mine
  ///    ticked is empty, else [picked] as it came — an untouched Done
  ///    included, so this comes before the next.
  /// 3. **A Done nobody touched, with no row that was not there when the
  ///    picker opened, is no store**: [previous] comes back as it is — a
  ///    list is never widened, narrowed or rewritten by a look.
  /// 4. **A pick changed into every row on offer** is every category, `{}`:
  ///    "Select all" means all — also while a category of theirs is hidden
  ///    here, and where none of theirs is on offer at all. This is the one
  ///    place a part of theirs the picker could not show is not carried.
  ///
  /// Otherwise my group is read from the answer as it came — whole, it is
  /// its entry; else its ticked ids, so a category made inside the picker
  /// and left un-ticked stays out, which is why the catalogue is read at
  /// the store. Their group is different, because only they can add to it:
  /// **while no row of theirs was changed their part stays what the list
  /// held** — the whole group where it held the whole group (an empty list
  /// held all of it), the same ids otherwise — so a category of theirs that
  /// arrives while the picker is open is not left out by a pick nobody
  /// made, and one left out and hidden since is not taken in by ticking the
  /// rows beside it. Once a row of theirs is changed, every row of theirs
  /// on offer ticked is their entry, and a part is its ticked ids beside
  /// the hidden ones the list held. An id no category holds is dropped. A
  /// group that lists nothing never writes its entry: it was not on offer.
  static Set<String> fromPicker(
    Set<String> previous,
    Set<String> picked, {
    PickerOpening? opening,
    bool partnerListed = true,
  }) {
    final was =
        opening ??
        CategoryAllowlist.opening(previous, partnerListed: partnerListed);
    final untouched =
        picked.length == was.ticked.length && picked.containsAll(was.ticked);
    final mineIds = {
      for (final c in CalendarCategories.visiblePlus(previous)) c.id,
    };
    final listedPartner = {for (final c in _partnerOf(partnerListed)) c.id};
    final knownPartner = {for (final c in CalendarCategories.partner) c.id};
    final ticksNone = !picked.any(
      (id) => mineIds.contains(id) || listedPartner.contains(id),
    );
    if (ticksNone && !untouched) return const <String>{};
    if (listedPartner.isEmpty &&
        knownPartner.isEmpty &&
        !previous.any(isEntry)) {
      return picked.containsAll(mineIds) ? const <String>{} : picked;
    }
    final rowAdded =
        mineIds.any((id) => !was.listed.contains(id)) ||
        listedPartner.any((id) => !was.listed.contains(id));
    if (untouched && !rowAdded) return previous;

    final mineWhole = picked.containsAll(mineIds);
    final everyRow = mineWhole && picked.containsAll(listedPartner);
    if (!untouched && everyRow) return const <String>{};
    final theirsListedWhole =
        listedPartner.isNotEmpty && picked.containsAll(listedPartner);

    // An empty list held all of theirs, the hidden ones included.
    final heldWhole = previous.isEmpty || previous.contains(partnerEntry);
    final theirsBefore = was.ticked.where(knownPartner.contains).toSet();
    final theirsNow = picked.where(knownPartner.contains).toSet();
    final theirsTouched =
        listedPartner.isNotEmpty &&
        (theirsNow.length != theirsBefore.length ||
            !theirsNow.containsAll(theirsBefore));
    final bool partnerWhole;
    final Set<String> partnerPart;
    if (theirsTouched) {
      partnerWhole = theirsListedWhole;
      partnerPart = {
        ...picked.where(listedPartner.contains),
        // Hidden here: no row, so the pick could not have changed it.
        ...previous.where(
          (id) => knownPartner.contains(id) && !listedPartner.contains(id),
        ),
      };
    } else {
      partnerWhole = heldWhole;
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

  /// The list a digest of [cadence] counts by: a report's own part alone
  /// ([forReport]), else [ids] as stored. A report digest's stored list can
  /// still hold the partner's part — written on my other device, or left
  /// from before a switch to a report — so every reader of a digest's list
  /// takes it from here: the planner's scan, the report's fold, the words
  /// and the editor's store. Read raw, such a digest armed nothing or
  /// counted nothing.
  static Set<String> forDigest(DigestCadence cadence, Set<String> ids) =>
      cadence.isReport ? forReport(ids) : ids;
}
