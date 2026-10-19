import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';
import 'package:anta/models/utility_button_config.dart';
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

    test('a stored layout gains them at the end, its own order kept', () {
      // A layout saved before indent existed: every other id, rearranged.
      final stored = [
        for (final id in UtilityButtonId.defaultOrder.reversed)
          if (id != UtilityButtonId.indent && id != UtilityButtonId.outdent)
            UtilityButtonConfig(
              id: id,
              isVisible: id != UtilityButtonId.undo,
            ),
      ];

      final decoded = UtilityButtonConfig.decode(
        UtilityButtonConfig.encode(stored),
      );

      expect(decoded.take(stored.length), stored);
      expect(decoded.map((c) => c.id).skip(stored.length), [
        UtilityButtonId.indent,
        UtilityButtonId.outdent,
      ]);
      expect(decoded.length, UtilityButtonId.defaultOrder.length);
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
    testWidgets('lists the six levels with their markers and ids', (
      tester,
    ) async {
      await tester.pumpWidget(_bar(shortcuts: [_header]));

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();

      expect(
        find.byType(FormMenuChoiceItem<CustomMarkdownShortcut>),
        findsNWidgets(6),
      );
      for (var level = 1; level <= 6; level++) {
        expect(find.text('Header $level'), findsOneWidget);
        expect(find.text('#' * level), findsOneWidget);
        expect(
          find.bySemanticsIdentifier(SemanticsIds.editorHeadingLevel(level)),
          findsOneWidget,
        );
      }
    });

    testWidgets('a pick hands the page that level\'s shortcut', (tester) async {
      final picked = <CustomMarkdownShortcut>[];
      await tester.pumpWidget(
        _bar(shortcuts: [_header], onShortcutPressed: picked.add),
      );

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Header 3'));
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
          .widgetList<FormMenuChoiceItem<CustomMarkdownShortcut>>(
            find.byType(FormMenuChoiceItem<CustomMarkdownShortcut>),
          )
          .toList();
      expect([for (final item in items) item.checked], [
        false,
        true,
        false,
        false,
        false,
        false,
      ]);
    });

    testWidgets('a plain caret line checks nothing', (tester) async {
      await tester.pumpWidget(
        _bar(shortcuts: [_header], currentHeadingLevel: () => null),
      );

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widgetList<FormMenuChoiceItem<CustomMarkdownShortcut>>(
              find.byType(FormMenuChoiceItem<CustomMarkdownShortcut>),
            )
            .any((item) => item.checked),
        isFalse,
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

      expect(find.text('Header 1'), findsOneWidget);
      expect(editorFocus.hasFocus, isTrue);
    });

    testWidgets('dismissing picks nothing', (tester) async {
      final picked = <CustomMarkdownShortcut>[];
      await tester.pumpWidget(
        _bar(shortcuts: [_header], onShortcutPressed: picked.add),
      );

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(find.text('Header 1'), findsNothing);
      expect(picked, isEmpty);
    });

    testWidgets('speaks German', (tester) async {
      await tester.pumpWidget(
        _bar(shortcuts: [_header], locale: const Locale('de')),
      );

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();

      expect(find.text('Überschrift 2'), findsOneWidget);
      expect(find.text('Header 2'), findsNothing);
    });
  });

  group('feedback and labels (E27)', () {
    testWidgets('built-in tooltips follow the app language, custom ones '
        'keep their own label', (tester) async {
      await tester.pumpWidget(
        _bar(shortcuts: [_bold, _header, _custom], locale: const Locale('de')),
      );

      expect(find.byTooltip('Fett'), findsOneWidget);
      expect(find.byTooltip('Überschriften'), findsOneWidget);
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
      // An icon button is still 44 x 40: its 20 px glyph, 10 px of
      // padding and 2 px of margin a side. The ink adds no box of its own.
      final iconInk = find.ancestor(
        of: find.byIcon(Icons.undo),
        matching: find.byType(InkResponse),
      );
      expect(tester.getSize(iconInk), const Size(44, MarkdownBar.rowHeight));
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
  VoidCallback? onIndent,
  VoidCallback? onOutdent,
  int? Function()? currentHeadingLevel,
  ValueChanged<CustomMarkdownShortcut>? onShortcutPressed,
  ValueChanged<List<CustomMarkdownShortcut>>? onReorderComplete,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  FocusNode? editorFocus,
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
      body: Column(
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
            onUndo: () {},
            onRedo: () {},
            onDecreaseFontSize: () {},
            onIncreaseFontSize: () {},
            onSettings: () {},
            onIndent: onIndent,
            onOutdent: onOutdent,
            currentHeadingLevel: currentHeadingLevel,
            hapticsEnabled: hapticsEnabled,
            onShortcutPressed: onShortcutPressed ?? (_) {},
            onReorderComplete: onReorderComplete,
            utilityConfigs: utilityConfigs,
          ),
        ],
      ),
    ),
  );
}
