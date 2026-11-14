import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/settings_keys.dart';
import 'fresh_preferences.dart';

/// The one marker for "a database of this install is being replaced" that
/// an isolate other than the app's can read: a restore, an import, and —
/// through the marker the launch's recovery already keeps — a download
/// between its switch and its bind.
///
/// `SyncSuspension` says the same to the app's own engine, but it is a
/// static of the app's isolate: the check that runs in an isolate of its
/// own (`docs/cloud-shared-freshness.md` §6) reads its copy, which is always
/// false, and opened the database in the middle of a restore. This marker
/// is in the preferences, which every isolate of the install reads.
///
/// Written and cleared only by the app's isolate. The check asks
/// [standingIfKnown] before it looks at anything else, and again before it
/// arms or reads, and never clears: a marker left by a process that died
/// mid-way stands until the next launch, which holds the database alone,
/// takes it off ([clearLeftBehind]).
abstract final class DatabaseReplacing {
  static int _depth = 0;

  /// Runs [body] with the marker standing. Re-entrant; the marker goes when
  /// the outermost scope ends, however it ends. A store that cannot be
  /// written costs the body nothing.
  ///
  /// The outermost scope's end removes the marker whatever this isolate's
  /// copy of the preferences says of it: the copy is not what another
  /// isolate reads, and a clear that consulted it first could be talked
  /// out of the removal.
  static Future<T> run<T>(Future<T> Function() body) async {
    if (_depth++ == 0) await _raise();
    try {
      return await body();
    } finally {
      if (--_depth == 0) await _clear(always: true);
    }
  }

  /// Whether a scope of this isolate is open: the app's own answer, with
  /// no store asked.
  static bool get inFlight => _depth > 0;

  /// Whether a replacement is in flight, as the store says now — read off
  /// the store itself ([FreshPreferences]), since the isolate that asks is
  /// not the one that wrote. A store that cannot be read answers true: not
  /// knowing is no licence to open.
  static Future<bool> standing() async => await standingIfKnown() ?? true;

  /// [standing], with a store that cannot be read told apart: null. The
  /// check ends differently on the two — a marker that stands waits for
  /// the app, a store that did not answer is asked again by the platform.
  static Future<bool?> standingIfKnown() async {
    try {
      final fresh = await FreshPreferences.read();
      return fresh.containsKey(SettingsKeys.databaseReplacing) ||
          fresh.containsKey(SettingsKeys.syncDownloadInFlight);
    } catch (e) {
      debugPrint('[DatabaseReplacing] marker not read: $e');
      return null;
    }
  }

  /// Takes off a marker that describes nothing any more: one a dead process
  /// left, asked by the launch, and one whose own removal the store refused,
  /// asked by every resume — left standing, it kept the check away until
  /// the app was next started from nothing. Does nothing while a scope of
  /// this isolate is open: an import in flight keeps its marker. Never
  /// called by the check.
  ///
  /// Asks the store only where there is reason to: the copy holds the
  /// marker — at a launch it was just loaded — or a removal is owed. An
  /// install that never replaced a database pays one look at its copy.
  static Future<void> clearLeftBehind() async {
    if (_depth > 0) return;
    await _clear(always: false);
  }

  /// Whether a removal failed and is still owed. The preferences drop a key
  /// from their own copy before the store answers, so after a refusal the
  /// copy says "gone" of a marker that stands for every other isolate.
  static bool _clearOwed = false;

  static Future<void> _raise() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(SettingsKeys.databaseReplacing, '1')) {
        debugPrint('[DatabaseReplacing] marker not taken by the store');
      }
    } catch (e) {
      debugPrint('[DatabaseReplacing] marker not written: $e');
    }
  }

  static Future<void> _clear({required bool always}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (always ||
          _clearOwed ||
          prefs.containsKey(SettingsKeys.databaseReplacing)) {
        _clearOwed = !await prefs.remove(SettingsKeys.databaseReplacing);
        if (_clearOwed) {
          debugPrint('[DatabaseReplacing] marker not removed by the store');
        }
      }
    } catch (e) {
      _clearOwed = true;
      debugPrint('[DatabaseReplacing] marker not cleared: $e');
    }
  }
}
