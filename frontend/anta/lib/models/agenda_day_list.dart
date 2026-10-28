import 'package:flutter/widgets.dart' show Color, IconData;

import 'fasting_appearance.dart';

/// One dated row inside an [AgendaDayList].
///
/// Pre-resolved on purpose: the sheet that renders these reads no facade, so
/// the domain knowledge stays in the agenda layer that already holds it.
class AgendaDayListEntry {
  /// The day this row stands for, and what a tap on it returns.
  final DateTime day;

  final IconData icon;
  final Color color;

  /// What the agenda row shows for the same occurrence — the event's title,
  /// the holiday's name, the fast's own title. The date lives in the group
  /// header above the row, never in the row itself.
  final String title;
  final String? subtitle;

  /// Whether the row offers the pencil. Event rows do, so collapsing the
  /// events layer never puts editing further away than a row tap; a holiday or
  /// fasting day has nothing to open and leaves it false, which is also what
  /// keeps those rows free of an empty action strip.
  ///
  /// A flag, never a callback: the sheet hands the pencil back as an
  /// [AgendaDayListEdit] and runs nothing from the row itself, so a closure
  /// here would only keep the row's `CalendarEvent` alive behind the open
  /// sheet — and would be a second, different question from the one
  /// [eventId] already answers.
  final bool editable;

  /// Whether this occurrence was marked missed (**v26**).
  ///
  /// Resolved in the agenda layer at conversion time, exactly where the
  /// `EventPresence` read already happens, so the sheet keeps drawing what it
  /// was handed instead of learning what attendance is. Only ever true under
  /// `CalendarMissedDisplay.faded` — `hidden` drops the entry before it is
  /// built, so nothing downstream counts, marks or draws it.
  final bool missed;

  /// The event behind an event row, for a surface that opens an occurrence
  /// rather than editing it. Null for holiday and fasting rows.
  final String? eventId;

  /// Whether the entry's event takes presence marks — `EventPresence.appliesTo`,
  /// resolved beside [missed] for the same reason: a surface that offers the
  /// day panel's presence button learns which rows carry it without reading
  /// the facade itself.
  final bool presenceTracked;

  const AgendaDayListEntry({
    required this.day,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.editable = false,
    this.missed = false,
    this.eventId,
    this.presenceTracked = false,
  });
}

/// One occurrence reduced to what a year tile paints: its day, its colour and
/// whether it was missed. No title, no subtitle, no localization — a year of
/// tiles needs masks and counts, never rows, so resolving marks costs the scan
/// alone.
class AgendaDayMark {
  final DateTime day;
  final Color color;
  final bool missed;

  const AgendaDayMark({
    required this.day,
    required this.color,
    this.missed = false,
  });
}

/// Marks for an arbitrary date range under the same filters as the entry
/// resolver, with the same contract: date-only UTC, inclusive, at most
/// `EventAgenda.maxRangeDays` per call, synchronous.
typedef AgendaDayMarkResolver =
    List<AgendaDayMark> Function(DateTime start, DateTime end);

/// The first and last year a surface may page to, inclusive.
typedef AgendaYearBounds = ({int first, int last});

/// What the viewer picked out of the sheet: a day to focus, or an entry to
/// edit.
///
/// A record rather than a sealed hierarchy — the house style for small
/// multi-valued returns (`getMoneyConfig`, the day-group tuples in
/// `buildAgendaRows`) — and returned rather than acted on, so the editor opens
/// after this sheet has closed instead of stacking on it.
typedef AgendaDayListResult = ({DateTime? focusDay, AgendaDayListEdit? edit});

/// The occurrence whose pencil was tapped: the event **named**, never a copy
/// of it. The sheet freezes its rows at open, so the event behind one may
/// have been replaced — or tombstoned — by a sync reload or an alert edit by
/// the time the editor opens; the caller re-reads it then (review 2).
///
/// Returned rather than acted on, and the name travels all the way to the
/// page that owns the unfiltered events: a lookup in a view holding a
/// filtered list would open nothing for a row its filters now hide.
typedef AgendaDayListEdit = ({String eventId, DateTime day});

/// Which summary card an [AgendaDayList] came from — its identity, not its
/// contents.
///
/// Carried so the agenda layer can rebuild the *same* rows over a **wider**
/// range on demand: the sheet browses months the card never counted, and only
/// the card's own source knows which scan, with which filters, produces them.
/// The sheet never reads this itself; it hands the range to the
/// [AgendaDayListResolver] the caller built from it.
sealed class AgendaDayListSource {
  const AgendaDayListSource();
}

class AgendaDayListCategorySource extends AgendaDayListSource {
  final String categoryId;

  const AgendaDayListCategorySource(this.categoryId);
}

class AgendaDayListHolidaySource extends AgendaDayListSource {
  const AgendaDayListHolidaySource();
}

class AgendaDayListFastingSource extends AgendaDayListSource {
  final FastingTradition tradition;

  const AgendaDayListFastingSource(this.tradition);
}

/// Rows for an arbitrary date range, resolved with exactly the filters the
/// card was built under.
///
/// [start] and [end] are date-only UTC and inclusive, and a single call never
/// spans more than `EventAgenda.maxRangeDays`. Synchronous by contract: the
/// sheet resolves on navigation and caches the answer, so a month is never
/// resolved twice and never resolved while building a frame.
typedef AgendaDayListResolver =
    List<AgendaDayListEntry> Function(DateTime start, DateTime end);

/// The full contents behind a summary card, ready to render.
///
/// [title] and [subtitle] are the **card's own**, so the sheet header and the
/// card that opened it read as the same object — and the count the card claims
/// is the count of [entries] rather than a second, separately-derived number.
class AgendaDayList {
  final String title;
  final String subtitle;
  final List<AgendaDayListEntry> entries;

  /// What the card stands for, so a wider range can be resolved for it. The
  /// entries above stay the window's — this is only the identity behind them.
  final AgendaDayListSource source;

  /// The card's own tint — its category colour, the holiday amber, the fasting
  /// violet.
  ///
  /// Carried rather than read off the first entry: an event with a per-event
  /// colour override would otherwise repaint every tile, every count and the
  /// whole dot matrix in *its* colour, and a card with nothing in it would
  /// have no colour at all.
  final Color color;

  const AgendaDayList({
    required this.title,
    required this.subtitle,
    required this.entries,
    required this.source,
    required this.color,
  });
}
