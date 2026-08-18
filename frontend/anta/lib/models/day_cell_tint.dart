import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

/// One resolved tint contribution for a day cell, from a single source.
///
/// Both colours arrive with their alpha **already applied** — the cell is a
/// dumb painter and must never decide how strong a wash is. A source carries
/// two because the same colour cannot serve both roles: a full-cell [wash]
/// has to stay faint enough to sit under the day number, while a 3px [edge]
/// stripe has to be near-opaque to register at all.
///
/// [priority] follows the same convention as `DayBar.priority`: lower wins.
/// Bands are assigned by `CellTintResolver` from the user's conflict setting
/// rather than baked into the providers, so adding a source (holiday, money,
/// training block) is a matter of picking a band.
class CellTintLayer extends Equatable {
  final String key;
  final Color wash;
  final Color edge;
  final int priority;

  const CellTintLayer({
    required this.key,
    required this.wash,
    required this.edge,
    required this.priority,
  });

  @override
  List<Object?> get props => [key, wash, edge, priority];
}

/// The tint a day cell paints: at most one background wash plus at most one
/// edge stripe for the runner-up source.
///
/// Two washes are never stacked. Blending them produces a third colour that
/// belongs to neither source, so the user can no longer tell what they are
/// looking at; a wash plus a thin stripe keeps both signals attributable.
class DayCellTint extends Equatable {
  final Color? wash;
  final Color? edge;

  const DayCellTint({this.wash, this.edge});

  static const DayCellTint empty = DayCellTint();

  bool get isEmpty => wash == null && edge == null;

  @override
  List<Object?> get props => [wash, edge];
}
