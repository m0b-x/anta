import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';

/// Guards the `sync_metadata` keys the engine writes and the prefix delete a
/// bind and an unbind clear the pull state with: the prefix is literal, so
/// the `_` in `pull_cursor.` matches only itself.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  test('the per-table keys share their prefixes', () {
    expect(SyncDao.keyPullCursor('notes'), 'pull_cursor.notes');
    expect(SyncDao.keyPullSeen('notes'), 'pull_seen.notes');
    expect(
      SyncDao.keyPullCursor('counter_values'),
      startsWith(SyncDao.pullCursorPrefix),
    );
    expect(
      SyncDao.keyPullSeen('counter_values'),
      startsWith(SyncDao.pullSeenPrefix),
    );
  });

  test('a prefix delete takes its keys and nothing else', () async {
    for (final table in ['folders', 'notes', 'counter_values']) {
      await db.syncDao.setValue(SyncDao.keyPullCursor(table), 'c-$table');
      await db.syncDao.setValue(SyncDao.keyPullSeen(table), 's-$table');
    }
    await db.syncDao.setValue(SyncDao.keyBindFloor, 'floor');
    await db.syncDao.setValue(SyncDao.keyBindMergePending, '1');
    // `_` is a LIKE wildcard: a pattern match would take this key too.
    await db.syncDao.setValue('pullXcursor.notes', 'kept');

    expect(await db.syncDao.deleteByPrefix(SyncDao.pullCursorPrefix), 3);

    for (final table in ['folders', 'notes', 'counter_values']) {
      expect(await db.syncDao.getValue(SyncDao.keyPullCursor(table)), isNull);
      expect(
        await db.syncDao.getValue(SyncDao.keyPullSeen(table)),
        's-$table',
      );
    }
    expect(await db.syncDao.getValue('pullXcursor.notes'), 'kept');
    expect(await db.syncDao.getValue(SyncDao.keyBindFloor), 'floor');
    expect(await db.syncDao.getValue(SyncDao.keyBindMergePending), '1');
  });

  test('a prefix nothing starts with deletes nothing', () async {
    await db.syncDao.setValue(SyncDao.keyLastPullAt, '1');

    expect(await db.syncDao.deleteByPrefix(SyncDao.pullSeenPrefix), 0);
    expect(await db.syncDao.getValue(SyncDao.keyLastPullAt), '1');
  });

  test('an empty prefix is refused, never a wipe', () async {
    await db.syncDao.setValue(SyncDao.keyQuotaPausedAt, '1');

    expect(() => db.syncDao.deleteByPrefix(''), throwsArgumentError);
    expect(await db.syncDao.getValue(SyncDao.keyQuotaPausedAt), '1');
  });
}
