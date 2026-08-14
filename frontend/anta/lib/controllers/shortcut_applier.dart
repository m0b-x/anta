import 'package:intl/intl.dart';
import 'package:re_editor/re_editor.dart';

import '../models/custom_markdown_shortcut.dart';

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
///  * `wrap` — wraps the current selection with `before`/`after` text.
///  * `date` — inserts a formatted date as the middle content (with
///    optional per-repeat date increment).
///  * `counter` — legacy single-counter shortcut where the first counter
///    binding's value is rendered as the middle content (kept for
///    backwards compatibility with existing user data).
///  * `header` — toggles markdown header level on the active line.
///
/// `before`/`after` (and the repeat wrapper text) may contain counter
/// tokens `{c1}` and `{c2}`, which expand to the corresponding counter
/// binding's value. Each occurrence triggers exactly one mutation per
/// repeat iteration, so `repeatCount: 5` with `{c1}` once = 5 mutations.
class ShortcutApplier {
  ShortcutApplier._();

  static Future<void> apply({
    required CodeLineEditingController controller,
    required CustomMarkdownShortcut shortcut,
    required CounterMutator mutateCounter,
  }) async {
    if (shortcut.insertType == 'header') {
      _applyHeader(controller);
      return;
    }

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

      // For symmetric wrappers with empty selection, preserve historical
      // behavior: the result is just `before` (which now may include
      // expanded tokens) so the caret can land between the wrapper.
      String iter;
      if (shortcut.insertType != 'date' &&
          shortcut.insertType != 'counter' &&
          selectedText.isEmpty &&
          before == after &&
          before.isNotEmpty) {
        iter = before;
      } else {
        iter = '$before$middle$after';
      }
      results.add(iter);
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

    controller.replaceSelection(wrapped);
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

  static void _applyHeader(CodeLineEditingController controller) {
    final selection = controller.selection;
    final lineIndex = selection.startIndex;
    final line = controller.codeLines[lineIndex];
    final lineText = line.text;

    final headerMatch = RegExp(r'^(#{1,6})\s').firstMatch(lineText);
    String newLineText;

    if (headerMatch != null) {
      final currentHashes = headerMatch.group(1)!;
      final textWithoutHeader = lineText.substring(headerMatch.end);
      newLineText = currentHashes.length >= 6
          ? textWithoutHeader
          : '$currentHashes# $textWithoutHeader';
    } else {
      newLineText = '# $lineText';
    }

    controller.selectLine(lineIndex);
    controller.replaceSelection(newLineText);
  }
}
