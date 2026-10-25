import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/counter.dart';
import 'package:anta/pages/counter_per_note_page.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/counter_service.dart';

import '../database/support/db_test_support.dart';

/// The per-note values page words its failures from the bloc's typed error
/// rather than a raw exception string (S3c review F13).
void main() {
  late AppDatabase db;

  setUp(() async {
    db = await openTestDatabase();
    GetIt.I.registerSingleton<CounterService>(
      await CounterService.forTesting(db),
    );
    GetIt.I.registerSingleton<NoteRepository>(NoteRepository(database: db));
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  testWidgets('a counter that no longer exists reads as such', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CounterPerNotePage(
          counter: Counter(
            id: 'deleted-elsewhere',
            name: 'Laps',
            scope: CounterScope.perNote,
            createdAt: DateTime(2026, 10, 1),
          ),
        ),
      ),
    );
    // The bloc's open awaits work that fake time alone does not complete.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text(AppLocalizationsEn().counterNotFound), findsOneWidget);
    expect(find.text(AppLocalizationsEn().counterLoadError), findsNothing);
  });
}
