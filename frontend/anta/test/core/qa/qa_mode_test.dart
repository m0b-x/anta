import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/core/qa/qa_mode.dart';
import 'package:anta/services/firebase_auth_service.dart';
import 'package:anta/services/sync/firestore_sync_gateway.dart';

/// The QA seam's emulator switches: the suite's ports, and the boundary that
/// keeps Firebase out of `lib/core/qa` — a pass runs under the app's own
/// project id, so nothing here rewrites its Firebase options (record §3.8,
/// S5b).
void main() {
  test('the emulator ports default to the ones the suite declares', () {
    expect(QaMode.firebaseFirestorePort, 8080);
    expect(QaMode.firebaseAuthPort, 9099);
  });

  test('both gateways take their emulator port from the QA seam', () {
    expect(
      FirestoreSyncGateway.emulatorFirestorePort,
      QaMode.firebaseFirestorePort,
    );
    expect(FirebaseAuthService.emulatorAuthPort, QaMode.firebaseAuthPort);
  });

  test('the QA seam imports no Firebase package', () {
    final importers = [
      for (final file in Directory('lib/core/qa').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            RegExp(r'package:firebase_\w+/').hasMatch(file.readAsStringSync()))
          file.path.replaceAll(r'\', '/'),
    ]..sort();

    expect(importers, isEmpty);
  });
}
