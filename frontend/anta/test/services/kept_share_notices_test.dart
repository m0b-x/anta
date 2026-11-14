import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/constants/shared_refresh_constants.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/share_notice.dart';
import 'package:anta/services/kept_share_notices.dart';

import '../database/support/db_test_support.dart';
import '../support/scripted_prefs_store.dart';

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

  /// The databases that exist, for the pruning of names; null leaves every
  /// name standing.
  Set<String>? existing;

  /// The app's read, with [active] the open database's name. Clears
  /// nothing.
  Future<List<ShareNotice>> readAs(String active, {AppDatabase? open}) =>
      KeptShareNotices.forActiveDatabase(
        activeName: () async => active,
        open: () async => open ?? db,
        exists: (name) async => existing?.contains(name) ?? true,
      );

  /// The app's word that [said] was dealt with, under [active].
  Future<void> forgetAs(
    String active,
    KeptNoticesSaid said, {
    AppDatabase? open,
  }) => KeptShareNotices.forgetForActiveDatabase(
    said,
    activeName: () async => active,
    open: () async => open ?? db,
  );

  /// Everything [notices] names, as a listener that said all of it tells
  /// the store.
  KeptNoticesSaid allOf(List<ShareNotice> notices) => KeptNoticesSaid(
    left: {
      for (final notice in notices)
        if (notice is ShareLeftWithAlert)
          for (final event in notice.events) event.id,
    },
    categories: {
      for (final notice in notices)
        if (notice is ShareArrived) ...notice.categoryIds,
    },
    events: {
      for (final notice in notices)
        if (notice is ShareArrived)
          for (final event in notice.events) event.id,
    },
  );

  /// The read, and then the word that all of it was said: what the old
  /// "take" did in one step.
  Future<List<ShareNotice>> takeAs(String active, {AppDatabase? open}) async {
    final notices = await readAs(active, open: open);
    if (notices.isNotEmpty) await forgetAs(active, allOf(notices), open: open);
    return notices;
  }

  Future<List<String>> names() async =>
      (await SharedPreferences.getInstance()).getStringList(
        'share_notices_kept_in',
      ) ??
      const [];

  setUp(() => existing = null);

  test('kept by a run, read at every open until it was said, gone only '
      'then (review item 13)', () async {
    await KeptShareNotices.keep(
      db,
      'main',
      const ShareLeftWithAlert([dinner], partnerName: 'Ana'),
    );

    // Read, and read again: an app closed before the bar showed has lost
    // nothing.
    for (var open = 0; open < 3; open++) {
      expect(await readAs('main'), const [
        ShareLeftWithAlert([dinner], partnerName: 'Ana'),
      ]);
    }
    expect(await names(), ['main']);

    await forgetAs('main', const KeptNoticesSaid(left: {'e-dinner'}));

    expect(await readAs('main'), isEmpty);
    expect(await db.syncDao.getValue(SyncDao.keyShareNoticesKept), isNull);
    expect(await names(), isEmpty);
  });

  test('only what was said is forgotten, each id from the list of its own '
      'kind: what a run kept meanwhile stays for its own turn', () async {
    await KeptShareNotices.keep(
      db,
      'main',
      const ShareLeftWithAlert([dinner, run], partnerName: 'Ana'),
    );
    await KeptShareNotices.keep(
      db,
      'main',
      const ShareArrived(categoryIds: ['c-shifts', 'c-choir']),
    );
    final read = await readAs('main');
    // A run, between the read and the saying: a third event arrives.
    await KeptShareNotices.keep(
      db,
      'main',
      const ShareArrived(events: [(id: 'e-lunch', title: 'Lunch')]),
    );

    // The leave of one event is said, and one category's arrival; an id
    // that is said as an arrival is no leave forgotten.
    await forgetAs(
      'main',
      const KeptNoticesSaid(
        left: {'e-dinner'},
        categories: {'c-shifts'},
        events: {'e-run'},
      ),
    );

    expect(read, hasLength(2));
    expect(await readAs('main'), const [
      ShareLeftWithAlert([run], partnerName: 'Ana'),
      ShareArrived(
        categoryIds: ['c-choir'],
        events: [(id: 'e-lunch', title: 'Lunch')],
      ),
    ]);
    expect(await names(), ['main']);
  });

  test(
    'the last leave forgotten takes the name it was told with along',
    () async {
      await KeptShareNotices.keep(
        db,
        'main',
        const ShareLeftWithAlert([dinner], partnerName: 'Ana'),
      );
      await KeptShareNotices.keep(
        db,
        'main',
        const ShareArrived(events: [run]),
      );
      await forgetAs('main', const KeptNoticesSaid(left: {'e-dinner'}));

      // The pair has ended since: a later leave names nobody, and must not
      // be told with the name of a leave long said.
      await KeptShareNotices.keep(db, 'main', const ShareLeftWithAlert([run]));

      expect(await readAs('main'), const [
        ShareLeftWithAlert([run]),
      ]);
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

  test('leaves told with different names are kept apart (N8): each name\'s '
      'a notice of its own, the earlier first, forgotten by id — and a row '
      'an earlier build wrote, one name for all, still reads', () async {
    await KeptShareNotices.keep(
      db,
      'main',
      const ShareLeftWithAlert([dinner], partnerName: 'Mara'),
    );
    await KeptShareNotices.keep(
      db,
      'main',
      const ShareLeftWithAlert([run], partnerName: 'Ion'),
    );
    expect(await readAs('main'), const [
      ShareLeftWithAlert([dinner], partnerName: 'Mara'),
      ShareLeftWithAlert([run], partnerName: 'Ion'),
    ]);

    await forgetAs('main', const KeptNoticesSaid(left: {'e-dinner'}));
    expect(await readAs('main'), const [
      ShareLeftWithAlert([run], partnerName: 'Ion'),
    ]);

    await db.syncDao.setValue(
      SyncDao.keyShareNoticesKept,
      '{"l":[["e-dinner","Dinner"],["e-run","Run"]],"n":"Ana","c":[],"e":[]}',
    );
    expect(await readAs('main'), const [
      ShareLeftWithAlert([dinner, run], partnerName: 'Ana'),
    ]);
  });

  test('an event that arrived and then left with my alert is told as left '
      'alone; one that left and came back before anyone was told is told '
      'as neither — it sat in both lists (review item 13)', () async {
    await KeptShareNotices.keep(db, 'main', const ShareArrived(events: [run]));
    await KeptShareNotices.keep(db, 'main', const ShareLeftWithAlert([run]));
    expect(await takeAs('main'), const [
      ShareLeftWithAlert([run]),
    ]);

    await KeptShareNotices.keep(
      db,
      'main',
      const ShareLeftWithAlert([run, dinner], partnerName: 'Ana'),
    );
    await KeptShareNotices.keep(db, 'main', const ShareArrived(events: [run]));
    expect(await readAs('main'), const [
      ShareLeftWithAlert([dinner], partnerName: 'Ana'),
    ]);

    // And when it was the only one: nothing is kept at all.
    await KeptShareNotices.keep(
      db,
      'main',
      const ShareArrived(events: [dinner]),
    );
    expect(await readAs('main'), isEmpty);
    expect(await names(), isEmpty);
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

    expect(await readAs('main'), isEmpty);
    expect(await db.syncDao.getValue(SyncDao.keyShareNoticesKept), isNull);
    expect(await names(), isEmpty);
  });

  group('what it costs a database that kept nothing', () {
    test('an install where no run ever kept a notice — an account that '
        'never paired — reads nothing at a start or a resume, and saying a '
        'notice that arrived live forgets nothing: no statement, no '
        'database asked for, no file looked for', () async {
      counter.reset();
      var opened = 0;
      var looked = 0;
      Future<AppDatabase> open() async {
        opened++;
        return db;
      }

      // And the preferences are not read again from the platform: where no
      // run can exist, nobody else writes them.
      final store = ScriptedPrefsStore.install();
      await SharedPreferences.getInstance();
      final loaded = store.reads;

      for (var i = 0; i < 3; i++) {
        final notices = await KeptShareNotices.forActiveDatabase(
          activeName: () async => 'main',
          open: open,
          exists: (_) async {
            looked++;
            return true;
          },
        );
        expect(notices, isEmpty);
        await KeptShareNotices.forgetForActiveDatabase(
          const KeptNoticesSaid(left: {'e-dinner'}, events: {'e-run'}),
          activeName: () async => 'main',
          open: open,
        );
      }

      expect(counter.count, 0);
      expect(opened, 0);
      expect(looked, 0);
      expect(store.reads, loaded, reason: 'no platform call');
    });

    test('where a run can exist, a notice it kept while this process lives '
        'is seen at the next read (N2): the run writes the name from an '
        'isolate of its own, and this one\'s copy of the preferences does '
        'not hold it until it is read again', () async {
      for (final gate in [
        SettingsKeys.sharedRefreshPlanned,
        SettingsKeys.pushAddressHeld,
      ]) {
        final store = ScriptedPrefsStore.install({gate: '1'});
        await SharedPreferences.getInstance();
        // The run: its row, and the name in the platform's store.
        await db.syncDao.setValue(
          SyncDao.keyShareNoticesKept,
          '{"l":[["e-dinner","Dinner"]],"n":"Mara","c":[],"e":[]}',
        );
        await store.setValue(
          'StringList',
          'flutter.share_notices_kept_in',
          <String>['main'],
        );

        expect(await readAs('main'), const [
          ShareLeftWithAlert([dinner], partnerName: 'Mara'),
        ], reason: gate);
      }
    });

    test('once everything kept was said, the next start and resume read '
        'nothing again, and a saying forgets nothing', () async {
      await KeptShareNotices.keep(
        db,
        'main',
        const ShareArrived(events: [run]),
      );
      await takeAs('main');
      counter.reset();

      expect(await readAs('main'), isEmpty);
      await forgetAs('main', const KeptNoticesSaid(events: {'e-run'}));

      expect(counter.count, 0);
    });

    test('a read while something is kept is one statement, and writes '
        'none', () async {
      await KeptShareNotices.keep(
        db,
        'main',
        const ShareArrived(events: [run]),
      );
      counter.reset();

      await readAs('main');

      final issued = counter.statements.where(
        (sql) => sql.contains('sync_metadata'),
      );
      expect(issued, hasLength(1), reason: 'Issued:\n${issued.join('\n')}');
      expect(issued.single.trimLeft().toUpperCase(), startsWith('SELECT'));
    });

    test('a name with nothing behind it — a run killed before its row — '
        'costs one open its look, and is off the list after', () async {
      SharedPreferences.setMockInitialValues({
        'share_notices_kept_in': ['main'],
      });

      expect(await readAs('main'), isEmpty);
      expect(await names(), isEmpty);
      counter.reset();

      expect(await readAs('main'), isEmpty);
      expect(counter.count, 0);
    });
  });

  group('the row and the list of names are not one step (review item '
      '13)', () {
    test('a run that keeps after the app emptied the row and before it '
        'took the name off: the name is put back, so the row is looked '
        'for', () async {
      await KeptShareNotices.keep(
        db,
        'main',
        const ShareArrived(events: [run]),
      );
      // The run's row lands inside the app's forgetting, right after its
      // transaction has deleted the emptied row — the first write of the
      // list that follows is the name coming off.
      var kept = false;
      Future<void>? written;
      counter.onStatement = (sql, _) {
        if (kept || !sql.trimLeft().toUpperCase().startsWith('DELETE')) {
          return null;
        }
        kept = true;
        counter.onStatement = null;
        // As the run's isolate would: straight into the row, its own look
        // at the list having found the name still there. Outside the
        // transaction's zone, so it waits for the commit like another
        // connection's write.
        written = Zone.root.run(
          () => db.syncDao.setValue(
            SyncDao.keyShareNoticesKept,
            '{"l":[],"c":[],"e":[["e-dinner","Dinner"]]}',
          ),
        );
        return null;
      };

      await forgetAs('main', const KeptNoticesSaid(events: {'e-run'}));
      await written;

      expect(kept, isTrue);
      expect(await names(), ['main']);
      expect(await readAs('main'), const [
        ShareArrived(events: [dinner]),
      ]);
    });

    test('a run names the database before its row and again after it, so a '
        'name the app took off in between is back', () async {
      await KeptShareNotices.keep(
        db,
        'main',
        const ShareArrived(events: [run]),
      );
      // The app takes the name off while the run's transaction is open.
      var removed = false;
      counter.onStatement = (sql, _) async {
        if (removed || !sql.contains('sync_metadata')) return;
        removed = true;
        counter.onStatement = null;
        await (await SharedPreferences.getInstance()).setStringList(
          'share_notices_kept_in',
          const [],
        );
      };

      await KeptShareNotices.keep(
        db,
        'main',
        const ShareArrived(events: [dinner]),
      );

      expect(removed, isTrue);
      expect(await names(), ['main']);
    });
  });

  group('a name whose database no longer exists (review item 13)', () {
    test('is taken off the list at the next read, whichever database is '
        'open — and the open one\'s notices are read all the same', () async {
      await KeptShareNotices.keep(
        db,
        'main',
        const ShareArrived(events: [run]),
      );
      SharedPreferences.setMockInitialValues({
        'share_notices_kept_in': ['deleted', 'main', 'renamed-away'],
      });
      existing = {'main'};

      expect(await readAs('main'), const [
        ShareArrived(events: [run]),
      ]);
      expect(await names(), ['main']);
    });

    test('never the open database\'s own name, and nothing when the files '
        'cannot be asked about', () async {
      SharedPreferences.setMockInitialValues({
        'share_notices_kept_in': ['main', 'travel'],
      });
      existing = {};
      await readAs('travel', open: db);
      expect(await names(), isEmpty, reason: 'travel: nothing behind it');

      SharedPreferences.setMockInitialValues({
        'share_notices_kept_in': ['main', 'travel'],
      });
      await KeptShareNotices.forActiveDatabase(
        activeName: () async => 'other',
        open: () async => db,
        exists: (_) async => throw StateError('no directory'),
      );
      expect(await names(), ['main', 'travel']);
    });
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
