import 'package:equatable/equatable.dart';

/// Which end of the period the overview list starts from. Persisted by name;
/// [fromName] falls back to [oldestFirst] for a value written by a newer
/// build.
enum OverviewOrder {
  oldestFirst,
  newestFirst;

  static OverviewOrder fromName(String? name) {
    for (final order in values) {
      if (order.name == name) return order;
    }
    return oldestFirst;
  }
}

/// Whether a recurring event lists every occurrence in the period or one row
/// standing for all of them. Persisted by name; [fromName] falls back to
/// [everyOccurrence].
enum OverviewRows {
  everyOccurrence,
  perEvent;

  static OverviewRows fromName(String? name) {
    for (final rows in values) {
      if (rows.name == name) return rows;
    }
    return everyOccurrence;
  }
}

/// The overview list's options sheet. [order] and [rows] are persisted;
/// [missedOnly] is session-only by decision — a list opening on a narrowed
/// view nobody remembers asking for reads as missing entries.
class OverviewListOptions extends Equatable {
  final OverviewOrder order;
  final OverviewRows rows;
  final bool missedOnly;

  /// Whether a tap on an entry row toggles the day's presence instead of
  /// opening its detail sheet (D18 · A). Session-only like [missedOnly]: a
  /// list that silently writes on the first tap of a later visit would mark
  /// days nobody meant to.
  final bool markPresence;

  const OverviewListOptions({
    this.order = OverviewOrder.oldestFirst,
    this.rows = OverviewRows.everyOccurrence,
    this.missedOnly = false,
    this.markPresence = false,
  });

  static const OverviewListOptions defaults = OverviewListOptions();

  OverviewListOptions copyWith({
    OverviewOrder? order,
    OverviewRows? rows,
    bool? missedOnly,
    bool? markPresence,
  }) {
    return OverviewListOptions(
      order: order ?? this.order,
      rows: rows ?? this.rows,
      missedOnly: missedOnly ?? this.missedOnly,
      markPresence: markPresence ?? this.markPresence,
    );
  }

  @override
  List<Object?> get props => [order, rows, missedOnly, markPresence];
}
