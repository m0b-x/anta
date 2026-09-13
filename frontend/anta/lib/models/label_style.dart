/// How a labelled note or folder shows its colour in the browser list.
///
/// Persisted by name through `SettingsService`, so [fromName] falls back to
/// [dot] for a value written by a newer build rather than throwing.
enum LabelStyle {
  /// A 10 dp filled circle at the row's trailing edge. The default: it sits
  /// in space the row already reserves for a count or a chevron, so turning a
  /// label on is the only thing that ever moves the name beside it.
  dot,

  /// A 3 dp vertical bar on the row's leading edge, inset from the row's top
  /// and bottom and rounded on its right. The opt-in: it reads as a margin
  /// mark down the whole list rather than as one more trailing glyph.
  stripe;

  static LabelStyle fromName(String? name) {
    return LabelStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => LabelStyle.dot,
    );
  }
}
