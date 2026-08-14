class TextPositionUtils {
  TextPositionUtils._();

  static int getLineFromOffset(String text, int offset) {
    if (offset <= 0 || text.isEmpty) return 0;
    final clampedOffset = offset.clamp(0, text.length);
    int line = 0;
    for (int i = 0; i < clampedOffset; i++) {
      if (text.codeUnitAt(i) == 10) line++;
    }
    return line;
  }

  static int getColumnFromOffset(String text, int offset) {
    if (offset <= 0 || text.isEmpty) return 0;
    final clampedOffset = offset.clamp(0, text.length);
    int lastNewline = text.lastIndexOf('\n', clampedOffset - 1);
    return clampedOffset - (lastNewline + 1);
  }

  static ({int line, int column}) getPosition(String text, int offset) {
    return (
      line: getLineFromOffset(text, offset),
      column: getColumnFromOffset(text, offset),
    );
  }
}
