import '../crdt/synced_tables.dart';
import '../daos/sync_dao.dart';

/// The triggers that keep a row another account shares with this one as its
/// owner wrote it (`docs/cloud-sharing-foundations.md` §7): on this device
/// such a row is a copy of a live grant, and nothing but the reader of
/// shared rows may store, change or remove one.
///
/// A trigger rather than a check in each writer, because the writers are
/// many and some are sets — a reorder of a folder's notes, "delete all", a
/// label taken off every row that wears it, whatever a later change adds —
/// and one that forgot the check would stamp another person's row, queue it
/// and show the device owner a change the next read undoes.
///
/// Each one skips the row and nothing else (`RAISE(IGNORE)`): a statement
/// over many rows goes on with the others, and the person's own rows in it
/// are written as before. So a write of a shared row does not fail — it
/// does nothing — and a surface has to ask `SharedRowDao.isShared` before
/// it offers an edit; the two creations that would otherwise return a row
/// that was never stored refuse by name (`SharedRowException`).
///
/// Armed only while the database holds another account's rows at all
/// ([SyncDao.keySharedOwner]) and the reader is not the one writing
/// ([SyncDao.keySharedWriting], set and cleared inside its transactions):
/// for every database that never read a shared row, each costs one lookup
/// of a key that is not there.
abstract final class SharedRowFences {
  static const String _owner =
      "(SELECT value FROM sync_metadata WHERE key = '${SyncDao.keySharedOwner}')";

  static const String _armed =
      '$_owner IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sync_metadata '
      "WHERE key = '${SyncDao.keySharedWriting}')";

  /// Whether the folder under [id] (a column reference) is a shared one.
  static String _sharedFolder(String id) =>
      'EXISTS (SELECT 1 FROM folders shared_parent '
      'WHERE shared_parent.id = $id AND shared_parent.owner_id IS $_owner)';

  static String _sharedEvent(String id) =>
      'EXISTS (SELECT 1 FROM calendar_events shared_parent '
      'WHERE shared_parent.id = $id AND shared_parent.owner_id IS $_owner)';

  static String _sharedCategory(String id) =>
      'EXISTS (SELECT 1 FROM calendar_categories shared_parent '
      'WHERE shared_parent.id = $id AND shared_parent.owner_id IS $_owner)';

  static String _sharedNote(String id) =>
      'EXISTS (SELECT 1 FROM notes shared_parent '
      'WHERE shared_parent.id = $id AND shared_parent.owner_id IS $_owner)';

  static String _fence(String name, String event, String when) =>
      'CREATE TRIGGER IF NOT EXISTS shared_fence_$name BEFORE $event '
      'WHEN $_armed AND ($when) BEGIN SELECT RAISE(IGNORE); END';

  /// Every fence, as the statements that create it — idempotent, for a
  /// fresh install and for the migration alike.
  static List<String> get statements => [
    // The shared rows themselves: never stored, changed, re-owned or
    // removed but by the reader — and no row of the person's own made to
    // look like one.
    for (final table in sharedTables) ...[
      _fence('${table}_insert', 'INSERT ON $table', 'NEW.owner_id IS $_owner'),
      _fence(
        '${table}_update',
        'UPDATE ON $table',
        'OLD.owner_id IS $_owner OR NEW.owner_id IS $_owner',
      ),
      _fence('${table}_delete', 'DELETE ON $table', 'OLD.owner_id IS $_owner'),
    ],
    // Nothing of the person's own is hung under a shared row: a note or a
    // folder of theirs inside a shared folder, a skipped day or a day's
    // text of theirs on a shared event. It would show beside the owner's
    // rows and go with them when the share ends.
    _fence('notes_into', 'INSERT ON notes', _sharedFolder('NEW.folder_id')),
    _fence(
      'notes_moved_into',
      'UPDATE OF folder_id ON notes',
      'NEW.folder_id IS NOT OLD.folder_id AND '
          '${_sharedFolder('NEW.folder_id')}',
    ),
    _fence('folders_into', 'INSERT ON folders', _sharedFolder('NEW.parent_id')),
    _fence(
      'folders_moved_into',
      'UPDATE OF parent_id ON folders',
      'NEW.parent_id IS NOT OLD.parent_id AND '
          '${_sharedFolder('NEW.parent_id')}',
    ),
    for (final table in const [
      'calendar_event_occurrences',
      'calendar_event_skips',
    ])
      _fence('${table}_onto', 'INSERT ON $table', _sharedEvent('NEW.event_id')),
    // An event or a template of the person's own does not take a partner's
    // category: it would draw in the partner's colours, and be left on an
    // id that is gone when the share ends. A category alert of theirs may
    // name one — it is a personal row, as an alert on a shared event is.
    for (final table in const [
      'calendar_events',
      'calendar_event_templates',
    ]) ...[
      _fence(
        '${table}_onto_category',
        'INSERT ON $table',
        _sharedCategory('NEW.category'),
      ),
      _fence(
        '${table}_moved_onto_category',
        'UPDATE OF category ON $table',
        'NEW.category IS NOT OLD.category AND '
            '${_sharedCategory('NEW.category')}',
      ),
    ],
    // A shared note's text is its chunk rows, which carry no owner of
    // their own.
    _fence(
      'chunks_insert',
      'INSERT ON content_chunks',
      _sharedNote('NEW.note_id'),
    ),
    // Both ends: a chunk of the person's own must not be moved under a
    // shared note either.
    _fence(
      'chunks_update',
      'UPDATE ON content_chunks',
      '${_sharedNote('OLD.note_id')} OR ${_sharedNote('NEW.note_id')}',
    ),
    _fence(
      'chunks_delete',
      'DELETE ON content_chunks',
      _sharedNote('OLD.note_id'),
    ),
  ];
}
