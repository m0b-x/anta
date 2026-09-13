import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/widgets/label_swatch_strip.dart';

/// The one picker sheet every "assign a colour" entry point opens — the
/// browser's bulk action and the editor's menu row alike.
///
/// Its two contracts are the answer (the pick, or null on a dismiss) and the
/// bottom padding: `viewInsets` alone is zero with no keyboard up, which puts
/// the strip under the gesture bar.
void main() {
  final l10n = AppLocalizationsEn();

  /// The picks the host recorded, one entry per closed sheet — `null` for a
  /// dismissal, so "answered nothing" and "never answered" stay distinct.
  late List<ItemLabel?> answers;

  setUp(() => answers = <ItemLabel?>[]);

  Future<void> pumpHost(
    WidgetTester tester, {
    ItemLabel value = ItemLabel.none,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  answers.add(
                    await showLabelPickerSheet(context, value: value),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// The sheet's own bottom padding: the one ancestor of the strip that pads
  /// the bottom edge and nothing else. The strip's own wrapper pads top and
  /// bottom alike, and `SafeArea(top: false, bottom: false)` pads the sides.
  EdgeInsets sheetBottomPadding(WidgetTester tester) {
    return tester
        .widgetList<Padding>(
          find.ancestor(
            of: find.byType(LabelSwatchStrip),
            matching: find.byType(Padding),
          ),
        )
        .map((widget) => widget.padding)
        .whereType<EdgeInsets>()
        .firstWhere(
          (padding) =>
              padding.bottom > 0 &&
              padding.top == 0 &&
              padding.left == 0 &&
              padding.right == 0,
        );
  }

  testWidgets('returns the tapped label and closes', (tester) async {
    await pumpHost(tester);
    await openSheet(tester);

    expect(find.byType(LabelSwatchStrip), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(l10n.labelTeal));
    await tester.pumpAndSettle();

    expect(answers, [ItemLabel.teal]);
    expect(find.byType(LabelSwatchStrip), findsNothing);
  });

  testWidgets('returns null when the barrier is tapped', (tester) async {
    await pumpHost(tester);
    await openSheet(tester);

    await tester.tapAt(const Offset(400, 8));
    await tester.pumpAndSettle();

    expect(answers, [null]);
    expect(find.byType(LabelSwatchStrip), findsNothing);
  });

  testWidgets('the title is the label action', (tester) async {
    await pumpHost(tester);
    await openSheet(tester);

    expect(find.text(l10n.labelAction), findsOneWidget);

    await tester.tapAt(const Offset(400, 8));
    await tester.pumpAndSettle();
  });

  testWidgets('the strip opens ringed on the value it was given', (
    tester,
  ) async {
    await pumpHost(tester, value: ItemLabel.yellow);
    await openSheet(tester);

    expect(
      tester.widget<LabelSwatchStrip>(find.byType(LabelSwatchStrip)).value,
      ItemLabel.yellow,
    );
    final ring =
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.bySemanticsLabel(l10n.labelYellow),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect((ring.border! as Border).top.color, AppTheme.lightScheme.primary);

    await tester.tapAt(const Offset(400, 8));
    await tester.pumpAndSettle();
  });

  testWidgets('with no keyboard up it still clears the gesture bar', (
    tester,
  ) async {
    // `FakeViewPadding` is in *physical* pixels, so 96 over the test view's
    // 3x ratio is the 32 dp the sheet has to clear.
    tester.view.viewInsets = FakeViewPadding.zero;
    tester.view.padding = const FakeViewPadding(bottom: 96);
    tester.view.viewPadding = const FakeViewPadding(bottom: 96);
    addTearDown(tester.view.reset);

    await pumpHost(tester);
    await openSheet(tester);

    expect(
      sheetBottomPadding(tester),
      const EdgeInsets.only(bottom: 32),
      reason:
          'padding by viewInsets alone is this app\'s most-repeated bug — '
          'with no keyboard up it is zero and the strip lands under the '
          'gesture bar',
    );

    await tester.tapAt(const Offset(400, 8));
    await tester.pumpAndSettle();
  });

  testWidgets('the keyboard wins when it is the taller of the two', (
    tester,
  ) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = const FakeViewPadding(bottom: 96);
    addTearDown(tester.view.reset);

    await pumpHost(tester);
    await openSheet(tester);

    expect(sheetBottomPadding(tester), const EdgeInsets.only(bottom: 100));

    await tester.tapAt(const Offset(400, 8));
    await tester.pumpAndSettle();
  });
}
