import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/markdown_bar_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';
import 'package:anta/models/utility_button_config.dart';
import 'package:anta/models/utility_button_definition.dart';
import 'package:anta/widgets/form_menu_item.dart';
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

  testWidgets('the bar closes on its 48 dp button row within 3 dp (U1.1)', (
    tester,
  ) async {
    await tester.pumpWidget(_host(Brightness.light));
    await tester.pumpAndSettle();

    // The hairline, then 3 + 48 + 3: the row grew once, from 40, to reach
    // 48 dp targets.
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(MarkdownBar),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(container.padding, const EdgeInsets.symmetric(vertical: 3));
    expect(MarkdownBar.rowHeight, 48);
    expect(tester.getSize(find.byType(MarkdownBar)).height, 55);
  });

  group('indent and outdent (E9)', () {
    const configs = [
      UtilityButtonConfig(id: UtilityButtonId.indent),
      UtilityButtonConfig(id: UtilityButtonId.outdent),
    ];

    testWidgets('each button runs its own callback', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        _bar(
          utilityConfigs: configs,
          onIndent: () => calls.add('indent'),
          onOutdent: () => calls.add('outdent'),
        ),
      );

      await tester.tap(find.byTooltip('Indent'));
      await tester.tap(find.byTooltip('Outdent'));

      expect(calls, ['indent', 'outdent']);
      expect(find.byIcon(Icons.format_indent_increase), findsOneWidget);
      expect(find.byIcon(Icons.format_indent_decrease), findsOneWidget);
    });

    // Y9: a host without the edit (the event sheets) would show two
    // buttons that never enable, so they leave like Paste and Counter.
    testWidgets('unwired buttons are absent', (tester) async {
      await tester.pumpWidget(_bar(utilityConfigs: configs));

      expect(find.byIcon(Icons.format_indent_increase), findsNothing);
      expect(find.byIcon(Icons.format_indent_decrease), findsNothing);
    });

    testWidgets('the buttons leave the bar in preview', (tester) async {
      await tester.pumpWidget(
        _bar(
          utilityConfigs: configs,
          isPreviewMode: true,
          onIndent: () {},
          onOutdent: () {},
        ),
      );

      expect(find.byIcon(Icons.format_indent_increase), findsNothing);
      expect(find.byIcon(Icons.format_indent_decrease), findsNothing);
    });

    test('a stored layout gains them after redo, its own order kept '
        '(U1.2)', () {
      // A layout saved before indent existed: every other id, rearranged.
      final stored = [
        for (final id in UtilityButtonId.defaultOrder.reversed)
          if (id != UtilityButtonId.indent && id != UtilityButtonId.outdent)
            UtilityButtonConfig(id: id, isVisible: id != UtilityButtonId.undo),
      ];

      final decoded = UtilityButtonConfig.decode(
        UtilityButtonConfig.encode(stored),
      );

      // Redo is indent's nearest default predecessor the layout holds;
      // outdent then follows indent. Nothing stored moves.
      final redoAt = stored.indexWhere((c) => c.id == UtilityButtonId.redo);
      expect(decoded.map((c) => c.id).toList(), [
        for (final c in stored.take(redoAt + 1)) c.id,
        UtilityButtonId.indent,
        UtilityButtonId.outdent,
        for (final c in stored.skip(redoAt + 1)) c.id,
      ]);
      expect(
        decoded.where(
          (c) =>
              c.id != UtilityButtonId.indent && c.id != UtilityButtonId.outdent,
        ),
        stored,
      );
    });

    test('a pre-indent layout in the default order decodes to the new '
        'default', () {
      final stored = [
        for (final id in UtilityButtonId.defaultOrder)
          if (id != UtilityButtonId.indent && id != UtilityButtonId.outdent)
            UtilityButtonConfig(id: id),
      ];

      final decoded = UtilityButtonConfig.decode(
        UtilityButtonConfig.encode(stored),
      );

      expect(decoded, UtilityButtonConfig.defaults());
    });

    test('an unseen id with no stored predecessor goes first', () {
      final decoded = UtilityButtonConfig.decode(
        UtilityButtonConfig.encode(const [
          UtilityButtonConfig(id: UtilityButtonId.settings),
        ]),
      );

      expect(decoded.first.id, UtilityButtonId.undo);
      expect(decoded.last.id, UtilityButtonId.settings);
      expect(decoded.map((c) => c.id).toList(), UtilityButtonId.defaultOrder);
    });

    test('a new install has them right after undo and redo (Y14)', () {
      expect(UtilityButtonConfig.defaults().map((c) => c.id).take(4), [
        UtilityButtonId.undo,
        UtilityButtonId.redo,
        UtilityButtonId.indent,
        UtilityButtonId.outdent,
      ]);
    });
  });

  group('the heading menu (E12)', () {
    testWidgets('lists body text and the six levels with their markers and '
        'ids (U1.5)', (tester) async {
      await tester.pumpWidget(_bar(shortcuts: [_header]));

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();

      expect(find.byType(FormMenuChoiceItem<int>), findsNWidgets(7));
      expect(find.text('Body text'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.editorHeadingLevel(0)),
        findsOneWidget,
      );
      for (var level = 1; level <= 6; level++) {
        expect(find.text('Heading $level'), findsOneWidget);
        expect(find.text('#' * level), findsOneWidget);
        expect(
          find.bySemanticsIdentifier(SemanticsIds.editorHeadingLevel(level)),
          findsOneWidget,
        );
      }
      // Body text is first, above Heading 1.
      expect(
        tester.getTopLeft(find.text('Body text')).dy,
        lessThan(tester.getTopLeft(find.text('Heading 1')).dy),
      );
    });

    testWidgets('the current level shows a visible check (U1.5)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _bar(shortcuts: [_header], currentHeadingLevel: () => 3),
      );

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();

      final check = find.byIcon(Icons.check_rounded);
      expect(check, findsOneWidget);
      expect(
        tester.getCenter(check).dy,
        moreOrLessEquals(tester.getCenter(find.text('Heading 3')).dy),
      );
    });

    testWidgets('body text is checked on a plain line and picks nothing '
        'there', (tester) async {
      final picked = <CustomMarkdownShortcut>[];
      await tester.pumpWidget(
        _bar(
          shortcuts: [_header],
          currentHeadingLevel: () => null,
          onShortcutPressed: picked.add,
        ),
      );

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byIcon(Icons.check_rounded)).dy,
        moreOrLessEquals(tester.getCenter(find.text('Body text')).dy),
      );
      await tester.tap(find.text('Body text'));
      await tester.pumpAndSettle();

      expect(find.text('Body text'), findsNothing);
      expect(picked, isEmpty);
    });

    testWidgets('body text on a heading hands the page that level again, '
        'which removes it', (tester) async {
      final picked = <CustomMarkdownShortcut>[];
      await tester.pumpWidget(
        _bar(
          shortcuts: [_header],
          currentHeadingLevel: () => 2,
          onShortcutPressed: picked.add,
        ),
      );

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Body text'));
      await tester.pumpAndSettle();

      expect(picked.single.id, 'header_level_2');
      expect(picked.single.beforeText, '## ');
      expect(picked.single.insertType, 'header');
    });

    testWidgets('body text reads the caret line again when it is picked', (
      tester,
    ) async {
      // The editor keeps the keyboard while the menu is open, so the caret
      // can move to another line between the open and the pick.
      final picked = <CustomMarkdownShortcut>[];
      int? level = 2;
      await tester.pumpWidget(
        _bar(
          shortcuts: [_header],
          currentHeadingLevel: () => level,
          onShortcutPressed: picked.add,
        ),
      );

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();
      level = null;
      await tester.tap(find.text('Body text'));
      await tester.pumpAndSettle();
      expect(picked, isEmpty);

      level = 2;
      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();
      level = 3;
      await tester.tap(find.text('Body text'));
      await tester.pumpAndSettle();
      expect(picked.single.id, 'header_level_3');
    });

    testWidgets('a host without a level reader checks no row and keeps body '
        'text in place, disabled', (tester) async {
      final picked = <CustomMarkdownShortcut>[];
      await tester.pumpWidget(
        _bar(shortcuts: [_header], onShortcutPressed: picked.add),
      );

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      final items = tester
          .widgetList<FormMenuChoiceItem<int>>(
            find.byType(FormMenuChoiceItem<int>),
          )
          .toList();
      expect(items.first.value, 0);
      expect(items.first.enabled, isFalse);
      expect(items.skip(1).every((item) => item.enabled), isTrue);

      await tester.tap(find.text('Body text'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Body text'), findsOneWidget);
      await tester.tap(find.text('Heading 2'));
      await tester.pumpAndSettle();
      expect(picked.single.id, 'header_level_2');
    });

    testWidgets('a pick hands the page that level\'s shortcut', (tester) async {
      final picked = <CustomMarkdownShortcut>[];
      await tester.pumpWidget(
        _bar(shortcuts: [_header], onShortcutPressed: picked.add),
      );

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Heading 3'));
      await tester.pumpAndSettle();

      expect(picked, hasLength(1));
      expect(picked.single.beforeText, '### ');
      expect(picked.single.afterText, '');
      expect(picked.single.insertType, 'header');
      expect(picked.single.id, 'header_level_3');
    });

    testWidgets('the caret line\'s level is the checked item (Y7)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _bar(shortcuts: [_header], currentHeadingLevel: () => 2),
      );

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();

      final items = tester
          .widgetList<FormMenuChoiceItem<int>>(
            find.byType(FormMenuChoiceItem<int>),
          )
          .toList();
      expect(
        [for (final item in items) item.checked],
        [false, false, true, false, false, false, false],
      );
    });

    testWidgets('a plain caret line checks body text alone', (tester) async {
      await tester.pumpWidget(
        _bar(shortcuts: [_header], currentHeadingLevel: () => null),
      );

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();

      expect(
        [
          for (final item in tester.widgetList<FormMenuChoiceItem<int>>(
            find.byType(FormMenuChoiceItem<int>),
          ))
            item.checked,
        ],
        [true, false, false, false, false, false, false],
      );
    });

    testWidgets('the menu leaves the editor its focus (Y7)', (tester) async {
      final editorFocus = FocusNode();
      addTearDown(editorFocus.dispose);
      await tester.pumpWidget(
        _bar(shortcuts: [_header], editorFocus: editorFocus),
      );
      editorFocus.requestFocus();
      await tester.pump();
      expect(editorFocus.hasFocus, isTrue);

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();

      expect(find.text('Heading 1'), findsOneWidget);
      expect(editorFocus.hasFocus, isTrue);
    });

    testWidgets('on a desktop the menu takes focus, so a hardware keyboard '
        'stops typing into the note (U1.7)', (tester) async {
      final editorFocus = FocusNode();
      addTearDown(editorFocus.dispose);
      await tester.pumpWidget(
        _bar(shortcuts: [_header], editorFocus: editorFocus),
      );
      editorFocus.requestFocus();
      await tester.pump();

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();

      expect(find.text('Heading 1'), findsOneWidget);
      expect(editorFocus.hasFocus, isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('dismissing picks nothing', (tester) async {
      final picked = <CustomMarkdownShortcut>[];
      await tester.pumpWidget(
        _bar(shortcuts: [_header], onShortcutPressed: picked.add),
      );

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(find.text('Heading 1'), findsNothing);
      expect(picked, isEmpty);
    });

    testWidgets('speaks German', (tester) async {
      await tester.pumpWidget(
        _bar(shortcuts: [_header], locale: const Locale('de')),
      );

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();

      expect(find.text('Überschrift 2'), findsOneWidget);
      expect(find.text('Fließtext'), findsOneWidget);
      expect(find.text('Heading 2'), findsNothing);
    });

    testWidgets('speaks Romanian (D5)', (tester) async {
      await tester.pumpWidget(
        _bar(shortcuts: [_header], locale: const Locale('ro')),
      );
      expect(find.byTooltip('Titlu'), findsOneWidget);

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();

      expect(find.text('Titlu 2'), findsOneWidget);
      expect(find.text('Text normal'), findsOneWidget);
    });
  });

  // `showMenu` placed this menu by its top edge from an estimate of its
  // height and revealed it downward from the top of the screen: at 1.15 and
  // 1.3 it stopped 57 and 41 dp short of the button.
  group('the heading menu stands on its button', () {
    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.reset);
    }

    // The status bar plus the route's margin.
    const topLimit = 24.0 + 8.0;
    // The menu stands on the bar's top edge, its hairline, not on the
    // button inside the bar's chrome.
    const barTopEdge =
        MarkdownBarMetrics.verticalPadding + MarkdownBarMetrics.hairline;

    Future<AppLocalizations> open(
      WidgetTester tester, {
      required Locale locale,
      double textScale = 1.0,
      ValueChanged<CustomMarkdownShortcut>? onShortcutPressed,
    }) async {
      phone(tester);
      await tester.pumpWidget(
        _bar(
          shortcuts: [_header, _bold, _italic],
          currentHeadingLevel: () => 2,
          onShortcutPressed: onShortcutPressed,
          locale: locale,
          textScale: textScale,
          asEditorPage: true,
        ),
      );
      await tester.pumpAndSettle();
      return lookupAppLocalizations(locale);
    }

    Finder menuOf(AppLocalizations l10n) => find
        .ancestor(
          of: find.text(l10n.headingBodyText),
          matching: find.byType(Material),
        )
        .first;

    for (final locale in const [Locale('en'), Locale('de')]) {
      for (final scale in const [1.0, 1.15, 1.3, 2.0]) {
        testWidgets('${locale.languageCode} at $scale: on the button, rising '
            'from it, every level reachable', (tester) async {
          final picked = <CustomMarkdownShortcut>[];
          final l10n = await open(
            tester,
            locale: locale,
            textScale: scale,
            onShortcutPressed: picked.add,
          );
          final button = find.byTooltip(l10n.headers);
          final buttonTop = tester.getTopLeft(button).dy - barTopEdge;

          await tester.tap(button);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
          final rising = tester.getRect(menuOf(l10n));
          expect(rising.bottom, moreOrLessEquals(buttonTop, epsilon: 1));

          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final menu = tester.getRect(menuOf(l10n));
          expect(menu.bottom, moreOrLessEquals(buttonTop, epsilon: 1));
          expect(menu.top, greaterThanOrEqualTo(topLimit));
          expect(menu.left, moreOrLessEquals(RowMetrics.groupInset));
          expect(rising.height, lessThan(menu.height));

          expect(find.text(l10n.headingBodyText).hitTestable(), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text(l10n.header6),
            50,
            scrollable: find
                .ancestor(
                  of: find.text(l10n.headingBodyText),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(find.text(l10n.header6).hitTestable(), findsOneWidget);

          await tester.tap(find.text(l10n.header6));
          await tester.pumpAndSettle();
          expect(picked.single.id, 'header_level_6');
          expect(picked.single.beforeText, '###### ');
        });
      }
    }

    testWidgets('a barrier tap picks nothing', (tester) async {
      final picked = <CustomMarkdownShortcut>[];
      final l10n = await open(
        tester,
        locale: const Locale('en'),
        onShortcutPressed: picked.add,
      );

      await tester.tap(find.byTooltip(l10n.headers));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(find.text(l10n.headingBodyText), findsNothing);
      expect(picked, isEmpty);
    });
  });

  // At 2.0 the full-width marker squeezed the label until Roboto broke
  // "Heading 5" and "Überschrift 4" mid-word; the marker is decoration.
  testWidgets('the heading marker scales up to 1.3 and gives its column to '
      'the label past it', (tester) async {
    Future<void> open(double scale) async {
      await tester.pumpWidget(
        _bar(
          shortcuts: [_header],
          currentHeadingLevel: () => 6,
          textScale: scale,
        ),
      );
      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();
    }

    Future<void> close() async {
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
    }

    await open(1.0);
    final atOne = tester.getSize(find.text('######')).width;
    await close();
    await open(FormMetrics.menuMarkerMaxScale);
    expect(tester.getSize(find.text('######')).width, greaterThan(atOne));
    await close();

    await open(2.0);
    expect(find.text('######'), findsNothing);
    expect(find.text('#'), findsNothing);
    expect(find.text('Heading 6'), findsOneWidget);
    expect(
      tester.getCenter(find.byIcon(Icons.check_rounded)).dy,
      moreOrLessEquals(tester.getCenter(find.text('Heading 6')).dy),
    );
  });

  group('accessibility guidelines', () {
    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<void> meetsAll(WidgetTester tester) async {
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }

    for (final brightness in Brightness.values) {
      for (final split in [true, false]) {
        for (final pinned in [true, false]) {
          testWidgets('${brightness.name}, ${split ? 'split' : 'single row'}, '
              '${pinned ? 'pinned' : 'unpinned'}: the bar', (tester) async {
            final semantics = tester.ensureSemantics();
            phone(tester);
            await tester.pumpWidget(
              _bar(
                shortcuts: [_bold, _italic, _header],
                utilityConfigs: const [
                  UtilityButtonConfig(id: UtilityButtonId.undo),
                  UtilityButtonConfig(id: UtilityButtonId.redo),
                  UtilityButtonConfig(id: UtilityButtonId.settings),
                ],
                canUndo: true,
                splitEnabled: split,
                pinUndoRedo: pinned,
                brightness: brightness,
              ),
            );
            await tester.pumpAndSettle();

            await meetsAll(tester);
            semantics.dispose();
          });
        }
      }

      testWidgets('${brightness.name}: the open heading menu', (tester) async {
        final semantics = tester.ensureSemantics();
        phone(tester);
        await tester.pumpWidget(
          _bar(
            shortcuts: [_header],
            currentHeadingLevel: () => 2,
            brightness: brightness,
          ),
        );
        await tester.tap(find.text('H'));
        await tester.pumpAndSettle();

        await meetsAll(tester);
        semantics.dispose();
      });
    }
  });

  group('feedback and labels (E27)', () {
    testWidgets('built-in tooltips follow the app language, custom ones '
        'keep their own label', (tester) async {
      await tester.pumpWidget(
        _bar(shortcuts: [_bold, _header, _custom], locale: const Locale('de')),
      );

      expect(find.byTooltip('Fett'), findsOneWidget);
      expect(find.byTooltip('Überschrift'), findsOneWidget);
      expect(find.byTooltip('Satz'), findsOneWidget);
      expect(find.byTooltip('Bold'), findsNothing);
    });

    testWidgets('every button inks on the bar without changing its size', (
      tester,
    ) async {
      await tester.pumpWidget(
        _bar(
          shortcuts: [_bold, _custom],
          utilityConfigs: const [UtilityButtonConfig(id: UtilityButtonId.undo)],
          canUndo: true,
        ),
      );

      final inks = find.descendant(
        of: find.byType(MarkdownBar),
        matching: find.byType(InkResponse),
      );
      expect(inks, findsNWidgets(3));
      for (final element in inks.evaluate()) {
        expect((element.widget as InkResponse).onTap, isNotNull);
      }
      // Every button is one 48 dp square, the glyph centred in it (U1.1).
      for (final glyph in [find.byIcon(Icons.undo), find.text('B')]) {
        final ink = find.ancestor(
          of: glyph,
          matching: find.byType(InkResponse),
        );
        expect(tester.getSize(ink), const Size.square(MarkdownBar.rowHeight));
      }
      // The ink paints on a transparent material inside the bar's
      // decorated surface, or the surface would hide it.
      final material = tester.widget<Material>(
        find.ancestor(of: inks.first, matching: find.byType(Material)).first,
      );
      expect(material.type, MaterialType.transparency);
    });

    testWidgets('B, I and H keep the row height at text scale 2.0', (
      tester,
    ) async {
      await tester.pumpWidget(_bar(shortcuts: [_bold, _italic, _header]));
      final atOne = tester.getSize(find.byType(MarkdownBar)).height;

      await tester.pumpWidget(
        _bar(shortcuts: [_bold, _italic, _header], textScale: 2.0),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(MarkdownBar)).height, atOne);
    });
  });

  group('haptics (E20)', () {
    Future<List<MethodCall>> reorderRoundTrip(
      WidgetTester tester, {
      required bool hapticsEnabled,
    }) async {
      final vibrations = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') vibrations.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        _bar(
          shortcuts: [_bold],
          utilityConfigs: const [
            UtilityButtonConfig(id: UtilityButtonId.reorder),
          ],
          onReorderComplete: (_) {},
          hapticsEnabled: hapticsEnabled,
        ),
      );

      await tester.tap(find.byIcon(Icons.swap_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      return vibrations;
    }

    testWidgets('reorder mode vibrates while the setting is on', (
      tester,
    ) async {
      final vibrations = await reorderRoundTrip(tester, hapticsEnabled: true);
      expect(vibrations, hasLength(2));
    });

    testWidgets('reorder mode is silent while the setting is off', (
      tester,
    ) async {
      final vibrations = await reorderRoundTrip(tester, hapticsEnabled: false);
      expect(vibrations, isEmpty);
    });
  });

  group('the utility strip (U1.2)', () {
    final en = lookupAppLocalizations(const Locale('en'));
    String label(String id) => UtilityButtonDefinition.getById(id)!.label(en);
    const strip = [
      UtilityButtonConfig(id: UtilityButtonId.undo),
      UtilityButtonConfig(id: UtilityButtonId.redo),
      UtilityButtonConfig(id: UtilityButtonId.decreaseFont),
      UtilityButtonConfig(id: UtilityButtonId.increaseFont),
      UtilityButtonConfig(id: UtilityButtonId.settings),
    ];

    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Finder scrollerOf(String tooltip) => find.ancestor(
      of: find.byTooltip(tooltip),
      matching: find.byType(SingleChildScrollView),
    );

    testWidgets('undo and redo sit outside the scroller, after the divider', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(_bar(shortcuts: [_bold], utilityConfigs: strip));

      expect(scrollerOf(label(UtilityButtonId.undo)), findsNothing);
      expect(scrollerOf(label(UtilityButtonId.redo)), findsNothing);
      expect(scrollerOf(label(UtilityButtonId.settings)), findsOneWidget);
      expect(
        find.byTooltip(label(UtilityButtonId.undo)).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byTooltip(label(UtilityButtonId.undo))).dx,
        greaterThan(tester.getTopRight(find.byTooltip('Bold')).dx),
      );
    });

    testWidgets('the edge fades follow the scroll extent', (tester) async {
      phone(tester);
      await tester.pumpWidget(_bar(shortcuts: [_bold], utilityConfigs: strip));
      await tester.pumpAndSettle();

      MarkdownBarEdgeFadeState fade() => tester.state(
        find.ancestor(
          of: scrollerOf(label(UtilityButtonId.settings)),
          matching: find.byType(MarkdownBarEdgeFade),
        ),
      );
      final shortcuts = tester.state<MarkdownBarEdgeFadeState>(
        find.ancestor(
          of: find.byTooltip('Bold'),
          matching: find.byType(MarkdownBarEdgeFade),
        ),
      );
      expect(shortcuts.fadesStart, isFalse);
      expect(shortcuts.fadesEnd, isFalse);
      expect(fade().fadesStart, isFalse);
      expect(fade().fadesEnd, isTrue);

      await tester.drag(
        scrollerOf(label(UtilityButtonId.settings)),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();

      expect(fade().fadesStart, isTrue);
      expect(fade().fadesEnd, isFalse);
    });

    // C2.6 — the overlay that replaced the mask lost the old gradient's
    // "never past the middle" stop, and painted `surface` on any ground.
    testWidgets('a narrow split strip fading at both ends keeps each fade '
        'within half of it', (tester) async {
      phone(tester);
      // Narrower than the phones, so the strip is under two fades wide.
      tester.view.physicalSize = Size(
        300 * tester.view.devicePixelRatio,
        780 * tester.view.devicePixelRatio,
      );
      await tester.pumpWidget(
        _bar(shortcuts: [_bold], utilityConfigs: strip, shortcutRatio: 0.8),
      );
      await tester.pumpAndSettle();
      final utility = find.ancestor(
        of: scrollerOf(label(UtilityButtonId.settings)),
        matching: find.byType(MarkdownBarEdgeFade),
      );
      await tester.drag(
        scrollerOf(label(UtilityButtonId.settings)),
        const Offset(-30, 0),
      );
      await tester.pumpAndSettle();
      final state = tester.state<MarkdownBarEdgeFadeState>(utility);
      expect(state.fadesStart, isTrue);
      expect(state.fadesEnd, isTrue);

      final width = tester.getSize(utility).width;
      expect(width, lessThan(2 * MarkdownBarMetrics.edgeFadeExtent));
      final edges = find.descendant(
        of: utility,
        matching: find.byType(Positioned),
      );
      expect(edges, findsNWidgets(2));
      for (final edge in edges.evaluate()) {
        expect(
          (edge.renderObject! as RenderBox).size.width,
          moreOrLessEquals(width / 2),
        );
      }
    });

    testWidgets('a bar on its host\'s ground fades into that ground', (
      tester,
    ) async {
      phone(tester);
      const ground = Color(0xFF336699);
      await tester.pumpWidget(
        _bar(
          shortcuts: [_bold],
          utilityConfigs: strip,
          showBackground: false,
          fadeGround: ground,
        ),
      );
      await tester.pumpAndSettle();
      final utility = find.ancestor(
        of: scrollerOf(label(UtilityButtonId.settings)),
        matching: find.byType(MarkdownBarEdgeFade),
      );
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: utility, matching: find.byType(DecoratedBox)).last,
      );
      final gradient =
          (box.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors.first, ground);
    });

    testWidgets('a tap inside the scroller puts it back at its start', (
      tester,
    ) async {
      phone(tester);
      var pastes = 0;
      await tester.pumpWidget(
        _bar(
          shortcuts: [_bold],
          // Paste leads, so a short drag leaves it on screen; it is not a
          // repeatable button, so a tap on it still resets the scroller.
          utilityConfigs: [
            strip[0],
            strip[1],
            const UtilityButtonConfig(id: UtilityButtonId.paste),
            ...strip.skip(2),
          ],
          onPaste: () => pastes++,
        ),
      );
      await tester.pumpAndSettle();
      final scroller = scrollerOf(label(UtilityButtonId.paste));
      ScrollController controller() =>
          tester.widget<SingleChildScrollView>(scroller).controller!;

      controller().jumpTo(20);
      await tester.pumpAndSettle();
      expect(controller().offset, 20);

      await tester.tap(find.byTooltip(label(UtilityButtonId.paste)));
      await tester.pumpAndSettle();

      expect(pastes, 1);
      expect(controller().offset, 0);
    });

    // Slice L4 — A+ / A- / scroll top and bottom, and indent / outdent, are
    // tapped in runs, so the reset would slide another button under the
    // second tap.
    for (final id in const [
      UtilityButtonId.decreaseFont,
      UtilityButtonId.increaseFont,
      UtilityButtonId.scrollToTop,
      UtilityButtonId.scrollToBottom,
      UtilityButtonId.indent,
      UtilityButtonId.outdent,
    ]) {
      testWidgets('$id keeps the scroller where it is', (tester) async {
        phone(tester);
        var taps = 0;
        void tapped() => taps++;
        await tester.pumpWidget(
          _bar(
            shortcuts: [_bold],
            utilityConfigs: const [
              UtilityButtonConfig(id: UtilityButtonId.undo),
              UtilityButtonConfig(id: UtilityButtonId.redo),
              UtilityButtonConfig(id: UtilityButtonId.decreaseFont),
              UtilityButtonConfig(id: UtilityButtonId.increaseFont),
              UtilityButtonConfig(id: UtilityButtonId.scrollToTop),
              UtilityButtonConfig(id: UtilityButtonId.scrollToBottom),
              UtilityButtonConfig(id: UtilityButtonId.indent),
              UtilityButtonConfig(id: UtilityButtonId.outdent),
              UtilityButtonConfig(id: UtilityButtonId.settings),
            ],
            onDecreaseFontSize: id == UtilityButtonId.decreaseFont
                ? tapped
                : null,
            onIncreaseFontSize: id == UtilityButtonId.increaseFont
                ? tapped
                : null,
            onScrollToTop: id == UtilityButtonId.scrollToTop ? tapped : null,
            onScrollToBottom: id == UtilityButtonId.scrollToBottom
                ? tapped
                : null,
            onIndent: id == UtilityButtonId.indent ? tapped : null,
            onOutdent: id == UtilityButtonId.outdent ? tapped : null,
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byTooltip(label(id));
        final scroller = scrollerOf(label(id));
        ScrollController controller() =>
            tester.widget<SingleChildScrollView>(scroller).controller!;

        // Off the start, with the button still under the finger.
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        if (controller().offset == 0) {
          controller().jumpTo(8);
          await tester.pumpAndSettle();
        }
        final scrolled = controller().offset;
        expect(scrolled, greaterThan(0));
        expect(button.hitTestable(), findsOneWidget);

        final at = tester.getCenter(button);
        await tester.tapAt(at);
        await tester.pumpAndSettle();
        expect(controller().offset, scrolled);
        expect(tester.getCenter(button), at);

        await tester.tapAt(at);
        await tester.pumpAndSettle();
        expect(taps, 2, reason: 'the second tap lands on the same button');
        expect(controller().offset, scrolled);
      });
    }

    testWidgets('the single-row bar pins undo and redo at its trailing edge, '
        'its 48 dp buttons behind one edge fade', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        _bar(
          shortcuts: [_bold, _italic, _header, _custom, _bold, _italic],
          utilityConfigs: strip,
          splitEnabled: false,
        ),
      );
      await tester.pumpAndSettle();

      final undo = find.byTooltip(label(UtilityButtonId.undo));
      expect(scrollerOf(label(UtilityButtonId.undo)), findsNothing);
      expect(scrollerOf(label(UtilityButtonId.redo)), findsNothing);
      expect(scrollerOf(label(UtilityButtonId.settings)), findsOneWidget);
      expect(undo.hitTestable(), findsOneWidget);
      expect(tester.getSize(undo), const Size.square(48));
      expect(
        tester.getTopRight(find.byTooltip(label(UtilityButtonId.redo))).dx,
        greaterThan(360 - 48 - MarkdownBarMetrics.sidePadding),
      );
      final fade = tester.state<MarkdownBarEdgeFadeState>(
        find.byType(MarkdownBarEdgeFade),
      );
      expect(fade.fadesEnd, isTrue);

      await tester.drag(
        scrollerOf(label(UtilityButtonId.settings)),
        const Offset(-800, 0),
      );
      await tester.pumpAndSettle();
      expect(fade.fadesStart, isTrue);
      expect(fade.fadesEnd, isFalse);
      expect(undo.hitTestable(), findsOneWidget);
    });

    testWidgets('the preview bar pins undo and redo outside its scroller', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        _bar(shortcuts: [_bold], utilityConfigs: strip, isPreviewMode: true),
      );

      expect(scrollerOf(label(UtilityButtonId.undo)), findsNothing);
      expect(scrollerOf(label(UtilityButtonId.redo)), findsNothing);
      expect(scrollerOf(label(UtilityButtonId.settings)), findsOneWidget);
      expect(
        find.byTooltip(label(UtilityButtonId.undo)).hitTestable(),
        findsOneWidget,
      );
    });

    group('with undo and redo unpinned', () {
      testWidgets('the split bar scrolls them in their config place, past '
          'the one divider', (tester) async {
        phone(tester);
        await tester.pumpWidget(
          _bar(
            shortcuts: [_bold],
            utilityConfigs: [strip[2], strip[0], strip[1], ...strip.skip(3)],
            pinUndoRedo: false,
          ),
        );

        final undo = find.byTooltip(label(UtilityButtonId.undo));
        final redo = find.byTooltip(label(UtilityButtonId.redo));
        final smaller = find.byTooltip(label(UtilityButtonId.decreaseFont));
        expect(scrollerOf(label(UtilityButtonId.undo)), findsOneWidget);
        expect(scrollerOf(label(UtilityButtonId.redo)), findsOneWidget);
        expect(find.byType(MarkdownBarDivider), findsOneWidget);
        expect(
          tester.getTopLeft(undo).dx,
          greaterThan(tester.getTopRight(find.byType(MarkdownBarDivider)).dx),
        );
        expect(
          tester.getTopLeft(smaller).dx,
          lessThan(tester.getTopLeft(undo).dx),
        );
        expect(
          tester.getTopLeft(undo).dx,
          lessThan(tester.getTopLeft(redo).dx),
        );
      });

      testWidgets('a tap on undo keeps the scroller where it is', (
        tester,
      ) async {
        phone(tester);
        var undos = 0;
        await tester.pumpWidget(
          _bar(
            shortcuts: [_bold],
            utilityConfigs: const [
              UtilityButtonConfig(id: UtilityButtonId.decreaseFont),
              UtilityButtonConfig(id: UtilityButtonId.increaseFont),
              UtilityButtonConfig(id: UtilityButtonId.undo),
              UtilityButtonConfig(id: UtilityButtonId.redo),
              UtilityButtonConfig(id: UtilityButtonId.settings),
            ],
            canUndo: true,
            onUndo: () => undos++,
            pinUndoRedo: false,
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byTooltip(label(UtilityButtonId.undo));
        ScrollController controller() => tester
            .widget<SingleChildScrollView>(
              scrollerOf(label(UtilityButtonId.undo)),
            )
            .controller!;

        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        if (controller().offset == 0) {
          controller().jumpTo(8);
          await tester.pumpAndSettle();
        }
        final scrolled = controller().offset;
        expect(scrolled, greaterThan(0));

        final at = tester.getCenter(button);
        await tester.tapAt(at);
        await tester.pumpAndSettle();
        await tester.tapAt(at);
        await tester.pumpAndSettle();
        expect(undos, 2, reason: 'the second tap lands on undo again');
        expect(controller().offset, scrolled);
      });

      testWidgets('a config that hides undo hides it', (tester) async {
        phone(tester);
        await tester.pumpWidget(
          _bar(
            shortcuts: [_bold],
            utilityConfigs: [
              const UtilityButtonConfig(
                id: UtilityButtonId.undo,
                isVisible: false,
              ),
              ...strip.skip(1),
            ],
            pinUndoRedo: false,
          ),
        );

        expect(find.byTooltip(label(UtilityButtonId.undo)), findsNothing);
        expect(scrollerOf(label(UtilityButtonId.redo)), findsOneWidget);
      });

      testWidgets('the single-row bar has no trailing pinned pair', (
        tester,
      ) async {
        phone(tester);
        await tester.pumpWidget(
          _bar(
            shortcuts: [_bold, _italic],
            utilityConfigs: strip,
            splitEnabled: false,
            pinUndoRedo: false,
          ),
        );

        expect(scrollerOf(label(UtilityButtonId.undo)), findsOneWidget);
        expect(scrollerOf(label(UtilityButtonId.redo)), findsOneWidget);
        // Only the divider inside the row, between shortcuts and utilities.
        expect(find.byType(MarkdownBarDivider), findsOneWidget);
      });

      testWidgets('the preview bar scrolls them with the rest', (tester) async {
        phone(tester);
        await tester.pumpWidget(
          _bar(
            shortcuts: [_bold],
            utilityConfigs: strip,
            isPreviewMode: true,
            pinUndoRedo: false,
          ),
        );

        expect(scrollerOf(label(UtilityButtonId.undo)), findsOneWidget);
        expect(scrollerOf(label(UtilityButtonId.redo)), findsOneWidget);
      });
    });

    // U1 C16: the fade is the bar's ground painted over a faded edge, never
    // a ShaderMask, whose saveLayer ran per strip on every frame.
    testWidgets('the fade paints the ground over a fading edge only, with '
        'no saveLayer mask', (tester) async {
      phone(tester);
      await tester.pumpWidget(_bar(shortcuts: [_bold], utilityConfigs: strip));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(MarkdownBarEdgeFade),
          matching: find.byType(ShaderMask),
        ),
        findsNothing,
      );
      final scroller = find.ancestor(
        of: scrollerOf(label(UtilityButtonId.settings)),
        matching: find.byType(MarkdownBarEdgeFade),
      );
      Finder overlays(Finder of) => find.descendant(
        of: of,
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient != null,
        ),
      );
      final shortcuts = find.ancestor(
        of: find.byTooltip('Bold'),
        matching: find.byType(MarkdownBarEdgeFade),
      );
      expect(overlays(shortcuts), findsNothing);

      final ground = Theme.of(tester.element(scroller)).colorScheme.surface;
      expect(overlays(scroller), findsOneWidget);
      final end = tester.widget<DecoratedBox>(overlays(scroller));
      expect((end.decoration as BoxDecoration).gradient!.colors, [
        ground,
        ground.withValues(alpha: 0),
      ]);
      expect(
        tester.getRect(overlays(scroller)).right,
        tester.getRect(scroller).right,
      );
      expect(
        find.ancestor(
          of: overlays(scroller),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );

      await tester.drag(
        scrollerOf(label(UtilityButtonId.settings)),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();

      expect(overlays(scroller), findsOneWidget);
      expect(
        tester.getRect(overlays(scroller)).left,
        tester.getRect(scroller).left,
      );
    });
  });

  group('semantics (U1.8)', () {
    testWidgets('every bar button is one button node with its enabled '
        'state, and B is not read as a letter', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _bar(
          shortcuts: [_bold],
          utilityConfigs: const [
            UtilityButtonConfig(id: UtilityButtonId.undo),
            UtilityButtonConfig(id: UtilityButtonId.settings),
          ],
        ),
      );

      expect(
        tester.getSemantics(find.byTooltip('Bold')),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          tooltip: 'Bold',
          label: '',
        ),
      );
      expect(
        tester.getSemantics(find.byTooltip('Undo')),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
      final undoGlyph = tester.widget<Icon>(find.byIcon(Icons.undo));
      expect(
        undoGlyph.color!.a,
        moreOrLessEquals(FormMetrics.disabledOpacity, epsilon: 0.01),
      );
      semantics.dispose();
    });
  });

  testWidgets('entering reorder mode unfocuses the editor (U1.3)', (
    tester,
  ) async {
    final editorFocus = FocusNode();
    addTearDown(editorFocus.dispose);
    await tester.pumpWidget(
      _bar(
        shortcuts: [_bold],
        utilityConfigs: const [
          UtilityButtonConfig(id: UtilityButtonId.reorder),
        ],
        onReorderComplete: (_) {},
        editorFocus: editorFocus,
      ),
    );
    editorFocus.requestFocus();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.swap_horiz));
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsOneWidget);
    expect(editorFocus.hasFocus, isFalse);
  });

  group('360 x 780, German at text scale 2.0', () {
    final de = lookupAppLocalizations(const Locale('de'));
    final many = [
      _bold,
      _italic,
      _header,
      for (final id in [
        'default_strikethrough',
        'default_highlight',
        'default_bullet_list',
        'default_numbered_list',
        'default_checkbox',
        'default_quote',
        'default_inline_code',
        'default_code_block',
        'default_link',
        'default_checked_checkbox',
        'default_horizontal_rule',
        'default_money_subtract',
      ])
        CustomMarkdownShortcut(
          id: id,
          label: id,
          iconCodePoint: 0xe145,
          iconFontFamily: 'MaterialIcons',
          beforeText: '',
          afterText: '',
          isDefault: true,
        ),
    ];

    // Reorder first in the scroller, where a 360 dp bar shows it; the panel
    // still lists every utility.
    final reorderFirst = [
      const UtilityButtonConfig(id: UtilityButtonId.reorder),
      for (final config in UtilityButtonConfig.defaults())
        if (config.id != UtilityButtonId.reorder) config,
    ];
    final lastChip = UtilityButtonDefinition.getById(
      reorderFirst.last.id,
    )!.label(de);
    // Past the long-press timeout a reorder chip lifts.
    const longPress = Duration(milliseconds: 600);

    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('the visible buttons are 48 dp and hit-testable', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        _bar(
          shortcuts: many,
          utilityConfigs: UtilityButtonConfig.defaults(),
          canUndo: true,
          onReorderComplete: (_) {},
          locale: const Locale('de'),
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final tooltip in [
        de.bold,
        de.italic,
        de.headers,
        de.undo,
        de.redo,
      ]) {
        final button = find.byTooltip(tooltip);
        expect(button.hitTestable(), findsOneWidget, reason: tooltip);
        expect(tester.getSize(button), const Size.square(48), reason: tooltip);
      }
      expect(tester.getSize(find.byType(MarkdownBar)).height, 55);
    });

    testWidgets('unpinned, the visible buttons are 48 dp and hit-testable '
        'and the bar keeps its height', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        _bar(
          shortcuts: many,
          utilityConfigs: UtilityButtonConfig.defaults(),
          canUndo: true,
          onReorderComplete: (_) {},
          locale: const Locale('de'),
          textScale: 2.0,
          pinUndoRedo: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final tooltip in [de.bold, de.italic, de.headers, de.undo]) {
        final button = find.byTooltip(tooltip);
        expect(button.hitTestable(), findsOneWidget, reason: tooltip);
        expect(tester.getSize(button), const Size.square(48), reason: tooltip);
      }
      // Redo scrolls with the rest; it may stand past the strip's edge.
      expect(tester.getSize(find.byTooltip(de.redo)), const Size.square(48));
      expect(tester.getSize(find.byType(MarkdownBar)).height, 55);
    });

    testWidgets('the reorder panel fits with the keyboard up and down, its '
        'chips in German and 48 dp tall', (tester) async {
      phone(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpWidget(
        _bar(
          shortcuts: many,
          utilityConfigs: reorderFirst,
          onReorderComplete: (_) {},
          locale: const Locale('de'),
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(de.reorderShortcuts));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(MarkdownBar)).height,
        lessThanOrEqualTo(780 / 2),
      );
      expect(find.text(de.bold), findsOneWidget);
      expect(find.text('Bold'), findsNothing);
      expect(find.text(de.strikethrough), findsOneWidget);
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.text(de.bold),
                matching: find.byType(DragTarget<int>),
              ),
            )
            .height,
        greaterThanOrEqualTo(48),
      );

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('on the editor\'s geometry the panel takes half of what the '
        'keyboard leaves, following it down and up, and scrolls', (
      tester,
    ) async {
      phone(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpWidget(
        _bar(
          shortcuts: many,
          utilityConfigs: reorderFirst,
          onReorderComplete: (_) {},
          locale: const Locale('de'),
          asEditorPage: true,
        ),
      );
      await tester.pumpAndSettle();

      double panel() => tester.getSize(find.byType(MarkdownBar)).height;
      await tester.tap(find.byTooltip(de.reorderShortcuts));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(FilledButton), findsOneWidget);
      // Half of what the keyboard leaves, then half the screen once it
      // has gone, then half again when it comes back.
      expect(panel(), moreOrLessEquals((780 - 320) * 0.5));
      expect(find.text(de.bold), findsOneWidget);
      expect(find.text('Bold'), findsNothing);
      expect(find.text(de.strikethrough), findsOneWidget);
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.text(de.bold),
                matching: find.byType(DragTarget<int>),
              ),
            )
            .height,
        greaterThanOrEqualTo(48),
      );

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(panel(), moreOrLessEquals(780 * 0.5));

      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(panel(), moreOrLessEquals((780 - 320) * 0.5));

      // The cap binds, and the panel scrolls to its last chip.
      await tester.scrollUntilVisible(
        find.text(lastChip),
        100,
        // The chips' scroll view, after the header's own.
        scrollable: find
            .descendant(
              of: find.byType(MarkdownBar),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      expect(find.text(lastChip).hitTestable(), findsOneWidget);
    });

    // The German header at 2.0 outgrew the whole cap while the keyboard was
    // still up on the editor's geometry (an overflow of ~152 px).
    testWidgets('at 2.0 on the editor\'s geometry the reorder header scrolls '
        'within the cap with a 280 dp keyboard, going down and up', (
      tester,
    ) async {
      phone(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      final editorFocus = FocusNode();
      addTearDown(editorFocus.dispose);
      await tester.pumpWidget(
        _bar(
          shortcuts: many,
          utilityConfigs: reorderFirst,
          onReorderComplete: (_) {},
          locale: const Locale('de'),
          textScale: 2.0,
          asEditorPage: true,
          editorFocus: editorFocus,
        ),
      );
      editorFocus.requestFocus();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(de.reorderShortcuts));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(editorFocus.hasFocus, isFalse, reason: 'entering unfocuses');
      expect(
        tester.getSize(find.byType(MarkdownBar)).height,
        lessThanOrEqualTo((780 - 280) * 0.5 + 0.01),
      );

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Only the title scrolls: Done, the panel's only exit, stays in view.
      expect(find.byType(FilledButton).hitTestable(), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(FilledButton),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      final header = find
          .ancestor(
            of: find.text(de.reorderShortcuts),
            matching: find.byType(Scrollable),
          )
          .first;
      expect(
        tester.getSize(header).height,
        lessThanOrEqualTo((780 - 280) * 0.5 * 0.5 + 0.01),
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('the heading menu opens above the bar with the keyboard up '
        'and stays there as it closes', (tester) async {
      phone(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpWidget(
        _bar(
          shortcuts: many,
          utilityConfigs: reorderFirst,
          currentHeadingLevel: () => 2,
          locale: const Locale('de'),
          textScale: 2.0,
          asEditorPage: true,
        ),
      );
      await tester.pumpAndSettle();

      // The H button's own top: the menu may meet it, never cover it.
      double buttonTop() => tester.getTopLeft(find.byTooltip(de.headers)).dy;
      final barTop = buttonTop();
      await tester.tap(find.byTooltip(de.headers));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The menu's own scroll view: rows that wrap at 2.0 outgrow the room
      // above the keyboard, and the menu scrolls them rather than spill.
      final menu = find
          .ancestor(
            of: find.text(de.headingBodyText),
            matching: find.byType(Scrollable),
          )
          .first;
      double menuBottom() => tester.getBottomLeft(menu).dy;
      expect(menuBottom(), lessThanOrEqualTo(barTop));
      expect(tester.getTopLeft(menu).dy, greaterThan(0));
      expect(find.text(de.headingBodyText).hitTestable(), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(de.header6),
        50,
        scrollable: menu,
      );
      expect(find.text(de.header6).hitTestable(), findsOneWidget);

      // The keyboard closes while the menu is open: the bar falls with it
      // and the menu keeps its side, above, standing on the button where it
      // lands.
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        menuBottom(),
        moreOrLessEquals(
          buttonTop() -
              MarkdownBarMetrics.verticalPadding -
              MarkdownBarMetrics.hairline,
          epsilon: 1,
        ),
      );
    });

    testWidgets('a dragged chip lands where it is dropped, and no chip moves '
        'while it hovers', (tester) async {
      phone(tester);
      List<CustomMarkdownShortcut>? saved;
      await tester.pumpWidget(
        _bar(
          shortcuts: many,
          utilityConfigs: reorderFirst,
          onReorderComplete: (order) => saved = order,
          locale: const Locale('de'),
          asEditorPage: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(de.reorderShortcuts));
      await tester.pumpAndSettle();

      Finder chip(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byType(DragTarget<int>),
      );
      final targets = find.descendant(
        of: find.byType(MarkdownBarReorderWrap).first,
        matching: find.byType(DragTarget<int>),
      );
      List<Offset> layout() => [
        for (final element in targets.evaluate())
          tester.getTopLeft(find.byElementPredicate((e) => e == element)),
      ];
      // A chip on a later run than the first.
      final firstTop = tester.getTopLeft(chip(de.bold)).dy;
      final later = targets.evaluate().toList().indexWhere(
        (e) =>
            tester.getTopLeft(find.byElementPredicate((x) => x == e)).dy >
            firstTop,
      );
      expect(later, greaterThan(1));
      final drop = tester.getCenter(
        find.byElementPredicate(
          (e) => e == targets.evaluate().elementAt(later),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(chip(de.bold)),
      );
      await tester.pump(longPress);
      await gesture.moveTo(drop - const Offset(4, 0));
      await tester.pump();
      final before = layout();
      expect(find.byKey(const ValueKey('reorder-drop-marker')), findsOneWidget);
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump();
      expect(layout(), before);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      final ids = saved!.map((s) => s.id).toList();
      expect(ids.indexOf('default_bold'), later - 1);
      expect(ids.first, 'default_italic');
    });

    testWidgets('a drag held at the panel\'s bottom edge scrolls it', (
      tester,
    ) async {
      phone(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpWidget(
        _bar(
          shortcuts: many,
          utilityConfigs: reorderFirst,
          onReorderComplete: (_) {},
          locale: const Locale('de'),
          asEditorPage: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(de.reorderShortcuts));
      await tester.pumpAndSettle();

      // The chips' scroll view, after the header's own.
      final scrollable = find
          .descendant(
            of: find.byType(MarkdownBar),
            matching: find.byType(Scrollable),
          )
          .last;
      double offset() =>
          tester.state<ScrollableState>(scrollable).position.pixels;
      expect(offset(), 0);

      final gesture = await tester.startGesture(
        tester.getCenter(
          find.ancestor(
            of: find.text(de.bold),
            matching: find.byType(DragTarget<int>),
          ),
        ),
      );
      await tester.pump(longPress);
      await gesture.moveTo(
        tester.getBottomLeft(scrollable) + const Offset(60, -4),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(0, 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(offset(), greaterThan(0));
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}

const _bold = CustomMarkdownShortcut(
  id: 'default_bold',
  label: 'Bold',
  iconCodePoint: 0xe238,
  iconFontFamily: 'MaterialIcons',
  beforeText: '**',
  afterText: '**',
  isDefault: true,
);

const _italic = CustomMarkdownShortcut(
  id: 'default_italic',
  label: 'Italic',
  iconCodePoint: 0xe23f,
  iconFontFamily: 'MaterialIcons',
  beforeText: '_',
  afterText: '_',
  isDefault: true,
);

const _header = CustomMarkdownShortcut(
  id: 'default_header',
  label: 'Headers',
  iconCodePoint: 0xe167,
  iconFontFamily: 'MaterialIcons',
  beforeText: '# ',
  afterText: '',
  isDefault: true,
  insertType: 'header',
);

const _custom = CustomMarkdownShortcut(
  id: 'custom_set',
  label: 'Satz',
  iconCodePoint: 0xe145,
  iconFontFamily: 'MaterialIcons',
  beforeText: 'Set: ',
  afterText: '',
);

/// A bar with only what a case varies; everything else inert.
Widget _bar({
  List<CustomMarkdownShortcut> shortcuts = const [],
  List<UtilityButtonConfig> utilityConfigs = const [
    UtilityButtonConfig(id: UtilityButtonId.settings),
  ],
  bool isPreviewMode = false,
  bool canUndo = false,
  bool hapticsEnabled = true,
  bool pinUndoRedo = true,
  VoidCallback? onUndo,
  VoidCallback? onIndent,
  VoidCallback? onOutdent,
  VoidCallback? onPaste,
  int? Function()? currentHeadingLevel,
  ValueChanged<CustomMarkdownShortcut>? onShortcutPressed,
  ValueChanged<List<CustomMarkdownShortcut>>? onReorderComplete,
  VoidCallback? onDecreaseFontSize,
  VoidCallback? onIncreaseFontSize,
  VoidCallback? onScrollToTop,
  VoidCallback? onScrollToBottom,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  FocusNode? editorFocus,
  bool splitEnabled = true,
  bool asEditorPage = false,
  double shortcutRatio = 0.7,
  bool showBackground = true,
  Color? fadeGround,
  Brightness brightness = Brightness.light,
}) {
  final column = Column(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      // Stands in for the editor the bar sits under.
      if (editorFocus != null)
        Focus(focusNode: editorFocus, child: const SizedBox.shrink()),
      MarkdownBar(
        shortcuts: shortcuts,
        isPreviewMode: isPreviewMode,
        canUndo: canUndo,
        canRedo: false,
        previewFontSize: 14,
        onUndo: onUndo ?? () {},
        onRedo: () {},
        onDecreaseFontSize: onDecreaseFontSize ?? () {},
        onIncreaseFontSize: onIncreaseFontSize ?? () {},
        onScrollToTop: onScrollToTop,
        onScrollToBottom: onScrollToBottom,
        onSettings: () {},
        onIndent: onIndent,
        onOutdent: onOutdent,
        onPaste: onPaste,
        currentHeadingLevel: currentHeadingLevel,
        hapticsEnabled: hapticsEnabled,
        onShortcutPressed: onShortcutPressed ?? (_) {},
        onReorderComplete: onReorderComplete,
        utilityConfigs: utilityConfigs,
        splitEnabled: splitEnabled,
        pinUndoRedo: pinUndoRedo,
        shortcutRatio: shortcutRatio,
        showBackground: showBackground,
        fadeGround: fadeGround,
      ),
    ],
  );
  return MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    // The note editor's own geometry: its Scaffold does not resize for the
    // keyboard and pads the body by the inset itself, so the bar's
    // MediaQuery still carries the keyboard.
    home: asEditorPage
        ? Scaffold(
            resizeToAvoidBottomInset: false,
            body: Builder(
              builder: (context) => Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: column,
              ),
            ),
          )
        : Scaffold(body: column),
  );
}
