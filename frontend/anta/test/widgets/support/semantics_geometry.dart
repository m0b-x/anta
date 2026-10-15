import 'dart:ui' show FlutterView;

import 'package:flutter/rendering.dart';

/// Where [node] says it is, in logical pixels: its rect mapped through every
/// transform up to the root — the same walk the QA harness's dump makes
/// before a tap by id lands at the centre of what it reads.
Rect semanticsGlobalRect(SemanticsNode node, FlutterView view) {
  var rect = node.rect;
  SemanticsNode? current = node;
  while (current != null) {
    final transform = current.transform;
    if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
    current = current.parent;
  }
  // The root's transform scales to physical pixels.
  final ratio = view.devicePixelRatio;
  return Rect.fromLTRB(
    rect.left / ratio,
    rect.top / ratio,
    rect.right / ratio,
    rect.bottom / ratio,
  );
}
