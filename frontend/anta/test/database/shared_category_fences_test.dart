import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/daos/shared_row_dao.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/models/calendar_event.dart';

import 'support/db_test_support.dart';

/// The fences around a category another account shares with this one
/// (`docs/cloud-share-surfaces-roadmap.md` §7.5, `SharedRowFences`): it is
/// stored, changed and removed by the reader alone, and nothing of the
/// person's own takes it — no event and no template — while a category alert
/// of theirs may name it, as an alert on a shared event may. Every case runs
/// on a fresh install and on a database that took its fences from v56.
void main() {
  const partner = 'partner';
  final day = DateTime.utc(2026, 6, 1);

  /// A v55 database brought to v56: the category's mark and the fences of
  /// that build, without a single fence that names `calendar_categories`,
  /// and then the step.
  Future<AppDatabase> upgraded() async {
    final db = await openTestDatabase();
    for (final row
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'trigger' "
              "AND name LIKE 'shared_fence_%categor%'",
            )
            .get()) {
      await db.customStatement('DROP TRIGGER ${row.read<String>('name')}');
    }
    await db.customStatement('DROP INDEX idx_calendar_categories_shared_pair');
    await db.customStatement(
      'ALTER TABLE calendar_categories DROP COLUMN shared_stamp',
    );
    await db.customStatement(
      'ALTER TABLE calendar_categories DROP COLUMN shared_pair',
    );
    await DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      DatabaseSchema.v55FencesAgain,
      DatabaseSchema.v56CategorySharedPair,
    );
    return db;
  }

  for (final (install, open) in [
    ('a fresh install', openTestDatabase),
    ('a database upgraded through v56', upgraded),
  ]) {
    group('on $install', () {
      late AppDatabase db;

      setUp(() async => db = await open());
      tearDown(() async => db.close());

      Future<T> one<T>(String sql, [List<Object?> args = const []]) async {
        final row = await db
            .customSelect(sql, variables: [for (final a in args) Variable(a)])
            .getSingle();
        return row.data.values.single as T;
      }

      Future<void> category(String id) => db.calendarCategoryDao.insertCategory(
        CalendarCategoriesCompanion.insert(
          id: id,
          name: 'Category $id',
          colorValue: 0xFF336699,
          iconKey: 'event',
          createdAt: day,
          updatedAt: day,
        ),
      );

      CalendarEventsCompanion event(String id, String category) =>
          CalendarEventsCompanion.insert(
            id: id,
            title: 'Event $id',
            category: category,
            startDate: day,
            ruleKind: 'weekly',
            createdAt: day,
            updatedAt: day,
          );

      EventTemplatesCompanion template(String id, String category) =>
          EventTemplatesCompanion.insert(
            id: id,
            name: 'Template $id',
            category: category,
            createdAt: day,
            updatedAt: day,
            hlcTimestamp: '000000000001:0000:dev',
            deviceId: 'dev',
          );

      Future<String?> categoryOf(String table, String id) async {
        final rows = await db
            .customSelect(
              'SELECT category FROM $table WHERE id = ?',
              variables: [Variable(id)],
            )
            .get();
        return rows.isEmpty ? null : rows.single.read<String>('category');
      }

      /// `theirs` as the reader stores it, under the partner's account;
      /// `mine` with an event and a template of the person's own in it.
      setUp(() async {
        await category('theirs');
        await category('mine');
        await db.calendarEventDao.upsert(event('own', 'mine'));
        await db.eventTemplateDao.upsertTemplate(template('tpl', 'mine'));
        await db.customStatement(
          "UPDATE calendar_categories SET owner_id = '$partner' "
          "WHERE id = 'theirs'",
        );
        await db.syncDao.setValue(SyncDao.keySharedOwner, partner);
        await db.syncOutboxDao.clear();
      });

      test('a partner\'s category cannot be changed or deleted, by the app\'s '
          'writers or by a statement over many rows — and the writers that '
          'answer say the edit was lost', () async {
        final before = (await db.calendarCategoryDao.getByIdsIncludingDeleted([
          'theirs',
        ])).single;

        expect(
          await db.calendarCategoryDao.updateCategory(
            const CalendarCategoriesCompanion(
              id: Value('theirs'),
              name: Value('Renamed here'),
            ),
          ),
          isFalse,
        );
        expect(await db.calendarCategoryDao.softDeleteById('theirs'), isFalse);
        expect(
          await db.calendarCategoryDao.tombstoneCascade(
            'theirs',
            reassignTo: 'mine',
          ),
          isFalse,
        );
        expect(
          await db.calendarCategoryDao.setSharedPair('theirs', 'pair-1'),
          isFalse,
        );
        await db.calendarCategoryDao.reorder(['mine', 'theirs']);
        await db.customStatement(
          "UPDATE calendar_categories SET name = 'Every row', is_hidden = 1",
        );
        await db.customStatement(
          "UPDATE calendar_categories SET owner_id = NULL WHERE id = 'theirs'",
        );
        await db.customStatement("DELETE FROM calendar_categories");

        final after = (await db.calendarCategoryDao.getByIdsIncludingDeleted([
          'theirs',
        ])).single;
        expect(after, before);
        expect(
          await one<int>(
            "SELECT COUNT(*) FROM calendar_categories "
            "WHERE id = 'mine'",
          ),
          0,
          reason: 'the person\'s own row in the same statements was written',
        );
        expect(
          [
            for (final entry in await db.syncOutboxDao.pending())
              if (entry.rowKey == 'theirs') entry,
          ],
          isEmpty,
          reason: 'a lost edit queues nothing for the partner\'s row',
        );
      });

      test('no category of the person\'s own is made to look like one of '
          'the partner\'s, nor created under the partner\'s account', () async {
        await db.customStatement(
          "UPDATE calendar_categories SET owner_id = '$partner' "
          "WHERE id = 'mine'",
        );
        await db.customStatement(
          'INSERT INTO calendar_categories (id, name, color_value, icon_key, '
          'created_at, updated_at, hlc_timestamp, device_id, owner_id) '
          "VALUES ('planted', 'P', 1, 'event', 0, 0, 'h', 'd', '$partner')",
        );

        expect(
          await one<String?>(
            "SELECT owner_id FROM calendar_categories WHERE id = 'mine'",
          ),
          isNull,
        );
        expect(
          await one<int>(
            "SELECT COUNT(*) FROM calendar_categories WHERE id = 'planted'",
          ),
          0,
        );
      });

      final refusedTheirs = throwsA(
        isA<SharedRowException>()
            .having((e) => e.table, 'table', 'calendar_categories')
            .having((e) => e.id, 'id', 'theirs'),
      );

      test('a save of an event of the person\'s own into one is refused by '
          'name before anything is stamped or queued: a new event, a move '
          'with a rename beside it, an Undo that puts one back', () async {
        await expectLater(
          db.calendarEventDao.upsert(event('new', 'theirs')),
          refusedTheirs,
        );
        await expectLater(
          db.calendarEventDao.upsert(
            event('own', 'theirs').copyWith(title: const Value('Renamed')),
          ),
          refusedTheirs,
        );
        await expectLater(
          db.calendarEventDao.restoreEventCascade(
            event('restored', 'theirs'),
            marks: const {},
            descriptions: const {},
            skips: const {},
            alerts: const [],
          ),
          refusedTheirs,
        );

        expect(await categoryOf('calendar_events', 'new'), isNull);
        expect(await categoryOf('calendar_events', 'restored'), isNull);
        expect(await categoryOf('calendar_events', 'own'), 'mine');
        expect(
          await one<String>("SELECT title FROM calendar_events WHERE id = 'own'"),
          'Event own',
        );
        expect(await db.syncOutboxDao.pending(), isEmpty);
      });

      test('a save that leaves an event in the category it already names is '
          'not asked about the partner\'s', () async {
        await db.calendarEventDao.upsert(
          event('own', 'mine').copyWith(title: const Value('Renamed')),
        );
        await db.eventTemplateDao.upsertTemplate(
          template('tpl', 'mine').copyWith(name: const Value('Renamed')),
        );

        expect(
          await one<String>("SELECT title FROM calendar_events WHERE id = 'own'"),
          'Renamed',
        );
        expect(
          await one<String>(
            "SELECT name FROM calendar_event_templates WHERE id = 'tpl'",
          ),
          'Renamed',
        );
      });

      test('a save of a template into one is refused the same way', () async {
        await expectLater(
          db.eventTemplateDao.upsertTemplate(template('new', 'theirs')),
          refusedTheirs,
        );
        await expectLater(
          db.eventTemplateDao.upsertTemplate(
            template('tpl', 'theirs').copyWith(name: const Value('Renamed')),
          ),
          refusedTheirs,
        );

        expect(await categoryOf('calendar_event_templates', 'new'), isNull);
        expect(await categoryOf('calendar_event_templates', 'tpl'), 'mine');
        expect(
          await one<String>(
            "SELECT name FROM calendar_event_templates WHERE id = 'tpl'",
          ),
          'Template tpl',
        );
        expect(await db.syncOutboxDao.pending(), isEmpty);
      });

      test('the fences stay the last line for an event: not reassigned to '
          'one by a statement over many rows; a delete that names it as the '
          'target moves its events to the fallback instead', () async {
        await db.calendarEventDao.reassignCategory('mine', 'theirs');
        await db.customStatement(
          "UPDATE calendar_events SET category = 'theirs'",
        );

        expect(await categoryOf('calendar_events', 'own'), 'mine');

        expect(
          await db.calendarCategoryDao.tombstoneCascade(
            'mine',
            reassignTo: 'theirs',
          ),
          isTrue,
        );
        expect(
          await categoryOf('calendar_events', 'own'),
          kFallbackCategoryId,
          reason: 'never left on the tombstoned id',
        );
        expect(
          await categoryOf('calendar_event_templates', 'tpl'),
          kFallbackCategoryId,
        );
      });

      test('and for a template', () async {
        await db.eventTemplateDao.reassignCategory('mine', 'theirs');
        await db.customStatement(
          "UPDATE calendar_event_templates SET category = 'theirs'",
        );

        expect(await categoryOf('calendar_event_templates', 'tpl'), 'mine');
      });

      test('a category alert of the person\'s own may name one: it is a '
          'personal row', () async {
        await db.categoryAlertDao.replaceForCategory('theirs', [
          CalendarCategoryAlertsCompanion.insert(
            id: 'alert',
            categoryId: 'theirs',
            createdAt: day,
            updatedAt: day,
            hlcTimestamp: '000000000001:0000:dev',
            deviceId: 'dev',
          ),
        ]);

        expect(
          await one<int>(
            'SELECT COUNT(*) FROM calendar_category_alerts '
            "WHERE category_id = 'theirs' AND is_deleted = 0",
          ),
          1,
        );
      });

      group('a replacing insert does not get past a fence', () {
        test('an archive\'s event or template in the partner\'s category is '
            'not stored, and one of the person\'s own under the same id is '
            'left as it was', () async {
          await db.calendarEventDao.importAll([
            event('archived', 'theirs'),
            event('own', 'theirs'),
          ]);
          await db.eventTemplateDao.importAll([
            template('archived', 'theirs'),
            template('tpl', 'theirs'),
          ]);

          expect(await categoryOf('calendar_events', 'archived'), isNull);
          expect(await categoryOf('calendar_events', 'own'), 'mine');
          expect(
            await categoryOf('calendar_event_templates', 'archived'),
            isNull,
          );
          expect(await categoryOf('calendar_event_templates', 'tpl'), 'mine');
        });

        test('an archive\'s category under the partner\'s id is the person\'s '
            'own from then on — the partner\'s copy gives way, as it would '
            'to the own pull — and never stored as the partner\'s', () async {
          await db.calendarCategoryDao.importAll([
            CalendarCategoriesCompanion.insert(
              id: 'theirs',
              name: 'Mine, restored',
              colorValue: 0xFF112233,
              iconKey: 'event',
              createdAt: day,
              updatedAt: day,
            ),
          ]);

          final row = (await db.calendarCategoryDao.getByIdsIncludingDeleted([
            'theirs',
          ])).single;
          expect(row.name, 'Mine, restored');
          expect(row.ownerId, isNull);
        });

        test(
          'an archive\'s category alert may name the partner\'s category',
          () async {
            await db.categoryAlertDao.importAll([
              CalendarCategoryAlertsCompanion.insert(
                id: 'alert',
                categoryId: 'theirs',
                createdAt: day,
                updatedAt: day,
                hlcTimestamp: '000000000001:0000:dev',
                deviceId: 'dev',
              ),
            ]);

            expect(
              await one<int>(
                'SELECT COUNT(*) FROM calendar_category_alerts '
                "WHERE category_id = 'theirs'",
              ),
              1,
            );
          },
        );
      });

      test('the reader stores, changes and removes the partner\'s category '
          'inside its own transaction', () async {
        await db.sharedRowDao.writing(() async {
          await db.customStatement(
            "UPDATE calendar_categories SET name = 'Theirs, renamed' "
            "WHERE id = 'theirs'",
          );
        });
        expect(
          await one<String>(
            "SELECT name FROM calendar_categories WHERE id = 'theirs'",
          ),
          'Theirs, renamed',
        );
        await db.sharedRowDao.writing(() async {
          await db.customStatement(
            "DELETE FROM calendar_categories WHERE id = 'theirs'",
          );
        });
        expect(
          await one<int>(
            "SELECT COUNT(*) FROM calendar_categories WHERE id = 'theirs'",
          ),
          0,
        );
      });
    });
  }

  test('a database upgraded through v56 holds exactly the fences a fresh '
      'install does', () async {
    Future<Map<String, String>> fences(AppDatabase db) async => {
      for (final row
          in await db
              .customSelect(
                "SELECT name, sql FROM sqlite_master WHERE type = 'trigger'",
              )
              .get())
        row.read<String>('name'): row.read<String>('sql'),
    };
    final fresh = await openTestDatabase();
    final old = await upgraded();
    addTearDown(fresh.close);
    addTearDown(old.close);

    final created = await fences(fresh);
    expect(created.keys, contains('shared_fence_calendar_categories_update'));
    expect(
      created.keys,
      contains('shared_fence_calendar_event_templates_onto_category'),
    );
    expect(await fences(old), created);
  });
}
