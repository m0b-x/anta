// An isolate-backed file database: the calendar round trip's slowest case
// ran 14 s in its own file and past 30 s under whole-suite load.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/event_template_service.dart';
import 'package:anta/services/label_appearance_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';

/// The restore of a backup nobody can make again (the exporter went in S18):
/// what it does with a row that points at something the archive does not
/// carry, with the order it was handed, and with a file it cannot apply.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_backup_safety');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    GetIt.I.registerSingleton<CounterService>(
      await CounterService.getInstance(),
    );
  });

  tearDownAll(() async {
    await GetIt.I.reset();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<ImportResult> restore(Map<String, dynamic> archive) async =>
      (await BackupService.getInstance()).importFromJson(jsonEncode(archive));

  Future<Note> restoredNote(AppDatabase db, String title) async =>
      (await db.noteDao.getAllNotes()).singleWhere((n) => n.title == title);

  test('a caller that arrives while the service opens gets the whole '
      'service', () async {
    BackupService.reset();
    final first = BackupService.getInstance();
    final second = await BackupService.getInstance();
    // Throws `LateInitializationError` on a service published before its
    // database was set.
    await second.hasExistingData();
    expect(identical(await first, second), isTrue);
  });

  group('a file the restore cannot apply', () {
    Map<String, dynamic> archive(Map<String, dynamic> fault) => {
      'version': 8,
      'folders': [
        {JsonKeys.id: 'r1', JsonKeys.name: 'Refused folder'},
      ],
      'notes': [
        {
          JsonKeys.id: 'rn1',
          JsonKeys.folderId: 'r1',
          JsonKeys.title: 'Refused note',
          JsonKeys.content: 'one',
        },
      ],
      'settings': {'safety_refused': 'written'},
      ...fault,
    };

    for (final (what, fault) in <(String, Map<String, dynamic>)>[
      (
        'a note without a title',
        {
          'notes': [
            {
              JsonKeys.id: 'rn1',
              JsonKeys.folderId: 'r1',
              JsonKeys.title: 'Refused note',
            },
            {JsonKeys.id: 'rn2', JsonKeys.folderId: 'r1', JsonKeys.title: null},
          ],
        },
      ),
      (
        'a folder row that is not an object',
        {
          'folders': ['Refused folder'],
        },
      ),
      (
        'a folder whose name is not a string',
        {
          'folders': [
            {JsonKeys.id: 'r1', JsonKeys.name: 'Refused folder'},
            {JsonKeys.id: 'r2', JsonKeys.name: 5},
          ],
        },
      ),
    ]) {
      // Each of these gets past the restore's own casts to the unbind, so
      // only the shape check stops it there.
      test('— $what — is refused before anything changes', () async {
        final db = await AppDatabase.getInstance();
        const binding = SyncBinding(
          spaceId: 'space-1',
          ownerUid: 'owner-1',
          accountUid: 'account-1',
        );
        await (await SettingsService.getInstance()).setSyncBinding(binding);
        final file = archive(fault);

        final result = await restore(file);

        expect(result.success, isFalse);
        expect(
          await (await SyncBindingService.getInstance()).read(),
          isNotNull,
          reason: 'a refused file leaves the database bound',
        );
        expect(
          (await db.folderDao.getAllFolders()).map((f) => f.name),
          isNot(contains('Refused folder')),
        );
        expect(
          (await db.noteDao.getAllNotes()).map((n) => n.title),
          isNot(contains('Refused note')),
        );
        expect(await db.userSettingsDao.getValue('safety_refused'), isNull);
        await (await SyncBindingService.getInstance()).unbind();
      });
    }

    test('is refused by the validation too, so the confirmation never '
        'opens on it', () async {
      final backup = await BackupService.getInstance();
      for (final fault in <Map<String, dynamic>>[
        {
          'notes': [
            {JsonKeys.id: 'rn2', JsonKeys.folderId: 'r1', JsonKeys.title: null},
          ],
        },
        {
          'notes': [
            {JsonKeys.id: 'rn2', JsonKeys.title: 'No folder'},
          ],
        },
        {
          'folders': ['Refused folder'],
        },
        {
          'folders': [
            {JsonKeys.id: 'r2', JsonKeys.name: 5},
          ],
        },
        {
          'folders': [
            {JsonKeys.id: 'r2', JsonKeys.name: 'x', JsonKeys.parentId: 3},
          ],
        },
        {'notes': <String, dynamic>{}},
        {'version': '8'},
      ]) {
        expect(
          (await backup.validateBackupData(archive(fault))).isValid,
          isFalse,
          reason: '$fault',
        );
      }
      expect((await backup.validateBackupData(archive({}))).isValid, isTrue);
    });
  });

  test('a damaged optional section costs only itself: the folders and notes '
      'land, and the restore counts what it skipped', () async {
    final db = await AppDatabase.getInstance();
    final file = <String, dynamic>{
      'version': 8,
      'folders': [
        {JsonKeys.id: 'df', JsonKeys.name: 'Damaged folder'},
      ],
      'notes': [
        {
          JsonKeys.id: 'dn',
          JsonKeys.folderId: 'df',
          JsonKeys.title: 'Damaged note',
          JsonKeys.content: 'kept',
        },
      ],
      'settings': 'theme_mode=dark',
      'counterData': {
        'counters': jsonEncode([
          {JsonKeys.id: 'dup', JsonKeys.name: 'First'},
          {JsonKeys.id: 'dup', JsonKeys.name: 'Second'},
        ]),
        'noteValues': '{bad',
        'noteValueExtras': 'null',
      },
      'calendarEvents': <String, dynamic>{},
      'eventTemplates': ['not a row'],
      'publicHolidays': [
        {'dateMs': 0, 'nameKey': 7},
      ],
    };
    final backup = await BackupService.getInstance();
    expect((await backup.validateBackupData(file)).isValid, isTrue);

    final result = await restore(file);

    expect(result.success, isTrue, reason: '${result.error}');
    expect(
      result.skipped,
      7,
      reason:
          'settings, calendarEvents, the template row, the duplicate '
          'counter, noteValues, noteValueExtras and the holiday',
    );
    expect(
      (await db.folderDao.getAllFolders()).where(
        (f) => f.name == 'Damaged folder',
      ),
      hasLength(1),
    );
    await restoredNote(db, 'Damaged note');
    expect(
      (await db.counterDao.getAllCounters()).map((c) => c.name),
      contains('First'),
    );
  });

  /// Every optional section restored alone, with one valid row and its
  /// damaged ones: the valid row lands, no damaged one does, and the count is
  /// exactly the damaged rows. Each case reaches the guard of the service
  /// that owns the section, so a guard that stops counting turns its own
  /// case red. Keys under `tbl-` are what [landed] reads back, per
  /// `table.column`.
  group('every optional section counts each row it skips', () {
    final day = DateTime.utc(2026, 5, 5).millisecondsSinceEpoch;
    int dayAfter(int days) =>
        DateTime.utc(2026, 5, 5 + days).millisecondsSinceEpoch;
    Map<String, dynamic> event(String id, [Map<String, dynamic>? fault]) => {
      'id': id,
      'title': id,
      'category': 'other',
      'startDateMs': day,
      'ruleKind': 'oneTime',
      ...?fault,
    };

    for (final (:section, :rows, :damaged, :landed, :fault)
        in <
          ({
            String section,
            Object rows,
            int damaged,
            Map<String, Set<String>> landed,
            String? fault,
          })
        >[
          (
            section: 'settings',
            rows: {
              'tbl-set-text': 'text',
              'tbl-set-number': 5,
              'tbl-set-flag': true,
              'tbl-set-object': {'x': 1},
              'tbl-set-list': [1],
              'tbl-set-null': null,
            },
            damaged: 3,
            landed: {
              'user_settings.key': {
                'tbl-set-text',
                'tbl-set-number',
                'tbl-set-flag',
              },
            },
            fault: null,
          ),
          (
            section: 'counterData',
            rows: {
              'counters': jsonEncode([
                {JsonKeys.id: 'tbl-c-ok', JsonKeys.name: 'Kept'},
                {JsonKeys.id: 'tbl-c-bad', JsonKeys.name: 42},
              ]),
            },
            damaged: 1,
            landed: {
              'counters.id': {'tbl-c-ok'},
            },
            fault: null,
          ),
          (
            section: 'calendarCategories',
            rows: [
              {
                'id': 'tbl-cat-ok',
                'name': 'Kept',
                'colorValue': 0xFF112233,
                'iconKey': 'savings',
              },
              // A custom row, which no seed puts back.
              {
                'id': 'tbl-cat-bad',
                'name': 'Damaged',
                'colorValue': 'red',
                'iconKey': 'savings',
              },
            ],
            damaged: 1,
            landed: {
              'calendar_categories.id': {'tbl-cat-ok'},
            },
            fault: null,
          ),
          (
            section: 'categoryAlerts',
            rows: [
              {
                'id': 'tbl-ca-ok',
                'categoryId': 'other',
                'mode': 'notification',
              },
              {'id': 'tbl-ca-bad', 'categoryId': 7},
              {'id': 'tbl-ca-throws', 'categoryId': 'other', 'mode': 5},
            ],
            damaged: 2,
            landed: {
              'calendar_category_alerts.id': {'tbl-ca-ok'},
            },
            fault: null,
          ),
          (
            section: 'categoryProfiles',
            rows: [
              {'id': 'tbl-cp-ok', 'categoryId': 'other', 'kind': 'workout'},
              {'id': 'tbl-cp-bad', 'categoryId': 'other', 'kind': 7},
            ],
            damaged: 1,
            landed: {
              'calendar_category_profiles.id': {'tbl-cp-ok'},
            },
            fault: null,
          ),
          (
            section: 'eventTemplates',
            rows: [
              {'id': 'tbl-t-ok', 'name': 'Kept', 'category': 'other'},
              {'id': 'tbl-t-bad', 'name': 5, 'category': 'other'},
              {
                'id': 'tbl-t-throws',
                'name': 'Throws',
                'category': 'other',
                'startMinute': 'noon',
              },
            ],
            damaged: 2,
            landed: {
              'calendar_event_templates.id': {'tbl-t-ok'},
            },
            fault: null,
          ),
          (
            section: 'calendarFilterPresets',
            rows: [
              {'id': 'tbl-p-ok', 'name': 'Kept'},
              {'id': 'tbl-p-bad', 'name': null},
            ],
            damaged: 1,
            landed: {
              'calendar_filter_presets.id': {'tbl-p-ok'},
            },
            fault: null,
          ),
          (
            section: 'overviewViews',
            rows: [
              {'id': 'tbl-v-ok', 'name': 'Kept'},
              {'id': 'tbl-v-bad', 'name': 3},
            ],
            damaged: 1,
            landed: {
              'overview_views.id': {'tbl-v-ok'},
            },
            fault: null,
          ),
          (
            section: 'eventDigests',
            rows: [
              {'id': 'tbl-d-ok', 'name': 'Kept'},
              {'id': 5, 'name': 'Damaged'},
            ],
            damaged: 1,
            landed: {
              'event_digests.id': {'tbl-d-ok'},
            },
            fault: null,
          ),
          (
            section: 'vocabularies',
            rows: [
              {
                'id': 'tbl-voc-ok',
                'name': 'Kept',
                'items': [
                  {'id': 'tbl-i-ok', 'term': 'alpha'},
                  {'id': 'tbl-i-throws', 'term': 5},
                  'not an item',
                  {'id': 'tbl-i-blank', 'term': ' '},
                  {'id': 'tbl-i-after', 'term': 'omega'},
                ],
              },
              // Counted once, its item with it.
              {
                'id': 'tbl-voc-bad',
                'name': 7,
                'items': [
                  {'id': 'tbl-i-dependant', 'term': 'beta'},
                ],
              },
              {'id': 'tbl-voc-itemless', 'name': 'Kept', 'items': 'oops'},
              // A second list under an id already restored: the first is
              // kept, this one counted once, its item with it.
              {
                'id': 'tbl-voc-ok',
                'name': 'Again',
                'items': [
                  {'id': 'tbl-i-duplicate', 'term': 'gamma'},
                ],
              },
            ],
            damaged: 6,
            landed: {
              'vocabularies.id': {'tbl-voc-ok', 'tbl-voc-itemless'},
              'vocabulary_items.id': {'tbl-i-ok', 'tbl-i-after'},
            },
            fault: null,
          ),
          (
            section: 'calendarEvents',
            rows: [
              event('tbl-ev-ok'),
              event('tbl-ev-bad', {'startDateMs': 'monday'}),
              event('tbl-ev-throws', {'allDay': 'yes'}),
            ],
            damaged: 2,
            landed: {
              'calendar_events.id': {'tbl-ev-ok'},
            },
            fault: null,
          ),
          (
            section: 'eventOccurrences',
            rows: [
              {'eventId': 'tbl-oc-ok', 'dayMs': day, 'description': 'Kept'},
              {'eventId': 'tbl-oc-bad', 'dayMs': day, 'description': 4},
            ],
            damaged: 1,
            landed: {
              'calendar_event_occurrences.event_id': {'tbl-oc-ok'},
            },
            fault: null,
          ),
          (
            section: 'eventAbsences',
            rows: [
              {'eventId': 'tbl-ab-ok', 'dayMs': day},
              {'eventId': 'tbl-ab-bad', 'dayMs': 'monday'},
            ],
            damaged: 1,
            landed: {
              'calendar_event_absences.event_id': {'tbl-ab-ok'},
            },
            fault: null,
          ),
          (
            section: 'eventSkips',
            rows: [
              {'eventId': 'tbl-sk-ok', 'dayMs': day},
              {'eventId': 'tbl-sk-bad', 'dayMs': 'monday'},
            ],
            damaged: 1,
            landed: {
              'calendar_event_skips.event_id': {'tbl-sk-ok'},
            },
            fault: null,
          ),
          (
            section: 'eventAlerts',
            rows: [
              {
                'id': 'tbl-al-ok',
                'eventId': 'tbl-ev-ok',
                'mode': 'notification',
              },
              {'id': 'tbl-al-bad', 'eventId': ''},
              {'id': 'tbl-al-throws', 'eventId': 'tbl-ev-ok', 'mode': 5},
            ],
            damaged: 2,
            landed: {
              'calendar_event_alerts.id': {'tbl-al-ok'},
            },
            fault: null,
          ),
          (
            section: 'publicHolidays',
            rows: [
              for (final (i, fault) in <Map<String, dynamic>>[
                {'customLabel': 'tbl-hol-ok'},
                {'customLabel': 'tbl-hol-suppressed', 'suppressed': 'yes'},
                {'customLabel': 'tbl-hol-profile', 'profile': 3},
                {'customLabel': 5},
                // Refused by the database, the [fault] below.
                {'customLabel': 'tbl-hol-refused'},
              ].indexed)
                {'dateMs': dayAfter(i), 'nameKey': 'custom', ...fault},
            ],
            damaged: 4,
            landed: {
              'public_holidays.custom_label': {'tbl-hol-ok'},
            },
            fault:
                'CREATE TEMP TRIGGER tbl_refused BEFORE INSERT ON '
                "public_holidays WHEN NEW.custom_label = 'tbl-hol-refused' "
                "BEGIN SELECT RAISE(ABORT, 'refused'); END",
          ),
        ]) {
      test('— $section', () async {
        final db = await AppDatabase.getInstance();
        if (fault != null) {
          await db.customStatement(fault);
          addTearDown(() => db.customStatement('DROP TRIGGER tbl_refused'));
        }

        final result = await restore({
          'version': 8,
          'folders': [],
          'notes': [],
          section: rows,
        });

        expect(result.success, isTrue, reason: '${result.error}');
        expect(result.skipped, damaged);
        for (final MapEntry(key: where, value: expected) in landed.entries) {
          final [table, column] = where.split('.');
          final keys = await db
              .customSelect(
                'SELECT "$column" AS k FROM "$table" '
                "WHERE \"$column\" LIKE 'tbl-%'",
              )
              .get();
          expect({for (final row in keys) row.read<String>('k')}, expected);
        }
      });
    }
  });

  test('a row whose parent the restore skipped counts once, with its '
      'parent', () async {
    final db = await AppDatabase.getInstance();
    final result = await restore({
      'version': 8,
      'folders': [],
      'notes': [],
      'calendarCategories': [
        {
          'id': 'dep-cat',
          'name': 'Damaged',
          'colorValue': 'red',
          'iconKey': 'savings',
        },
      ],
      'categoryProfiles': [
        {'id': 'dep-profile', 'categoryId': 'dep-cat', 'kind': 'workout'},
      ],
      'calendarEvents': [
        {
          'id': 'dep-ev',
          'title': 'Damaged',
          'category': 'other',
          'startDateMs': 'monday',
          'ruleKind': 'oneTime',
        },
      ],
      'eventSkips': [
        {
          'eventId': 'dep-ev',
          'dayMs': DateTime.utc(2026, 5, 5).millisecondsSinceEpoch,
        },
      ],
      'eventAlerts': [
        {'id': 'dep-alert', 'eventId': 'dep-ev', 'mode': 'notification'},
      ],
    });

    expect(result.success, isTrue, reason: '${result.error}');
    expect(
      result.skipped,
      2,
      reason:
          'the category and the event; the profile, the skip and the '
          'alert go with them',
    );
    expect(
      await db
          .customSelect(
            "SELECT id FROM calendar_category_profiles WHERE id = 'dep-profile'",
          )
          .get(),
      isEmpty,
    );
  });

  test('a section of the wrong type is read as absent, so beside the '
      'categories it clears what hangs off them', () async {
    final db = await AppDatabase.getInstance();
    final seeded = await restore({
      'version': 8,
      'folders': [],
      'notes': [],
      'categoryAlerts': [
        {'id': 'absent-ca', 'categoryId': 'other', 'mode': 'notification'},
      ],
    });
    expect(seeded.skipped, 0);

    // An absent `categoryAlerts` beside `calendarCategories` is the strand
    // rule's clear: the categories' id space was replaced. A string where the
    // list should be is read as that absent key, and counted.
    final result = await restore({
      'version': 8,
      'folders': [],
      'notes': [],
      'calendarCategories': [
        {
          'id': 'absent-cat',
          'name': 'Kept',
          'colorValue': 0xFF112233,
          'iconKey': 'savings',
        },
      ],
      'categoryAlerts': 'oops',
    });

    expect(result.success, isTrue, reason: '${result.error}');
    expect(result.skipped, 1);
    expect(
      await db.customSelect('SELECT id FROM calendar_category_alerts').get(),
      isEmpty,
    );
  });

  test('a setting is written as the text it holds: a string as it is, a '
      'number or a flag as its plain text, anything else skipped', () async {
    final db = await AppDatabase.getInstance();
    final result = await restore({
      'version': 8,
      'folders': [],
      'notes': [
        {
          JsonKeys.id: 'typed-n',
          JsonKeys.folderId: '',
          JsonKeys.title: 'Typed settings',
        },
      ],
      'settings': {
        'typed_text': 'dark',
        'typed_int': 14,
        'typed_double': 1.5,
        'typed_flag': false,
        'typed_object': {'x': 1},
      },
      'noteBarAssignments': {'typed-n': 7, 'typed-gone': 'bar'},
      'noteMoneyCurrencies': {
        'typed-n': ['EUR'],
      },
    });

    expect(result.success, isTrue, reason: '${result.error}');
    expect(result.skipped, 2, reason: 'the object and the currency list');
    final settings = db.userSettingsDao;
    expect(await settings.getValue('typed_text'), 'dark');
    expect(await settings.getValue('typed_int'), '14');
    expect(await settings.getValue('typed_double'), '1.5');
    expect(await settings.getValue('typed_flag'), 'false');
    expect(await settings.getValue('typed_object'), isNull);
    final note = await restoredNote(db, 'Typed settings');
    expect(await settings.getValue('note_bar_${note.id}'), '7');
    expect(
      await settings.getValue(
        '${SettingsKeys.moneyNoteCurrencyPrefix}${note.id}',
      ),
      isNull,
    );
  });

  test('a step after the commit that throws leaves the restore a '
      'success', () async {
    BackupService.afterCommitStepForTesting = () async =>
        throw StateError('the palette could not be read');
    addTearDown(() => BackupService.afterCommitStepForTesting = null);

    final result = await restore({
      'version': 8,
      'folders': [
        {JsonKeys.id: 'pc', JsonKeys.name: 'Post-commit folder'},
      ],
      'notes': [],
    });

    expect(result.success, isTrue, reason: '${result.error}');
    expect(result.foldersImported, 1);
  });

  test('a step after the commit that throws does not stop the steps after '
      'it', () async {
    // The test step runs first — asserted below, since run last it would
    // have nothing after it to stop and this case would prove nothing; the
    // label style is republished after it.
    final before = await LabelAppearanceService.getInstance();
    var ranBeforeTheLabelStyle = false;
    BackupService.afterCommitStepForTesting = () async {
      ranBeforeTheLabelStyle = identical(
        await LabelAppearanceService.getInstance(),
        before,
      );
      throw StateError('the bar could not be reset');
    };
    addTearDown(() => BackupService.afterCommitStepForTesting = null);

    final result = await restore({'version': 8, 'folders': [], 'notes': []});

    expect(result.success, isTrue, reason: '${result.error}');
    expect(
      ranBeforeTheLabelStyle,
      isTrue,
      reason: 'the throwing step ran while the old label style was held',
    );
    expect(
      identical(await LabelAppearanceService.getInstance(), before),
      isFalse,
      reason: 'the label style was read again',
    );
  });

  test('an archive without notes links, assigns and prices nothing', () async {
    final db = await AppDatabase.getInstance();
    final result = await restore({
      'version': 8,
      'folders': [],
      'notes': [],
      'noteBarAssignments': {'noteless-gone': 'bar'},
      'noteMoneyCurrencies': {'noteless-gone': 'EUR'},
      'calendarEvents': [
        {
          'id': 'noteless-e',
          'title': 'Noteless',
          'category': 'other',
          'startDateMs': DateTime.utc(2026, 3, 3).millisecondsSinceEpoch,
          'ruleKind': 'oneTime',
          'noteId': 'noteless-gone',
        },
      ],
    });
    expect(result.success, isTrue, reason: '${result.error}');

    final event = (await db.calendarEventDao.getAll()).singleWhere(
      (e) => e.id == 'noteless-e',
    );
    expect(event.noteId, isNull);
    expect(await db.userSettingsDao.getValue('note_bar_noteless-gone'), isNull);
    expect(
      await db.userSettingsDao.getValue(
        '${SettingsKeys.moneyNoteCurrencyPrefix}noteless-gone',
      ),
      isNull,
    );
  });

  test('a restore that throws halfway rolls every row back, and the '
      'corrected file then restores once', () async {
    final db = await AppDatabase.getInstance();
    final counters = await CounterService.getInstance();
    await counters.addCounter(name: 'Atomic kept counter');
    final kept = [for (final c in await db.counterDao.getAllCounters()) c.id];
    await db.userSettingsDao.setValue('safety_atomic', 'before');
    final calendar = await CalendarEventService.getInstance();
    final categories = await CategoryService.getInstance();
    final templates = await EventTemplateService.getInstance();
    // A database error in the last section, after every other section was
    // written and its cache refilled inside the transaction: the holiday
    // import's wipe meets a row this trigger refuses to delete.
    await (await PublicHolidayService.getInstance()).addCustom(
      DateTime.utc(2026, 4, 4),
      'Atomic kept holiday',
    );
    await db.customStatement(
      'CREATE TEMP TRIGGER safety_fault BEFORE DELETE ON public_holidays '
      "BEGIN SELECT RAISE(ABORT, 'safety fault'); END",
    );

    Map<String, dynamic> archive() => {
      'version': 8,
      'folders': [
        {JsonKeys.id: 'af', JsonKeys.name: 'Atomic folder'},
      ],
      'notes': [
        {
          JsonKeys.id: 'an',
          JsonKeys.folderId: 'af',
          JsonKeys.title: 'Atomic note',
          JsonKeys.content: 'body',
        },
      ],
      'settings': {'safety_atomic': 'after'},
      'counterData': {
        'counters': jsonEncode([
          {JsonKeys.id: 'atomic-c', JsonKeys.name: 'Atomic counter'},
        ]),
      },
      'calendarEvents': [
        {
          'id': 'atomic-e',
          'title': 'Atomic event',
          'category': 'other',
          'startDateMs': DateTime.utc(2026, 2, 2).millisecondsSinceEpoch,
          'ruleKind': 'oneTime',
          'noteId': 'an',
        },
      ],
      'calendarCategories': [
        {
          'id': 'atomic-cat',
          'name': 'Atomic category',
          'colorValue': 0xFF112233,
          'iconKey': 'savings',
        },
      ],
      'eventTemplates': [
        {'id': 'atomic-t', 'name': 'Atomic template', 'category': 'other'},
      ],
      'publicHolidays': [],
    };

    final failed = await restore(archive());
    expect(failed.success, isFalse);
    expect(failed.error, contains('safety fault'));
    await db.customStatement('DROP TRIGGER safety_fault');

    Future<int> folders() async => (await db.folderDao.getAllFolders())
        .where((f) => f.name == 'Atomic folder')
        .length;
    Future<int> notes() async => (await db.noteDao.getAllNotes())
        .where((n) => n.title == 'Atomic note')
        .length;
    expect(await folders(), 0);
    expect(await notes(), 0);
    expect(await db.userSettingsDao.getValue('safety_atomic'), 'before');
    expect((await db.counterDao.getAllCounters()).map((c) => c.id), kept);
    expect(counters.counters.map((c) => c.id), kept);
    expect(
      (await db.calendarEventDao.getAll()).map((e) => e.id),
      isNot(contains('atomic-e')),
    );
    expect(
      calendar.events.map((e) => e.id),
      isNot(contains('atomic-e')),
      reason: 'no service cache keeps a rolled-back row',
    );
    expect(
      categories.categories.map((c) => c.id),
      isNot(contains('atomic-cat')),
    );
    expect(
      CalendarCategories.all.map((c) => c.id),
      isNot(contains('atomic-cat')),
    );
    expect(templates.templates.map((t) => t.id), isNot(contains('atomic-t')));

    final retried = await restore(archive());
    expect(retried.success, isTrue, reason: '${retried.error}');
    expect(await folders(), 1);
    expect(await notes(), 1);
    expect(await db.userSettingsDao.getValue('safety_atomic'), 'after');
    expect(counters.counters.map((c) => c.id), ['atomic-c']);
    final note = await restoredNote(db, 'Atomic note');
    expect(
      calendar.events.where((e) => e.id == 'atomic-e').map((e) => e.noteId),
      [note.id],
    );
  });

  test('restored sibling folders keep their archived order, appended after '
      'what is already there', () async {
    final db = await AppDatabase.getInstance();
    await db.folderDao.createFolder(name: 'Order existing root');
    // Listed out of order, and a grandchild ahead of its parent: the walk that
    // puts parents first must not let either decide the siblings' order.
    // Notes never carried a position, so only folders are ordered here.
    final result = await restore({
      'version': 8,
      'folders': [
        {
          JsonKeys.id: 'x',
          JsonKeys.name: 'Order X',
          JsonKeys.parentId: 'b',
          'position': 0,
        },
        {
          JsonKeys.id: 'a',
          JsonKeys.name: 'Order A',
          JsonKeys.parentId: 'p',
          'position': 1,
        },
        {
          JsonKeys.id: 'b',
          JsonKeys.name: 'Order B',
          JsonKeys.parentId: 'p',
          'position': 2,
        },
        {
          JsonKeys.id: 'c',
          JsonKeys.name: 'Order C',
          JsonKeys.parentId: 'p',
          'position': 0,
        },
        {JsonKeys.id: 'p', JsonKeys.name: 'Order P', 'position': 0},
      ],
      'notes': [],
    });
    expect(result.success, isTrue, reason: '${result.error}');

    final all = await db.folderDao.getAllFolders();
    final parent = all.singleWhere((f) => f.name == 'Order P');
    final existing = all.singleWhere((f) => f.name == 'Order existing root');
    expect(parent.position, greaterThan(existing.position));
    final kids = await db.folderDao.getFoldersByParent(parent.id);
    expect(kids.map((f) => f.name), ['Order C', 'Order A', 'Order B']);
    final b = kids.singleWhere((f) => f.name == 'Order B');
    expect((await db.folderDao.getFoldersByParent(b.id)).map((f) => f.name), [
      'Order X',
    ]);
  });

  test('siblings without an archived position keep the list order', () async {
    final db = await AppDatabase.getInstance();
    final result = await restore({
      'version': 1,
      'folders': [
        {JsonKeys.id: 'q', JsonKeys.name: 'Unpositioned Q'},
        {
          JsonKeys.id: 'q2',
          JsonKeys.name: 'Unpositioned 2',
          JsonKeys.parentId: 'q',
        },
        {
          JsonKeys.id: 'q1',
          JsonKeys.name: 'Unpositioned 1',
          JsonKeys.parentId: 'q',
          'position': 'first',
        },
      ],
      'notes': [],
    });
    expect(result.success, isTrue, reason: '${result.error}');
    final parent = (await db.folderDao.getAllFolders()).singleWhere(
      (f) => f.name == 'Unpositioned Q',
    );
    expect(
      (await db.folderDao.getFoldersByParent(parent.id)).map((f) => f.name),
      ['Unpositioned 2', 'Unpositioned 1'],
    );
  });

  test('an event linked to a note the archive does not carry restores '
      'unlinked', () async {
    final db = await AppDatabase.getInstance();
    final result = await restore({
      'version': 8,
      'folders': [],
      'notes': [
        {
          JsonKeys.id: 'link-carried',
          JsonKeys.folderId: '',
          JsonKeys.title: 'Link carried',
          JsonKeys.content: 'body',
        },
      ],
      'calendarEvents': [
        for (final (id, noteId) in [
          ('link-e1', 'link-carried'),
          ('link-e2', 'link-deleted-before-export'),
        ])
          {
            'id': id,
            'title': id,
            'category': 'other',
            'startDateMs': DateTime.utc(2026, 1, 5).millisecondsSinceEpoch,
            'ruleKind': 'oneTime',
            'noteId': noteId,
          },
      ],
    });
    expect(result.success, isTrue, reason: '${result.error}');

    final note = await restoredNote(db, 'Link carried');
    final events = {
      for (final e in await db.calendarEventDao.getAll()) e.id: e.noteId,
    };
    expect(events, {'link-e1': note.id, 'link-e2': null});
  });

  test('per-note settings of a note the archive does not carry are dropped, '
      'never written under the archived id', () async {
    final db = await AppDatabase.getInstance();
    // The restore onto the database the archive came from: this note is the
    // original of one the archive no longer carries.
    final live = await db.noteDao.createNote(folderId: '', title: 'Live note');
    await db.userSettingsDao.setValue('note_bar_${live.id}', 'mine');
    await db.userSettingsDao.setValue(
      '${SettingsKeys.moneyNoteCurrencyPrefix}${live.id}',
      'RON',
    );

    final result = await restore({
      'version': 8,
      'folders': [],
      'notes': [
        {
          JsonKeys.id: 'settings-carried',
          JsonKeys.folderId: '',
          JsonKeys.title: 'Settings carried',
          JsonKeys.content: 'body',
        },
      ],
      'noteBarAssignments': {'settings-carried': 'bar-a', live.id: 'bar-b'},
      'noteMoneyCurrencies': {'settings-carried': 'EUR', live.id: 'USD'},
    });
    expect(result.success, isTrue, reason: '${result.error}');

    final copy = await restoredNote(db, 'Settings carried');
    final settings = db.userSettingsDao;
    expect(await settings.getValue('note_bar_${copy.id}'), 'bar-a');
    expect(await settings.getValue('note_bar_${live.id}'), 'mine');
    expect(
      await settings.getValue(
        '${SettingsKeys.moneyNoteCurrencyPrefix}${copy.id}',
      ),
      'EUR',
    );
    expect(
      await settings.getValue(
        '${SettingsKeys.moneyNoteCurrencyPrefix}${live.id}',
      ),
      'RON',
    );
    expect(await settings.getValue('note_bar_settings-carried'), isNull);
  });
}
