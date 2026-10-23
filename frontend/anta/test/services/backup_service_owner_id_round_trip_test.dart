import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_digest_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/event_template_service.dart';
import 'package:anta/services/filter_preset_service.dart';
import 'package:anta/services/overview_view_service.dart';
import 'package:anta/services/vocabulary_service.dart';

/// One synced table as the test reads it back: the SQL that names a row and
/// the archived row seeded as someone else's and as mine.
class _Table {
  const _Table(this.name, this.key, {required this.them, required this.mine});

  final String name;

  /// An SQL expression naming one row of [name].
  final String key;
  final String them;
  final String mine;
}

/// Guards D16: `owner_id` rides every synced table's backup rows as an
/// additive `ownerId` key, written only when set, and an import restores it
/// verbatim — absent means NULL, so an older archive restores everything as
/// mine and an archive with no foreign row is the one this app always wrote.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final day = DateTime.utc(2026, 8, 3).millisecondsSinceEpoch;

  const tables = [
    _Table('folders', 'name', them: 'Theirs', mine: 'Mine'),
    _Table('notes', 'title', them: 'Their note', mine: 'My note'),
    _Table('counters', 'id', them: 'k-them', mine: 'k-mine'),
    _Table(
      'counter_values',
      "counter_id || '::' || note_id",
      them: 'k-them::',
      mine: 'k-mine::',
    ),
    _Table(
      'counter_values',
      "counter_id || '::' || note_id",
      them: 'k-them::note-a',
      mine: 'k-mine::note-a',
    ),
    _Table('calendar_categories', 'id', them: 'c-them', mine: 'c-mine'),
    _Table('calendar_category_alerts', 'id', them: 'ca-them', mine: 'ca-mine'),
    _Table('calendar_events', 'id', them: 'e-them', mine: 'e-mine'),
    _Table(
      'calendar_event_occurrences',
      'event_id',
      them: 'e-them',
      mine: 'e-mine',
    ),
    _Table(
      'calendar_event_absences',
      'event_id',
      them: 'e-them',
      mine: 'e-mine',
    ),
    _Table('calendar_event_skips', 'event_id', them: 'e-them', mine: 'e-mine'),
    _Table('calendar_event_alerts', 'id', them: 'a-them', mine: 'a-mine'),
    _Table('calendar_event_templates', 'id', them: 't-them', mine: 't-mine'),
    _Table('calendar_filter_presets', 'id', them: 'p-them', mine: 'p-mine'),
    _Table('overview_views', 'id', them: 'v-them', mine: 'v-mine'),
    _Table('event_digests', 'id', them: 'd-them', mine: 'd-mine'),
    _Table('vocabularies', 'id', them: 'voc-them', mine: 'voc-mine'),
    _Table('vocabulary_items', 'id', them: 'i-them', mine: 'i-mine'),
  ];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_owner_round_trip');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    GetIt.I.registerSingleton<CounterService>(
      await CounterService.getInstance(),
    );
    GetIt.I.registerSingleton<AlertGateway>(const NoOpAlertGateway());
  });

  tearDownAll(() async {
    await GetIt.I.reset();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Drops every singleton, so each service's cache — the counters' above all,
  /// which export from memory — is read back from the database.
  Future<void> resetServices() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    GetIt.I.unregister<CounterService>();
    GetIt.I.registerSingleton<CounterService>(
      await CounterService.getInstance(),
    );
  }

  /// Folders and notes are the two tables an import appends to; wiping them
  /// is what lets a restored row be found by its name.
  Future<void> wipeFoldersAndNotes(AppDatabase db) async {
    await db.customStatement('DELETE FROM notes');
    await db.customStatement('DELETE FROM folders');
  }

  /// Seeds one row per table that is someone else's (when [foreign]) and one
  /// that is mine, over whatever an earlier test left.
  Future<AppDatabase> seed({required bool foreign}) async {
    final db = await AppDatabase.getInstance();
    await wipeFoldersAndNotes(db);
    await db.counterDao.deleteAll();

    await db.folderDao.createFolder(name: 'Theirs');
    final mine = await db.folderDao.createFolder(name: 'Mine');
    await db.noteDao.createNote(folderId: mine.id, title: 'Their note');
    await db.noteDao.createNote(folderId: mine.id, title: 'My note');

    final now = DateTime.now();
    for (final id in ['k-them', 'k-mine']) {
      await db.counterDao.insertCounter(
        CountersCompanion.insert(id: id, name: id, createdAt: now),
      );
      await db.counterDao.upsertValue(id, '', 3);
      await db.counterDao.upsertValue(id, 'note-a', 4);
    }

    await (await CategoryService.getInstance()).importData([
      for (final id in ['c-them', 'c-mine'])
        {'id': id, 'name': id, 'colorValue': 0xFF123456, 'iconKey': 'savings'},
    ]);
    await (await CalendarEventService.getInstance()).importData([
      for (final id in ['e-them', 'e-mine'])
        {
          'id': id,
          'title': id,
          'category': 'c-mine',
          'startDateMs': day,
          'ruleKind': 'daily',
        },
    ]);
    await (await EventOccurrenceService.getInstance()).importData([
      for (final id in ['e-them', 'e-mine'])
        {'eventId': id, 'dayMs': day, 'description': 'Standup'},
    ]);
    await (await EventPresenceService.getInstance()).importData([
      for (final id in ['e-them', 'e-mine']) {'eventId': id, 'dayMs': day},
    ]);
    await (await EventSkipService.getInstance()).importData([
      for (final id in ['e-them', 'e-mine']) {'eventId': id, 'dayMs': day},
    ]);
    final alerts = await EventAlertService.getInstance();
    await alerts.importData([
      for (final id in ['a-them', 'a-mine'])
        EventAlert(id: id, eventId: 'e-mine', daysBefore: 1).toJson(),
    ]);
    await alerts.importCategoryAlerts([
      for (final id in ['ca-them', 'ca-mine'])
        CategoryAlert(id: id, categoryId: 'c-mine', daysBefore: 1).toJson(),
    ]);
    await (await EventTemplateService.getInstance()).importData([
      for (final id in ['t-them', 't-mine'])
        {'id': id, 'name': id, 'category': 'c-mine'},
    ]);
    await (await FilterPresetService.getInstance()).importData([
      for (final id in ['p-them', 'p-mine']) {'id': id, 'name': id},
    ]);
    await (await OverviewViewService.getInstance()).importData([
      for (final id in ['v-them', 'v-mine']) {'id': id, 'name': id},
    ]);
    await (await EventDigestService.getInstance()).importData([
      for (final id in ['d-them', 'd-mine']) {'id': id, 'name': id},
    ]);
    await (await VocabularyService.getInstance()).importData([
      {
        'id': 'voc-them',
        'name': 'Theirs',
        'items': [
          {'id': 'i-them', 'term': 'squat'},
          {'id': 'i-mine', 'term': 'deadlift'},
        ],
      },
      {'id': 'voc-mine', 'name': 'Mine'},
    ]);

    if (foreign) {
      for (final table in tables) {
        await db.customUpdate(
          "UPDATE ${table.name} SET owner_id = 'them' WHERE ${table.key} = ?",
          variables: [Variable.withString(table.them)],
        );
      }
    }
    await resetServices();
    return db;
  }

  Future<Map<String, String?>> owners(AppDatabase db, _Table table) async {
    final rows = await db
        .customSelect('SELECT ${table.key} AS k, owner_id FROM ${table.name}')
        .get();
    return {
      for (final row in rows)
        row.read<String>('k'): row.readNullable<String>('owner_id'),
    };
  }

  Future<void> expectOwnership(AppDatabase db, {required String? them}) async {
    for (final table in tables) {
      final byKey = await owners(db, table);
      expect(byKey, contains(table.them), reason: table.name);
      expect(byKey, contains(table.mine), reason: table.name);
      expect(byKey[table.them], them, reason: '${table.name} ${table.them}');
      expect(byKey[table.mine], isNull, reason: '${table.name} ${table.mine}');
    }
  }

  Map<String, dynamic> byId(List<dynamic> rows, String key, String value) {
    return rows.cast<Map<String, dynamic>>().singleWhere(
      (r) => r[key] == value,
    );
  }

  /// [exported] with every `ownerId` key gone, the counters' JSON-in-a-string
  /// payloads included: the archive an app before D16 wrote.
  Object? strip(Object? value) {
    if (value is List) return [for (final v in value) strip(v)];
    if (value is Map) {
      return <String, dynamic>{
        for (final e in value.entries)
          if (e.key != 'ownerId') e.key as String: strip(e.value),
      };
    }
    return value;
  }

  Map<String, dynamic> stripAll(Map<String, dynamic> exported) {
    final stripped = strip(exported) as Map<String, dynamic>;
    final counters = stripped['counterData'] as Map<String, dynamic>;
    stripped['counterData'] = {
      for (final e in counters.entries)
        e.key: e.value is String
            ? jsonEncode(strip(jsonDecode(e.value as String)))
            : e.value,
    };
    return stripped;
  }

  test('ownerId round-trips on every synced table, absent on mine', () async {
    final db = await seed(foreign: true);
    final exported = await (await BackupService.getInstance()).exportAllData();
    expect(exported['version'], 7);

    final keyed = <String, (List<dynamic>, String, String, String)>{
      'folders': (exported['folders'] as List, 'name', 'Theirs', 'Mine'),
      'notes': (exported['notes'] as List, 'title', 'Their note', 'My note'),
      'calendarCategories': (
        exported['calendarCategories'] as List,
        'id',
        'c-them',
        'c-mine',
      ),
      'categoryAlerts': (
        exported['categoryAlerts'] as List,
        'id',
        'ca-them',
        'ca-mine',
      ),
      'calendarEvents': (
        exported['calendarEvents'] as List,
        'id',
        'e-them',
        'e-mine',
      ),
      'eventOccurrences': (
        exported['eventOccurrences'] as List,
        'eventId',
        'e-them',
        'e-mine',
      ),
      'eventAbsences': (
        exported['eventAbsences'] as List,
        'eventId',
        'e-them',
        'e-mine',
      ),
      'eventSkips': (
        exported['eventSkips'] as List,
        'eventId',
        'e-them',
        'e-mine',
      ),
      'eventAlerts': (
        exported['eventAlerts'] as List,
        'id',
        'a-them',
        'a-mine',
      ),
      'eventTemplates': (
        exported['eventTemplates'] as List,
        'id',
        't-them',
        't-mine',
      ),
      'calendarFilterPresets': (
        exported['calendarFilterPresets'] as List,
        'id',
        'p-them',
        'p-mine',
      ),
      'overviewViews': (
        exported['overviewViews'] as List,
        'id',
        'v-them',
        'v-mine',
      ),
      'eventDigests': (
        exported['eventDigests'] as List,
        'id',
        'd-them',
        'd-mine',
      ),
      'vocabularies': (
        exported['vocabularies'] as List,
        'id',
        'voc-them',
        'voc-mine',
      ),
      'vocabularyItems': (
        byId(exported['vocabularies'] as List, 'id', 'voc-them')['items']
            as List,
        'id',
        'i-them',
        'i-mine',
      ),
    };
    for (final MapEntry(key: name, value: (rows, key, them, mine))
        in keyed.entries) {
      expect(byId(rows, key, them)['ownerId'], 'them', reason: name);
      expect(byId(rows, key, mine), isNot(contains('ownerId')), reason: name);
    }

    final counterData = exported['counterData'] as Map<String, dynamic>;
    final counters = jsonDecode(counterData['counters'] as String) as List;
    expect(byId(counters, 'id', 'k-them')['ownerId'], 'them');
    expect(byId(counters, 'id', 'k-mine'), isNot(contains('ownerId')));
    final extras =
        jsonDecode(counterData['noteValueExtras'] as String)
            as Map<String, dynamic>;
    expect(extras['k-them::'], {'ownerId': 'them'});
    expect(extras['k-them::note-a'], {'ownerId': 'them'});
    expect(extras, isNot(contains('k-mine::')));
    expect(extras, isNot(contains('k-mine::note-a')));

    await wipeFoldersAndNotes(db);
    final result = await (await BackupService.getInstance()).importFromJson(
      jsonEncode(exported),
    );

    expect(result.success, isTrue, reason: result.error);
    await expectOwnership(db, them: 'them');
  });

  test('an archive written before D16 restores every row as mine', () async {
    final db = await seed(foreign: true);
    final exported = await (await BackupService.getInstance()).exportAllData();
    final older = jsonEncode(stripAll(exported));
    expect(older, isNot(contains('ownerId')));

    await wipeFoldersAndNotes(db);
    final result = await (await BackupService.getInstance()).importFromJson(
      older,
    );

    expect(result.success, isTrue, reason: result.error);
    await expectOwnership(db, them: null);
  });

  test('a non-string ownerId imports as unowned and drops nothing', () async {
    final db = await seed(foreign: true);
    final exported = await (await BackupService.getInstance()).exportAllData();
    // Every archived `ownerId` — the counters' JSON-in-a-string payloads
    // included, where a failed cast would lose the whole counters import —
    // is a number, as a hand-edited archive could make it.
    Object? retype(Object? value) {
      if (value is List) return [for (final v in value) retype(v)];
      if (value is Map) {
        return <String, dynamic>{
          for (final e in value.entries)
            e.key as String: e.key == 'ownerId' ? 42 : retype(e.value),
        };
      }
      return value;
    }

    final edited = retype(exported) as Map<String, dynamic>;
    final counters = edited['counterData'] as Map<String, dynamic>;
    edited['counterData'] = {
      for (final e in counters.entries)
        e.key: e.value is String
            ? jsonEncode(retype(jsonDecode(e.value as String)))
            : e.value,
    };
    expect(jsonEncode(edited), contains('"ownerId":42'));

    await wipeFoldersAndNotes(db);
    final result = await (await BackupService.getInstance()).importFromJson(
      jsonEncode(edited),
    );

    expect(result.success, isTrue, reason: result.error);
    await expectOwnership(db, them: null);
  });

  test('an archive of a database holding no foreign row carries no ownerId '
      'key', () async {
    await seed(foreign: false);

    final exported = await (await BackupService.getInstance()).exportAllData();

    expect(jsonEncode(exported), isNot(contains('ownerId')));
  });
}
