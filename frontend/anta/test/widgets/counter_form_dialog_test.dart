import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/counter.dart';
import 'package:anta/widgets/app_dialogs.dart';
import 'package:anta/widgets/counter_form_dialog.dart';

/// The counter form refuses a number it cannot keep (review C12): a step of
/// 0 is a counter no tap moves, and a field that does not parse was saved as
/// 1, a value nobody typed. Save is held, and the field says why.
void main() {
  late List<CounterFormResult?> answers;

  Future<void> open(
    WidgetTester tester, {
    Counter? existing,
    Locale locale = const Locale('en'),
    double textScale = 1.0,
  }) async {
    answers = [];
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
                onPressed: () async => answers.add(
                  await AppDialogs.counterForm(context, existing: existing),
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
  }

  Finder field(String label) =>
      find.widgetWithText(TextField, label, skipOffstage: false);

  Future<void> type(WidgetTester tester, String label, String text) async {
    await tester.enterText(field(label), text);
    await tester.pumpAndSettle();
  }

  /// The reason a field shows: every reason is also laid out unseen in its
  /// caption slot, which takes no pointer.
  Finder reason(String text) => find.text(text).hitTestable();

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  bool saveEnabled(WidgetTester tester) => tester
      .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
      .enabled;

  testWidgets('a step of 0 holds Save and says so', (tester) async {
    await open(tester);
    await type(tester, 'Counter Name', 'Sets');
    await type(tester, 'Step', '0');

    expect(reason("Step can't be 0"), findsOneWidget);
    expect(saveEnabled(tester), isFalse);
    await save(tester);
    expect(answers, isEmpty, reason: 'the form is still open');
  });

  for (final (label, text) in [
    ('Start Value', '-'),
    ('Start Value', ''),
    ('Step', '-'),
    ('Step', '99999999999999999999'),
  ]) {
    testWidgets('"$text" as the ${label.toLowerCase()} holds Save and says '
        'so, never saved as 1', (tester) async {
      await open(tester);
      await type(tester, 'Counter Name', 'Sets');
      await type(tester, label, text);

      expect(reason('Enter a whole number'), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      await save(tester);
      expect(answers, isEmpty, reason: 'the form is still open');
    });
  }

  testWidgets('a number typed again releases Save and is what is saved', (
    tester,
  ) async {
    await open(tester);
    await type(tester, 'Counter Name', 'Sets');
    await type(tester, 'Step', '0');
    await type(tester, 'Step', '-2');
    await type(tester, 'Start Value', '0');

    expect(reason("Step can't be 0"), findsNothing);
    expect(saveEnabled(tester), isTrue);
    await save(tester);

    final result = answers.single!;
    expect(result.name, 'Sets');
    expect(result.startValue, 0);
    expect(result.step, -2);
  });

  testWidgets('an edit opens on the counter and saves it as typed', (
    tester,
  ) async {
    await open(
      tester,
      existing: Counter(
        id: 'c1',
        name: 'Laps',
        startValue: 5,
        step: 2,
        scope: CounterScope.perNote,
        createdAt: DateTime(2026, 11, 27),
      ),
    );
    await type(tester, 'Step', '3');
    await save(tester);

    final result = answers.single!;
    expect(result.name, 'Laps');
    expect(result.startValue, 5);
    expect(result.step, 3);
    expect(result.scope, CounterScope.perNote);
  });

  testWidgets('a field emptied between its last frame and the Save tap '
      'keeps the form open and throws nothing', (tester) async {
    await open(tester);
    await type(tester, 'Counter Name', 'Sets');
    await type(tester, 'Step', '5');
    await tester.showKeyboard(field('Step'));
    tester.testTextInput.updateEditingValue(TextEditingValue.empty);

    // No pump: Save is still drawn enabled from the frame before.
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(answers, isEmpty, reason: 'the form is still open');
    expect(reason('Enter a whole number'), findsOneWidget);
  });

  for (final (locale, scale, start, step, invalid) in [
    ('en', 1.0, 'Start Value', 'Step', 'Enter a whole number'),
    ('de', 2.0, 'Startwert', 'Schritt', 'Ganze Zahl eingeben'),
  ]) {
    testWidgets('nothing below a field moves when its error comes and goes '
        '($locale, text scale $scale)', (tester) async {
      await open(tester, locale: Locale(locale), textScale: scale);
      // Measured from the start field: at 2.0 the form scrolls to the field
      // being typed in, which moves everything together.
      double top(Finder finder) => tester.getTopLeft(finder).dy;
      double stepAt() => top(field(step)) - top(field(start));
      double scopeAt() =>
          top(find.byType(SegmentedButton<CounterScope>)) - top(field(start));
      final stepTop = stepAt();
      final scopeTop = scopeAt();

      await type(tester, start, '');
      await tester.pumpAndSettle();
      expect(reason(invalid), findsOneWidget);
      expect(stepAt(), stepTop);
      expect(scopeAt(), scopeTop);

      await type(tester, start, '3');
      await tester.pumpAndSettle();
      expect(stepAt(), stepTop);
      expect(scopeAt(), scopeTop);

      await type(tester, step, '0');
      await tester.pumpAndSettle();
      expect(scopeAt(), scopeTop);

      await type(tester, step, '-');
      await tester.pumpAndSettle();
      expect(scopeAt(), scopeTop);
    });
  }

  /// Whether any semantics node says [text] — as its label, hint or value —
  /// which is how a screen reader learns why Save is held.
  bool announced(WidgetTester tester, String text) => find.semantics
      .byPredicate((node) {
        final data = node.getSemanticsData();
        return '${data.label} ${data.hint} ${data.value}'.contains(text);
      })
      .evaluate()
      .isNotEmpty;

  /// What the field's own node says beside its label — read out when the
  /// field takes focus, as a plain `errorText` would be.
  String hintOf(WidgetTester tester, String label) =>
      tester.getSemantics(field(label)).getSemanticsData().hint;

  testWidgets('the shown reason reaches the screen reader on its field, the '
      'unseen ones never do', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    await type(tester, 'Counter Name', 'Sets');

    expect(announced(tester, 'Enter a whole number'), isFalse);
    expect(announced(tester, "Step can't be 0"), isFalse);

    await type(tester, 'Start Value', '');
    await type(tester, 'Step', '0');
    expect(hintOf(tester, 'Start Value'), 'Enter a whole number');
    expect(hintOf(tester, 'Step'), "Step can't be 0");
    expect(announced(tester, "Step can't be 0"), isTrue);

    await type(tester, 'Start Value', '3');
    await type(tester, 'Step', '2');
    expect(hintOf(tester, 'Start Value'), isEmpty);
    expect(hintOf(tester, 'Step'), isEmpty);
    expect(announced(tester, 'Enter a whole number'), isFalse);
    expect(announced(tester, "Step can't be 0"), isFalse);
    semantics.dispose();
  });

  testWidgets('the field keeps its semantics node as its reason comes and '
      'goes, so the screen reader keeps its focus there', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    await type(tester, 'Step', '1');
    final id = tester.getSemantics(field('Step')).id;
    expect(hintOf(tester, 'Step'), isEmpty);

    await type(tester, 'Step', '0');
    expect(tester.getSemantics(field('Step')).id, id);
    expect(hintOf(tester, 'Step'), "Step can't be 0");

    await type(tester, 'Step', '1');
    expect(tester.getSemantics(field('Step')).id, id);
    expect(hintOf(tester, 'Step'), isEmpty);
    semantics.dispose();
  });

  testWidgets('the reason is laid out whole in German at text scale 2.0 on '
      'a 360 × 780 phone', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await open(tester, locale: const Locale('de'), textScale: 2.0);
    await type(tester, 'Schritt', '0');
    await tester.pumpAndSettle();

    // The form scrolls at this size: the shown line is its slot's last text.
    await tester.ensureVisible(find.text('Schritt darf nicht 0 sein').last);
    await tester.pumpAndSettle();
    final shown = reason('Schritt darf nicht 0 sein');
    expect(shown, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(shown).didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel returns nothing', (tester) async {
    await open(tester);
    await type(tester, 'Counter Name', 'Sets');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answers, [null]);
  });
}
