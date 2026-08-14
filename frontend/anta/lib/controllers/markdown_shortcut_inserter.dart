import 'package:re_editor/re_editor.dart';

import '../models/custom_markdown_shortcut.dart';
import '../utils/ghost_text.dart';

/// Insert behaviors that a few built-in shortcuts need instead of the
/// generic [ShortcutApplier] wrap, shared by every surface that hosts a
/// markdown bar over a [CodeLineEditingController] (the note editor and
/// the event description).
///
/// Each entry point performs exactly one atomic, undoable mutation.
/// Callers own what happens around it (change notification, scrolling the
/// caret into view).
class MarkdownShortcutInserter {
  MarkdownShortcutInserter._();

  static const String _ghostId = 'default_ghost';

  static const Set<String> _ghostSlotIds = {
    'default_color_text',
    'default_color_highlight',
  };

  /// Whether [shortcut] is one of the ids handled here. Callers check this
  /// before falling through to the generic applier.
  static bool handles(CustomMarkdownShortcut shortcut) =>
      shortcut.id == _ghostId || _ghostSlotIds.contains(shortcut.id);

  /// Runs the bespoke insert for [shortcut]. Only call when [handles]
  /// returned true.
  static void apply(
    CodeLineEditingController controller,
    CustomMarkdownShortcut shortcut,
  ) {
    if (shortcut.id == _ghostId) {
      insertGhost(controller);
      return;
    }
    insertWithGhostSlot(controller, shortcut);
  }

  /// Inserts a ghost placeholder. On an empty selection the caret lands
  /// inside the placeholder; a selection is wrapped in place.
  static void insertGhost(CodeLineEditingController controller) {
    final selected = controller.selectedText;
    if (selected.isEmpty) {
      final caret = controller.selection;
      final line = caret.baseIndex;
      final col = caret.baseOffset;
      controller.runRevocableOp(() {
        controller.replaceSelection(GhostText.wrap(''));
        // '{{  }}' → drop the caret between the two spaces (col + 3).
        controller.selection = CodeLineSelection.collapsed(
          index: line,
          offset: col + GhostText.open.length + 1,
        );
      });
    } else {
      controller.runRevocableOp(() {
        controller.replaceSelection(GhostText.wrap(selected));
      });
    }
  }

  /// Wraps the selection in [shortcut]'s before/after text. With no
  /// selection, drops an empty ghost placeholder into the slot and
  /// **selects the whole run** so the first keystroke replaces it —
  /// `{red:` yields `{red:{{  }}}` with `{{  }}` selected, and typing
  /// produces `{red:hello}`, which renders in the colour.
  ///
  /// The ghost must be selected, not merely have the caret inside it:
  /// typing *into* the placeholder leaves the run a ghost
  /// (`{red:{{ hello }}}`), and the ghost's dim styling overrides the
  /// colour — the text renders grey and the feature looks broken.
  ///
  /// The wrapper text is read from the shortcut itself rather than
  /// hardcoded, so a user who edits the shortcut to `{green:` (or
  /// duplicates it per colour) keeps the same insert behavior.
  static void insertWithGhostSlot(
    CodeLineEditingController controller,
    CustomMarkdownShortcut shortcut,
  ) {
    final before = shortcut.beforeText;
    final after = shortcut.afterText;
    final selected = controller.selectedText;

    if (selected.isNotEmpty) {
      controller.runRevocableOp(() {
        controller.replaceSelection('$before$selected$after');
      });
      return;
    }

    final caret = controller.selection;
    final line = caret.baseIndex;
    final col = caret.baseOffset;
    final ghost = GhostText.wrap('');
    controller.runRevocableOp(() {
      controller.replaceSelection('$before$ghost$after');
      controller.selection = CodeLineSelection(
        baseIndex: line,
        baseOffset: col + before.length,
        extentIndex: line,
        extentOffset: col + before.length + ghost.length,
      );
    });
  }
}
