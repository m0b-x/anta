import 'package:equatable/equatable.dart';

import 'calendar_event.dart';

/// Everything the upcoming-agenda panel filters by.
///
/// Lives above the panel widget and is persisted through `SettingsService`,
/// so the agenda survives both a panel-mode switch (which disposes the view)
/// and an app restart.
class UpcomingAgendaFilters extends Equatable {
  /// Look-ahead window in days, used when no [customStart]/[customEnd] is
  /// set.
  final int rangeDays;

  /// Priorities to include. **Empty means every priority** — the filter is
  /// off, not "nothing matches".
  final Set<int> priorities;

  /// Explicit range picked through the date-range picker (date-only UTC).
  /// Both are set together; either being null means "use [rangeDays]".
  final DateTime? customStart;
  final DateTime? customEnd;

  /// Case-insensitive text matched against event titles and descriptions.
  final String query;

  /// Whether the period/priority chip rows are expanded in the panel.
  final bool filtersExpanded;

  /// Whether public holidays are listed alongside events. Off by default —
  /// the agenda is a training log first.
  final bool showHolidays;

  const UpcomingAgendaFilters({
    this.rangeDays = 30,
    this.priorities = const {},
    this.customStart,
    this.customEnd,
    this.query = '',
    this.filtersExpanded = false,
    this.showHolidays = false,
  });

  bool get hasCustomRange => customStart != null && customEnd != null;

  UpcomingAgendaFilters copyWith({
    int? rangeDays,
    Set<int>? priorities,
    DateTime? customStart,
    DateTime? customEnd,
    String? query,
    bool? filtersExpanded,
    bool? showHolidays,
    bool clearCustomRange = false,
  }) {
    return UpcomingAgendaFilters(
      rangeDays: rangeDays ?? this.rangeDays,
      priorities: priorities ?? this.priorities,
      customStart: clearCustomRange ? null : (customStart ?? this.customStart),
      customEnd: clearCustomRange ? null : (customEnd ?? this.customEnd),
      query: query ?? this.query,
      filtersExpanded: filtersExpanded ?? this.filtersExpanded,
      showHolidays: showHolidays ?? this.showHolidays,
    );
  }

  /// Drops a custom range that has already fully elapsed.
  ///
  /// Without this, reopening the app weeks after picking an explicit range
  /// lands on an "Upcoming" panel showing a window that ended in the past —
  /// which reads as "no events" rather than as a stale filter.
  UpcomingAgendaFilters withoutElapsedRange(DateTime today) {
    final end = customEnd;
    if (end == null) return this;
    return end.isBefore(today) ? copyWith(clearCustomRange: true) : this;
  }

  /// Encodes [priorities] as a sorted CSV. An empty string means "all"; the
  /// caller distinguishes "never set" by the key being absent entirely.
  static String encodePriorities(Set<int> priorities) {
    final sorted = priorities.toList()..sort();
    return sorted.join(',');
  }

  static Set<int> decodePriorities(String raw) {
    if (raw.isEmpty) return const {};
    final values = <int>{};
    for (final part in raw.split(',')) {
      final value = int.tryParse(part.trim());
      if (value != null &&
          value >= kMinEventPriority &&
          value <= kMaxEventPriority) {
        values.add(value);
      }
    }
    return values;
  }

  /// Encodes the custom range as `yyyyMMdd|yyyyMMdd`, or an empty string
  /// when there is none.
  static String encodeRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '';
    return '${_encodeDate(start)}|${_encodeDate(end)}';
  }

  /// Decodes [encodeRange]. Returns `(null, null)` for anything malformed,
  /// so a corrupted value degrades to the preset window instead of throwing.
  static (DateTime?, DateTime?) decodeRange(String raw) {
    if (raw.isEmpty) return (null, null);
    final parts = raw.split('|');
    if (parts.length != 2) return (null, null);
    final start = _decodeDate(parts[0]);
    final end = _decodeDate(parts[1]);
    if (start == null || end == null || end.isBefore(start)) {
      return (null, null);
    }
    return (start, end);
  }

  static String _encodeDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}$month$day';
  }

  static DateTime? _decodeDate(String raw) {
    if (raw.length != 8) return null;
    final year = int.tryParse(raw.substring(0, 4));
    final month = int.tryParse(raw.substring(4, 6));
    final day = int.tryParse(raw.substring(6, 8));
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime.utc(year, month, day);
  }

  @override
  List<Object?> get props => [
    rangeDays,
    priorities,
    customStart,
    customEnd,
    query,
    filtersExpanded,
    showHolidays,
  ];
}
