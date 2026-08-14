/// Thrown by [FolderStorageService] / [NoteStorageService] when a create,
/// rename, or move operation would violate the per-parent name uniqueness
/// invariant (folder names unique within their parent, note titles unique
/// within their folder; both case-insensitive and whitespace-trimmed; empty
/// note titles are exempt so multiple "Untitled" notes can coexist).
///
/// This is the canonical signal of the conflict — UI layers should catch
/// this specific type and surface a friendly snackbar instead of treating
/// it as a generic failure. All other write failures continue to surface
/// as the existing generic error states.
library;

enum DuplicateNameKind { folder, note }

class DuplicateNameException implements Exception {
  final DuplicateNameKind kind;
  final String name;

  /// For folders: the parent folder id (null = root).
  /// For notes: the containing folder id (never null since notes can't live
  /// at root in this app).
  final String? parentId;

  const DuplicateNameException({
    required this.kind,
    required this.name,
    required this.parentId,
  });

  @override
  String toString() =>
      'DuplicateNameException(kind: ${kind.name}, name: "$name", '
      'parentId: $parentId)';
}
