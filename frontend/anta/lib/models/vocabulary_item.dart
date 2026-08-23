import 'package:equatable/equatable.dart';

/// One term inside a [Vocabulary] — the exact text the editor inserts when the
/// suggestion is accepted.
///
/// [term] is stored verbatim; matching folds it at comparison time.
class VocabularyItem extends Equatable {
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
