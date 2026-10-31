import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/vocabulary.dart';
import 'package:anta/pages/vocabulary_editor_page.dart';
import 'package:anta/services/vocabulary_service.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../widgets/support/layout_errors.dart';

/// The vocabulary editor's smoke suite (D14 of
/// `docs/settings-rework-roadmap.md`), pinned before a slice of the settings
/// rework touches it: it opens new and on a stored list, measures at de 2.0
/// on the small phone, its details fold and its switch flip without a write,
/// and leaving it unsaved writes nothing.
///
/// The page has no dialog of its own today — no discard prompt and no
/// delete — so the suite pins that leaving with edits typed simply drops
/// them.
void main() {
  late AppDatabase db;
  late Vocabulary exercises;

  final l10n = AppLocalizationsEn();

  setUp(() async {
    db = await openTestDatabase();
    VocabularyService.reset();
    final service = await VocabularyService.forTesting(db);
    exercises = await service.createVocabulary(
      name: 'Exercises',
      terms: const [';; Legs', 'Squat', 'Lunge', 'Bench Press'],
    );
  });

  tearDown(() async {
    VocabularyService.reset();
    await db.close();
  });

  /// The lists and then their terms, row by row, as the tables hold them.
  Future<List<Object>> stored(WidgetTester tester) async =>
      (await tester.runAsync<List<Object>>(
        () async => [
          ...await db.vocabularyDao.getAllVocabularies(),
          ...await db.vocabularyDao.getAllItems(),
        ],
      ))!;

  /// Pushes the editor over a host page, the way the vocabularies page opens
  /// it, and returns a holder for what the route pops with.
  Future<List<Vocabulary?>> pumpEditor(
    WidgetTester tester, {
    Vocabulary? initial,
    Size size = const Size(412, 915),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final results = <Vocabulary?>[];
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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => results.add(
                  await Navigator.of(context).push<Vocabulary>(
                    MaterialPageRoute(
                      builder: (_) => VocabularyEditorPage(initial: initial),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  final nameField = field(l10n.vocabularyName);

  /// The last field on the page, whether or not the details are folded.
  final termsField = find.byType(TextField).last;

  TextEditingController controllerOf(WidgetTester tester, Finder field) =>
      tester.widget<TextField>(field).controller!;

  FilledButton saveButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, l10n.save));

  testWidgets('new, it opens empty on the name with Save disabled', (
    tester,
  ) async {
    await pumpEditor(tester);

    expect(find.text(l10n.createVocabulary), findsOneWidget);
    expect(find.text(l10n.vocabularyTermCount(0)), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);
    final name = tester.widget<TextField>(field(l10n.vocabularyName));
    expect(name.controller!.text, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stored, it opens on the name, the terms one per line and the '
      'count without the header', (tester) async {
    await pumpEditor(tester, initial: exercises);

    expect(find.text(l10n.editVocabulary), findsOneWidget);
    expect(controllerOf(tester, nameField).text, 'Exercises');
    expect(
      controllerOf(tester, termsField).text,
      ';; Legs\nSquat\nLunge\nBench Press',
    );
    expect(find.text(l10n.vocabularyTermCount(3)), findsOneWidget);
    expect(saveButton(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the details fold and reopen, and the switch flips, writing '
      'nothing', (tester) async {
    final before = await stored(tester);
    await pumpEditor(tester, initial: exercises);

    await tester.tap(find.byTooltip(l10n.vocabularyDetails));
    await tester.pumpAndSettle();
    expect(field(l10n.vocabularyName), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);

    await tester.tap(find.byTooltip(l10n.vocabularyDetails));
    await tester.pumpAndSettle();
    expect(field(l10n.vocabularyName), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );

    expect(await stored(tester), before);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // Today's state: no discard prompt guards typed edits, so system back
  // leaves at once and drops them.
  testWidgets('back from a stored list with edits typed pops null and '
      'writes nothing, with no prompt (known; not scheduled)', (tester) async {
    final before = await stored(tester);
    final results = await pumpEditor(tester, initial: exercises);

    // The switch first: focusing the terms folds the details away.
    await tester.tap(find.byType(SwitchListTile));
    await tester.enterText(nameField, 'Gym');
    await tester.enterText(termsField, 'Deadlift');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(VocabularyEditorPage), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(results, [null]);
    expect(await stored(tester), before);
    final service = await VocabularyService.getInstance();
    expect(service.vocabularies.single.name, 'Exercises');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('back from a new list with a name typed pops null and creates '
      'nothing', (tester) async {
    final before = await stored(tester);
    final results = await pumpEditor(tester);

    await tester.enterText(field(l10n.vocabularyName), 'Stretches');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(VocabularyEditorPage), findsNothing);
    expect(results, [null]);
    expect(await stored(tester), before);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('smoke', () {
    // Measured with Roboto: the test font's square glyphs are about twice as
    // wide, and would report overflows no device shows.
    setUpAll(loadGoldenFonts);

    for (final stored in [false, true]) {
      final which = stored ? 'stored' : 'new';
      testWidgets('$which, de 2.0 on 360 × 780 fits with no exception', (
        tester,
      ) async {
        final errors = await layoutErrorsDuring(
          () => pumpEditor(
            tester,
            initial: stored ? exercises : null,
            size: const Size(360, 780),
            locale: const Locale('de'),
            textScale: 2.0,
          ),
        );

        expect(errors.map((e) => e.exceptionAsString()), isEmpty);
        expect(tester.takeException(), isNull);
        expect(find.byType(VocabularyEditorPage), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });
}
