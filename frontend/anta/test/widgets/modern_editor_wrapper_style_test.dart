import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/constants/app_spacing.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/utils/re_editor_search_controller.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

/// E9, E10, E12 — the editor body's own chrome, read straight off the
/// style the wrapper hands the fork.
///
/// The caret line used to be `primary@0.10`, a purple wash over the text;
/// the find hit fell through to the fork's `primary@0.4`, which is also
/// the selection colour, so a hit and a selection were the same paint.
void main() {
  const fontSize = 16.0;

  Future<CodeEditorStyle> pumpAndReadStyle(
    WidgetTester tester,
    Brightness brightness, {
    String text = 'one\ntwo\nthree',
    double textScale = 1.0,
    bool followsTextScale = false,
    String? hint,
  }) async {
    final controller = CodeLineEditingController.fromText(text);
    final searchController = ReEditorSearchController();
    final scrollController = CodeScrollController();
    final focusNode = FocusNode();
    addTearDown(() {
      focusNode.dispose();
      searchController.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ModernEditorWrapper(
            controller: controller,
            focusNode: focusNode,
            scrollController: scrollController,
            searchController: searchController,
            editorFontSize: fontSize,
            onTextChanged: () {},
            wordWrap: false,
            showScrollIndicator: false,
            showCursorLine: true,
            followsTextScale: followsTextScale,
            hint: hint,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<CodeEditor>(find.byType(CodeEditor)).style!;
  }

  Future<void> teardownEditor(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  for (final brightness in Brightness.values) {
    testWidgets('the caret line and the find hit are palette roles '
        '(${brightness.name})', (tester) async {
      final scheme = brightness == Brightness.light
          ? AppTheme.lightScheme
          : AppTheme.darkScheme;
      final style = await pumpAndReadStyle(tester, brightness);

      expect(style.cursorLineColor, scheme.surfaceContainerLow);
      expect(style.cursorLineColor!.a, 1.0);
      if (brightness == Brightness.dark) {
        expect(style.highlightColor, scheme.primaryContainer);
        expect(style.currentHighlightColor, scheme.tertiaryContainer);
      } else {
        expect(
          style.highlightColor,
          scheme.tertiary.withValues(
            alpha: MarkdownConstants.findMatchAlphaLight,
          ),
        );
        expect(
          style.currentHighlightColor,
          scheme.tertiary.withValues(
            alpha: MarkdownConstants.findCurrentMatchAlphaLight,
          ),
        );
      }
      expect(style.highlightColor, isNot(style.selectionColor));
      expect(style.currentHighlightColor, isNot(style.highlightColor));
      expect(style.currentHighlightColor, isNot(style.selectionColor));
      // A plain match never shares the selection's hue, so a match never
      // reads as one more selection.
      expect(
        style.highlightColor!.withValues(alpha: 1),
        isNot(style.selectionColor!.withValues(alpha: 1)),
      );

      await teardownEditor(tester);
    });
  }

  group('U2.5 the editor font follows the system text size, de', () {
    for (final (scale, follows, expected) in [
      (1.5, true, 24.0),
      (2.0, true, 32.0),
      (2.5, true, 32.0), // clamped at ModernEditorWrapper.maxTextScale
      (2.0, false, fontSize), // the event sheets stay unscaled
    ]) {
      testWidgets('scale $scale, followsTextScale $follows', (tester) async {
        final style = await pumpAndReadStyle(
          tester,
          Brightness.light,
          textScale: scale,
          followsTextScale: follows,
        );
        expect(style.fontSize, expected);
        await teardownEditor(tester);
      });
    }

    testWidgets('U2.11 the empty-note hint is drawn once at the editor size, '
        'dimmed', (tester) async {
      final hint = AppLocalizationsDe().editorHint;
      final style = await pumpAndReadStyle(
        tester,
        Brightness.light,
        text: '',
        textScale: 2.0,
        followsTextScale: true,
        hint: hint,
      );

      final text = tester.widget<Text>(find.text(hint));
      // The style already carries the scale; a second one would draw the
      // hint at four times the base size.
      expect(text.textScaler, TextScaler.noScaling);
      expect(text.style!.fontSize, style.fontSize);
      expect(text.style!.color, AppTheme.lightScheme.onSurfaceVariant);
      await teardownEditor(tester);
    });
  });

  testWidgets('the editor body is inset 20 dp', (tester) async {
    await pumpAndReadStyle(tester, Brightness.light);

    final padding =
        tester.widget<CodeEditor>(find.byType(CodeEditor)).padding!
            as EdgeInsets;
    expect(padding.left, AppSpacing.xl);
    expect(padding.right, AppSpacing.xl + AppConstants.editorScrollbarPadding);

    await teardownEditor(tester);
  });
}
