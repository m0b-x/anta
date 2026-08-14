import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../interfaces/markdown_shortcut_handler.dart';
import '../models/custom_markdown_shortcut.dart';
import '../database/database.dart';
import '../constants/settings_keys.dart';

class DateShortcutHandler implements MarkdownShortcutHandler {
  String? _cachedFormat;

  Future<String> _getDefaultDateFormat() async {
    if (_cachedFormat != null) return _cachedFormat!;
    final db = await AppDatabase.getInstance();
    final format = await db.userSettingsDao.getValue(SettingsKeys.dateFormat);
    _cachedFormat = format ?? SettingsKeys.defaultDateFormat;
    return _cachedFormat!;
  }

  void clearCache() {
    _cachedFormat = null;
  }

  /// Calculate date with offset applied
  DateTime _applyDateOffset(DateTime date, DateOffset? offset) {
    if (offset == null || offset.isEmpty) return date;
    return DateTime(
      date.year + offset.years,
      date.month + offset.months,
      date.day + offset.days,
    );
  }

  /// Calculate date with incremental offset for repetitions
  DateTime _applyRepeatIncrement(
    DateTime baseDate,
    RepeatConfig config,
    int repetitionIndex,
  ) {
    if (!config.incrementDate || repetitionIndex == 0) return baseDate;
    return DateTime(
      baseDate.year + (config.dateIncrementYears * repetitionIndex),
      baseDate.month + (config.dateIncrementMonths * repetitionIndex),
      baseDate.day + (config.dateIncrementDays * repetitionIndex),
    );
  }

  @override
  void execute({
    required BuildContext context,
    required CustomMarkdownShortcut shortcut,
    required TextEditingController controller,
    required FocusNode focusNode,
    required VoidCallback onTextChanged,
  }) async {
    final format = shortcut.dateFormat ?? await _getDefaultDateFormat();
    final text = controller.text;
    final selection = controller.selection;
    final cursorPos = selection.start;
    final selectedText = selection.start != selection.end
        ? text.substring(selection.start, selection.end)
        : '';

    // Calculate base date with offset
    final baseDate = _applyDateOffset(DateTime.now(), shortcut.dateOffset);

    // Get repeat configuration
    final repeatConfig = shortcut.repeatConfig;
    final repeatCount = repeatConfig?.count ?? 1;
    final separator = repeatConfig?.separator ?? '\n';

    // Generate all repetitions
    final results = <String>[];
    for (int i = 0; i < repeatCount; i++) {
      final date = repeatConfig != null
          ? _applyRepeatIncrement(baseDate, repeatConfig, i)
          : baseDate;
      final formattedDate = DateFormat(format).format(date);

      // Use selected text only for first repetition, otherwise use the date
      final middle = (selectedText.isNotEmpty && i == 0)
          ? selectedText
          : formattedDate;
      results.add('${shortcut.beforeText}$middle${shortcut.afterText}');
    }

    final insertText = results.join(separator);
    final newText =
        text.substring(0, cursorPos) +
        insertText +
        text.substring(selection.end);

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorPos + insertText.length),
    );

    focusNode.requestFocus();
    onTextChanged();
  }
}
