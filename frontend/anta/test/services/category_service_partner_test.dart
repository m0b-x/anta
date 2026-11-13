import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/daos/shared_row_dao.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/event_template.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_template_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// The catalogue on a phone that holds a partner's own categories
/// (`docs/cloud-share-surfaces-roadmap.md` §6.1, §7.5): each is told apart
/// once per load, draws the partner's events, and is kept out of everything
/// that chooses, edits or leaves the phone — and no write of one answers
/// "saved", since the database turns it into nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const partner = 'partner-uid';
  final day = DateTime.utc(2026, 6, 1);

  late StatementCounter counter;
  late AppDatabase db;
  late CategoryService service;

  setUp(() async {
    CategoryService.reset();
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
    service = await CategoryService.forTesting(db);
  });

  tearDown(() async {
    EventAlertService.reset();
    CategoryService.reset();
    await db.close();
  });

  Future<void> insertCategory(
    String id, {
    String? name,
    int sortOrder = 50,
    bool hidden = false,
  }) => db.calendarCategoryDao.insertCategory(
    CalendarCategoriesCompanion.insert(
      id: id,
      name: name ?? 'Category $id',
      colorValue: 0xFF336699,
      iconKey: 'event',
      sortOrder: Value(sortOrder),
      isHidden: Value(hidden),
      createdAt: day,
      updatedAt: day,
    ),
  );

  Future<void> insertEvent(String id, String category) =>
      db.calendarEventDao.upsert(
        CalendarEventsCompanion.insert(
          id: id,
          title: 'Event $id',
          category: category,
          startDate: day,
          ruleKind: 'oneTime',
          createdAt: day,
          updatedAt: day,
        ),
      );

  /// What the reader would have stored: the categories [ids] under the
  /// partner's account at order 0, as the reader stores them, and that
  /// account as the one this database reads — the fences armed from here
  /// on. Then the catalogue is read again.
  Future<void> partnersCategories(
    List<String> ids, {
    bool hidden = false,
    Map<String, String> names = const {},
  }) async {
    for (final id in ids) {
      await insertCategory(
        id,
        name: names[id] ?? 'Shifts $id',
        sortOrder: 0,
        hidden: hidden,
      );
      await db.customStatement(
        'UPDATE calendar_categories SET owner_id = ? WHERE id = ?',
        [partner, id],
      );
    }
    await db.syncDao.setValue(SyncDao.keySharedOwner, partner);
    await db.syncOutboxDao.clear();
    await service.reload();
  }

  Future<CalendarCategoryRow> row(String id) async =>
      (await db.calendarCategoryDao.getByIdsIncludingDeleted([id])).single;

  Future<Set<String>> queued() async => {
    for (final entry in await db.syncOutboxDao.pending())
      '${entry.syncedTable}/${entry.rowKey}',
  };

  group('the catalogue', () {
    test('marks the partner\'s rows, and only theirs', () async {
      await insertCategory('mine');
      await partnersCategories(['theirs']);

      expect(CalendarCategories.byId('theirs')!.fromPartner, isTrue);
      expect(CalendarCategories.byId('mine')!.fromPartner, isFalse);
      expect(CalendarCategories.byId('gym')!.fromPartner, isFalse);
    });

    test('a row another account left behind is not the partner\'s unless '
        'it is the account this database reads', () async {
      await insertCategory('left');
      await db.customStatement(
        "UPDATE calendar_categories SET owner_id = 'someone-else' "
        "WHERE id = 'left'",
      );
      await partnersCategories(['theirs']);

      expect(CalendarCategories.byId('left')!.fromPartner, isFalse);
      expect(CalendarCategories.byId('theirs')!.fromPartner, isTrue);
    });

    test('resolves the partner\'s category for its events, but no choosing '
        'list holds it', () async {
      await partnersCategories(['theirs']);

      expect(CalendarCategories.resolve('theirs').name, 'Shifts theirs');
      expect(CalendarCategories.all.map((c) => c.id), contains('theirs'));
      expect(CalendarCategories.partner.map((c) => c.id), ['theirs']);
      expect(
        CalendarCategories.visible.map((c) => c.id),
        isNot(contains('theirs')),
      );
      expect(
        CalendarCategories.visiblePlus({'theirs'}).map((c) => c.id),
        isNot(contains('theirs')),
        reason: 'a partner\'s category is no selection of mine to keep',
      );
      expect(service.categories.map((c) => c.id), isNot(contains('theirs')));
      expect(CalendarCategories.defaultForNewEvent, isNot('theirs'));
    });

    test('an own archived category is still kept for a selection that '
        'holds it beside a partner\'s', () async {
      await insertCategory('archived', hidden: true);
      await partnersCategories(['theirs']);

      expect(
        CalendarCategories.visiblePlus({'archived'}).map((c) => c.id),
        contains('archived'),
      );
      expect(
        CalendarCategories.visiblePlus(const <String>{}).map((c) => c.id),
        isNot(contains('archived')),
      );
    });

    test('lists the person\'s own by their order first, then the partner\'s '
        'by name — so the report\'s and the overview\'s order of mine does '
        'not move for them', () async {
      await insertCategory('mine', sortOrder: 3);
      await service.reload();
      final own = [for (final c in CalendarCategories.all) c.id];
      await partnersCategories(
        ['t1', 't2', 't3'],
        names: const {'t1': 'Yoga', 't2': 'Archery', 't3': 'kayak'},
      );

      expect([for (final c in CalendarCategories.all) c.id], [
        ...own,
        't2',
        't3',
        't1',
      ]);
      expect([for (final c in CalendarCategories.partner) c.id], [
        't2',
        't3',
        't1',
      ]);
      expect([for (final c in service.categories) c.id], own);
    });

    test('the partner\'s archive flag is not obeyed here', () async {
      await partnersCategories(['theirs'], hidden: true);

      expect(CalendarCategories.byId('theirs')!.isHidden, isFalse);
      expect(CalendarCategories.partner.map((c) => c.id), ['theirs']);
    });

    test('a singly shared event whose category was not shared draws as '
        'Other', () async {
      await partnersCategories(['theirs']);

      expect(CalendarCategories.byId('their-unshared'), isNull);
      expect(CalendarCategories.resolve('their-unshared').id, 'other');
    });

    test('an account that never paired has no partner\'s categories', () {
      expect(CalendarCategories.partner, isEmpty);
      expect(CalendarCategories.all.every((c) => !c.fromPartner), isTrue);
      expect(service.categories, CalendarCategories.all);
    });

    test('a pair that ended takes the partner\'s categories with it at the '
        'next reload', () async {
      await partnersCategories(['theirs']);
      await db.sharedRowDao.removeAll();
      await service.reload();

      expect(CalendarCategories.byId('theirs'), isNull);
      expect(CalendarCategories.partner, isEmpty);
    });

    test('fromPartner is part of equality and survives copyWith', () {
      const mine = CalendarCategory(
        id: 'x',
        name: 'X',
        colorValue: 0,
        iconKey: 'event',
        sortOrder: 0,
        isBuiltIn: false,
      );
      const theirs = CalendarCategory(
        id: 'x',
        name: 'X',
        colorValue: 0,
        iconKey: 'event',
        sortOrder: 0,
        isBuiltIn: false,
        fromPartner: true,
      );
      expect(mine, isNot(theirs));
      expect(theirs.copyWith(name: 'Y').fromPartner, isTrue);
    });
  });

  test('a choice of what shows that cannot be read hides nothing, and the '
      'catalogue it sits beside is published whole', () async {
    await insertCategory('mine');
    await partnersCategories(['theirs']);
    await SettingsService.setShareHiddenCategoriesOf(db, {'theirs'});
    await service.reload();
    expect(CalendarCategories.partnerShown, isEmpty);
    final before = CalendarCategories.all.length;

    counter.onStatement = (sql, args) =>
        args.contains(SettingsKeys.shareHiddenCategories)
        ? Future<void>.error(StateError('settings read failed'))
        : null;
    await service.reload();
    counter.onStatement = null;

    expect(CalendarCategories.all, hasLength(before));
    expect(CalendarCategories.byId('mine'), isNotNull);
    expect(CalendarCategories.partnerShown.map((c) => c.id), ['theirs']);
  });

  group('what a load costs', () {
    Future<int> sharedOwnerReads() async {
      counter.reset();
      await service.reload();
      return [
        for (final statement in counter.captured)
          if (statement.args.contains(SyncDao.keySharedOwner)) statement,
      ].length;
    }

    test('a database that was never bound never asks for the shared '
        'account', () async {
      await insertCategory('mine');
      expect(await sharedOwnerReads(), 0);
    });

    test('a bound one asks once, whatever the rows', () async {
      await insertCategory('mine');
      await insertCategory('also-mine');
      await db.customStatement(
        "UPDATE calendar_categories SET owner_id = 'my-uid'",
      );
      expect(await sharedOwnerReads(), 1);
    });
  });

  group('nothing answers "saved" for a partner\'s category', () {
    test('an edit is refused before anything is stamped or queued', () async {
      await partnersCategories(['theirs']);
      final before = await row('theirs');

      final saved = await service.updateCategory(
        CalendarCategories.byId('theirs')!.copyWith(name: 'Mine now'),
      );

      expect(saved, isFalse);
      expect(await row('theirs'), before);
      expect(await queued(), isEmpty);
    });

    test('archiving and restoring are refused, by the service and by the '
        'DAO behind it', () async {
      await partnersCategories(['theirs']);
      final before = await row('theirs');

      expect(await service.setHidden('theirs', true), isFalse);
      for (final hidden in const [true, false]) {
        expect(
          await db.calendarCategoryDao.updateCategory(
            CalendarCategoriesCompanion(
              id: const Value('theirs'),
              isHidden: Value(hidden),
              updatedAt: Value(DateTime.utc(2026, 7, 1)),
            ),
          ),
          isFalse,
        );
      }
      expect(await row('theirs'), before);
      expect(await queued(), isEmpty);
    });

    test('an own category is still archived and answers true', () async {
      await insertCategory('mine');
      await service.reload();
      expect(await service.setHidden('mine', true), isTrue);
      expect(CalendarCategories.byId('mine')!.isHidden, isTrue);
    });

    test('an order that names one writes nothing', () async {
      await insertCategory('mine', sortOrder: 20);
      await partnersCategories(['theirs']);
      final before = [for (final c in CalendarCategories.all) c.sortOrder];

      final ordered = await service.reorder([
        'theirs',
        for (final c in service.categories) c.id,
      ]);

      expect(ordered, isFalse);
      expect([for (final c in CalendarCategories.all) c.sortOrder], before);
      expect(await queued(), isEmpty);
    });

    test('an order of the person\'s own is written and answers true', () async {
      await partnersCategories(['theirs']);
      final ids = [for (final c in service.categories) c.id].reversed.toList();

      expect(await service.reorder(ids), isTrue);
      expect([for (final c in service.categories) c.id], ids);
      expect((await row('theirs')).sortOrder, 0);
    });

    test('a delete is refused', () async {
      await partnersCategories(['theirs']);

      expect(await service.deleteCategory('theirs'), isFalse);
      expect((await row('theirs')).isDeleted, isFalse);
      expect(await queued(), isEmpty);
    });

    test('a delete of mine never moves my events into one: they go to '
        'Other', () async {
      await insertCategory('mine');
      await insertEvent('e1', 'mine');
      await partnersCategories(['theirs']);

      expect(
        await service.deleteCategory('mine', reassignTo: 'theirs'),
        isTrue,
      );
      final moved = await db.calendarEventDao.getByIdsIncludingDeleted(['e1']);
      expect(moved.single.category, 'other');
    });

    test('the DAO keeps one out of the reassignment too, whatever the '
        'catalogue says', () async {
      await insertCategory('mine');
      await insertEvent('e1', 'mine');
      await partnersCategories(['theirs']);

      expect(
        await db.calendarCategoryDao.tombstoneCascade(
          'mine',
          reassignTo: 'theirs',
        ),
        isTrue,
      );
      final moved = await db.calendarEventDao.getByIdsIncludingDeleted(['e1']);
      expect(moved.single.category, 'other');
    });

    test('a new category of mine takes the slot after my own, not after '
        'the partner\'s', () async {
      await insertCategory('mine', sortOrder: 40);
      await partnersCategories(['theirs']);

      final created = await service.create(
        name: 'New',
        colorValue: 0xFF112233,
        iconKey: 'event',
      );

      expect(created.sortOrder, 41);
    });

    test(
      'a category alert of my own may name one: it is a personal row',
      () async {
        await partnersCategories(['theirs']);
        final alerts = await EventAlertService.forTesting(db);

        await alerts.replaceForCategory('theirs', const [
          CategoryAlert(id: 'a1', categoryId: 'theirs', daysBefore: 1),
        ]);

        final stored = await db.categoryAlertDao.getAllActive();
        expect(stored.map((a) => a.categoryId), contains('theirs'));
        expect(alerts.categoryAlertsFor('theirs'), hasLength(1));
      },
    );
  });

  group('an event or a template of my own saved into a partner\'s category', () {
    final refusedTheirs = throwsA(
      isA<SharedRowException>()
          .having((e) => e.table, 'table', 'calendar_categories')
          .having((e) => e.id, 'id', 'theirs'),
    );

    tearDown(() {
      CalendarEventService.reset();
      EventTemplateService.reset();
    });

    test('a new event is refused by name, and nothing is cached or '
        'queued', () async {
      await partnersCategories(['theirs']);
      final events = await CalendarEventService.forTesting(db);

      await expectLater(
        events.upsert(
          CalendarEvent(
            id: 'new',
            title: 'New',
            categoryId: 'theirs',
            startDate: day,
          ),
        ),
        refusedTheirs,
      );

      expect(events.events.map((e) => e.id), isNot(contains('new')));
      expect(await queued(), isEmpty);
    });

    test('an edit that moves mine into one is refused, and the cache keeps '
        'the event as stored', () async {
      await insertCategory('mine');
      await insertEvent('e1', 'mine');
      await partnersCategories(['theirs']);
      final events = await CalendarEventService.forTesting(db);
      final stored = events.events.singleWhere((e) => e.id == 'e1');

      await expectLater(
        events.upsert(stored.copyWith(title: 'Renamed', categoryId: 'theirs')),
        refusedTheirs,
      );

      expect(events.events.singleWhere((e) => e.id == 'e1'), stored);
      expect(await queued(), isEmpty);
    });

    test('a new template is refused by name, never handed back as '
        'stored', () async {
      await partnersCategories(['theirs']);
      final templates = await EventTemplateService.forTesting(db);

      await expectLater(
        templates.create(
          const EventTemplate(id: '', name: 'Shift', categoryId: 'theirs'),
        ),
        refusedTheirs,
      );

      expect(templates.templates, isEmpty);
      expect(await queued(), isEmpty);
    });
  });

  group('the doors out', () {
    test('the category export holds the person\'s own and never the share '
        'mark', () async {
      await insertCategory('mine');
      await partnersCategories(['theirs']);
      await service.setShared('mine', 'pair-1');

      final exported = await service.exportData();

      expect(exported.map((c) => c['id']), contains('mine'));
      expect(exported.map((c) => c['id']), isNot(contains('theirs')));
      for (final category in exported) {
        expect(category.values, isNot(contains('pair-1')));
        expect(category.values, isNot(contains(partner)));
      }
    });

    group('the .ics export', () {
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      late Directory dir;
      late ImportExportService exports;

      setUp(() async {
        dir = await Directory.systemTemp.createTemp('anta_ics_partner');
        messenger.setMockMethodCallHandler(
          pathProvider,
          (call) async => dir.path,
        );
        final notes = NoteRepository(database: db);
        exports = ImportExportService(
          noteStorage: NoteStorageService(repository: notes),
          folderStorage: FolderStorageService(
            repository: FolderRepository(database: db),
          ),
          noteRepository: notes,
        );
      });

      tearDown(() async {
        messenger.setMockMethodCallHandler(pathProvider, null);
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      });

      // The door asks whose the event is, never whose its category is: a
      // partner's event in a built-in they share carries a category id of
      // the person's own.
      test('leaves out a partner\'s event — in their own category, with the '
          'category\'s name, and in a built-in they share', () async {
        await partnersCategories(['theirs']);

        final result = await exports.exportCalendar(
          events: [
            CalendarEvent(
              id: 'mine',
              title: 'My session',
              categoryId: 'gym',
              startDate: day,
            ),
            CalendarEvent(
              id: 'their',
              title: 'Their shift',
              categoryId: 'theirs',
              startDate: day,
              fromPartner: true,
            ),
            CalendarEvent(
              id: 'their-gym',
              title: 'Their session',
              categoryId: 'gym',
              startDate: day,
              fromPartner: true,
            ),
          ],
        );

        final body = await File(result.filePath).readAsString();
        expect(result.eventsExported, 1);
        expect(body, contains('My session'));
        expect(body, isNot(contains('Their shift')));
        expect(body, isNot(contains('Their session')));
        expect(body, isNot(contains('Shifts theirs')));
      });
    });
  });

  group('a restore on a phone that holds a partner\'s category', () {
    test('wipes the person\'s own and leaves the partner\'s, as the '
        'events\' restore leaves a partner\'s events', () async {
      await insertCategory('mine');
      await partnersCategories(['theirs']);

      await service.importData([
        {
          'id': 'restored',
          'name': 'Restored',
          'colorValue': 0xFF445566,
          'iconKey': 'event',
          'sortOrder': 10,
        },
      ]);

      expect(CalendarCategories.byId('mine'), isNull);
      expect(CalendarCategories.byId('restored')!.fromPartner, isFalse);
      expect(CalendarCategories.byId('theirs')!.fromPartner, isTrue);
      expect((await row('theirs')).ownerId, partner);
    });

    test('an archive row under a partner\'s id is the person\'s own and '
        'takes the place of the partner\'s copy', () async {
      await partnersCategories(['theirs']);

      await service.importData([
        {
          'id': 'theirs',
          'name': 'Mine from the archive',
          'colorValue': 0xFF445566,
          'iconKey': 'event',
          'sortOrder': 10,
        },
      ]);

      final restored = await row('theirs');
      expect(restored.ownerId, isNull);
      expect(restored.name, 'Mine from the archive');
      expect(CalendarCategories.byId('theirs')!.fromPartner, isFalse);
      expect(service.categories.map((c) => c.id), contains('theirs'));
    });
  });
}
