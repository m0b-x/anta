import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/controllers/editor_render_controller.dart';
import 'package:anta/controllers/shortcut_applier.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';

/// The applier's two halves, kept apart on purpose.
///
/// [ShortcutApplier.resolve] does all the awaiting (counter mutations,
/// date formatting) and hands back a string; the write is the caller's,
/// so the note editor can run it synchronously inside one undo entry and
/// one edit-tracker guard. A resolve that touched the document would put
/// the insert back in a microtask and lose both. The toggles — headings,
/// line markers, plain wrappers — need nothing awaited, so resolve hands
/// them back as `null` and [ShortcutApplier.applyRewrite] does the work.
void main() {
  CodeLineEditingController controllerWith(String text, {int? line}) {
    final controller = CodeLineEditingController.fromText(text);
    controller.selection = CodeLineSelection.collapsed(
      index: line ?? 0,
      offset: 0,
    );
    return controller;
  }

  CustomMarkdownShortcut shortcut({
    required String insertType,
    String id = '',
    String beforeText = '',
    String afterText = '',
  }) => CustomMarkdownShortcut(
    id: id.isEmpty ? 'test-$insertType' : id,
    label: 'test',
    iconCodePoint: 0xe000,
    iconFontFamily: 'MaterialIcons',
    beforeText: beforeText,
    afterText: afterText,
    insertType: insertType,
  );

  CodeLineSelection range(int line, int base, int extent, {int? toLine}) =>
      CodeLineSelection(
        baseIndex: line,
        baseOffset: base,
        extentIndex: toLine ?? line,
        extentOffset: extent,
      );

  Future<int?> noCounter(String id, CounterOp op) async => null;

  group('resolve', () {
    test('returns the text without touching the document', () async {
      final controller = controllerWith('body');

      final text = await ShortcutApplier.resolve(
        controller: controller,
        shortcut: shortcut(insertType: 'wrap', beforeText: '[', afterText: ']'),
        mutateCounter: noCounter,
      );

      expect(text, '[]');
      expect(controller.text, 'body');
    });

    test('wraps the selection with an asymmetric wrapper', () async {
      final controller = controllerWith('body');
      controller.selection = range(0, 0, 4);

      final text = await ShortcutApplier.resolve(
        controller: controller,
        shortcut: shortcut(
          insertType: 'wrap',
          beforeText: '[',
          afterText: '](url)',
        ),
        mutateCounter: noCounter,
      );

      expect(text, '[body](url)');
      expect(controller.text, 'body');
    });

    test('a symmetric non-plain wrapper inserts both halves', () async {
      // The "historical" before-only result for a symmetric pair is gone:
      // a pair of line breaks is not a wrapper the applier can toggle, so
      // it inserts exactly what it spells.
      final controller = controllerWith('body');

      final text = await ShortcutApplier.resolve(
        controller: controller,
        shortcut: shortcut(
          insertType: 'wrap',
          beforeText: '\n',
          afterText: '\n',
        ),
        mutateCounter: noCounter,
      );

      expect(text, '\n\n');
    });

    test('returns null for every rewrite', () async {
      final controller = controllerWith('# heading');

      for (final rewrite in [
        shortcut(insertType: 'header'),
        shortcut(insertType: 'wrap', beforeText: '**', afterText: '**'),
        shortcut(
          insertType: CustomMarkdownShortcut.linePrefixType,
          beforeText: '- ',
        ),
      ]) {
        final text = await ShortcutApplier.resolve(
          controller: controller,
          shortcut: rewrite,
          mutateCounter: noCounter,
        );
        expect(text, isNull, reason: rewrite.insertType);
      }
      expect(controller.text, '# heading');
    });
  });

  group('rewrites', () {
    test('a stored default list shortcut toggles though it says wrap', () {
      // Profiles saved before the line-prefix type carry the built-in list
      // and quote shortcuts as plain wraps; the id is what marks them.
      for (final id in [
        'default_checkbox',
        'default_checked_checkbox',
        'default_bullet_list',
        'default_point_list',
        'default_numbered_list',
        'default_quote',
      ]) {
        expect(
          ShortcutApplier.rewrites(
            shortcut(insertType: 'wrap', id: id, beforeText: '- '),
          ),
          isTrue,
          reason: id,
        );
      }
    });

    test('a custom prefix shortcut keeps inserting at the caret', () {
      expect(
        ShortcutApplier.rewrites(
          shortcut(insertType: 'wrap', id: 'custom-uuid', beforeText: '- '),
        ),
        isFalse,
      );
    });

    test('dates, counters and token wrappers are not plain wrappers', () {
      expect(
        ShortcutApplier.rewrites(
          shortcut(insertType: 'date', beforeText: '*', afterText: '*'),
        ),
        isFalse,
      );
      expect(
        ShortcutApplier.rewrites(
          shortcut(insertType: 'counter', beforeText: '*', afterText: '*'),
        ),
        isFalse,
      );
      expect(
        ShortcutApplier.rewrites(
          shortcut(insertType: 'wrap', beforeText: '{c1}', afterText: '{c1}'),
        ),
        isFalse,
      );
    });

    test('apply runs a stored default list shortcut as a toggle', () async {
      final controller = controllerWith('squat');

      await ShortcutApplier.apply(
        controller: controller,
        shortcut: shortcut(
          insertType: 'wrap',
          id: 'default_bullet_list',
          beforeText: '- ',
        ),
        mutateCounter: noCounter,
      );
      expect(controller.text, '- squat');

      await ShortcutApplier.apply(
        controller: controller,
        shortcut: shortcut(
          insertType: 'wrap',
          id: 'default_bullet_list',
          beforeText: '- ',
        ),
        mutateCounter: noCounter,
      );
      expect(controller.text, 'squat');
    });

    // U2 T15: the fence predicate reaches the rewrite through apply.
    test('forwards isFenceLine: a fenced line takes no heading or marker', () async {
      for (final s in [
        shortcut(insertType: 'header', id: 'header_level_2', beforeText: '## '),
        shortcut(
          insertType: 'wrap',
          id: 'default_bullet_list',
          beforeText: '- ',
        ),
      ]) {
        final controller = controllerWith('```\ncode\n```', line: 1);
        await ShortcutApplier.apply(
          controller: controller,
          shortcut: s,
          mutateCounter: noCounter,
          isFenceLine: (index) => index <= 2,
        );
        expect(controller.text, '```\ncode\n```', reason: s.id);
      }
    });
  });

  group('toggleWrap', () {
    test('an empty selection gets the pair with the caret between', () {
      final controller = controllerWith('ab');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 1,
      );

      ShortcutApplier.toggleWrap(controller, '**');

      expect(controller.text, 'a****b');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 3),
      );
    });

    // Y11: unwrapping there would merge the runs into `**ab**`.
    test('a caret between two runs gets a new pair, not a merge', () {
      final controller = controllerWith('**a****b**');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 5,
      );

      ShortcutApplier.toggleWrap(controller, '**');

      expect(controller.text, '**a********b**');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 7),
      );
    });

    test('an empty pair after a run still comes off', () {
      final controller = controllerWith('**a** ****');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 8,
      );

      ShortcutApplier.toggleWrap(controller, '**');

      expect(controller.text, '**a** ');
    });

    test('a second tap on the empty pair removes it', () {
      final controller = controllerWith('ab');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 1,
      );

      ShortcutApplier.toggleWrap(controller, '**');
      ShortcutApplier.toggleWrap(controller, '**');

      expect(controller.text, 'ab');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 1),
      );
    });

    test('wrapping keeps the inner text selected', () {
      final controller = controllerWith('do squat now');
      controller.selection = range(0, 3, 8);

      ShortcutApplier.toggleWrap(controller, '**');

      expect(controller.text, 'do **squat** now');
      expect(controller.selection, range(0, 5, 10));
      expect(controller.selectedText, 'squat');
    });

    test('markers right outside the selection are removed', () {
      final controller = controllerWith('do **squat** now');
      controller.selection = range(0, 5, 10);

      ShortcutApplier.toggleWrap(controller, '**');

      expect(controller.text, 'do squat now');
      expect(controller.selectedText, 'squat');
    });

    test('underscores inside a word are not a wrap around the selection', () {
      final controller = controllerWith('snake_case_more');
      controller.selection = range(0, 6, 10);

      ShortcutApplier.toggleWrap(controller, '_');

      expect(controller.text, 'snake__case__more');
      expect(controller.selectedText, 'case');
    });

    test('underscores inside Romanian quotes are a wrap', () {
      final controller = controllerWith('„_x_“');
      controller.selection = range(0, 2, 3);

      ShortcutApplier.toggleWrap(controller, '_');

      expect(controller.text, '„x“');
      expect(controller.selectedText, 'x');
    });

    test('a surrogate-pair letter keeps the underscores literal', () {
      // The tokenizer reads U+1D400 whole, a letter, so `𝐀_x_` renders
      // literal; the toggle must not unwrap what never rendered.
      final controller = controllerWith('𝐀_x_');
      controller.selection = range(0, 3, 4);

      ShortcutApplier.toggleWrap(controller, '_');

      expect(controller.text, '𝐀__x__');
      expect(controller.selectedText, 'x');
    });

    test('a star between digits is not a wrap around the selection', () {
      final controller = controllerWith('2*3*4');
      controller.selection = range(0, 2, 3);

      ShortcutApplier.toggleWrap(controller, '*');

      expect(controller.text, '2**3**4');
      expect(controller.selectedText, '3');
    });

    test('one word character beyond either marker is enough to keep it', () {
      final controller = controllerWith('do _squat_now');
      controller.selection = range(0, 4, 9);

      ShortcutApplier.toggleWrap(controller, '_');

      expect(controller.text, 'do __squat__now');
    });

    test('a one-character marker at the line edges still unwraps', () {
      final controller = controllerWith('_squat_');
      controller.selection = range(0, 1, 6);

      ShortcutApplier.toggleWrap(controller, '_');

      expect(controller.text, 'squat');
      expect(controller.selectedText, 'squat');
    });

    test('a two-character marker keeps unwrapping inside a word', () {
      final controller = controllerWith('re**set**up');
      controller.selection = range(0, 4, 7);

      ShortcutApplier.toggleWrap(controller, '**');

      expect(controller.text, 'resetup');
      expect(controller.selectedText, 'set');
    });

    test('a selection that includes the markers is unwrapped', () {
      final controller = controllerWith('do _squat_ now');
      controller.selection = range(0, 3, 10);

      ShortcutApplier.toggleWrap(controller, '_');

      expect(controller.text, 'do squat now');
      expect(controller.selection, range(0, 3, 8));
    });

    test('a multi-line selection wraps and unwraps across its lines', () {
      final controller = controllerWith('one\ntwo');
      controller.selection = range(0, 0, 3, toLine: 1);

      ShortcutApplier.toggleWrap(controller, '==');
      expect(controller.text, '==one\ntwo==');
      expect(controller.selectedText, 'one\ntwo');

      ShortcutApplier.toggleWrap(controller, '==');
      expect(controller.text, 'one\ntwo');
      expect(controller.selectedText, 'one\ntwo');
    });

    test('one undo reverts the toggle and its selection', () {
      final controller = controllerWith('do squat now');
      controller.selection = range(0, 3, 8);

      ShortcutApplier.toggleWrap(controller, '~~');
      controller.undo();

      expect(controller.text, 'do squat now');
    });
  });

  group('toggleLinePrefix', () {
    String toggle(String text, String prefix, {CodeLineSelection? at}) {
      final controller = controllerWith(text);
      if (at != null) controller.selection = at;
      ShortcutApplier.toggleLinePrefix(controller, prefix);
      return controller.text;
    }

    test('a mid-line caret marks the line start, not the caret', () {
      final controller = controllerWith('squat 5x5');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 5,
      );

      ShortcutApplier.toggleLinePrefix(controller, '- [ ] ');

      expect(controller.text, '- [ ] squat 5x5');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 11),
        reason: 'the caret keeps its place in the text',
      );
    });

    test('an empty line gets the marker with the caret after it', () {
      final controller = controllerWith('');

      ShortcutApplier.toggleLinePrefix(controller, '- ');

      expect(controller.text, '- ');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 2),
      );
    });

    test('a second tap removes the marker instead of stacking one', () {
      expect(toggle('- squat', '- '), 'squat');
      expect(toggle('- [ ] squat', '- [ ] '), 'squat');
      expect(toggle('- [x] squat', '- [x] '), 'squat');
      expect(toggle('3. squat', '1. '), 'squat');
      expect(toggle('> squat', '> '), 'squat');
    });

    test('the marker goes after the indentation', () {
      expect(toggle('  squat', '- '), '  - squat');
      expect(toggle('  - squat', '- '), '  squat');
    });

    // Y4: a list marker on a quote line toggles inside the quote.
    test('a list marker goes inside a quote, after its bars', () {
      expect(toggle('> squat', '- '), '> - squat');
      expect(toggle('> - squat', '- '), '> squat');
      expect(toggle('> > squat', '- [ ] '), '> > - [ ] squat');
      expect(toggle('> - squat', '1. '), '> 1. squat');
      expect(toggle('>   squat', '- '), '>   - squat');
    });

    test('numbered continues an ordered item inside the quote above', () {
      expect(
        toggle('> 2. bench\n> squat', '1. ', at: range(1, 0, 0)),
        '> 2. bench\n> 3. squat',
      );
    });

    test('the quote marker itself still toggles at the line start', () {
      expect(toggle('- squat', '> '), '> - squat');
      expect(toggle('> - squat', '> '), '- squat');
    });

    // Y12: blank lines do not restart the count.
    test('a blank line inside a selection keeps the numbering going', () {
      expect(
        toggle(
          'bench\n\nsquat\ndeadlift',
          '1. ',
          at: range(0, 0, 3, toLine: 3),
        ),
        '1. bench\n\n2. squat\n3. deadlift',
      );
    });

    test('fence lines are left alone', () {
      final controller = controllerWith('```\ncode\n```\nsquat');
      controller.selection = range(0, 0, 5, toLine: 3);

      ShortcutApplier.toggleLinePrefix(
        controller,
        '- ',
        isFenceLine: (index) => index <= 2,
      );

      expect(controller.text, '```\ncode\n```\n- squat');
    });

    test('a fence line alone takes no marker', () {
      final controller = controllerWith('```\ncode\n```', line: 1);

      ShortcutApplier.toggleLinePrefix(
        controller,
        '- ',
        isFenceLine: (index) => index <= 2,
      );

      expect(controller.text, '```\ncode\n```');
    });

    // B1 fix pass C1: `- ---` is itself a rule, so a marker on a rule
    // line would stack on every tap and never come off.
    test('a rule line takes no list marker', () {
      expect(toggle('---', '- '), '---');
      expect(toggle('- - -', '- '), '- - -');
      expect(toggle('* * *', '* '), '* * *');
      expect(toggle('> ---', '- '), '> ---');
      expect(toggle('---', '> '), '> ---', reason: 'a quote marker is no list');
    });

    test('a rule inside a selection lets the other lines toggle', () {
      final on = toggle('a\n---\nb', '- ', at: range(0, 0, 1, toLine: 2));
      expect(on, '- a\n---\n- b');
      expect(toggle(on, '- ', at: range(0, 0, 3, toLine: 2)), 'a\n---\nb');
      expect(
        toggle('- a\n- - -\n- b', '- ', at: range(0, 0, 3, toLine: 2)),
        'a\n- - -\nb',
      );
    });

    test('another list kind swaps its marker', () {
      expect(toggle('- squat', '- [ ] '), '- [ ] squat');
      expect(toggle('- [ ] squat', '1. '), '1. squat');
      expect(toggle('2) squat', '- '), '- squat');
      expect(toggle('• squat', '- '), '- squat');
      expect(toggle('- [x] squat', '- [ ] '), '- [ ] squat');
    });

    test('a custom task state swaps to either box, never loses its task', () {
      expect(toggle('- [-] skipped', '- [ ] '), '- [ ] skipped');
      expect(toggle('- [/] half', '- [ ] '), '- [ ] half');
      expect(toggle('- [-] skipped', '- [x] '), '- [x] skipped');
      expect(
        toggle('- [ ] a\n- [-] b', '- [ ] ', at: range(0, 0, 3, toLine: 1)),
        '- [ ] a\n- [ ] b',
        reason: 'a mixed selection is not all on, so nothing is stripped',
      );
    });

    test('numbered continues an ordered item directly above', () {
      final controller = controllerWith('4. bench\nsquat', line: 1);

      ShortcutApplier.toggleLinePrefix(controller, '1. ');

      expect(controller.text, '4. bench\n5. squat');
    });

    test('numbered restarts at the prefix under anything else', () {
      expect(
        toggle('bench\nsquat', '1. ', at: range(1, 0, 0)),
        'bench\n1. squat',
      );
      expect(
        toggle('  4. bench\nsquat', '1. ', at: range(1, 0, 0)),
        '  4. bench\n1. squat',
        reason: 'the item above sits at another indent',
      );
    });

    test('a multi-line selection numbers its lines in order', () {
      expect(
        toggle('bench\nsquat\ndeadlift', '1. ', at: range(0, 0, 3, toLine: 2)),
        '1. bench\n2. squat\n3. deadlift',
      );
    });

    test('a multi-line selection removes only when every line has it', () {
      expect(
        toggle('- bench\n- squat', '- ', at: range(0, 0, 3, toLine: 1)),
        'bench\nsquat',
      );
      expect(
        toggle('- bench\nsquat', '- ', at: range(0, 0, 3, toLine: 1)),
        '- bench\n- squat',
      );
    });

    test('blank lines inside a multi-line selection are left alone', () {
      expect(
        toggle('bench\n\nsquat', '> ', at: range(0, 0, 3, toLine: 2)),
        '> bench\n\n> squat',
      );
    });

    test('a selection ending at column 0 leaves that line out', () {
      expect(
        toggle('bench\nsquat\nrest', '- ', at: range(0, 0, 0, toLine: 2)),
        '- bench\n- squat\nrest',
      );
    });

    test('a nested quote comes off as a whole run', () {
      expect(toggle('> > squat', '> '), 'squat');
    });

    test('the selection moves with each line', () {
      final controller = controllerWith('bench\nsquat');
      controller.selection = range(0, 1, 3, toLine: 1);

      ShortcutApplier.toggleLinePrefix(controller, '- [ ] ');

      expect(controller.text, '- [ ] bench\n- [ ] squat');
      expect(controller.selection, range(0, 7, 9, toLine: 1));
    });

    test('a literal prefix toggles by its text', () {
      expect(toggle('12.50 coffee', r'$- '), r'$- 12.50 coffee');
      expect(toggle(r'$- 12.50 coffee', r'$- '), '12.50 coffee');
    });

    test('one undo reverts the whole toggle', () {
      final controller = controllerWith('bench\nsquat');
      controller.selection = range(0, 0, 5, toLine: 1);

      ShortcutApplier.toggleLinePrefix(controller, '- ');
      expect(controller.text, '- bench\n- squat');
      controller.undo();

      expect(controller.text, 'bench\nsquat');
    });
  });

  group('applyHeader', () {
    void expectCycle(String from, String to) {
      final controller = controllerWith(from);
      ShortcutApplier.applyHeader(controller);
      expect(controller.text, to, reason: '"$from" should cycle to "$to"');
    }

    test('plain text gains a level-1 heading', () {
      expectCycle('squat 5x5', '# squat 5x5');
    });

    test('each level adds one hash', () {
      expectCycle('# squat', '## squat');
      expectCycle('##### squat', '###### squat');
    });

    test('level six drops back to the bare content', () {
      expectCycle('###### squat', 'squat');
    });

    test('dropping past level six drops the closing run too', () {
      expectCycle('###### Week 3 ##', 'Week 3');
      expectCycle('  ###### Week 3 #  ', '  Week 3');
      expectCycle('## Week 3 ##', '### Week 3 ##');
    });

    test('a bare hash run is an empty heading, so it cycles up', () {
      // `###` with no trailing space is a level-3 heading with empty
      // content per `MarkdownLineShape.headingAt` — the same call both
      // rendering surfaces make — so the toolbar takes it to `#### `.
      expectCycle('###', '#### ');
    });

    test('seven hashes are prose, not a heading', () {
      expectCycle('####### squat', '# ####### squat');
    });

    test('an indented heading keeps its indent', () {
      // `headingAt` allows leading whitespace; the rewrite must not
      // swallow it, or the line shifts left on every cycle.
      expectCycle('  ## squat', '  ### squat');
      expectCycle('  ###### squat', '  squat');
    });

    test('a hashtag is prose, not a heading', () {
      expectCycle('#squat', '# #squat');
    });

    // Y12: at column 0 the run would read `#   squat`.
    test('an indented plain line gains its run after the indent', () {
      expectCycle('  squat', '  # squat');
      final controller = controllerWith('  squat');
      ShortcutApplier.applyHeaderLevel(controller, 2);
      expect(controller.text, '  ## squat');
      ShortcutApplier.applyHeaderLevel(controller, 2);
      expect(controller.text, '  squat', reason: 'the same level removes it');
    });

    test('the caret line is the one rewritten', () {
      final controller = controllerWith('first\n# second\nthird', line: 1);
      ShortcutApplier.applyHeader(controller);
      expect(controller.text, 'first\n## second\nthird');
    });

    test('the caret keeps its column in the text', () {
      final controller = controllerWith('# squat');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 4,
      );
      ShortcutApplier.applyHeader(controller);
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 5),
      );
    });
  });

  group('a setext heading', () {
    test('a picked level converts it to ATX and drops the underline', () {
      final controller = controllerWith('Week 3\n===\nafter');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 2,
      );
      ShortcutApplier.applyHeaderLevel(controller, 3);
      expect(controller.text, '### Week 3\nafter');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 6),
      );
    });

    test('its own level removes the heading and keeps the text', () {
      final h1 = controllerWith('Week 3\n===\nafter');
      ShortcutApplier.applyHeaderLevel(h1, 1);
      expect(h1.text, 'Week 3\nafter');
      final h2 = controllerWith('Week 3\n---');
      ShortcutApplier.applyHeaderLevel(h2, 2);
      expect(h2.text, 'Week 3');
    });

    test('the cycling button steps on from its level', () {
      final controller = controllerWith('Week 3\n---\nafter');
      ShortcutApplier.applyHeader(controller);
      expect(controller.text, '### Week 3\nafter');
    });

    test('a selection past the underline moves up with the lines', () {
      final controller = controllerWith('Week 3\n===\nafter');
      controller.selection = range(0, 0, 3, toLine: 2);
      ShortcutApplier.applyHeaderLevel(controller, 2);
      expect(controller.text, '## Week 3\nafter');
      expect(controller.selection, range(0, 3, 3, toLine: 1));
    });

    test('one undo restores both lines', () {
      final controller = controllerWith('Week 3\n===\nafter');
      ShortcutApplier.applyHeaderLevel(controller, 2);
      expect(controller.text, '## Week 3\nafter');
      controller.undo();
      expect(controller.text, 'Week 3\n===\nafter');
    });

    test('a list line above a rule is no setext heading', () {
      final controller = controllerWith('- item\n---');
      ShortcutApplier.applyHeaderLevel(controller, 2);
      expect(controller.text, '## - item\n---');
    });

    test('a caret on the underline acts on the heading above it', () {
      final controller = controllerWith('Title\n===\nafter');
      controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 3,
      );
      ShortcutApplier.applyHeaderLevel(controller, 2);
      expect(controller.text, '## Title\nafter');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 8),
      );
      final own = controllerWith('Title\n===');
      own.selection = const CodeLineSelection.collapsed(index: 1, offset: 3);
      ShortcutApplier.applyHeaderLevel(own, 1);
      expect(own.text, 'Title');
    });

    test('a selection ending on the underline ends at the heading text', () {
      final controller = controllerWith('Week 3\n===\nafter');
      controller.selection = range(0, 0, 2, toLine: 1);
      ShortcutApplier.applyHeaderLevel(controller, 2);
      expect(controller.text, '## Week 3\nafter');
      expect(controller.selection, range(0, 3, 9));
    });

    test('removing its own level keeps the caret in the text', () {
      final controller = controllerWith('Week 3\n===\nafter');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 4,
      );
      ShortcutApplier.applyHeaderLevel(controller, 1);
      expect(controller.text, 'Week 3\nafter');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 4),
      );
    });

    test('removal is refused when another underline would slide up', () {
      final controller = controllerWith('Title\n---\n---');
      ShortcutApplier.applyHeaderLevel(controller, 2);
      expect(controller.text, 'Title\n---\n---');
      ShortcutApplier.applyHeaderLevel(controller, 1);
      expect(controller.text, '# Title\n---');
    });

    test('a front matter property above its closer is no heading', () {
      const note = '---\ntitle: x\ntags: a\n---\n# H1';
      final controller = controllerWith(note);
      controller.selection = const CodeLineSelection.collapsed(
        index: 2,
        offset: 0,
      );
      ShortcutApplier.applyHeaderLevel(controller, 1);
      expect(controller.text, '---\ntitle: x\n# tags: a\n---\n# H1');
      final onCloser = controllerWith(note);
      onCloser.selection = const CodeLineSelection.collapsed(
        index: 3,
        offset: 3,
      );
      ShortcutApplier.applyHeaderLevel(onCloser, 2);
      expect(onCloser.text, '---\ntitle: x\ntags: a\n## ---\n# H1');
      // A later `---` is an underline again: the closer came first.
      final after = controllerWith('$note\nWeek 3\n---');
      after.selection = const CodeLineSelection.collapsed(index: 5, offset: 0);
      ShortcutApplier.applyHeaderLevel(after, 1);
      expect(after.text, '$note\n# Week 3');
    });

    test('a pair on fence lines is left to the fence', () {
      final controller = controllerWith('Title\n===\nafter');
      controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 0,
      );
      ShortcutApplier.applyHeaderLevel(
        controller,
        2,
        isFenceLine: (line) => line == 0,
      );
      expect(controller.text, 'Title\n## ===\nafter');
    });
  });

  group('applyHeaderLevel', () {
    String pick(String from, int level) {
      final controller = controllerWith(from);
      ShortcutApplier.applyHeaderLevel(controller, level);
      return controller.text;
    }

    test('plain text gets exactly the level picked', () {
      expect(pick('squat', 3), '### squat');
    });

    test('another level is replaced, not cycled', () {
      expect(pick('# squat', 3), '### squat');
      expect(pick('###### squat', 2), '## squat');
      expect(pick('  ## squat', 5), '  ##### squat');
    });

    test('the same level again removes the heading', () {
      expect(pick('### squat', 3), 'squat');
      expect(pick('###', 3), '');
    });

    test('removing a closed heading keeps only its content', () {
      expect(pick('## Week 3 ##', 2), 'Week 3');
      expect(pick('## ##', 2), '');
      expect(pick('## Week 3 ##', 4), '#### Week 3 ##');
    });

    test('removing a closed heading maps the caret into the content', () {
      CodeLineSelection after(int offset) {
        final controller = controllerWith('## Week 3 ##');
        controller.selection = CodeLineSelection.collapsed(
          index: 0,
          offset: offset,
        );
        ShortcutApplier.applyHeaderLevel(controller, 2);
        expect(controller.text, 'Week 3');
        return controller.selection;
      }

      expect(after(5), const CodeLineSelection.collapsed(index: 0, offset: 2));
      expect(after(9), const CodeLineSelection.collapsed(index: 0, offset: 6));
      expect(after(12), const CodeLineSelection.collapsed(index: 0, offset: 6));
    });

    test('the caret keeps its column in the text', () {
      final controller = controllerWith('squat');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 2,
      );
      ShortcutApplier.applyHeaderLevel(controller, 2);
      expect(controller.text, '## squat');
      expect(
        controller.selection,
        const CodeLineSelection.collapsed(index: 0, offset: 5),
      );
    });

    test('applyRewrite routes the menu by level and the bar button by id', () {
      final menu = controllerWith('squat');
      ShortcutApplier.applyRewrite(
        menu,
        shortcut(
          insertType: 'header',
          id: 'header_level_3',
          beforeText: '### ',
        ),
      );
      expect(menu.text, '### squat');

      // The bar's own button also carries `# `, but it keeps cycling.
      final button = controllerWith('# squat');
      ShortcutApplier.applyRewrite(
        button,
        shortcut(insertType: 'header', id: 'default_header', beforeText: '# '),
      );
      expect(button.text, '## squat');
    });

    test('a selection into the cut tail clamps to the content', () {
      CodeLineSelection after(CodeLineSelection selection) {
        final controller = controllerWith('## Week 3 ##');
        controller.selection = selection;
        ShortcutApplier.applyHeaderLevel(controller, 2);
        expect(controller.text, 'Week 3');
        return controller.selection;
      }

      expect(after(range(0, 3, 12)), range(0, 0, 6));
      expect(after(range(0, 4, 11)), range(0, 1, 6));
    });

    test('one undo restores a dropped closed heading', () {
      final controller = controllerWith('## Week 3 ##');
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 5,
      );

      ShortcutApplier.applyHeaderLevel(controller, 2);
      controller.undo();

      expect(controller.text, '## Week 3 ##');
    });

    test('the menu drops a closed heading through applyRewrite', () {
      final controller = controllerWith('## Week 3 ##');
      ShortcutApplier.applyRewrite(
        controller,
        shortcut(insertType: 'header', id: 'header_level_2', beforeText: '## '),
      );
      expect(controller.text, 'Week 3');
    });

    test('a tail that reads as a closing run goes with the heading', () {
      // `## Week ##` is a closed heading, so the second pick drops the
      // ` ##` the plain line carried as text; one undo brings it back.
      expect(pick(pick('Week ##', 2), 2), 'Week');
    });

    test('a heading shortcut leaves a fence line alone', () {
      for (final id in const <String>['header_level_2', 'default_header']) {
        final controller = controllerWith('```\n## build ##\n```', line: 1);
        ShortcutApplier.applyRewrite(
          controller,
          shortcut(insertType: 'header', id: id, beforeText: '## '),
          isFenceLine: (index) => index <= 2,
        );
        expect(controller.text, '```\n## build ##\n```', reason: id);
      }
    });
  });

  // S2 C5 / U1 C15 — handed the editor's positional reader, the setext
  // branch acts only on the pairs the editor draws as headings.
  group('the editor\'s heading reader', () {
    (CodeLineEditingController, EditorRenderController) bound(
      String text,
      int line,
    ) {
      final controller = controllerWith(text, line: line);
      final render = EditorRenderController()..bind(controller);
      return (controller, render);
    }

    test('answers ATX, setext text and underline, and nothing in a block', () {
      final (controller, render) = bound(
        '# a\nTitle\n===\n```\n# x\n```\n---\nk: v',
        0,
      );
      expect(
        [
          for (int i = 0; i < controller.codeLines.length; i++)
            render.headingLevelAt(i),
        ],
        [1, 1, -1, 0, 0, 0, 0, 0],
      );
    });

    test('a pair past the render cap is no heading to the rewrite', () {
      final long = 'a' * 5000;
      final (controller, render) = bound('$long\n===\nafter', 1);
      expect(render.headingLevelAt(0), 0);
      expect(render.headingLevelAt(1), 0);

      ShortcutApplier.applyHeaderLevel(
        controller,
        2,
        isFenceLine: render.lineInFence,
        headingLevelAt: render.headingLevelAt,
      );

      expect(controller.codeLines[0].text, long);
      expect(controller.codeLines[1].text, '## ===');
    });

    // C1 fix pass C5 / P6 / T9 — the menu checks nothing on an ATX line
    // drawn raw, so a pick sets that level and never strips the run.
    test('an ATX line past the render cap is set, never toggled off', () {
      final long = '# ${'a' * 5000}';
      for (final (level, expected) in [(1, long), (2, '#$long')]) {
        final (controller, render) = bound('$long\nafter', 0);
        expect(render.headingLevelAt(0), 0);

        ShortcutApplier.applyHeaderLevel(
          controller,
          level,
          isFenceLine: render.lineInFence,
          headingLevelAt: render.headingLevelAt,
        );

        expect(controller.codeLines[0].text, expected, reason: 'H$level');
      }
    });

    test('a drawn setext pair still toggles off through the reader', () {
      final (controller, render) = bound('Title\n===\nafter', 1);

      ShortcutApplier.applyHeaderLevel(
        controller,
        1,
        isFenceLine: render.lineInFence,
        headingLevelAt: render.headingLevelAt,
      );

      expect(controller.text, 'Title\nafter');
    });

    // C1 fix pass C4 / P5 / T3 — the event sheets pass no positional
    // reader; the text reader now reads the chunker's front matter, so a
    // candidate it rejects converts as the pair the editor draws.
    test('the text reader agrees with the editor on a rejected block', () {
      const text = '---\nTitle\n---\nafter';
      final (_, render) = bound(text, 1);
      expect(render.headingLevelAt(1), 2);
      final controller = controllerWith(text, line: 1);

      ShortcutApplier.applyHeaderLevel(controller, 1);

      expect(controller.text, '---\n# Title\nafter');
    });

    test('a front matter closer underlines nothing', () {
      final (controller, render) = bound('---\ntags: a\n---\n# H', 2);
      expect(render.headingLevelAt(2), 0);
      expect(render.lineInFence(1), isTrue);
      expect(controller.codeLines.length, 4);
    });
  });
}
