import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/shared_refresh_constants.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/share_notice.dart';
import 'package:anta/services/kept_share_notices.dart';

import '../database/support/db_test_support.dart';

/// `KeptShareNotices` — what a check found while no app ran to say it, kept
/// with the database for the next open (`docs/cloud-shared-freshness.md`,
/// decision f).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StatementCounter counter;
  late AppDatabase db;

  const dinner = (id: 'e-dinner', title: 'Dinner');
  const run = (id: 'e-run', title: 'Run');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
  });

  tearDown(() async => db.close());

  /// The app's take, with [active] the open database's name.
  Future<List<ShareNotice>> takeAs(String active, {AppDatabase? open}) =>
      KeptShareNotices.takeForActiveDatabase(
        activeName: () async => active,
        open: () async => open ?? db,
      );

  test(
    'kept by a run, handed over once at the next open, gone after',
    () async {
      await KeptShareNotices.keep(
        db,
        'main',
        const ShareLeftWithAlert([dinner], partnerName: 'Ana'),
      );

      expect(await takeAs('main'), const [
        ShareLeftWithAlert([dinner], partnerName: 'Ana'),
      ]);
      expect(await takeAs('main'), isEmpty);
      expect(await db.syncDao.getValue(SyncDao.keyShareNoticesKept), isNull);
    },
  );

  test('two runs\' notices are merged — the leave first, an event once, its '
      'latest title, the name the leaves were told with', () async {
    await KeptShareNotices.keep(
      db,
      'main',
      const ShareArrived(categoryIds: ['c-shifts'], events: [run]),
    );
    await KeptShareNotices.keep(
      db,
      'main',
      const ShareLeftWithAlert([dinner], partnerName: 'Ana'),
    );
    await KeptShareNotices.keep(
      db,
      'main',
      const ShareArrived(
        categoryIds: ['c-shifts', 'c-choir'],
        events: [(id: 'e-run', title: 'Long run')],
      ),
    );
    // The pair has ended meanwhile: the later leave names nobody.
    await KeptShareNotices.keep(db, 'main', const ShareLeftWithAlert([run]));

    expect(await takeAs('main'), const [
      ShareLeftWithAlert([dinner, run], partnerName: 'Ana'),
      ShareArrived(categoryIds: ['c-shifts', 'c-choir']),
    ]);
  });

  test('an event that arrived and then left with my alert is told as left '
      'alone; one that comes back after is told as both', () async {
    await KeptShareNotices.keep(db, 'main', const ShareArrived(events: [run]));
    await KeptShareNotices.keep(db, 'main', const ShareLeftWithAlert([run]));
    expect(await takeAs('main'), const [
      ShareLeftWithAlert([run]),
    ]);

    await KeptShareNotices.keep(db, 'main', const ShareLeftWithAlert([run]));
    await KeptShareNotices.keep(db, 'main', const ShareArrived(events: [run]));
    expect(await takeAs('main'), const [
      ShareLeftWithAlert([run]),
      ShareArrived(events: [run]),
    ]);
  });

  test('the newest of each kind are kept, never an endless list', () async {
    for (var i = 0; i < kShareNoticesKeptMax + 5; i++) {
      await KeptShareNotices.keep(
        db,
        'main',
        ShareArrived(
          categoryIds: ['c$i'],
          events: [(id: 'e$i', title: 'Event $i')],
        ),
      );
      await KeptShareNotices.keep(
        db,
        'main',
        ShareLeftWithAlert([(id: 'l$i', title: 'Left $i')]),
      );
    }

    final [left as ShareLeftWithAlert, arrived as ShareArrived] = await takeAs(
      'main',
    );

    expect(left.events, hasLength(kShareNoticesKeptMax));
    expect(left.events.first.id, 'l5');
    expect(arrived.events, hasLength(kShareNoticesKeptMax));
    expect(arrived.events.last.id, 'e${kShareNoticesKeptMax + 4}');
    expect(arrived.categoryIds, hasLength(kShareNoticesKeptMax));
  });

  test('a row nobody can read is nothing kept, and is cleared', () async {
    await KeptShareNotices.keep(db, 'main', const ShareArrived(events: [run]));
    await db.syncDao.setValue(SyncDao.keyShareNoticesKept, '{not json');

    expect(await takeAs('main'), isEmpty);
    expect(await db.syncDao.getValue(SyncDao.keyShareNoticesKept), isNull);
  });

  group('what it costs a database that kept nothing', () {
    test('an install where no run ever kept a notice — an account that '
        'never paired — reads nothing at a start or a resume: no statement, '
        'no database asked for', () async {
      counter.reset();
      var opened = 0;

      for (var i = 0; i < 3; i++) {
        final notices = await KeptShareNotices.takeForActiveDatabase(
          activeName: () async => 'main',
          open: () async {
            opened++;
            return db;
          },
        );
        expect(notices, isEmpty);
      }

      expect(counter.count, 0);
      expect(opened, 0);
    });

    test(
      'after the take, the next start and resume read nothing again',
      () async {
        await KeptShareNotices.keep(
          db,
          'main',
          const ShareArrived(events: [run]),
        );
        await takeAs('main');
        counter.reset();

        expect(await takeAs('main'), isEmpty);

        expect(counter.count, 0);
      },
    );

    test(
      'the take itself is one transaction: the read and the delete',
      () async {
        await KeptShareNotices.keep(
          db,
          'main',
          const ShareArrived(events: [run]),
        );
        counter.reset();

        await takeAs('main');

        expect(
          counter.statements.where((sql) => sql.contains('sync_metadata')),
          hasLength(2),
          reason: 'Issued:\n${counter.statements.join('\n')}',
        );
      },
    );
  });

  group('a notice belongs to the database it arrived under', () {
    test('another database open at the next launch says nothing and reads '
        'nothing; back under its own, it is said', () async {
      final other = await openTestDatabase();
      addTearDown(other.close);
      await KeptShareNotices.keep(
        db,
        'main',
        const ShareLeftWithAlert([dinner], partnerName: 'Ana'),
      );
      counter.reset();

      expect(await takeAs('travel', open: other), isEmpty);
      expect(counter.count, 0);

      expect(await takeAs('main'), const [
        ShareLeftWithAlert([dinner], partnerName: 'Ana'),
      ]);
    });

    test('two databases each keep and hand over their own', () async {
      final other = await openTestDatabase();
      addTearDown(other.close);
      await KeptShareNotices.keep(
        db,
        'main',
        const ShareArrived(events: [run]),
      );
      await KeptShareNotices.keep(
        other,
        'travel',
        const ShareArrived(events: [dinner]),
      );

      expect(await takeAs('travel', open: other), const [
        ShareArrived(events: [dinner]),
      ]);
      expect(await takeAs('main'), const [
        ShareArrived(events: [run]),
      ]);
    });
  });
}
