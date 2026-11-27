import '../models/catalog_tag.dart';
import '../utils/vocabulary_matcher.dart';

/// Synchronous, `await`-free view over the tags the notes carry, published
/// by `TagCatalogService` so the editor's `#…` suggestions read it during a
/// keystroke — the `Vocabularies` shape: the service owns the read, this
/// owns what the typing path needs, built once per publish.
///
/// `TagCatalogService.reset()` clears it, so a database switch cannot offer
/// a closed database's tags.
class TagCatalog {
  TagCatalog._();

  /// The [VocabularyCandidate.vocabularyId] of every tag candidate. One
  /// source, so the suggestion bar never labels a tag pill with where it came
  /// from; no vocabulary id (a uuid) can equal it.
  static const String sourceId = '#';

  static List<CatalogTag> _all = const [];
  static List<VocabularyCandidate> _candidates = const [];

  /// Every tag in use, most notes first, then by the folded form, then by
  /// spelling.
  static List<CatalogTag> get all => _all;

  /// [all] as `VocabularyMatcher`'s input, in the same order: each term is
  /// `#` and the tag's spelling, folded here rather than per keystroke, so a
  /// query is matched with its `#`.
  static List<VocabularyCandidate> get candidates => _candidates;

  static void updateCache(List<CatalogTag> tags) {
    _all = List.unmodifiable(tags);
    _candidates = List.unmodifiable([
      for (final (i, tag) in tags.indexed)
        VocabularyCandidate(
          term: '#${tag.tag}',
          foldedTerm: '#${tag.folded}',
          vocabularyId: sourceId,
          vocabularyName: '',
          vocabularySortOrder: 0,
          itemSortOrder: i,
        ),
    ]);
  }

  static void resetCache() => updateCache(const []);
}
