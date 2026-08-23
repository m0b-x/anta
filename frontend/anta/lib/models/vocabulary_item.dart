import 'package:equatable/equatable.dart';

/// One line of a [Vocabulary] — either a term the editor inserts when the
/// suggestion is accepted, or a `;;` **section header** that only organises the
/// list.
///
/// [term] is stored verbatim; matching folds it at comparison time.
///
/// Headers are ordinary rows rather than a separate table or column: they carry
/// position and identity exactly like terms, so the diff-based save reorders
/// and tombstones them with no special case, and a list round-trips through the
/// editor unchanged. Only the *suggestion* path filters them out — the grammar
/// lives here because both the facade (`lib/constants/vocabularies.dart`) and
/// the service need it, and the model is the one file both already import.
class VocabularyItem extends Equatable {
  /// Marks a line as a section header. Two characters, because a single `;`
  /// is plausible inside a real term and a header must never swallow one.
  static const String commentMarker = ';;';

  static bool isCommentText(String text) =>
      text.trimLeft().startsWith(commentMarker);

  final String id;
  final String vocabularyId;
  final String term;
  final int sortOrder;

  const VocabularyItem({
    required this.id,
    required this.vocabularyId,
    required this.term,
    required this.sortOrder,
  });

  /// Whether this line organises the list rather than being suggestible.
  bool get isComment => isCommentText(term);

  /// The header's text with its marker stripped, for surfaces that show the
  /// section rather than the raw line.
  String get commentLabel =>
      term.trimLeft().substring(commentMarker.length).trim();

  VocabularyItem copyWith({
    String? id,
    String? vocabularyId,
    String? term,
    int? sortOrder,
  }) {
    return VocabularyItem(
      id: id ?? this.id,
      vocabularyId: vocabularyId ?? this.vocabularyId,
      term: term ?? this.term,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  List<Object?> get props => [id, vocabularyId, term, sortOrder];
}
