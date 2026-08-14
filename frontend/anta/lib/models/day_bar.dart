import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

/// A single colored bar to draw inside a calendar day cell.
///
/// Bars are produced by `DayBarProvider`s and composed by `DayBarsResolver`.
/// Lower [priority] values are drawn first (top of the stack); higher values
/// sink to the bottom. The default ordering places context bars (weekend /
/// holiday) below event bars so events stay visually dominant.
class DayBar extends Equatable {
  /// Stable identifier used for deduplication across providers.
  /// e.g. `"weekend"`, `"holiday"`, `"event:gym"`.
  final String key;

  final Color color;

  /// Lower = drawn higher in the stack. Suggested ranges:
  ///   *   0..99   events (most important)
  ///   * 100..199  public holiday
  ///   * 200..299  weekend / contextual
  final int priority;

  /// Used as a tooltip / semantics label.
  final String semanticLabel;

  const DayBar({
    required this.key,
    required this.color,
    required this.priority,
    required this.semanticLabel,
  });

  @override
  List<Object?> get props => [key, color, priority, semanticLabel];
}
