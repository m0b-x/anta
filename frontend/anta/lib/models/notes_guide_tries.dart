/// The notes book's "Try it" editors (`docs/guide-hub-roadmap.md` §9.2 and
/// §10.3), as data: a card is a slug, its steps, its seed and the buttons
/// of its bar, and every check is a named function over the grammar
/// modules the editor itself renders with (D18) — never a scanner of the
/// guide's own, so a mark the stage draws is a mark the coach sees. Actions
/// are frozen like slugs.
///
/// A line names the bar's button where one writes the mark (D28), by the
/// app's own label; the check under it is the same whichever way the mark
/// got there.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/ghost_text.dart';
import '../utils/markdown_inline_grammar.dart';
import '../utils/markdown_line_shape.dart';
import '../utils/markdown_list_syntax.dart';
import '../utils/markdown_money_syntax.dart';
import 'calendar_guide_content.dart';
import 'custom_markdown_shortcut.dart';
import 'guide_content.dart';
import 'utility_button_config.dart';

/// The section's title on every editor card: "Try it", as the calendar's.
String _tryTitle(AppLocalizations l10n) => l10n.calendarGuideTryIt;

/// The markdown page's card (§9.2 row 1): a heading, a bold word, a bullet
/// and a ticked box, each on the gym note she is shown.
final GuideEditorCard notesGuideMarkdownTry = GuideEditorCard(
  GuideCardSpec('markdown', [
    GuideEditorStep(
      'heading',
      (l10n) => l10n.notesGuideCoachMarkdownHeading(l10n.headers),
      notesGuideHasHeading,
    ),
    GuideEditorStep(
      'bold',
      (l10n) => l10n.notesGuideCoachMarkdownBold(l10n.bold),
      notesGuideHasBold,
    ),
    GuideEditorStep(
      'list',
      (l10n) => l10n.notesGuideCoachMarkdownList(l10n.bulletList),
      notesGuideHasBullet,
    ),
    GuideEditorStep(
      'task',
      (l10n) => l10n.notesGuideCoachMarkdownTask(l10n.checkbox),
      notesGuideHasTickedTask,
    ),
  ], _tryTitle),
  seed: (l10n) => l10n.notesGuideSeedMarkdown,
  bar: const GuideEditorBar(
    builtIns: {
      'default_checkbox',
      'default_bullet_list',
      'default_numbered_list',
      'default_bold',
      'default_italic',
      'default_header',
      'default_strikethrough',
      'default_highlight',
      'default_quote',
      'default_link',
    },
  ),
);

/// The lists page's card (§9.2 row 2): Enter continues the list, the swipe
/// or the bar's arrows nest an item and bring it back, and Enter on an
/// empty item ends it.
final GuideEditorCard notesGuideListsTry = GuideEditorCard(
  GuideCardSpec('lists', [
    GuideEditorStep(
      'enter',
      (l10n) => l10n.notesGuideCoachListsEnter,
      notesGuideHasMoreItems,
    ),
    GuideEditorStep(
      'nest',
      (l10n) => l10n.notesGuideCoachListsNest(l10n.indentLine),
      notesGuideHasNestedItem,
    ),
    GuideEditorStep(
      'outdent',
      (l10n) => l10n.notesGuideCoachListsOutdent(l10n.outdentLine),
      notesGuideHasOutdented,
    ),
    GuideEditorStep(
      'end',
      (l10n) => l10n.notesGuideCoachListsEnd,
      notesGuideHasEndedList,
    ),
  ], _tryTitle),
  seed: (l10n) => l10n.notesGuideSeedLists,
  bar: const GuideEditorBar(
    builtIns: {
      'default_checkbox',
      'default_bullet_list',
      'default_numbered_list',
    },
    // The two arrows the lesson names lead; undo trails them.
    utilities: [
      UtilityButtonId.indent,
      UtilityButtonId.outdent,
      UtilityButtonId.undo,
      UtilityButtonId.redo,
    ],
  ),
);

/// The own-markdown page's card (§9.2 row 3): a tag, a ghost, a colour and
/// a wiki link, the marks only ANTA reads.
final GuideEditorCard notesGuideOwnTry = GuideEditorCard(
  GuideCardSpec('own', [
    GuideEditorStep(
      'tag',
      (l10n) => l10n.notesGuideCoachOwnTag,
      notesGuideHasTag,
    ),
    GuideEditorStep(
      'ghost',
      (l10n) => l10n.notesGuideCoachOwnGhost(l10n.shortcutGhostText),
      notesGuideHasGhost,
    ),
    GuideEditorStep(
      'colour',
      (l10n) => l10n.notesGuideCoachOwnColour(l10n.shortcutColorText),
      notesGuideHasColour,
    ),
    GuideEditorStep(
      'wiki',
      (l10n) => l10n.notesGuideCoachOwnWiki,
      notesGuideHasWikiLink,
    ),
  ], _tryTitle),
  seed: (l10n) => l10n.notesGuideSeedOwn,
  bar: const GuideEditorBar(
    builtIns: {
      'default_callout',
      'default_date',
      'default_ghost',
      'default_color_text',
      'default_color_highlight',
    },
  ),
);

/// The money page's card (§9.2 row 4): a second spend, money coming in and
/// the total, on a ledger that is on in a card whatever her setting (§4).
final GuideEditorCard notesGuideMoneyTry = GuideEditorCard(
  GuideCardSpec('money', [
    GuideEditorStep(
      'spend',
      (l10n) => l10n.notesGuideCoachMoneySpend(l10n.shortcutMoneySubtract),
      notesGuideHasSpends,
    ),
    GuideEditorStep(
      'add',
      (l10n) => l10n.notesGuideCoachMoneyAdd(l10n.shortcutMoneyAdd),
      notesGuideHasIncome,
    ),
    GuideEditorStep(
      'total',
      (l10n) => l10n.notesGuideCoachMoneyTotal(l10n.shortcutMoneyTotal),
      notesGuideHasTotal,
    ),
  ], _tryTitle),
  seed: (l10n) => l10n.notesGuideSeedMoney,
  // The six buttons the page's "On the bar" row names.
  bar: const GuideEditorBar(
    builtIns: {
      'default_money',
      'default_money_subtract',
      'default_money_set',
      'default_money_total',
      'default_money_delta',
      'default_money_target',
    },
  ),
);

/// The counter the Set button's `{c1}` token counts with: the stage's own
/// (`docs/guide-hub-roadmap.md` D33), never one of hers.
const String notesGuideSetCounterId = 'guide-set';

/// The two ready-made buttons' ids, frozen like the built-in ones': a
/// device flow and the suite know a button by it.
const String notesGuideSetShortcutId = 'guide_shortcut_set';
const String notesGuideTodayShortcutId = 'guide_shortcut_today';

/// The shortcuts card's two ready-made buttons (D33), real shortcuts the
/// real applier runs: a checkbox line with the set's number and two blanks,
/// and today's date as a heading. Each ends its line, so a second press
/// starts the next.
List<CustomMarkdownShortcut> notesGuideShortcutButtons(AppLocalizations l10n) =>
    [
      CustomMarkdownShortcut(
        id: notesGuideSetShortcutId,
        label: l10n.notesGuideShortcutSetLabel,
        iconCodePoint: Icons.fitness_center.codePoint,
        iconFontFamily: 'MaterialIcons',
        beforeText: '${l10n.notesGuideShortcutSetText('{c1}', '{', '}')}\n',
        afterText: '',
        counters: const [CounterBinding(counterId: notesGuideSetCounterId)],
      ),
      CustomMarkdownShortcut(
        id: notesGuideTodayShortcutId,
        label: l10n.notesGuideShortcutTodayLabel,
        iconCodePoint: Icons.today.codePoint,
        iconFontFamily: 'MaterialIcons',
        beforeText: '## ',
        afterText: '\n',
        insertType: 'date',
        // One of the New Shortcut page's own formats.
        dateFormat: 'd MMMM yyyy',
      ),
    ];

/// The shortcuts page's card (§10.3): two buttons that write whole lines,
/// then the one she makes — a text in the stage's field, and her button
/// writing it.
final GuideEditorCard notesGuideShortcutsTry = GuideEditorCard(
  GuideCardSpec('shortcuts', [
    GuideEditorStep(
      'line',
      (l10n) =>
          l10n.notesGuideCoachShortcutsLine(l10n.notesGuideShortcutSetLabel),
      notesGuideHasBlankTask,
    ),
    GuideEditorStep(
      'count',
      (l10n) =>
          l10n.notesGuideCoachShortcutsCount(l10n.notesGuideShortcutSetLabel),
      notesGuideHasTwoTasks,
    ),
    GuideEditorStep(
      'date',
      (l10n) =>
          l10n.notesGuideCoachShortcutsDate(l10n.notesGuideShortcutTodayLabel),
      notesGuideHasHeading,
    ),
    GuideEditorStep(
      'write',
      (l10n) => l10n.notesGuideCoachShortcutsWrite(l10n.markdownStart),
      notesGuideHasMakerText,
    ),
    GuideEditorStep(
      'press',
      (l10n) =>
          l10n.notesGuideCoachShortcutsPress(l10n.notesGuideShortcutMineLabel),
      notesGuideHasOwnPress,
    ),
  ], _tryTitle),
  seed: (l10n) => l10n.notesGuideSeedShortcuts,
  bar: const GuideEditorBar(own: notesGuideShortcutButtons),
  maker: true,
);

/// Some line is an ATX heading, as every surface reads one.
bool notesGuideHasHeading(GuideEditorDocument document) =>
    document.lines.any((line) => MarkdownLineShape.headingAt(line) != null);

/// Some line holds a bold run — bold italic counts, it is drawn bold — at any
/// depth, inside a link's text or a colour as on its own.
bool notesGuideHasBold(GuideEditorDocument document) => _anyInline(
  document,
  (token) =>
      token is InlineEmphasis &&
      (token.kind == InlineEmphasisKind.bold ||
          token.kind == InlineEmphasisKind.boldItalic),
);

/// Some line is a bullet item; a task's box makes it a task, not a bullet.
bool notesGuideHasBullet(GuideEditorDocument document) => document.lines.any(
  (line) => MarkdownListSyntax.parse(line)?.kind == MarkdownListKind.bullet,
);

/// Some task item is ticked.
bool notesGuideHasTickedTask(GuideEditorDocument document) =>
    document.lines.any((line) {
      final item = MarkdownListSyntax.parse(line);
      return item != null && item.kind == MarkdownListKind.task && item.checked;
    });

/// The lists seed's items in every language: one more is an Enter that
/// continued the list. A test pins each seed to it.
@visibleForTesting
const int notesGuideListsSeedItems = 4;

/// More list items than the seed holds.
bool notesGuideHasMoreItems(GuideEditorDocument document) =>
    document.lines.where(MarkdownListSyntax.isListLine).length >
    notesGuideListsSeedItems;

/// Some list item sits a level or more in.
bool notesGuideHasNestedItem(GuideEditorDocument document) =>
    document.lines.any(_isNestedItem);

/// This change brought the last nested item back out: the document before
/// it had one and this one has none. The transition itself, so a flat list
/// after a skipped nest is no outdent she made (§9.2, review finding 3).
bool notesGuideHasOutdented(GuideEditorDocument document) =>
    document.previousLines.any(_isNestedItem) &&
    !document.lines.any(_isNestedItem);

/// A blank line directly under a list item and not directly over one: what
/// Enter on an empty item leaves when it ends the list, never a line opened
/// above an item (§9.2, review finding 2).
bool notesGuideHasEndedList(GuideEditorDocument document) {
  final lines = document.lines;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim().isEmpty &&
        MarkdownListSyntax.isListLine(lines[i - 1]) &&
        (i + 1 == lines.length ||
            !MarkdownListSyntax.isListLine(lines[i + 1]))) {
      return true;
    }
  }
  return false;
}

bool _isNestedItem(String line) =>
    MarkdownListSyntax.isListLine(line) &&
    MarkdownListSyntax.indentLevel(line) >= 1;

/// Some line holds a tag at any depth the renderer draws one.
bool notesGuideHasTag(GuideEditorDocument document) =>
    _anyInline(document, (token) => token is InlineTag);

/// Some line holds a ghost run.
bool notesGuideHasGhost(GuideEditorDocument document) => document.lines.any(
  (line) =>
      GhostText.mightContain(line) && GhostText.findGhosts(line).isNotEmpty,
);

/// Some text is drawn in a colour of the card's palette: a `{name:text}`
/// colour or a tinted highlight, the two shapes a colour takes, holding
/// text of its own. The slot the bar's colour buttons leave —
/// `{red:{{  }}}` — is not it yet: a ghost draws dim whatever is around it
/// (`docs/guide-hub-roadmap.md` D31).
bool notesGuideHasColour(GuideEditorDocument document) {
  for (var i = 0; i < document.lines.length; i++) {
    final line = document.lines[i];
    // Every colour run of the line, as (whole run, its inside).
    final runs = [
      for (final token in document.inlineTokens[i])
        if (_colourInside(token) case final inside?) (token, inside),
    ];
    if (runs.isEmpty) continue;
    final ghosts = GhostText.mightContain(line)
        ? GhostText.findGhosts(line)
        : const <GhostMatch>[];
    for (final (run, (from, to)) in runs) {
      for (var at = from; at < to; at++) {
        if (line.codeUnitAt(at) == 0x20) continue;
        if (ghosts.any((ghost) => at >= ghost.start && at < ghost.end)) {
          continue;
        }
        // A colour run inside this one answers for its own text: its
        // markers are chrome, so a slot wrapped in a second colour —
        // the button pressed twice — is still only a slot.
        final nested = runs.any(
          (other) =>
              !identical(other.$1, run) &&
              other.$1.start >= from &&
              other.$1.end <= to &&
              at >= other.$1.start &&
              at < other.$1.end,
        );
        if (!nested) return true;
      }
    }
  }
  return false;
}

/// The range a colour run draws in its colour: a `{name:…}` run's inside,
/// a tinted highlight's content past its `name:` prefix; null for any
/// other token.
(int, int)? _colourInside(InlineToken token) => switch (token) {
  InlineColor(:final innerStart, :final innerEnd) => (innerStart, innerEnd),
  InlineEmphasis(:final contentStart, :final innerEnd, :final tintSpec)
      when tintSpec != null =>
    (contentStart, innerEnd),
  _ => null,
};

/// Some checkbox item holds a blank: what the Set button writes, whatever
/// the language of its words.
bool notesGuideHasBlankTask(GuideEditorDocument document) => document.lines.any(
  (line) =>
      _isTask(line) &&
      GhostText.mightContain(line) &&
      GhostText.findGhosts(line).isNotEmpty,
);

/// Two checkbox items: the button pressed again. Not two with a blank —
/// she may have filled the first one's in between.
bool notesGuideHasTwoTasks(GuideEditorDocument document) =>
    document.lines.where(_isTask).length >= 2;

bool _isTask(String line) =>
    MarkdownListSyntax.parse(line)?.kind == MarkdownListKind.task;

/// The stage's own-button field holds something to write (D34).
bool notesGuideHasMakerText(GuideEditorDocument document) =>
    document.makerText.trim().isNotEmpty;

/// Her own button wrote its text (D34).
bool notesGuideHasOwnPress(GuideEditorDocument document) =>
    document.ownPresses > 0;

/// Some line holds a wiki link.
bool notesGuideHasWikiLink(GuideEditorDocument document) =>
    _anyInline(document, (token) => token is InlineWikiLink);

/// Two spends or more: the seed's one and hers.
bool notesGuideHasSpends(GuideEditorDocument document) =>
    _moneyLines(document, MoneyLineKind.subtract) >= 2;

/// Some line adds money.
bool notesGuideHasIncome(GuideEditorDocument document) =>
    _moneyLines(document, MoneyLineKind.add) >= 1;

/// Some line shows the total.
bool notesGuideHasTotal(GuideEditorDocument document) =>
    _moneyLines(document, MoneyLineKind.total) >= 1;

/// The lines the ledger draws as a [kind] row. A row with an error is
/// drawn as its error, never as a spend or an income, so it is none
/// (`docs/guide-hub-roadmap.md` D31).
int _moneyLines(GuideEditorDocument document, MoneyLineKind kind) =>
    document.lines.where((line) {
      final row = MarkdownMoneySyntax.parse(line);
      return row != null && row.kind == kind && row.error == null;
    }).length;

/// Whether [test] holds for an inline token of some line, at any depth the
/// renderer descends — read off the document's one tokenization, shared by
/// every inline check of the change.
bool _anyInline(
  GuideEditorDocument document,
  bool Function(InlineToken token) test,
) => document.inlineTokens.any((tokens) => tokens.any(test));
