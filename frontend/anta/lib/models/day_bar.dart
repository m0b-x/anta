import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

import 'chain_item.dart';

/// A single colored bar to draw inside a calendar day cell.
///
/// Bars are produced by `DayBarProvider`s and composed by `DayBarsResolver`.
/// Lower [priority] values are drawn first (top of the stack); higher values
/// sink to the bottom. The default ordering places context bars (weekend /
/// holiday) below event bars so events stay visually dominant.
class DayBar extends Equatable implements ChainItem {
  /// Stable identifier used for deduplication across providers.
  /// e.g. `"weekend"`, `"holiday"`, `"event:gym"`.
  @override
  final String key;

  final Color color;

  /// Lower = drawn higher in the stack. Suggested ranges:
  ///   *   0..99   events (most important)
  ///   * 100..199  public holiday
  ///   * 200..299  weekend / contextual
  @override
  final int priority;

  /// Used as a tooltip / semantics label.
  final String semanticLabel;

  /// Drawn by its outline alone, in the same box as a filled marker: a
  /// partner's event under the Outlined look
  /// (`docs/cloud-share-surfaces-roadmap.md` §6.7). Nothing moves, so a
  /// cell's strip keeps its height whichever look is picked.
  final bool hollow;

  const DayBar({
    required this.key,
    required this.color,
    required this.priority,
    required this.semanticLabel,
    this.hollow = false,
  });

  @override
  List<Object?> get props => [key, color, priority, semanticLabel, hollow];
}
