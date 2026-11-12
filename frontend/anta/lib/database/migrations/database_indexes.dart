import 'package:flutter/foundation.dart' show debugPrint;

import '../database.dart';

class DatabaseIndexes {
  final AppDatabase _db;

  DatabaseIndexes(this._db);

  Future<void> createAllIndexes() async {
    await _createFolderIndexes();
    await _createNoteIndexes();
    await _createChunkIndexes();
    await createChunkHashIndex();
    await _createOutboxIndexes();
    await createCounterIndexes();
    await createCounterValueNoteIndex();
    await createCategoryIndexes();
    await createCalendarIndexes();
    await createCalendarDeltaIndexes();
    await createAlertIndexes();
    await createCategoryAlertIndexes();
    await createCategoryProfileIndexes();
    await createBodySearchTables();
    await createUniqueNameIndexes();
    await createNoteTitleIndex();
    await createPositionIndexes();
    await createShareMarkIndexes();
  }

  /// The events and folders that carry a share mark, tombstones included,
  /// as two partial indexes (**v53**): every sync page and push of a
  /// shareable table first asks whether anything is marked at all, and for
  /// nearly every database the answer is an empty index rather than a scan
  /// of two tables (`docs/cloud-sharing-foundations.md` §3). The queries
  /// repeat `shared_pair IS NOT NULL` literally, which is what lets SQLite
  /// prove the partial index applies.
  Future<void> createShareMarkIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_folders_shared_pair '
      'ON folders(shared_pair) WHERE shared_pair IS NOT NULL',
    );
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_calendar_events_shared_pair '
      'ON calendar_events(shared_pair) WHERE shared_pair IS NOT NULL',
    );
  }

  /// The body search index's two tables on a fresh install and in the v50
  /// step, which recreates the FTS table in this shape (the v48 step keeps
  /// its one-column DDL frozen in its own copy). Defensive: a SQLite without
  /// the trigram tokenizer refuses the virtual table, the database must open
  /// regardless, and the indexer reads the table's absence as "search the
  /// old way".
  ///
  /// Three columns, in the order the quick search's `bm25()` weighs them:
  /// `title` (the title's tokens alone, so a title hit can outrank a body
  /// hit), `body` (the title's and the body's tokens — the full search's
  /// projection, matched by that column alone) and `tags` (the body's
  /// `#tags`, folded, which only narrow).
  ///
  /// `case_sensitive 1` because the projection is folded and lower-cased in
  /// Dart before it is stored, as the query is: SQLite's own case folding
  /// could only make two strings Dart keeps apart match.
  Future<void> createBodySearchTables() async {
    await _db.customStatement(
      'CREATE TABLE IF NOT EXISTS note_search_ledger ('
      'note_rowid INTEGER PRIMARY KEY, note_id TEXT NOT NULL, '
      'indexed_hlc TEXT NOT NULL, fingerprint TEXT NOT NULL)',
    );
    try {
      await _db.customStatement(
        'CREATE VIRTUAL TABLE IF NOT EXISTS note_body_fts USING fts5('
        "title, body, tags, tokenize='trigram case_sensitive 1', "
        "content='', contentless_delete=1)",
      );
    } catch (e) {
      debugPrint('[DatabaseIndexes] body index unavailable: $e');
    }
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
      'CREATE INDEX IF NOT EXISTS idx_folders_hlc ON folders(hlc_timestamp)',
    );
  }

  Future<void> _createNoteIndexes() async {
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

  /// Full, not partial on live rows, since **v47**: a tombstoned note's
  /// chunks are deleted, so every row is live and a predicate would buy
  /// nothing but the bound-parameter miss recorded on
  /// [createCalendarDeltaIndexes]. The v47 step carries its own frozen copy.
  Future<void> _createChunkIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_content_chunks_note '
      'ON content_chunks(note_id, chunk_index)',
    );
  }

  /// The push order `SyncOutboxDao.pending` reads in and resumes from
  /// (**v47**), so a drain's every page is a range seek rather than a sort of
  /// the whole queue. The v47 step carries its own frozen copy.
  Future<void> _createOutboxIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_outbox_order '
      'ON sync_outbox(hlc, table_name, row_key)',
    );
  }

  /// The index a chunk is found by its content hash through (**v46**): the
  /// chunked sync wire names a chunk by that hash. Plain, not unique — two
  /// notes, or two places in one note, may hold the same text. Called by the
  /// v46 step and by `createAllIndexes`, so both paths build one definition.
  Future<void> createChunkHashIndex() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_content_chunks_hash '
      'ON content_chunks(content_hash)',
    );
  }

  /// The counter indexes, partial on live rows since **v43**, when both tables
  /// became CRDT-shaped and every `CounterDao` read started filtering
  /// tombstones. Public because the v43 step calls it; v6 creates
  /// `idx_counter_values_counter` in its own frozen full shape, and v43 drops
  /// it by name before this recreates it, so upgraders and fresh installs end
  /// on one definition.
  ///
  /// Both follow their list's ordering — pinned first, then position — so
  /// `getAllCounters` and `getValuesForCounterOrdered` read in index order
  /// without a temp B-tree; the values index's `counter_id` prefix still
  /// serves the unordered per-counter read. Both predicates are the literal
  /// `is_deleted = 0` the DAO spells, for the bound-parameter reason recorded
  /// on [createCalendarDeltaIndexes].
  Future<void> createCounterIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_counter_values_counter '
      'ON counter_values(counter_id, is_pinned DESC, position) '
      'WHERE is_deleted = 0',
    );
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_counters_active '
      'ON counters(is_pinned DESC, position) WHERE is_deleted = 0',
    );
  }

  /// The live values by note (**v49**): a note delete tombstones its values
  /// by `note_id` (S20), and `getValuesForNote` reads them so, which the
  /// `counter_id`-led index cannot serve. Public because the v49 step calls
  /// it, so both paths build one definition.
  Future<void> createCounterValueNoteIndex() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_counter_values_note '
      'ON counter_values(note_id) WHERE is_deleted = 0',
    );
  }

  /// The category catalog's index (**v43**), partial on live rows and keyed by
  /// `CalendarCategoryDao.getAll`'s `(sort_order, id)` ordering. Public because
  /// the v43 step calls it, so both paths build one definition.
  Future<void> createCategoryIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_calendar_categories_active '
      'ON calendar_categories(sort_order, id) WHERE is_deleted = 0',
    );
  }

  /// Indexes for the calendar feature. Public because the v27 migration calls
  /// this directly so existing installs get the index without re-running the
  /// full `createAllIndexes` path. v10 does **not**: it creates the index in
  /// its own frozen v10 shape, because this definition names `is_deleted`, a
  /// column `calendar_events` only gains in v27.
  ///
  /// Partial since v27: `CalendarEventDao.getAll` is the single read path and
  /// it filters tombstones, so the index only has to cover live rows.
  /// `getAll`'s predicate must restate `is_deleted = 0` exactly or SQLite
  /// silently drops to a scan plus a temp B-tree for the ordering — the v27
  /// migration drops the full index by name first so upgraders and fresh
  /// installs cannot end up on different definitions.
  ///
  /// Scoped to `calendar_events` on purpose: v27 calls this before
  /// `calendar_event_skips` exists (v30), so anything touching the delta
  /// tables belongs in [createCalendarDeltaIndexes] instead.
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
  /// v27 migration, where `calendar_event_skips` does not exist yet (v30).
  ///
  /// Called by `createAllIndexes` and by the v37 step only. v31, which first
  /// introduced these indexes, creates them in its own frozen two-column shape:
  /// this definition follows the live schema, and a step older than the column
  /// it names cannot run it.
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

  /// The three indexes behind event alerts (**v40**). Public because the v40
  /// migration calls this directly, so upgraders and fresh installs get the
  /// same definitions from the same place.
  ///
  /// `idx_calendar_event_alerts_active` is partial on live rows for the reason
  /// every other CRDT table's is: tombstones are never collected, and the two
  /// per-event statements that matter — the live read the editor and the
  /// facade refresh do, and the `replaceForEvent` / delete cascade update —
  /// both filter them out. The predicate is spelled as the literal
  /// `is_deleted = 0` rather than through Drift's `.equals(false)`: that emits
  /// a bound `?`, and whether SQLite can prove a bound parameter implies a
  /// partial index's `WHERE` is version-dependent (3.53 can, the version
  /// shipping to Android cannot). Every statement that wants this index spells
  /// the same literal.
  ///
  /// `idx_alert_registrations_pending` is partial on `state = 'pending'` and
  /// keyed by `fire_at`, which is the whole of the reconcile read: the pending
  /// set, soonest first. Being partial keeps it to the handful of live
  /// registrations instead of every `fired`/`stopped` row waiting for the
  /// 7-day sweep, and being keyed by `fire_at` is what spares the ordering a
  /// temp B-tree.
  ///
  /// `idx_alert_registrations_event` serves the per-event cascade and
  /// re-registration; it is a plain index because those statements do not
  /// filter by state.
  Future<void> createAlertIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_calendar_event_alerts_active '
      'ON calendar_event_alerts(event_id) WHERE is_deleted = 0',
    );
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_alert_registrations_pending '
      "ON alert_registrations(fire_at) WHERE state = 'pending'",
    );
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_alert_registrations_event '
      'ON alert_registrations(event_id)',
    );
  }

  /// The index behind `CategoryAlertDao`'s per-category writes — the
  /// `replaceForCategory` read and the `deleteCategory` cascade (**v42**).
  ///
  /// A creator of its own, not a line in [createAlertIndexes]: the v40 step
  /// calls that one before `calendar_category_alerts` exists, and an old step
  /// must never reach a table a later one creates. Called by the v42 step and
  /// by `createAllIndexes`, so both paths build one definition.
  ///
  /// Plain rather than partial on live rows, as the record's DDL has it: the
  /// whole table is read once into the facade, and the writes that use this
  /// index want the category's tombstones too (a re-added id resurrects its
  /// row).
  Future<void> createCategoryAlertIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_calendar_category_alerts_category '
      'ON calendar_category_alerts(category_id)',
    );
  }

  /// The index behind `CategoryProfileDao`'s per-category reads and writes —
  /// the upsert's live-row read and the `deleteCategory` cascade (**v44**).
  ///
  /// [createCategoryAlertIndexes]'s twin and for its reasons: a creator of
  /// its own so no older step can reach the table, called by the v44 step and
  /// by `createAllIndexes`. Plain, not unique: two devices may each hold a
  /// live profile for one category until a local write converges them, and a
  /// merge must be able to store both.
  Future<void> createCategoryProfileIndexes() async {
    await _db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_calendar_category_profiles_category '
      'ON calendar_category_profiles(category_id)',
    );
  }
}
