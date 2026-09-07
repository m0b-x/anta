import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/note_editor_chrome.dart';

/// E16 — the stats strip is chrome between two fixed bars. It keeps a fixed
/// 24 dp whatever the platform text scale says, so raising the scale never
/// pushes the editor body down, and its digits are tabular so a growing
/// character count does not jitter the row.
void main() {
  Widget host(double textScale) {
    return MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const Scaffold(
          body: NoteEditorStatsBar(
            stats: _stats,
            fallbackCharCount: 120,
            chunkCount: 3,
            isCompressed: false,
          ),
        ),
      ),
    );
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('the strip is 24 dp at text scale $scale', (tester) async {
      await tester.pumpWidget(host(scale));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(NoteEditorStatsBar)).height,
        NoteEditorStatsBar.statsBarHeight,
      );
    });
  }

  testWidgets('the strip prints tabular digits on surfaceContainerHigh', (
    tester,
  ) async {
    await tester.pumpWidget(host(1.0));
    await tester.pumpAndSettle();

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(NoteEditorStatsBar),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(container.color, AppTheme.lightScheme.surfaceContainerHigh);

    final text = tester.widget<Text>(find.textContaining('chunks').first);
    expect(text.style?.fontSize, 11);
    expect(text.style?.color, AppTheme.lightScheme.onSurfaceVariant);
    expect(text.style?.fontFeatures, const [FontFeature.tabularFigures()]);
  });
}

const ValueListenable<NoteEditorStats> _stats = _FixedStats();

class _FixedStats implements ValueListenable<NoteEditorStats> {
  const _FixedStats();

  @override
  NoteEditorStats get value => (lineCount: 42, charCount: 1234);

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
