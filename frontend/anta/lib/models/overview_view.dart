import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

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

  const OverviewView({
    required this.id,
    required this.name,
    required this.period,
    this.options = OverviewListOptions.defaults,
    this.categoryIds = const {},
    this.sortOrder = 0,
  });

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
    );
  }

  /// Whether the overview showing [period], [options] and [categoryIds] is
  /// this view's list.
  bool matches(
    OverviewPeriod period,
    OverviewListOptions options,
    Set<String> categoryIds,
  ) {
    return this.period == period &&
        this.options.order == options.order &&
        this.options.rows == options.rows &&
        this.options.missedOnly == options.missedOnly &&
        setEquals(this.categoryIds, categoryIds);
  }

  static const String _period = 'period';
  static const String _kind = 'kind';
  static const String _kindYear = 'year';
  static const String _kindThisYear = 'thisYear';
  static const String _kindPreset = 'preset';
  static const String _kindCustom = 'custom';
  static const String _year = 'year';
  static const String _preset = 'preset';
  static const String _start = 'start';
  static const String _end = 'end';
  static const String _order = 'order';
  static const String _rows = 'rows';
  static const String _missedOnly = 'missedOnly';
  static const String _categories = 'categories';

  /// The stored blob: what is listed, not who the view is — the id, the name
  /// and the position are the row's own columns. The categories are sorted
  /// so one list always writes one blob. [today]'s year is saved as "this
  /// year", which rolls with the calendar as the Period menu's presets do;
  /// any other year — one paged to — keeps its number.
  Map<String, Object?> toJson({required DateTime today}) => {
    _period: switch (period) {
      OverviewYearPeriod(:final year) when year == today.year => {
        _kind: _kindThisYear,
      },
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

  /// Reads [toJson]'s output forward-compatibly: "this year" is [today]'s; a
  /// period this build cannot read — an unknown kind, a preset a newer build
  /// added, a malformed date — is this year too; an absent or unknown option
  /// is its default; an unknown key
  /// is ignored. Never throws, so one bad blob cannot hide the other views.
  static OverviewView fromJson(
    Object? json, {
    required String id,
    required String name,
    required DateTime today,
    int sortOrder = 0,
  }) {
    final map = json is Map ? json : const {};
    final missedOnly = map[_missedOnly];
    final categories = map[_categories];
    return OverviewView(
      id: id,
      name: name,
      period: _decodePeriod(map[_period], today: today),
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
    );
  }

  static OverviewPeriod _decodePeriod(Object? raw, {required DateTime today}) {
    if (raw is Map) {
      switch (raw[_kind]) {
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
