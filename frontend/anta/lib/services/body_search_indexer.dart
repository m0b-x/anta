import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../constants/search_constants.dart';
import '../database/daos/note_search_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/item_label.dart';
import 'auto_save_service.dart';
import 'folder_search_service.dart';

/// What the body index's drain waits on and where it computes — injectable
/// so a test drives a whole backfill with no timers and no isolates.
class BodyIndexScheduler {
  /// The pause between two pages of a drain.
  final Future<void> Function() yieldBetweenPages;

  /// Whether an open editor holds text it has not written yet. The drain
  /// waits rather than queue its pages in front of that save.
  final bool Function() editorBusy;

  /// One wait while [editorBusy] holds.
  final Future<void> Function() editorPoll;

  /// Runs a projection or a scoring pass off the UI isolate.
  final Future<R> Function<R>(R Function() work) run;

  const BodyIndexScheduler({
    this.yieldBetweenPages = _yieldBetweenPages,
    this.editorBusy = AutoSaveService.hasAnyPendingChanges,
    this.editorPoll = _editorPoll,
    this.run = _runInIsolate,
  });

  static Future<void> _yieldBetweenPages() =>
      Future<void>.delayed(SearchConstants.bodyIndexPageYield);

  static Future<void> _editorPoll() =>
      Future<void>.delayed(SearchConstants.bodyIndexEditorPoll);

  static Future<R> _runInIsolate<R>(R Function() work) => Isolate.run(work);
}

/// [items] cut into consecutive pages whose [sizeOf] stays within [budget]
/// and whose length stays within [maxItems]; an item larger than [budget] is
/// a page of its own. The count cap matters for a page read by id: a byte
/// budget alone lets tens of thousands of empty notes into one `IN (…)`,
/// past SQLite's limit on bound variables.
Iterable<List<T>> pagesByBytes<T>(
  List<T> items,
  int Function(T item) sizeOf,
  int budget, {
  required int maxItems,
}) sync* {
  var page = <T>[];
  var bytes = 0;
  for (final item in items) {
    final size = sizeOf(item);
    if (page.isNotEmpty && (bytes + size > budget || page.length >= maxItems)) {
      yield page;
      page = <T>[];
      bytes = 0;
    }
    page.add(item);
    bytes += size;
  }
  if (page.isNotEmpty) yield page;
}

typedef _Projected = ({
  String body,
  String title,
  String tags,
  String ledgerTags,
});

List<_Projected> _projectAll(List<(String, String)> notes) => [
  for (final (title, body) in notes) _project(title, body),
];

_Projected _project(String title, String body) {
  final tags = tagColumns(body);
  return (
    body: searchProjection(title, body),
    title: titleProjection(title),
    tags: tags.projection,
    ledgerTags: tags.spelled,
  );
}

/// Keeps the device-local body index (`note_body_fts`, `NoteSearchDao`) in
/// step with the notes, lazily and off the typing path
/// (`docs/scalability-roadmap.md` §5.5 S11).
///
/// Nothing is indexed when a note is written: a write moves the note's
/// `hlc_timestamp`, and a **drain** — after launch, after a database
/// switch, and before a full search when something changed — finds what
/// moved, settles label, move and reorder stamps with one statement, and
/// re-projects only real title and body changes, a page of bodies at a time.
///
/// A singleton on the `DatabaseLifecycle` reset contract: [reset] closes the
/// instance, and every page re-checks the generation it started under after
/// each await, so a switch mid-drain never writes the previous database's
/// notes anywhere.
class BodySearchIndexer {
  final AppDatabase _db;
  final NoteSearchDao _dao;
  final BodyIndexScheduler scheduler;
  final int _pageBytes;
  final int _generation;

  /// Known to have work: set at construction and by [markActiveDirty], so
  /// the next [start] or [ensureFresh] drains without probing first. Never
  /// the only signal — [ensureFresh] probes the ledger whenever it is clear.
  bool _dirty = true;
  bool _closed = false;
  Future<bool>? _available;
  Future<void>? _drain;

  /// Held while the running drain is still bringing the projections up to
  /// date, and dropped before it fills the tags v57 left unread: a search
  /// waits on this part alone, since the tags change none of its answers.
  Completer<void>? _indexing;

  BodySearchIndexer({
    required AppDatabase database,
    this.scheduler = const BodyIndexScheduler(),
    int pageBytes = SearchConstants.bodyIndexPageBytes,
  }) : _db = database,
       _dao = NoteSearchDao(database),
       _pageBytes = pageBytes,
       _generation = DatabaseLifecycle.generation;

  static BodySearchIndexer? _instance;
  static Future<BodySearchIndexer>? _opening;

  /// The indexer over the active database. Built once per database: the
  /// instance is published only after its database is in hand, and an open
  /// a switch overtook starts over on the new one.
  static Future<BodySearchIndexer> getInstance() {
    final instance = _instance;
    if (instance != null) return Future.value(instance);
    return _opening ??= _open();
  }

  static Future<BodySearchIndexer> _open() async {
    final generation = DatabaseLifecycle.generation;
    try {
      final database = await AppDatabase.getInstance();
      if (generation != DatabaseLifecycle.generation) {
        _opening = null;
        return getInstance();
      }
      final indexer = BodySearchIndexer(database: database);
      _instance = indexer;
      DatabaseLifecycle.registerResetHandler(reset);
      return indexer;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static void reset() {
    _instance?.close();
    _instance = null;
    _opening = null;
  }

  /// Starts the backfill for the open database and again for every database
  /// a switch opens. Called once, after the first frame, so a launch never
  /// waits on it.
  static void startAfterLaunch() {
    DatabaseLifecycle.registerSwitchedHandler(_startOnSwitch);
    _startForActiveDatabase();
  }

  static void _startOnSwitch(AppDatabase _) => _startForActiveDatabase();

  static void _startForActiveDatabase() {
    unawaited(
      getInstance().then((indexer) => indexer.start()).catchError((
        Object e,
        StackTrace st,
      ) {
        debugPrint('[BodySearchIndexer] start failed: $e');
      }),
    );
  }

  /// Tells the active database's indexer that notes moved, so its next
  /// search drains without probing first. The note change stream calls it;
  /// a bulk path that moves notes behind the repository may too. Only a
  /// hint — the probe finds every change anyway. Free when no indexer is
  /// open.
  static void markActiveDirty() => _instance?._dirty = true;

  /// [catchUp] on the active database's indexer, for a caller that wants
  /// what is read from the ledger current without owning the index — the
  /// tag catalog, as an editor opens. Free when no indexer is open: never
  /// opens one, and a launch's own drain covers a note opened before it.
  static void catchUpActive() => _instance?.catchUp();

  /// Fires after each page a drain stored and after an orphan sweep that
  /// dropped any row — never for a drain that only settled label and move
  /// stamps — and whenever a path that forgets notes removes their ledger
  /// rows itself ([NoteSearchDao.ledgerChanged]), so what is read from the
  /// ledger (the tag catalog) reads again as the drain goes. Outlives the
  /// indexer a database switch replaces.
  static Stream<void> get changes => NoteSearchDao.ledgerChanges;

  /// Begins a drain in the background when anything may have moved.
  void start() {
    if (_dirty) unawaited(drain());
  }

  /// Brings the index up to date, joining the drain already running. Never
  /// throws: a failed drain is logged and leaves the indexer dirty.
  Future<void> drain() {
    return _drain ??= _runDrain().whenComplete(() => _drain = null);
  }

  /// Completes when no drain is running.
  Future<void> whenIdle() => _drain ?? Future<void>.value();

  /// Completes once the projections are current — the moment a search that
  /// came back incomplete is worth running again: at the end of the running
  /// drain's index pages, at once when only its tag pages remain, and at the
  /// end of the drain when a note moved after its index pages, since only
  /// the drain after it projects that note.
  Future<void> whenIndexed() {
    final indexing = _indexing;
    if (indexing != null) return indexing.future;
    return _dirty ? whenIdle() : Future<void>.value();
  }

  /// Drains, but answers by [budget] at the latest: true when the index is
  /// up to date, false when the drain is still projecting behind the
  /// answer. A drain past its index pages, filling tags alone, holds no
  /// answer back.
  ///
  /// With no drain projecting, one statement asks the ledger whether any
  /// note moved since it was indexed — so an edit is never missed for want
  /// of a flag that the change reached the right indexer, and a search costs
  /// one probe when nothing did.
  Future<bool> ensureFresh(Duration budget) async {
    if (_indexing == null && !_dirty) {
      if (!await _isAvailable() || !await _dao.hasPendingWork()) return true;
      // A drain filling tags is past its index pages: the flag tells
      // [whenIndexed] the moved note waits for the drain after it.
      _dirty = true;
    }
    final drained = _projected().then((_) => true);
    final expired = Completer<bool>();
    final timer = Timer(budget, () => expired.complete(false));
    try {
      return await Future.any([drained, expired.future]);
    } finally {
      timer.cancel();
    }
  }

  /// Completes once a drain has projected what moved: the running drain's
  /// index pages, or — when it is past them, filling tags — the next
  /// drain's. Never more than that next one, so a drain that keeps failing
  /// cannot keep this running behind an answer that has expired.
  Future<void> _projected() async {
    final running = drain();
    final indexing = _indexing;
    if (indexing != null) return indexing.future;
    await running;
    final next = drain();
    await (_indexing?.future ?? next);
  }

  /// The live notes that may match [words] and carry every one of [tags]
  /// whole under the filters: the index's candidates, or every live note in
  /// scope where this database has no index. A superset either way — the
  /// caller scores each body, which is what decides a hit.
  Future<List<Note>> candidates(
    Set<String> words, {
    Set<String> tags = const {},
    Set<String>? folderIds,
    Set<ItemLabel> labels = const {},
  }) async {
    if (await _isAvailable()) {
      return _dao.matching(
        [
          bodyMatchExpression(words),
          tagMatchExpression(tags, whole: true),
        ].where((clause) => clause.isNotEmpty).join(' AND '),
        folderIds: folderIds,
        labels: labels,
      );
    }
    return _dao.liveNotes(folderIds: folderIds, labels: labels);
  }

  /// The catch-up the search surface kicks when it opens, so the drain runs
  /// while the user starts typing and no keystroke ever starts one: a drain
  /// begins only when the in-memory flag says notes moved, joins one already
  /// running, and is never waited for. The full search's [ensureFresh]
  /// still probes the ledger for anything the flag missed.
  void catchUp() {
    if (_dirty) unawaited(drain());
  }

  /// Whether a drain is still projecting notes, so a keystroke's answer may
  /// grow once it settles. Read without a statement. A drain filling tags
  /// alone is not behind: no answer would change. Nor is a dirty index with
  /// no drain: nothing would settle, and a re-run would only repeat the same
  /// query — it waits for the next open or full search, and the
  /// newest-notes scan covers fresh local edits meanwhile.
  bool get mayBeBehind => _indexing != null;

  /// The quick search's hits, best first: the matches of [titleMatch] (an
  /// FTS5 expression confined to the `title` column) cut to [limit], then
  /// those of [match] (over the title, body and tags columns) that are not
  /// among them, cut to [limit] too. Two statements, so a title hit is never
  /// cut behind a body that repeats the word; one when the two expressions
  /// are the same. Null where this database has no index, so the caller
  /// knows nothing more will come from it; throws where the probe could
  /// not tell this time, which is a failed read, not an absent index.
  Future<List<({Note note, double score})>?> quickMatches(
    String titleMatch,
    String match, {
    Set<String>? folderIds,
    Set<ItemLabel> labels = const {},
    required int limit,
  }) async {
    if (!await _isAvailable()) {
      // An unknown answer is not cached, so the next search asks again.
      if (_available == null) {
        throw StateError('the body index could not be probed');
      }
      return null;
    }
    Future<List<({Note note, double score})>> run(String expression) =>
        _dao.quickMatching(
          expression,
          folderIds: folderIds,
          labels: labels,
          limit: limit,
        );
    final titled = titleMatch.isEmpty
        ? const <({Note note, double score})>[]
        : await run(titleMatch);
    if (match.isEmpty || match == titleMatch) return titled;
    final seen = {for (final hit in titled) hit.note.id};
    return [
      ...titled,
      for (final hit in await run(match))
        if (!seen.contains(hit.note.id)) hit,
    ];
  }

  /// [noteIds]' bodies in one read; an unreadable note is absent.
  Future<Map<String, String>> bodies(List<String> noteIds) =>
      _db.contentChunkDao.loadContentForNotes(noteIds);

  /// Runs [work] through [scheduler] when it covers [bytes] of text worth an
  /// isolate, here otherwise. [work] must capture only plain data.
  Future<R> offIsolate<R>(int bytes, R Function() work) {
    if (bytes < SearchConstants.bodyIsolateThresholdBytes) {
      return Future<R>.value(work());
    }
    return scheduler.run(work);
  }

  /// Stops every drain at its next check. The tables keep what was written.
  void close() => _closed = true;

  bool get _isStale => _closed || DatabaseLifecycle.generation != _generation;

  Future<bool> _isAvailable() => _available ??= _probeAvailable();

  /// Whether the FTS table answers a query, settled once per database. A
  /// table this SQLite does not have or cannot use is created again first —
  /// the v48 step swallows a refusal, so a later build whose SQLite has the
  /// trigram tokenizer recovers — and if that fails too the search scores
  /// every note instead of throwing. Any other failure answers no for this
  /// search only: it is not cached, so the next search probes again.
  Future<bool> _probeAvailable() async {
    var capability = await _dao.probeCapability();
    if (capability == BodyIndexCapability.unsupported) {
      await _dao.createTables();
      capability = await _dao.probeCapability();
    }
    if (capability == BodyIndexCapability.unknown) _available = null;
    return capability == BodyIndexCapability.usable;
  }

  Future<void> _runDrain() async {
    _dirty = false;
    final indexing = _indexing = Completer<void>();
    void projected() {
      if (identical(_indexing, indexing)) _indexing = null;
      if (!indexing.isCompleted) indexing.complete();
    }

    try {
      if (!await _isAvailable() || _isStale) return;
      if (await _dao.removeOrphans() > 0) NoteSearchDao.ledgerChanged();
      if (_isStale) return;
      await _dao.touchUnchanged();
      if (_isStale) return;

      // A note written while its page was in flight fails the write's
      // compare-and-set and comes back from the next probe; one this drain
      // already tried waits for the next drain, so an edit storm cannot keep
      // it running.
      final attempted = <int>{};
      var wrote = false;
      // The pause behind an unsaved editor is bounded per drain: a save the
      // row refuses (`SaveRefused`) leaves the editor dirty until it closes,
      // and an unbounded pause would hold every search at its budget with
      // the notice up for that long.
      var paused = Duration.zero;
      // Stores [notes] through [store] a page at a time, each page that
      // wrote announced at once, so a drain a switch or a failure cuts short
      // has still published what it stored. False when a switch overtook it.
      Future<bool> inPages(
        List<StaleBodyNote> notes,
        Future<int?> Function(List<StaleBodyNote> page) store,
      ) async {
        for (final page in pagesByBytes(
          notes,
          (note) => note.contentLength,
          _pageBytes,
          maxItems: SearchConstants.bodyPageMaxNotes,
        )) {
          while (paused < SearchConstants.bodyIndexEditorPauseLimit &&
              scheduler.editorBusy()) {
            await scheduler.editorPoll();
            paused += SearchConstants.bodyIndexEditorPoll;
            if (_isStale) return false;
          }
          final written = await store(page);
          if (written == null) return false;
          attempted.addAll([for (final note in page) note.rowid]);
          if (written > 0) {
            wrote = true;
            NoteSearchDao.ledgerChanged();
          }
          await scheduler.yieldBetweenPages();
          if (_isStale) return false;
        }
        return true;
      }

      while (true) {
        final stale = [
          for (final note in await _dao.staleNotes())
            if (!attempted.contains(note.rowid)) note,
        ];
        if (_isStale) return;
        if (stale.isEmpty) break;
        if (!await inPages(stale, _indexPage)) return;
      }
      projected();
      // The tags v57 left unread, once the projections are current: read
      // from the bodies alone, so the FTS table is never rewritten for them.
      final untagged = await _dao.untaggedNotes();
      if (_isStale || !await inPages(untagged, _tagPage)) return;
      if (wrote) await _dao.checkpoint();
    } catch (e, st) {
      _dirty = true;
      debugPrint('[BodySearchIndexer] drain failed: $e');
      debugPrintStack(stackTrace: st, maxFrames: 10);
    } finally {
      projected();
    }
  }

  /// Reads, projects and stores one page; how many notes it stored, or null
  /// when a switch overtook it.
  ///
  /// A note whose chunks cannot be decoded is settled at its current stamp
  /// with its title alone and an unreadable mark. Left unsettled, it would
  /// keep every later search draining — re-reading it, logging, and
  /// checkpointing — for as long as the note stays broken; a repair arrives
  /// as a write or a merge, which moves the stamp and makes it stale again.
  Future<int?> _indexPage(List<StaleBodyNote> page) async {
    final bodies = await this.bodies([for (final note in page) note.id]);
    if (_isStale) return null;
    final inputs = [
      for (final note in page) (note.title, bodies[note.id] ?? ''),
    ];
    var bytes = 0;
    for (final (title, body) in inputs) {
      bytes += title.length + body.length;
    }
    final texts = await _projectPage(this, inputs, bytes);
    if (_isStale) return null;
    final written = await _dao.writeProjections([
      for (final (i, note) in page.indexed)
        BodyProjection(
          rowid: note.rowid,
          id: note.id,
          hlc: note.hlc,
          text: texts[i].body,
          title: texts[i].title,
          tags: texts[i].tags,
          ledgerTags: texts[i].ledgerTags,
          bodyUnreadable: !bodies.containsKey(note.id),
        ),
    ]);
    return _isStale ? null : written;
  }

  /// Reads one page of [NoteSearchDao.untaggedNotes]' bodies and stores
  /// their tags alone; how many it stored, or null when a switch overtook
  /// it. An unreadable body stores `''`, as its projection would.
  Future<int?> _tagPage(List<StaleBodyNote> page) async {
    final bodies = await this.bodies([for (final note in page) note.id]);
    if (_isStale) return null;
    final texts = [for (final note in page) bodies[note.id] ?? ''];
    var bytes = 0;
    for (final text in texts) {
      bytes += text.length;
    }
    final tags = await _tagsOfPage(this, texts, bytes);
    if (_isStale) return null;
    final written = await _dao.writeTags([
      for (final (i, note) in page.indexed)
        (rowid: note.rowid, id: note.id, hlc: note.hlc, tags: tags[i]),
    ]);
    return _isStale ? null : written;
  }
}

/// [_projectPage]'s shape for the tags alone.
Future<List<String>> _tagsOfPage(
  BodySearchIndexer indexer,
  List<String> bodies,
  int bytes,
) => indexer.offIsolate(
  bytes,
  () => [for (final body in bodies) tagColumns(body).spelled],
);

/// Top-level so the closure handed to an isolate captures the inputs alone,
/// never the indexer and its database.
Future<List<_Projected>> _projectPage(
  BodySearchIndexer indexer,
  List<(String, String)> inputs,
  int bytes,
) => indexer.offIsolate(bytes, () => _projectAll(inputs));
