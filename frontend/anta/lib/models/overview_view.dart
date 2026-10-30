import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'calendar_appearance.dart';
import 'overview_list_options.dart';
import 'overview_period.dart';

/// A named overview list the user saved to get back in one tap — the period,
/// the list options and the categories allowlist (D17c · A; never the query,
/// never the mode).
///
/// Persisted in `overview_views` (**v41**) as the one JSON blob [toJson]
/// produces. The period is spelled out here rather than through
/// [OverviewPeriod.encode]: that codec is the period key's, which keeps a
/// custom span or a past year out on purpose (D4), while a view is exactly
/// the place a fixed span earns its keep (D17b).
class OverviewView extends Equatable {
  final String id;

  /// What the user called it; never empty by the time it reaches storage.
  final String name;

  final OverviewPeriod period;

  /// Order, Rows and Missed only.
  final OverviewListOptions options;

  /// The overview's allowlist: empty means every category.
  final Set<String> categoryIds;

  /// Display position: appended on create, rewritten dense by
  /// `OverviewViewService.reorder`.
  final int sortOrder;

  /// How the stored period was written, for a week, a month or a year:
  /// `true` for the rolling "this week", "this month" or "this year",
  /// `false` for a pinned one, `null` for a period the user has just picked,
  /// which [toJson] then reads off `today` as before.
  ///
  /// The one bit [OverviewWeekPeriod], [OverviewMonthPeriod] and
  /// [OverviewYearPeriod] cannot carry, and the reason a decode no longer
  /// loses it: a rename on a later day re-encodes the period it decoded, and
  /// without this a view left on "this year" over New Year — or on "this
  /// week" over a Monday — pinned the old one for good (review 2).
  final bool? rollsWithToday;

  const OverviewView({
    required this.id,
    required this.name,
    required this.period,
    this.options = OverviewListOptions.defaults,
    this.categoryIds = const {},
    this.sortOrder = 0,
    this.rollsWithToday,
  });

  /// A new [period] drops [rollsWithToday]: re-pointing a view at the list
  /// shown is the one moment the stored kind may be decided afresh.
  OverviewView copyWith({
    String? id,
    String? name,
    OverviewPeriod? period,
    OverviewListOptions? options,
    Set<String>? categoryIds,
    int? sortOrder,
  }) {
    return OverviewView(
      id: id ?? this.id,
      name: name ?? this.name,
      period: period ?? this.period,
      options: options ?? this.options,
      categoryIds: categoryIds ?? this.categoryIds,
      sortOrder: sortOrder ?? this.sortOrder,
      rollsWithToday: period == null ? rollsWithToday : null,
    );
  }

  /// The period this view lists on [today] — the one live read of it.
  ///
  /// [period] is a snapshot taken when the view was decoded, and a view
  /// stays decoded for as long as the service lives: a view saved on "this
  /// week" read on Monday from Sunday's snapshot would list last week, fail
  /// to match the This week list and, applied, persist a past week — which
  /// clears the period key. A rolling view is re-derived from [today] by its
  /// kind instead; a pinned one or a period just picked is [period] as is.
  OverviewPeriod periodOn({
    required DateTime today,
    required CalendarWeekStart weekStart,
  }) {
    if (rollsWithToday != true) return period;
    return switch (period) {
      OverviewWeekPeriod() => OverviewPeriod.thisWeek(
        today: today,
        weekStart: weekStart,
      ),
      OverviewMonthPeriod() => OverviewPeriod.thisMonth(today: today),
      OverviewYearPeriod() => OverviewPeriod.thisYear(today: today),
      OverviewRollingPeriod() || OverviewCustomPeriod() => period,
    };
  }

  /// Whether the overview showing [period], [options] and [categoryIds] on
  /// [today] is this view's list, the view's period read through [periodOn].
  bool matches(
    OverviewPeriod period,
    OverviewListOptions options,
    Set<String> categoryIds, {
    required DateTime today,
    required CalendarWeekStart weekStart,
  }) {
    return periodOn(today: today, weekStart: weekStart) == period &&
        this.options.order == options.order &&
        this.options.rows == options.rows &&
        this.options.missedOnly == options.missedOnly &&
        setEquals(this.categoryIds, categoryIds);
  }

  static const String _period = 'period';
  static const String _kind = 'kind';
  static const String _kindWeek = 'week';
  static const String _kindThisWeek = 'thisWeek';
  static const String _kindMonth = 'month';
  static const String _kindThisMonth = 'thisMonth';
  static const String _kindYear = 'year';
  static const String _kindThisYear = 'thisYear';
  static const String _kindPreset = 'preset';
  static const String _kindCustom = 'custom';
  static const String _year = 'year';
  static const String _month = 'month';
  static const String _preset = 'preset';
  static const String _start = 'start';
  static const String _end = 'end';
  static const String _order = 'order';
  static const String _rows = 'rows';
  static const String _missedOnly = 'missedOnly';
  static const String _categories = 'categories';

  /// The stored blob: what is listed, not who the view is — the id, the name
  /// and the position are the row's own columns. The categories are sorted
  /// so one list always writes one blob. [today]'s week, month and year are
  /// saved as "this week", "this month" and "this year", which roll with the
  /// calendar as the Period menu's presets do; any other one — paged to —
  /// keeps its dates. A period this view was decoded with keeps the kind it
  /// was stored under ([rollsWithToday]), whatever day it is written on.
  Map<String, Object?> toJson({required DateTime today}) => {
    _period: switch (period) {
      OverviewWeekPeriod()
          when rollsWithToday ??
              period.menuChoice(today: today) ==
                  OverviewPeriodChoice.thisWeek =>
        {_kind: _kindThisWeek},
      OverviewWeekPeriod(:final start) => {
        _kind: _kindWeek,
        _start: _day(start),
      },
      OverviewMonthPeriod(:final year, :final month)
          when rollsWithToday ?? (year == today.year && month == today.month) =>
        {_kind: _kindThisMonth},
      OverviewMonthPeriod(:final year, :final month) => {
        _kind: _kindMonth,
        _year: year,
        _month: month,
      },
      OverviewYearPeriod(:final year)
          when rollsWithToday ?? year == today.year =>
        {_kind: _kindThisYear},
      OverviewYearPeriod(:final year) => {_kind: _kindYear, _year: year},
      OverviewRollingPeriod(:final preset) => {
        _kind: _kindPreset,
        _preset: preset.name,
      },
      OverviewCustomPeriod(:final start, :final end) => {
        _kind: _kindCustom,
        _start: _day(start),
        _end: _day(end),
      },
    },
    _order: options.order.name,
    _rows: options.rows.name,
    _missedOnly: options.missedOnly,
    _categories: categoryIds.toList()..sort(),
  };

  /// Reads [toJson]'s output forward-compatibly: "this week", "this month"
  /// and "this year" are [today]'s, the week starting on [weekStart] — the
  /// calendar's now, not when the view was saved; a period this build cannot
  /// read — an unknown kind, a preset a newer build added, a malformed date —
  /// is this year too; an absent or unknown option is its default; an
  /// unknown key is ignored. Never throws, so one bad blob cannot hide the
  /// other views.
  static OverviewView fromJson(
    Object? json, {
    required String id,
    required String name,
    required DateTime today,
    required CalendarWeekStart weekStart,
    int sortOrder = 0,
  }) {
    final map = json is Map ? json : const {};
    final missedOnly = map[_missedOnly];
    final categories = map[_categories];
    return OverviewView(
      id: id,
      name: name,
      period: _decodePeriod(map[_period], today: today, weekStart: weekStart),
      options: OverviewListOptions(
        order: OverviewOrder.fromName(_string(map[_order])),
        rows: OverviewRows.fromName(_string(map[_rows])),
        missedOnly: missedOnly is bool && missedOnly,
      ),
      categoryIds: {
        if (categories is List)
          for (final id in categories)
            if (id is String && id.isNotEmpty) id,
      },
      sortOrder: sortOrder,
      rollsWithToday: _rollsWithToday(map[_period]),
    );
  }

  /// Which week, month or year kind [raw] was stored under, or `null` for a
  /// period that is none of those and for one this build read as this year
  /// by fallback — both of which re-encode from `today` as they always did.
  static bool? _rollsWithToday(Object? raw) {
    if (raw is! Map) return null;
    return switch (raw[_kind]) {
      _kindThisWeek || _kindThisMonth || _kindThisYear => true,
      _kindWeek when _parseDay(raw[_start]) != null => false,
      _kindMonth when _month1to12(raw[_month]) != null && raw[_year] is int =>
        false,
      _kindYear when raw[_year] is int => false,
      _ => null,
    };
  }

  static OverviewPeriod _decodePeriod(
    Object? raw, {
    required DateTime today,
    required CalendarWeekStart weekStart,
  }) {
    if (raw is Map) {
      switch (raw[_kind]) {
        case _kindThisWeek:
          return OverviewPeriod.thisWeek(today: today, weekStart: weekStart);
        case _kindWeek:
          final start = _parseDay(raw[_start]);
          if (start != null) return OverviewWeekPeriod(start);
        case _kindThisMonth:
          return OverviewPeriod.thisMonth(today: today);
        case _kindMonth:
          final year = raw[_year];
          final month = _month1to12(raw[_month]);
          if (year is int && month != null) {
            return OverviewMonthPeriod(year, month);
          }
        case _kindThisYear:
          return OverviewPeriod.thisYear(today: today);
        case _kindYear:
          final year = raw[_year];
          if (year is int) return OverviewYearPeriod(year);
        case _kindPreset:
          for (final preset in OverviewRollingPreset.values) {
            if (preset.name == raw[_preset]) {
              return OverviewRollingPeriod(preset);
            }
          }
        case _kindCustom:
          final start = _parseDay(raw[_start]);
          final end = _parseDay(raw[_end]);
          if (start != null && end != null) {
            return OverviewCustomPeriod(start, end);
          }
      }
    }
    return OverviewPeriod.thisYear(today: today);
  }

  static String? _string(Object? value) => value is String ? value : null;

  /// A stored month number, or null for one no calendar has: a month 13
  /// would otherwise roll into the next year's January.
  static int? _month1to12(Object? value) =>
      value is int && value >= DateTime.january && value <= DateTime.december
      ? value
      : null;

  static String _day(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// A stored `yyyy-mm-dd` as the date-only UTC value the overview's custom
  /// span carries, so a decoded view compares equal to the period it saved.
  static DateTime? _parseDay(Object? value) {
    if (value is! String) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  /// [rollsWithToday] stays out: it is how the period was written down, not
  /// part of the view or of the list it stands for, and a view read back is
  /// the view that was saved.
  @override
  List<Object?> get props => [
    id,
    name,
    period,
    options,
    categoryIds,
    sortOrder,
  ];
}
