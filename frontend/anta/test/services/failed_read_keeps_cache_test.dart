import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_templates.dart';
import 'package:anta/constants/tag_catalog.dart';
import 'package:anta/constants/vocabularies.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_grid_filters.dart';
import 'package:anta/models/event_template.dart';
import 'package:anta/models/overview_list_options.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/event_template_service.dart';
import 'package:anta/services/filter_preset_service.dart';
import 'package:anta/services/body_search_indexer.dart';
import 'package:anta/services/overview_view_service.dart';
import 'package:anta/services/tag_catalog_service.dart';
import 'package:anta/services/vocabulary_service.dart';

import '../database/support/db_test_support.dart';
import 'support/body_index_support.dart';

void _resetSingletons() {
  CategoryService.reset();
  EventTemplateService.reset();
  FilterPresetService.reset();
  OverviewViewService.reset();
  TagCatalogService.reset();
  VocabularyService.reset();
}

/// A whole-table read that fails must leave a service's cache, and the
/// facade it publishes, as they were held: each of these services used to
/// answer a failed read with an empty list, which no reader can tell from a
/// table with no rows — the categories went from every picker and filter,
/// the saved filters and views read as never saved, the editor lost its
/// suggestions — until some later reload happened to succeed (settings
/// rework review, 2026-11-01). `CalendarEventService` has kept its cache
/// since the scalability pass; its own suite pins it.
void main() {
  late _FailingReads reads;
  late AppDatabase db;

  setUp(() async {
    _resetSingletons();
    reads = _FailingReads();
    db = await openTestDatabase(interceptor: reads);
  });

  tearDown(() async {
    reads.failing = null;
    _resetSingletons();
    await db.close();
  });

  /// The service's whole read of [table]: the one statement that both names
  /// it and orders its rows, which no keyed lookup or seed does.
  bool Function(String) wholeReadOf(String table) =>
      (sql) => sql.contains('FROM "$table"') && sql.contains('ORDER BY');

  group('categories', () {
    late CategoryService service;

    setUp(() async {
      service = await CategoryService.forTesting(db);
    });

    test('a reload whose read fails keeps the catalogue and the hidden '
        'set', () async {
      final held = [for (final c in CalendarCategories.all) c.id];
      expect(held, isNotEmpty);
      CalendarCategories.updatePartnerHidden(const {'theirs'});

      reads.failing = wholeReadOf('calendar_categories');
      await service.reload();

      expect(reads.failed, 1, reason: 'the read under test never ran');
      expect([for (final c in CalendarCategories.all) c.id], held);
      expect([for (final c in service.categories) c.id], held);
      // A hidden set republished from a read that never happened would
      // show every category the person chose to hide.
      expect(CalendarCategories.partnerHidden, {'theirs'});
    });

    test('a write whose read-back fails is not lost: the next reload '
        'publishes it', () async {
      reads.failing = wholeReadOf('calendar_categories');
      await service.setHidden('gym', true);

      expect(reads.failed, 1);
      expect(CalendarCategories.all, isNotEmpty);
      expect(CalendarCategories.resolve('gym').isHidden, isFalse);

      reads.failing = null;
      await service.reload();

      expect(CalendarCategories.resolve('gym').isHidden, isTrue);
    });
  });

  test(
    'templates: a failed read keeps the saved ones in every picker',
    () async {
      final service = await EventTemplateService.forTesting(db);
      final saved = await service.create(
        const EventTemplate(
          id: '',
          name: 'Push day',
          categoryId: 'gym',
          rule: OneTimeRecurrence(),
        ),
      );

      reads.failing = wholeReadOf('calendar_event_templates');
      await service.reload();

      expect(reads.failed, 1, reason: 'the read under test never ran');
      expect([for (final t in service.templates) t.id], [saved.id]);
      expect(CalendarTemplates.byId(saved.id)?.name, 'Push day');
    },
  );

  test('saved filters: a failed read keeps them, and the cap still '
      'counts them', () async {
    final service = await FilterPresetService.forTesting(db);
    const filters = CalendarGridFilters(trackedOnly: true);
    final saved = await service.create(name: 'Training', filters: filters);

    reads.failing = wholeReadOf('calendar_filter_presets');
    await service.reload();

    expect(reads.failed, 1, reason: 'the read under test never ran');
    expect([for (final p in service.presets) p.id], [saved!.id]);
    expect(service.matching(filters)?.id, saved.id);
  });

  test('saved filters at the cap stay full through a failed read: an empty '
      'cache would let a save past it', () async {
    final service = await FilterPresetService.forTesting(db);
    for (var i = 0; i < FilterPresetService.maxPresets; i++) {
      await service.create(
        name: 'Filter $i',
        filters: CalendarGridFilters(priorities: {i}),
      );
    }
    expect(service.isFull, isTrue);

    reads.failing = wholeReadOf('calendar_filter_presets');
    await service.reload();
    reads.failing = null;

    expect(service.isFull, isTrue);
    expect(
      await service.create(
        name: 'One too many',
        filters: const CalendarGridFilters(trackedOnly: true),
      ),
      isNull,
    );
  });

  _afterAResetGroup(() => db, () => reads, wholeReadOf);

  test('saved views: a failed read keeps them', () async {
    final service = await OverviewViewService.forTesting(db);
    final saved = await service.create(
      name: 'Q1 gym',
      period: OverviewCustomPeriod(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 3, 31),
      ),
      options: const OverviewListOptions(),
      categoryIds: const {'gym'},
    );

    reads.failing = wholeReadOf('overview_views');
    await service.reload();

    expect(reads.failed, 1, reason: 'the read under test never ran');
    expect([for (final v in service.views) v.id], [saved!.id]);
  });

  test('vocabularies: a failed read keeps the lists the editor suggests '
      'from', () async {
    final service = await VocabularyService.forTesting(db);
    final saved = await service.createVocabulary(
      name: 'Lifts',
      terms: const ['Bench press', 'Deadlift'],
    );

    reads.failing = wholeReadOf('vocabularies');
    await service.reload();

    expect(reads.failed, 1, reason: 'the read under test never ran');
    expect([for (final v in service.vocabularies) v.id], [saved.id]);
    expect(
      [for (final item in Vocabularies.byId(saved.id)!.items) item.term],
      ['Bench press', 'Deadlift'],
    );
  });

  test('tags: a failed read keeps the catalog the editor suggests '
      'from', () async {
    final folder = await db.folderDao.createFolder(name: 'Log');
    await db.noteDao.createNote(
      folderId: folder.id,
      title: 'Legs',
      content: '#squat',
    );
    await BodySearchIndexer(
      database: db,
      scheduler: inlineBodyIndexScheduler,
    ).drain();
    final service = await TagCatalogService.forTesting(db);
    expect([for (final t in TagCatalog.all) t.tag], ['squat']);

    // The catalog's one read: the ledger's tags, which nothing else selects.
    reads.failing = (sql) =>
        sql.contains('FROM note_search_ledger') && sql.contains('l.tags');
    await service.refresh();

    expect(reads.failed, 1, reason: 'the read under test never ran');
    expect([for (final t in service.tags) t.tag], ['squat']);
    expect([for (final t in TagCatalog.all) t.tag], ['squat']);
    expect([for (final c in TagCatalog.candidates) c.term], ['#squat']);
  });
}

/// The other side of keeping the cache: an instance a database switch has
/// already dropped must not publish it. Its read fails because the
/// connection closed under it, after the switch cleared the facade — a
/// republish there puts the closed database's rows back in front of every
/// picker of the new one.
void _afterAResetGroup(
  AppDatabase Function() db,
  _FailingReads Function() reads,
  bool Function(String) Function(String table) wholeReadOf,
) {
  group('an instance a switch dropped', () {
    test('never republishes its templates', () async {
      final old = await EventTemplateService.forTesting(db());
      await old.create(
        const EventTemplate(
          id: '',
          name: 'Other database',
          categoryId: 'gym',
          rule: OneTimeRecurrence(),
        ),
      );
      EventTemplateService.reset();
      expect(CalendarTemplates.all, isEmpty);

      reads().failing = wholeReadOf('calendar_event_templates');
      await old.reload();

      expect(reads().failed, 1, reason: 'the read under test never ran');
      expect(CalendarTemplates.all, isEmpty);
    });

    test('never republishes its vocabularies', () async {
      final old = await VocabularyService.forTesting(db());
      await old.createVocabulary(name: 'Other database', terms: const ['x']);
      VocabularyService.reset();
      expect(Vocabularies.all, isEmpty);

      reads().failing = wholeReadOf('vocabularies');
      await old.reload();

      expect(reads().failed, 1, reason: 'the read under test never ran');
      expect(Vocabularies.all, isEmpty);
    });
  });
}

/// Fails every read [failing] names while it is set — the one way to make a
/// DAO read throw under a real service.
class _FailingReads extends QueryInterceptor {
  bool Function(String statement)? failing;

  /// How many reads were failed, so a case can tell its read was reached.
  int failed = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (failing?.call(statement) ?? false) {
      failed++;
      throw StateError('read failed on purpose');
    }
    return super.runSelect(executor, statement, args);
  }
}
