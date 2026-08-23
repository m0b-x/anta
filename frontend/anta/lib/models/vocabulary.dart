import 'package:equatable/equatable.dart';

import 'vocabulary_item.dart';

/// A named list of terms the editor offers as autocomplete.
///
/// Carries its [items] because every surface that shows a vocabulary shows its
/// terms too — the management list needs the count, the editor sheet needs the
/// text, and the suggestion facade flattens them all into one candidate list.
class Vocabulary extends Equatable {
  final String id;
  final String name;
  final bool isEnabled;
  final int sortOrder;
  final List<VocabularyItem> items;

  const Vocabulary({
    required this.id,
    required this.name,
    required this.isEnabled,
    required this.sortOrder,
    this.items = const [],
  });

  /// Every line, section headers included — this is what round-trips through
  /// the editor, so dropping headers here would delete them on the next save.
  List<String> get terms => [for (final item in items) item.term];

  /// The lines that can actually be suggested.
  Iterable<VocabularyItem> get suggestibleItems =>
      items.where((item) => !item.isComment);

  /// What every surface means by "how many terms" — headers are structure, not
  /// content, so a list of ten exercises under three headings is still ten.
  int get termCount => suggestibleItems.length;

  Vocabulary copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    int? sortOrder,
    List<VocabularyItem>? items,
  }) {
    return Vocabulary(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      sortOrder: sortOrder ?? this.sortOrder,
      items: items ?? this.items,
    );
  }

  @override
  List<Object?> get props => [id, name, isEnabled, sortOrder, items];
}
