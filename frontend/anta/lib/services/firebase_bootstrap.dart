import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'sync_availability.dart';

/// Brings Firebase up where sync runs, for the app's launch and for the
/// check that runs with the app closed — one initialisation, so the two can
/// never reach different projects.
///
/// Degrades to local-only rather than failing: a checkout without
/// `google-services.json` must still start, just without sync.
///
/// The app's own project id on every path, a QA run included: the emulator
/// suite is started under it (`--project alexs-note-tracking-app`), so its
/// rules are the ones a pass proves, and nothing reaches the real backend
/// while the app points at the emulator host (record §3.8, S5b) — which the
/// dependency graph sets before any call, for the launch and for the check
/// through the one function (`injection.dart`).
Future<void> initializeFirebaseForSync() async {
  if (!SyncAvailability.isSupported) return;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('[main] Firebase init failed, continuing offline: $e');
  }
}
