import 'package:equatable/equatable.dart';

/// What deleting one category touches, counted over exactly the live rows
/// `CalendarCategoryDao.tombstoneCascade` moves or tombstones: the delete
/// sheet says it before the user confirms, so the numbers must be the
/// cascade's own and never a cache's.
class CategoryDeleteImpact extends Equatable {
  /// Events that move to the chosen category.
  final int events;

  /// The category's own alerts, which are tombstoned with it.
  final int alerts;

  /// Templates that move with the events.
  final int templates;

  const CategoryDeleteImpact({
    required this.events,
    required this.alerts,
    required this.templates,
  });

  @override
  List<Object?> get props => [events, alerts, templates];
}
