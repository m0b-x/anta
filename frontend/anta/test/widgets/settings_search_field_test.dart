import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/settings_search_field.dart';

/// The settings search field's focus and its accessible name: a clear keeps
/// the keyboard up, and the field is named by its hint whether or not it
/// holds text — the hint's text leaves the tree once text replaces it.
void main() {
  const hint = 'Search settings';

  late TextEditingController controller;
  late List<String> changes;

  setUp(() {
    controller = TextEditingController();
    changes = [];
  });

  tearDown(() => controller.dispose());

  Future<void> pumpField(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: Center(
          child: SettingsSearchField(
            controller: controller,
            hint: hint,
            onChanged: changes.add,
          ),
        ),
      ),
    ),
  );

  Finder field() => find.byType(TextField);

  Finder clear() =>
      find.bySemanticsIdentifier(SemanticsIds.settingsSearchClear);

  SemanticsData fieldNode(WidgetTester tester) => tester
      .getSemantics(find.bySemanticsIdentifier(SemanticsIds.settingsSearch))
      .getSemanticsData();

  // A probe: focused, "gym" typed, the ✕ tapped — the focus was gone.
  testWidgets('the ✕ clears the text and keeps the focus', (tester) async {
    await pumpField(tester);
    await tester.tap(field());
    await tester.pump();
    await tester.enterText(field(), 'gym');
    await tester.pump();
    expect(clear(), findsOneWidget);

    await tester.tap(clear());
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(changes.last, '');
    expect(clear(), findsNothing);
    expect(tester.widget<TextField>(field()).focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('a tap outside the field still drops the focus', (tester) async {
    await pumpField(tester);
    await tester.tap(field());
    await tester.pump();
    await tester.enterText(field(), 'gym');
    await tester.pump();

    await tester.tapAt(const Offset(5, 5));
    await tester.pump();

    expect(tester.widget<TextField>(field()).focusNode!.hasFocus, isFalse);
    expect(controller.text, 'gym');
  });

  testWidgets('while empty the hint names the field once; with text it '
      'still does, the text its value', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpField(tester);

    final empty = fieldNode(tester);
    expect(empty.label, hint);
    expect(empty.flagsCollection.isTextField, isTrue);

    // Settled: the hint fades out, and only at opacity 0 does it leave the
    // semantics tree.
    await tester.enterText(field(), 'Ka');
    await tester.pumpAndSettle();

    final typed = fieldNode(tester);
    expect(typed.label, hint);
    expect(typed.value, 'Ka');
    expect(typed.flagsCollection.isTextField, isTrue);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    semantics.dispose();
  });
}
