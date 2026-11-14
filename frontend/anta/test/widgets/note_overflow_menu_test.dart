import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/widgets/note_overflow_menu.dart';

import '../goldens/support/golden_fonts.dart';

/// The partner's note's ⋮ menu (share surfaces §6.13): every write is drawn
/// off — the words dimmed with the glyph, not the glyph alone — and the menu
/// fits at German 2.0 on a 360 × 780 phone, measured with real Roboto.
void main() {
  final de = AppLocalizationsDe();

  Future<void> openMenu(
    WidgetTester tester, {
    double scale = 1.0,
    bool realFonts = false,
    String folderName = 'Reisen nach Portugal und Spanien im Sommer',
  }) async {
    if (realFonts) await tester.runAsync(loadGoldenFonts);
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        theme: realFonts
            ? withRobotoMenuLabels(AppTheme.light())
            : AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              NoteOverflowMenu(
                folderName: folderName,
                onOpenFolder: () {},
                onEditTitle: () {},
                onMove: () {},
                onLabel: () {},
                onShare: () {},
                onDelete: () {},
                onSettings: () {},
                fromPartner: true,
                onCopyToMine: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(NoteOverflowMenu));
    await tester.pumpAndSettle();
  }

  testWidgets('the partner\'s note: every disabled row\'s words at the '
      'disabled opacity', (tester) async {
    await openMenu(tester);

    final onSurface = AppTheme.light().colorScheme.onSurface;
    for (final off in [
      de.editTitle,
      de.moveToFolder,
      de.labelAction,
      de.shareNote,
      de.deleteNote,
    ]) {
      expect(
        tester.widget<Text>(find.text(off)).style?.color,
        onSurface.withValues(alpha: FormMetrics.disabledOpacity),
        reason: off,
      );
    }
    expect(
      tester.widget<Text>(find.text(de.sharedNoteCopy)).style?.color,
      isNot(onSurface.withValues(alpha: FormMetrics.disabledOpacity)),
      reason: 'the one act left is drawn live',
    );
  });

  testWidgets('German 2.0 on 360 × 780 with real Roboto: nothing overflows', (
    tester,
  ) async {
    await openMenu(tester, scale: 2.0, realFonts: true);

    expect(tester.takeException(), isNull);
    expect(find.text(de.sharedNoteCopy), findsOneWidget);
  });

  testWidgets('German 2.0 with real Roboto: no entry\'s words are cut — a '
      'label wraps, the folder row\'s value goes under its name', (
    tester,
  ) async {
    // A name of two words, as the review's render: a name too long for two
    // lines at 2.0 is cut at its second, by the rule.
    await openMenu(
      tester,
      scale: 2.0,
      realFonts: true,
      folderName: 'Reisen nach Portugal',
    );

    final paragraphs = find.descendant(
      of: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
      matching: find.byType(RichText),
    );
    expect(paragraphs, findsAtLeastNWidgets(9));
    for (final element in paragraphs.evaluate()) {
      final paragraph = element.renderObject! as RenderParagraph;
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: paragraph.text.toPlainText(),
      );
    }
    expect(tester.takeException(), isNull);
  });

  // Leg 10: the entry a device flow opens the note's folder by, on the
  // menu item's one node with its name and its words.
  testWidgets('the folder entry carries its id, once', (tester) async {
    await openMenu(tester, folderName: 'Reisen');

    final entry = find.bySemanticsIdentifier(SemanticsIds.editorMenuFolder);
    expect(entry, findsOneWidget);
    expect(
      tester.getSemantics(entry).getSemanticsData().label,
      allOf(contains('Reisen'), contains(de.openFolder)),
    );
  });
}
