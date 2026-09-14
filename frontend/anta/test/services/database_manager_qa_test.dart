import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/core/qa/qa_mode.dart';
import 'package:anta/services/database_manager.dart';

/// Which database an install opens when it has never switched is the whole of
/// the QA build's data isolation: its preferences live in their own namespace,
/// so it never sees a stored `active_database` and lands on this fallback.
///
/// `QaMode.enabled` is a compile-time constant, so the decision is tested as
/// the pure function rather than through the constant.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a normal build defaults to the owner database', () {
    expect(DatabaseManager.defaultDatabaseName(qaEnabled: false), 'gym_notes');
  });

  test('a QA build defaults to its own database', () {
    expect(DatabaseManager.defaultDatabaseName(qaEnabled: true), 'qa');
    expect(
      DatabaseManager.defaultDatabaseName(qaEnabled: true),
      QaMode.databaseName,
      reason: 'the fallback is whatever ANTA_QA_DB says',
    );
    expect(
      DatabaseManager.defaultDatabaseName(
        qaEnabled: true,
        qaDatabaseName: 'qa_scratch',
      ),
      'qa_scratch',
    );
  });

  test('an install that never switched opens the default', () async {
    final manager = await DatabaseManager.getInstance();
    expect(
      manager.getActiveDatabaseName(),
      DatabaseManager.defaultDatabaseName(qaEnabled: QaMode.enabled),
      reason: 'no stored preference means the fallback, in either build',
    );
  });

  test('a stored active database still wins', () async {
    final manager = await DatabaseManager.getInstance();
    await manager.setActiveDatabaseName('training');
    expect(
      manager.getActiveDatabaseName(),
      'training',
      reason: 'switching databases from Settings keeps working in both builds',
    );
  });
}
