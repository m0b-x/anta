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
  Widget host({
    double textScale = 1.0,
    Locale locale = const Locale('en'),
    int? fallbackCharCount,
    int? chunkCount,
    NoteEditorStats stats = (lineCount: 42, charCount: 1234),
  }) {
    return MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: NoteEditorStatsBar(
          stats: _FixedStats(stats),
          fallbackCharCount: fallbackCharCount,
          chunkCount: chunkCount,
          isCompressed: false,
        ),
      ),
    );
  }

  Finder strip() => find.descendant(
    of: find.byType(NoteEditorStatsBar),
    matching: find.byType(Text),
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('the strip is 24 dp at text scale $scale', (tester) async {
      await tester.pumpWidget(host(textScale: scale));
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
    await tester.pumpWidget(host());
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

    final text = tester.widget<Text>(strip().first);
    expect(text.style?.fontSize, 11);
    expect(text.style?.color, AppTheme.lightScheme.onSurfaceVariant);
    expect(text.style?.fontFeatures, const [FontFeature.tabularFigures()]);
  });

  // U2.4: the copy, the grouping per locale, the fallback before the first
  // report and the dev-only chunk clause.
  group('the stats copy', () {
    testWidgets('groups the count in English', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('1,234 characters · 42 lines'), findsOneWidget);
    });

    testWidgets('groups the count in German', (tester) async {
      await tester.pumpWidget(host(locale: const Locale('de')));
      await tester.pumpAndSettle();
      expect(find.text('1.234 Zeichen · 42 Zeilen'), findsOneWidget);
    });

    testWidgets('takes the few and other forms in Romanian', (tester) async {
      await tester.pumpWidget(
        host(
          locale: const Locale('ro'),
          stats: (lineCount: 3, charCount: 20),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('20 de caractere · 3 linii'), findsOneWidget);
    });

    testWidgets('shows the stored length only before the first report', (
      tester,
    ) async {
      await tester.pumpWidget(host(fallbackCharCount: 120));
      await tester.pumpAndSettle();
      expect(find.text('120 characters · 42 lines'), findsOneWidget);

      // Loaded and emptied: the tracker's 0, never the old length.
      await tester.pumpWidget(host(stats: (lineCount: 1, charCount: 0)));
      await tester.pumpAndSettle();
      expect(find.text('0 characters · 1 line'), findsOneWidget);
    });

    testWidgets('prints the chunk clause only when given a count', (
      tester,
    ) async {
      final en = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.textContaining('chunk'), findsNothing);

      await tester.pumpWidget(host(chunkCount: 3));
      await tester.pumpAndSettle();
      expect(find.text(en.noteChunkCount(3)), findsOneWidget);
    });
  });

  // U2.13: German at 2.0 on the narrow phone stays one legible line in the
  // 24 dp strip, its text scale clamped at 1.3.
  testWidgets('at 360 x 780, German at 2.0, the strip clamps its scale at '
      '1.3 and keeps 24 dp', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(textScale: 2.0, locale: const Locale('de'), chunkCount: 3),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(NoteEditorStatsBar)).height,
      NoteEditorStatsBar.statsBarHeight,
    );
    final scaler = MediaQuery.textScalerOf(tester.element(strip().first));
    expect(scaler.scale(1), NoteEditorStatsBar.maxTextScale);
    expect(NoteEditorStatsBar.maxTextScale, 1.3);
    expect(find.text('1.234 Zeichen · 42 Zeilen'), findsOneWidget);
  });
}

class _FixedStats implements ValueListenable<NoteEditorStats> {
  const _FixedStats(this.value);

  @override
  final NoteEditorStats value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
