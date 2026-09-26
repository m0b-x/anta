import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';

/// `UserSettingsDao.setValues` exists so a bundle of settings lands whole: the
/// agenda filters are saved unawaited on every change, and thirteen separate
/// writes from two saves in flight could interleave key by key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late StatementCounter counter;

  setUp(() async {
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
  });

  tearDown(() => db.close());

  test('a bundle is one batched statement, not one write per key', () async {
    final values = {
      for (var i = 0; i < 13; i++) 'calendar_upcoming_probe_$i': 'v$i',
    };
    counter.reset();

    await db.userSettingsDao.setValues(values);

    final writes = counter.statements.where(
      (sql) => sql.contains('user_settings') && !sql.contains('SELECT'),
    );
    expect(
      writes,
      hasLength(1),
      reason:
          'drift batches identical statements into one and runs the batch '
          'in a transaction. Issued:\n${counter.statements.join('\n')}',
    );
    expect(await db.userSettingsDao.getValuesFor(values.keys), values);
  });

  test('a second bundle overwrites the first key by key', () async {
    await db.userSettingsDao.setValues({'a': '1', 'b': '2'});
    await db.userSettingsDao.setValues({'a': '3'});

    expect(await db.userSettingsDao.getValuesFor(['a', 'b']), {
      'a': '3',
      'b': '2',
    });
  });

  test('an empty bundle writes nothing', () async {
    counter.reset();
    await db.userSettingsDao.setValues(const {});
    expect(counter.statements.where((s) => !s.contains('SELECT')), isEmpty);
  });
}
