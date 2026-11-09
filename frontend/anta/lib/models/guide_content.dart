import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../utils/ghost_text.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/markdown_inline_grammar.dart';
import 'calendar_guide_coach.dart';
import 'calendar_guide_content.dart';

/// One page of a guide book (`docs/guide-hub-roadmap.md` D3, D4): the hub
/// lists it, the top hub's search reaches into its entries, and its page
/// shows them under one "How it works" card.
///
/// An interface rather than a base enum, so each book's pages stay an enum
/// of their own whose slugs cannot collide inside the book; the calendar's
/// [CalendarGuideTopic] keeps its own shape (D7).
abstract interface class GuideTopic {
  /// Frozen: the hub row's, the page's and every entry's ids are built on it
  /// together with the book's slug.
  String get slug;

  IconData get icon;

  String title(AppLocalizations l10n);

  String caption(AppLocalizations l10n);

  /// The one line under the page's heading; null for a page without one.
  String? lead(AppLocalizations l10n);

  /// The page's rows in reading order.
  List<GuideEntry> entries(AppLocalizations l10n);

  /// The page's "Try it" editors (D17), drawn above its rows; empty for a
  /// page that is only read.
  List<GuideEditorCard> get editorCards;
}

/// What a step's check reads (D18): the document as the stage draws it and
/// as it stood before this change, whether an earlier step is done, and the
/// palette the card renders with. One per change, shared by every check.
final class GuideEditorDocument {
  GuideEditorDocument({
    required this.lines,
    this.previousLines = const [],
    required this.hasDone,
    required this.palette,
  });

  /// The lines with every line of a code fence, a `%%` comment or front
  /// matter blank (`docs/guide-hub-roadmap.md` §9.2): the stage draws those
  /// verbatim, so `# x` typed inside a fence is no heading she was taught.
  /// Built by [blankBlocks] from the editor's own block reading.
  final List<String> lines;

  /// [lines] as they stood before this change, read the same way; empty for
  /// the first change. A step that is a transition (the lists card's
  /// outdent) reads both, so a skipped step cannot stand in for it.
  final List<String> previousLines;

  /// Whether an earlier step is done or skipped. Cheap, and kept for a check
  /// that only means something after another even though none reads it now.
  final bool Function(String action) hasDone;

  /// The card's colours: a `{name:text}` run is a colour only when the
  /// palette names it, so a check resolves it as the stage draws it.
  final MarkdownColorPalette palette;

  /// Every inline token of each line, at every depth the renderer descends
  /// (a link's text, an emphasis' content, a colour's inside), outermost
  /// first. Tokenized on first read and kept, so a card with several inline
  /// checks tokenizes each line once per change (§9.2, review finding 8).
  late final List<List<InlineToken>> inlineTokens = [
    for (final line in lines) _inlineTokensOf(line, palette),
  ];

  /// [lines] with each line [inBlock] says the editor draws as a block body
  /// — fence, `%%` comment or front matter — replaced by `''`. The block
  /// reading is the render controller's, never the guide's own (D18).
  static List<String> blankBlocks(
    List<String> lines,
    bool Function(int index) inBlock,
  ) => [for (var i = 0; i < lines.length; i++) inBlock(i) ? '' : lines[i]];

  /// The tokenizer's tokens of [line] and of every range it descends into,
  /// with the line's ghost runs found once and handed to every level.
  static List<InlineToken> _inlineTokensOf(
    String line,
    MarkdownColorPalette palette,
  ) {
    if (line.isEmpty) return const [];
    final ghosts = GhostText.mightContain(line)
        ? GhostText.findGhosts(line)
        : const <GhostMatch>[];
    final tokens = <InlineToken>[];
    void walk(int start, int end, int depth) {
      for (final token in MarkdownInlineGrammar.tokenize(
        line,
        start: start,
        end: end,
        ghosts: ghosts,
        palette: palette,
        depth: depth,
      )) {
        tokens.add(token);
        final inside = switch (token) {
          InlineLink(:final textStart, :final textEnd) => (textStart, textEnd),
          InlineEmphasis(:final contentStart, :final innerEnd) => (
            contentStart,
            innerEnd,
          ),
          InlineColor(:final innerStart, :final innerEnd) => (
            innerStart,
            innerEnd,
          ),
          _ => null,
        };
        if (inside case (final from, final to)) walk(from, to, depth + 1);
      }
    }

    walk(0, line.length, 0);
    return tokens;
  }
}

/// A coach step of a "Try it" editor: done when the document shows it, never
/// when a control is tapped (D18), so every road to the mark — typed, pasted,
/// continued by Enter — counts alike.
class GuideEditorStep extends GuideCoachStep {
  const GuideEditorStep(super.action, super.line, this.done);

  /// Run after every text change while the step is not done, through the
  /// grammar modules the editor renders with; the coach's done set is
  /// sticky, so an edit undone later does not un-teach the step.
  final bool Function(GuideEditorDocument document) done;
}

/// One "Try it" editor of a book page (D17): its coach, whose steps are
/// [GuideEditorStep]s, over the text the stage opens with.
@immutable
final class GuideEditorCard {
  GuideEditorCard(this.spec, {required this.seed})
    : assert(spec.steps.every((step) => step is GuideEditorStep));

  /// The coach's card. Every step is a [GuideEditorStep]: a step without a
  /// check could never be done by typing and would hold the line forever.
  final GuideCardSpec spec;

  /// In the page's language when the stage first has one; a seed never
  /// satisfies a step of its card.
  final GuideLine seed;

  /// The coach's steps with their checks.
  Iterable<GuideEditorStep> get steps =>
      spec.steps.whereType<GuideEditorStep>();
}

/// One row of a guide page: a paragraph to read or an example to look at.
sealed class GuideEntry {
  const GuideEntry();
}

/// A read row, drawn exactly as the calendar guide draws its own (D4, D7).
final class GuideReadEntry extends GuideEntry {
  const GuideReadEntry(this.row);

  final CalendarGuideRow row;
}

/// A markdown example (§4 of the record): the [source] as typed over what
/// the editor's preview makes of it, with a [caption] under both.
final class GuideExampleEntry extends GuideEntry {
  const GuideExampleEntry({
    required this.slug,
    required this.source,
    required this.caption,
  });

  /// Frozen like a read row's: the example's id is built on it.
  final String slug;
  final String source;
  final String caption;
}
