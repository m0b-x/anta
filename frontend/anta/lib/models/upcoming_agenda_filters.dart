import 'package:equatable/equatable.dart';

import 'calendar_event.dart';

/// Which events the upcoming agenda lists — a single mutually-exclusive axis,
/// so it can never encode the contradictory "neither" state two booleans would
/// allow. [none] hides the events layer entirely, leaving only the interleaved
/// holiday/fasting rows ("upcoming holidays without events"). Persisted by
/// name; [fromName] falls back to [all] for a value written by a newer build.
enum AgendaEventType {
  all,
  recurring,
  oneTime,
  none;

  static AgendaEventType fromName(String? name) {
    for (final type in values) {
      if (type.name == name) return type;
    }
    return all;
  }
}

/// How the upcoming agenda presents fasting days — three mutually exclusive
/// presentations of one thing, so it can never encode the nonsense a second
/// boolean stacked on the old collapse switch would allow (collapse *and*
/// summarize).
///
/// [everyDay] lists one row per marked day, [periods] one row per fasting run
/// (the shipped behaviour, and still the default), and [summary] a single card
/// per enabled tradition digesting the whole window. Persisted by name;
/// [fromName] falls back to [periods] for a value written by a newer build.
enum AgendaFastingDisplay {
  everyDay,
  periods,
  summary;

  static AgendaFastingDisplay fromName(String? name) {
    for (final display in values) {
      if (display.name == name) return display;
    }
    return periods;
  }
}

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

  /// Whether public holidays are listed alongside events. Off by default —
  /// the agenda is a training log first.
  final bool showHolidays;

  /// Whether configured fasting days are listed alongside events. Off by
  /// default, and inert unless a fasting tradition is configured.
  final bool showFasting;

  /// Whether each recurring event is shown once (its next in-window
  /// occurrence) instead of one row per occurring day. Off by default; the
  /// recurrence label already conveys the cadence.
  final bool collapseRecurring;

  /// How fasting days are presented — see [AgendaFastingDisplay].
  /// [AgendaFastingDisplay.periods] by default: a Lent is forty consecutive
  /// days, and listing each one buries everything else.
  final AgendaFastingDisplay fastingDisplay;

  /// Whether the look-ahead window restarts from the calendar's selected day.
  /// **Off by default** — the window starts today, and a grid tap only moves
  /// the grid. Turning it on restores the walk-forward "upcoming from here"
  /// model; an agenda row tap never re-anchors either way.
  final bool followSelectedDay;

  /// Which events the list shows — see [AgendaEventType]. [AgendaEventType.all]
  /// (the default) is the filter off.
  final AgendaEventType eventType;

  /// Category ids to include (an allowlist). **Empty means every category** —
  /// the filter is off, mirroring [priorities]. Composes on top of the
  /// calendar's inherited hidden-category set.
  final Set<String> categoryIds;

  const UpcomingAgendaFilters({
    this.rangeDays = defaultRangeDays,
    this.priorities = const {},
    this.customStart,
    this.customEnd,
    this.query = '',
    this.showHolidays = false,
    this.showFasting = false,
    this.collapseRecurring = false,
    this.fastingDisplay = AgendaFastingDisplay.periods,
    this.followSelectedDay = false,
    this.eventType = AgendaEventType.all,
    this.categoryIds = const {},
  });

  /// Look-ahead window the panel opens on, and the one [restrictiveFilterCount]
  /// treats as "no window filter".
  static const int defaultRangeDays = 30;

  /// Look-ahead windows offered as presets, in days.
  static const List<int> rangePresets = [7, defaultRangeDays, 90];

  bool get hasCustomRange => customStart != null && customEnd != null;

  /// How many filters are currently **narrowing** the results.
  ///
  /// Only restrictions count: the layer toggles ([showHolidays],
  /// [showFasting]) add rows rather than remove them, and the collapse
  /// toggles condense rows that are all still represented. So this is exactly
  /// the set of filters that can explain "why is something missing" — which is
  /// what the panel's badge counts and its summary chips undo one at a time.
  int get restrictiveFilterCount {
    var count = 0;
    if (hasCustomRange || rangeDays != defaultRangeDays) count++;
    if (eventType != AgendaEventType.all) count++;
    if (priorities.isNotEmpty) count++;
    if (categoryIds.isNotEmpty) count++;
    return count;
  }

  UpcomingAgendaFilters copyWith({
    int? rangeDays,
    Set<int>? priorities,
    DateTime? customStart,
    DateTime? customEnd,
    String? query,
    bool? showHolidays,
    bool? showFasting,
    bool? collapseRecurring,
    AgendaFastingDisplay? fastingDisplay,
    bool? followSelectedDay,
    AgendaEventType? eventType,
    Set<String>? categoryIds,
    bool clearCustomRange = false,
  }) {
    return UpcomingAgendaFilters(
      rangeDays: rangeDays ?? this.rangeDays,
      priorities: priorities ?? this.priorities,
      customStart: clearCustomRange ? null : (customStart ?? this.customStart),
      customEnd: clearCustomRange ? null : (customEnd ?? this.customEnd),
      query: query ?? this.query,
      showHolidays: showHolidays ?? this.showHolidays,
      showFasting: showFasting ?? this.showFasting,
      collapseRecurring: collapseRecurring ?? this.collapseRecurring,
      fastingDisplay: fastingDisplay ?? this.fastingDisplay,
      followSelectedDay: followSelectedDay ?? this.followSelectedDay,
      eventType: eventType ?? this.eventType,
      categoryIds: categoryIds ?? this.categoryIds,
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

  /// Encodes [categoryIds] as a sorted CSV. Built-in ids are plain names and
  /// custom ids are UUIDs, so neither contains a comma.
  static String encodeCategories(Set<String> ids) {
    final sorted = ids.toList()..sort();
    return sorted.join(',');
  }

  static Set<String> decodeCategories(String raw) {
    if (raw.isEmpty) return const {};
    return {
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    };
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
    showHolidays,
    showFasting,
    collapseRecurring,
    fastingDisplay,
    followSelectedDay,
    eventType,
    categoryIds,
  ];
}
