import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/shared_refresh_constants.dart';
import '../database/daos/sync_dao.dart';
import '../database/database.dart';
import '../models/share_notice.dart';
import 'database_manager.dart';

/// What a check found while no app ran to say it, kept with the database
/// and said at the next open (`docs/cloud-shared-freshness.md`, decision
/// f): never a system notification.
///
/// The notices are one row of the database they arrived under
/// ([SyncDao.keyShareNoticesKept]), so they are said under no other. Which
/// databases hold any is a list in the install's preferences, written
/// before the row: the app asks that list — in memory once the launch has
/// read its preferences — before it reads anything, so a database that
/// never kept a notice, an account that never paired above all, pays no
/// statement at a start or a resume.
abstract final class KeptShareNotices {
  static const String _prefsKey = 'share_notices_kept_in';

  /// Adds [notice] to what [db] — open under [databaseName] — keeps, in one
  /// transaction: merged by id, an event's latest title the one kept, the
  /// newest [kShareNoticesKeptMax] of each kind.
  static Future<void> keep(
    AppDatabase db,
    String databaseName,
    ShareNotice notice,
  ) async {
    // The list first: a run killed between the two leaves a name with
    // nothing behind it, which costs the next open one read — the other
    // order would leave a notice nobody ever looks for.
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList(_prefsKey) ?? const <String>[];
    if (!names.contains(databaseName)) {
      await prefs.setStringList(_prefsKey, [...names, databaseName]);
    }
    await db.transaction(() async {
      final kept = _Kept.decode(
        await db.syncDao.getValue(SyncDao.keyShareNoticesKept),
      )..add(notice);
      await db.syncDao.setValue(SyncDao.keyShareNoticesKept, kept.encode());
    });
  }

  /// What the active database keeps, taken: read and cleared together, the
  /// leave before the arrival. Nothing, and nothing read, unless the
  /// install's list names the active database.
  ///
  /// [activeName] and [open] stand in for the install's database manager
  /// and the open database in a suite.
  static Future<List<ShareNotice>> takeForActiveDatabase({
    Future<String> Function()? activeName,
    Future<AppDatabase> Function() open = AppDatabase.getInstance,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList(_prefsKey);
    if (names == null || names.isEmpty) return const [];
    final active = activeName != null
        ? await activeName()
        : (await DatabaseManager.getInstance()).getActiveDatabaseName();
    if (!names.contains(active)) return const [];
    final notices = await take(await open());
    await prefs.setStringList(_prefsKey, [
      for (final name in prefs.getStringList(_prefsKey) ?? const <String>[])
        if (name != active) name,
    ]);
    return notices;
  }

  /// What [db] keeps, read and cleared in one transaction.
  static Future<List<ShareNotice>> take(AppDatabase db) {
    return db.transaction(() async {
      final stored = await db.syncDao.getValue(SyncDao.keyShareNoticesKept);
      if (stored == null) return const <ShareNotice>[];
      await db.syncDao.deleteValue(SyncDao.keyShareNoticesKept);
      return _Kept.decode(stored).notices();
    });
  }
}

/// The stored shape: `l` the leaves and `e` the events that arrived, each a
/// list of `[id, title]`; `n` the name the leaves are told with; `c` the
/// categories that arrived. Anything unreadable is nothing kept.
class _Kept {
  final Map<String, String> left = {};
  String? leftName;
  final List<String> categories = [];
  final Map<String, String> events = {};

  static _Kept decode(String? stored) {
    final kept = _Kept();
    if (stored == null) return kept;
    try {
      final json = jsonDecode(stored);
      if (json is! Map) return kept;
      kept.left.addAll(_pairs(json['l']));
      kept.events.addAll(_pairs(json['e']));
      final name = json['n'];
      if (name is String) kept.leftName = name;
      final categories = json['c'];
      if (categories is List) {
        kept.categories.addAll(categories.whereType<String>());
      }
    } on FormatException {
      // Nothing kept.
    }
    return kept;
  }

  static Map<String, String> _pairs(Object? list) => {
    if (list is List)
      for (final pair in list)
        if (pair case [final String id, final String title]) id: title,
  };

  void add(ShareNotice notice) {
    switch (notice) {
      case ShareArrived(:final categoryIds, events: final arrived):
        for (final id in categoryIds) {
          categories
            ..remove(id)
            ..add(id);
        }
        for (final event in arrived) {
          _put(events, event);
        }
      case ShareLeftWithAlert(events: final gone, :final partnerName):
        for (final event in gone) {
          _put(left, event);
          // It is not here any more: its arrival is no news.
          events.remove(event.id);
        }
        leftName = partnerName ?? leftName;
      // The person's own act on this phone, said by its bar as it happens:
      // a run without the app hides nothing, so there is none to keep.
      case ShareHiddenWithAlerts():
        break;
    }
    _cap(left);
    _cap(events);
    while (categories.length > kShareNoticesKeptMax) {
      categories.removeAt(0);
    }
  }

  /// Last in, so the cap drops the oldest.
  static void _put(Map<String, String> into, ShareNoticeEvent event) {
    into
      ..remove(event.id)
      ..[event.id] = event.title;
  }

  static void _cap(Map<String, String> map) {
    while (map.length > kShareNoticesKeptMax) {
      map.remove(map.keys.first);
    }
  }

  String encode() => jsonEncode({
    'l': [
      for (final MapEntry(key: id, value: title) in left.entries) [id, title],
    ],
    'n': ?leftName,
    'c': categories,
    'e': [
      for (final MapEntry(key: id, value: title) in events.entries) [id, title],
    ],
  });

  List<ShareNotice> notices() => [
    if (left.isNotEmpty)
      ShareLeftWithAlert([
        for (final MapEntry(key: id, value: title) in left.entries)
          (id: id, title: title),
      ], partnerName: leftName),
    if (categories.isNotEmpty || events.isNotEmpty)
      ShareArrived(
        categoryIds: List.unmodifiable(categories),
        events: [
          for (final MapEntry(key: id, value: title) in events.entries)
            (id: id, title: title),
        ],
      ),
  ];
}
