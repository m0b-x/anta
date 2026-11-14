import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/settings_keys.dart';
import '../../constants/shared_refresh_constants.dart';
import '../fresh_preferences.dart';

/// What keeps a pair's relay messages, while the app is not in front, to
/// one work waiting to start (`docs/cloud-shared-freshness.md` §7).
///
/// One note per pair in the preferences, a key of its own so no write of
/// one isolate can undo another's: set by the isolate a message arrives
/// in, before it hands the work to the platform, and taken off by every
/// start of a message's work for the pair ([started]). A message that
/// finds it schedules nothing — the work that waits reads after it starts,
/// so after this message's change. One that arrives while a work runs
/// finds none and hands a work over, which takes the running one's place:
/// the change may have landed after that run's read began.
///
/// The note is believed for [kSharedRefreshWaitingMarkAge] and no longer,
/// so one left by a work that never ran — a process killed between the
/// note and the hand-over, a work the platform lost — swallows nothing for
/// good. Bounded in age rather than checked with the platform, whose one
/// question cannot tell a chain that waits from one that is over.
///
/// Nothing here spaces the runs themselves. What bounds a pair's messages
/// is this one waiting work, the handler's drop of any pair but the one
/// the address was written for, and the relay's own rate. There is no
/// backlog: a hand-over replaces whatever stands under the work's name
/// (`SharedRefreshScheduler.scheduleMessage`), so at most one message's
/// work stands at the platform — the newest — however long a phone was
/// asleep. A floor between runs was tried and taken out: the work it put
/// off was a plain one, which a phone asleep holds.
///
/// Both isolates read the note off the store ([FreshPreferences]): the one
/// that asks is never the one that wrote. Nothing here throws — a store
/// that cannot be read or written costs an extra work, never a message.
abstract final class SharedRefreshMessageGate {
  static String _waitingKey(String pair) =>
      '${SettingsKeys.sharedRefreshMessageWaitingPrefix}$pair';

  /// Whether a note made at [at] is still believed at [now]. One from
  /// after [now] — the clock went back since — is not: it would otherwise
  /// be believed until the clock caught up.
  static bool _young(int? at, DateTime now) {
    if (at == null) return false;
    final age = now.millisecondsSinceEpoch - at;
    return age >= 0 && age < kSharedRefreshWaitingMarkAge.inMilliseconds;
  }

  /// Whether a work for [pair] waits to start, as [stored] — the caller's
  /// one read of the store for this message — says.
  static bool waitsIn(FreshPreferences stored, String pair, {DateTime? now}) =>
      _young(stored.getInt(_waitingKey(pair)), now ?? DateTime.now());

  /// Notes that a work for [pair] is about to be handed to the platform.
  /// Before the hand-over, never after: noted after, a work that had
  /// already started would be said to wait, and a message during its read
  /// would schedule nothing.
  static Future<void> mark(String pair, {DateTime? now}) =>
      _write(_waitingKey(pair), (now ?? DateTime.now()).millisecondsSinceEpoch);

  /// Takes the note off: the hand-over failed, and nothing waits.
  static Future<void> unmark(String pair) => _write(_waitingKey(pair), null);

  /// A message's work for [pair] starts — every start, whichever way the
  /// work came to run: the note goes before anything is read, so a message
  /// from here on hands a work over, which takes the running one's place.
  /// Told apart, a fresh work taken for a retry kept its own note and its
  /// pair's messages scheduled nothing until the note aged out.
  ///
  /// With it go the notes other pairs left that are believed no longer: a
  /// pair that ended would otherwise leave its key for good.
  static Future<void> started(String pair, {DateTime? now}) async {
    await unmark(pair);
    try {
      final stored = await FreshPreferences.read();
      final at = now ?? DateTime.now();
      for (final key in stored.keys) {
        if (!key.startsWith(SettingsKeys.sharedRefreshMessageWaitingPrefix)) {
          continue;
        }
        if (!_young(stored.getInt(key), at)) await _write(key, null);
      }
    } catch (error) {
      debugPrint('[SharedRefresh] old waiting notes not cleared: $error');
    }
  }

  static Future<void> _write(String key, int? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setInt(key, value);
      }
    } catch (error) {
      debugPrint('[SharedRefresh] message note not written: $error');
    }
  }
}
