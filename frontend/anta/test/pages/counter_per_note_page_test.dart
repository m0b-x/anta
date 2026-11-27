import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/counter.dart';
import 'package:anta/pages/counter_per_note_page.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/app_navigator.dart';
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

  group('Reset and Reset All say how they went', () {
    final l10n = AppLocalizationsEn();
    late CounterService service;
    late String laps;

    setUp(() async {
      service = GetIt.I<CounterService>();
      final note = await db.noteDao.createNote(folderId: 'f1', title: 'Log');
      laps = await service.addCounter(
        name: 'Laps',
        scope: CounterScope.perNote,
        startValue: 0,
      );
      await service.setValueForNote(laps, 3, noteId: note.id);
      await service.flush();
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 14; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CounterPerNotePage(counter: service.getCounterById(laps)!),
        ),
      );
      await settle(tester);
    }

    /// Opens the dialog of the card's Reset, or of the page's Reset All.
    Future<void> ask(WidgetTester tester, {required bool all}) async {
      if (all) {
        await tester.tap(find.text(l10n.counterResetAllNotes));
      } else {
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.resetCounter));
      }
      await tester.pumpAndSettle();
    }

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sheetConfirm));
      await settle(tester);
    }

    for (final all in [false, true]) {
      final what = all ? 'Reset All' : 'Reset';
      final success = all
          ? l10n.counterResetAllSuccess
          : l10n.counterResetSuccess;

      testWidgets('$what that worked says so', (tester) async {
        await pumpPage(tester);

        await ask(tester, all: all);
        await confirm(tester);

        expect(find.text(success), findsOneWidget);
        expect(find.text(l10n.categoryChangeFailed), findsNothing);
        expect(find.text('0'), findsOneWidget, reason: 'the value shown');
        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('$what that failed says so, never that it worked', (
        tester,
      ) async {
        await pumpPage(tester);
        // Gone beneath the page, as a sync pull can do: the card is still
        // drawn.
        await tester.runAsync(() => service.deleteCounter(laps));

        await ask(tester, all: all);
        await confirm(tester);

        expect(find.text(success), findsNothing);
        expect(find.text(l10n.categoryChangeFailed), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    // A single Reset cannot answer that nothing was attempted from this page:
    // the card that offers it is drawn only over loaded values, and it sends
    // the Reset in the turn its dialog closes. Reset All's button outlives a
    // page that stopped being loaded beneath its open dialog.
    testWidgets('Reset All that was not attempted says nothing', (
      tester,
    ) async {
      await pumpPage(tester);
      await ask(tester, all: true);
      // A pull removed the counter while the dialog was open: the page now
      // shows its error, not values.
      await tester.runAsync(() => service.deleteCounter(laps));
      // In the test's zone: the reload queues behind the page's own reads,
      // which `settle` moves on together with the database.
      unawaited(service.reload());
      await settle(tester);
      expect(find.text(l10n.counterNotFound), findsOneWidget);

      await confirm(tester);

      expect(find.text(l10n.counterResetAllSuccess), findsNothing);
      expect(find.text(l10n.categoryChangeFailed), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('after a database switch', () {
    late Directory tempDir;
    late CounterService live;
    late String laps;

    // One file for the group: `AppDatabase` keeps its instance per name, so
    // a case that closed it would hand the next one a closed handle.
    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('anta_counter_page');
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => tempDir.path,
          );
    });

    tearDownAll(() async {
      await (await AppDatabase.getInstance()).close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    // GetIt still holds the service of the top-level set-up, standing for
    // the one built at launch; the singleton is the switched-to database's.
    setUp(() async {
      live = await CounterService.getInstance();
      laps = await live.addCounter(name: 'Laps', scope: CounterScope.perNote);
    });

    tearDown(CounterService.reset);

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    void expectLiveService() {
      expect(find.text(AppLocalizationsEn().counterNotFound), findsNothing);
      expect(
        find.text(AppLocalizationsEn().counterPerNoteEmpty),
        findsOneWidget,
      );
    }

    testWidgets('the page reads the live service, not the one GetIt kept', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CounterPerNotePage(counter: live.getCounterById(laps)!),
        ),
      );
      await settle(tester);

      expectLiveService();
    });

    testWidgets('opened before anything asked for the switched-to service, '
        'the page still gets it', (tester) async {
      final counter = live.getCounterById(laps)!;
      // The switch dropped the singleton and nothing has opened it since.
      CounterService.reset();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  AppNavigator.toCounterPerNote(context, counter: counter),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await settle(tester);

      expectLiveService();
    });
  });
}
