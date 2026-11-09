import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/controllers/editor_render_controller.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/l10n/app_localizations_ro.dart';
import 'package:anta/models/calendar_guide_coach.dart';
import 'package:anta/models/calendar_guide_content.dart';
import 'package:anta/models/guide_content.dart';
import 'package:anta/models/notes_guide_content.dart';
import 'package:anta/models/notes_guide_tries.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/markdown_list_syntax.dart';

/// The notes cards' checks (`docs/guide-hub-roadmap.md` §9.2, D18), each
/// over hand-written documents, and the seeds that satisfy none of them.
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

  test('every step of every card carries a check', () {
    for (final card in [
      notesGuideMarkdownTry,
      notesGuideListsTry,
      notesGuideOwnTry,
      notesGuideMoneyTry,
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

  test('the four pages where a mark is read hold one card each', () {
    const cards = {
      NotesGuideTopic.markdown: 'markdown',
      NotesGuideTopic.lists: 'lists',
      NotesGuideTopic.own: 'own',
      NotesGuideTopic.money: 'money',
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
