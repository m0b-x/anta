part of '../event_editor_sheet.dart';

class _DescriptionBox extends SingleChildRenderObjectWidget {
  final Listenable revision;
  final double? Function() measure;
  final double minHeight;
  final double maxHeight;

  const _DescriptionBox({
    required this.revision,
    required this.measure,
    required this.minHeight,
    required this.maxHeight,
    required Widget super.child,
  });

  @override
  _RenderDescriptionBox createRenderObject(BuildContext context) {
    return _RenderDescriptionBox(
      revision: revision,
      measure: measure,
      minHeight: minHeight,
      maxHeight: maxHeight,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDescriptionBox renderObject,
  ) {
    renderObject
      ..revision = revision
      ..measure = measure
      ..minHeight = minHeight
      ..maxHeight = maxHeight;
  }
}

class _RenderDescriptionBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  static const int _maxPasses = 3;

  Listenable _revision;
  double? Function() measure;
  double _minHeight;
  double _maxHeight;
  double _height;

  _RenderDescriptionBox({
    required Listenable revision,
    required this.measure,
    required double minHeight,
    required double maxHeight,
  }) : _revision = revision,
       _minHeight = minHeight,
       _maxHeight = maxHeight,
       _height = minHeight;

  set revision(Listenable value) {
    if (identical(value, _revision)) return;
    if (attached) _revision.removeListener(markNeedsLayout);
    _revision = value;
    if (attached) _revision.addListener(markNeedsLayout);
  }

  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  set maxHeight(double value) {
    if (value == _maxHeight) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _revision.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _revision.removeListener(markNeedsLayout);
    super.detach();
  }

  double _clamp(double height) => height.clamp(_minHeight, _maxHeight);

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(width, _clamp(_height)));
      return;
    }
    var height = _clamp(_height);
    for (var pass = 0; pass < _maxPasses; pass++) {
      child.layout(
        BoxConstraints.tightFor(width: width, height: height),
        parentUsesSize: true,
      );
      final content = measure();
      if (content == null) break;
      final next = _clamp(content);
      if ((next - height).abs() < 0.5) break;
      height = next;
      if (pass == _maxPasses - 1) {
        child.layout(
          BoxConstraints.tightFor(width: width, height: height),
          parentUsesSize: true,
        );
      }
    }
    _height = height;
    size = constraints.constrain(Size(width, height));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    return constraints.constrain(Size(constraints.maxWidth, _clamp(_height)));
  }

  @override
  double computeMinIntrinsicHeight(double width) => _clamp(_height);

  @override
  double computeMaxIntrinsicHeight(double width) => _clamp(_height);

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) context.paintChild(child, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return child?.hitTest(result, position: position) ?? false;
  }
}
