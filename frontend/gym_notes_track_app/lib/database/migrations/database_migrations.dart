import 'dart:convert';
import 'package:drift/drift.dart';
import '../database.dart';
import 'database_indexes.dart';
import 'database_schema.dart';

class DatabaseMigrations {
  final AppDatabase _db;

  DatabaseMigrations(this._db);

  List<Migration> get _migrations => [
    Migration(
      fromVersion: DatabaseSchema.v1Initial,
      toVersion: DatabaseSchema.v2UserSettings,
      migrate: _migrateV1ToV2,
    ),
    Migration(
      fromVersion: DatabaseSchema.v2UserSettings,
      toVersion: DatabaseSchema.v3ContentChunksIsDeleted,
      migrate: _migrateV2ToV3,
    ),
    Migration(
      fromVersion: DatabaseSchema.v3ContentChunksIsDeleted,
      toVersion: DatabaseSchema.v4ManualOrdering,
      migrate: _migrateV3ToV4,
    ),
    Migration(
      fromVersion: DatabaseSchema.v4ManualOrdering,
      toVersion: DatabaseSchema.v5FolderSortPreferences,
      migrate: _migrateV4ToV5,
    ),
    Migration(
      fromVersion: DatabaseSchema.v5FolderSortPreferences,
      toVersion: DatabaseSchema.v6CounterTables,
      migrate: _migrateV5ToV6,
    ),
    Migration(
      fromVersion: DatabaseSchema.v6CounterTables,
      toVersion: DatabaseSchema.v7CounterDateTimeFix,
      migrate: _migrateV6ToV7,
    ),
    Migration(
      fromVersion: DatabaseSchema.v7CounterDateTimeFix,
      toVersion: DatabaseSchema.v8CounterPinAndOrder,
      migrate: _migrateV7ToV8,
    ),
    Migration(
      fromVersion: DatabaseSchema.v8CounterPinAndOrder,
      toVersion: DatabaseSchema.v9NameUniquenessIndexes,
      migrate: _migrateV8ToV9,
    ),
    Migration(
      fromVersion: DatabaseSchema.v9NameUniquenessIndexes,
      toVersion: DatabaseSchema.v10CalendarTables,
      migrate: _migrateV9ToV10,
    ),
    Migration(
      fromVersion: DatabaseSchema.v10CalendarTables,
      toVersion: DatabaseSchema.v11CalendarEndDateAndTimeOfDay,
      migrate: _migrateV10ToV11,
    ),
    Migration(
      fromVersion: DatabaseSchema.v11CalendarEndDateAndTimeOfDay,
      toVersion: DatabaseSchema.v12CalendarDescription,
      migrate: _migrateV11ToV12,
    ),
    Migration(
      fromVersion: DatabaseSchema.v12CalendarDescription,
      toVersion: DatabaseSchema.v13HolidayProfiles,
      migrate: _migrateV12ToV13,
    ),
    Migration(
      fromVersion: DatabaseSchema.v13HolidayProfiles,
      toVersion: DatabaseSchema.v14CalendarEventNoteLink,
      migrate: _migrateV13ToV14,
    ),
    Migration(
      fromVersion: DatabaseSchema.v14CalendarEventNoteLink,
      toVersion: DatabaseSchema.v15CalendarCategories,
      migrate: _migrateV14ToV15,
    ),
    Migration(
      fromVersion: DatabaseSchema.v15CalendarCategories,
      toVersion: DatabaseSchema.v16CalendarEventColorPriority,
      migrate: _migrateV15ToV16,
    ),
    Migration(
      fromVersion: DatabaseSchema.v16CalendarEventColorPriority,
      toVersion: DatabaseSchema.v17PublicHolidaySuppressed,
      migrate: _migrateV16ToV17,
    ),
    Migration(
      fromVersion: DatabaseSchema.v17PublicHolidaySuppressed,
      toVersion: DatabaseSchema.v18EventPriorityInverted,
      migrate: _migrateV17ToV18,
    ),
    Migration(
      fromVersion: DatabaseSchema.v18EventPriorityInverted,
      toVersion: DatabaseSchema.v19EventRetroactive,
      migrate: _migrateV18ToV19,
    ),
    Migration(
      fromVersion: DatabaseSchema.v19EventRetroactive,
      toVersion: DatabaseSchema.v20EventOccurrenceCount,
      migrate: _migrateV19ToV20,
    ),
    Migration(
      fromVersion: DatabaseSchema.v20EventOccurrenceCount,
      toVersion: DatabaseSchema.v21EventCountStyle,
      migrate: _migrateV20ToV21,
    ),
  ];

  Future<void> runMigrations(Migrator m, int from, int to) async {
    for (final migration in _migrations) {
      if (from < migration.toVersion && to >= migration.toVersion) {
        await migration.migrate(m, _db);
      }
    }
  }

  Future<void> _migrateV1ToV2(Migrator m, GeneratedDatabase db) async {
    await m.createTable(_db.userSettings);
  }

  Future<void> _migrateV2ToV3(Migrator m, GeneratedDatabase db) async {
    await m.addColumn(_db.contentChunks, _db.contentChunks.isDeleted);
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notes_created ON notes(created_at DESC) WHERE is_deleted = 0',
    );
    await _db.customStatement('DROP INDEX IF EXISTS idx_chunks_note');
  }

  Future<void> _migrateV3ToV4(Migrator m, GeneratedDatabase db) async {
    await m.addColumn(_db.folders, _db.folders.position);
    await m.addColumn(_db.notes, _db.notes.position);

    await _initializeFolderPositions();
    await _initializeNotePositions();
    await _createPositionIndexes();
  }

  Future<void> _initializeFolderPositions() async {
    await _db.customStatement('''
      UPDATE folders SET position = (
        SELECT COUNT(*) FROM folders f2 
        WHERE f2.created_at < folders.created_at 
        AND COALESCE(f2.parent_id, '') = COALESCE(folders.parent_id, '')
        AND f2.is_deleted = 0
      ) WHERE is_deleted = 0
    ''');
  }

  Future<void> _initializeNotePositions() async {
    await _db.customStatement('''
      UPDATE notes SET position = (
        SELECT COUNT(*) FROM notes n2 
        WHERE n2.created_at < notes.created_at 
        AND n2.folder_id = notes.folder_id
        AND n2.is_deleted = 0
      ) WHERE is_deleted = 0
    ''');
  }

  Future<void> _createPositionIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_folders_position ON folders(parent_id, position) WHERE is_deleted = 0',
    );
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notes_position ON notes(folder_id, position) WHERE is_deleted = 0',
    );
  }

  Future<void> _migrateV4ToV5(Migrator m, GeneratedDatabase db) async {
    // Add sort preference columns to folders table
    await m.addColumn(_db.folders, _db.folders.noteSortOrder);
    await m.addColumn(_db.folders, _db.folders.subfolderSortOrder);
  }

  Future<void> _migrateV5ToV6(Migrator m, GeneratedDatabase db) async {
    // 1. Create the new tables using raw SQL (schema as of v6, without
    //    isPinned/position columns that were added in v8)
    await _db.customStatement(
      'CREATE TABLE IF NOT EXISTS counters ('
      '  id TEXT NOT NULL PRIMARY KEY, '
      '  name TEXT NOT NULL, '
      '  start_value INTEGER NOT NULL DEFAULT 1, '
      '  step INTEGER NOT NULL DEFAULT 1, '
      '  scope TEXT NOT NULL DEFAULT \'global\', '
      '  position INTEGER NOT NULL DEFAULT 0, '
      '  created_at INTEGER NOT NULL'
      ')',
    );
    await _db.customStatement(
      'CREATE TABLE IF NOT EXISTS counter_values ('
      '  counter_id TEXT NOT NULL, '
      '  note_id TEXT NOT NULL DEFAULT \'\', '
      '  value INTEGER NOT NULL, '
      '  PRIMARY KEY (counter_id, note_id)'
      ')',
    );

    // 2. Create index on counter_values for fast lookups by counter_id
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_counter_values_counter '
      'ON counter_values(counter_id)',
    );

    // 3. Migrate existing JSON data from user_settings
    await _migrateCounterJsonToTables();

    // 4. Clean up old JSON keys
    await _db.customStatement(
      "DELETE FROM user_settings WHERE key = 'counters'",
    );
    await _db.customStatement(
      "DELETE FROM user_settings WHERE key = 'counter_global_values'",
    );
    await _db.customStatement(
      "DELETE FROM user_settings WHERE key LIKE 'counter_note_values_%'",
    );
  }

  Future<void> _migrateV6ToV7(Migrator m, GeneratedDatabase db) async {
    await _db.customStatement(
      "UPDATE counters "
      "SET created_at = CAST(strftime('%s', created_at) AS INTEGER) * 1000 "
      "WHERE typeof(created_at) = 'text'",
    );
  }

  Future<void> _migrateCounterJsonToTables() async {
    // Read existing counter definitions
    final countersRaw = await _db.userSettingsDao.getValue('counters');
    if (countersRaw == null) return;

    List<dynamic> countersList;
    try {
      countersList = jsonDecode(countersRaw) as List<dynamic>;
    } catch (_) {
      return;
    }

    // Insert counter definitions
    for (var i = 0; i < countersList.length; i++) {
      final c = countersList[i] as Map<String, dynamic>;
      final id = c['id'] as String;
      final name = c['name'] as String? ?? 'Counter';
      final startValue = c['start_value'] as int? ?? 1;
      final step = c['step'] as int? ?? 1;
      final scope = c['scope'] as String? ?? 'global';
      final createdAtStr =
          c['created_at'] as String? ?? DateTime.now().toIso8601String();
      final createdAtMs =
          DateTime.tryParse(createdAtStr)?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch;

      await _db.customStatement(
        'INSERT OR IGNORE INTO counters (id, name, start_value, step, scope, position, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [id, name, startValue, step, scope, i, createdAtMs],
      );
    }

    // Migrate global values
    final globalRaw = await _db.userSettingsDao.getValue(
      'counter_global_values',
    );
    if (globalRaw != null) {
      try {
        final globalMap = jsonDecode(globalRaw) as Map<String, dynamic>;
        for (final entry in globalMap.entries) {
          await _db.customStatement(
            'INSERT OR IGNORE INTO counter_values (counter_id, note_id, value) '
            'VALUES (?, ?, ?)',
            [entry.key, '', entry.value as int],
          );
        }
      } catch (_) {}
    }

    // Migrate per-note values
    final allSettings = await _db.userSettingsDao.getAllSettings();
    for (final entry in allSettings.entries) {
      if (!entry.key.startsWith('counter_note_values_')) continue;
      final noteId = entry.key.substring('counter_note_values_'.length);
      try {
        final noteMap = jsonDecode(entry.value) as Map<String, dynamic>;
        for (final valEntry in noteMap.entries) {
          await _db.customStatement(
            'INSERT OR IGNORE INTO counter_values (counter_id, note_id, value) '
            'VALUES (?, ?, ?)',
            [valEntry.key, noteId, valEntry.value as int],
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _migrateV7ToV8(Migrator m, GeneratedDatabase db) async {
    await _db.customStatement(
      'ALTER TABLE counters ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0',
    );
    await _db.customStatement(
      'ALTER TABLE counter_values ADD COLUMN position INTEGER NOT NULL DEFAULT 0',
    );
    await _db.customStatement(
      'ALTER TABLE counter_values ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0',
    );
  }

  /// v8→v9: Add expression indexes that back the per-parent name
  /// uniqueness queries. The new indexes cover
  /// `(COALESCE(parent_id,''), LOWER(TRIM(name)))` for folders and
  /// `(folder_id, LOWER(TRIM(title)))` for notes, both partial on
  /// `is_deleted = 0`. CREATE INDEX IF NOT EXISTS makes this idempotent
  /// for fresh installs (where createAllIndexes already created them).
  Future<void> _migrateV8ToV9(Migrator m, GeneratedDatabase db) async {
    await DatabaseIndexes(_db).createUniqueNameIndexes();
  }

  /// v9→v10: Add calendar events and public holidays tables.
  ///
  /// Uses raw `CREATE TABLE` statements that freeze the schema at the
  /// v10 shape (mirroring the v6 counters precedent). Any future column
  /// added to `CalendarEvents`/`PublicHolidaysTable` must ship its own
  /// migration step rather than relying on the live Drift declaration.
  Future<void> _migrateV9ToV10(Migrator m, GeneratedDatabase db) async {
    await _db.customStatement(
      'CREATE TABLE IF NOT EXISTS calendar_events ('
      '  id TEXT NOT NULL PRIMARY KEY, '
      '  title TEXT NOT NULL, '
      '  category TEXT NOT NULL, '
      '  start_date INTEGER NOT NULL, '
      '  all_day INTEGER NOT NULL DEFAULT 1, '
      '  icon_key TEXT, '
      '  rule_kind TEXT NOT NULL, '
      '  rule_payload TEXT, '
      '  created_at INTEGER NOT NULL, '
      '  updated_at INTEGER NOT NULL'
      ')',
    );
    await _db.customStatement(
      'CREATE TABLE IF NOT EXISTS public_holidays ('
      '  date INTEGER NOT NULL PRIMARY KEY, '
      '  name_key TEXT NOT NULL, '
      '  custom_label TEXT'
      ')',
    );
    await DatabaseIndexes(_db).createCalendarIndexes();
  }

  /// v10→v11: Extend `calendar_events` with three nullable columns.
  ///
  /// - `end_date INTEGER` (nullable) is an inclusive upper bound for
  ///   recurring rules. `NULL` keeps the historical "recurs forever"
  ///   behaviour, so existing rows remain semantically unchanged.
  /// - `start_minute INTEGER` (nullable, 0–1439) and `duration_minutes
  ///   INTEGER` (nullable) are reserved placeholders for future
  ///   time-of-day events. No production code writes them yet.
  ///
  /// All three are `ALTER TABLE ADD COLUMN`, which is cheap on SQLite and
  /// does not rewrite existing rows. Idempotency is achieved by querying
  /// `PRAGMA table_info` before each add so re-running the migration on a
  /// partially-upgraded DB cannot fail.
  Future<void> _migrateV10ToV11(Migrator m, GeneratedDatabase db) async {
    final existing = <String>{
      for (final row
          in await _db.customSelect('PRAGMA table_info(calendar_events)').get())
        row.read<String>('name'),
    };
    if (!existing.contains('end_date')) {
      await _db.customStatement(
        'ALTER TABLE calendar_events ADD COLUMN end_date INTEGER',
      );
    }
    if (!existing.contains('start_minute')) {
      await _db.customStatement(
        'ALTER TABLE calendar_events ADD COLUMN start_minute INTEGER',
      );
    }
    if (!existing.contains('duration_minutes')) {
      await _db.customStatement(
        'ALTER TABLE calendar_events ADD COLUMN duration_minutes INTEGER',
      );
    }
  }

  /// v11→v12: Add a free-form `description` column to `calendar_events`
  /// for longer-form per-event notes ("focus on hamstrings", etc.).
  /// Nullable so existing rows are unchanged. Idempotent via
  /// `PRAGMA table_info` so re-runs on a partially-upgraded DB are safe.
  Future<void> _migrateV11ToV12(Migrator m, GeneratedDatabase db) async {
    final existing = <String>{
      for (final row
          in await _db.customSelect('PRAGMA table_info(calendar_events)').get())
        row.read<String>('name'),
    };
    if (!existing.contains('description')) {
      await _db.customStatement(
        'ALTER TABLE calendar_events ADD COLUMN description TEXT',
      );
    }
  }

  /// v12→v13: Holiday profiles.
  ///
  /// Reshapes `public_holidays` to support multiple region/tradition
  /// presets (`generic`, `romania`, ...) chosen by the user:
  ///
  /// 1. Adds a `profile` column that records which preset seeded each
  ///    row, or the sentinel `'custom'` for user-added rows.
  /// 2. Replaces the date-only primary key with a composite
  ///    `(date, name_key)` PK so the same calendar day can carry
  ///    multiple distinct holidays (e.g. Easter Monday + a user note,
  ///    or two different built-ins that happen to coincide).
  ///
  /// Existing rows are back-filled: built-ins receive `profile='generic'`
  /// (matching the historical Catholic-leaning seed set) and customs
  /// receive `profile='custom'`. Idempotent via `PRAGMA table_info`.
  Future<void> _migrateV12ToV13(Migrator m, GeneratedDatabase db) async {
    final existing = <String>{
      for (final row
          in await _db.customSelect('PRAGMA table_info(public_holidays)').get())
        row.read<String>('name'),
    };
    // Already migrated (e.g. partial upgrade re-run).
    if (existing.contains('profile')) return;

    // SQLite cannot change a primary key in place — rebuild the table.
    await _db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await _db.customStatement(
        'CREATE TABLE public_holidays_new ('
        '  date INTEGER NOT NULL, '
        '  name_key TEXT NOT NULL, '
        "  profile TEXT NOT NULL DEFAULT 'generic', "
        '  custom_label TEXT, '
        '  PRIMARY KEY (date, name_key)'
        ')',
      );
      await _db.customStatement(
        'INSERT INTO public_holidays_new (date, name_key, profile, custom_label) '
        'SELECT date, name_key, '
        "  CASE WHEN name_key = 'custom' THEN 'custom' ELSE 'generic' END, "
        '  custom_label '
        'FROM public_holidays',
      );
      await _db.customStatement('DROP TABLE public_holidays');
      await _db.customStatement(
        'ALTER TABLE public_holidays_new RENAME TO public_holidays',
      );
    } finally {
      await _db.customStatement('PRAGMA foreign_keys = ON');
    }
  }

  /// v13→v14: Add a nullable `note_id` column to `calendar_events` so an
  /// event can link to a workout note (`notes.id`). `NULL` keeps the
  /// historical "no linked note" behaviour, so existing rows are
  /// semantically unchanged. The folder is resolved from the note at
  /// navigation time, so no foreign key / index is added here. Idempotent
  /// via `PRAGMA table_info` so a partial-upgrade re-run cannot fail.
  Future<void> _migrateV13ToV14(Migrator m, GeneratedDatabase db) async {
    final existing = <String>{
      for (final row
          in await _db.customSelect('PRAGMA table_info(calendar_events)').get())
        row.read<String>('name'),
    };
    if (!existing.contains('note_id')) {
      await _db.customStatement(
        'ALTER TABLE calendar_events ADD COLUMN note_id TEXT',
      );
    }
  }

  /// v14→v15: User-creatable event categories.
  ///
  /// Creates the `calendar_categories` table. Built-in categories are NOT
  /// seeded here — `CategoryService` seeds them on every launch with
  /// insert-if-missing semantics (stable ids equal to the historical
  /// `CalendarEventCategory` enum names). Because existing events already
  /// store those names in `calendar_events.category`, they link to the
  /// seeded built-ins with no data migration. Idempotent via
  /// `CREATE TABLE IF NOT EXISTS`; the column shape mirrors Drift's generated
  /// DDL so fresh installs (via `createAll`) and upgrades agree.
  Future<void> _migrateV14ToV15(Migrator m, GeneratedDatabase db) async {
    await _db.customStatement(
      'CREATE TABLE IF NOT EXISTS calendar_categories ('
      '  id TEXT NOT NULL, '
      '  name TEXT NOT NULL, '
      '  color_value INTEGER NOT NULL, '
      '  icon_key TEXT NOT NULL, '
      '  sort_order INTEGER NOT NULL DEFAULT 0, '
      '  is_built_in INTEGER NOT NULL DEFAULT 0 CHECK (is_built_in IN (0, 1)), '
      '  created_at INTEGER NOT NULL, '
      '  updated_at INTEGER NOT NULL, '
      '  PRIMARY KEY (id)'
      ')',
    );
  }

  /// v15→v16: Per-event color & priority on `calendar_events`.
  ///
  /// - `color_value INTEGER` (nullable) is an optional ARGB override; `NULL`
  ///   keeps the historical "use the category color" behaviour.
  /// - `tint_icon INTEGER NOT NULL DEFAULT 1` decides whether the color also
  ///   tints the icon. Existing rows default to `1` (tint both).
  /// - `priority INTEGER NOT NULL DEFAULT 3` orders bars / summary entries.
  ///   Existing rows default to the neutral middle priority.
  ///
  /// All three are `ALTER TABLE ADD COLUMN`, guarded by `PRAGMA table_info`
  /// so a partial-upgrade re-run cannot fail.
  Future<void> _migrateV15ToV16(Migrator m, GeneratedDatabase db) async {
    final existing = <String>{
      for (final row
          in await _db.customSelect('PRAGMA table_info(calendar_events)').get())
        row.read<String>('name'),
    };
    if (!existing.contains('color_value')) {
      await _db.customStatement(
        'ALTER TABLE calendar_events ADD COLUMN color_value INTEGER',
      );
    }
    if (!existing.contains('tint_icon')) {
      await _db.customStatement(
        'ALTER TABLE calendar_events ADD COLUMN tint_icon INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (!existing.contains('priority')) {
      await _db.customStatement(
        'ALTER TABLE calendar_events ADD COLUMN priority INTEGER NOT NULL DEFAULT 3',
      );
    }
  }

  /// v16→v17: Add a `suppressed` flag to `public_holidays`.
  ///
  /// Lets a user remove a single dated holiday occurrence and have it
  /// stay removed: suppressed built-in rows are kept (not deleted) so the
  /// seeder's insert-if-missing pass never resurrects them on the next
  /// app start or after a backup restore. `ALTER TABLE ADD COLUMN` with a
  /// `NOT NULL DEFAULT 0`, guarded by `PRAGMA table_info` so a
  /// partial-upgrade re-run cannot fail.
  Future<void> _migrateV16ToV17(Migrator m, GeneratedDatabase db) async {
    final existing = <String>{
      for (final row
          in await _db.customSelect('PRAGMA table_info(public_holidays)').get())
        row.read<String>('name'),
    };
    if (!existing.contains('suppressed')) {
      await _db.customStatement(
        'ALTER TABLE public_holidays ADD COLUMN suppressed INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  /// v17→v18: Invert event priority semantics — 1 is now the highest.
  ///
  /// Every stored priority flips (`p -> 6 - p`) so an event the user marked
  /// "Highest" stays highest under the new reading. Data-only migration:
  /// drift runs it inside the upgrade transaction with the version bump, so
  /// the self-inverse `6 - p` can never be applied twice. The persisted
  /// agenda priority filter flips with it, and the superseded
  /// single-threshold filter key is folded in and removed (old meaning
  /// "priority >= t on a 5-is-highest scale" becomes the set `{1..6-t}`).
  Future<void> _migrateV17ToV18(Migrator m, GeneratedDatabase db) async {
    await _db.customStatement(
      'UPDATE calendar_events SET priority = 6 - priority '
      'WHERE priority BETWEEN 1 AND 5',
    );

    String? settingValue(List<QueryRow> rows) =>
        rows.isEmpty ? null : rows.first.read<String?>('value');

    int? flip(int? p) => p == null || p < 1 || p > 5 ? null : 6 - p;

    final prioritiesRows = await _db
        .customSelect(
          "SELECT value FROM user_settings "
          "WHERE key = 'calendar_upcoming_priorities'",
        )
        .get();
    final rawPriorities = settingValue(prioritiesRows);
    if (rawPriorities != null && rawPriorities.isNotEmpty) {
      final flipped =
          rawPriorities
              .split(',')
              .map((part) => flip(int.tryParse(part.trim())))
              .whereType<int>()
              .toList()
            ..sort();
      await _db.customStatement(
        "UPDATE user_settings SET value = ? "
        "WHERE key = 'calendar_upcoming_priorities'",
        [flipped.join(',')],
      );
    } else {
      final legacyRows = await _db
          .customSelect(
            "SELECT value FROM user_settings "
            "WHERE key = 'calendar_upcoming_min_priority'",
          )
          .get();
      final threshold = int.tryParse(settingValue(legacyRows) ?? '');
      if (threshold != null && threshold > 1 && threshold <= 5) {
        final converted = [for (var p = 1; p <= 6 - threshold; p++) p];
        // Drift's default DateTime storage is unix SECONDS, not millis.
        await _db.customStatement(
          "INSERT OR REPLACE INTO user_settings (key, value, updated_at) "
          "VALUES ('calendar_upcoming_priorities', ?, ?)",
          [converted.join(','), DateTime.now().millisecondsSinceEpoch ~/ 1000],
        );
      }
    }
    await _db.customStatement(
      "DELETE FROM user_settings WHERE key = 'calendar_upcoming_min_priority'",
    );
  }

  /// v18→v19: Add `retroactive` to `calendar_events`.
  ///
  /// Lets a recurring rule also produce occurrences before its start date
  /// (a yearly check-up added today then shows in previous years too).
  /// `NOT NULL DEFAULT 0` means every existing event keeps the classic
  /// forward-only behaviour, and the `PRAGMA table_info` guard makes a
  /// partial-upgrade re-run safe.
  Future<void> _migrateV18ToV19(Migrator m, GeneratedDatabase db) async {
    final existing = <String>{
      for (final row
          in await _db.customSelect('PRAGMA table_info(calendar_events)').get())
        row.read<String>('name'),
    };
    if (!existing.contains('retroactive')) {
      await _db.customStatement(
        'ALTER TABLE calendar_events ADD COLUMN retroactive INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  /// v19→v20: Add `count_occurrences` to `calendar_events`.
  ///
  /// Display-only flag: each occurrence of a periodic rule shows the time
  /// elapsed since the start date (a birthday anchored on the birth date
  /// shows the age). `NOT NULL DEFAULT 0` keeps every existing event
  /// unchanged, and the `PRAGMA table_info` guard makes a partial-upgrade
  /// re-run safe.
  Future<void> _migrateV19ToV20(Migrator m, GeneratedDatabase db) async {
    final existing = <String>{
      for (final row
          in await _db.customSelect('PRAGMA table_info(calendar_events)').get())
        row.read<String>('name'),
    };
    if (!existing.contains('count_occurrences')) {
      await _db.customStatement(
        'ALTER TABLE calendar_events ADD COLUMN count_occurrences INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  /// v20→v21: Add `count_style` to `calendar_events`.
  ///
  /// How a counted occurrence is labelled: `numbered` ("Day 1", "Week 3" —
  /// the start day is the first) or `elapsed` ("30 years" — the
  /// birthday/anniversary style, start day unlabelled). A separate step from
  /// v20 because that migration had already run on devices when the style
  /// choice was added; same additive shape, same `PRAGMA` guard.
  Future<void> _migrateV20ToV21(Migrator m, GeneratedDatabase db) async {
    final existing = <String>{
      for (final row
          in await _db.customSelect('PRAGMA table_info(calendar_events)').get())
        row.read<String>('name'),
    };
    if (!existing.contains('count_style')) {
      await _db.customStatement(
        "ALTER TABLE calendar_events ADD COLUMN count_style TEXT NOT NULL DEFAULT 'numbered'",
      );
    }
  }
}
