import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/core/qa/qa_mode.dart';

/// The emulator run's Firebase options: the app's own, under the project the
/// emulator suite runs as.
void main() {
  test('the emulator options change the project id and nothing else', () {
    const real = FirebaseOptions(
      apiKey: 'key',
      appId: '1:2:android:3',
      messagingSenderId: '2',
      projectId: 'real-project',
      storageBucket: 'real-project.appspot.com',
      authDomain: 'real-project.firebaseapp.com',
    );

    final emulated = QaMode.emulatorFirebaseOptions(real);

    expect(emulated.projectId, 'demo-anta');
    expect(
      emulated,
      FirebaseOptions(
        apiKey: real.apiKey,
        appId: real.appId,
        messagingSenderId: real.messagingSenderId,
        projectId: QaMode.firebaseEmulatorProject,
        storageBucket: real.storageBucket,
        authDomain: real.authDomain,
      ),
    );
  });
}
