import '../models/category_profile.dart';

/// The synchronous read of every category's analytics profile — what the
/// report's memo key, the event editor and the detail sheet read while they
/// build, the `CalendarCategories` / `EventAlerts` shape.
///
/// Only `CategoryProfileService` writes it, after every load and write; an
/// unloaded cache answers [EffectiveProfile.unprofiled] for every category,
/// which is the calendar as it was before profiles existed.
abstract final class CategoryProfiles {
  static Map<String, CategoryProfile> _byCategory = const {};
  static int _revision = 0;

  /// Bumped on every [updateCache] and [resetCache], never compared by
  /// value: a profile edit changes what the report counts without any event
  /// row changing, so a memo keyed on the calendar's revisions alone would
  /// serve the old fold.
  static int get revision => _revision;

  /// The stored profile of [categoryId], or null when the owner never set
  /// one — the editor's read, which must tell "nothing chosen" from a
  /// `custom` profile the owner did choose.
  static CategoryProfile? profileFor(String categoryId) =>
      _byCategory[categoryId];

  /// What [categoryId] resolves to, the one read every counting surface
  /// acts on. A category without a profile is [EffectiveProfile.unprofiled],
  /// and that is what keeps an unprofiled calendar byte-for-byte as it was:
  /// the readers take their old path on it.
  static EffectiveProfile effectiveFor(String categoryId) =>
      CategoryProfile.effectiveOf(_byCategory[categoryId]);

  /// Every stored profile by category id; unmodifiable.
  static Map<String, CategoryProfile> get all => _byCategory;

  /// Replaces the cache with [byCategory], one profile per category.
  static void updateCache(Map<String, CategoryProfile> byCategory) {
    _byCategory = Map.unmodifiable(byCategory);
    _revision++;
  }

  /// Drops everything. Part of the `DatabaseLifecycle` reset contract: a
  /// profile leaked from a closed database would count a category of the
  /// newly opened one by a kind its owner never picked.
  static void resetCache() {
    _byCategory = const {};
    _revision++;
  }
}
