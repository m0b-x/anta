part of re_editor;

typedef CodeScrollbarBuilder = Widget Function(
    BuildContext context, Widget child, ScrollableDetails details);

class CodeScrollController {
  final ScrollController verticalScroller;
  final ScrollController horizontalScroller;

  GlobalKey? _editorKey;

  /// A centring request the render consumes inside its next layout pass;
  /// see [makeCenterIfInvisibleOnLayout].
  CodeLinePosition? _pendingCenter;

  CodeScrollController({
    ScrollController? verticalScroller,
    ScrollController? horizontalScroller,
  })  : verticalScroller = verticalScroller ?? ScrollController(),
        horizontalScroller = horizontalScroller ?? ScrollController();

  void makeCenterIfInvisible(CodeLinePosition position) {
    _render?.makePositionCenterIfInvisible(position);
  }

  /// [makeCenterIfInvisible], applied inside the editor's next layout pass
  /// instead of after a frame has already been painted.
  ///
  /// The render corrects its viewport while laying out, so the frame that
  /// comes out of that layout is the first one anybody sees — no jump from
  /// the top, no retry frames walking the estimate in. It also works
  /// before the editor has been built at all: the request waits on this
  /// controller and the editor's first layout consumes it, which is how a
  /// note opened at a stored position shows that position in its very
  /// first frame. A later request replaces an unconsumed one.
  void makeCenterIfInvisibleOnLayout(CodeLinePosition position) {
    _pendingCenter = position;
    _render?.markNeedsLayout();
  }

  void makeVisible(CodeLinePosition position) {
    _render?.makePositionVisible(position);
  }

  void bindEditor(GlobalKey key) {
    _editorKey = key;
  }

  _CodeFieldRender? get _render {
    final RenderObject? renderObject =
        _editorKey?.currentContext?.findRenderObject();
    return renderObject is _CodeFieldRender ? renderObject : null;
  }

  void dispose() {
    _editorKey = null;
    _pendingCenter = null;
  }
}
