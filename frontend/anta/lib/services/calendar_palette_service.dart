import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/calendar_palette.dart';
import '../constants/settings_keys.dart';
import '../database/database_lifecycle.dart';
import 'settings_service.dart';

/// Owns the calendar's colour palette: the built-in swatches plus the ones
/// the user added, offered by every colour picker in the app.
///
/// Holds no database reference of its own — it writes through
/// [SettingsService], which is what keeps it correct across a database
/// switch — and publishes a synchronous cache via [CalendarPalette] so the
/// pickers never `await` mid-build.
///
/// Every mutation is serialized onto a single chain ([_serialize]) and
/// republishes the facade, so two taps issued from different sheets cannot
/// land — or publish — out of order.
///
/// Deleting a swatch removes it from the *palette*, never from the things
/// already painted with it: events, categories, templates and the fasting
/// styles store raw ARGB ints, so a deleted colour keeps rendering wherever
/// it was chosen and simply stops being offered.
class CalendarPaletteService {
  static CalendarPaletteService? _instance;

  /// The first-initialization future while it is in flight.
  ///
  /// Without it two callers racing the very first [getInstance] each build a
  /// service and each publish it, and the loser walks away holding an orphan
  /// with its own `_custom` and its own write chain — so a colour added
  /// through one silently overwrites a colour added through the other. Every
  /// other service in the app caches a *read* model, where a second instance
  /// is merely stale; this one owns a list it rewrites whole.
  static Future<CalendarPaletteService>? _initializing;

  /// Bumped by every [reset]. With [DatabaseLifecycle.generation] it is how a
  /// construction tells, past each of its awaits, that it has been overtaken:
  /// this counter covers a restore's deliberate re-init inside one database
  /// lifetime (`BackupService.importFromJson`), the lifecycle's covers a
  /// switch that landed before the construction had registered its handler
  /// and so never called [reset] here at all.
  static int _generation = 0;

  late SettingsService _settings;
  List<int> _custom = const [];

  /// Whether [_custom] reflects a successful read.
  ///
  /// False means "unknown", never "empty": [_commit] rewrites the whole row
  /// from memory, so treating a failed read as an empty palette would let the
  /// next colour the user picks erase every swatch they had.
  bool _loaded = false;

  /// Tail of the serialized write chain, or null when nothing is in flight.
  Future<void>? _writes;

  CalendarPaletteService._();

  static Future<CalendarPaletteService> getInstance() => _createOnce();

  /// One construction at a time, and never one a [reset] overtook.
  ///
  /// A construction the reset overtook read the palette row as it stood
  /// before the restore — or in a database that is already closed — so it
  /// discards itself and hands its caller the instance the new state
  /// installs. Publishing that stale list is not merely stale here: [_commit]
  /// rewrites the whole row from memory, so the next colour the user picks
  /// would persist the pre-restore swatches over the restored ones.
  static Future<CalendarPaletteService> _createOnce() {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    final pending = _initializing;
    if (pending != null) return pending;
    late final Future<CalendarPaletteService> creating;
    creating = () async {
      final generation = _generation;
      final lifecycle = DatabaseLifecycle.generation;
      bool overtaken() =>
          generation != _generation ||
          lifecycle != DatabaseLifecycle.generation;

      Future<CalendarPaletteService> restart() async {
        if (identical(_initializing, creating)) _initializing = null;
        final service = await _createOnce();
        // This construction may already have published the pre-reset
        // swatches on its way through `_load`.
        service._publish();
        return service;
      }

      try {
        final settings = await SettingsService.getInstance();
        if (overtaken()) return await restart();
        final service = CalendarPaletteService._();
        service._settings = settings;
        await service._load();
        if (overtaken()) return await restart();
        // The legacy fold **writes** the palette row, so it runs out here
        // under the construction's guard rather than inside `_load`. It is
        // reachable precisely because `recent_event_colors` is *not* in the
        // backup's allow-list: a restore leaves this device's own recents
        // standing, so a construction the restore overtook would fold them
        // into its pre-reset swatches and persist that list over the restored
        // one — the facade then showing the restored palette and SQLite the
        // old one. [reload] does not fold; the fold is once-only.
        await service._foldLegacy(overtaken);
        if (overtaken()) return await restart();
        _instance = service;
        DatabaseLifecycle.registerResetHandler(reset);
        return service;
      } finally {
        if (identical(_initializing, creating)) _initializing = null;
      }
    }();
    return _initializing = creating;
  }

  /// Drops the cached singleton and the published palette, so custom colours
  /// from a closed database — or from before a restore — cannot leak into the
  /// next one's pickers.
  static void reset() {
    _generation++;
    _instance = null;
    _initializing = null;
    CalendarPalette.resetCache();
  }

  /// The user's own swatches, in the order they were added.
  List<int> get customColors => _custom;

  /// Built-ins first, then the user's own.
  List<int> get colors => CalendarPalette.all;

  Future<void> reload() => _load();

  /// Reads the stored swatches.
  ///
  /// A failed read may not leave the service thinking an unreadable palette is
  /// an empty one — [_loaded] is what every write checks before rewriting the
  /// row from memory. The retired recents are folded in by [_foldLegacy],
  /// which writes and therefore runs under the construction's guard instead.
  Future<void> _load() async {
    try {
      _custom = _normalize(await _settings.getCustomCalendarColors());
      _loaded = true;
    } catch (e) {
      debugPrint('[CalendarPaletteService] Load error: $e');
      _custom = const [];
      _loaded = false;
    }
    _publish();
  }

  /// Republishes this instance's swatches to the synchronous facade.
  void _publish() => CalendarPalette.updateCache(_custom);

  /// [_foldLegacyRecents] for the one caller that may run it — the
  /// construction, which holds the [overtaken] guard the fold's write needs.
  ///
  /// Guarded apart from [_load] for the reason the read is: a fold that fails
  /// must not discard a set that was read successfully, and an unreadable
  /// palette is never folded into.
  Future<void> _foldLegacy(bool Function() overtaken) async {
    if (!_loaded) return;
    try {
      if (await _foldLegacyRecents(overtaken)) _publish();
    } catch (e) {
      debugPrint('[CalendarPaletteService] Legacy fold error: $e');
    }
  }

  /// Carries the retired recent-colors list into the permanent palette once,
  /// returning whether it changed [_custom].
  ///
  /// Those colours are exactly what this feature makes permanent — a user who
  /// mixed one on the wheel last week should find it waiting, not have to mix
  /// it again — and clearing the row afterwards is what keeps the fold from
  /// resurrecting a swatch the user then deleted.
  ///
  /// [overtaken] is re-read between the recents and the write: a restore can
  /// land while this very read is in flight, and the write that follows it
  /// rewrites the whole palette row from a `_custom` that predates the
  /// restore.
  Future<bool> _foldLegacyRecents(bool Function() overtaken) async {
    final legacy = await _settings.getRecentEventColors();
    if (legacy.isEmpty || overtaken()) return false;
    final folded = _normalize([
      ..._custom,
      ...legacy.where((c) => !CalendarPalette.isDefault(c)),
    ]);
    // Destination first, source second: clearing the recents before the
    // palette write lands would lose those colours outright if the write
    // failed or the process died between the two, and the fold — being
    // once-only by design — would never run again to recover them.
    var changed = false;
    if (folded.length != _custom.length) {
      _custom = folded;
      await _settings.setCustomCalendarColors(_custom);
      changed = true;
    }
    await _settings.clearRecentEventColors();
    return changed;
  }

  /// Drops built-ins and duplicates, then applies the cap. Order is
  /// insertion order: a palette that reshuffled itself would move the dot the
  /// user is aiming at.
  static List<int> _normalize(List<int> colors) {
    final seen = <int>{};
    final out = <int>[];
    for (final color in colors) {
      if (CalendarPalette.isDefault(color) || !seen.add(color)) continue;
      out.add(color);
      if (out.length == SettingsKeys.maxCustomCalendarColors) break;
    }
    return out;
  }

  /// Adds [color] to the user's palette.
  ///
  /// Returns false when it changes nothing — the colour is already offered
  /// (built-in or custom) or the palette is full — so the caller can say why
  /// instead of silently doing nothing.
  Future<bool> add(int color) {
    return _serialize(() async {
      if (!_loaded) return false;
      if (CalendarPalette.contains(color)) return false;
      if (_custom.length >= SettingsKeys.maxCustomCalendarColors) return false;
      await _commit([..._custom, color]);
      return true;
    });
  }

  /// Recolours an existing custom swatch in place, keeping its position.
  ///
  /// Returns false when [previous] is not a custom swatch or [next] is
  /// already offered elsewhere.
  Future<bool> update(int previous, int next) {
    return _serialize(() async {
      if (!_loaded || previous == next) return false;
      final index = _custom.indexOf(previous);
      if (index < 0) return false;
      if (CalendarPalette.contains(next)) return false;
      final updated = [..._custom]..[index] = next;
      // Published with the new list so a picker can move its selection onto
      // the recoloured swatch — see [CalendarPalette.lastRecolor].
      await _commit(updated, recolored: (previous, next));
      return true;
    });
  }

  /// Removes a custom swatch. Built-ins are not removable, so a value that is
  /// not in the custom half is a no-op rather than an error.
  Future<bool> remove(int color) {
    return _serialize(() async {
      if (!_loaded || !_custom.contains(color)) return false;
      await _commit([
        for (final c in _custom)
          if (c != color) c,
      ]);
      return true;
    });
  }

  /// Moves a custom swatch to a new position.
  ///
  /// The stored order **is** the order every picker draws, so this is the one
  /// mutation that changes nothing about the set and everything about how it
  /// reads. Indices are into [customColors], already adjusted for the removal
  /// by `ReorderableList`'s `onReorderItem`; out-of-range or no-op moves
  /// return false rather than throwing, since a drag that lands where it
  /// started is a normal gesture.
  Future<bool> move(int oldIndex, int newIndex) {
    return _serialize(() async {
      if (!_loaded || oldIndex == newIndex) return false;
      if (oldIndex < 0 || oldIndex >= _custom.length) return false;
      if (newIndex < 0 || newIndex >= _custom.length) return false;
      final next = [..._custom];
      next.insert(newIndex, next.removeAt(oldIndex));
      await _commit(next);
      return true;
    });
  }

  /// Drops every custom swatch, leaving the palette as it ships.
  Future<bool> resetToDefaults() {
    return _serialize(() async {
      if (!_loaded || _custom.isEmpty) return false;
      await _commit(const []);
      return true;
    });
  }

  Future<void> _commit(List<int> colors, {(int, int)? recolored}) async {
    // Never reachable with `_loaded == false` — every mutation gates on it —
    // because this rewrites the whole row from memory, and memory after a
    // failed read means "unknown", not "empty".
    assert(_loaded, 'commit from an unloaded palette would erase the row');
    final next = _normalize(colors);
    await _settings.setCustomCalendarColors(next);
    _custom = next;
    CalendarPalette.updateCache(_custom, recolored: recolored);
  }

  /// Runs [action] after every write already queued, so concurrent taps land
  /// in the order they were made and each one sees the previous one's state.
  Future<bool> _serialize(Future<bool> Function() action) {
    final previous = _writes ?? Future<void>.value();
    final result = previous.then((_) => action());
    _writes = result.then((_) {}, onError: (_) {});
    return result;
  }
}
