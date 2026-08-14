/// Data class for passing note information to isolate-based search indexing.
class NoteIndexData {
  final String id;
  final String title;
  final String content;

  const NoteIndexData({
    required this.id,
    required this.title,
    required this.content,
  });
}
