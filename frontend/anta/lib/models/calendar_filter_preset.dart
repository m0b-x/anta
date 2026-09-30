import 'package:equatable/equatable.dart';

import 'calendar_grid_filters.dart';

/// A named [CalendarGridFilters] the user saved to re-apply in one tap.
///
/// Persisted in `calendar_filter_presets` (**v35**), where [filters] is stored
/// as the one JSON blob [CalendarGridFilters.encode] produces — see the table
/// declaration for why that beats a column per axis.
class CalendarFilterPreset extends Equatable {
  final String id;

  /// What the user called it. Never empty by the time it reaches storage —
  /// `FilterPresetService` falls back to a generated summary when the naming
  /// field is left blank, so a preset always has something to be found by.
  final String name;

  final CalendarGridFilters filters;

  /// Display position: appended on create, rewritten dense (`0..N-1`) by
  /// `FilterPresetService.reorder` after a drag or a Move to top in the
  /// saved-filters sheet (2026-09-29, `docs/calendar-saved-filters-roadmap.md`).
  final int sortOrder;

  const CalendarFilterPreset({
    required this.id,
    required this.name,
    required this.filters,
    this.sortOrder = 0,
  });

  CalendarFilterPreset copyWith({
    String? id,
    String? name,
    CalendarGridFilters? filters,
    int? sortOrder,
  }) {
    return CalendarFilterPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      filters: filters ?? this.filters,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  List<Object?> get props => [id, name, filters, sortOrder];
}
