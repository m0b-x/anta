import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/backup_service.dart';
import '../../services/settings_service.dart';
import 'qa_mode.dart';

/// Imports a full-backup JSON document and reports whether it succeeded and
/// a one-line description of what happened, for the `[qa]` log.
typedef QaSeedImporter = Future<(bool ok, String message)> Function(String json);

/// One `[qa]` line, typed: what it was about, whether it went well, and the
/// wording that was printed. The driver branches on [ok], never on the text.
class QaLogEntry {
  const QaLogEntry(this.kind, this.ok, this.message);

  final String kind;
  final bool ok;
  final String message;

  Map<String, Object?> toJson() => {'kind': kind, 'ok': ok, 'message': message};
}

/// Marker-file driven startup hooks for the automation build.
///
/// The driver on the other side of this owns no app code: it drops a file into
/// the documents directory and relaunches. [applyResetMarker] gives it a clean
/// database, [applySeedMarker] gives it a known one, and [applyOnboardingSkip]
/// keeps a reset run from landing on the first-run pages.
///
/// Every collaborator is injected so the whole class runs against a temp
/// directory and fakes in tests; [beforeDependencies] and [afterDependencies]
/// are the two calls `main()` makes, and both are compiled out of a build that
/// does not define `ANTA_QA`.
class QaBootstrap {
  QaBootstrap({
    required this.documentsPath,
    required this.clearPreferences,
    required this.importSeed,
    required this.isOnboardingCompleted,
    required this.markOnboardingCompleted,
    this.databaseName = QaMode.databaseName,
    this.skipOnboarding = QaMode.skipOnboarding,
    this.enabled = true,
  });

  /// Directory the markers live in — `getApplicationDocumentsDirectory()` in
  /// the app, which on Android is
  /// `/data/user/0/com.alexzamfir.anta/app_flutter`.
  final String documentsPath;

  /// Wipes the QA preference namespace. Separate from this class because the
  /// plugin's prefix has to be set before anything reads preferences.
  final Future<void> Function() clearPreferences;

  final QaSeedImporter importSeed;

  final Future<bool> Function() isOnboardingCompleted;

  final Future<void> Function() markOnboardingCompleted;

  /// Database the reset deletes. Never the owner's `gym_notes`.
  final String databaseName;

  final bool skipOnboarding;

  /// False turns every hook into a no-op, which is what a non-QA build is.
  final bool enabled;

  /// Every `[qa]` line this process has printed, in order, so the driver can
  /// read them back over the VM service instead of scraping a device log.
  static final List<String> log = <String>[];

  /// The same lines, typed, so the driver can tell a failed seed from a
  /// successful one without matching on wording.
  static final List<QaLogEntry> entries = <QaLogEntry>[];

  static void _say(String kind, bool ok, String message) {
    log.add(message);
    entries.add(QaLogEntry(kind, ok, message));
    debugPrint('[qa] $message');
  }

  /// `SharedPreferences.setPrefix` plus the reset marker.
  ///
  /// Runs before `configureDependencies()`, because the first thing the
  /// dependency graph does is open the active database — and which database
  /// that is comes out of preferences.
  static Future<void> beforeDependencies() async {
    if (!QaMode.enabled) return;
    SharedPreferences.setPrefix(QaMode.preferencesPrefix);
    await (await _forApp()).applyResetMarker();
  }

  /// The seed marker plus the onboarding skip. Runs after
  /// `configureDependencies()`, since importing a backup needs the services
  /// that `BackupService` resolves.
  static Future<void> afterDependencies() async {
    if (!QaMode.enabled) return;
    final bootstrap = await _forApp();
    await bootstrap.applySeedMarker();
    await bootstrap.applyOnboardingSkip();
  }

  static QaBootstrap? _appInstance;

  /// The production wiring, built once and reused by both hooks.
  static Future<QaBootstrap> _forApp() async {
    final existing = _appInstance;
    if (existing != null) return existing;
    final documents = (await getApplicationDocumentsDirectory()).path;
    return _appInstance = QaBootstrap(
      documentsPath: documents,
      clearPreferences: () async =>
          (await SharedPreferences.getInstance()).clear(),
      importSeed: (json) async {
        final backup = await BackupService.getInstance();
        final result = await backup.importFromJson(json);
        return result.success
            ? (
                true,
                'imported ${result.foldersImported} folders, '
                    '${result.notesImported} notes',
              )
            : (false, 'import failed: ${result.error}');
      },
      isOnboardingCompleted: () async =>
          (await SettingsService.getInstance()).isOnboardingCompleted(),
      markOnboardingCompleted: () async =>
          (await SettingsService.getInstance()).setOnboardingCompleted(true),
    );
  }

  /// Deletes the QA database and clears the QA preference namespace when the
  /// reset marker is present, then removes the marker. Returns whether it
  /// fired.
  Future<bool> applyResetMarker() async {
    if (!enabled) return false;

    final marker = File(p.join(documentsPath, QaMode.resetMarker));
    if (!await marker.exists()) return false;

    if (databaseName == _ownerDatabaseName) {
      _say(
        'reset',
        false,
        'reset refused: ANTA_QA_DB is "$_ownerDatabaseName", '
        'which is the owner database',
      );
      await _deleteQuietly(marker);
      return false;
    }

    await clearPreferences();

    final base = p.join(documentsPath, _databaseDirectory, '$databaseName.db');
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      await _deleteQuietly(File('$base$suffix'));
    }

    await _deleteQuietly(marker);
    _say('reset', true, 'reset: cleared preferences and $databaseName.db');
    return true;
  }

  /// Imports the seed marker's contents, then removes the marker — including
  /// when the import throws, so a bad fixture costs one launch rather than
  /// every launch after it.
  Future<void> applySeedMarker() async {
    if (!enabled) return;

    final marker = File(p.join(documentsPath, QaMode.seedMarker));
    if (!await marker.exists()) return;

    try {
      final json = await marker.readAsString();
      final (ok, message) = await importSeed(json);
      _say('seed', ok, 'seed: $message');
    } catch (e) {
      _say('seed', false, 'seed: threw $e');
    } finally {
      await _deleteQuietly(marker);
    }
  }

  /// Marks onboarding completed so a reset run opens straight on the folder
  /// root. Mirrors what the onboarding page's "start fresh" does, minus the
  /// UI: `main()` reads the flag afterwards and takes the returning-user path,
  /// which is also what unseals navigation recording.
  Future<bool> applyOnboardingSkip() async {
    if (!enabled || !skipOnboarding) return false;
    if (await isOnboardingCompleted()) return false;
    await markOnboardingCompleted();
    _say('onboarding', true, 'onboarding marked completed');
    return true;
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (e) {
      _say('cleanup', false, 'could not delete ${file.path}: $e');
    }
  }

  /// The on-disk directory every database lives in. Load-bearing runtime path.
  static const String _databaseDirectory = 'gym_notes';

  /// The database a non-QA build opens by default, and the one a QA reset must
  /// never delete.
  static const String _ownerDatabaseName = 'gym_notes';
}
