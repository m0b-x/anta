/// Which conflict copies an open editor takes over from a pulled page.
///
/// One decision needs it: a pulled page files no conflict copy for a note an
/// open editor will file one for itself, because that page keeps its live
/// body, writes it back on its next save and files the *arriving* body as
/// the copy — so the engine's copy of the stored loser would be a second
/// one, holding an intermediate autosave the live text supersedes (record
/// §3.9, D3, R99). A registry rather than a lookup through the tree: the
/// hook runs inside the page's transaction, with no `BuildContext` and
/// nothing above it to ask.
///
/// The editor is asked, never a stored id: a new note is created on its
/// first save, so the id it answers for changes under it.
///
/// A claim, not a question. The merge asks inside its transaction and acts
/// on the answer there, while the editor only hears of the change once the
/// page committed; an answer re-derived then can differ — an autosave
/// landing in between reads the page clean — and both sides would stand
/// back, leaving the overwritten local body nowhere (A7 review R129). An
/// editor that answers true has taken the filing on and files it.
abstract final class OpenNoteRegistry {
  static final List<bool Function(String noteId)> _editors = [];

  /// Call from the editor page's `initState`.
  static void register(bool Function(String noteId) claimsConflictFiling) {
    _editors.add(claimsConflictFiling);
  }

  /// Call from `dispose`, with the same function.
  static void unregister(bool Function(String noteId) claimsConflictFiling) {
    _editors.remove(claimsConflictFiling);
  }

  /// Whether an open editor claims the conflict copy of [noteId]. False on a
  /// device that never opened a note — and on every other surface — so a
  /// pull behaves as it did before this seam existed.
  static bool claimsConflictFiling(String noteId) {
    for (final editor in _editors) {
      if (editor(noteId)) return true;
    }
    return false;
  }
}
