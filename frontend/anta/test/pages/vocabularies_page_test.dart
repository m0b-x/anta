import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
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
