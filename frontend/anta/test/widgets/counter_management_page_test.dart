import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/counter/counter_bloc.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/counter.dart';
import 'package:anta/pages/counter_management_page.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/layout_errors.dart';

/// The counters page's reset and delete, pinned against today's behaviour
/// before S6 of the settings rework (`docs/settings-rework-roadmap.md`, §6
/// "Pinned in S0") touches the page: each is read back from the service and
/// the table, not only from the row, and each dialog's cancel is a no-op.
void main() {
  late AppDatabase db;
  late CounterService service;
  late CounterBloc bloc;
  late String laps;
  late String sets;

  final l10n = AppLocalizationsEn();

  setUp(() async {
    SettingsService.reset();
    db = await openTestDatabase();
    SettingsService.forTesting(db);
    service = await CounterService.forTesting(db);
    laps = await service.addCounter(name: 'Laps', startValue: 0);
    sets = await service.addCounter(name: 'Sets', startValue: 1);
    await service.setGlobalValue(laps, 7);
    await service.setGlobalValue(sets, 4);
    await service.flush();
    bloc = CounterBloc(counterService: service);
  });

  tearDown(() async {
    await bloc.close();
    await service.flush();
    CounterService.reset();
    SettingsService.reset();
    await db.close();
  });

  /// Drift answers on futures `FakeAsync` alone never completes, so real time
  /// and pumped frames are interleaved rather than `pumpAndSettle` used.
  Future<void> settle(WidgetTester tester, {int rounds = 14}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(412, 915),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    String? noteId,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bloc.add(LoadCounters(noteId: noteId));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: BlocProvider<CounterBloc>.value(
          value: bloc,
          child: CounterManagementPage(noteId: noteId),
        ),
      ),
    );
    await settle(tester);
  }

  Finder card(String id) => find.byKey(ValueKey(id));

  /// Opens [id]'s ⋮ and picks [action] — the menu item's own label, the one
  /// place it is shown while the menu is open.
  Future<void> chooseFromMenu(
    WidgetTester tester,
    String id,
    String action,
  ) async {
    await tester.tap(
      find.descendant(of: card(id), matching: find.byIcon(Icons.more_vert)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  Future<void> answerDialog(WidgetTester tester, String id) async {
    await tester.tap(find.bySemanticsIdentifier(id));
    await settle(tester);
    // A reset is written by the service's debounced flush; the app forces it
    // on pause, and so does the suite before it reads the table.
    await tester.runAsync(service.flush);
  }

  Map<String, int> shownValues() => (bloc.state as CounterLoaded).counterValues;

  group('Reset', () {
    testWidgets('confirmed puts the global value back to its start and keeps '
        'the counter', (tester) async {
      await pumpPage(tester);
      expect(
        find.descendant(of: card(laps), matching: find.text('7')),
        findsOneWidget,
      );

      await chooseFromMenu(tester, laps, l10n.resetCounter);
      expect(find.text(l10n.resetCounterConfirm), findsOneWidget);
      await answerDialog(tester, SemanticsIds.sheetConfirm);

      expect(find.text(l10n.counterResetSuccess), findsOneWidget);
      expect(service.getGlobalValue(laps), 0);
      expect(await tester.runAsync(() => db.counterDao.getValue(laps, '')), 0);
      expect(shownValues()[laps], 0);
      expect(
        find.descendant(of: card(laps), matching: find.text('0')),
        findsOneWidget,
      );
      // The counter itself and its neighbour are untouched.
      final rows = await tester.runAsync(db.counterDao.getAllCounters);
      expect(rows!.map((r) => r.id), containsAll([laps, sets]));
      expect(await tester.runAsync(() => db.counterDao.getValue(sets, '')), 4);
      expect(service.getGlobalValue(sets), 4);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('cancelled changes nothing', (tester) async {
      await pumpPage(tester);

      await chooseFromMenu(tester, laps, l10n.resetCounter);
      await answerDialog(tester, SemanticsIds.sheetCancel);

      expect(find.text(l10n.counterResetSuccess), findsNothing);
      expect(service.getGlobalValue(laps), 7);
      expect(await tester.runAsync(() => db.counterDao.getValue(laps, '')), 7);
      expect(shownValues()[laps], 7);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('opened for a note, confirmed resets the note\'s own value '
        'row and leaves the global row alone', (tester) async {
      const note = 'note-1';
      final reps = await tester.runAsync(() async {
        final id = await service.addCounter(
          name: 'Reps',
          startValue: 2,
          scope: CounterScope.perNote,
        );
        await service.setGlobalValue(id, 5);
        await service.setValueForNote(id, 9, noteId: note);
        await service.flush();
        return id;
      });
      await pumpPage(tester, noteId: note);
      expect(shownValues()[reps], 9);

      await chooseFromMenu(tester, reps!, l10n.resetCounter);
      await answerDialog(tester, SemanticsIds.sheetConfirm);

      expect(find.text(l10n.counterResetSuccess), findsOneWidget);
      expect(
        await tester.runAsync(() => db.counterDao.getValue(reps, note)),
        2,
      );
      expect(shownValues()[reps], 2);
      expect(await tester.runAsync(() => db.counterDao.getValue(reps, '')), 5);
      expect(service.getGlobalValue(reps), 5);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Delete', () {
    testWidgets('confirmed tombstones the counter and its value, and the page '
        'and the service drop it', (tester) async {
      await pumpPage(tester);

      await chooseFromMenu(tester, laps, l10n.deleteCounter);
      expect(find.text(l10n.deleteCounterConfirm), findsOneWidget);
      await answerDialog(tester, SemanticsIds.sheetConfirm);

      expect(find.text(l10n.counterDeleteSuccess), findsOneWidget);
      expect(card(laps), findsNothing);
      expect(card(sets), findsOneWidget);
      expect(service.counters.map((c) => c.id), [sets]);
      expect(shownValues().containsKey(laps), isFalse);

      final live = await tester.runAsync(db.counterDao.getAllCounters);
      expect(live!.map((r) => r.id), [sets]);
      // A soft delete: the row stays as a tombstone for sync, and so does the
      // global value row (`noteId == ''`).
      final tombstones = await tester.runAsync(
        () => db.counterDao.getCountersByIdsIncludingDeleted([laps]),
      );
      expect(tombstones!.single.isDeleted, isTrue);
      expect(tombstones.single.deletedAt, isNotNull);
      expect(
        await tester.runAsync(() => db.counterDao.getValue(laps, '')),
        isNull,
      );
      final valueRows = await tester.runAsync(
        () => db.counterDao.getValuesByKeysIncludingDeleted([
          (counterId: laps, noteId: ''),
        ]),
      );
      expect(valueRows!.single.isDeleted, isTrue);
      expect(await tester.runAsync(() => db.counterDao.getValue(sets, '')), 4);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('cancelled changes nothing', (tester) async {
      await pumpPage(tester);

      await chooseFromMenu(tester, laps, l10n.deleteCounter);
      await answerDialog(tester, SemanticsIds.sheetCancel);

      expect(find.text(l10n.counterDeleteSuccess), findsNothing);
      expect(card(laps), findsOneWidget);
      expect(service.counters.map((c) => c.id), containsAll([laps, sets]));
      final live = await tester.runAsync(db.counterDao.getAllCounters);
      expect(live!.map((r) => r.id), containsAll([laps, sets]));
      expect(await tester.runAsync(() => db.counterDao.getValue(laps, '')), 7);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('smoke', () {
    // Measured with Roboto: the test font's square glyphs are about twice as
    // wide, and would report overflows no device shows.
    setUpAll(loadGoldenFonts);

    testWidgets('de 2.0 on 360 × 780 fits with no exception', (tester) async {
      final errors = await layoutErrorsDuring(
        () => pumpPage(
          tester,
          size: const Size(360, 780),
          locale: const Locale('de'),
          textScale: 2.0,
        ),
      );

      expect(errors.map((e) => e.exceptionAsString()), isEmpty);
      expect(tester.takeException(), isNull);
      expect(card(laps), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
