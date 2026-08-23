import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../constants/vocabularies.dart';
import '../database/daos/vocabulary_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/vocabulary.dart';
import '../models/vocabulary_item.dart';
import 'folder_search_service.dart';

/// Owns `vocabularies` / `vocabulary_items` and publishes them to the
/// synchronous [Vocabularies] facade.
///
/// Same shape as [EventTemplateService]: both (small) tables are read once at
/// [getInstance] and republished after every mutation, so the editor resolves
/// suggestions during a keystroke with no `await`.
///
/// All CRDT stamping lives in [VocabularyDao]; this layer never touches
/// `hlcTimestamp` / `deviceId` / `version` / `isDeleted`, and its cache holds
/// live rows only.
class VocabularyService {
  static VocabularyService? _instance;
  static const Uuid _uuid = Uuid();

  late VocabularyDao _dao;
  List<Vocabulary> _cache = const [];

  VocabularyService._();

  static Future<VocabularyService> getInstance() async {
    if (_instance != null) return _instance!;
    return _create(await AppDatabase.getInstance());
  }

  /// Binds the singleton to an arbitrary [AppDatabase], bypassing
  /// [AppDatabase.getInstance]'s `path_provider` lookup and device-id file.
  ///
  /// Exists so tests can exercise the real DAO, the real CRDT stamping and the
  /// real facade against `NativeDatabase.memory()`. Never use it in app code —
  /// the singleton is what the [DatabaseLifecycle] reset contract is built on.
  @visibleForTesting
  static Future<VocabularyService> forTesting(AppDatabase db) async {
    if (_instance != null) return _instance!;
    return _create(db);
  }

  static Future<VocabularyService> _create(AppDatabase db) async {
    final service = VocabularyService._();
    service._dao = db.vocabularyDao;
    await service._load();
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the cached singleton and clears the static facade, so terms from a
  /// closed database cannot leak into the suggestion bar before the next
  /// [getInstance] republishes. Invoked by [DatabaseLifecycle].
  static void reset() {
    _instance = null;
    Vocabularies.resetCache();
  }

  List<Vocabulary> get vocabularies => _cache;

  Future<void> reload() => _load();

  /// Turns the editor's one-line-per-entry block into a clean list: trimmed,
  /// blank lines dropped, duplicates removed.
  ///
  /// Duplicates are judged **folded**, so "Bench press" typed twice with
  /// different capitalisation collapses to the first spelling — the same
  /// store-verbatim / match-folded rule the suggestion bar uses.
  ///
  /// `;;` section headers survive as ordinary lines (they are non-blank, so
  /// they need no special case here) and are filtered out of suggestions by the
  /// facade instead. They de-duplicate like anything else: two identically
  /// titled headings in one list collapse to the first, which is the same rule
  /// applied consistently rather than a second one to remember.
  static List<String> parseTerms(String raw) {
    final seen = <String>{};
    final terms = <String>[];
    for (final line in const LineSplitter().convert(raw)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (!seen.add(normalizeForSearch(trimmed))) continue;
      terms.add(trimmed);
    }
    return terms;
  }

  /// Renders a term list back into the sheet's editable block.
  static String formatTerms(List<String> terms) => terms.join('\n');

  Future<Vocabulary> createVocabulary({
    required String name,
    List<String> terms = const [],
    bool isEnabled = true,
  }) async {
    final id = _uuid.v4();
    final sortOrder = await _dao.nextSortOrder();
    await _dao.upsertVocabulary(
      VocabulariesCompanion(
        id: Value(id),
        name: Value(name.trim()),
        isEnabled: Value(isEnabled),
        sortOrder: Value(sortOrder),
      ),
    );
    await _dao.saveItems(vocabularyId: id, terms: terms);
    await _load();
    return Vocabularies.byId(id) ??
        Vocabulary(
          id: id,
          name: name.trim(),
          isEnabled: isEnabled,
          sortOrder: sortOrder,
        );
  }

  Future<void> updateVocabulary({
    required String id,
    required String name,
    required List<String> terms,
    required bool isEnabled,
  }) async {
    await _dao.upsertVocabulary(
      VocabulariesCompanion(
        id: Value(id),
        name: Value(name.trim()),
        isEnabled: Value(isEnabled),
      ),
    );
    await _dao.saveItems(vocabularyId: id, terms: terms);
    await _load();
  }

  Future<void> setEnabled(String id, bool isEnabled) async {
    await _dao.upsertVocabulary(
      VocabulariesCompanion(id: Value(id), isEnabled: Value(isEnabled)),
    );
    await _load();
  }

  Future<void> deleteVocabulary(String id) async {
    await _dao.softDeleteVocabularyById(id);
    await _load();
  }

  Future<void> reorder(List<String> orderedIds) async {
    await _dao.reorderVocabularies(orderedIds);
    await _load();
  }

  // ── Cache load ───────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final rows = await _dao.getAllVocabularies();
      final itemRows = await _dao.getAllItems();

      final itemsByVocabulary = <String, List<VocabularyItem>>{};
      for (final row in itemRows) {
        (itemsByVocabulary[row.vocabularyId] ??= <VocabularyItem>[]).add(
          VocabularyItem(
            id: row.id,
            vocabularyId: row.vocabularyId,
            term: row.term,
            sortOrder: row.sortOrder,
          ),
        );
      }

      _cache = List.unmodifiable([
        for (final row in rows)
          Vocabulary(
            id: row.id,
            name: row.name,
            isEnabled: row.isEnabled,
            sortOrder: row.sortOrder,
            items: List.unmodifiable(itemsByVocabulary[row.id] ?? const []),
          ),
      ]);
    } catch (e) {
      debugPrint('[VocabularyService] Load error: $e');
      _cache = const [];
    }
    Vocabularies.updateCache(_cache);
  }

  // ── Backup export / import ───────────────────────────────────────────

  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getAllVocabularies();
    final itemRows = await _dao.getAllItems();

    final itemsByVocabulary = <String, List<Map<String, dynamic>>>{};
    for (final row in itemRows) {
      (itemsByVocabulary[row.vocabularyId] ??= <Map<String, dynamic>>[]).add({
        'id': row.id,
        'term': row.term,
        'sortOrder': row.sortOrder,
        'createdAtMs': row.createdAt.millisecondsSinceEpoch,
        'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
      });
    }

    return [
      for (final row in rows)
        {
          'id': row.id,
          'name': row.name,
          'isEnabled': row.isEnabled,
          'sortOrder': row.sortOrder,
          'createdAtMs': row.createdAt.millisecondsSinceEpoch,
          'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
          'items': itemsByVocabulary[row.id] ?? const <Map<String, dynamic>>[],
        },
    ];
  }

  /// Replaces every vocabulary with [data]. Malformed rows are skipped.
  Future<void> importData(List<dynamic> data) async {
    await _dao.deleteAll();
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      try {
        final id = map['id'] as String?;
        final name = map['name'] as String?;
        if (id == null || name == null) continue;

        final createdMs = map['createdAtMs'] is int
            ? map['createdAtMs'] as int
            : DateTime.now().millisecondsSinceEpoch;
        final updatedMs = map['updatedAtMs'] is int
            ? map['updatedAtMs'] as int
            : createdMs;

        await _dao.importVocabulary(
          VocabulariesCompanion(
            id: Value(id),
            name: Value(name),
            isEnabled: Value(map['isEnabled'] as bool? ?? true),
            sortOrder: Value(
              map['sortOrder'] is int ? map['sortOrder'] as int : 0,
            ),
            createdAt: Value(_fromMs(createdMs)),
            updatedAt: Value(_fromMs(updatedMs)),
          ),
        );

        final items = map['items'];
        if (items is! List) continue;
        for (var i = 0; i < items.length; i++) {
          final rawItem = items[i];
          if (rawItem is! Map) continue;
          final itemMap = rawItem.cast<String, dynamic>();
          final term = itemMap['term'] as String?;
          if (term == null || term.trim().isEmpty) continue;

          final itemCreatedMs = itemMap['createdAtMs'] is int
              ? itemMap['createdAtMs'] as int
              : createdMs;
          final itemUpdatedMs = itemMap['updatedAtMs'] is int
              ? itemMap['updatedAtMs'] as int
              : itemCreatedMs;

          await _dao.importItem(
            VocabularyItemsCompanion(
              id: Value(itemMap['id'] as String? ?? _uuid.v4()),
              vocabularyId: Value(id),
              term: Value(term),
              sortOrder: Value(
                itemMap['sortOrder'] is int ? itemMap['sortOrder'] as int : i,
              ),
              createdAt: Value(_fromMs(itemCreatedMs)),
              updatedAt: Value(_fromMs(itemUpdatedMs)),
            ),
          );
        }
      } catch (e) {
        debugPrint('[VocabularyService] Import row error: $e');
      }
    }
    await _load();
  }

  /// Empties the tables when a backup carries no vocabularies but the caller
  /// still wants the restore to be authoritative.
  Future<void> clearAllForImport() async {
    await _dao.deleteAll();
    await _load();
  }

  static DateTime _fromMs(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}
