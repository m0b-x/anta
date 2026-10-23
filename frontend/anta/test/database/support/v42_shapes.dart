import 'package:anta/database/database.dart';

/// Rebuilds `counters` and `counter_values` at their v42 shape — the frozen v6
/// DDL plus v8's pin and position columns, none of the CRDT block — with the
/// **full** v6 `idx_counter_values_counter` and no `idx_counters_active`, the
/// state the v43 step has to convert. Leaves both tables empty.
Future<void> rebuildCountersAtV42(AppDatabase db) async {
  // Dropping a table drops its indexes, the v43 ones included.
  await db.customStatement('DROP TABLE counters');
  await db.customStatement('DROP TABLE counter_values');
  await db.customStatement(
    'CREATE TABLE counters ('
    '  id TEXT NOT NULL PRIMARY KEY, '
    '  name TEXT NOT NULL, '
    '  start_value INTEGER NOT NULL DEFAULT 1, '
    '  step INTEGER NOT NULL DEFAULT 1, '
    "  scope TEXT NOT NULL DEFAULT 'global', "
    '  position INTEGER NOT NULL DEFAULT 0, '
    '  created_at INTEGER NOT NULL, '
    '  is_pinned INTEGER NOT NULL DEFAULT 0'
    ')',
  );
  await db.customStatement(
    'CREATE TABLE counter_values ('
    '  counter_id TEXT NOT NULL, '
    "  note_id TEXT NOT NULL DEFAULT '', "
    '  value INTEGER NOT NULL, '
    '  position INTEGER NOT NULL DEFAULT 0, '
    '  is_pinned INTEGER NOT NULL DEFAULT 0, '
    '  PRIMARY KEY (counter_id, note_id)'
    ')',
  );
  await db.customStatement(
    'CREATE INDEX idx_counter_values_counter ON counter_values(counter_id)',
  );
}

/// Rebuilds `calendar_categories` at its v42 shape — the frozen v15 DDL plus
/// v33's archive flag, none of the CRDT block — with no catalog index. Leaves
/// the table empty.
Future<void> rebuildCategoriesAtV42(AppDatabase db) async {
  await db.customStatement('DROP TABLE calendar_categories');
  await db.customStatement(
    'CREATE TABLE calendar_categories ('
    '  id TEXT NOT NULL, '
    '  name TEXT NOT NULL, '
    '  color_value INTEGER NOT NULL, '
    '  icon_key TEXT NOT NULL, '
    '  sort_order INTEGER NOT NULL DEFAULT 0, '
    '  is_built_in INTEGER NOT NULL DEFAULT 0, '
    '  created_at INTEGER NOT NULL, '
    '  updated_at INTEGER NOT NULL, '
    '  is_hidden INTEGER NOT NULL DEFAULT 0, '
    '  PRIMARY KEY (id)'
    ')',
  );
}
