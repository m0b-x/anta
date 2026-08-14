import 'package:re_editor/re_editor.dart';

/// A lightweight wrapper around [CodeLineEditingController] that provides
/// undo/redo grouping helpers for multi-step operations.
///
/// The re_editor's [CodeLineEditingController] already maintains its own
/// undo/redo history via an internal linked-list cache. Each call to
/// `runRevocableOp` (used internally by `set text`, `replaceSelection`, etc.)
/// creates a **new** undo node. Mutations that do NOT go through
/// `runRevocableOp` (i.e. setting `controller.value` directly) will
/// **overwrite** the current node — effectively merging with the previous
/// action.
///
/// This class provides:
///
/// * **[runAtomic]** — wraps multiple synchronous mutations in a single
///   `runRevocableOp` call so they produce one undo entry.
///
/// * Direct value merging guidance: for follow-up mutations that should
///   merge with an *already committed* undo entry (e.g. auto-formatting
///   after a paste), set `controller.value` directly instead of using
///   `set text` or `replaceSelection`.
///
/// ### Usage
///
/// ```dart
/// final observer = TextHistoryObserver(controller);
///
/// // Single atomic undo for synchronous multi-step changes:
/// observer.runAtomic(() {
///   controller.replaceSelection(someText);
///   controller.replaceSelection(moreText);
/// });
///
/// // Merge a follow-up change with the previous undo entry:
/// // (set value directly — bypasses runRevocableOp)
/// controller.value = CodeLineEditingValue(
///   codeLines: newText.codeLines,
///   selection: newSelection,
/// );
///
/// observer.dispose();
/// ```
class TextHistoryObserver {
  final CodeLineEditingController controller;

  TextHistoryObserver(this.controller);

  // ---------------------------------------------------------------------------
  // Atomic grouping
  // ---------------------------------------------------------------------------

  /// Executes [operation] as a single, atomic undo entry.
  ///
  /// This delegates to [CodeLineEditingController.runRevocableOp].
  /// All mutations inside [operation] will be recorded as one undo step.
  void runAtomic(void Function() operation) {
    controller.runRevocableOp(operation);
  }

  // ---------------------------------------------------------------------------
  // Convenience pass-throughs
  // ---------------------------------------------------------------------------

  bool get canUndo => controller.canUndo;
  bool get canRedo => controller.canRedo;

  void undo() => controller.undo();
  void redo() => controller.redo();

  void clearHistory() => controller.clearHistory();

  void dispose() {
    // Nothing to clean up — the controller is owned externally.
  }
}
