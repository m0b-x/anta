part of '../settings_service.dart';

// ── What a partner shares, as this phone shows it ─────────────────────
// `docs/cloud-share-surfaces-roadmap.md` §6.4, §6.7, §6.8. Read through
// `ShareService`; the looks also ride [getCalendarPageSettings] and
// [getCalendarOverviewSettings].

ShareLook _decodeShareLook(Map<String, String> values) => ShareLook(
  eventLook: ShareEventLook.fromName(
    values[SettingsKeys.shareEventLook] ?? SettingsKeys.defaultShareEventLook,
  ),
  noteLook: _decodeShareNoteLook(values[SettingsKeys.shareNoteLook]),
  markMine: _decodeBool(
    values[SettingsKeys.shareMarkMine],
    SettingsKeys.defaultShareMarkMine,
  ),
);

ShareAlerts _decodeShareAlerts(String? raw) =>
    ShareAlerts.fromName(raw ?? SettingsKeys.defaultShareAlerts);

ShareNoteLook _decodeShareNoteLook(String? raw) =>
    ShareNoteLook.fromName(raw ?? SettingsKeys.defaultShareNoteLook);

/// What a partner shares, as this phone shows it: the looks, the alerts and
/// the categories hidden here.
mixin _ShareSettings on _AlertSettings {
  /// How shared rows are drawn, in one statement. [withNotes] reads the
  /// notes look too; without it the statement is the one every calendar
  /// surface and an account that never paired have always run, and the
  /// notes look is the shipped value.
  Future<ShareLook> getShareLook({bool withNotes = false}) async =>
      _decodeShareLook(
        await _db.userSettingsDao.getValuesFor(
          withNotes
              ? const [
                  SettingsKeys.shareEventLook,
                  SettingsKeys.shareMarkMine,
                  SettingsKeys.shareNoteLook,
                ]
              : const [SettingsKeys.shareEventLook, SettingsKeys.shareMarkMine],
        ),
      );

  Future<void> setShareEventLook(ShareEventLook look) =>
      _db.userSettingsDao.setValue(SettingsKeys.shareEventLook, look.name);

  /// How a partner's folders and notes are drawn, alone: what the browser
  /// reads with its page state.
  Future<ShareNoteLook> getShareNoteLook() async => _decodeShareNoteLook(
    await _db.userSettingsDao.getValue(SettingsKeys.shareNoteLook),
  );

  Future<void> setShareNoteLook(ShareNoteLook look) =>
      _db.userSettingsDao.setValue(SettingsKeys.shareNoteLook, look.name);

  Future<void> setShareMarkMine(bool value) =>
      _setBool(SettingsKeys.shareMarkMine, value);

  /// What may ring for a partner's event, published to [EventAlerts] as the
  /// alert defaults are, so a badge answers by the value the scheduler armed
  /// by.
  Future<ShareAlerts> getShareAlerts() async {
    final value = _decodeShareAlerts(
      await _db.userSettingsDao.getValue(SettingsKeys.shareAlerts),
    );
    EventAlerts.configureShareAlerts(value);
    return value;
  }

  /// Stores [value]; the caller asks the scheduler for the pass that arms
  /// or cancels by it, as the Alert settings page does for its own options.
  Future<void> setShareAlerts(ShareAlerts value) async {
    await _db.userSettingsDao.setValue(SettingsKeys.shareAlerts, value.name);
    EventAlerts.configureShareAlerts(value);
  }

  /// The partner's categories this phone does not show; empty when none is
  /// hidden or the stored value cannot be read.
  Future<Set<String>> getShareHiddenCategories() =>
      SettingsService.shareHiddenCategoriesOf(_db);

  /// Stores [ids], deleting the row when none is hidden so "never hidden"
  /// and "hidden then shown again" leave the same absence.
  Future<void> setShareHiddenCategories(Set<String> ids) =>
      SettingsService.setShareHiddenCategoriesOf(_db, ids);
}
