import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/utility_button_config.dart';
import 'package:anta/widgets/markdown_bar.dart';

Widget _wrap({
  required bool isPreviewMode,
  VoidCallback? onShare,
  List<UtilityButtonConfig>? utilityConfigs,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          MarkdownBar(
            shortcuts: const [],
            isPreviewMode: isPreviewMode,
            canUndo: false,
            canRedo: false,
            previewFontSize: 14,
            onUndo: () {},
            onRedo: () {},
            onDecreaseFontSize: () {},
            onIncreaseFontSize: () {},
            onSettings: () {},
            onShortcutPressed: (_) {},
            onShare: onShare,
            utilityConfigs:
                utilityConfigs ??
                const [UtilityButtonConfig(id: UtilityButtonId.share)],
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('share is exposed in edit mode when onShare is set', (
    tester,
  ) async {
    var shared = 0;
    await tester.pumpWidget(
      _wrap(isPreviewMode: false, onShare: () => shared++),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.share), findsOneWidget);

    await tester.tap(find.byIcon(Icons.share));
    await tester.pump();

    expect(shared, 1);
  });

  testWidgets('share stays available in preview mode', (tester) async {
    await tester.pumpWidget(_wrap(isPreviewMode: true, onShare: () {}));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.share), findsOneWidget);
  });

  testWidgets('share is absent in either mode when onShare is null', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(isPreviewMode: false));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.share), findsNothing);

    await tester.pumpWidget(_wrap(isPreviewMode: true));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.share), findsNothing);
  });

  testWidgets('share ships in the default utility layout outside preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        isPreviewMode: false,
        onShare: () {},
        utilityConfigs: UtilityButtonConfig.defaults(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.share), findsOneWidget);
  });
}
