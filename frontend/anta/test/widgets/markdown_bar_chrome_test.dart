import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/utility_button_config.dart';
import 'package:anta/widgets/markdown_bar.dart';

/// E4 — the toolbar used to be separated from the editor body by a 10 %
/// black drop shadow, which is invisible on a dark ground. The mock draws
/// a hairline instead, and a hairline reads in both themes.
Widget _host(Brightness brightness) {
  return MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          MarkdownBar(
            shortcuts: const [],
            isPreviewMode: false,
            canUndo: false,
            canRedo: false,
            previewFontSize: 14,
            onUndo: () {},
            onRedo: () {},
            onDecreaseFontSize: () {},
            onIncreaseFontSize: () {},
            onSettings: () {},
            onShortcutPressed: (_) {},
            utilityConfigs: const [
              UtilityButtonConfig(id: UtilityButtonId.undo),
              UtilityButtonConfig(id: UtilityButtonId.redo),
            ],
          ),
        ],
      ),
    ),
  );
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'the toolbar is a hairline, not a shadow (${brightness.name})',
      (tester) async {
        await tester.pumpWidget(_host(brightness));
        await tester.pumpAndSettle();

        final scheme = brightness == Brightness.light
            ? AppTheme.lightScheme
            : AppTheme.darkScheme;
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(MarkdownBar),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = container.decoration! as BoxDecoration;

        expect(decoration.boxShadow, isNull);
        expect(decoration.color, scheme.surface);
        expect(decoration.border!.top.color, scheme.outlineVariant);
        expect(decoration.border!.top.width, 1);
      },
    );
  }

  testWidgets('the bar closes on its 40 dp button row within 3 dp', (
    tester,
  ) async {
    await tester.pumpWidget(_host(Brightness.light));
    await tester.pumpAndSettle();

    // 3 + 40 + 3 = the mock's 46. The measured height rides on the icon
    // font's own metrics, so the padding is what this pins.
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(MarkdownBar),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(container.padding, const EdgeInsets.symmetric(vertical: 3));
    expect(tester.getSize(find.byType(MarkdownBar)).height, lessThan(48));
  });
}
