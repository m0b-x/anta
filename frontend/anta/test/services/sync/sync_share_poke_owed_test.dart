import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/database/database.dart';
import 'package:anta/services/push/push_relay.dart';
import 'package:anta/services/sync/sync_gateway.dart';

import '../../support/fake_push.dart';
import 'support/sync_pair.dart';

/// What the sender owes the partner's phone survives what a run in memory
/// would lose (`docs/cloud-shared-freshness.md` §7): a granted row that
/// landed in a run that then failed, a poke owed when no pair id is held,
/// and a poke behind an entry the server keeps refusing.
void main() {
  late SharePair pair;
  late FakePushRelay relay;
  final day = DateTime.utc(2026, 6, 1);

  setUp(() async {
    pair = await SharePair.open();
    relay = FakePushRelay(address: Uri.parse('https://relay.test'));
    GetIt.I.registerSingleton<PushRelay>(relay);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await pair.close();
  });

  AppDatabase db() => pair.owner.db;

  Future<void> event(String id) => db().calendarEventDao.upsert(
    CalendarEventsCompanion.insert(
      id: id,
      title: 'Event $id',
      category: 'general',
      startDate: day,
      ruleKind: 'weekly',
      createdAt: day,
      updatedAt: day,
    ),
  );

  Future<void> rename(String id, String title) => db().calendarEventDao.upsert(
    CalendarEventsCompanion(id: Value(id), title: Value(title)),
  );

  Future<void> sharedAndSettled(String id) async {
    await event(id);
    await db().calendarEventDao.setSharedPair(id, sharePairId);
    await pair.owner.sync();
    await pair.owner.sync();
    relay.pokes.clear();
  }

  test('a shared row that landed in a run that then failed is still poked '
      'for by the next run that ends well', () async {
    await sharedAndSettled('e1');
    await rename('e1', 'Night shift');
    await event('e2');
    pair.gateway
      ..maxBatch = 1
      ..landPushes = 1;
    await pair.owner.sync();
    expect(relay.pokes, isEmpty);

    pair.gateway.landPushes = null;
    await pair.owner.sync();
    expect(relay.pokes, [(pair: sharePairId, urgent: true)]);
  });

  test('an owed poke is sent to the pair it was owed to, though no pair id '
      'is held for the partner\'s rows', () async {
    await sharedAndSettled('e1');
    await db().customStatement(
      "DELETE FROM sync_metadata WHERE key = 'shared_pair'",
    );
    await db().calendarEventDao.setSharedPair('e1', null);
    await pair.owner.sync();

    expect(relay.pokes, [(pair: sharePairId, urgent: true)]);
  });

  test('an entry the server keeps refusing holds no owed poke back', () async {
    await sharedAndSettled('e1');
    final folder = await db().folderDao.createFolder(name: 'Mine');
    final note = await writeNote(
      pair.owner,
      folderId: folder.id,
      title: 'Refused',
      body: 'Row',
    );
    pair.gateway.refuse('notes', note.id, SyncGatewayFailure.invalidData);
    await pair.owner.sync();
    relay.pokes.clear();

    await db().calendarEventDao.setSharedPair('e1', null);
    await pair.owner.sync();

    expect(relay.pokes, [(pair: sharePairId, urgent: true)]);
  });
}
