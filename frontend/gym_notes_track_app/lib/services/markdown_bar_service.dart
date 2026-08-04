import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config/default_markdown_shortcuts.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/custom_markdown_shortcut.dart';
import '../models/markdown_bar_profile.dart';

/// Manages multiple markdown bar profiles and per-note assignments.
///
/// Profiles are stored as a JSON list under a single user-settings key.
/// Per-note overrides are stored under `note_bar_<noteId>` keys.
///
/// Usage:
/// ```dart
/// final svc = await MarkdownBarService.getInstance();
/// final profiles = svc.profiles;
/// svc.addProfile('My Bar');
/// ```
class MarkdownBarService extends ChangeNotifier {
  static MarkdownBarService? _instance;
  late AppDatabase _db;

  static const String _profilesKey = 'markdown_bar_profiles';
  static const String _activeProfileKey = 'active_markdown_bar';
  static const String _noteBarPrefix = 'note_bar_';

  /// One-time guards so a new default shortcut is appended to pre-existing
  /// profiles only once (and not resurrected after the user removes it).
  static const String _ghostSeedKey = 'ghost_shortcut_seeded';
  static const String _highlightSeedKey = 'highlight_shortcut_seeded';
  static const String _calloutSeedKey = 'callout_shortcut_seeded';
  static const String _moneySeedKey = 'money_shortcut_seeded';
  static const String _moneyOpsSeedKey = 'money_ops_shortcuts_seeded';
  static const String _moneyTargetSeedKey = 'money_target_shortcut_seeded';
  static const String _moneyDiffSeedKey = 'money_diff_shortcut_seeded';
  static const String _moneySpanSeedKey = 'money_span_shortcut_seeded';
  static const String _colorSeedKey = 'color_shortcuts_seeded';

  /// In-memory cache of all profiles.
  List<MarkdownBarProfile> _profiles = [];

  /// Currently active global profile ID.
  String _activeProfileId = MarkdownBarProfile.defaultProfileId;

  MarkdownBarService._();

  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  static Future<MarkdownBarService> getInstance() async {
    if (_instance == null) {
      _instance = MarkdownBarService._();
      _instance!._db = await AppDatabase.getInstance();
      await _instance!._load();
      DatabaseLifecycle.registerResetHandler(reset);
    }
    return _instance!;
  }

  /// Force re-init (e.g. after database switch).
  static void reset() {
    _instance = null;
  }

  // ---------------------------------------------------------------------------
  // Public getters
  // ---------------------------------------------------------------------------

  /// All profiles, with the default always first.
  List<MarkdownBarProfile> get profiles => List.unmodifiable(_profiles);

  /// The currently active global profile ID.
  String get activeProfileId => _activeProfileId;

  /// Convenience: the currently active profile object.
  MarkdownBarProfile get activeProfile => _profiles.firstWhere(
    (p) => p.id == _activeProfileId,
    orElse: () => _profiles.first,
  );

  // ---------------------------------------------------------------------------
  // CRUD – Profiles
  // ---------------------------------------------------------------------------

  /// Creates a new profile with default shortcuts, returns its ID.
  Future<String> addProfile(String name) async {
    final id = const Uuid().v4();
    final profile = MarkdownBarProfile(
      id: id,
      name: name.trim().isEmpty ? 'Untitled Bar' : name.trim(),
      shortcuts: DefaultMarkdownShortcuts.shortcuts,
      updatedAt: DateTime.now(),
    );
    _profiles.add(profile);
    await _persist();
    notifyListeners();
    return id;
  }

  /// Duplicates an existing profile with a new name.
  Future<String> duplicateProfile(String sourceId, String newName) async {
    final source = _profiles.firstWhere((p) => p.id == sourceId);
    final id = const Uuid().v4();
    final profile = source.copyWith(
      id: id,
      name: newName.trim().isEmpty ? '${source.name} (copy)' : newName.trim(),
      isDefault: false,
      updatedAt: DateTime.now(),
    );
    _profiles.add(profile);
    await _persist();
    notifyListeners();
    return id;
  }

  /// Renames a profile. No-op for the default profile.
  Future<void> renameProfile(String profileId, String newName) async {
    final index = _profiles.indexWhere((p) => p.id == profileId);
    if (index < 0 || _profiles[index].isDefault) return;
    _profiles[index] = _profiles[index].copyWith(
      name: newName.trim(),
      updatedAt: DateTime.now(),
    );
    await _persist();
    notifyListeners();
  }

  /// Deletes a profile. The default profile cannot be deleted.
  /// If the deleted profile was active, switches to default.
  Future<void> deleteProfile(String profileId) async {
    if (profileId == MarkdownBarProfile.defaultProfileId) return;
    _profiles.removeWhere((p) => p.id == profileId);
    if (_activeProfileId == profileId) {
      _activeProfileId = MarkdownBarProfile.defaultProfileId;
      await _db.userSettingsDao.setValue(_activeProfileKey, _activeProfileId);
    }
    await _persist();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Shortcut editing within a profile
  // ---------------------------------------------------------------------------

  /// Replaces the shortcuts list for a given profile.
  Future<void> updateShortcuts(
    String profileId,
    List<CustomMarkdownShortcut> shortcuts,
  ) async {
    final index = _profiles.indexWhere((p) => p.id == profileId);
    if (index < 0) return;
    _profiles[index] = _profiles[index].copyWith(
      shortcuts: shortcuts,
      updatedAt: DateTime.now(),
    );
    await _persist();
    notifyListeners();
  }

  /// Returns the shortcuts for a specific profile.
  List<CustomMarkdownShortcut> getShortcuts(String profileId) {
    final profile = _profiles.firstWhere(
      (p) => p.id == profileId,
      orElse: () => _profiles.first,
    );
    return List.from(profile.shortcuts);
  }

  // ---------------------------------------------------------------------------
  // Active profile
  // ---------------------------------------------------------------------------

  /// Sets the globally active profile.
  Future<void> setActiveProfile(String profileId) async {
    if (!_profiles.any((p) => p.id == profileId)) return;
    _activeProfileId = profileId;
    await _db.userSettingsDao.setValue(_activeProfileKey, profileId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Per-note assignment
  // ---------------------------------------------------------------------------

  /// Returns the profile ID assigned to a specific note, or null if the note
  /// uses the global active profile.
  Future<String?> getNoteBarId(String noteId) async {
    return _db.userSettingsDao.getValue('$_noteBarPrefix$noteId');
  }

  /// Assigns a specific profile to a note. Pass null to clear the override.
  Future<void> setNoteBarId(String noteId, String? profileId) async {
    if (profileId == null) {
      await _db.userSettingsDao.deleteValue('$_noteBarPrefix$noteId');
    } else {
      await _db.userSettingsDao.setValue('$_noteBarPrefix$noteId', profileId);
    }
    notifyListeners();
  }

  /// Returns all note IDs that have a per-note bar override.
  Future<Map<String, String>> getAllNoteBarAssignments() async {
    final all = await _db.userSettingsDao.getAllSettings();
    final result = <String, String>{};
    for (final entry in all.entries) {
      if (entry.key.startsWith(_noteBarPrefix)) {
        final noteId = entry.key.substring(_noteBarPrefix.length);
        result[noteId] = entry.value;
      }
    }
    return result;
  }

  /// Resolves which profile a note should use: per-note override → global active.
  Future<MarkdownBarProfile> resolveProfileForNote(String? noteId) async {
    if (noteId != null) {
      final override = await getNoteBarId(noteId);
      if (override != null) {
        final profile = _profiles.firstWhere(
          (p) => p.id == override,
          orElse: () => activeProfile,
        );
        return profile;
      }
    }
    return activeProfile;
  }

  // ---------------------------------------------------------------------------
  // Migration: import legacy single-list shortcuts into the default profile
  // ---------------------------------------------------------------------------

  /// Call once to migrate from the old `markdown_shortcuts` key.
  Future<void> migrateFromLegacy() async {
    final legacy = await _db.userSettingsDao.getValue('markdown_shortcuts');
    if (legacy == null) return;

    final List<dynamic> decoded = jsonDecode(legacy);
    final shortcuts = decoded
        .map((j) => CustomMarkdownShortcut.fromJson(j as Map<String, dynamic>))
        .toList();

    // Update the default profile's shortcuts with the legacy data.
    final index = _profiles.indexWhere(
      (p) => p.id == MarkdownBarProfile.defaultProfileId,
    );
    if (index >= 0) {
      _profiles[index] = _profiles[index].copyWith(
        shortcuts: shortcuts,
        updatedAt: DateTime.now(),
      );
      await _persist();
    }

    // Remove the legacy key so migration doesn't run again.
    await _db.userSettingsDao.deleteValue('markdown_shortcuts');
  }

  /// One-time reconciliation that appends a default shortcut (by id) to
  /// every profile that predates it. Guarded by [guardKey] so it runs
  /// exactly once — a user who later deletes the shortcut won't have it
  /// return on the next launch. New installs already include it via
  /// [DefaultMarkdownShortcuts], so the append is a no-op there and only
  /// the flag is written.
  Future<void> _seedDefaultShortcutIfNeeded(
    String shortcutId,
    String guardKey,
  ) async {
    final done = await _db.userSettingsDao.getValue(guardKey);
    if (done == 'true') return;

    CustomMarkdownShortcut? proto;
    for (final s in DefaultMarkdownShortcuts.shortcuts) {
      if (s.id == shortcutId) {
        proto = s;
        break;
      }
    }

    if (proto != null) {
      bool changed = false;
      for (int i = 0; i < _profiles.length; i++) {
        final profile = _profiles[i];
        if (!profile.shortcuts.any((s) => s.id == shortcutId)) {
          _profiles[i] = profile.copyWith(
            shortcuts: [...profile.shortcuts, proto],
            updatedAt: DateTime.now(),
          );
          changed = true;
        }
      }
      if (changed) await _persist();
    }

    await _db.userSettingsDao.setValue(guardKey, 'true');
  }

  // ---------------------------------------------------------------------------
  // Internal persistence
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    // Load profiles
    final raw = await _db.userSettingsDao.getValue(_profilesKey);
    if (raw != null) {
      try {
        _profiles = MarkdownBarProfile.decodeList(raw);
      } catch (e) {
        debugPrint('[MarkdownBarService] Error decoding profiles: $e');
        _profiles = [];
      }
    }

    // Ensure the default profile always exists
    if (!_profiles.any((p) => p.id == MarkdownBarProfile.defaultProfileId)) {
      _profiles.insert(
        0,
        MarkdownBarProfile(
          id: MarkdownBarProfile.defaultProfileId,
          name: 'Default',
          isDefault: true,
          shortcuts: DefaultMarkdownShortcuts.shortcuts,
          updatedAt: DateTime.now(),
        ),
      );
      await _persist();
    }

    // Load active profile ID
    final activeId = await _db.userSettingsDao.getValue(_activeProfileKey);
    if (activeId != null && _profiles.any((p) => p.id == activeId)) {
      _activeProfileId = activeId;
    } else {
      _activeProfileId = MarkdownBarProfile.defaultProfileId;
    }

    // Attempt one-time legacy migration
    await migrateFromLegacy();

    // One-time: add newer default shortcuts to profiles created before
    // they shipped (runs after legacy migration so they aren't wiped).
    await _seedDefaultShortcutIfNeeded('default_ghost', _ghostSeedKey);
    await _seedDefaultShortcutIfNeeded('default_highlight', _highlightSeedKey);
    await _seedDefaultShortcutIfNeeded('default_callout', _calloutSeedKey);
    await _seedDefaultShortcutIfNeeded('default_money', _moneySeedKey);
    // The six money-op siblings ship together under one guard so the
    // whole family appears exactly once as a unit (the single-shortcut
    // helper can't be looped with a shared guard — it stamps the guard
    // after the first id and would skip the rest).
    await _seedDefaultShortcutBatchIfNeeded(const [
      'default_money_subtract',
      'default_money_multiply',
      'default_money_divide',
      'default_money_set',
      'default_money_total',
      'default_money_delta',
    ], _moneyOpsSeedKey);
    // Target shipped after the op batch, so it carries its own guard —
    // devices that already consumed the batch guard still receive it.
    await _seedDefaultShortcutIfNeeded(
      'default_money_target',
      _moneyTargetSeedKey,
    );
    // Checkpoint diff (`$^`) shipped after target, same pattern.
    await _seedDefaultShortcutIfNeeded('default_money_diff', _moneyDiffSeedKey);
    // Checkpoint span (`$~`) shipped after diff, same pattern.
    await _seedDefaultShortcutIfNeeded('default_money_span', _moneySpanSeedKey);
    // The two colour shortcuts ship together as one family.
    await _seedDefaultShortcutBatchIfNeeded(const [
      'default_color_text',
      'default_color_highlight',
    ], _colorSeedKey);
  }

  /// Batch counterpart of [_seedDefaultShortcutIfNeeded]: appends every
  /// listed default shortcut missing from each pre-existing profile,
  /// persists once, then stamps [guardKey] so the whole family seeds
  /// exactly once.
  Future<void> _seedDefaultShortcutBatchIfNeeded(
    List<String> shortcutIds,
    String guardKey,
  ) async {
    final done = await _db.userSettingsDao.getValue(guardKey);
    if (done == 'true') return;

    final protos = <CustomMarkdownShortcut>[
      for (final s in DefaultMarkdownShortcuts.shortcuts)
        if (shortcutIds.contains(s.id)) s,
    ];

    if (protos.isNotEmpty) {
      bool changed = false;
      for (int i = 0; i < _profiles.length; i++) {
        final profile = _profiles[i];
        final missing = [
          for (final proto in protos)
            if (!profile.shortcuts.any((s) => s.id == proto.id)) proto,
        ];
        if (missing.isNotEmpty) {
          _profiles[i] = profile.copyWith(
            shortcuts: [...profile.shortcuts, ...missing],
            updatedAt: DateTime.now(),
          );
          changed = true;
        }
      }
      if (changed) await _persist();
    }

    await _db.userSettingsDao.setValue(guardKey, 'true');
  }

  Future<void> _persist() async {
    await _db.userSettingsDao.setValue(
      _profilesKey,
      MarkdownBarProfile.encodeList(_profiles),
    );
  }
}
