/// Compile-time switches for the QA/automation build.
///
/// A normal build never defines any of these, so [enabled] const-folds to
/// `false` and every QA branch is dropped by the tree shaker. A QA build is
/// launched with `--dart-define=ANTA_QA=true`, which is the only thing that
/// separates it from the app the owner runs on the same device.
abstract final class QaMode {
  /// Whether this build is the automation build.
  static const bool enabled = bool.fromEnvironment('ANTA_QA');

  /// Database the QA build works in, inside the existing `gym_notes`
  /// directory. Never `gym_notes` itself: that file belongs to the owner.
  static const String databaseName = String.fromEnvironment(
    'ANTA_QA_DB',
    defaultValue: 'qa',
  );

  /// Whether a QA launch marks onboarding completed for itself, so a freshly
  /// reset run lands on the folder root instead of the first-run pages.
  static const bool skipOnboarding = bool.fromEnvironment(
    'ANTA_QA_SKIP_ONBOARDING',
    defaultValue: true,
  );

  /// Whether a QA build may reach Firebase at all. Off by default: the
  /// signed-in identity belongs to the install, not to a database, so an
  /// automation run would otherwise act as the owner against the production
  /// project. `--dart-define=ANTA_QA_CLOUD=true` opts a run in on purpose.
  static const bool allowCloud = bool.fromEnvironment('ANTA_QA_CLOUD');

  /// Namespace for the QA build's `SharedPreferences`. The plugin's default is
  /// `flutter.`, so a prefix of our own puts every QA key in a disjoint key
  /// space from the owner's — including `active_database`, which is the one
  /// preference this app stores.
  static const String preferencesPrefix = 'anta_qa.';

  /// Marker file that asks the next launch to wipe the QA database and the QA
  /// preference namespace. Dropped into the documents directory by the driver.
  static const String resetMarker = 'qa_reset';

  /// Marker file carrying a full-backup JSON document to import once the
  /// dependency graph is up.
  static const String seedMarker = 'qa_seed.json';
}
