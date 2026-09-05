import 'package:equatable/equatable.dart';
import 'package:re_editor/re_editor.dart';

import 'ghost_text.dart';
import 'markdown_color_syntax.dart';
import 'markdown_editor_span_builder.dart';
import 'markdown_inline_grammar.dart';
import 'markdown_list_syntax.dart';
import 'markdown_list_utils.dart';
import 'markdown_money_syntax.dart';

/// What a claimed tap does instead of editing. Pure data — the editor
/// wrapper maps each action to its haptics plus the page callback that
/// carries it out — so the whole tap policy is table-testable without a
/// widget tree.
sealed class EditorTapAction extends Equatable {
  const EditorTapAction();

  @override
  List<Object?> get props => const [];
}

/// Flip the task checkbox on [lineIndex].
final class EditorToggleTaskAction extends EditorTapAction {
  const EditorToggleTaskAction(this.lineIndex);

  final int lineIndex;

  @override
  List<Object?> get props => [lineIndex];
}

/// Open the url of a concealed `[text](url)` link.
final class EditorOpenLinkAction extends EditorTapAction {
  const EditorOpenLinkAction(this.url);

  final String url;

  @override
  List<Object?> get props => [url];
}

/// Open the ledger detail sheet for the money row on [lineIndex].
final class EditorOpenMoneyAction extends EditorTapAction {
  const EditorOpenMoneyAction(this.lineIndex);

  final int lineIndex;

  @override
  List<Object?> get props => [lineIndex];
}

/// Search for a tapped `#tag`, leading `#` preserved — the same string
/// the preview's tag recognizer passes.
final class EditorOpenTagAction extends EditorTapAction {
  const EditorOpenTagAction(this.tag);

  final String tag;

  @override
  List<Object?> get props => [tag];
}

/// One tap zone on a line: the half-open offset range `[start, end)`
/// whose every offset resolves to [action] through
/// [EditorInputPolicy.resolveTap].
///
/// Ranges are what a screen reader needs and a single offset is not: a
/// semantics child node per zone needs the zone's extent to size its
/// rect. One zone per construct — two adjacent links are two zones, and
/// a construct a ghost run or a higher-precedence zone cuts in two is
/// two zones as well, because both halves are separately reachable.
class EditorTapZone extends Equatable {
  const EditorTapZone({
    required this.start,
    required this.end,
    required this.action,
  });

  /// First offset of the zone.
  final int start;

  /// One past the zone's last offset.
  final int end;

  /// What a tap anywhere in `[start, end)` does.
  final EditorTapAction action;

  @override
  List<Object?> get props => [start, end, action];
}

/// Which tap zones the host enabled — the wrapper's `checkboxTapToggle`
/// flag and its three nullable callbacks — plus the palette the span
/// builder renders with, so a zone resolves nested `{name:…}` runs
/// exactly as they are drawn.
class EditorTapZones {
  const EditorTapZones({
    required this.checkbox,
    required this.links,
    required this.money,
    required this.tags,
    required this.palette,
  });

  final bool checkbox;
  final bool links;
  final bool money;
  final bool tags;
  final MarkdownColorPalette palette;
}

/// The result of a Tab / Shift-Tab on a single list line: the line's new
/// [text] and the [delta] every caret offset on it shifts by. A [delta]
/// of 0 leaves [text] unchanged and means "consume the key, change
/// nothing" — an outdent already at column 0.
class EditorListIndent extends Equatable {
  const EditorListIndent(this.text, this.delta);

  final String text;
  final int delta;

  @override
  List<Object?> get props => [text, delta];
}

/// The pure input policy of the live markdown editor: which taps mean
/// something other than caret placement, and what Tab / Shift-Tab and a
/// checkbox toggle do to a line.
///
/// It reads nothing but the line's text and the caller's flags, so the
/// wrapper stays a thin adapter (controller reads, haptics, callbacks)
/// and every rule below is pinned by a table test instead of by geometry
/// against a mounted editor.
class EditorInputPolicy {
  EditorInputPolicy._();

  /// Resolves what a tap at [offset] on [lineIndex] does instead of
  /// editing. `null` means the tap falls through to normal caret
  /// placement; [lineText] of `null` means [lineIndex] is out of range.
  ///
  /// The pass-through rules exist because the tapped text is not the
  /// rendered construct: a revealed (selection-covered) line and a fence
  /// line show raw markdown, an over-long line is rendered raw by the
  /// span builder's length guard, hit-testing clamps taps in blank space
  /// to the line-end offset, and a tap inside a ghost run rides the
  /// selection change instead (ghosts win).
  ///
  /// Zones resolve in precedence order — checkbox, link, money, tag —
  /// so a construct nested in an earlier zone opens that zone's action.
  static EditorTapAction? resolveTap({
    required String? lineText,
    required int lineIndex,
    required int offset,
    required bool lineRevealed,
    required bool inFence,
    required EditorTapZones zones,
  }) {
    if (lineText == null) return null;
    if (lineRevealed) return null;
    if (inFence) return null;
    if (lineText.length > MarkdownEditorSpanBuilder.maxStyledLineLength) {
      return null;
    }
    if (offset >= lineText.length) return null;
    // The ghost runs are scanned once and then handed to the link and
    // tag zones, which would otherwise rescan the line for them: first
    // to decide whether the tap rides the selection change instead, then
    // once per grammar descent.
    final List<GhostMatch> ghostRuns = GhostText.mightContain(lineText)
        ? GhostText.findGhosts(lineText)
        : const <GhostMatch>[];
    for (final GhostMatch ghost in ghostRuns) {
      if (ghost.containsStrict(offset)) return null;
      if (ghost.start > offset) break;
    }
    if (zones.checkbox) {
      final item = MarkdownListSyntax.parse(lineText);
      // The toggle zone starts at the list marker, not the bracket, so
      // fat-finger taps just left of the box still toggle; everything
      // left of the marker is indent and keeps caret placement, and the
      // content right of the box stays editable.
      if (item != null &&
          item.kind == MarkdownListKind.task &&
          offset >= item.indent.length &&
          offset <= item.bracketStart + 3) {
        return EditorToggleTaskAction(lineIndex);
      }
    }
    if (zones.links) {
      // The zone is exactly the construct the editor renders as a link,
      // resolved through the one inline grammar both surfaces consume,
      // at any nesting depth — so emphasis, colour runs, inline code,
      // escapes, images and ghosts all decide the zone the same way they
      // decide the paint. Outermost boundary offsets are excluded by the
      // grammar, so taps that resolve to the edges still place the caret.
      final link = MarkdownInlineGrammar.linkAt(
        lineText,
        offset,
        palette: zones.palette,
        ghosts: ghostRuns,
      );
      if (link != null) return EditorOpenLinkAction(link.urlOf(lineText));
    }
    if (zones.money && MarkdownMoneySyntax.leadsWithMoney(lineText)) {
      final money = MarkdownMoneySyntax.parse(lineText);
      // Only a display row's painted chip (`$$` / `$?` / bare `$!` /
      // `$^` / `$~` — the shared [MarkdownMoneySyntax.isDisplayKind]
      // grouping) is a zone: from the marker up to the amount range (the
      // chip is wider than its two source chars, so the spaces and any
      // concealed accent token ride along); heading hashes, `$^`/`$~`
      // count digits, label text, op lines, and `$! N` declarations stay
      // editable. When a value slot moved the chip into the label, its
      // single `$` is a zone too — the marker keeps its own (it still
      // renders the kind's glyph there), so both the glyph and the value
      // open the sheet while the label around them stays editable.
      // Exactly the slot offset, never the space beside it.
      if (money != null &&
          MarkdownMoneySyntax.isDisplayKind(money.kind) &&
          ((offset >= money.markerStart && offset < money.amountStart) ||
              (money.valueSlot >= 0 && offset == money.valueSlot))) {
        return EditorOpenMoneyAction(lineIndex);
      }
    }
    if (zones.tags) {
      // Tags conceal and substitute nothing, so the tapped offset maps
      // 1:1 onto source code units; like the link zone the construct is
      // resolved at any nesting depth, so a tag inside emphasis or a
      // colour run is tappable while heading hashes, `#3`, and tags
      // inside code spans, escapes or ghost runs are not.
      final tag = MarkdownInlineGrammar.tagAt(
        lineText,
        offset,
        palette: zones.palette,
        ghosts: ghostRuns,
      );
      if (tag != null) return EditorOpenTagAction(tag.tagOf(lineText));
    }
    return null;
  }

  /// Every tap zone on [lineIndex], sorted by [EditorTapZone.start] and
  /// non-overlapping — the range-enumerating sibling of [resolveTap],
  /// for the accessibility layer, which cannot probe offsets and needs
  /// one child node per reachable zone.
  ///
  /// The two agree by construction: for every offset in
  /// `[0, lineText.length)`, [resolveTap] answers non-`null` exactly
  /// when some returned range contains that offset, and with that
  /// range's [EditorTapZone.action]. Every pass-through rule holds
  /// identically — a `null`, revealed, fenced or over-long line
  /// enumerates nothing, and ghost runs are cut out of every zone, so a
  /// construct straddling one is reported as the two halves that are
  /// actually tappable.
  ///
  /// The constructs come from the same grammars [resolveTap] reads;
  /// precedence — checkbox, link, money, tag, and outermost before
  /// nested within each — is resolved by claiming offsets in that order,
  /// so a zone nested in an earlier one is simply never reported.
  ///
  /// The claim table spans only the offsets some candidate reaches, not
  /// the whole line: with a screen reader on, this runs once per visible
  /// line on every layout, and a long line holding one short link should
  /// cost the link's width, not the line's.
  static List<EditorTapZone> zonesOf({
    required String? lineText,
    required int lineIndex,
    required bool lineRevealed,
    required bool inFence,
    required EditorTapZones zones,
  }) {
    if (lineText == null) return const [];
    if (lineRevealed) return const [];
    if (inFence) return const [];
    final int length = lineText.length;
    if (length == 0) return const [];
    if (length > MarkdownEditorSpanBuilder.maxStyledLineLength) {
      return const [];
    }

    final List<_ZoneCandidate> candidates = <_ZoneCandidate>[];
    if (zones.checkbox) {
      final item = MarkdownListSyntax.parse(lineText);
      if (item != null && item.kind == MarkdownListKind.task) {
        _addCandidate(
          candidates,
          item.indent.length,
          item.bracketStart + 4,
          EditorToggleTaskAction(lineIndex),
          length,
        );
      }
    }

    final bool mightHaveGhosts = GhostText.mightContain(lineText);
    List<GhostMatch>? ghostRuns;
    final List<InlineToken> inline;
    if (zones.links || zones.tags) {
      ghostRuns = mightHaveGhosts
          ? GhostText.findGhosts(lineText)
          : const <GhostMatch>[];
      inline = MarkdownInlineGrammar.linksAndTags(
        lineText,
        palette: zones.palette,
        ghosts: ghostRuns,
      );
    } else {
      inline = const <InlineToken>[];
    }

    if (zones.links) {
      for (final InlineToken token in inline) {
        if (token is InlineLink) {
          _addCandidate(
            candidates,
            token.start + 1,
            token.end,
            EditorOpenLinkAction(token.urlOf(lineText)),
            length,
          );
        }
      }
    }

    if (zones.money && MarkdownMoneySyntax.leadsWithMoney(lineText)) {
      final money = MarkdownMoneySyntax.parse(lineText);
      if (money != null && MarkdownMoneySyntax.isDisplayKind(money.kind)) {
        final action = EditorOpenMoneyAction(lineIndex);
        _addCandidate(
          candidates,
          money.markerStart,
          money.amountStart,
          action,
          length,
        );
        if (money.valueSlot >= 0) {
          _addCandidate(
            candidates,
            money.valueSlot,
            money.valueSlot + 1,
            action,
            length,
          );
        }
      }
    }

    if (zones.tags) {
      for (final InlineToken token in inline) {
        if (token is InlineTag) {
          _addCandidate(
            candidates,
            token.start + 1,
            token.end,
            EditorOpenTagAction(token.tagOf(lineText)),
            length,
          );
        }
      }
    }

    if (candidates.isEmpty) return const [];

    int lo = candidates.first.start;
    int hi = candidates.first.end;
    for (int i = 1; i < candidates.length; i++) {
      final _ZoneCandidate candidate = candidates[i];
      if (candidate.start < lo) lo = candidate.start;
      if (candidate.end > hi) hi = candidate.end;
    }

    final List<int> owner = List<int>.filled(hi - lo, -1);
    for (int i = 0; i < candidates.length; i++) {
      final _ZoneCandidate candidate = candidates[i];
      for (int o = candidate.start; o < candidate.end; o++) {
        if (owner[o - lo] < 0) owner[o - lo] = i;
      }
    }
    if (mightHaveGhosts) {
      final List<GhostMatch> runs = ghostRuns ?? GhostText.findGhosts(lineText);
      for (final GhostMatch ghost in runs) {
        final int from = ghost.start + 1 > lo ? ghost.start + 1 : lo;
        final int to = ghost.end < hi ? ghost.end : hi;
        for (int o = from; o < to; o++) {
          owner[o - lo] = -1;
        }
      }
    }

    final List<EditorTapZone> result = <EditorTapZone>[];
    int offset = lo;
    while (offset < hi) {
      final int claim = owner[offset - lo];
      if (claim < 0) {
        offset++;
        continue;
      }
      int end = offset + 1;
      while (end < hi && owner[end - lo] == claim) {
        end++;
      }
      result.add(
        EditorTapZone(
          start: offset,
          end: end,
          action: candidates[claim].action,
        ),
      );
      offset = end;
    }
    return result;
  }

  /// Records `[start, end)` as a candidate, clipped to [length] — the
  /// checkbox zone's `bracketStart + 4` reaches past a line that ends at
  /// the box, and every other producer already ends inside the line.
  static void _addCandidate(
    List<_ZoneCandidate> candidates,
    int start,
    int end,
    EditorTapAction action,
    int length,
  ) {
    final int hi = end > length ? length : end;
    if (start < hi) candidates.add(_ZoneCandidate(start, hi, action));
  }

  /// [lineText] with its task box flipped, or `null` when it is not a
  /// task item. The rest of the line is untouched, so the caller can
  /// apply it as a single-line replacement.
  static String? toggledTaskLine(String lineText) {
    final item = MarkdownListSyntax.parse(lineText);
    if (item == null || item.kind != MarkdownListKind.task) return null;
    return lineText.replaceRange(
      item.bracketStart + 1,
      item.bracketStart + 2,
      item.checked ? ' ' : 'x',
    );
  }

  /// Tab / Shift-Tab on a single list line: the markdown-editor
  /// convention indents the whole item at its start instead of inserting
  /// spaces at the caret. `null` means [lineText] is not a list line and
  /// the editor's own indent applies.
  static EditorListIndent? listIndent({
    required String lineText,
    required bool outdent,
  }) {
    if (!MarkdownListUtils.isListLine(lineText)) return null;
    const unit = '  '; // MarkdownListUtils.indentUnit spaces
    if (!outdent) return EditorListIndent('$unit$lineText', unit.length);
    if (lineText.startsWith(unit)) {
      return EditorListIndent(lineText.substring(unit.length), -unit.length);
    }
    if (lineText.startsWith(' ') || lineText.startsWith('\t')) {
      return EditorListIndent(lineText.substring(1), -1);
    }
    return EditorListIndent(lineText, 0);
  }
}

class _ZoneCandidate {
  const _ZoneCandidate(this.start, this.end, this.action);

  final int start;
  final int end;
  final EditorTapAction action;
}

/// What the editor should do about the ghost run under the caret after a
/// controller change.
sealed class GhostEngagementDecision extends Equatable {
  const GhostEngagementDecision();

  @override
  List<Object?> get props => const [];
}

/// Leave the caret alone.
final class GhostNone extends GhostEngagementDecision {
  const GhostNone();
}

/// Select `[start, end)` on [lineIndex] — the whole `{{ … }}` run.
final class GhostSelectRun extends GhostEngagementDecision {
  const GhostSelectRun({
    required this.lineIndex,
    required this.start,
    required this.end,
  });

  final int lineIndex;
  final int start;
  final int end;

  @override
  List<Object?> get props => [lineIndex, start, end];
}

/// Leave the collapsed caret where the tap put it: the second tap on the
/// same, unmodified run switches from replace to edit-in-place.
final class GhostEditInPlace extends GhostEngagementDecision {
  const GhostEditInPlace();
}

/// The ghost two-tap state machine.
///
/// A tap that lands the caret strictly inside a `{{ … }}` run selects the
/// whole run so it reads as an active "fill-in" field — the native
/// selection highlight is the "you tapped it" signal. Typing replaces the
/// run (markers included); tapping away simply collapses the selection,
/// leaving the placeholder intact, so nothing is ever lost. A second tap
/// on the same, unmodified run switches to edit mode so the inner text
/// can be edited in place.
///
/// Pure: no timers and no controller. The host arms it from a pointer-up
/// (so only a *tap* — never arrow-key navigation, which fires no pointer
/// event — can engage a ghost), disarms it from the arming timer's
/// expiry, and applies the returned decision.
class GhostEngagement {
  bool _armed = false;
  int _line = -1;
  int _start = -1;
  int _end = -1;
  String _text = '';

  /// Whether a pointer-up armed the next caret change.
  bool get armed => _armed;

  /// Whether a run is currently engaged.
  bool get engaged => _line >= 0;

  void arm() => _armed = true;

  void disarm() => _armed = false;

  /// Drops both the arming and the engagement — the host calls this when
  /// the document under it is swapped out.
  void reset() {
    _armed = false;
    _clear();
  }

  /// Folds a controller change into the machine and reports what the
  /// host should do. [lineText] is the caret line's text, `null` when
  /// the caret index is out of range.
  ///
  /// Engagement is dropped whenever the selection leaves the run or the
  /// run's line changes, so a much-later tap on the same ghost starts
  /// fresh in replace mode instead of edit mode.
  GhostEngagementDecision caretChanged({
    required CodeLineSelection selection,
    required String? lineText,
  }) {
    final decision = _engage(selection, lineText);
    _disengageIfLeft(selection, lineText);
    return decision;
  }

  GhostEngagementDecision _engage(
    CodeLineSelection selection,
    String? lineText,
  ) {
    if (!_armed) return const GhostNone();
    if (!selection.isCollapsed) return const GhostNone();
    if (lineText == null) return const GhostNone();
    if (!GhostText.mightContain(lineText)) return const GhostNone();
    final ghost = GhostText.ghostAtOffset(lineText, selection.baseOffset);
    if (ghost == null) return const GhostNone();

    final lineIndex = selection.baseIndex;
    if (lineIndex == _line &&
        lineText == _text &&
        ghost.start == _start &&
        ghost.end == _end) {
      _armed = false;
      _clear();
      return const GhostEditInPlace();
    }
    _line = lineIndex;
    _start = ghost.start;
    _end = ghost.end;
    _text = lineText;
    _armed = false;
    return GhostSelectRun(
      lineIndex: lineIndex,
      start: ghost.start,
      end: ghost.end,
    );
  }

  void _disengageIfLeft(CodeLineSelection selection, String? lineText) {
    if (_line < 0) return;
    if (selection.baseIndex != _line ||
        selection.extentIndex != _line ||
        lineText == null ||
        lineText != _text) {
      _clear();
      return;
    }
    final base = selection.baseOffset;
    final extent = selection.extentOffset;
    final lo = base < extent ? base : extent;
    final hi = base < extent ? extent : base;
    if (lo < _start || hi > _end) _clear();
  }

  void _clear() {
    _line = -1;
    _start = -1;
    _end = -1;
    _text = '';
  }
}
