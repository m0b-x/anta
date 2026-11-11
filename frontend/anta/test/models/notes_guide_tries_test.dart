import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/config/default_markdown_shortcuts.dart';
import 'package:anta/controllers/editor_render_controller.dart';
import 'package:anta/controllers/shortcut_applier.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/l10n/app_localizations_ro.dart';
import 'package:anta/models/calendar_guide_coach.dart';
import 'package:anta/models/calendar_guide_content.dart';
import 'package:anta/models/guide_content.dart';
import 'package:anta/models/notes_guide_content.dart';
import 'package:anta/models/notes_guide_tries.dart';
import 'package:anta/models/utility_button_config.dart';
import 'package:anta/utils/ghost_text.dart';
import 'package:anta/utils/icon_utils.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/markdown_line_shape.dart';
import 'package:anta/utils/markdown_list_syntax.dart';
import 'package:anta/utils/markdown_money_syntax.dart';

/// The notes cards' checks (`docs/guide-hub-roadmap.md` §9.2, §10.3, D18),
/// each over hand-written documents, the seeds that satisfy none of them,
/// and the bars' buttons.
void main() {
  GuideEditorDocument doc(
    String text, {
    String? previous,
    Set<String> done = const {},
  }) => GuideEditorDocument(
    lines: text.split('\n'),
    previousLines: previous?.split('\n') ?? const [],
    hasDone: done.contains,
    palette: MarkdownColorPalette.presets,
  );

  /// [text] as the stage hands it to the checks: blanked where the editor's
  /// own render controller draws a fence, a `%%` comment or front matter.
  GuideEditorDocument drawn(String text) {
    final controller = CodeLineEditingController.fromText(text);
    addTearDown(controller.dispose);
    final render = EditorRenderController()..bind(controller);
    return GuideEditorDocument(
      lines: GuideEditorDocument.blankBlocks(
        text.split('\n'),
        render.lineInFence,
      ),
      hasDone: const <String>{}.contains,
      palette: MarkdownColorPalette.presets,
    );
  }

  group('the document', () {
    test('a fence, a comment or front matter hides a mark from every '
        'check', () {
      const fence = '```';
      for (final (text, check)
          in <(String, bool Function(GuideEditorDocument))>[
            ('$fence\n# Leg day\n$fence', notesGuideHasHeading),
            ('$fence\nDeadlift #pr\n$fence', notesGuideHasTag),
            ('$fence\n\$- 5 gym\n\$- 5 shoes\n$fence', notesGuideHasSpends),
            ('%%\nDeadlift #pr\n%%', notesGuideHasTag),
            ('---\ntags: #pr\n---\nSquat', notesGuideHasTag),
            ('$fence\n- [x] Stretch\n$fence', notesGuideHasTickedTask),
          ]) {
        expect(check(drawn(text)), isFalse, reason: text);
      }
      // The same marks out of the block count.
      expect(
        notesGuideHasHeading(drawn('$fence\nx\n$fence\n# Leg day')),
        isTrue,
      );
      expect(
        notesGuideHasTag(drawn('$fence\nx\n$fence\nDeadlift #pr')),
        isTrue,
      );
      expect(
        notesGuideHasSpends(drawn('\$- 5 gym\n$fence\nx\n$fence\n\$- 5 shoes')),
        isTrue,
      );
    });

    test('a line is tokenized once, however many checks read it', () {
      final document = doc('**heavy #pr** {red:x} [[Leg day]]\nSquat');
      expect(identical(document.inlineTokens, document.inlineTokens), isTrue);
      expect(document.inlineTokens, hasLength(2));
      expect(document.inlineTokens[1], isEmpty);
      expect(notesGuideHasBold(document), isTrue);
      expect(notesGuideHasTag(document), isTrue);
      expect(notesGuideHasColour(document), isTrue);
      expect(notesGuideHasWikiLink(document), isTrue);
    });
  });

  group('the markdown card', () {
    test('a heading: an ATX heading on any line, never a tag', () {
      expect(notesGuideHasHeading(doc('# Leg day\nSquat')), isTrue);
      expect(notesGuideHasHeading(doc('Squat\n### Felt strong')), isTrue);
      expect(notesGuideHasHeading(doc('#Leg day')), isFalse);
      expect(notesGuideHasHeading(doc('Leg day #gym')), isFalse);
      expect(notesGuideHasHeading(doc('Leg day\nSquat')), isFalse);
    });

    test('bold: a bold or bold-italic run at any depth', () {
      expect(notesGuideHasBold(doc('Felt **strong** today')), isTrue);
      expect(notesGuideHasBold(doc('Felt ***strong*** today')), isTrue);
      expect(notesGuideHasBold(doc('- **Squat** 5×5')), isTrue);
      expect(notesGuideHasBold(doc('[**strong**](https://a.b)')), isTrue);
      expect(notesGuideHasBold(doc('*so **very** strong*')), isTrue);
      expect(notesGuideHasBold(doc('Felt *strong* today')), isFalse);
      expect(notesGuideHasBold(doc('Felt **strong today')), isFalse);
      expect(notesGuideHasBold(doc('`**strong**`')), isFalse);
      expect(notesGuideHasBold(doc('Squat 5×5')), isFalse);
    });

    test('a bullet: a bullet item, not a task, a number or a rule', () {
      expect(notesGuideHasBullet(doc('Leg day\n- Squat 5×5')), isTrue);
      expect(notesGuideHasBullet(doc('* Squat')), isTrue);
      expect(notesGuideHasBullet(doc('- [ ] Squat')), isFalse);
      expect(notesGuideHasBullet(doc('1. Squat')), isFalse);
      expect(notesGuideHasBullet(doc('- - -')), isFalse);
      expect(notesGuideHasBullet(doc('-Squat')), isFalse);
    });

    test('a task: a ticked box only', () {
      expect(notesGuideHasTickedTask(doc('- [x] Stretch')), isTrue);
      expect(notesGuideHasTickedTask(doc('Leg day\n- [X] Stretch')), isTrue);
      expect(notesGuideHasTickedTask(doc('- [ ] Stretch')), isFalse);
      expect(notesGuideHasTickedTask(doc('- Stretch [x]')), isFalse);
    });

    test('its steps run in the order the coach asks for them', () {
      expect(notesGuideMarkdownTry.spec.slug, 'markdown');
      expect(notesGuideMarkdownTry.steps.map((step) => step.action), [
        'heading',
        'bold',
        'list',
        'task',
      ]);
      expect(
        notesGuideMarkdownTry.steps,
        hasLength(notesGuideMarkdownTry.spec.steps.length),
      );
    });
  });

  group('the lists card', () {
    test('Enter: more items than the seed\'s four', () {
      expect(notesGuideHasMoreItems(doc('- a\n- b\n- c\n- d\n- ')), isTrue);
      expect(notesGuideHasMoreItems(doc('- a\n- b\n- c\n- d\n1. e')), isTrue);
      expect(notesGuideHasMoreItems(doc('- a\n- b\n- c\n- d')), isFalse);
      expect(notesGuideHasMoreItems(doc('- a\n- b\n- c\n- d\ne')), isFalse);
      expect(notesGuideHasMoreItems(doc('- a\n- b\n- c\n- d\n-e')), isFalse);
    });

    test('nest: an item a level or more in', () {
      expect(notesGuideHasNestedItem(doc('- a\n  - b')), isTrue);
      expect(notesGuideHasNestedItem(doc('- a\n\t- b')), isTrue);
      expect(notesGuideHasNestedItem(doc('- a\n    1. b')), isTrue);
      expect(notesGuideHasNestedItem(doc('- a\n - b')), isFalse);
      expect(notesGuideHasNestedItem(doc('- a\n  b')), isFalse);
      expect(notesGuideHasNestedItem(doc('- a\n- b')), isFalse);
    });

    test('outdent: the change that took the last nested item out', () {
      expect(
        notesGuideHasOutdented(doc('- a\n- b', previous: '- a\n  - b')),
        isTrue,
      );
      // An indented line that is not an item is no nested item.
      expect(
        notesGuideHasOutdented(doc('- a\n  b', previous: '- a\n  - b')),
        isTrue,
      );
      // A flat list after a skipped nest is no outdent she made, whatever
      // the coach's done set says.
      expect(
        notesGuideHasOutdented(
          doc('- a\n- bx', previous: '- a\n- b', done: {'nest'}),
        ),
        isFalse,
      );
      expect(notesGuideHasOutdented(doc('- a\n- b')), isFalse);
      expect(notesGuideHasOutdented(doc('a\nb', previous: 'a\nb')), isFalse);
      expect(
        notesGuideHasOutdented(doc('- a\n  - b', previous: '- a\n  - b')),
        isFalse,
      );
      expect(
        notesGuideHasOutdented(
          doc('- a\n  - b\n- c', previous: '- a\n  - b\n  - c'),
        ),
        isFalse,
      );
    });

    test('end: a blank line directly under an item, not over one', () {
      expect(notesGuideHasEndedList(doc('- a\n')), isTrue);
      expect(notesGuideHasEndedList(doc('- a\n  \nb')), isTrue);
      expect(notesGuideHasEndedList(doc('- a\n- b')), isFalse);
      expect(notesGuideHasEndedList(doc('a\n')), isFalse);
      expect(notesGuideHasEndedList(doc('\n- a')), isFalse);
      expect(notesGuideHasEndedList(doc('- a\nb\n')), isFalse);
      // Enter at column 0 of an item opens a line above it: no list ended.
      expect(
        notesGuideHasEndedList(doc('- Legs\n\n- Squat\n- Lunges\n- Back')),
        isFalse,
      );
    });

    for (final l10n in [
      AppLocalizationsEn(),
      AppLocalizationsDe(),
      AppLocalizationsRo(),
    ]) {
      test('${l10n.localeName}: the seed holds the items Enter is counted '
          'against', () {
        expect(
          notesGuideListsTry
              .seed(l10n)
              .split('\n')
              .where(MarkdownListSyntax.isListLine),
          hasLength(notesGuideListsSeedItems),
        );
      });
    }

    test('its steps run in the order the coach asks for them', () {
      expect(notesGuideListsTry.spec.slug, 'lists');
      expect(notesGuideListsTry.steps.map((step) => step.action), [
        'enter',
        'nest',
        'outdent',
        'end',
      ]);
    });
  });

  group('the own card', () {
    test('a tag, at any depth, never in code or a heading\'s hash', () {
      expect(notesGuideHasTag(doc('Deadlift 140 kg #pr')), isTrue);
      expect(notesGuideHasTag(doc('**heavy #pr**')), isTrue);
      expect(notesGuideHasTag(doc('`#pr`')), isFalse);
      expect(notesGuideHasTag(doc('# pr')), isFalse);
      expect(notesGuideHasTag(doc('Deadlift 140 kg')), isFalse);
    });

    test('a ghost: a closed run only', () {
      expect(notesGuideHasGhost(doc('squat {{weight}}')), isTrue);
      expect(notesGuideHasGhost(doc('squat {{weight}')), isFalse);
      expect(notesGuideHasGhost(doc('squat {weight}')), isFalse);
    });

    test('a colour: a resolved colour or a tinted highlight', () {
      expect(notesGuideHasColour(doc('{red:heavy}')), isTrue);
      expect(notesGuideHasColour(doc('so ==green:light== today')), isTrue);
      expect(notesGuideHasColour(doc('**{blue:x}**')), isTrue);
      expect(notesGuideHasColour(doc('{nosuch:heavy}')), isFalse);
      expect(notesGuideHasColour(doc('==plain==')), isFalse);
      expect(notesGuideHasColour(doc('heavy')), isFalse);
    });

    test('a colour button\'s empty slot is no colour until a word fills '
        'it (D31)', () {
      // What "Color Text" and "Color Highlight" leave at an empty selection.
      expect(notesGuideHasColour(doc('{red:{{  }}}')), isFalse);
      expect(notesGuideHasColour(doc('==yellow:{{  }}==')), isFalse);
      // Typed into the ghost, the text is still the ghost's: drawn dim.
      expect(notesGuideHasColour(doc('{red:{{ heavy }}}')), isFalse);
      expect(notesGuideHasColour(doc('{red:  }')), isFalse);
      // A word beside the blank is coloured.
      expect(notesGuideHasColour(doc('{red:max {{ kg }}}')), isTrue);
      expect(notesGuideHasColour(doc('==yellow:done==')), isTrue);
    });

    test('a slot wrapped in a second colour — the button pressed twice — is '
        'still only a slot', () {
      for (final slot in [
        '{red:{red:{{  }}}}',
        '{red:==yellow:{{  }}==}',
        '==yellow:{red:{{  }}}==',
      ]) {
        expect(notesGuideHasColour(doc(slot)), isFalse, reason: slot);
      }
      // A word colours the run it stands in, whatever wraps that run.
      expect(notesGuideHasColour(doc('{red:{blue:max}}')), isTrue);
      expect(notesGuideHasColour(doc('{red:max {blue:{{  }}}}')), isTrue);
      expect(notesGuideHasColour(doc('{red:{blue:{{  }}} max}')), isTrue);
    });

    test('a wiki link: double brackets only', () {
      expect(notesGuideHasWikiLink(doc('Same as [[Leg day]]')), isTrue);
      expect(notesGuideHasWikiLink(doc('[Leg day](https://a.b)')), isFalse);
      expect(notesGuideHasWikiLink(doc('[Leg day]')), isFalse);
      expect(notesGuideHasWikiLink(doc('`[[Leg day]]`')), isFalse);
    });

    test('its steps run in the order the coach asks for them', () {
      expect(notesGuideOwnTry.spec.slug, 'own');
      expect(notesGuideOwnTry.steps.map((step) => step.action), [
        'tag',
        'ghost',
        'colour',
        'wiki',
      ]);
    });
  });

  group('the money card', () {
    test('spend: two spends or more', () {
      expect(
        notesGuideHasSpends(
          doc(
            r'$- 40 gym'
            '\n'
            r'$- 25 shoes',
          ),
        ),
        isTrue,
      );
      expect(
        notesGuideHasSpends(
          doc(
            r'- $- 40 gym'
            '\n'
            r'$- 25',
          ),
        ),
        isTrue,
      );
      expect(
        notesGuideHasSpends(
          doc(
            r'$= 500'
            '\n'
            r'$- 40 gym',
          ),
        ),
        isFalse,
      );
      expect(
        notesGuideHasSpends(
          doc(
            r'$- 40 gym'
            '\n'
            r'- 25 shoes',
          ),
        ),
        isFalse,
      );
    });

    test('add: money coming in', () {
      expect(notesGuideHasIncome(doc(r'$+ 25 refund')), isTrue);
      expect(notesGuideHasIncome(doc(r'$= 500 budget')), isFalse);
      expect(notesGuideHasIncome(doc(r'+ 25 refund')), isFalse);
    });

    test('a row the ledger draws as an error is no spend and no income '
        '(D31)', () {
      // A well-formed amount past the digit limit: an error row of its
      // kind, drawn yellow and left out of the balance.
      const income = r'$+ 99999999999999999999 refund';
      const spend = r'$- 99999999999999999999 shoes';
      expect(MarkdownMoneySyntax.parse(income)?.kind, MoneyLineKind.add);
      expect(MarkdownMoneySyntax.parse(income)?.error, isNotNull);
      expect(MarkdownMoneySyntax.parse(spend)?.kind, MoneyLineKind.subtract);
      expect(MarkdownMoneySyntax.parse(spend)?.error, isNotNull);
      expect(notesGuideHasIncome(doc(income)), isFalse);
      expect(notesGuideHasSpends(doc('\$- 40 gym\n$spend')), isFalse);
      // A marker with no amount is no ledger line at all.
      expect(MarkdownMoneySyntax.parse(r'$- '), isNull);
    });

    test('total: the balance chip', () {
      expect(
        notesGuideHasTotal(
          doc(
            r'$- 40 gym'
            '\n'
            r'$$',
          ),
        ),
        isTrue,
      );
      expect(notesGuideHasTotal(doc(r'$= 500 budget')), isFalse);
      expect(notesGuideHasTotal(doc(r'$')), isFalse);
    });

    test('its steps run in the order the coach asks for them', () {
      expect(notesGuideMoneyTry.spec.slug, 'money');
      expect(notesGuideMoneyTry.steps.map((step) => step.action), [
        'spend',
        'add',
        'total',
      ]);
    });
  });

  group('the shortcuts card', () {
    final en = AppLocalizationsEn();

    test('line: a checkbox item that holds a blank', () {
      expect(
        notesGuideHasBlankTask(doc('- [ ] Set 1: {{weight}} kg × {{reps}}')),
        isTrue,
      );
      expect(notesGuideHasBlankTask(doc('- [ ] Set 1: 60 kg × 5')), isFalse);
      expect(notesGuideHasBlankTask(doc('- Set 1: {{weight}} kg')), isFalse);
      expect(notesGuideHasBlankTask(doc('Squat {{weight}} kg')), isFalse);
    });

    test('count: two checkbox items, a filled-in first one included', () {
      expect(
        notesGuideHasTwoTasks(
          doc('- [x] Set 1: 60 kg × 5\n- [ ] Set 2: {{weight}} kg'),
        ),
        isTrue,
      );
      expect(notesGuideHasTwoTasks(doc('- [ ] Set 1: {{weight}} kg')), isFalse);
      expect(notesGuideHasTwoTasks(doc('- a\n- b')), isFalse);
    });

    test('write and press read the stage, not the note', () {
      GuideEditorDocument stage({String maker = '', int presses = 0}) =>
          GuideEditorDocument(
            lines: const ['Squat 5×5'],
            hasDone: const <String>{}.contains,
            palette: MarkdownColorPalette.presets,
            makerText: maker,
            ownPresses: presses,
          );
      expect(notesGuideHasMakerText(stage()), isFalse);
      expect(notesGuideHasMakerText(stage(maker: '   ')), isFalse);
      expect(notesGuideHasMakerText(stage(maker: 'Squat 5×5')), isTrue);
      // Her text typed into the note by hand is not her button's press.
      expect(notesGuideHasOwnPress(stage(maker: 'Squat 5×5')), isFalse);
      expect(
        notesGuideHasOwnPress(stage(maker: 'Squat 5×5', presses: 1)),
        isTrue,
      );
    });

    test('its steps run in the order the coach asks for them, over a field '
        'and its own buttons', () {
      expect(notesGuideShortcutsTry.spec.slug, 'shortcuts');
      expect(notesGuideShortcutsTry.steps.map((step) => step.action), [
        'line',
        'count',
        'date',
        'write',
        'press',
      ]);
      expect(notesGuideShortcutsTry.maker, isTrue);
      expect(notesGuideShortcutsTry.bar.builtIns, isEmpty);
    });

    test('the two ready-made buttons are shortcuts the applier inserts: a '
        'counted checkbox line with two blanks, and a dated heading', () {
      for (final l10n in [en, AppLocalizationsDe(), AppLocalizationsRo()]) {
        final [set, today] = notesGuideShortcutButtons(l10n);
        final reason = l10n.localeName;
        expect(ShortcutApplier.rewrites(set), isFalse, reason: reason);
        expect(ShortcutApplier.rewrites(today), isFalse, reason: reason);
        expect(set.label, l10n.notesGuideShortcutSetLabel, reason: reason);
        expect(set.beforeText, endsWith('\n'), reason: reason);
        expect(set.beforeText, contains('{c1}'), reason: reason);
        expect(
          set.effectiveCounters.single.counterId,
          notesGuideSetCounterId,
          reason: reason,
        );
        // What one press writes, the token counted: a line the `line` step
        // reads, whatever the language of its words.
        final written = set.beforeText.replaceAll('{c1}', '1').trimRight();
        expect(notesGuideHasBlankTask(doc(written)), isTrue, reason: reason);
        expect(GhostText.findGhosts(written), hasLength(2), reason: reason);
        expect(today.insertType, 'date', reason: reason);
        expect(
          MarkdownLineShape.headingAt('${today.beforeText}11 November 2026'),
          isNotNull,
          reason: reason,
        );
        // Both draw an icon the bar can resolve, never its fallback.
        for (final shortcut in [set, today]) {
          expect(
            IconUtils.isSupported(shortcut.iconCodePoint),
            isTrue,
            reason: '$reason ${shortcut.id}',
          );
        }
      }
    });
  });

  test('every bar names built-in shortcuts that exist, and utility buttons '
      'the bar knows', () {
    final builtIns = {
      for (final shortcut in DefaultMarkdownShortcuts.shortcuts) shortcut.id,
    };
    for (final topic in NotesGuideTopic.values) {
      for (final card in topic.editorCards) {
        expect(
          builtIns.containsAll(card.bar.builtIns),
          isTrue,
          reason: '${card.spec.slug}: ${card.bar.builtIns}',
        );
        expect(
          UtilityButtonId.defaultOrder.toSet().containsAll(card.bar.utilities),
          isTrue,
          reason: card.spec.slug,
        );
        // Undo is on every bar: a sandbox she can take a step back in.
        expect(
          card.bar.utilities,
          containsAll([UtilityButtonId.undo, UtilityButtonId.redo]),
          reason: card.spec.slug,
        );
      }
    }
    // The money card's buttons are the ones the page's row names.
    expect(notesGuideMoneyTry.bar.builtIns, {
      'default_money',
      'default_money_subtract',
      'default_money_set',
      'default_money_total',
      'default_money_delta',
      'default_money_target',
    });
  });

  test('every step of every card carries a check', () {
    for (final card in [
      notesGuideMarkdownTry,
      notesGuideListsTry,
      notesGuideOwnTry,
      notesGuideMoneyTry,
      notesGuideShortcutsTry,
    ]) {
      expect(
        card.steps,
        hasLength(card.spec.steps.length),
        reason: card.spec.slug,
      );
    }
    expect(
      () => GuideEditorCard(
        GuideCardSpec('x', [
          GuideCoachStep('plain', (l10n) => l10n.calendarGuideTryIt),
        ], (l10n) => l10n.calendarGuideTryIt),
        seed: (l10n) => '',
      ),
      throwsAssertionError,
    );
  });

  test('the pages where a mark is read or a button is made hold one card '
      'each', () {
    const cards = {
      NotesGuideTopic.markdown: 'markdown',
      NotesGuideTopic.lists: 'lists',
      NotesGuideTopic.own: 'own',
      NotesGuideTopic.money: 'money',
      NotesGuideTopic.shortcuts: 'shortcuts',
    };
    for (final topic in NotesGuideTopic.values) {
      final slug = cards[topic];
      expect(
        topic.editorCards.map((card) => card.spec.slug),
        slug == null ? isEmpty : [slug],
        reason: topic.slug,
      );
    }
  });

  for (final l10n in [
    AppLocalizationsEn(),
    AppLocalizationsDe(),
    AppLocalizationsRo(),
  ]) {
    test('${l10n.localeName}: every seed satisfies no step of its card', () {
      for (final topic in NotesGuideTopic.values) {
        for (final card in topic.editorCards) {
          final seeded = doc(card.seed(l10n));
          for (final step in card.steps) {
            expect(
              step.done(seeded),
              isFalse,
              reason: '${card.spec.slug} ${step.action}',
            );
          }
        }
      }
    });
  }
}
