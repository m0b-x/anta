import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

import 'chain_item.dart';

/// A single mark on the vertical rail drawn along the left edge of a calendar
/// day cell.
///
/// The rail is the calendar's **multi-source** presence channel. The cell wash
/// (`CellTintResolver`) deliberately picks exactly one event per day, so a day
/// carrying three tracked commitments reads as one; the rail shows every one of
/// them, and whether each was kept.
///
/// Deliberately a separate model from `DayBar` rather than a variant of it: the
/// two channels answer different questions, and merging them would let a rail
/// mark compete for the bottom strip's slots. It is `DayBar` plus [missed] —
/// same field names, so the two provider suites share fixture builders.
///
/// Lower [priority] values sort to the top of the rail, exactly as with
/// `DayBar`.
class DayRailMark extends Equatable implements ChainItem {
  /// Stable identifier used for deduplication across providers, e.g.
  /// `"event:<uuid>"`. Shares `DayBar`'s keyspace on purpose — the mark that
  /// survives the cap is then the same event that wins the wash.
  @override
  final String key;

  /// The mark's colour, **unfaded**. Missed marks are dimmed at paint time so
  /// the widget can also render them hollow in `dot` style; folding the alpha
  /// in here would fade them twice.
  final Color color;

  /// Lower = drawn higher in the stack.
  @override
  final int priority;

  /// Whether this occurrence was marked missed (**v26** presence). Drives the
  /// faded/hollow rendering and is already reflected in [semanticLabel] —
  /// colour is never the only carrier.
  final bool missed;

  /// Used as the mark's contribution to the rail's single merged semantics
  /// node.
  final String semanticLabel;

  const DayRailMark({
    required this.key,
    required this.color,
    required this.priority,
    required this.missed,
    required this.semanticLabel,
  });

  @override
  List<Object?> get props => [key, color, priority, missed, semanticLabel];
}
