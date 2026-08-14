part of re_editor;

extension _InlineSpanExtension on InlineSpan {
  int get length => _computeLength();

  int _computeLength() {
    int len = 0;
    if (this is TextSpan) {
      len += (this as TextSpan).length;
    } else {
      // Placeholders must count as their one U+FFFC code unit — the
      // same accounting `toPlainText()` uses for the paragraph's text —
      // or truncation/prefix-drop/range math desyncs on span trees
      // containing CodeInlinePaintSpan boxes.
      len += toPlainText().length;
    }
    return len;
  }
}

extension _TextSpanExtension on TextSpan {
  int get length => _computeLength();

  int _computeLength() {
    int len = 0;
    if (text != null) {
      len += text!.length;
    }
    if (children != null) {
      for (final InlineSpan span in children!) {
        len += span.length;
      }
    }
    return len;
  }
}

extension _OffsetExtension on Offset {
  bool isSamePosition(Offset offset) {
    return (this - offset).distance < 10;
  }
}
