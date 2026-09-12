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
    await createCalendarDeltaIndexes();
    await _createFtsTable();
    await createUniqueNameIndexes();
    await createNoteTitleIndex();
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

  /// Expression index backing the wiki-link resolver's lookup by title alone
  /// (`NoteDao.getNotesByTitle`), which searches **every** folder: a
  /// `[[note]]` names a note, not a path, so the query has no `folder_id` to
  /// narrow it with. Public because the v36 migration calls it.
  ///
  /// [createUniqueNameIndexes]' `idx_notes_folder_ltitle` cannot serve this.
  /// It is folder-led — `(folder_id, LOWER(TRIM(title)))` — and SQLite can
  /// only use an index from its leftmost column inward, so a title-only
  /// predicate would scan `notes` outright.
  ///
  /// `LOWER(TRIM(title))` is spelled character-for-character like that index's
  /// second column on purpose. An expression index is only usable when the
  /// query repeats the expression exactly, so one shared spelling is what
  /// keeps **both** lookups index-served: the uniqueness check on
  /// `idx_notes_folder_ltitle`, the resolver on this one.
  ///
  /// That is agreement about the *index expression*, not about the answer.
  /// The two normalise their **parameter** differently: `NoteDao`'s
  /// `noteTitleExistsInFolder` lowers it in Dart, which is Unicode-aware,
  /// while `NoteDao.getNotesByTitle` binds the raw trimmed title under
  /// SQLite's ASCII-only `LOWER(?1)`. So they can and do disagree — two notes
  /// titled `Șold` may coexist in one folder, and a `[[Șold]]` link then
  /// resolves one of them by the recency-then-id rule. See
  /// `NoteDao.getNotesByTitle`, and `test/database/note_title_lookup_test.dart`
  /// where the disagreement is pinned.
  ///
  /// `is_deleted = 0` is a literal for the reason recorded on
  /// [createCalendarDeltaIndexes]: Drift's `.equals(false)` emits a bound `?`,
  /// and whether SQLite can prove a bound parameter implies the index's
  /// `WHERE` is version-dependent. The DAO spells the same literal, so the
  /// match is syntactic on every SQLite version the app ships against.
  Future<void> createNoteTitleIndex() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notes_ltitle '
      'ON notes(LOWER(TRIM(title))) '
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
  ///
  /// Scoped to `calendar_events` on purpose: v10 calls this while that is the
  /// only calendar table in existence, so anything touching the delta tables
  /// belongs in [createCalendarDeltaIndexes] instead.
  Future<void> createCalendarIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_calendar_events_start_date '
      'ON calendar_events(start_date) WHERE is_deleted = 0',
    );
  }

  /// Covering indexes over the two occurrence-delta tables. Public because the
  /// v31 migration calls this directly.
  ///
  /// They exist because tombstones are never collected: `EventSkipService`
  /// and `EventPresenceService` each run a `_load` at startup and after every
  /// event delete, and without an index those reads scan years of dead rows to
  /// find the live ones. Each index carries the *entire* projection its own
  /// load consumes, so both are **covering** — the query answers from the index
  /// and never touches the table. The two are **no longer symmetric**: since
  /// **v37** an absence row also carries `status`, so its index is
  /// `(event_id, day, status)` while skips stay at `(event_id, day)`. Widening
  /// the skips index to match would only make it bigger. That is why the DAOs
  /// read through `getActiveKeys` rather than `getActive`, and why the
  /// predicate is
  /// spelled as the literal `is_deleted = 0`: Drift's `.equals(false)` emits a
  /// bound `?`, and whether SQLite can prove a bound parameter implies the
  /// index's `WHERE` is version-dependent — 3.53 uses the index, 3.50 falls
  /// back to a scan. A literal matches syntactically on every version.
  ///
  /// Separate from [createCalendarIndexes] because that one runs inside the
  /// v10 migration, where neither of these tables exists yet (v26 and v30).
  ///
  /// **`calendar_event_occurrences` deliberately has no counterpart here.**
  /// Its `_load` also reads `description` — up to 10,000 chars — so an index
  /// could only cover it by duplicating the table, and the non-covering
  /// version measured *slower* than the scan it replaced, at one rowid lookup
  /// per live row; an ANALYZE'd planner rejects it outright at a 10% tombstone
  /// ratio. A `_load` that reads every live row is already best served by a
  /// scan. Do not "restore" it.
  Future<void> createCalendarDeltaIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_calendar_event_skips_active '
      'ON calendar_event_skips(event_id, day) WHERE is_deleted = 0',
    );
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_calendar_event_absences_active '
      'ON calendar_event_absences(event_id, day, status) WHERE is_deleted = 0',
    );
  }

  Future<void> _createFtsTable() async {
    await _db.customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(title, preview, content=notes, content_rowid=rowid)',
    );
  }
}
