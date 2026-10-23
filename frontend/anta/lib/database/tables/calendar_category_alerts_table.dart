import 'package:drift/drift.dart';

/// Alerts hung off a calendar category (**v42**) — "remind me before each
/// birthday", set once on the category and inherited by every event in it.
///
/// The `calendar_event_alerts` row with `category_id` in place of `event_id`,
/// column for column, so one alert means the same thing wherever it hangs:
/// both offset sets are stored and the planner picks by the event's
/// `time == null`, which is what lets one category alert serve a category
/// that mixes timed and all-day events. [dayMinute] `NULL` is the
/// Calendar-settings default, [sound] `NULL` the default sound.
///
/// **Inherited at read time, never copied.** Nothing is written onto an event:
/// `EventAlerts.effectiveFor` projects these rows onto each event in the
/// category, so an event that moves category, a category delete or an import
/// can never leave a materialized copy behind.
///
/// The five CRDT columns are the v40 alert table's block byte-for-byte, with
/// [hlcTimestamp] / [deviceId] default-less. `calendar_categories` only gained
/// its own block in v43; this table carried one from the start because the
/// alert is user data that must merge, and it names its category by the stable
/// id. All stamping lives in `CategoryAlertDao`.
@DataClassName('CategoryAlertRow')
class CalendarCategoryAlerts extends Table {
  @override
  String get tableName => 'calendar_category_alerts';

  TextColumn get id => text()();

  TextColumn get categoryId => text()();

  /// `notify` | `ring` — see `AlertMode`; unknown decodes to `notify`.
  TextColumn get mode => text().withDefault(const Constant('notify'))();

  /// Minutes before a timed event's start. `0` is "at start".
  IntColumn get offsetMinutes => integer().withDefault(const Constant(0))();

  /// Whole days before an all-day event. `0` is "on the day".
  IntColumn get daysBefore => integer().withDefault(const Constant(0))();

  /// Minute of day an all-day alert fires at; `NULL` is the settings default.
  IntColumn get dayMinute => integer().nullable()();

  /// Alarm sound id; `NULL` is the default sound. Alarm tier only.
  TextColumn get sound => text().nullable()();

  /// The category's own switch for this alert, across every event in it.
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  TextColumn get hlcTimestamp => text()();
  TextColumn get deviceId => text()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// The owning account once sync binds one (**v43**); NULL until then.
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
