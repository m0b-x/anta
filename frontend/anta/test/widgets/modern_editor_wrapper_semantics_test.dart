import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/l10n/app_localizations_ro.dart';
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
  final ro = AppLocalizationsRo();

  /// A zone label with or without the content it names: "Toggle task"
  /// and "Toggle task: buy milk" both match, "Open linked note" never
  /// matches "Open link".
  Pattern zone(String action) => RegExp('^${RegExp.escape(action)}(: |\$)');

  const document =
      'plain line\n'
      '- [ ] task\n'
      '[link](https://x.dev)\n'
      'see #tag now\n'
      '- [ ] second task\n'
      r'$$ balance'
      '\n'
      'see [[Squat]] plan';

  const moneyLine = 5;

  /// Mounts the wrapper over [document] with every zone kind enabled and
  /// records every tag / link / money / wiki-link tap. [wikiLinks] picks
  /// whether the newest zone is wired at all. The returned `app` rebuilds
  /// the same tree — same controller, same editor state — under another
  /// locale.
  Future<
    ({
      List<String> tags,
      List<String> links,
      List<int> money,
      List<String> wikis,
      CodeLineEditingController controller,
      FocusNode focusNode,
      Widget Function(Locale locale) app,
    })
  >
  pumpEditor(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    bool wikiLinks = true,
    String text = document,
  }) async {
    final tags = <String>[];
    final links = <String>[];
    final money = <int>[];
    final wikis = <String>[];
    final controller = CodeLineEditingController.fromText(text);
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
          onOpenWikiLink: wikiLinks ? wikis.add : null,
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
      wikis: wikis,
      controller: controller,
      focusNode: focusNode,
      app: app,
    );
  }

  /// Focuses the editor: only a focused editor reveals its caret line.
  Future<void> focusEditor(WidgetTester tester, FocusNode focusNode) async {
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
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

    expect(
      find.semantics.byLabel(zone(l10n.editorZoneToggleTask)),
      findsExactly(2),
    );
    expect(find.semantics.byLabel(zone(l10n.editorZoneOpenLink)), findsOne);
    expect(find.semantics.byLabel(zone(l10n.editorZoneSearchTag)), findsOne);
    expect(find.semantics.byLabel(l10n.editorZoneOpenMoney), findsOne);
    expect(find.semantics.byLabel(zone(l10n.editorZoneOpenWikiLink)), findsOne);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a quoted task gets a toggle node that ticks its box', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, text: 'plain line\n> - [ ] quoted task');
    await parkCaret(tester, e.controller, 0);

    expect(find.semantics.byLabel(zone(l10n.editorZoneToggleTask)), findsOne);
    tester.semantics.tap(
      find.semantics.byLabel(zone(l10n.editorZoneToggleTask)),
    );
    await tester.pump();
    expect(e.controller.codeLines[1].text, '> - [x] quoted task');

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('an unwired wiki-link zone contributes no node', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, wikiLinks: false);
    await parkCaret(tester, e.controller, 0);

    expect(
      find.semantics.byLabel(zone(l10n.editorZoneOpenWikiLink)),
      findsNothing,
    );
    expect(
      find.semantics.byLabel(zone(l10n.editorZoneToggleTask)),
      findsExactly(2),
    );
    expect(find.semantics.byLabel(zone(l10n.editorZoneOpenLink)), findsOne);
    expect(find.semantics.byLabel(zone(l10n.editorZoneSearchTag)), findsOne);
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
        find.semantics.byLabel(zone(l10n.editorZoneToggleTask)).first,
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

    tester.semantics.tap(find.semantics.byLabel(zone(l10n.editorZoneOpenLink)));
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

    tester.semantics.tap(
      find.semantics.byLabel(zone(l10n.editorZoneSearchTag)),
    );
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
      expect(e.wikis, isEmpty);
      expect(e.controller.selection, selection);

      handle.dispose();
      await teardownEditor(tester);
    },
  );

  testWidgets(
    'activating the wiki-link node opens the note it names and leaves the '
    'caret alone',
    (tester) async {
      final handle = tester.ensureSemantics();
      final e = await pumpEditor(tester);
      await parkCaret(tester, e.controller, 0);
      final selection = e.controller.selection;

      tester.semantics.tap(
        find.semantics.byLabel(zone(l10n.editorZoneOpenWikiLink)),
      );
      await tester.pump();

      expect(e.wikis, ['Squat']);
      expect(e.links, isEmpty);
      expect(e.tags, isEmpty);
      expect(e.money, isEmpty);
      expect(e.controller.selection, selection);

      handle.dispose();
      await teardownEditor(tester);
    },
  );

  testWidgets('the caret line contributes no zone node', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester);
    await focusEditor(tester, e.focusNode);
    await parkCaret(tester, e.controller, 1);

    expect(find.semantics.byLabel(zone(l10n.editorZoneToggleTask)), findsOne);
    expect(find.semantics.byLabel(zone(l10n.editorZoneOpenLink)), findsOne);
    expect(find.semantics.byLabel(zone(l10n.editorZoneSearchTag)), findsOne);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('an unfocused editor reveals no caret line — its box keeps '
      'its node', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester);
    await parkCaret(tester, e.controller, 1);
    expect(e.focusNode.hasFocus, isFalse);

    expect(
      find.semantics.byLabel(zone(l10n.editorZoneToggleTask)),
      findsExactly(2),
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a caret past the marker keeps the caret line\'s toggle node, '
      'and activating it leaves the caret alone', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester);
    await focusEditor(tester, e.focusNode);
    e.controller.selection = CodeLineSelection.collapsed(
      index: 1,
      offset: e.controller.codeLines[1].length,
    );
    await tester.pump();
    await tester.pump();
    final selection = e.controller.selection;

    expect(
      find.semantics.byLabel(zone(l10n.editorZoneToggleTask)),
      findsExactly(2),
    );

    tester.semantics.tap(
      find.semantics.byLabel(zone(l10n.editorZoneToggleTask)).first,
    );
    await tester.pump();

    expect(e.controller.codeLines[1].text, '- [x] task');
    expect(e.controller.selection, selection);

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
        isSemantics(label: l10n.editorZoneToggleTaskNamed('task')),
        isSemantics(label: l10n.editorZoneOpenLinkNamed('link')),
        isSemantics(label: l10n.editorZoneSearchTagNamed('#tag')),
        isSemantics(label: l10n.editorZoneToggleTaskNamed('second task')),
        isSemantics(label: l10n.editorZoneOpenMoney),
        isSemantics(label: l10n.editorZoneOpenWikiLinkNamed('Squat')),
      ]),
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a zone names its content, a box its state, a link its role', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(
      tester,
      text:
          'plain line\n'
          '- [x] done **set**\n'
          '- [ ] \n'
          'go to <https://x.dev> or [[Squat|the plan]]',
    );
    await parkCaret(tester, e.controller, 0);

    expect(
      find.semantics.byLabel(l10n.editorZoneToggleTaskNamed('done set')),
      findsOne,
    );
    expect(
      find.semantics.byLabel(l10n.editorZoneToggleTaskNamed('done set')),
      isSemantics(hasCheckedState: true, isChecked: true, isLink: false),
    );
    // A blank task has nothing to name: the bare action, unchecked.
    expect(
      find.semantics.byLabel(l10n.editorZoneToggleTask),
      isSemantics(hasCheckedState: true, isChecked: false),
    );
    expect(
      find.semantics.byLabel(l10n.editorZoneOpenLinkNamed('https://x.dev')),
      isSemantics(isLink: true, hasCheckedState: false),
    );
    // An aliased wiki link reads the alias the editor shows, not the
    // concealed target.
    expect(
      find.semantics.byLabel(l10n.editorZoneOpenWikiLinkNamed('the plan')),
      isSemantics(isLink: true),
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a marked custom state reads checked, the state a tap clears', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(
      tester,
      text:
          'plain line\n'
          '- [-] skip deadlift\n'
          '- [/] half done\n'
          '- [x]done',
    );
    await parkCaret(tester, e.controller, 0);

    expect(
      find.semantics.byLabel(l10n.editorZoneToggleTaskNamed('skip deadlift')),
      isSemantics(hasCheckedState: true, isChecked: true),
    );
    expect(
      find.semantics.byLabel(l10n.editorZoneToggleTaskNamed('half done')),
      isSemantics(hasCheckedState: true, isChecked: true),
    );
    // No blank after the box: the name still starts at the content.
    expect(
      find.semantics.byLabel(l10n.editorZoneToggleTaskNamed('done')),
      isSemantics(hasCheckedState: true, isChecked: true),
    );

    tester.semantics.tap(
      find.semantics.byLabel(l10n.editorZoneToggleTaskNamed('skip deadlift')),
    );
    await tester.pump();
    await tester.pump();
    expect(e.controller.codeLines[1].text, '- [ ] skip deadlift');
    expect(
      find.semantics.byLabel(l10n.editorZoneToggleTaskNamed('skip deadlift')),
      isSemantics(hasCheckedState: true, isChecked: false),
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('both halves of a link a ghost cuts read the link text', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(
      tester,
      text: 'plain line\n[a {{reps}} b](https://x.dev)',
    );
    await parkCaret(tester, e.controller, 0);

    final labels = find.semantics
        .byLabel(zone(l10n.editorZoneOpenLink))
        .evaluate()
        .map((node) => node.label)
        .toList();
    expect(labels, hasLength(2));
    expect(labels.toSet(), hasLength(1));
    expect(labels.first, isNot(contains('[')));
    expect(labels.first, isNot(contains('https')));
    expect(labels.first, startsWith(l10n.editorZoneOpenLinkNamed('a ')));

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('typing in a task keeps its zone node', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, text: 'plain line\n- [ ] squat');
    await parkCaret(tester, e.controller, 0);
    final before = find.semantics
        .byLabel(l10n.editorZoneToggleTaskNamed('squat'))
        .evaluate()
        .single
        .id;

    e.controller.codeLines = e.controller.codeLines.replaceLine(
      1,
      const CodeLine('- [ ] squats'),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.semantics
          .byLabel(l10n.editorZoneToggleTaskNamed('squats'))
          .evaluate()
          .single
          .id,
      before,
      reason:
          'the label carries the task text, so keying the node on it '
          'would move the reader off the zone on every keystroke',
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a Romanian editor fills the Romanian patterns', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, locale: const Locale('ro'));
    await parkCaret(tester, e.controller, 0);

    expect(
      find.semantics.byLabel(ro.editorZoneToggleTaskNamed('task')),
      findsOne,
    );
    expect(
      find.semantics.byLabel(ro.editorZoneOpenWikiLinkNamed('Squat')),
      findsOne,
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a German editor fills the German patterns', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, locale: const Locale('de'));
    await parkCaret(tester, e.controller, 0);

    expect(
      find.semantics.byLabel(de.editorZoneToggleTaskNamed('task')),
      findsOne,
    );
    expect(
      find.semantics.byLabel(de.editorZoneSearchTagNamed('#tag')),
      findsOne,
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a repeat semantics flush over an unchanged document '
      'enumerates only the caret line', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester);
    await focusEditor(tester, e.focusNode);
    await parkCaret(tester, e.controller, 0);
    expect(
      find.semantics.byLabel(zone(l10n.editorZoneToggleTask)),
      findsExactly(2),
    );

    // A caret round trip, not a single move: the line the caret leaves
    // was never memoized while it was revealed, so 0 -> 1 -> 0 is the
    // shortest path back to a flush where every line but the caret's
    // own hits the memo. The caret line's zones hang on the caret offset,
    // so it is enumerated on each flush — that one line, never more.
    // The toggle-node counts either side prove the flush really ran.
    await parkCaret(tester, e.controller, 1);
    expect(find.semantics.byLabel(zone(l10n.editorZoneToggleTask)), findsOne);

    ModernEditorWrapper.debugZoneResolveCount = 0;
    await parkCaret(tester, e.controller, 0);
    expect(
      find.semantics.byLabel(zone(l10n.editorZoneToggleTask)),
      findsExactly(2),
    );
    expect(ModernEditorWrapper.debugZoneResolveCount, 1);

    // An edit off the caret line keys a new memo entry, so the counter
    // is not simply stuck at zero.
    tester.semantics.tap(
      find.semantics.byLabel(zone(l10n.editorZoneToggleTask)).first,
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

    expect(
      find.semantics.byLabel(zone(l10n.editorZoneToggleTask)),
      findsExactly(2),
    );
    expect(find.semantics.byLabel(zone(l10n.editorZoneOpenWikiLink)), findsOne);

    await tester.pumpWidget(e.app(const Locale('de')));
    await tester.pumpAndSettle();

    expect(
      find.semantics.byLabel(zone(de.editorZoneToggleTask)),
      findsExactly(2),
    );
    expect(
      find.semantics.byLabel(zone(l10n.editorZoneToggleTask)),
      findsNothing,
    );
    // The newest zone's label is translated too, and translated to
    // something other than the English string — a missing ARB entry falls
    // back to English and would otherwise pass the relabel assertion.
    expect(
      de.editorZoneOpenWikiLink,
      isNot(l10n.editorZoneOpenWikiLink),
      reason: 'the German label is a translation, not the English fallback',
    );
    expect(find.semantics.byLabel(zone(de.editorZoneOpenWikiLink)), findsOne);
    expect(
      find.semantics.byLabel(zone(l10n.editorZoneOpenWikiLink)),
      findsNothing,
    );

    handle.dispose();
    await teardownEditor(tester);
  });
}
