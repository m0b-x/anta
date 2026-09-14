import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/counter_service.dart';

/// `tool/qa/fixtures/basic.json` is the seed the QA build imports when the
/// driver drops a `qa_seed.json` marker, and it is hand-written rather than
/// exported — so nothing but this file notices when the backup format moves
/// underneath it.
///
/// The assertions are deliberately structural: a seed whose notes land in no
/// folder, or whose recurring event is skipped as malformed, imports
/// "successfully" and still gives the driver an empty screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_qa_fixture');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    GetIt.I.registerSingleton<CounterService>(
      await CounterService.getInstance(),
    );

    db = await AppDatabase.getInstance();
    final fixture = File('tool/qa/fixtures/basic.json');
    expect(
      await fixture.exists(),
      isTrue,
      reason: 'run from the package root: ${fixture.absolute.path}',
    );
    final backup = await BackupService.getInstance();
    final result = await backup.importFromJson(await fixture.readAsString());
    expect(result.success, isTrue, reason: 'error: ${result.error}');
    expect(result.foldersImported, 4);
    expect(result.notesImported, 3);
  });

  tearDownAll(() async {
    await GetIt.I.reset();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test(
    'the tree is three root folders, one subfolder and three notes',
    () async {
      final folders = await db.folderDao.getAllFolders(includeDeleted: false);
      expect(folders, hasLength(4));

      final roots = folders.where((f) => f.parentId == null).map((f) => f.name);
      expect(roots, containsAll(<String>['Training', 'Money', 'Inbox']));

      final training = folders.firstWhere((f) => f.name == 'Training');
      final week1 = folders.firstWhere((f) => f.name == 'Week 1');
      expect(
        week1.parentId,
        training.id,
        reason: 'the subfolder has to hang off the imported Training folder',
      );

      final notes = await db.noteDao.getAllNotes(includeDeleted: false);
      expect(notes, hasLength(3));
      expect(
        notes.where((n) => n.folderId == week1.id).map((n) => n.title),
        containsAll(<String>['Session 1', 'Session 2']),
      );

      final money = folders.firstWhere((f) => f.name == 'Money');
      expect(notes.where((n) => n.folderId == money.id).map((n) => n.title), [
        'January',
      ]);

      final inbox = folders.firstWhere((f) => f.name == 'Inbox');
      expect(notes.where((n) => n.folderId == inbox.id), isEmpty);
    },
  );

  test('note content round-trips, markers and all', () async {
    final notes = await db.noteDao.getAllNotes(includeDeleted: false);
    final session1 = notes.firstWhere((n) => n.title == 'Session 1');
    final content = await db.contentChunkDao.loadContent(session1.id);

    expect(content, startsWith('# Session 1'));
    expect(content, contains('- [x] Bike 10 min'));
    expect(content, contains('  - 5 x 5 @ 100 kg'));
    expect(content, contains('#training'));
    expect(
      content,
      contains('[[Session 2]]'),
      reason: 'the wiki link is what makes the seed navigable',
    );

    final ledger = notes.firstWhere((n) => n.title == 'January');
    final ledgerContent = await db.contentChunkDao.loadContent(ledger.id);
    expect(ledgerContent, contains('\$= 1000 opening balance'));
    expect(ledgerContent, contains('\$- 12.50 coffee'));
    expect(ledgerContent, contains('\$! 500 eating out'));
  });

  test('labels survive the import', () async {
    final folders = await db.folderDao.getAllFolders(includeDeleted: false);
    final training = folders.firstWhere((f) => f.name == 'Training');
    expect(ItemLabel.fromStorage(training.label), ItemLabel.blue);

    final notes = await db.noteDao.getAllNotes(includeDeleted: false);
    final session1 = notes.firstWhere((n) => n.title == 'Session 1');
    expect(ItemLabel.fromStorage(session1.label), ItemLabel.teal);
  });

  test('both counters and their values land', () async {
    final counters = GetIt.I<CounterService>().counters;
    final ids = counters.map((c) => c.id).toList();
    expect(ids, containsAll(<String>['qa-counter-sets', 'qa-counter-reps']));

    final global = counters.firstWhere((c) => c.id == 'qa-counter-sets');
    expect(global.isPinned, isTrue);
    expect(
      GetIt.I<CounterService>().getGlobalValue('qa-counter-sets'),
      12,
      reason: 'a global counter value is stored with an empty note id',
    );
  });

  test('the custom category and both events import', () async {
    final categories = await (await CategoryService.getInstance()).exportData();
    expect(
      categories.map((c) => c['id']),
      contains('qa-category-strength'),
      reason: 'the import re-seeds built-ins around the custom one',
    );

    final events = await (await CalendarEventService.getInstance())
        .exportData();
    expect(events, hasLength(2));
    final recurring = events.firstWhere(
      (e) => e['id'] == 'qa-event-weekly-lift',
    );
    expect(recurring['ruleKind'], 'weekly');
    expect(recurring['rulePayload'], '{"weekdays":[1,4]}');
    expect(
      recurring['category'],
      'qa-category-strength',
      reason: 'the recurring event points at the custom category',
    );
  });
}
