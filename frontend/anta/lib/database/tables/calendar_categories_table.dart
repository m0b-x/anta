import 'package:drift/drift.dart';

/// Persisted calendar event categories.
///
/// Built-in categories are seeded by `CategoryService` with stable ids equal
/// to the historical `CalendarEventCategory` enum names (`'gym'`, `'cardio'`,
/// …) using insert-if-missing semantics, so user edits to a built-in's color
/// or icon survive subsequent launches and existing events (whose
/// `calendar_events.category` already holds those strings) link to them with
/// no data migration. User-created categories carry a UUID [id] and
/// `is_built_in = false`.
@DataClassName('CalendarCategoryRow')
class CalendarCategories extends Table {
  @override
  String get tableName => 'calendar_categories';

  TextColumn get id => text()();
  TextColumn get name => text()();

  /// 32-bit ARGB color value.
  IntColumn get colorValue => integer()();

  /// Key into the `CalendarIcons` palette.
  TextColumn get iconKey => text()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
