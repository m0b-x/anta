import '../database.dart';

class DatabaseIndexes {
  final AppDatabase _db;

  DatabaseIndexes(this._db);

  Future<void> createAllIndexes() async {
    await _createFolderIndexes();
    await _createNoteIndexes();
    await _createChunkIndexes();
    await _createCounterIndexes();
    await createCalendarIndexes();
    await _createFtsTable();
    await createUniqueNameIndexes();
    await createPositionIndexes();
  }

  /// Indexes backing the manual-ordering browse queries
  /// (`FolderDao.getFoldersInParent` / `NoteDao.getNotesInFolder` ordering by
  /// `position`) — the folder content page's primary read.
  ///
  /// Public because the v4 and v25 migrations both call it. **v25 exists
  /// because these were originally created only inside the v3→v4 migration
  /// and never added here**, so every database created through `onCreate`
  /// (a new user, or any database added via the multi-database feature) was
  /// scanning and sorting where an upgraded one used an index.
  Future<void> createPositionIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_folders_position '
      'ON folders(parent_id, position) WHERE is_deleted = 0',
    );
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notes_position '
      'ON notes(folder_id, position) WHERE is_deleted = 0',
    );
  }

  Future<void> _createFolderIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_folders_parent ON folders(parent_id) WHERE is_deleted = 0',
    );
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_folders_hlc ON folders(hlc_timestamp)',
    );
  }

  Future<void> _createNoteIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notes_folder ON notes(folder_id) WHERE is_deleted = 0',
    );
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notes_hlc ON notes(hlc_timestamp)',
    );
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notes_updated ON notes(updated_at DESC) WHERE is_deleted = 0',
    );
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notes_created ON notes(created_at DESC) WHERE is_deleted = 0',
    );
  }

  /// Expression indexes that back the per-parent name uniqueness queries
  /// in FolderDao.folderNameExistsInParent and NoteDao.noteTitleExistsInFolder.
  /// Kept in their own method so the v9 migration can call this without
  /// recreating every other index.
  ///
  /// COALESCE on parent_id is required because SQLite indexes treat each
  /// NULL as distinct, so a plain `(parent_id, ...)` index can't satisfy
  /// the root-level lookup `parent_id IS NULL`. The folder-uniqueness
  /// query must use the same `COALESCE(parent_id, '')` expression for the
  /// planner to pick the index.
  Future<void> createUniqueNameIndexes() async {
    await _db.customStatement(
      "CREATE INDEX IF NOT EXISTS idx_folders_parent_lname "
      "ON folders(COALESCE(parent_id, ''), LOWER(TRIM(name))) "
      "WHERE is_deleted = 0",
    );
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notes_folder_ltitle '
      'ON notes(folder_id, LOWER(TRIM(title))) '
      'WHERE is_deleted = 0',
    );
  }

  Future<void> _createChunkIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_chunks_note_index ON content_chunks(note_id, chunk_index) WHERE is_deleted = 0',
    );
  }

  Future<void> _createCounterIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_counter_values_counter ON counter_values(counter_id)',
    );
  }

  /// Indexes for the calendar feature. Public because the v10 and v27
  /// migrations call this directly so existing installs get the index without
  /// re-running the full `createAllIndexes` path.
  ///
  /// Partial since v27: `CalendarEventDao.getAll` is the single read path and
  /// it filters tombstones, so the index only has to cover live rows.
  /// `getAll`'s predicate must restate `is_deleted = 0` exactly or SQLite
  /// silently drops to a scan plus a temp B-tree for the ordering — the v27
  /// migration drops the full index by name first so upgraders and fresh
  /// installs cannot end up on different definitions.
  Future<void> createCalendarIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_calendar_events_start_date '
      'ON calendar_events(start_date) WHERE is_deleted = 0',
    );
  }

  Future<void> _createFtsTable() async {
    await _db.customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(title, preview, content=notes, content_rowid=rowid)',
    );
  }
}
