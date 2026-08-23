import '../models/vocabulary.dart';
import '../services/folder_search_service.dart';
import '../utils/vocabulary_matcher.dart';

/// Synchronous, `await`-free view over the user's vocabularies, published by
/// `VocabularyService` and read by the editor on every keystroke.
///
/// The `CalendarCategories` pattern: the service owns the database, this owns
/// the shape the render/typing path needs. [candidates] is flattened and folded
/// once per publish so matching never allocates per keystroke.
///
/// `VocabularyService.reset()` clears this, so a database switch cannot leak
/// terms from a closed database into the suggestion bar.
class Vocabularies {
  Vocabularies._();

  static List<Vocabulary> _all = const [];
  static List<VocabularyCandidate> _candidates = const [];
  static Map<String, Vocabulary> _byId = const {};

  /// Ordered, including disabled ones — the management page shows everything.
  static List<Vocabulary> get all => _all;

  /// Every term of every **enabled** vocabulary, ordered by vocabulary and then
  /// by the user's own list order. This is the matcher's input.
  static List<VocabularyCandidate> get candidates => _candidates;

  /// Whether the editor has anything to suggest at all. Checked before any
  /// trigger parsing so an install without vocabularies pays nothing.
  static bool get hasCandidates => _candidates.isNotEmpty;

  static Vocabulary? byId(String id) => _byId[id];

  /// Resolves a ghost placeholder's inner text to a vocabulary, so
  /// `{{exercise}}` scopes its suggestions to the "Exercises" list.
  ///
  /// Folded comparison, with singular/plural tolerance in both directions — a
  /// placeholder is written the way it reads in the sentence, not the way the
  /// list is titled. Disabled vocabularies never resolve.
  static Vocabulary? byName(String name) {
    final folded = normalizeForSearch(name.trim());
    if (folded.isEmpty) return null;

    for (final vocabulary in _all) {
      if (!vocabulary.isEnabled) continue;
      if (_namesMatch(folded, normalizeForSearch(vocabulary.name.trim()))) {
        return vocabulary;
      }
    }
    return null;
  }

  /// Resolves the scope segment of a `@list:query` trigger to the lists it
  /// names, empty when it names none.
  ///
  /// Deliberately looser than [byName]: a token matches on folded **prefix**
  /// (so `@exer:` reaches "Exercises" and `@push:` reaches "Push Day") as well
  /// as the placeholder rule's plural tolerance (so `@exercises:` still reaches
  /// a list titled "Exercise"). One token matching several lists is the point —
  /// the union is the scope. Disabled lists never resolve.
  static Set<String> idsForScopeTokens(List<String> tokens) {
    if (tokens.isEmpty || _all.isEmpty) return const {};

    final ids = <String>{};
    for (final token in tokens) {
      final folded = normalizeForSearch(token.trim());
      if (folded.isEmpty) continue;

      for (final vocabulary in _all) {
        if (!vocabulary.isEnabled) continue;
        final name = normalizeForSearch(vocabulary.name.trim());
        if (name.startsWith(folded) || _namesMatch(folded, name)) {
          ids.add(vocabulary.id);
        }
      }
    }
    return ids;
  }

  static void updateCache(List<Vocabulary> vocabularies) {
    _all = List.unmodifiable(vocabularies);
    _byId = Map.unmodifiable({
      for (final vocabulary in vocabularies) vocabulary.id: vocabulary,
    });

    final candidates = <VocabularyCandidate>[];
    for (final vocabulary in vocabularies) {
      if (!vocabulary.isEnabled) continue;
      for (final item in vocabulary.items) {
        candidates.add(
          VocabularyCandidate(
            term: item.term,
            foldedTerm: normalizeForSearch(item.term),
            vocabularyId: vocabulary.id,
            vocabularyName: vocabulary.name,
            vocabularySortOrder: vocabulary.sortOrder,
            itemSortOrder: item.sortOrder,
          ),
        );
      }
    }
    _candidates = List.unmodifiable(candidates);
  }

  static void resetCache() => updateCache(const []);

  static bool _namesMatch(String a, String b) {
    if (a == b) return true;
    return _isPluralOf(a, b) || _isPluralOf(b, a);
  }

  static bool _isPluralOf(String plural, String singular) {
    return plural == '${singular}s' || plural == '${singular}es';
  }
}
