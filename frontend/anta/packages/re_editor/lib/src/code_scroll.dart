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

  /// Scrolls the scrollables **around** the editor until [position]'s caret
  /// line is on screen, [margin] included — for an editor embedded in a
  /// scroll view, where [makeVisible] alone leaves the caret visible
  /// inside the editor's box and the box itself behind the keyboard.
  ///
  /// Call it after the layout that placed the caret (a post-frame
  /// callback from an edit): it reads the last layout's geometry. Returns
  /// false when there was nothing to reveal — no editor mounted, the line
  /// outside the display window, or the caret outside the editor's box —
  /// and does nothing for an editor that sits in no scrollable.
  bool revealInAncestors(
    CodeLinePosition position, {
    EdgeInsets margin = EdgeInsets.zero,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    return _render?.showPositionOnScreen(position,
            margin: margin, duration: duration, curve: curve) ??
        false;
  }

  double? get contentHeight => _render?.contentHeight;

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
