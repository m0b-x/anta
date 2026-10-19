import 'package:intl/intl.dart';
import 'package:re_editor/re_editor.dart';

import '../config/default_markdown_shortcuts.dart';
import '../models/custom_markdown_shortcut.dart';
import '../utils/markdown_callout_syntax.dart';
import '../utils/markdown_inline_grammar.dart';
import '../utils/markdown_line_shape.dart';
import '../utils/markdown_list_syntax.dart';

/// Async callback that mutates a counter (increment or decrement) and
/// returns the post-mutation value, or `null` when the counter doesn't
/// exist or isn't loaded.
typedef CounterMutator = Future<int?> Function(String counterId, CounterOp op);

/// Token regex matching `{c1}`, `{c2}`, etc. Each occurrence triggers
/// one counter mutation when expanded.
final RegExp _counterTokenPattern = RegExp(r'\{c(\d+)\}');

/// Applies a [CustomMarkdownShortcut] to a [CodeLineEditingController].
///
/// Supports:
///  * `wrap` — wraps the current selection with `before`/`after` text. A
///    plain symmetric wrapper (`**`, `_`, `~~`, `==`, `` ` ``) toggles
///    instead: see [toggleWrap].
///  * `date` — inserts a formatted date as the middle content (with
///    optional per-repeat date increment).
///  * `counter` — legacy single-counter shortcut where the first counter
///    binding's value is rendered as the middle content (kept for
///    backwards compatibility with existing user data).
///  * `header` — toggles markdown header level on the active line.
///  * [CustomMarkdownShortcut.linePrefixType] — toggles a line marker on
///    every covered line: see [toggleLinePrefix].
///
/// `before`/`after` (and the repeat wrapper text) may contain counter
/// tokens `{c1}` and `{c2}`, which expand to the corresponding counter
/// binding's value. Each occurrence triggers exactly one mutation per
/// repeat iteration, so `repeatCount: 5` with `{c1}` once = 5 mutations.
class ShortcutApplier {
  ShortcutApplier._();

  /// Resolves [shortcut] to the text it inserts, mutating counters along
  /// the way but leaving the document untouched — so the caller can run
  /// the insert itself, synchronously, under whatever guards it needs.
  ///
  /// Returns `null` for a shortcut that [rewrites] the document rather
  /// than inserting at the selection: run [applyRewrite] instead.
  ///
  /// Splitting the await off the write is what lets the note editor keep
  /// a shortcut inside one undo entry and one edit-tracker guard: every
  /// `await` here would otherwise land the insert in a microtask, long
  /// after those wrappers returned.
  static Future<String?> resolve({
    required CodeLineEditingController controller,
    required CustomMarkdownShortcut shortcut,
    required CounterMutator mutateCounter,
  }) async {
    if (rewrites(shortcut)) return null;

    final selectedText = controller.selectedText;
    final repeatCount = shortcut.repeatConfig?.count ?? 1;
    final separator = shortcut.repeatConfig?.separator ?? '\n';
    final beforeRepeatText = shortcut.repeatConfig?.beforeRepeatText ?? '';
    final afterRepeatText = shortcut.repeatConfig?.afterRepeatText ?? '';
    final bindings = shortcut.effectiveCounters;

    final hasCounterToken =
        _counterTokenPattern.hasMatch(shortcut.beforeText) ||
        _counterTokenPattern.hasMatch(shortcut.afterText) ||
        _counterTokenPattern.hasMatch(beforeRepeatText) ||
        _counterTokenPattern.hasMatch(afterRepeatText);

    final baseDate = _resolveBaseDate(shortcut);
    final dateFormat = shortcut.dateFormat ?? 'yyyy-MM-dd';
    final repeatConfig = shortcut.repeatConfig;

    final results = <String>[];
    for (int i = 0; i < repeatCount; i++) {
      final middle = await _resolveMiddle(
        shortcut: shortcut,
        iteration: i,
        baseDate: baseDate,
        dateFormat: dateFormat,
        repeatConfig: repeatConfig,
        selectedText: selectedText,
        bindings: bindings,
        hasCounterToken: hasCounterToken,
        mutateCounter: mutateCounter,
      );

      final before = await _expandCounterTokens(
        shortcut.beforeText,
        bindings,
        mutateCounter,
      );
      final after = await _expandCounterTokens(
        shortcut.afterText,
        bindings,
        mutateCounter,
      );

      results.add('$before$middle$after');
    }

    var wrapped = results.join(separator);

    if (beforeRepeatText.isNotEmpty || afterRepeatText.isNotEmpty) {
      final expandedBeforeRepeat = await _expandCounterTokens(
        beforeRepeatText,
        bindings,
        mutateCounter,
      );
      final expandedAfterRepeat = await _expandCounterTokens(
        afterRepeatText,
        bindings,
        mutateCounter,
      );
      wrapped = '$expandedBeforeRepeat$wrapped$expandedAfterRepeat';
    }

    return wrapped;
  }

  /// Resolves [shortcut] and applies it to [controller] in one call, for
  /// callers with no guards of their own to raise around the write.
  ///
  /// A rewrite needs nothing awaited, so it runs before the first `await`
  /// and still lands inside whatever guard or undo op the caller raised.
  static Future<void> apply({
    required CodeLineEditingController controller,
    required CustomMarkdownShortcut shortcut,
    required CounterMutator mutateCounter,
  }) async {
    if (rewrites(shortcut)) {
      applyRewrite(controller, shortcut);
      return;
    }
    final text = await resolve(
      controller: controller,
      shortcut: shortcut,
      mutateCounter: mutateCounter,
    );
    if (text != null) controller.replaceSelection(text);
  }

  /// Whether [shortcut] rewrites what is already there — the caret line's
  /// heading, the covered lines' markers, a wrapper around the selection —
  /// instead of inserting resolved text at the selection.
  static bool rewrites(CustomMarkdownShortcut shortcut) =>
      shortcut.insertType == 'header' ||
      _togglesLinePrefix(shortcut) ||
      _isPlainWrapper(shortcut);

  /// Runs the rewrite for a shortcut [rewrites] accepted.
  ///
  /// A header shortcut whose `beforeText` is itself a heading marker
  /// (the H menu's `### `) sets exactly that level; the bar's own
  /// `default_header` button carries `# ` as well, but it keeps cycling.
  /// [isFenceLine] keeps line-marker toggles and headings off code-fence
  /// lines, where a `#` run is code text.
  static void applyRewrite(
    CodeLineEditingController controller,
    CustomMarkdownShortcut shortcut, {
    bool Function(int lineIndex)? isFenceLine,
  }) {
    assert(rewrites(shortcut), '${shortcut.id} inserts, it does not rewrite');
    if (shortcut.insertType == 'header') {
      if (isFenceLine?.call(controller.selection.startIndex) ?? false) return;
      final level = shortcut.id == _cyclingHeaderId
          ? null
          : MarkdownLineShape.headingAt(shortcut.beforeText)?.level;
      if (level == null) {
        applyHeader(controller);
      } else {
        applyHeaderLevel(controller, level);
      }
      return;
    }
    if (_togglesLinePrefix(shortcut)) {
      toggleLinePrefix(
        controller,
        shortcut.beforeText,
        isFenceLine: isFenceLine,
      );
      return;
    }
    toggleWrap(controller, shortcut.beforeText);
  }

  static const String _cyclingHeaderId = 'default_header';

  /// Built-in list and quote shortcuts toggle whatever type their stored
  /// copy carries: see [DefaultMarkdownShortcuts.linePrefixIds].
  static bool _togglesLinePrefix(CustomMarkdownShortcut shortcut) =>
      shortcut.insertType == CustomMarkdownShortcut.linePrefixType ||
      (shortcut.insertType == 'wrap' &&
          DefaultMarkdownShortcuts.linePrefixIds.contains(shortcut.id));

  /// A wrapper whose text is the same on both sides and expands to itself:
  /// no counter token, no repeat, no line break. Only such a wrapper can be
  /// recognised around a selection again, which is what unwrapping needs.
  static bool _isPlainWrapper(CustomMarkdownShortcut shortcut) {
    final marker = shortcut.beforeText;
    final repeat = shortcut.repeatConfig;
    return shortcut.insertType == 'wrap' &&
        marker.isNotEmpty &&
        marker == shortcut.afterText &&
        !marker.contains('\n') &&
        !_counterTokenPattern.hasMatch(marker) &&
        (repeat == null ||
            (!repeat.isActive &&
                repeat.beforeRepeatText.isEmpty &&
                repeat.afterRepeatText.isEmpty));
  }

  // ---------------------------------------------------------------------------
  // Middle content
  // ---------------------------------------------------------------------------

  static Future<String> _resolveMiddle({
    required CustomMarkdownShortcut shortcut,
    required int iteration,
    required DateTime baseDate,
    required String dateFormat,
    required RepeatConfig? repeatConfig,
    required String selectedText,
    required List<CounterBinding> bindings,
    required bool hasCounterToken,
    required CounterMutator mutateCounter,
  }) async {
    switch (shortcut.insertType) {
      case 'date':
        var date = baseDate;
        if (repeatConfig != null &&
            repeatConfig.incrementDate &&
            iteration > 0) {
          date = DateTime(
            baseDate.year + (repeatConfig.dateIncrementYears * iteration),
            baseDate.month + (repeatConfig.dateIncrementMonths * iteration),
            baseDate.day + (repeatConfig.dateIncrementDays * iteration),
          );
        }
        final formatted = DateFormat(dateFormat).format(date);
        if (iteration == 0 && selectedText.isNotEmpty) {
          return selectedText;
        }
        return formatted;

      case 'counter':
        // Legacy single-counter mode: when no `{cN}` token is present in
        // any template field, render the first counter binding's value as
        // the middle content (matches pre-multi-counter behavior).
        if (!hasCounterToken && bindings.isNotEmpty) {
          final binding = bindings.first;
          final value = await mutateCounter(binding.counterId, binding.op);
          if (value == null) return '';
          return value.toString();
        }
        return '';

      default:
        return selectedText;
    }
  }

  // ---------------------------------------------------------------------------
  // Token expansion
  // ---------------------------------------------------------------------------

  /// Expands all `{cN}` tokens in [input] using [bindings]. Each match
  /// triggers one [mutateCounter] call (so two occurrences of `{c1}`
  /// produce two mutations). Tokens with no matching binding are left
  /// untouched so users can spot misconfiguration.
  static Future<String> _expandCounterTokens(
    String input,
    List<CounterBinding> bindings,
    CounterMutator mutateCounter,
  ) async {
    if (input.isEmpty) return input;
    final matches = _counterTokenPattern.allMatches(input).toList();
    if (matches.isEmpty) return input;

    final buffer = StringBuffer();
    var cursor = 0;
    for (final match in matches) {
      buffer.write(input.substring(cursor, match.start));
      final index = int.tryParse(match.group(1) ?? '') ?? 0;
      final bindingIndex = index - 1;
      if (bindingIndex < 0 || bindingIndex >= bindings.length) {
        buffer.write(match.group(0));
      } else {
        final binding = bindings[bindingIndex];
        final value = await mutateCounter(binding.counterId, binding.op);
        if (value == null) {
          buffer.write(match.group(0));
        } else {
          buffer.write(value.toString());
        }
      }
      cursor = match.end;
    }
    buffer.write(input.substring(cursor));
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static DateTime _resolveBaseDate(CustomMarkdownShortcut shortcut) {
    final now = DateTime.now();
    final offset = shortcut.dateOffset;
    if (offset == null) return now;
    return DateTime(
      now.year + offset.years,
      now.month + offset.months,
      now.day + offset.days,
    );
  }

  /// Cycles the caret line's heading level: plain text becomes `# `, each
  /// further application adds one `#`, and level 6 drops back to the bare
  /// content.
  ///
  /// The level comes from [MarkdownLineShape.headingAt], the app's single
  /// heading predicate, so the toolbar agrees with what both rendering
  /// surfaces call a heading. One consequence worth knowing: a bare `###`
  /// with no trailing space *is* a level-3 heading with empty content, so
  /// cycling it yields `#### `.
  static void applyHeader(CodeLineEditingController controller) {
    _setHeading(
      controller,
      (current) => current == null ? 1 : (current >= 6 ? 0 : current + 1),
    );
  }

  /// Sets the caret line's heading to exactly [level] (1–6) — the H menu's
  /// pick — and picking the level the line already has removes it, so the
  /// menu toggles like the other line markers.
  static void applyHeaderLevel(
    CodeLineEditingController controller,
    int level,
  ) {
    assert(level >= 1 && level <= 6, 'no heading level $level');
    _setHeading(controller, (current) => current == level ? 0 : level);
  }

  /// Rewrites the caret line's `#` run to the level [levelFor] picks from
  /// the current one (`null` on a plain line); `0` drops the heading.
  ///
  /// Only the run changes (and, on a drop, the closing run), so the caret
  /// and any selection on the line keep their place in the text instead
  /// of jumping to the line end.
  static void _setHeading(
    CodeLineEditingController controller,
    int Function(int? current) levelFor,
  ) {
    final lineIndex = controller.selection.startIndex;
    final line = controller.codeLines[lineIndex];
    final heading = MarkdownLineShape.headingAt(line.text);
    final level = levelFor(heading?.level);
    // A plain line gains its run after the indentation, where
    // [MarkdownLineShape.headingAt] finds it again, not in front of it.
    final plainStart = _LineMarker._indentOf(line.text);
    // Dropping the heading drops its closing run too (`## Week 3 ##`
    // becomes `Week 3`): without its opening run it would read as text.
    final closed =
        level == 0 && heading != null && heading.contentEnd < line.text.length;
    final splice = _Splice(
      heading?.hashStart ?? plainStart,
      heading?.contentStart ?? plainStart,
      level == 0 ? '' : '${'#' * level} ',
      closed ? heading.contentEnd : null,
    );
    _commit(
      controller,
      controller.codeLines.replaceLine(
        lineIndex,
        line.copyWith(text: splice.applyTo(line.text)),
      ),
      {lineIndex: splice},
    );
  }

  // ---------------------------------------------------------------------------
  // Toggles
  // ---------------------------------------------------------------------------

  /// Toggles the plain symmetric [marker] (`**`, `_`, `` ` ``…) around the
  /// selection, keeping the inner text selected so a second tap reverses
  /// the first:
  ///  * the selection is itself wrapped (`**x**`) → it becomes `x`;
  ///  * [marker] sits right outside both ends → both copies go; between an
  ///    empty pair (`**|**`) that removes the pair, while a caret between
  ///    two runs (`**a**|**b**`) leaves both alone. A one-character
  ///    emphasis marker (`*`, `_`) counts only when no word character sits
  ///    beyond it on either side, so selecting `case` in `snake_case_more`
  ///    wraps it rather than eating the underscores of an identifier;
  ///  * otherwise the selection is wrapped, and an empty selection gets
  ///    the pair with the caret between.
  ///
  /// The replace and the selection that follows it are one undo entry.
  static void toggleWrap(CodeLineEditingController controller, String marker) {
    final selection = controller.selection;
    final startIndex = selection.startIndex;
    final startOffset = selection.startOffset;
    final endIndex = selection.endIndex;
    final endOffset = selection.endOffset;
    // A marker on the start line shifts the end only when both share it.
    final sameLine = startIndex == endIndex;
    final width = marker.length;
    final selected = controller.selectedText;

    CodeLineSelection span(int start, int end) => CodeLineSelection(
      baseIndex: startIndex,
      baseOffset: start,
      extentIndex: endIndex,
      extentOffset: end,
    );

    controller.runRevocableOp(() {
      if (selected.length >= 2 * width &&
          selected.startsWith(marker) &&
          selected.endsWith(marker)) {
        controller.replaceSelection(
          selected.substring(width, selected.length - width),
        );
        controller.selection = span(
          startOffset,
          endOffset - (sameLine ? 2 * width : width),
        );
        return;
      }

      final startLine = controller.codeLines[startIndex].text;
      final endLine = controller.codeLines[endIndex].text;
      if (startOffset >= width &&
          startLine.startsWith(marker, startOffset - width) &&
          endLine.startsWith(marker, endOffset) &&
          (!selection.isCollapsed ||
              _opensAt(marker, startLine, startOffset - width)) &&
          _closesAround(
            marker,
            startLine,
            startOffset - width,
            endLine,
            endOffset + width,
          )) {
        controller.replaceSelection(
          selected,
          span(startOffset - width, endOffset + width),
        );
        controller.selection = span(
          startOffset - width,
          endOffset - (sameLine ? width : 0),
        );
        return;
      }

      controller.replaceSelection('$marker$selected$marker');
      controller.selection = span(
        startOffset + width,
        endOffset + (sameLine ? width : 0),
      );
    });
  }

  /// Whether the [marker] copy at [at] on [line] opens a pair rather than
  /// closing one: an even number of copies lies before it. A caret between
  /// two runs (`**a**|**b**`) sits between a closer and an opener, and
  /// unwrapping there would merge the runs into `**ab**`; only an empty
  /// pair (`**|**`) has an opener on its left.
  static bool _opensAt(String marker, String line, int at) {
    var copies = 0;
    var i = line.indexOf(marker);
    while (i != -1 && i < at) {
      copies++;
      i = line.indexOf(marker, i + marker.length);
    }
    return copies.isEven;
  }

  /// The one-character emphasis markers, whose copies outside a selection
  /// may be the inside of a word rather than a wrap.
  static const Set<String> _intrawordMarkers = {'*', '_'};

  /// Whether the [marker] copies at [openAt] on [startLine] and just
  /// before [closeEnd] on [endLine] read as a wrap around the selection.
  /// A multi-character marker always does; a one-character one only when
  /// the character beyond each copy is not a word character in
  /// [MarkdownInlineGrammar.isWordChar]'s sense — CommonMark's flanking
  /// rule in spirit, so `snake_case_more` keeps its underscores.
  static bool _closesAround(
    String marker,
    String startLine,
    int openAt,
    String endLine,
    int closeEnd,
  ) {
    if (!_intrawordMarkers.contains(marker)) return true;
    // Read whole code points, as the tokenizer does, so a letter outside
    // the BMP next to a copy keeps it literal here too.
    final before = openAt > 0
        ? MarkdownInlineGrammar.codePointBefore(startLine, openAt, 0)
        : -1;
    final after = closeEnd < endLine.length
        ? MarkdownInlineGrammar.codePointAt(endLine, closeEnd, endLine.length)
        : -1;
    return (before == -1 || !MarkdownInlineGrammar.isWordChar(before)) &&
        (after == -1 || !MarkdownInlineGrammar.isWordChar(after));
  }

  /// Toggles [prefix] as a line marker on the caret line, or on every
  /// non-blank line of a multi-line selection, right after the indent.
  ///
  /// A list marker (`- `, `• `, `- [ ] `, `- [x] `, `1. `) or a quote
  /// marker (`> `) is recognised on the line through [MarkdownListSyntax]
  /// and [MarkdownCalloutSyntax], so a second tap finds what the first one
  /// wrote:
  ///  * every covered line already carries it → it comes off each;
  ///  * otherwise each line that lacks it gains it, and a list item of
  ///    another shape swaps its marker in place (bullet, task and numbered,
  ///    an open box and a ticked one) instead of stacking a second marker.
  ///    A numbered marker continues the nearest ordered item above (blank
  ///    lines skipped) at the same indent, else it is [prefix] as written.
  ///  * a list marker on a quote line goes inside the quote, after its `>`
  ///    run, so the bullet on `> squat` gives `> - squat`.
  ///
  /// Lines [isFenceLine] reports are code and are left alone, and so is a
  /// horizontal rule under a list marker: `- ` on `---` spells `- ---`,
  /// itself a rule, so the line would gain a marker on every tap and a
  /// selection holding it could never toggle off. Any other
  /// prefix is matched literally. The edit is one value change: each line
  /// goes through [CodeLines.replaceLine], and the selection moves with
  /// its own line's shift.
  static void toggleLinePrefix(
    CodeLineEditingController controller,
    String prefix, {
    bool Function(int lineIndex)? isFenceLine,
  }) {
    final marker = _LineMarker.of(prefix);
    final selection = controller.selection;
    final first = selection.startIndex;
    var last = selection.endIndex;
    // A selection dragged onto column 0 of the next line holds none of
    // its text, so that line is not part of the toggle.
    if (last > first && selection.endOffset == 0) last--;

    var lines = controller.codeLines;
    final targets = <int>[
      for (var i = first; i <= last; i++)
        if ((first == last || lines[i].text.trim().isNotEmpty) &&
            !(isFenceLine?.call(i) ?? false) &&
            !marker.skipsRule(lines[i].text))
          i,
    ];
    if (targets.isEmpty) return;
    final removing = targets.every((i) => marker.isOn(lines[i].text));

    String? nonBlankAbove(int i) {
      for (var j = i - 1; j >= 0; j--) {
        final text = lines[j].text;
        if (text.trim().isNotEmpty) return text;
      }
      return null;
    }

    final splices = <int, _Splice>{};
    for (final i in targets) {
      final text = lines[i].text;
      // The line above is read after its own rewrite, so a selection
      // numbered in one tap counts 1, 2, 3 — across a blank line too.
      final splice = removing
          ? marker.removal(text)
          : marker.addition(text, above: nonBlankAbove(i));
      if (splice == null) continue;
      lines = lines.replaceLine(
        i,
        lines[i].copyWith(text: splice.applyTo(text)),
      );
      splices[i] = splice;
    }
    _commit(controller, lines, splices);
  }

  /// Writes [lines] as one undoable value change, moving each end of the
  /// selection by the splice on its own line.
  static void _commit(
    CodeLineEditingController controller,
    CodeLines lines,
    Map<int, _Splice> splices,
  ) {
    if (splices.isEmpty) return;
    final selection = controller.selection;
    int moved(int index, int offset) => splices[index]?.map(offset) ?? offset;
    controller.runRevocableOp(() {
      controller.value = CodeLineEditingValue(
        codeLines: lines,
        selection: selection.copyWith(
          baseOffset: moved(selection.baseIndex, selection.baseOffset),
          extentOffset: moved(selection.extentIndex, selection.extentOffset),
        ),
      );
    });
  }
}

/// One line's rewrite: the columns `[start, end)` replaced by [insert].
final class _Splice {
  const _Splice(this.start, this.end, this.insert, [this.dropFrom]);

  final int start;
  final int end;
  final String insert;

  /// Where the line's tail is cut off (a removed heading's closing run),
  /// or `null` to keep it; at or past [end].
  final int? dropFrom;

  String applyTo(String text) => text
      .substring(0, dropFrom ?? text.length)
      .replaceRange(start, end, insert);

  /// Where a caret at [offset] lands. Text after the old marker shifts
  /// with it; a caret inside a replaced marker lands after the new one; a
  /// caret on the edge of a removed or swapped marker stays put, while an
  /// insertion at the caret pushes it past what was inserted. A caret in
  /// a dropped tail lands where the kept text ends.
  int map(int offset) {
    final cut = dropFrom;
    if (cut != null && offset > cut) offset = cut;
    if (offset < start || (offset == start && end > start)) return offset;
    if (offset >= end) return offset + insert.length - (end - start);
    return start + insert.length;
  }
}

/// The marker [ShortcutApplier.toggleLinePrefix] looks for, read once from
/// the shortcut's prefix through the list and quote grammars.
final class _LineMarker {
  const _LineMarker._(this.prefix, this.list, this.isQuote);

  factory _LineMarker.of(String prefix) {
    final item = MarkdownListSyntax.parse(prefix);
    if (item != null &&
        item.indent.isEmpty &&
        item.contentStart == prefix.length) {
      return _LineMarker._(prefix, item, false);
    }
    final quote = MarkdownCalloutSyntax.quoteMarkers(prefix);
    return _LineMarker._(
      prefix,
      null,
      quote != null &&
          quote.markerOffsets.first == 0 &&
          quote.contentStart == prefix.length,
    );
  }

  final String prefix;

  /// The list item [prefix] spells when it is a bare list marker.
  final MarkdownListItem? list;

  /// Whether [prefix] is a bare quote marker.
  final bool isQuote;

  /// Where a list marker's part of [text] begins: after a quote's `>`
  /// run, so a list marker toggles inside the quote instead of stacking
  /// in front of its bar (`- > squat`). Column 0 on any other line.
  static int _listBase(String text) =>
      MarkdownCalloutSyntax.quoteMarkers(text)?.contentStart ?? 0;

  /// The list item on [text] past its quote run, read through
  /// [MarkdownListSyntax] with offsets relative to [base].
  static MarkdownListItem? _listItemAt(String text, int base) =>
      MarkdownListSyntax.parse(base == 0 ? text : text.substring(base));

  /// Whether a list marker leaves [text] alone because its list part is a
  /// horizontal rule, which the list grammar never reads as an item.
  bool skipsRule(String text) {
    if (list == null) return false;
    final base = _listBase(text);
    return MarkdownLineShape.isHorizontalRule(
      base == 0 ? text : text.substring(base),
    );
  }

  bool isOn(String text) {
    final wanted = list;
    if (wanted != null) {
      final item = _listItemAt(text, _listBase(text));
      return item != null && _sameMarker(item, wanted);
    }
    if (isQuote) return MarkdownCalloutSyntax.quoteMarkers(text) != null;
    return text.startsWith(prefix, _indentOf(text));
  }

  /// Takes the marker off a line [isOn] accepted; a quote loses its whole
  /// `>` run, not one level.
  _Splice? removal(String text) {
    if (list != null) {
      final base = _listBase(text);
      final item = _listItemAt(text, base);
      return item == null
          ? null
          : _Splice(base + item.indent.length, base + item.contentStart, '');
    }
    if (isQuote) {
      final quote = MarkdownCalloutSyntax.quoteMarkers(text);
      return quote == null
          ? null
          : _Splice(quote.markerOffsets.first, quote.contentStart, '');
    }
    final indent = _indentOf(text);
    return _Splice(indent, indent + prefix.length, '');
  }

  /// Puts the marker on a line, swapping a list item's own marker for it;
  /// `null` when the line already carries it.
  _Splice? addition(String text, {required String? above}) {
    if (isOn(text)) return null;
    final wanted = list;
    final base = wanted == null ? 0 : _listBase(text);
    final item = wanted == null ? null : _listItemAt(text, base);
    final start = item == null
        ? _indentOf(text, base)
        : base + item.indent.length;
    final end = item == null ? start : base + item.contentStart;
    final marker = wanted?.kind == MarkdownListKind.ordered
        ? _orderedAfter(above, text.substring(base, start)) ?? prefix
        : prefix;
    return _Splice(start, end, marker);
  }

  /// The next number after an ordered item [above] at the same [indent]
  /// (past [above]'s own quote run), in its own delimiter, or `null` when
  /// there is nothing to continue.
  static String? _orderedAfter(String? above, String indent) {
    if (above == null) return null;
    final item = _listItemAt(above, _listBase(above));
    if (item == null ||
        item.kind != MarkdownListKind.ordered ||
        item.indent != indent) {
      return null;
    }
    final number = int.tryParse(item.marker);
    return number == null ? null : '${number + 1}${item.delimiter} ';
  }

  /// A bullet matches by glyph and a task by its box, so the `•` and `-`
  /// buttons, and the open and ticked boxes, swap rather than remove each
  /// other; any number matches a numbered marker.
  static bool _sameMarker(MarkdownListItem item, MarkdownListItem wanted) {
    if (item.kind != wanted.kind) return false;
    return switch (item.kind) {
      MarkdownListKind.bullet => item.marker == wanted.marker,
      MarkdownListKind.task => item.checked == wanted.checked,
      MarkdownListKind.ordered => true,
    };
  }

  static int _indentOf(String text, [int from = 0]) {
    var i = from;
    while (i < text.length &&
        (text.codeUnitAt(i) == 0x20 || text.codeUnitAt(i) == 0x09)) {
      i++;
    }
    return i;
  }
}
