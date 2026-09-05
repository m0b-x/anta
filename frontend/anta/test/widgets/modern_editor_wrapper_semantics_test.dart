import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/utils/re_editor_search_controller.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

/// The app half of the editor's accessibility zones: every region the
/// tap interceptor would claim is also a labelled semantics node under
/// the editor's text field, and activating one runs the same action the
/// pointer path runs.
///
/// The zones themselves are `EditorInputPolicy.zonesOf`'s business
/// (table-tested there); what is pinned here is the wiring — the labels,
/// the mapping from action kind to label, the reveal rule the nodes
/// inherit, that a node's tap reaches the host callbacks, and the two
/// properties the wrapper's zone memo has to keep: a repeat flush over
/// an unchanged document re-enumerates nothing, and a locale change
/// relabels the nodes that are already on screen.
///
/// Harness notes are the same as `modern_editor_wrapper_tag_tap_test.dart`
/// (the fork's cursor blink arms an unguarded delayed value-set on focus
/// changes, so the tree is flushed before it comes down), plus one of its
/// own: the semantics handle is disposed while the tree is still up.
void main() {
  const fontSize = 16.0;
  final l10n = AppLocalizationsEn();
  final de = AppLocalizationsDe();

  const document =
      'plain line\n'
      '- [ ] task\n'
      '[link](https://x.dev)\n'
      'see #tag now\n'
      '- [ ] second task\n'
      r'$$ balance';

  const moneyLine = 5;

  /// Mounts the wrapper over [document] with every zone kind enabled and
  /// records every tag / link / money tap. The returned `app` rebuilds
  /// the same tree — same controller, same editor state — under another
  /// locale.
  Future<
    ({
      List<String> tags,
      List<String> links,
      List<int> money,
      CodeLineEditingController controller,
      Widget Function(Locale locale) app,
    })
  >
  pumpEditor(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    final tags = <String>[];
    final links = <String>[];
    final money = <int>[];
    final controller = CodeLineEditingController.fromText(document);
    final searchController = ReEditorSearchController();
    final scrollController = CodeScrollController();
    final focusNode = FocusNode();
    addTearDown(() {
      focusNode.dispose();
      searchController.dispose();
      controller.dispose();
    });

    Widget app(Locale locale) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: ModernEditorWrapper(
          controller: controller,
          focusNode: focusNode,
          scrollController: scrollController,
          searchController: searchController,
          editorFontSize: fontSize,
          onTextChanged: () {},
          wordWrap: false,
          checkboxTapToggle: true,
          onOpenLink: links.add,
          onMoneyTap: money.add,
          onOpenTag: tags.add,
          showScrollIndicator: false,
        ),
      ),
    );

    await tester.pumpWidget(app(locale));
    await tester.pumpAndSettle();
    return (
      tags: tags,
      links: links,
      money: money,
      controller: controller,
      app: app,
    );
  }

  Future<void> teardownEditor(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  /// Parks the caret on a line with no zones, so no zone is suppressed
  /// by the reveal rule. The default selection sits on line 0, which is
  /// that line — this only makes the dependency explicit.
  Future<void> parkCaret(
    WidgetTester tester,
    CodeLineEditingController controller,
    int lineIndex,
  ) async {
    controller.selection = CodeLineSelection.collapsed(
      index: lineIndex,
      offset: 0,
    );
    await tester.pump();
    await tester.pump();
  }

  SemanticsNode textFieldNode() {
    final finder = find.semantics.byFlag(SemanticsFlag.isTextField);
    expect(finder, findsOne);
    return finder.evaluate().single;
  }

  testWidgets('every checkbox line off the caret line gets a toggle node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester);
    await parkCaret(tester, e.controller, 0);

    expect(find.semantics.byLabel(l10n.editorZoneToggleTask), findsExactly(2));
    expect(find.semantics.byLabel(l10n.editorZoneOpenLink), findsOne);
    expect(find.semantics.byLabel(l10n.editorZoneSearchTag), findsOne);
    expect(find.semantics.byLabel(l10n.editorZoneOpenMoney), findsOne);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets(
    'activating a toggle node checks the box and leaves the caret alone',
    (tester) async {
      final handle = tester.ensureSemantics();
      final e = await pumpEditor(tester);
      await parkCaret(tester, e.controller, 0);
      final selection = e.controller.selection;

      tester.semantics.tap(
        find.semantics.byLabel(l10n.editorZoneToggleTask).first,
      );
      await tester.pump();

      expect(e.controller.codeLines[1].text, '- [x] task');
      expect(e.controller.codeLines[4].text, '- [ ] second task');
      expect(e.controller.selection, selection);

      handle.dispose();
      await teardownEditor(tester);
    },
  );

  testWidgets('activating the link node opens its url', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester);
    await parkCaret(tester, e.controller, 0);

    tester.semantics.tap(find.semantics.byLabel(l10n.editorZoneOpenLink));
    await tester.pump();

    expect(e.links, ['https://x.dev']);
    expect(e.tags, isEmpty);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('activating the tag node searches the tag with its #', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester);
    await parkCaret(tester, e.controller, 0);

    tester.semantics.tap(find.semantics.byLabel(l10n.editorZoneSearchTag));
    await tester.pump();

    expect(e.tags, ['#tag']);
    expect(e.links, isEmpty);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets(
    'activating the money node opens its row and leaves the caret alone',
    (tester) async {
      final handle = tester.ensureSemantics();
      final e = await pumpEditor(tester);
      await parkCaret(tester, e.controller, 0);
      final selection = e.controller.selection;

      tester.semantics.tap(find.semantics.byLabel(l10n.editorZoneOpenMoney));
      await tester.pump();

      expect(e.money, [moneyLine]);
      expect(e.links, isEmpty);
      expect(e.tags, isEmpty);
      expect(e.controller.selection, selection);

      handle.dispose();
      await teardownEditor(tester);
    },
  );

  testWidgets('the caret line contributes no zone node', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester);
    await parkCaret(tester, e.controller, 1);

    expect(find.semantics.byLabel(l10n.editorZoneToggleTask), findsOne);
    expect(find.semantics.byLabel(l10n.editorZoneOpenLink), findsOne);
    expect(find.semantics.byLabel(l10n.editorZoneSearchTag), findsOne);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('the field reads before its zones, and the zones in line order', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester);
    await parkCaret(tester, e.controller, 0);

    expect(textFieldNode().value, document);
    expect(
      tester.semantics.simulatedAccessibilityTraversal(),
      containsAllInOrder(<Matcher>[
        isSemantics(value: document, isTextField: true),
        isSemantics(label: l10n.editorZoneToggleTask),
        isSemantics(label: l10n.editorZoneOpenLink),
        isSemantics(label: l10n.editorZoneSearchTag),
        isSemantics(label: l10n.editorZoneToggleTask),
        isSemantics(label: l10n.editorZoneOpenMoney),
      ]),
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a repeat semantics flush over an unchanged document '
      'enumerates nothing', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester);
    await parkCaret(tester, e.controller, 0);
    expect(find.semantics.byLabel(l10n.editorZoneToggleTask), findsExactly(2));

    // A caret round trip, not a single move: the line the caret leaves
    // was never memoized while it was revealed, so 0 -> 1 -> 0 is the
    // shortest path back to a flush that can enumerate nothing at all.
    // The toggle-node counts either side prove the flush really ran.
    await parkCaret(tester, e.controller, 1);
    expect(find.semantics.byLabel(l10n.editorZoneToggleTask), findsOne);

    ModernEditorWrapper.debugZoneResolveCount = 0;
    await parkCaret(tester, e.controller, 0);
    expect(find.semantics.byLabel(l10n.editorZoneToggleTask), findsExactly(2));
    expect(ModernEditorWrapper.debugZoneResolveCount, 0);

    // An edit off the caret line keys a new memo entry, so the counter
    // is not simply stuck at zero.
    tester.semantics.tap(
      find.semantics.byLabel(l10n.editorZoneToggleTask).first,
    );
    await tester.pump();
    await tester.pump();
    expect(e.controller.codeLines[1].text, '- [x] task');
    expect(ModernEditorWrapper.debugZoneResolveCount, greaterThan(0));

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a locale change relabels the zones already on screen', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester);
    await parkCaret(tester, e.controller, 0);

    expect(find.semantics.byLabel(l10n.editorZoneToggleTask), findsExactly(2));

    await tester.pumpWidget(e.app(const Locale('de')));
    await tester.pumpAndSettle();

    expect(find.semantics.byLabel(de.editorZoneToggleTask), findsExactly(2));
    expect(find.semantics.byLabel(l10n.editorZoneToggleTask), findsNothing);

    handle.dispose();
    await teardownEditor(tester);
  });
}
