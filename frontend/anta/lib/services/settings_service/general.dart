part of '../settings_service.dart';

/// How the app behaves around the notes — the drawer swipes, confirm before
/// delete, auto-save, the list's preview and labels, sorting, haptics — and
/// where it reopens: the last location, the restore mode, onboarding.
mixin _GeneralSettings on _MoneyAndColourSettings {
  // Folder swipe gesture (to open drawer)
  Future<bool> getFolderSwipeEnabled() async {
    return _getBool(
      SettingsKeys.folderSwipeEnabled,
      SettingsKeys.defaultFolderSwipeEnabled,
    );
  }

  Future<void> setFolderSwipeEnabled(bool value) async {
    await _setBool(SettingsKeys.folderSwipeEnabled, value);
  }

  // Note swipe gesture (to open drawer)
  Future<bool> getNoteSwipeEnabled() async {
    return _getBool(
      SettingsKeys.noteSwipeEnabled,
      SettingsKeys.defaultNoteSwipeEnabled,
    );
  }

  Future<void> setNoteSwipeEnabled(bool value) async {
    await _setBool(SettingsKeys.noteSwipeEnabled, value);
  }

  // Confirm before delete
  Future<bool> getConfirmDelete() async {
    return _getBool(
      SettingsKeys.confirmDelete,
      SettingsKeys.defaultConfirmDelete,
    );
  }

  Future<void> setConfirmDelete(bool value) async {
    await _setBool(SettingsKeys.confirmDelete, value);
  }

  // Auto-save
  Future<bool> getAutoSaveEnabled() async {
    return _getBool(
      SettingsKeys.autoSaveEnabled,
      SettingsKeys.defaultAutoSaveEnabled,
    );
  }

  Future<void> setAutoSaveEnabled(bool value) async {
    await _setBool(SettingsKeys.autoSaveEnabled, value);
  }

  // Auto-save interval in seconds
  Future<int> getAutoSaveInterval() async {
    return _getInt(
      SettingsKeys.autoSaveInterval,
      SettingsKeys.defaultAutoSaveInterval,
    );
  }

  Future<void> setAutoSaveInterval(int seconds) async {
    await _setInt(SettingsKeys.autoSaveInterval, seconds);
  }

  // Show note preview in list
  Future<bool> getShowNotePreview() async {
    return _getBool(
      SettingsKeys.showNotePreview,
      SettingsKeys.defaultShowNotePreview,
    );
  }

  Future<void> setShowNotePreview(bool value) async {
    await _setBool(SettingsKeys.showNotePreview, value);
  }

  Future<LabelStyle> getLabelStyle() async {
    final raw = await _db.userSettingsDao.getValue(SettingsKeys.labelStyle);
    return LabelStyle.fromName(raw ?? SettingsKeys.defaultLabelStyle);
  }

  Future<void> setLabelStyle(LabelStyle style) async {
    await _db.userSettingsDao.setValue(SettingsKeys.labelStyle, style.name);
  }

  // Show stats bar in note editor
  Future<bool> getShowStatsBar() async {
    return _getBool(
      SettingsKeys.showStatsBar,
      SettingsKeys.defaultShowStatsBar,
    );
  }

  Future<void> setShowStatsBar(bool value) async {
    await _setBool(SettingsKeys.showStatsBar, value);
  }

  // Default notes sort order (0 = updatedDesc, 1 = updatedAsc, 2 = titleAsc, 3 = titleDesc, 4 = createdDesc, 5 = createdAsc)
  Future<int> getDefaultNotesSortOrder() async {
    return _getInt(
      SettingsKeys.defaultNotesSortOrder,
      SettingsKeys.defaultDefaultNotesSortOrder,
    );
  }

  Future<void> setDefaultNotesSortOrder(int value) async {
    await _setInt(SettingsKeys.defaultNotesSortOrder, value);
  }

  // Haptic feedback
  Future<bool> getHapticFeedback() async {
    return _getBool(
      SettingsKeys.hapticFeedback,
      SettingsKeys.defaultHapticFeedback,
    );
  }

  Future<void> setHapticFeedback(bool value) async {
    await _setBool(SettingsKeys.hapticFeedback, value);
  }

  // ── Last navigation location ─────────────────────────────────────────
  // Remembers the routes the user had stacked above the root folder page, so
  // the app can reopen that whole chain on the next cold launch.

  /// Reads the remembered stack, migrating the retired three-key format on
  /// the way through.
  ///
  /// The migration is read-through rather than a Drift migration because
  /// `user_settings` is a key/value table — there is no schema to change. It
  /// is idempotent by construction: the stack key is written before the legacy
  /// rows are deleted, and an install that already has a stack row (empty
  /// envelope included) never consults the legacy keys again.
  Future<List<NavDestination>> getLastLocationStack() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.lastLocationStack,
    );
    if (raw != null) return NavDestination.decodeStack(raw);

    final folderId = await _db.userSettingsDao.getValue(
      SettingsKeys.lastFolderId,
    );
    final stack = <NavDestination>[];
    if (folderId != null && folderId.isNotEmpty) {
      final title =
          await _db.userSettingsDao.getValue(SettingsKeys.lastFolderTitle) ??
          '';
      stack.add(NavDestination.folder(folderId: folderId, title: title));
      final noteId = await _db.userSettingsDao.getValue(
        SettingsKeys.lastNoteId,
      );
      if (noteId != null && noteId.isNotEmpty) {
        stack.add(NavDestination.note(noteId: noteId, folderId: folderId));
      }
    }

    await saveLastLocationStack(stack);
    await _db.userSettingsDao.deleteValue(SettingsKeys.lastFolderId);
    await _db.userSettingsDao.deleteValue(SettingsKeys.lastFolderTitle);
    await _db.userSettingsDao.deleteValue(SettingsKeys.lastNoteId);
    return stack;
  }

  /// Persists the stack as it now stands. An empty stack writes the empty
  /// envelope rather than deleting the row: a healthy "user is at root" state
  /// must stay distinguishable from a never-migrated install, or the legacy
  /// migration would run again against long-deleted keys.
  Future<void> saveLastLocationStack(List<NavDestination> stack) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.lastLocationStack,
      NavDestination.encodeStack(stack),
    );
  }

  /// Forgets the remembered location — used when the stored value cannot be
  /// parsed at all, not as part of ordinary navigation.
  Future<void> clearLastLocation() async {
    await saveLastLocationStack(const []);
  }

  Future<RestoreLocationMode> getRestoreLocationMode() async {
    return RestoreLocationMode.fromName(
      await _db.userSettingsDao.getValue(SettingsKeys.restoreLocationMode) ??
          SettingsKeys.defaultRestoreLocationMode,
    );
  }

  Future<void> setRestoreLocationMode(RestoreLocationMode mode) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.restoreLocationMode,
      mode.name,
    );
  }

  Future<bool> isOnboardingCompleted() async {
    return _getBool(SettingsKeys.onboardingCompleted, false);
  }

  Future<void> setOnboardingCompleted(bool value) async {
    await _setBool(SettingsKeys.onboardingCompleted, value);
  }
}
