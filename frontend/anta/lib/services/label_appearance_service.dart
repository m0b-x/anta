import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/label_appearance.dart';
import '../database/database_lifecycle.dart';
import '../models/label_style.dart';
import 'settings_service.dart';

/// Owns the one preference that decides how a labelled note or folder row
/// draws its colour — the trailing dot or the leading edge stripe.
///
/// Holds no database reference of its own — it reads and writes through
/// [SettingsService], which is what keeps it correct across a database
/// switch — and publishes a synchronous value via [LabelAppearance] so a row
/// never `await`s mid-build.
///
/// The write lands **before** the facade is published: a row repainting off a
/// value the store then failed to take would be lying about what the next
/// launch will show.
class LabelAppearanceService {
  static LabelAppearanceService? _instance;

  /// The first-initialization future while it is in flight, so two callers
  /// racing the very first [getInstance] share one read rather than each
  /// publishing their own.
  static Future<LabelAppearanceService>? _initializing;

  /// Bumped by every [reset]. A [_create] that started before a reset
  /// compares its own generation against this on the far side of its awaits
  /// and, if a reset happened in between, discards itself: it read the
  /// database that was just closed, and installing it would republish that
  /// database's style and hand every later caller a service bound to a dead
  /// handle.
  static int _generation = 0;

  late SettingsService _settings;
  LabelStyle _style = LabelStyle.dot;

  LabelAppearanceService._();

  static Future<LabelAppearanceService> getInstance() {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    return _initializing ??= _create();
  }

  static Future<LabelAppearanceService> _create() async {
    final generation = _generation;
    final service = LabelAppearanceService._();
    try {
      service._settings = await SettingsService.getInstance();
      if (generation != _generation) return await getInstance();
      await service._load();
      if (generation != _generation) return await getInstance();
      _instance = service;
      DatabaseLifecycle.registerResetHandler(reset);
      return service;
    } finally {
      if (generation == _generation) _initializing = null;
    }
  }

  /// Drops the cached singleton so the next [getInstance] binds to the
  /// database that replaced the closed one.
  ///
  /// The published value is deliberately left standing: it is a rendering
  /// preference, the next `getInstance()` overwrites it with the new
  /// database's own, and blanking it first would flash every labelled row
  /// back to the dot in between.
  static void reset() {
    _generation++;
    _instance = null;
    _initializing = null;
  }

  /// The style currently published.
  LabelStyle get style => _style;

  /// Reads the stored style and publishes it. A read that fails publishes
  /// nothing: the facade keeps whatever it last showed rather than flashing
  /// every stripe row back to the dot on a transient error, and the next
  /// successful read corrects it.
  Future<void> _load() async {
    try {
      _style = await _settings.getLabelStyle();
    } catch (e) {
      debugPrint('[LabelAppearanceService] Load error: $e');
      _style = LabelAppearance.style.value;
      return;
    }
    LabelAppearance.style.value = _style;
  }

  /// Persists [style] and publishes it to every labelled row on screen.
  ///
  /// Always writes, even when nothing changes: "Reset to defaults" relies on
  /// the row existing in the store so a backup carries the default
  /// explicitly rather than by omission. The notifier itself only fires when
  /// the value actually moves.
  Future<void> setStyle(LabelStyle style) async {
    await _settings.setLabelStyle(style);
    _style = style;
    LabelAppearance.style.value = style;
  }
}
