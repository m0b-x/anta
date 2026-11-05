import 'package:equatable/equatable.dart';

/// A card of the calendar report's page, in the page's default order (W).
/// The footer is not a card: it is always there. Not `ReportCard`, which
/// names the group stacks a goal or an insight opens.
///
/// A card is named by its section label: goals → `reportSectionGoals`,
/// insights → `reportSectionInsights`, dueSoon → `reportSectionDueSoon`,
/// totals → `reportSectionTotals`, records → `reportSectionRecords`,
/// months → `reportSectionMonths`, categories → `reportSectionCategories`,
/// tags → `reportSectionTags`, overTime → `reportSectionOverTime`,
/// when → `reportSectionWhen`, balance → `reportSectionBalance`,
/// missed → `reportSectionMissed`, ahead → `reportSectionAhead`.
enum ReportCardKind {
  goals,
  insights,
  dueSoon,
  totals,
  records,
  months,
  categories,
  tags,
  overTime,
  when,
  balance,
  missed,
  ahead,
}

/// Which of the report's cards the page draws, and in which order — the one
/// thing Settings → Calendar → Report holds (W). An off card is absent from
/// the page, never collapsed: the owner turned it off to stop scrolling
/// past it.
///
/// [order] holds every [ReportCardKind] exactly once, so the settings page
/// lists an off card where it would sit when turned back on.
class ReportCards extends Equatable {
  /// Every card, in the order the settings page lists and the page draws
  /// them.
  final List<ReportCardKind> order;

  /// The cards turned off.
  final Set<ReportCardKind> off;

  const ReportCards._(this.order, this.off);

  /// The page's own order, every card on: what an unset key reads as.
  static const ReportCards defaults = ReportCards._(ReportCardKind.values, {});

  /// The cards the page draws, in order.
  List<ReportCardKind> get shown => [
    for (final kind in order)
      if (!off.contains(kind)) kind,
  ];

  /// The stored form: the names in [order], comma-separated, an off card
  /// prefixed with `-` — readable as it stands in a backup.
  String encode() => [
    for (final kind in order) off.contains(kind) ? '-${kind.name}' : kind.name,
  ].join(',');

  /// Reads [encode]'s form forward-compatibly: an unknown name (a card a
  /// later version dropped) is skipped, a repeated one keeps its first
  /// place, and a card the value does not name (one a later version added)
  /// joins on, after the rest, in the default order. Null or empty is
  /// [defaults].
  static ReportCards decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaults;
    final order = <ReportCardKind>[];
    final off = <ReportCardKind>{};
    for (final part in raw.split(',')) {
      var name = part.trim();
      final isOff = name.startsWith('-');
      if (isOff) name = name.substring(1);
      final kind = ReportCardKind.values.asNameMap()[name];
      if (kind == null || order.contains(kind)) continue;
      order.add(kind);
      if (isOff) off.add(kind);
    }
    for (final kind in ReportCardKind.values) {
      if (!order.contains(kind)) order.add(kind);
    }
    return ReportCards._(List.unmodifiable(order), Set.unmodifiable(off));
  }

  /// [order] with the card at [oldIndex] moved to [newIndex], both already
  /// adjusted for the removal as `ReorderableList`'s `onReorderItem` hands
  /// them over. A move out of range, or onto its own place, is this: a drag
  /// that lands where it started is a normal gesture.
  ReportCards moved(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return this;
    if (oldIndex < 0 || oldIndex >= order.length) return this;
    if (newIndex < 0 || newIndex >= order.length) return this;
    final next = [...order];
    next.insert(newIndex, next.removeAt(oldIndex));
    return ReportCards._(List.unmodifiable(next), off);
  }

  /// [kind] turned [on] or off, its place in [order] kept.
  ReportCards toggled(ReportCardKind kind, bool on) {
    if (on != off.contains(kind)) return this;
    return ReportCards._(
      order,
      Set.unmodifiable(on ? ({...off}..remove(kind)) : {...off, kind}),
    );
  }

  @override
  List<Object?> get props => [order, off];
}
