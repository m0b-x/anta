import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/counter/counter_bloc.dart';
import '../interfaces/markdown_shortcut_handler.dart';
import '../models/custom_markdown_shortcut.dart';
import '../services/counter_service.dart';

/// Nothing calls [execute] today: the note editor counts and inserts through
/// `ShortcutApplier.resolve` (`optimized_note_editor_page/toolbar.dart`), and
/// only [setActiveNoteId] is reached in the app. Kept to the editor's rule
/// all the same — with no valid place to write, nothing is counted.
class CounterShortcutHandler implements MarkdownShortcutHandler {
  String? _activeNoteId;

  void setActiveNoteId(String? noteId) {
    _activeNoteId = noteId;
  }

  @override
  void execute({
    required BuildContext context,
    required CustomMarkdownShortcut shortcut,
    required TextEditingController controller,
    required FocusNode focusNode,
    required VoidCallback onTextChanged,
  }) async {
    final counterId = shortcut.counterId;
    if (counterId == null) return;

    final counterService = await CounterService.getInstance();
    final counter = counterService.getCounterById(counterId);
    if (counter == null) return;
    // A per-note count reads the note's values first; read here, before the
    // caret is looked at, the count below has nothing left to wait for, and
    // no input can move the caret between the look and the write.
    final noteId = _activeNoteId;
    if (noteId != null) await counterService.getNoteValues(noteId);
    // With no caret there is nowhere to write the number, so nothing is
    // counted either: a count that lands in no note is one nobody can see.
    if (!controller.selection.isValid) return;

    // increment() now returns the post-increment value (the count you just reached).
    final currentValue = await counterService.increment(
      counterId,
      noteId: noteId,
    );

    final text = controller.text;
    final selection = controller.selection;
    final start = selection.start;
    final end = selection.end;

    final valueStr = currentValue.toString();
    final insertText = '${shortcut.beforeText}$valueStr${shortcut.afterText}';

    final newText = text.substring(0, start) + insertText + text.substring(end);

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insertText.length),
    );

    focusNode.requestFocus();
    onTextChanged();

    // Sync the BLoC state so counter picker / management pages reflect the
    // updated value.  The service already holds the truth; RefreshCounters
    // rebuilds counterValues from it without double-incrementing.
    if (context.mounted) {
      context.read<CounterBloc>().add(const RefreshCounters());
    }
  }
}
