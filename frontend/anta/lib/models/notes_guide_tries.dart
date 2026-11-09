/// The notes book's "Try it" editors (`docs/guide-hub-roadmap.md` §9.2), as
/// data: a card is a slug, its steps and its seed, and every check is a
/// named function over the grammar modules the editor itself renders with
/// (D18) — never a scanner of the guide's own, so a mark the stage draws is
/// a mark the coach sees. Actions are frozen like slugs.
library;

import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';
import '../utils/ghost_text.dart';
import '../utils/markdown_inline_grammar.dart';
import '../utils/markdown_line_shape.dart';
import '../utils/markdown_list_syntax.dart';
import '../utils/markdown_money_syntax.dart';
import 'calendar_guide_content.dart';
import 'guide_content.dart';

/// The section's title on every editor card: "Try it", as the calendar's.
String _tryTitle(AppLocalizations l10n) => l10n.calendarGuideTryIt;

/// The markdown page's card (§9.2 row 1): a heading, a bold word, a bullet
/// and a ticked box, each on the gym note she is shown.
final GuideEditorCard notesGuideMarkdownTry = GuideEditorCard(
  GuideCardSpec('markdown', [
    GuideEditorStep(
      'heading',
      (l10n) => l10n.notesGuideCoachMarkdownHeading,
      notesGuideHasHeading,
    ),
    GuideEditorStep(
      'bold',
      (l10n) => l10n.notesGuideCoachMarkdownBold,
      notesGuideHasBold,
    ),
    GuideEditorStep(
      'list',
      (l10n) => l10n.notesGuideCoachMarkdownList,
      notesGuideHasBullet,
    ),
    GuideEditorStep(
      'task',
      (l10n) => l10n.notesGuideCoachMarkdownTask,
      notesGuideHasTickedTask,
    ),
  ], _tryTitle),
  seed: (l10n) => l10n.notesGuideSeedMarkdown,
);

/// The lists page's card (§9.2 row 2): Enter continues the list, the swipe
/// nests an item and brings it back, and Enter on an empty item ends it.
final GuideEditorCard notesGuideListsTry = GuideEditorCard(
  GuideCardSpec('lists', [
    GuideEditorStep(
      'enter',
      (l10n) => l10n.notesGuideCoachListsEnter,
      notesGuideHasMoreItems,
    ),
    GuideEditorStep(
      'nest',
      (l10n) => l10n.notesGuideCoachListsNest,
      notesGuideHasNestedItem,
    ),
    GuideEditorStep(
      'outdent',
      (l10n) => l10n.notesGuideCoachListsOutdent,
      notesGuideHasOutdented,
    ),
    GuideEditorStep(
      'end',
      (l10n) => l10n.notesGuideCoachListsEnd,
      notesGuideHasEndedList,
    ),
  ], _tryTitle),
  seed: (l10n) => l10n.notesGuideSeedLists,
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
      (l10n) => l10n.notesGuideCoachOwnGhost('{', '}'),
      notesGuideHasGhost,
    ),
    GuideEditorStep(
      'colour',
      (l10n) => l10n.notesGuideCoachOwnColour('{', '}'),
      notesGuideHasColour,
    ),
    GuideEditorStep(
      'wiki',
      (l10n) => l10n.notesGuideCoachOwnWiki,
      notesGuideHasWikiLink,
    ),
  ], _tryTitle),
  seed: (l10n) => l10n.notesGuideSeedOwn,
);

/// The money page's card (§9.2 row 4): a second spend, money coming in and
/// the total, on a ledger that is on in a card whatever her setting (§4).
final GuideEditorCard notesGuideMoneyTry = GuideEditorCard(
  GuideCardSpec('money', [
    GuideEditorStep(
      'spend',
      (l10n) => l10n.notesGuideCoachMoneySpend,
      notesGuideHasSpends,
    ),
    GuideEditorStep(
      'add',
      (l10n) => l10n.notesGuideCoachMoneyAdd,
      notesGuideHasIncome,
    ),
    GuideEditorStep(
      'total',
      (l10n) => l10n.notesGuideCoachMoneyTotal,
      notesGuideHasTotal,
    ),
  ], _tryTitle),
  seed: (l10n) => l10n.notesGuideSeedMoney,
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

/// Some run is drawn in a colour of the card's palette: a `{name:text}`
/// colour or a tinted highlight, the two shapes a colour takes.
bool notesGuideHasColour(GuideEditorDocument document) => _anyInline(
  document,
  (token) =>
      token is InlineColor ||
      (token is InlineEmphasis && token.tintSpec != null),
);

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

int _moneyLines(GuideEditorDocument document, MoneyLineKind kind) => document
    .lines
    .where((line) => MarkdownMoneySyntax.parse(line)?.kind == kind)
    .length;

/// Whether [test] holds for an inline token of some line, at any depth the
/// renderer descends — read off the document's one tokenization, shared by
/// every inline check of the change.
bool _anyInline(
  GuideEditorDocument document,
  bool Function(InlineToken token) test,
) => document.inlineTokens.any((tokens) => tokens.any(test));
