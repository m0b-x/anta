import 'package:flutter/material.dart';
import '../interfaces/markdown_shortcut_handler.dart';
import '../models/custom_markdown_shortcut.dart';

class DefaultShortcutHandler implements MarkdownShortcutHandler {
  @override
  void execute({
    required BuildContext context,
    required CustomMarkdownShortcut shortcut,
    required TextEditingController controller,
    required FocusNode focusNode,
    required VoidCallback onTextChanged,
  }) {
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.start;
    final end = selection.end;

    String selectedText = '';
    if (start >= 0 && end >= 0 && start != end) {
      selectedText = text.substring(start, end);
    }

    // Build the single insertion
    final singleInsertion =
        shortcut.beforeText + selectedText + shortcut.afterText;

    // Apply repeat if configured
    final repeatConfig = shortcut.repeatConfig;
    final repeatCount = repeatConfig?.count ?? 1;
    final separator = repeatConfig?.separator ?? '\n';

    String insertText;
    if (repeatCount > 1) {
      // For repeats, use the single insertion pattern multiple times
      insertText = List.filled(repeatCount, singleInsertion).join(separator);
    } else {
      insertText = singleInsertion;
    }

    final newText = text.substring(0, start) + insertText + text.substring(end);

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insertText.length),
    );

    focusNode.requestFocus();
    onTextChanged();
  }
}
