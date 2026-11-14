import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/shared_refresh_constants.dart';
import '../database/daos/sync_dao.dart';
import '../database/database.dart';
import '../models/share_notice.dart';
import 'database_manager.dart';
import 'fresh_preferences.dart';
import 'shared_refresh/shared_refresh_scheduler.dart';

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
///
/// **Reading clears nothing.** A notice is forgotten only once the app says
/// it was dealt with — said, or dropped as undone at the moment it would
/// have been said ([forgetForActiveDatabase]) — and then by id, so what a
/// run kept meanwhile stays for its own turn. Cleared as it was read, a
/// notice whose bar never showed — the app closed under a dialog, a sheet,
/// an alert, an Undo — was lost for good.
abstract final class KeptShareNotices {
  static const String _prefsKey = 'share_notices_kept_in';

  static final StreamController<void> _prompts =
      StreamController<void>.broadcast();

  /// Told when the store may hold something new while the app is in front
  /// ([prompt]); whoever says the notices reads it again.
  static Stream<void> get prompts => _prompts.stream;

  /// A run kept notices behind a live app — it took the app for dead, and
  /// the app has just caught up (`SharedRefreshApp.caughtUp`): they are
  /// read now, not at a return that may be hours away. A relay like
  /// `ShareService.notify`, with nobody listening where no app runs.
  static void prompt() => _prompts.add(null);

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
    await _name(prefs, databaseName);
    await db.transaction(() async {
      final kept = _Kept.decode(
        await db.syncDao.getValue(SyncDao.keyShareNoticesKept),
      )..add(notice);
      await db.syncDao.setValue(SyncDao.keyShareNoticesKept, kept.encode());
    });
    // And again after it: the app, in its own isolate, may have taken the
    // name off in between, for the row it had just emptied ([_unname]).
    await _name(prefs, databaseName);
  }

  /// What the active database keeps, the leave before the arrival: read,
  /// never cleared. Nothing, and nothing read, unless the install's list
  /// names the active database.
  ///
  /// A name with nothing behind it — a run killed before its row, a row
  /// nobody can read — is taken off here, so it costs one read once. So is
  /// the name of a database that no longer [exists]: its row went with its
  /// file, and nobody would ever have looked.
  ///
  /// Where a run can exist the list is read off the platform's store
  /// ([_names]): the run names the database from an isolate of its own,
  /// and this one's copy of the preferences never saw that — a notice kept
  /// behind a live app was said only once the process had died.
  ///
  /// [activeName], [open] and [exists] stand in for the install's database
  /// manager and the open database in a suite.
  static Future<List<ShareNotice>> forActiveDatabase({
    Future<String> Function()? activeName,
    Future<AppDatabase> Function() open = AppDatabase.getInstance,
    Future<bool> Function(String name)? exists,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final names = await _names(prefs);
    if (names.isEmpty) return const [];
    final active = await _active(activeName);
    await _prune(prefs, names, active, exists);
    if (!names.contains(active)) return const [];
    final db = await open();
    final stored = await db.syncDao.getValue(SyncDao.keyShareNoticesKept);
    final notices = _Kept.decode(stored).notices();
    if (notices.isEmpty) {
      await forget(db, const KeptNoticesSaid());
      await _unname(prefs, db, active);
    }
    return notices;
  }

  /// Forgets what the app dealt with of the active database's notices, and
  /// that alone. Nothing, and no statement, unless the install's list names
  /// the active database: saying a notice that was never kept costs none.
  static Future<void> forgetForActiveDatabase(
    KeptNoticesSaid said, {
    Future<String> Function()? activeName,
    Future<AppDatabase> Function() open = AppDatabase.getInstance,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final names = await _names(prefs);
    if (names.isEmpty) return;
    final active = await _active(activeName);
    if (!names.contains(active)) return;
    final db = await open();
    if (await forget(db, said)) await _unname(prefs, db, active);
  }

  /// Takes [said] out of what [db] keeps, in one transaction, and the row
  /// with its last notice. True when nothing is kept any more.
  static Future<bool> forget(AppDatabase db, KeptNoticesSaid said) {
    return db.transaction(() async {
      final stored = await db.syncDao.getValue(SyncDao.keyShareNoticesKept);
      if (stored == null) return true;
      final kept = _Kept.decode(stored)..remove(said);
      if (kept.isEmpty) {
        await db.syncDao.deleteValue(SyncDao.keyShareNoticesKept);
        return true;
      }
      await db.syncDao.setValue(SyncDao.keyShareNoticesKept, kept.encode());
      return false;
    });
  }

  static Future<String> _active(Future<String> Function()? activeName) async =>
      activeName != null
      ? await activeName()
      : (await DatabaseManager.getInstance()).getActiveDatabaseName();

  /// The list as the platform's store holds it now ([FreshPreferences]):
  /// both isolates write it, and neither's copy of the preferences is
  /// replaced to read it.
  static Future<List<String>> _freshNames() async =>
      (await FreshPreferences.read()).getStringList(_prefsKey) ??
      const <String>[];

  /// The list as the app goes by at a start, a return and a saying: off
  /// the store where a run can exist
  /// ([SharedRefreshAvailability.runsCanExist]) — one platform call, no
  /// statement — and from this isolate's own copy elsewhere: an install
  /// where no run can exist has nobody else writing it, and asks the
  /// platform nothing.
  static Future<List<String>> _names(SharedPreferences prefs) async =>
      await SharedRefreshAvailability.runsCanExist()
      ? await _freshNames()
      : prefs.getStringList(_prefsKey) ?? const <String>[];

  /// Puts [name] on the list as the store holds it now, since the other
  /// isolate writes it too.
  static Future<void> _name(SharedPreferences prefs, String name) async {
    final names = await _freshNames();
    if (names.contains(name)) return;
    await prefs.setStringList(_prefsKey, [...names, name]);
  }

  /// Takes [name] off the list once [db] keeps nothing — and looks at the
  /// row again afterwards. The row and the list are not one step, and a run
  /// may keep between the two: it names the database before its row and
  /// again after it ([keep]), this looks for a row after the name is off,
  /// so whichever of the two comes last sees the other, and no row is left
  /// that nobody looks for.
  static Future<void> _unname(
    SharedPreferences prefs,
    AppDatabase db,
    String name,
  ) async {
    final names = await _freshNames();
    if (names.contains(name)) {
      await prefs.setStringList(_prefsKey, [
        for (final other in names)
          if (other != name) other,
      ]);
    }
    if (await db.syncDao.getValue(SyncDao.keyShareNoticesKept) != null) {
      await _name(prefs, name);
    }
  }

  /// Takes the names of databases that are gone off the list. Never the
  /// active one's, and nothing when the files cannot be asked about.
  static Future<void> _prune(
    SharedPreferences prefs,
    List<String> names,
    String active,
    Future<bool> Function(String name)? exists,
  ) async {
    try {
      final manager = exists == null
          ? await DatabaseManager.getInstance()
          : null;
      final gone = <String>{};
      for (final name in names) {
        if (name == active) continue;
        final there = exists != null
            ? await exists(name)
            : await manager!.databaseExists(name);
        if (!there) gone.add(name);
      }
      if (gone.isEmpty) return;
      await prefs.setStringList(_prefsKey, [
        for (final name in await _freshNames())
          if (!gone.contains(name)) name,
      ]);
    } catch (_) {
      // Pruned at a later open.
    }
  }
}

/// What the app dealt with of a database's kept notices, by kind and id:
/// said, or dropped as undone at the moment it would have been said — it
/// will never be said.
class KeptNoticesSaid {
  /// The events whose leaving was told.
  final Set<String> left;

  /// The categories and the events whose arrival was told, or dropped.
  final Set<String> categories;
  final Set<String> events;

  const KeptNoticesSaid({
    this.left = const {},
    this.categories = const {},
    this.events = const {},
  });

  bool get isEmpty => left.isEmpty && categories.isEmpty && events.isEmpty;
}

/// The stored shape: `l` the leaves, each `[id, title]` or — told with a
/// name — `[id, title, name]`; `e` the events that arrived, each
/// `[id, title]`; `c` the categories that arrived. A row an earlier build
/// wrote has one name for all its leaves, `n`, which is then each one's.
/// Anything unreadable is nothing kept.
///
/// The name is each leave's own: leaves of two pairs — an unsaid one of
/// the pair that ended, then one of the next — were told as one notice
/// under the later name, the first person's events said as the second's.
class _Kept {
  final Map<String, String> left = {};

  /// The name each leave is told with, by its event; none for a leave that
  /// named nobody.
  final Map<String, String> leftNames = {};
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
      final oneName = json['n'];
      if (json['l'] case final List leaves) {
        for (final leave in leaves) {
          switch (leave) {
            case [final String id, String _, final String name]:
              kept.leftNames[id] = name;
            case [final String id, String _] when oneName is String:
              kept.leftNames[id] = oneName;
          }
        }
      }
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
        if (pair case [final String id, final String title, ...]) id: title,
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
          // It left with my alert and is back before anyone was told: the
          // alert stands again, so there is neither a leave nor news to
          // say. In both lists, the person read "your alert is off" and
          // "new from…" of one event that never moved for them.
          if (left.remove(event.id) != null) {
            leftNames.remove(event.id);
            continue;
          }
          _put(events, event);
        }
      case ShareLeftWithAlert(events: final gone, :final partnerName):
        for (final event in gone) {
          _put(left, event);
          if (partnerName == null) {
            leftNames.remove(event.id);
          } else {
            leftNames[event.id] = partnerName;
          }
          // It is not here any more: its arrival is no news.
          events.remove(event.id);
        }
      // The person's own act on this phone, said by its bar as it happens:
      // a run without the app hides nothing, so there is none to keep.
      case ShareHiddenWithAlerts():
        break;
    }
    _cap(left);
    leftNames.removeWhere((id, _) => !left.containsKey(id));
    _cap(events);
    while (categories.length > kShareNoticesKeptMax) {
      categories.removeAt(0);
    }
  }

  bool get isEmpty => left.isEmpty && categories.isEmpty && events.isEmpty;

  /// Takes out what was dealt with, each id from the list of its own kind:
  /// an event told as left may have arrived again since, and that is news.
  void remove(KeptNoticesSaid said) {
    said.left.forEach(left.remove);
    said.left.forEach(leftNames.remove);
    categories.removeWhere(said.categories.contains);
    said.events.forEach(events.remove);
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
      for (final MapEntry(key: id, value: title) in left.entries)
        [id, title, ?leftNames[id]],
    ],
    'c': categories,
    'e': [
      for (final MapEntry(key: id, value: title) in events.entries) [id, title],
    ],
  });

  /// The leaves as the notices they are told in, oldest first: a run of
  /// leaves under one name is one notice. A leave that named nobody — the
  /// pair had ended by then — joins the leaves it stands beside, and a
  /// name that comes after such leaves is theirs too; only two names that
  /// differ part a notice.
  List<ShareLeftWithAlert> _leaves() {
    final names = <String?>[];
    final groups = <List<ShareNoticeEvent>>[];
    for (final MapEntry(key: id, value: title) in left.entries) {
      final name = leftNames[id];
      if (groups.isEmpty ||
          (name != null && names.last != null && names.last != name)) {
        names.add(name);
        groups.add([]);
      }
      names.last ??= name;
      groups.last.add((id: id, title: title));
    }
    return [
      for (var i = 0; i < groups.length; i++)
        ShareLeftWithAlert(groups[i], partnerName: names[i]),
    ];
  }

  List<ShareNotice> notices() => [
    ..._leaves(),
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
