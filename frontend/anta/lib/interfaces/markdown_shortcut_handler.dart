import 'package:flutter/material.dart';
import '../models/custom_markdown_shortcut.dart';

abstract class MarkdownShortcutHandler {
  void execute({
    required BuildContext context,
    required CustomMarkdownShortcut shortcut,
    required TextEditingController controller,
    required FocusNode focusNode,
    required VoidCallback onTextChanged,
  });
}
