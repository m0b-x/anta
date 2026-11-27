import 'package:equatable/equatable.dart';

/// One tag of the tag catalog: every spelling of it that the live notes
/// carry, counted as one.
class CatalogTag extends Equatable {
  /// The spelling most of those notes use; on a tie, the one that sorts
  /// first — so a suggestion writes the tag the way the notes mostly do.
  final String tag;

  /// [tag] through `normalizeForSearch`: the one equality every tag surface
  /// uses, so `#LegDay` and `#legday` are this one entry.
  final String folded;

  /// How many live notes carry the tag, in any spelling.
  final int noteCount;

  const CatalogTag({
    required this.tag,
    required this.folded,
    required this.noteCount,
  });

  @override
  List<Object?> get props => [tag, folded, noteCount];
}
