part of re_editor;

/// Test-only handle on the library-private editor render — the object
/// that owns the display window and, with it, the per-line height
/// contract every caret/handle/IME anchor resolves through.
///
/// The render's widget is private too, so a test cannot reach it by
/// type: [of] walks down from any ancestor [RenderObject] (the one under
/// `find.byType(CodeEditor)` will do) and returns the first code-field
/// render it finds.
@visibleForTesting
class CodeFieldRenderForTesting {
  final _CodeFieldRender _render;

  CodeFieldRenderForTesting._(this._render);

  /// The code-field render at or below [root], or null when [root]
  /// belongs to no editor.
  static CodeFieldRenderForTesting? maybeOf(RenderObject root) {
    if (root is _CodeFieldRender) {
      return CodeFieldRenderForTesting._(root);
    }
    CodeFieldRenderForTesting? found;
    root.visitChildren((RenderObject child) {
      found ??= maybeOf(child);
    });
    return found;
  }

  /// The code-field render at or below [root]. Throws when there is
  /// none, so a test that mis-targets its finder fails loudly.
  static CodeFieldRenderForTesting of(RenderObject root) {
    final CodeFieldRenderForTesting? found = maybeOf(root);
    if (found == null) {
      throw StateError('No code field render below $root.');
    }
    return found;
  }

  /// The base line height — a whole-viewport estimate, never a
  /// per-line anchor.
  double get lineHeight => _render.lineHeight;

  /// Line height of the paragraph at line [index]; see
  /// `_CodeFieldRender.lineHeightOfLine`.
  double lineHeightOfLine(int index) => _render.lineHeightOfLine(index);

  /// Line height of the paragraph under a viewport-local [localOffset];
  /// see `_CodeFieldRender.lineHeightAtOffset`.
  double lineHeightAtOffset(Offset localOffset) =>
      _render.lineHeightAtOffset(localOffset);
}
