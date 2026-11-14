import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/core/di/injection.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/sync/app_sync_apply_hooks.dart';
import 'package:anta/services/sync/sync_binding_service.dart';

/// D31's wiring (`docs/cloud-share-surfaces-roadmap.md` §16.2): the unbind's
/// one call above itself — what takes the alerts on a partner's rows off the
/// platform when "Stop syncing" removes them — is the app's own start-up's,
/// not a test's.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(resetDependencies);

  test('starting the engine points the unbind at the hooks, and a reset of '
      'the dependencies clears it', () async {
    expect(SyncBindingService.onSharedRowsRemoved, isNull);

    // The engine itself cannot open here — no database — and start-up
    // logs that; the wiring is set before it is asked.
    await startSyncEngine();

    expect(
      SyncBindingService.onSharedRowsRemoved,
      AppSyncApplyHooks.afterSharedRowsRemoved,
    );
    await resetDependencies();
    expect(SyncBindingService.onSharedRowsRemoved, isNull);
  });

  test(
    'the share service\'s "after marks" is what the pairing tells once '
    'an adoption cleared the marks other pairs left, set where sharing '
    'is configured and cleared with the dependencies (device leg 2, R4)',
    () async {
      // `_configureSharing` runs inside the whole start-up, which no suite
      // can run: its one line is held by reading the source, the reset by
      // running it.
      final source = File('lib/core/di/injection.dart').readAsStringSync();
      final configured = source.indexOf(
        'void _configureSharing(FolderStorageService folders) {',
      );
      expect(configured, isNonNegative);
      final body = source.substring(
        configured,
        source.indexOf('\n}', configured),
      );
      expect(
        body.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          'PairingService.onMarksOfOtherPairsCleared = '
          'ShareService.afterMarksClearedElsewhere;',
        ),
      );

      PairingService.onMarksOfOtherPairsCleared = () async {};
      await resetDependencies();
      expect(PairingService.onMarksOfOtherPairsCleared, isNull);
    },
  );
}
