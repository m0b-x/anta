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

  static Future<CalendarPaletteService> getInstance() {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    return _initializing ??= _create();
  }

  static Future<CalendarPaletteService> _create() async {
    try {
      final service = CalendarPaletteService._();
      service._settings = await SettingsService.getInstance();
      await service._load();
      _instance = service;
      DatabaseLifecycle.registerResetHandler(reset);
      return service;
    } finally {
      _initializing = null;
    }
  }

  /// Drops the cached singleton and the published palette, so custom colours
  /// from a closed database cannot leak into the next one's pickers.
  static void reset() {
    _instance = null;
    _initializing = null;
    CalendarPalette.resetCache();
  }

  /// The user's own swatches, in the order they were added.
  List<int> get customColors => _custom;

  /// Built-ins first, then the user's own.
  List<int> get colors => CalendarPalette.all;

  Future<void> reload() => _load();

  /// Reads the stored swatches, then folds the retired recents in.
  ///
  /// The two are guarded separately on purpose: a fold that fails must not
  /// discard a set that was read successfully, and neither failure may leave
  /// the service thinking an unreadable palette is an empty one.
  Future<void> _load() async {
    try {
      _custom = _normalize(await _settings.getCustomCalendarColors());
      _loaded = true;
    } catch (e) {
      debugPrint('[CalendarPaletteService] Load error: $e');
      _custom = const [];
      _loaded = false;
    }
    if (_loaded) {
      try {
        await _foldLegacyRecents();
      } catch (e) {
        debugPrint('[CalendarPaletteService] Legacy fold error: $e');
      }
    }
    CalendarPalette.updateCache(_custom);
  }

  /// Carries the retired recent-colors list into the permanent palette once.
  ///
  /// Those colours are exactly what this feature makes permanent — a user who
  /// mixed one on the wheel last week should find it waiting, not have to mix
  /// it again — and clearing the row afterwards is what keeps the fold from
  /// resurrecting a swatch the user then deleted.
  Future<void> _foldLegacyRecents() async {
    final legacy = await _settings.getRecentEventColors();
    if (legacy.isEmpty) return;
    final folded = _normalize([
      ..._custom,
      ...legacy.where((c) => !CalendarPalette.isDefault(c)),
    ]);
    // Destination first, source second: clearing the recents before the
    // palette write lands would lose those colours outright if the write
    // failed or the process died between the two, and the fold — being
    // once-only by design — would never run again to recover them.
    if (folded.length != _custom.length) {
      _custom = folded;
      await _settings.setCustomCalendarColors(_custom);
    }
    await _settings.clearRecentEventColors();
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
