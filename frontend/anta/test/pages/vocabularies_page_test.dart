import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/vocabularies.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/pages/vocabularies_page.dart';
import 'package:anta/services/vocabulary_service.dart';

import '../database/support/db_test_support.dart';

/// The vocabularies page follows lists re-read beneath it: a sync pull's
/// reload (S3c review F12), and the service of another database taking the
/// singleton's place after a switch (S4a review L12).
void main() {
  late AppDatabase db;
  late VocabularyService service;
  // The switch case holds two databases at once, as a switch briefly does.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() async {
    db = await openTestDatabase();
    VocabularyService.reset();
    service = await VocabularyService.forTesting(db);
  });

  tearDown(() async {
    VocabularyService.reset();
    await db.close();
  });

  /// A list written beneath the service, as a sync pull writes it.
  Future<void> writeList(AppDatabase into, String id, String name) =>
      into.vocabularyDao.importVocabulary(
        VocabulariesCompanion(
          id: Value(id),
          name: Value(name),
          createdAt: Value(DateTime.utc(2026, 1, 1)),
          updatedAt: Value(DateTime.utc(2026, 1, 1)),
        ),
      );

  /// A term written beneath the service, as a pull writes one.
  Future<void> writeItem(
    AppDatabase into,
    String id,
    String vocabularyId,
    String term,
  ) => into.vocabularyDao.importItem(
    VocabularyItemsCompanion(
      id: Value(id),
      vocabularyId: Value(vocabularyId),
      term: Value(term),
      createdAt: Value(DateTime.utc(2026, 1, 1)),
      updatedAt: Value(DateTime.utc(2026, 1, 1)),
    ),
  );

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VocabulariesPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a reload beneath the service shows the merged lists', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('Exercises'), findsNothing);

    await tester.runAsync(() async {
      await writeList(db, 'v1', 'Exercises');
      await service.reload();
    });
    await tester.pumpAndSettle();

    expect(find.text('Exercises'), findsOneWidget);
  });

  /// The merge-created duplicate the phase record §8 accepts: both devices
  /// added the same term and both rows arrived. It must read as one term in
  /// the suggestions, collapse on the next save, and delete whole
  /// (A1b review R31).
  testWidgets('a term two live rows hold reads as one through the list, the '
      'suggestions, an edit and a delete', (tester) async {
    final en = AppLocalizationsEn();
    await tester.runAsync(() async {
      await writeList(db, 'v1', 'Exercises');
      await writeItem(db, 'i1', 'v1', 'Bench Press');
      await writeItem(db, 'i2', 'v1', 'Bench Press');
      await service.reload();
    });
    await pumpPage(tester);

    // The list counts lines, which is what the editor opens on.
    expect(find.text('Exercises'), findsOneWidget);
    expect(find.text(en.vocabularyTermCount(2)), findsOneWidget);
    // The pills take one candidate per folded term (A1b review R35).
    expect([for (final c in Vocabularies.candidates) c.term], ['Bench Press']);

    // An edit: the save collapses the pair and keeps the term.
    await tester.tap(find.text('Exercises'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.save));
    await tester.pumpAndSettle();

    final live = await tester.runAsync(() => db.vocabularyDao.getAllItems());
    expect([for (final row in live!) row.term], ['Bench Press']);
    expect(find.text(en.vocabularyTermCount(1)), findsOneWidget);

    // A delete: the surviving row and the tombstone both go.
    await tester.tap(find.byTooltip(en.deleteVocabulary));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.delete));
    await tester.pumpAndSettle();

    expect(find.text('Exercises'), findsNothing);
    expect(
      await tester.runAsync(() => db.vocabularyDao.getAllItems()),
      isEmpty,
    );
    expect(Vocabularies.candidates, isEmpty);
  });

  testWidgets("after a database switch the page shows the new database's "
      'lists and follows its service', (tester) async {
    await tester.runAsync(() async {
      await writeList(db, 'v1', 'Old list');
      await service.reload();
    });
    await pumpPage(tester);
    expect(find.text('Old list'), findsOneWidget);

    final switched = (await tester.runAsync(() => openTestDatabase()))!;
    addTearDown(switched.close);
    await tester.runAsync(() async {
      await writeList(switched, 'v2', 'Switched list');
      VocabularyService.reset();
      await VocabularyService.forTesting(switched);
    });
    await tester.pumpAndSettle();

    expect(find.text('Switched list'), findsOneWidget);
    expect(find.text('Old list'), findsNothing);

    await tester.runAsync(() async {
      await writeList(switched, 'v3', 'Pulled list');
      await (await VocabularyService.getInstance()).reload();
    });
    await tester.pumpAndSettle();

    expect(find.text('Pulled list'), findsOneWidget);
  });
}
