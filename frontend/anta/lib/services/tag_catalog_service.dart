import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/tag_catalog.dart';
import '../database/daos/note_search_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/catalog_tag.dart';
import 'body_search_indexer.dart';
import 'folder_search_service.dart';

/// Every tag the live notes carry, with how many notes carry it, published
/// to the synchronous [TagCatalog] facade for the editor's `#…`
/// suggestions.
///
/// Kept by the body index's own pass, never by a note write: the drain stores
/// each note's tags on its ledger row (`NoteSearchDao.writeProjections`), and
/// this reads them back in one statement whenever ledger rows were stored or
/// removed ([BodySearchIndexer.changes]). So a tag typed into a note joins
/// the catalog once the drain has caught that note up — after launch, a
/// switch, as an editor opens ([prime]), or before a full search. Where
/// this SQLite has no trigram tokenizer the drain never runs: the catalog
/// shows whatever tags the ledger was carried in with (a `.db` from a phone
/// that had one) and never updates.
class TagCatalogService {
  TagCatalogService._(this._dao);

  final NoteSearchDao _dao;
  StreamSubscription<void>? _drains;
  List<CatalogTag> _tags = const [];

  /// The [refresh] in flight, and whether a call arrived during it.
  Future<void>? _refreshing;
  bool _refreshAgain = false;

  static TagCatalogService? _instance;

  /// The open in flight, shared by every caller that arrives before it
  /// finishes.
  static Future<TagCatalogService>? _opening;

  /// How many times [_open] starts over before it gives up on a database
  /// that keeps switching under it.
  static const int _openAttempts = 3;

  /// The catalog over the active database, read once per database before it
  /// is published (`SettingsService.getInstance`'s shape).
  static Future<TagCatalogService> getInstance() {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    final inFlight = _opening;
    if (inFlight != null) return inFlight;
    final opening = _open();
    _opening = opening;
    // Only this open's own entry is cleared: a reset during it may already
    // have let a newer open take the slot.
    void settle() {
      if (identical(_opening, opening)) _opening = null;
    }

    opening.then<void>((_) => settle(), onError: (Object _) => settle());
    return opening;
  }

  /// What an editor asks as it opens with Autocomplete on, never awaited by
  /// its mount: the catalog, and the search index catching up on what was
  /// written since its last drain — whose pages are what bring a tag saved
  /// in another note here; nothing else would before the next launch,
  /// switch or search. The catch-up keeps every rule of the drain (it starts
  /// only when notes moved and pauses behind an unsaved editor) and is asked
  /// only once the catalog listens, so no page it stores goes unheard.
  ///
  /// An instance this call opened, or joined opening, has just read the
  /// ledger and is not read again; one already open reads again, so a read
  /// that failed earlier does not hold until the next drain.
  static Future<void> prime() async {
    final open = _instance;
    final catalog = await getInstance();
    BodySearchIndexer.catchUpActive();
    if (identical(catalog, open)) await catalog.refresh();
  }

  /// Publishes only a catalog no switch overtook, its read included: one
  /// that did may hold the closing database's tags, which the reset has just
  /// cleared from the facade.
  static Future<TagCatalogService> _open() async {
    for (var attempt = 0; attempt < _openAttempts; attempt++) {
      final generation = DatabaseLifecycle.generation;
      final db = await AppDatabase.getInstance();
      final raced = _instance;
      if (raced != null) return raced;
      if (DatabaseLifecycle.generation != generation) continue;
      final service = TagCatalogService._(NoteSearchDao(db));
      final tags = await service._read();
      if (DatabaseLifecycle.generation != generation) continue;
      // An open a reset left running and one started after it both read;
      // only the first to finish publishes and subscribes.
      final published = _instance;
      if (published != null) return published;
      return service._take(tags);
    }
    throw StateError('the database switched while the tag catalog was read');
  }

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup. Exists so tests can
  /// read a real ledger in `NativeDatabase.memory()`; never use it in app
  /// code — the singleton is what the [DatabaseLifecycle] reset contract is
  /// built on.
  @visibleForTesting
  static Future<TagCatalogService> forTesting(AppDatabase db) async {
    final existing = _instance;
    if (existing != null) return existing;
    final service = TagCatalogService._(NoteSearchDao(db));
    return service._take(await service._read());
  }

  TagCatalogService _take(List<CatalogTag>? tags) {
    if (tags != null) _publish(tags);
    _drains = BodySearchIndexer.changes.listen((_) => unawaited(refresh()));
    _instance = this;
    DatabaseLifecycle.registerResetHandler(reset);
    return this;
  }

  /// Drops the singleton, stops it hearing drains and clears the facade.
  /// Invoked by [DatabaseLifecycle].
  static void reset() {
    _instance?._drains?.cancel();
    _instance = null;
    _opening = null;
    TagCatalog.resetCache();
  }

  /// What [TagCatalog.all] publishes.
  List<CatalogTag> get tags => _tags;

  /// Reads the ledger again and publishes it. A failed read keeps the tags
  /// as they were held and publishes nothing — an empty catalog would take
  /// every suggestion away until the next drain — and an instance a switch
  /// dropped never publishes, or the closed database's tags would come back
  /// into the facade the switch had just cleared.
  ///
  /// Calls coalesce: a backfill signals once per indexed batch, and one read
  /// per signal was a whole-ledger read each on the UI isolate. A call while
  /// a read runs only asks for one more pass after it — a later read sees
  /// every write the skipped ones would have — and shares its future.
  Future<void> refresh() {
    final running = _refreshing;
    if (running != null) {
      _refreshAgain = true;
      return running;
    }
    final refreshing = _refreshLoop();
    _refreshing = refreshing;
    return refreshing;
  }

  /// Passes again only while this is still the singleton: a reset during a
  /// pass leaves nothing to publish to, and the database it would read is
  /// closing.
  Future<void> _refreshLoop() async {
    try {
      do {
        _refreshAgain = false;
        final tags = await _read();
        if (tags != null && identical(_instance, this)) _publish(tags);
      } while (_refreshAgain && identical(_instance, this));
    } finally {
      _refreshing = null;
    }
  }

  void _publish(List<CatalogTag> tags) {
    _tags = tags;
    TagCatalog.updateCache(tags);
  }

  /// Whole-ledger reads, across every instance — the cost seam that proves
  /// an editor's first open reads once. Counted in debug builds only.
  @visibleForTesting
  static int debugLedgerReads = 0;

  /// The catalog, or null when the read failed.
  Future<List<CatalogTag>?> _read() async {
    assert(() {
      debugLedgerReads++;
      return true;
    }());
    try {
      return _tally(await _dao.catalogTags());
    } catch (e) {
      debugPrint('[TagCatalogService] read failed: $e');
      return null;
    }
  }

  /// [rows] — one note's ledger tags each, every folded form once, as the
  /// drain writes them — counted per folded tag, each under the spelling
  /// most notes use (a tie to the one that sorts first), most notes first,
  /// then by the folded form — so `alpha` comes before `Mobility` — and then
  /// by that spelling.
  static List<CatalogTag> _tally(List<String> rows) {
    final spellings = <String, Map<String, int>>{};
    for (final row in rows) {
      for (final tag in row.split(' ')) {
        if (tag.isEmpty) continue;
        final counts = spellings[normalizeForSearch(tag)] ??= {};
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final tags = [
      for (final MapEntry(key: folded, value: counts) in spellings.entries)
        CatalogTag(
          tag: _majority(counts),
          folded: folded,
          noteCount: counts.values.fold(0, (sum, n) => sum + n),
        ),
    ];
    tags.sort((a, b) {
      final byNotes = b.noteCount.compareTo(a.noteCount);
      if (byNotes != 0) return byNotes;
      final byFolded = a.folded.compareTo(b.folded);
      return byFolded != 0 ? byFolded : a.tag.compareTo(b.tag);
    });
    return List.unmodifiable(tags);
  }

  static String _majority(Map<String, int> counts) {
    String? best;
    var most = 0;
    for (final MapEntry(key: spelling, value: n) in counts.entries) {
      if (n > most || (n == most && spelling.compareTo(best!) < 0)) {
        best = spelling;
        most = n;
      }
    }
    return best!;
  }
}
