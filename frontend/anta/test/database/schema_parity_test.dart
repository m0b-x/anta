import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';

/// Guards the invariant that the **create path and the migration path agree**.
///
/// This is not hypothetical. `idx_folders_position` / `idx_notes_position`
/// were introduced inside the v3→v4 migration and never added to
/// `DatabaseIndexes.createAllIndexes`, so for years they existed only on
/// databases that had *upgraded* through v4. Every fresh install — a new user,
/// or any database added through the multi-database feature — ran the folder
/// content page's primary query (`ORDER BY position`) as a scan-and-sort. It
/// was invisible until a folder grew large. This test fails on that.
///
/// The declared set is scraped from the source rather than hardcoded, so a
/// hand-maintained golden list can't rot: adding an index anywhere under
/// `lib/database/` immediately obliges the create path to produce it.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  test(
    'every index declared in lib/database is created on a fresh install',
    () async {
      final declared = _declaredNames(
        RegExp(r'CREATE\s+INDEX\s+IF\s+NOT\s+EXISTS\s+([a-z_0-9]+)'),
      );
      // Sanity: the scrape itself must not silently match nothing.
      expect(declared, isNotEmpty, reason: 'index scrape found nothing');

      final actual = await indexNames(db);
      expect(
        declared.difference(actual),
        isEmpty,
        reason:
            'These indexes exist somewhere in lib/database but a freshly created '
            'database does not have them. An index reachable only from a '
            'migration leaves every fresh install slower than an upgraded one. '
            'Add it to DatabaseIndexes.createAllIndexes().',
      );
    },
  );

  test(
    'every table declared in lib/database is created on a fresh install',
    () async {
      final declared = _declaredNames(
        RegExp(
          r'CREATE\s+(?:VIRTUAL\s+)?TABLE\s+IF\s+NOT\s+EXISTS\s+([a-z_0-9]+)',
        ),
      );
      expect(declared, isNotEmpty, reason: 'table scrape found nothing');

      final actual = await tableNames(db);
      expect(
        declared.difference(actual),
        isEmpty,
        reason:
            'A table created by a migration is missing from the fresh-create '
            'path. Add it to the @DriftDatabase tables list.',
      );
    },
  );

  test('the occurrence table matches its frozen migration DDL', () async {
    // The migration writes raw DDL frozen at v24 rather than using
    // `m.createTable`, precisely so upgraders and fresh installs cannot drift.
    // That only pays off if something checks it. v28 grew the CRDT block onto
    // it by ALTER, which is the same agreement under more pressure.
    final columns = await db
        .customSelect('PRAGMA table_info(calendar_event_occurrences)')
        .get();
    final byName = {for (final row in columns) row.read<String>('name'): row};

    expect(byName.keys.toSet(), {
      'event_id',
      'day',
      'description',
      'created_at',
      'updated_at',
      'hlc_timestamp',
      'device_id',
      'version',
      'is_deleted',
      'deleted_at',
    });
    for (final name in byName.keys) {
      // `deleted_at` is the single nullable column — the one place the blanket
      // loop does not apply. `ContentChunks` skips it entirely, which is
      // exactly the variant this table must not become.
      expect(
        byName[name]!.read<int>('notnull'),
        name == 'deleted_at' ? 0 : 1,
        reason: name == 'deleted_at'
            ? 'deleted_at must stay nullable'
            : '$name should be NOT NULL',
      );
    }
    expect(byName['event_id']!.read<String>('type'), 'TEXT');
    expect(byName['day']!.read<String>('type'), 'INTEGER');
    // Non-nullable: the row's existence is the override, and `''` is a
    // meaningful value — a reset tombstones instead of blanking.
    expect(byName['description']!.read<String>('type'), 'TEXT');
    expect(byName['hlc_timestamp']!.read<String>('type'), 'TEXT');
    expect(byName['device_id']!.read<String>('type'), 'TEXT');
    // The `calendar_events` variant, not the absence table's: v28 added these
    // to a *populated* table, so `ALTER TABLE … ADD COLUMN NOT NULL` demanded a
    // default and the Drift declaration had to grow the same one. `''` is
    // transitional — the migration backfills it in the same run.
    expect(byName['hlc_timestamp']!.read<String>('dflt_value'), "''");
    expect(byName['device_id']!.read<String>('dflt_value'), "''");
    expect(byName['version']!.read<String>('dflt_value'), '1');
    expect(byName['is_deleted']!.read<String>('dflt_value'), '0');
    // Composite primary key, in order — this is what gives the point lookup
    // and the per-event cascade an index without declaring one.
    expect(byName['event_id']!.read<int>('pk'), 1);
    expect(byName['day']!.read<int>('pk'), 2);
  });

  test('the absence table matches its frozen migration DDL', () async {
    // Frozen at v26 for the same reason as the occurrence table, but this one
    // also carries the five CRDT columns — the first frozen-DDL table in the
    // codebase to do so (notes/folders are v1 `createAll`-only). Their exact
    // shape is what cloud-sync phase-02 wires transport to, so a drift here is
    // a schema retrofit later.
    final columns = await db
        .customSelect('PRAGMA table_info(calendar_event_absences)')
        .get();
    final byName = {for (final row in columns) row.read<String>('name'): row};

    expect(byName.keys.toSet(), {
      'event_id',
      'day',
      'status',
      'created_at',
      'updated_at',
      'hlc_timestamp',
      'device_id',
      'version',
      'is_deleted',
      'deleted_at',
    });
    for (final name in byName.keys) {
      // `deleted_at` is the single nullable column — the one place the
      // blanket loop above does not apply. `ContentChunks` skips it entirely,
      // which is exactly the variant this table must not become.
      expect(
        byName[name]!.read<int>('notnull'),
        name == 'deleted_at' ? 0 : 1,
        reason: name == 'deleted_at'
            ? 'deleted_at must stay nullable'
            : '$name should be NOT NULL',
      );
    }
    expect(byName['event_id']!.read<String>('type'), 'TEXT');
    expect(byName['day']!.read<String>('type'), 'INTEGER');
    // v37: a live row is an explicit status, not the bare fact of a mark. The
    // default is what every pre-v37 row already meant, which is why the
    // migration needs no backfill.
    expect(byName['status']!.read<String>('type'), 'TEXT');
    expect(byName['status']!.read<String>('dflt_value'), "'missed'");
    expect(byName['hlc_timestamp']!.read<String>('type'), 'TEXT');
    expect(byName['device_id']!.read<String>('type'), 'TEXT');
    // No DEFAULT on the identity columns on purpose: every insert must stamp
    // them or fail, which is what keeps CRDT stamping out of the service.
    expect(byName['hlc_timestamp']!.readNullable<String>('dflt_value'), isNull);
    expect(byName['device_id']!.readNullable<String>('dflt_value'), isNull);
    expect(byName['version']!.read<String>('dflt_value'), '1');
    expect(byName['is_deleted']!.read<String>('dflt_value'), '0');
    // Composite primary key, in order — the automatic index it gives SQLite is
    // why this table declares none of its own.
    expect(byName['event_id']!.read<int>('pk'), 1);
    expect(byName['day']!.read<int>('pk'), 2);
  });

  test('the skip table matches its frozen migration DDL', () async {
    // Frozen at v30, and the v26 absence shape minus the `status` column v37
    // added there — same composite key, same CRDT block, no DEFAULT on the
    // identity columns. The two tables carrying the same *storage* for
    // different *meanings* is the point; a skip is one fact, so it never grew
    // a status, and a divergence in the shared block would be the first sign
    // someone had started treating them as one thing.
    final columns = await db
        .customSelect('PRAGMA table_info(calendar_event_skips)')
        .get();
    final byName = {for (final row in columns) row.read<String>('name'): row};

    expect(byName.keys.toSet(), {
      'event_id',
      'day',
      'created_at',
      'updated_at',
      'hlc_timestamp',
      'device_id',
      'version',
      'is_deleted',
      'deleted_at',
    });
    for (final name in byName.keys) {
      expect(
        byName[name]!.read<int>('notnull'),
        name == 'deleted_at' ? 0 : 1,
        reason: name == 'deleted_at'
            ? 'deleted_at must stay nullable'
            : '$name should be NOT NULL',
      );
    }
    expect(byName['event_id']!.read<String>('type'), 'TEXT');
    expect(byName['day']!.read<String>('type'), 'INTEGER');
    expect(byName['hlc_timestamp']!.read<String>('type'), 'TEXT');
    expect(byName['device_id']!.read<String>('type'), 'TEXT');
    // Born with the CRDT block rather than growing it by ALTER, so no
    // transitional `''` default — every insert must stamp identity or fail.
    expect(byName['hlc_timestamp']!.readNullable<String>('dflt_value'), isNull);
    expect(byName['device_id']!.readNullable<String>('dflt_value'), isNull);
    expect(byName['version']!.read<String>('dflt_value'), '1');
    expect(byName['is_deleted']!.read<String>('dflt_value'), '0');
    expect(byName['event_id']!.read<int>('pk'), 1);
    expect(byName['day']!.read<int>('pk'), 2);
  });

  test('the template table matches its frozen migration DDL', () async {
    // Frozen at v29. Unlike the two tables above this one was born with the
    // CRDT block rather than growing it by ALTER, so its identity columns must
    // carry **no** DEFAULT — the v26 absence shape, not the v27/v28 one. That
    // distinction is the whole point of the assertion: a `DEFAULT ''` sneaking
    // in here would mean an insert could silently store an unidentified row.
    final columns = await db
        .customSelect('PRAGMA table_info(calendar_event_templates)')
        .get();
    final byName = {for (final row in columns) row.read<String>('name'): row};

    expect(byName.keys.toSet(), {
      'id',
      'name',
      'category',
      'sort_order',
      'rule_kind',
      'rule_payload',
      'start_minute',
      'duration_minutes',
      'description',
      'icon_key',
      'color_value',
      'tint_icon',
      'priority',
      'retroactive',
      'count_occurrences',
      'count_style',
      'tracks_presence',
      'assume_absent',
      'per_occurrence_descriptions',
      'created_at',
      'updated_at',
      'hlc_timestamp',
      'device_id',
      'version',
      'is_deleted',
      'deleted_at',
    });

    // Nullable exactly where `null` carries meaning: fall back to the
    // category, be all-day, have no description, carry no rule data.
    const nullable = {
      'rule_payload',
      'start_minute',
      'duration_minutes',
      'description',
      'icon_key',
      'color_value',
      'deleted_at',
    };
    for (final name in byName.keys) {
      expect(
        byName[name]!.read<int>('notnull'),
        nullable.contains(name) ? 0 : 1,
        reason: nullable.contains(name)
            ? '$name must stay nullable'
            : '$name should be NOT NULL',
      );
    }

    expect(byName['id']!.read<String>('type'), 'TEXT');
    expect(byName['name']!.read<String>('type'), 'TEXT');
    expect(byName['category']!.read<String>('type'), 'TEXT');
    expect(byName['hlc_timestamp']!.read<String>('type'), 'TEXT');
    expect(byName['device_id']!.read<String>('type'), 'TEXT');

    // Every default that decides what an un-set column means at apply time.
    expect(byName['sort_order']!.read<String>('dflt_value'), '0');
    expect(byName['rule_kind']!.read<String>('dflt_value'), "'oneTime'");
    expect(byName['tint_icon']!.read<String>('dflt_value'), '1');
    expect(byName['priority']!.read<String>('dflt_value'), '3');
    expect(byName['retroactive']!.read<String>('dflt_value'), '0');
    expect(byName['count_occurrences']!.read<String>('dflt_value'), '0');
    expect(byName['count_style']!.read<String>('dflt_value'), "'numbered'");
    expect(byName['tracks_presence']!.read<String>('dflt_value'), '0');
    // v37: templates carry the presence-default flag but never a from-date.
    expect(byName['assume_absent']!.read<String>('dflt_value'), '0');
    expect(
      byName['per_occurrence_descriptions']!.read<String>('dflt_value'),
      '0',
    );
    expect(byName['version']!.read<String>('dflt_value'), '1');
    expect(byName['is_deleted']!.read<String>('dflt_value'), '0');
    // No DEFAULT on the identity columns: every insert must stamp them or
    // fail, which is what keeps CRDT stamping out of the service.
    expect(byName['hlc_timestamp']!.readNullable<String>('dflt_value'), isNull);
    expect(byName['device_id']!.readNullable<String>('dflt_value'), isNull);

    expect(byName['id']!.read<int>('pk'), 1);
  });

  test('the filter preset table matches its frozen migration DDL', () async {
    // Frozen at v35. Born with the CRDT block like the template table above,
    // so the same distinction applies: **no** DEFAULT on the identity columns,
    // or an insert could silently store an unidentified row.
    final columns = await db
        .customSelect('PRAGMA table_info(calendar_filter_presets)')
        .get();
    final byName = {for (final row in columns) row.read<String>('name'): row};

    expect(byName.keys.toSet(), {
      'id',
      'name',
      'filters',
      'sort_order',
      'created_at',
      'updated_at',
      'hlc_timestamp',
      'device_id',
      'version',
      'is_deleted',
      'deleted_at',
    });

    for (final name in byName.keys) {
      // `deleted_at` is the single nullable column. `filters` in particular is
      // NOT NULL: an empty string is a legal encoding ("nothing filtered"), so
      // a null would be a second way to say the same thing.
      expect(
        byName[name]!.read<int>('notnull'),
        name == 'deleted_at' ? 0 : 1,
        reason: name == 'deleted_at'
            ? 'deleted_at must stay nullable'
            : '$name should be NOT NULL',
      );
    }

    expect(byName['id']!.read<String>('type'), 'TEXT');
    expect(byName['name']!.read<String>('type'), 'TEXT');
    // The whole filter set as one JSON blob — see the table declaration for
    // why this is not a column per axis.
    expect(byName['filters']!.read<String>('type'), 'TEXT');
    expect(byName['hlc_timestamp']!.read<String>('type'), 'TEXT');
    expect(byName['device_id']!.read<String>('type'), 'TEXT');

    expect(byName['sort_order']!.read<String>('dflt_value'), '0');
    expect(byName['version']!.read<String>('dflt_value'), '1');
    expect(byName['is_deleted']!.read<String>('dflt_value'), '0');
    expect(byName['hlc_timestamp']!.readNullable<String>('dflt_value'), isNull);
    expect(byName['device_id']!.readNullable<String>('dflt_value'), isNull);

    expect(byName['id']!.read<int>('pk'), 1);
  });

  test('the alert table matches its frozen migration DDL', () async {
    // Frozen at v40, born with the CRDT block — so the v29/v32 shape, not the
    // v27 one: **no** DEFAULT on the identity columns, because this is a new
    // table where every insert must stamp them or fail, and `deleted_at` is
    // the only nullable member of the block.
    final columns = await db
        .customSelect('PRAGMA table_info(calendar_event_alerts)')
        .get();
    final byName = {for (final row in columns) row.read<String>('name'): row};

    expect(byName.keys.toSet(), {
      'id',
      'event_id',
      'mode',
      // Both offset sets live on every row: the planner picks by the derived
      // `event.time == null`, so an event flipped to all-day keeps alerts that
      // still mean something. Dropping either column would make that flip
      // lossy.
      'offset_minutes',
      'days_before',
      'day_minute',
      'sound',
      'enabled',
      'created_at',
      'updated_at',
      'hlc_timestamp',
      'device_id',
      'version',
      'is_deleted',
      'deleted_at',
    });

    for (final name in byName.keys) {
      final nullable = const {'day_minute', 'sound', 'deleted_at'};
      expect(
        byName[name]!.read<int>('notnull'),
        nullable.contains(name) ? 0 : 1,
        reason: nullable.contains(name)
            ? 'calendar_event_alerts.$name must stay nullable'
            : 'calendar_event_alerts.$name should be NOT NULL',
      );
    }

    // NULL is a meaning of its own here — *use the settings default* — so a
    // `NOT NULL DEFAULT 540` would freeze every alert at 09:00 and make the
    // setting inert for everything already saved.
    expect(byName['day_minute']!.readNullable<String>('dflt_value'), isNull);

    expect(byName['mode']!.read<String>('dflt_value'), "'notify'");
    expect(byName['offset_minutes']!.read<String>('dflt_value'), '0');
    expect(byName['days_before']!.read<String>('dflt_value'), '0');
    // An alert exists to fire; a row arrives armed and the hub switch is what
    // turns it off.
    expect(byName['enabled']!.read<String>('dflt_value'), '1');
    expect(byName['version']!.read<String>('dflt_value'), '1');
    expect(byName['is_deleted']!.read<String>('dflt_value'), '0');
    expect(byName['hlc_timestamp']!.readNullable<String>('dflt_value'), isNull);
    expect(byName['device_id']!.readNullable<String>('dflt_value'), isNull);
    expect(byName['id']!.read<int>('pk'), 1);
  });

  test('the registration table matches its frozen migration DDL', () async {
    // The one calendar table with **no** CRDT block, and that is the feature:
    // it mirrors a single device's OS scheduler, is never exported or merged,
    // and hard deletes are allowed because any reconcile can rebuild it.
    final columns = await db
        .customSelect('PRAGMA table_info(alert_registrations)')
        .get();
    final byName = {for (final row in columns) row.read<String>('name'): row};

    expect(byName.keys.toSet(), {
      'os_id',
      'alert_id',
      'event_id',
      'day',
      'fire_at',
      'kind',
      'state',
      'backend',
      'created_at',
      'updated_at',
    });

    for (final name in byName.keys) {
      expect(
        byName[name]!.read<int>('notnull'),
        1,
        reason: 'alert_registrations.$name should be NOT NULL',
      );
    }

    // `day` is a date-only **UTC** day and `fire_at` a **local** instant, both
    // in epoch milliseconds. Storing them as Drift `DateTime`s would put them
    // through one implicit conversion (and unix *seconds*), which is exactly
    // the shift the calendar's date helpers exist to undo.
    expect(byName['day']!.read<String>('type'), 'INTEGER');
    expect(byName['fire_at']!.read<String>('type'), 'INTEGER');

    expect(byName['kind']!.read<String>('dflt_value'), "'scheduled'");
    expect(byName['state']!.read<String>('dflt_value'), "'pending'");
    // No default: the gateway that placed the registration is the only thing
    // that knows which backend holds it, so a row must say.
    expect(byName['backend']!.readNullable<String>('dflt_value'), isNull);
    expect(byName['os_id']!.read<int>('pk'), 1);
  });

  test('the vocabulary tables match their frozen migration DDL', () async {
    // Frozen at v32, born with the CRDT block — so the v29 template shape, not
    // the v27/v28 one: no DEFAULT on the identity columns, `deleted_at` the
    // only nullable. Both tables are asserted together because a term is
    // meaningless without its list, and the two must tombstone alike.
    for (final table in ['vocabularies', 'vocabulary_items']) {
      final columns = await db.customSelect('PRAGMA table_info($table)').get();
      final byName = {for (final row in columns) row.read<String>('name'): row};

      expect(byName.keys.toSet(), {
        'id',
        if (table == 'vocabularies') ...['name', 'is_enabled'],
        if (table == 'vocabulary_items') ...['vocabulary_id', 'term'],
        'sort_order',
        'created_at',
        'updated_at',
        'hlc_timestamp',
        'device_id',
        'version',
        'is_deleted',
        'deleted_at',
      }, reason: '$table columns');

      for (final name in byName.keys) {
        expect(
          byName[name]!.read<int>('notnull'),
          name == 'deleted_at' ? 0 : 1,
          reason: name == 'deleted_at'
              ? '$table.deleted_at must stay nullable'
              : '$table.$name should be NOT NULL',
        );
      }

      expect(byName['id']!.read<String>('type'), 'TEXT');
      expect(byName['hlc_timestamp']!.read<String>('type'), 'TEXT');
      expect(byName['device_id']!.read<String>('type'), 'TEXT');
      expect(byName['sort_order']!.read<String>('dflt_value'), '0');
      expect(byName['version']!.read<String>('dflt_value'), '1');
      expect(byName['is_deleted']!.read<String>('dflt_value'), '0');
      // No DEFAULT on the identity columns: every insert must stamp them or
      // fail, which is what keeps CRDT stamping out of the service.
      expect(
        byName['hlc_timestamp']!.readNullable<String>('dflt_value'),
        isNull,
      );
      expect(byName['device_id']!.readNullable<String>('dflt_value'), isNull);
      expect(byName['id']!.read<int>('pk'), 1);
    }

    final vocabularies = await db
        .customSelect('PRAGMA table_info(vocabularies)')
        .get();
    final byName = {
      for (final row in vocabularies) row.read<String>('name'): row,
    };
    // A list is offered until the user says otherwise; an install that
    // upgrades mid-edit must not silently mute its own vocabularies.
    expect(byName['is_enabled']!.read<String>('dflt_value'), '1');
  });

  test('the event table carries the v27 CRDT block', () async {
    // `calendar_events` is the one CRDT table whose identity columns have a
    // DEFAULT: v27 added them to a *populated* table, and SQLite's
    // `ALTER TABLE … ADD COLUMN NOT NULL` demands one. The Drift declaration
    // then has to match, so the create path grows the same defaults — which is
    // exactly the create-vs-migrate agreement this file exists to pin.
    //
    // `''` is transitional, never a valid stored identity: the migration
    // backfills it in the same run and `CalendarEventDao` stamps every write.
    final columns = await db
        .customSelect('PRAGMA table_info(calendar_events)')
        .get();
    final byName = {for (final row in columns) row.read<String>('name'): row};

    expect(
      byName.keys,
      containsAll([
        'hlc_timestamp',
        'device_id',
        'version',
        'is_deleted',
        'deleted_at',
        // v28's per-event description scope. Added by ALTER on upgraders and by
        // the Drift declaration on fresh installs — the same two paths this
        // file exists to hold together.
        'per_occurrence_descriptions',
        // v34's day-rail override. Same two paths, and the one column here
        // whose *nullability* is the feature — see below.
        'show_in_day_rail',
        // v37's presence default and its optional lower bound. The pair is
        // the point: the flag says unmarked days read as missed, the date says
        // from when, and NULL there means the whole event.
        'assume_absent',
        'assume_absent_from',
        // v40's "this event exists only until its alarm is acknowledged".
        // Same two paths again, and the same no-backfill argument: an event
        // that could not carry an alarm could not be removed by one.
        'remove_after_alert',
      ]),
    );
    expect(byName['remove_after_alert']!.read<int>('notnull'), 1);
    expect(byName['remove_after_alert']!.read<String>('dflt_value'), '0');
    expect(byName['per_occurrence_descriptions']!.read<int>('notnull'), 1);
    // Off is the pre-v28 reading: one shared description for every day.
    expect(
      byName['per_occurrence_descriptions']!.read<String>('dflt_value'),
      '0',
    );
    // The schema's first nullable bool, and it must stay one: NULL is the
    // *auto* state, distinct from both an explicit `true` and an explicit
    // `false`. A `NOT NULL DEFAULT 0` on either path would collapse auto into
    // "never" for every event that never opted in.
    expect(byName['show_in_day_rail']!.read<int>('notnull'), 0);
    expect(
      byName['show_in_day_rail']!.readNullable<String>('dflt_value'),
      isNull,
    );
    // Off is the pre-v37 reading: implicit attendance, which is what every
    // tracked event meant before the flag existed — so the migration needs no
    // backfill on either path.
    expect(byName['assume_absent']!.read<int>('notnull'), 1);
    expect(byName['assume_absent']!.read<String>('dflt_value'), '0');
    // Nullable with **no** default, unlike the flag beside it: NULL is "the
    // whole event", a meaning of its own rather than an unset value. A
    // `NOT NULL DEFAULT 0` here would date every flip to the epoch and make
    // `assumesAbsentOn` true for all of recorded time.
    expect(byName['assume_absent_from']!.read<int>('notnull'), 0);
    expect(
      byName['assume_absent_from']!.readNullable<String>('dflt_value'),
      isNull,
    );
    for (final name in [
      'hlc_timestamp',
      'device_id',
      'version',
      'is_deleted',
    ]) {
      expect(
        byName[name]!.read<int>('notnull'),
        1,
        reason: '$name should be NOT NULL',
      );
    }
    // The single nullable column of the block, and the reason a tombstone can
    // say *when* — `ContentChunks` drops it, which is the variant this must
    // not become.
    expect(byName['deleted_at']!.read<int>('notnull'), 0);
    expect(byName['deleted_at']!.readNullable<String>('dflt_value'), isNull);

    expect(byName['hlc_timestamp']!.read<String>('type'), 'TEXT');
    expect(byName['device_id']!.read<String>('type'), 'TEXT');
    expect(byName['hlc_timestamp']!.read<String>('dflt_value'), "''");
    expect(byName['device_id']!.read<String>('dflt_value'), "''");
    // A pre-v27 event is a live, never-merged row — which is what it was.
    expect(byName['version']!.read<String>('dflt_value'), '1');
    expect(byName['is_deleted']!.read<String>('dflt_value'), '0');
  });

  test('the event start-date index is partial on live rows', () async {
    // The v27 migration drops the full index by name before recreating it, so
    // an upgraded database and a fresh one hold the same definition. The
    // name-only scrape above cannot see that difference; this can.
    final sql = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_calendar_events_start_date'",
        )
        .getSingle();
    expect(sql.read<String>('sql'), contains('WHERE is_deleted = 0'));
  });

  test(
    'the note title index stores the expression it was declared with',
    () async {
      // The name scrape above only proves a fresh install has an index called
      // this. This reads the **stored definition** back out of `sqlite_master`:
      // an expression index is unusable unless a query repeats the expression
      // exactly, so `LOWER(TRIM(title))` has to have survived verbatim into what
      // SQLite actually built. And the predicate has to stay a literal: Drift's
      // `.equals(false)` would emit a bound `?`, which older SQLite refuses to
      // match against a partial index's `WHERE`.
      //
      // What this cannot see is the *query* side or the sibling index — for
      // those, `query_plan_test.dart` asserts the DAO's own SQL text, and the
      // source scrape below asserts the two declarations agree.
      final sql = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_notes_ltitle'",
          )
          .getSingle();
      expect(sql.read<String>('sql'), contains('LOWER(TRIM(title))'));
      expect(sql.read<String>('sql'), contains('WHERE is_deleted = 0'));
    },
  );

  test('both title indexes are declared with one spelling', () {
    // `idx_notes_folder_ltitle` serves the per-folder uniqueness check and
    // `idx_notes_ltitle` the wiki-link resolver. They are only both
    // index-served while they spell the title expression character for
    // character alike — one of them drifting to, say, `lower(trim(title))`
    // costs that lookup its index with no error anywhere.
    final source = File(
      'lib/database/migrations/database_indexes.dart',
    ).readAsStringSync();
    for (final method in ['createUniqueNameIndexes', 'createNoteTitleIndex']) {
      expect(
        _methodBody(source, method),
        contains('LOWER(TRIM(title))'),
        reason:
            '$method no longer spells the title expression as '
            'LOWER(TRIM(title)), so the two indexes have diverged',
      );
    }
  });
}

/// The body of `Future<void> [name]() async { … }` in [source], from its
/// opening brace to the matching close.
///
/// Starts at the signature so the doc comment above it — which quotes the very
/// expression being asserted — cannot satisfy the assertion by itself.
String _methodBody(String source, String name) {
  final start = source.indexOf('Future<void> $name(');
  expect(
    start,
    isNonNegative,
    reason: '$name not found in database_indexes.dart',
  );
  final open = source.indexOf('{', start);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  fail('$name has no closing brace');
}

/// All capture-group-1 matches of [pattern] across `lib/database/**.dart`,
/// with `//` comments stripped first so prose mentioning a statement (there is
/// one, describing why `IF NOT EXISTS` matters) is not mistaken for a
/// declaration.
Set<String> _declaredNames(RegExp pattern) {
  final names = <String>{};
  final dir = Directory('lib/database');
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Generated code restates the schema; scanning it would assert nothing
    // about hand-written migrations.
    if (entity.path.endsWith('.g.dart')) continue;
    final source = entity
        .readAsLinesSync()
        .map((line) {
          final comment = line.indexOf('//');
          return comment == -1 ? line : line.substring(0, comment);
        })
        .join('\n');
    for (final match in pattern.allMatches(source)) {
      names.add(match.group(1)!);
    }
  }
  return names;
}
