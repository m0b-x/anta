part of re_editor;

/// Test-only handle on the library-private paragraph provider — the
/// layer that turns a line's span tree into the [IParagraph] the render
/// draws, and the only place the hanging-indent split, the marker
/// measurement cache and the span-splitting helpers exist.
///
/// The provider is deliberately private (the editor owns exactly one,
/// inside its highlighter) so no app code can hold a second one with a
/// different style; this wrapper opens it for tests only, with the same
/// call order the render uses: [updateBaseStyle] first, then [build].
@visibleForTesting
class CodeParagraphProviderForTesting {
  final _CodeParagraphProvider _provider = _CodeParagraphProvider();

  void updateBaseStyle(TextStyle style) => _provider.updateBaseStyle(style);

  void updateMaxLengthSingleLineRendering(int? maxLengthSingleLineRendering) =>
      _provider
          .updateMaxLengthSingleLineRendering(maxLengthSingleLineRendering);

  IParagraph build(TextSpan span, double maxWidth) =>
      _provider.build(span, maxWidth);

  void clearCache() => _provider.clearCache();

  TextSpan truncate(TextSpan span, int maxLength) =>
      _provider.trucate(span, maxLength);

  TextSpan dropPrefix(TextSpan span, int skip) =>
      _provider._dropPrefix(span, skip);

  /// Whether [paragraph] took the two-paragraph hanging-indent path
  /// rather than falling back to a plain single paragraph.
  bool isHanging(IParagraph paragraph) => paragraph is _HangingParagraphImpl;

  int get markerCacheLength => _provider.markerCacheLength;
}
