import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/event_priorities.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/calendar_grid_filters.dart';
import '../models/upcoming_agenda_filters.dart';

/// One active filter axis, named once for every surface that has to say what
/// the calendar is currently narrowed to.
class CalendarFilterFacet {
  final IconData icon;
  final String label;

  /// The same filter set with this one axis turned off — precomputed rather
  /// than a callback, so a chip's delete action is a value, not a closure over
  /// which axis it happens to be.
  final CalendarGridFilters without;

  const CalendarFilterFacet({
    required this.icon,
    required this.label,
    required this.without,
  });
}

/// **The** description of what a [CalendarGridFilters] is hiding.
///
/// Three surfaces name the active axes — the summary chips above the grid, a
/// saved preset's subtitle, and the name suggested when saving one — and a
/// second copy of the vocabulary would let them disagree about the same
/// filter. They all read [facetsOf]; the icons and labels below are the only
/// definitions. The one licensed difference is *how much* a set says: a chip
/// counts ("Priority (2)") because it must stay one word wide, while a
/// caption and a name read the members back through [namesReadBack]
/// ("Highest, High") like every set row of the filter sheet (`named`).
///
/// Ordered exactly as the filter sheet's sections are, so scanning the chips
/// and scanning the sheet feel like reading the same list twice.
abstract final class CalendarFilterSummary {
  static const IconData categoryIcon = Icons.category_rounded;
  static const IconData trackedIcon = Icons.checklist_rounded;
  static const IconData missedIcon = Icons.remove_circle_outline_rounded;
  static const IconData linkedNoteIcon = Icons.link_rounded;

  /// Shared by the "with money" trait and the money **layer**: they are the
  /// same subsystem seen from two sides, and giving them different icons would
  /// imply they are unrelated.
  static const IconData moneyIcon = Icons.payments_outlined;
  static const IconData descriptionIcon = Icons.notes_rounded;
  static const IconData countedIcon = Icons.tag_rounded;
  static const IconData hideEndedIcon = Icons.event_busy_rounded;
  static const IconData holidayIcon = Icons.celebration_rounded;
  static const IconData fastingIcon = Icons.no_food_rounded;

  /// `none` wears the agenda strip's "no events" glyph, so the chip that
  /// undoes it and the menu item that sets it are one picture.
  static IconData eventTypeIcon(AgendaEventType type) {
    return switch (type) {
      AgendaEventType.all => Icons.event_note_rounded,
      AgendaEventType.recurring => Icons.repeat_rounded,
      AgendaEventType.oneTime => Icons.event_rounded,
      AgendaEventType.none => Icons.event_busy_rounded,
    };
  }

  /// Shares the agenda's strings deliberately: both name the same
  /// [AgendaEventType], and one surface calling a rule "recurring" while the
  /// other called it something else would be a difference the user sees.
  static String eventTypeLabel(AppLocalizations l10n, AgendaEventType type) {
    return switch (type) {
      AgendaEventType.all => l10n.upcomingEventTypeAll,
      AgendaEventType.recurring => l10n.upcomingEventTypeRecurring,
      AgendaEventType.oneTime => l10n.upcomingEventTypeOneTime,
      AgendaEventType.none => l10n.upcomingEventsHidden,
    };
  }

  static IconData timingIcon(CalendarEventTiming timing) {
    return switch (timing) {
      CalendarEventTiming.timed => Icons.schedule_rounded,
      CalendarEventTiming.allDay => Icons.today_rounded,
      CalendarEventTiming.all => Icons.access_time_rounded,
    };
  }

  static String timingLabel(AppLocalizations l10n, CalendarEventTiming timing) {
    return switch (timing) {
      CalendarEventTiming.all => l10n.upcomingEventTypeAll,
      CalendarEventTiming.timed => l10n.calendarFilterTimed,
      CalendarEventTiming.allDay => l10n.eventAllDay,
    };
  }

  /// Every narrowing axis currently active, in sheet order.
  ///
  /// `panelShowsAll` is deliberately absent: it widens rather than narrows, so
  /// it can never be the reason something is missing and has nothing to
  /// contribute to a description of what is hidden.
  static List<CalendarFilterFacet> facetsOf(
    CalendarGridFilters filters,
    AppLocalizations l10n, {
    bool named = false,
  }) {
    final facets = <CalendarFilterFacet>[];

    if (filters.hiddenCategoryIds.isNotEmpty) {
      facets.add(
        CalendarFilterFacet(
          icon: categoryIcon,
          label: _categoryLabel(filters, l10n, named: named),
          without: filters.copyWith(hiddenCategoryIds: const {}),
        ),
      );
    }

    if (filters.priorities.isNotEmpty) {
      // One selected priority names itself; several would not fit a chip, so
      // the count stands in there — the shape the agenda's chip already
      // uses — while a named read-back lists them highest first.
      final single = filters.priorities.length == 1
          ? filters.priorities.single
          : null;
      final ascending = filters.priorities.toList()..sort();
      facets.add(
        CalendarFilterFacet(
          icon: EventPriorities.iconFor(single ?? kDefaultEventPriority),
          label: single != null
              ? EventPriorities.labelOf(single, l10n)
              : named
              ? namesReadBack(
                  [for (final p in ascending) EventPriorities.labelOf(p, l10n)],
                  l10n,
                )
              : '${l10n.upcomingPriority} (${filters.priorities.length})',
          without: filters.copyWith(priorities: const {}),
        ),
      );
    }

    if (filters.eventType != AgendaEventType.all) {
      facets.add(
        CalendarFilterFacet(
          icon: eventTypeIcon(filters.eventType),
          label: eventTypeLabel(l10n, filters.eventType),
          without: filters.copyWith(eventType: AgendaEventType.all),
        ),
      );
    }

    if (filters.timing != CalendarEventTiming.all) {
      facets.add(
        CalendarFilterFacet(
          icon: timingIcon(filters.timing),
          label: timingLabel(l10n, filters.timing),
          without: filters.copyWith(timing: CalendarEventTiming.all),
        ),
      );
    }

    if (filters.trackedOnly) {
      facets.add(
        CalendarFilterFacet(
          icon: trackedIcon,
          label: l10n.calendarFilterTracked,
          without: filters.copyWith(trackedOnly: false),
        ),
      );
    }

    if (filters.missedOnly) {
      facets.add(
        CalendarFilterFacet(
          icon: missedIcon,
          label: l10n.eventPresenceMissed,
          without: filters.copyWith(missedOnly: false),
        ),
      );
    }

    if (filters.linkedNotesOnly) {
      facets.add(
        CalendarFilterFacet(
          icon: linkedNoteIcon,
          label: l10n.eventLinkedNote,
          without: filters.copyWith(linkedNotesOnly: false),
        ),
      );
    }

    if (filters.moneyOnly) {
      facets.add(
        CalendarFilterFacet(
          icon: moneyIcon,
          label: l10n.calendarFilterWithMoney,
          without: filters.copyWith(moneyOnly: false),
        ),
      );
    }

    if (filters.withDescriptionOnly) {
      facets.add(
        CalendarFilterFacet(
          icon: descriptionIcon,
          label: l10n.calendarFilterWithDescription,
          without: filters.copyWith(withDescriptionOnly: false),
        ),
      );
    }

    if (filters.countedOnly) {
      facets.add(
        CalendarFilterFacet(
          icon: countedIcon,
          label: l10n.calendarFilterCounted,
          without: filters.copyWith(countedOnly: false),
        ),
      );
    }

    if (filters.hideEnded) {
      facets.add(
        CalendarFilterFacet(
          icon: hideEndedIcon,
          label: l10n.calendarFilterHideEnded,
          without: filters.copyWith(hideEnded: false),
        ),
      );
    }

    // A layer facet exists only while its layer is **off**, and reads
    // "Without X" rather than "X" — a facet wearing the layer's bare name
    // would say the opposite of what it means.
    if (!filters.showHolidays) {
      facets.add(
        CalendarFilterFacet(
          icon: holidayIcon,
          label: l10n.calendarFilterLayerHidden(l10n.upcomingShowHolidays),
          without: filters.copyWith(showHolidays: true),
        ),
      );
    }

    if (!filters.showFasting) {
      facets.add(
        CalendarFilterFacet(
          icon: fastingIcon,
          label: l10n.calendarFilterLayerHidden(l10n.upcomingShowFasting),
          without: filters.copyWith(showFasting: true),
        ),
      );
    }

    if (!filters.showMoney) {
      facets.add(
        CalendarFilterFacet(
          icon: moneyIcon,
          label: l10n.calendarFilterLayerHidden(l10n.calendarFilterMoneyLayer),
          without: filters.copyWith(showMoney: true),
        ),
      );
    }

    return facets;
  }

  /// Every active axis in one line — a saved preset's subtitle, and what the
  /// search field matches against. The sets are named, not counted, so the
  /// caption reads like the Filters sheet's rows.
  ///
  /// Returns [AppLocalizations.calendarFilterShowsEverything] for a filter set
  /// that hides nothing, which a preset can still hold: a blob written by a
  /// newer build, or one corrupted in storage, decodes to exactly that rather
  /// than throwing, and the row must still say something true.
  static String describe(
    CalendarGridFilters filters,
    AppLocalizations l10n,
  ) {
    final facets = facetsOf(filters, l10n, named: true);
    if (facets.isEmpty) return l10n.calendarFilterShowsEverything;
    return facets.map((facet) => facet.label).join(' · ');
  }

  /// How many names a set reads back before folding the rest into "+N more".
  /// Two keeps a value on one line at typical name lengths.
  static const int namedLimit = 2;

  /// One line naming a selection — the first [namedLimit] of [names] joined
  /// by ", " and, past them, `categoriesMore(rest)`: "Gym, Strength +3 more".
  ///
  /// The one read-back rule for every set — the Categories, Priority and Only
  /// show rows of the filter sheet and `CategoryFilterTile` — so a count can
  /// never hide behind an ellipsis on one surface and read "+N more" on
  /// another. An empty list reads as nothing; each caller owns its own word
  /// for that ("All", "Any", "Everything").
  static String namesReadBack(List<String> names, AppLocalizations l10n) {
    if (names.length <= namedLimit) return names.join(', ');
    final named = names.take(namedLimit).join(', ');
    return '$named ${l10n.categoriesMore(names.length - namedLimit)}';
  }

  /// The name the save dialog opens on: the first two axes, which is what a
  /// user would have typed anyway ("Gym · Tracked"), with the rest elided.
  ///
  /// A suggestion, never a constraint — the field is editable and the caller
  /// takes whatever comes back.
  static String suggestName(
    CalendarGridFilters filters,
    AppLocalizations l10n,
  ) {
    final facets = facetsOf(filters, l10n, named: true);
    if (facets.isEmpty) return l10n.calendarFilterShowsEverything;
    final leading = facets.take(2).map((facet) => facet.label).join(' · ');
    return facets.length > 2 ? '$leading…' : leading;
  }

  /// Names the categories still showing while few enough to name, and counts
  /// them past that — or, [named], reads them all back ("Gym, Strength +3
  /// more").
  ///
  /// Counts what is **shown**, not what is hidden, matching the agenda's
  /// allowlist chip — and counted over the offered catalog rather than by
  /// subtracting set sizes, so a stale id left by a deleted category cannot
  /// make the number lie.
  static String _categoryLabel(
    CalendarGridFilters filters,
    AppLocalizations l10n, {
    bool named = false,
  }) {
    final shown = [
      for (final category in CalendarCategories.visiblePlus(
        filters.hiddenCategoryIds,
      ))
        if (!filters.hiddenCategoryIds.contains(category.id)) category,
    ];
    if (shown.isEmpty) return l10n.calendarFilterNoCategories;
    if (named || shown.length <= namedLimit) {
      return namesReadBack(
        [for (final c in shown) CalendarCategories.labelOf(c, l10n)],
        l10n,
      );
    }
    return '${l10n.calendarCategories} (${shown.length})';
  }
}
