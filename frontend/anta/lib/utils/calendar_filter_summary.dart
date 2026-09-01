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
/// definitions.
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

  static IconData eventTypeIcon(AgendaEventType type) {
    return switch (type) {
      AgendaEventType.recurring => Icons.repeat_rounded,
      AgendaEventType.oneTime => Icons.event_rounded,
      _ => Icons.event_note_rounded,
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
    AppLocalizations l10n,
  ) {
    final facets = <CalendarFilterFacet>[];

    if (filters.hiddenCategoryIds.isNotEmpty) {
      facets.add(
        CalendarFilterFacet(
          icon: categoryIcon,
          label: _categoryLabel(filters, l10n),
          without: filters.copyWith(hiddenCategoryIds: const {}),
        ),
      );
    }

    if (filters.priorities.isNotEmpty) {
      // One selected priority names itself; several would not fit, so the
      // count stands in — the shape the agenda's chip already uses.
      final single = filters.priorities.length == 1
          ? filters.priorities.single
          : null;
      facets.add(
        CalendarFilterFacet(
          icon: EventPriorities.iconFor(single ?? kDefaultEventPriority),
          label: single != null
              ? EventPriorities.labelOf(single, l10n)
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
  /// search field matches against.
  ///
  /// Returns [AppLocalizations.calendarFilterShowsEverything] for a filter set
  /// that hides nothing, which a preset can still hold: a blob written by a
  /// newer build, or one corrupted in storage, decodes to exactly that rather
  /// than throwing, and the row must still say something true.
  static String describe(
    CalendarGridFilters filters,
    AppLocalizations l10n,
  ) {
    final facets = facetsOf(filters, l10n);
    if (facets.isEmpty) return l10n.calendarFilterShowsEverything;
    return facets.map((facet) => facet.label).join(' · ');
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
    final facets = facetsOf(filters, l10n);
    if (facets.isEmpty) return l10n.calendarFilterShowsEverything;
    final leading = facets.take(2).map((facet) => facet.label).join(' · ');
    return facets.length > 2 ? '$leading…' : leading;
  }

  /// Names the categories still showing while few enough to name, and counts
  /// them past that.
  ///
  /// Counts what is **shown**, not what is hidden, matching the agenda's
  /// allowlist chip — and counted over the offered catalog rather than by
  /// subtracting set sizes, so a stale id left by a deleted category cannot
  /// make the number lie.
  static String _categoryLabel(
    CalendarGridFilters filters,
    AppLocalizations l10n,
  ) {
    final shown = [
      for (final category in CalendarCategories.visiblePlus(
        filters.hiddenCategoryIds,
      ))
        if (!filters.hiddenCategoryIds.contains(category.id)) category,
    ];
    if (shown.isEmpty) return l10n.calendarFilterNoCategories;
    if (shown.length <= 2) {
      return shown.map((c) => CalendarCategories.labelOf(c, l10n)).join(', ');
    }
    return '${l10n.calendarCategories} (${shown.length})';
  }
}
