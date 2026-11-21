import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/note_storage_service.dart';
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

  test('a poke owed to a pair that is no longer the active one is dropped '
      'unsent; the active pair\'s is sent (A7)', () async {
    await sharedAndSettled('e1');
    // A stale mark of an ended pair made a writer owe it a poke.
    await db().syncDao.oweSharePoke(pairId: 'pair-old', urgent: false);
    await rename('e1', 'Night shift');

    await pair.owner.sync();

    expect(relay.pokes, [(pair: sharePairId, urgent: true)]);
    expect(
      await db().syncDao.valuesByPrefix(SyncDao.sharePokeOwedPrefix),
      isEmpty,
      reason: 'the ended pair\'s entry is gone, not kept for later',
    );
  });

  test('the active pair is the one this phone\'s pairing stores now, not the '
      'one the last shared read named: a new pair is poked at once, the old '
      'one dropped (C4)', () async {
    await sharedAndSettled('e1');
    // This phone paired anew; no shared read has met it, so the reader's
    // key still names the pair before.
    pair.partners.localPairIds[ownerUid] = 'pair-new';
    expect(await db().syncDao.getValue(SyncDao.keySharedPair), sharePairId);
    await db().syncDao.oweSharePoke(pairId: 'pair-new', urgent: false);
    await rename('e1', 'Night shift');

    await pair.owner.sync();

    expect(relay.pokes, [(pair: 'pair-new', urgent: false)]);
    expect(
      await db().syncDao.valuesByPrefix(SyncDao.sharePokeOwedPrefix),
      isEmpty,
    );
  });

  test('with no pairing stored — a second database on the phone, whose '
      'pairing rows were never written — the pair the shared read holds as '
      'active is still poked (C4, A13)', () async {
    await sharedAndSettled('e1');
    // This database's own record names no pair, while a mark of its own
    // still shares the event and its reader holds the pair.
    pair.partners.local.clear();
    await rename('e1', 'Night shift');

    await pair.owner.sync();

    expect(relay.pokes, [(pair: sharePairId, urgent: true)]);
  });

  /// The pokes owed, as `pair: urgency`.
  Future<Map<String, String>> owedPokes() async => {
    for (final (key, value) in await db().syncDao.valuesByPrefix(
      SyncDao.sharePokeOwedPrefix,
    ))
      key.substring(SyncDao.sharePokeOwedPrefix.length): value,
  };

  /// Leaves the owner's database with no pairing stored and a reader that
  /// found its pair ended, owing that pair a poke the relay never had: an
  /// un-share whose poke could not go yet, the relay's address not known.
  Future<void> endedOwingAPoke() async {
    await sharedAndSettled('e1');
    final address = relay.address;
    relay.address = null;
    await db().calendarEventDao.setSharedPair('e1', null);
    await pair.owner.sync();
    relay.address = address;
    pair.end();
    pair.partners.local.clear();
    // The shared read meets the end before the run pokes.
    await pair.owner.sync();
  }

  test(
    'with no pairing stored, a poke owed while the shared read holds no '
    'pair after its pair ended is neither sent nor dropped: an ended pair '
    'still holds this account, and the relay serves it for a day (A13)',
    () async {
      await endedOwingAPoke();

      expect(relay.pokes, isEmpty);
      expect((await owedPokes()).keys, [sharePairId], reason: 'kept');

      // A run that only drains judges nothing either.
      await db().syncDao.oweSharePoke(pairId: 'pair-2', urgent: false);
      await pair.owner.engine.pushNow();
      await pair.owner.settle();
      expect(relay.pokes, isEmpty);
      expect(
        (await owedPokes()).keys,
        unorderedEquals([sharePairId, 'pair-2']),
      );
    },
  );

  test('what was kept is judged once the shared read holds a pair: the new '
      'pair\'s poke is sent, the ended pair\'s dropped (A13)', () async {
    await endedOwingAPoke();
    // Urgent, where what the run below owes is not: the poke sent is the
    // one kept.
    await db().syncDao.oweSharePoke(pairId: 'pair-2', urgent: true);
    await pair.owner.engine.pushNow();
    await pair.owner.settle();

    // A new pair, which this database's own record does not store: a mark
    // of it sends the reader to the server.
    pair.join(pairId: 'pair-2');
    pair.partners.local.clear();
    final shelf = await db().folderDao.createFolder(name: 'Shelf');
    await db().folderDao.setSharedPair(shelf.id, 'pair-2');
    await pair.owner.sync();

    expect(relay.pokes, [(pair: 'pair-2', urgent: true)]);
    expect(await owedPokes(), isEmpty);
  });

  test('with no pairing stored and a shared read that never met a partner, '
      'what is owed is sent as owed (A13)', () async {
    // The server cannot be asked, so the reader never begins a partner.
    pair.partners
      ..local.clear()
      ..failure = const SyncGatewayException(
        SyncGatewayFailure.offline,
        'scripted',
      );
    await event('e1');
    await db().calendarEventDao.setSharedPair('e1', sharePairId);

    await pair.owner.sync();

    expect(await db().syncDao.getValue(SyncDao.keySharedEverHeld), isNull);
    expect(relay.pokes, [(pair: sharePairId, urgent: true)]);
  });

  test('with no pairing stored, a poke owed to another pair than the one '
      'the shared read holds is dropped; that one\'s is sent (A13)', () async {
    await sharedAndSettled('e1');
    pair.partners.local.clear();
    await db().syncDao.oweSharePoke(pairId: 'pair-old', urgent: false);
    await rename('e1', 'Night shift');

    await pair.owner.sync();

    expect(relay.pokes, [(pair: sharePairId, urgent: true)]);
  });

  // A note's move owes its poke in the DAO's own transaction (share
  // surfaces P5), as every folder writer does: whoever moves it, and
  // whatever happens after the commit.
  group('a note moved', () {
    late Folder shelf;
    late Folder plain;
    late Note inside;
    late Note outside;

    /// The pokes owed, as `pair: urgency`.
    Future<Map<String, String>> owed() async => {
      for (final (key, value) in await db().syncDao.valuesByPrefix(
        SyncDao.sharePokeOwedPrefix,
      ))
        key.substring(SyncDao.sharePokeOwedPrefix.length): value,
    };

    setUp(() async {
      shelf = await db().folderDao.createFolder(name: 'Shelf');
      plain = await db().folderDao.createFolder(name: 'Plain');
      inside = await writeNote(
        pair.owner,
        folderId: shelf.id,
        title: 'Inside',
        body: 'Shared',
      );
      outside = await writeNote(
        pair.owner,
        folderId: plain.id,
        title: 'Outside',
        body: 'Private',
      );
      await db().folderDao.setSharedPair(shelf.id, sharePairId);
      await pair.owner.sync();
      await pair.owner.sync();
      relay.pokes.clear();
      await db().syncDao.deleteByPrefix(SyncDao.sharePokeOwedPrefix);
    });

    test('out of a shared folder by the DAO owes the pair a normal poke '
        'with the move, which the next run sends (P5)', () async {
      await db().noteDao.moveNote(id: inside.id, targetFolderId: plain.id);

      expect(await owed(), {sharePairId: 'normal'});
      await pair.owner.sync();
      expect(relay.pokes, [(pair: sharePairId, urgent: false)]);
    });

    test('into a shared folder by the DAO owes it too (P5)', () async {
      await db().noteDao.moveNote(id: outside.id, targetFolderId: shelf.id);

      expect(await owed(), {sharePairId: 'normal'});
    });

    test('as a selection, out of a shared folder, owes it too (P5)', () async {
      await db().noteDao.moveNotes([inside.id, outside.id], plain.id);

      expect(await owed(), {sharePairId: 'normal'});
    });

    test('between two private folders owes nothing (P5)', () async {
      final other = await db().folderDao.createFolder(name: 'Other');

      await db().noteDao.moveNote(id: outside.id, targetFolderId: other.id);
      await db().noteDao.moveNotes([outside.id], plain.id);

      expect(await owed(), isEmpty);
    });

    test('re-filed by the repair from under a deleted folder into a shared '
        'one owes the pair a normal poke (P5)', () async {
      final gone = await db().folderDao.createFolder(
        name: 'Gone',
        parentId: shelf.id,
      );
      final stranded = await writeNote(
        pair.owner,
        folderId: gone.id,
        title: 'Stranded',
        body: 'Text',
      );
      // Deleted on another device below the note's stamp: the note lies live
      // under a tombstone, private until the repair re-files it.
      await db().customStatement(
        'UPDATE folders SET is_deleted = 1, '
        "hlc_timestamp = '0000000000001:0000:other' WHERE id = ?",
        [gone.id],
      );
      await db().syncDao.deleteByPrefix(SyncDao.sharePokeOwedPrefix);

      final moved = await db().noteDao.refileNotesUnderDeletedFolders();

      expect(moved, [(id: stranded.id, folderId: gone.id)]);
      expect(await owed(), {sharePairId: 'normal'});
    });

    // A guard, not P5's: the mark's own writer owed this before.
    test('an un-share owes the pair a normal poke, as it always did', () async {
      await db().folderDao.setSharedPair(shelf.id, null);

      expect(await owed(), {sharePairId: 'normal'});
    });

    test('re-filed by the repair as it merges, from under a deleted folder '
        'into a shared one, owes the pair a normal poke (B8)', () async {
      final gone = await db().folderDao.createFolder(
        name: 'Gone',
        parentId: shelf.id,
      );
      await db().customStatement(
        'UPDATE folders SET is_deleted = 1, '
        "hlc_timestamp = '0000000000001:0000:other' WHERE id = ?",
        [gone.id],
      );
      await db().syncDao.deleteByPrefix(SyncDao.sharePokeOwedPrefix);

      await db().noteDao.mergeNoteDocument(
        outside.copyWith(
          id: 'arrived',
          folderId: gone.id,
          hlcTimestamp: 'ffffffffff01:0000:other',
          deviceId: 'other',
        ),
        'Edited elsewhere',
      );

      expect(
        (await db().noteDao.getByIdsIncludingDeleted([
          'arrived',
        ])).single.folderId,
        shelf.id,
      );
      expect(await owed(), {sharePairId: 'normal'});
    });

    test('between two folders marked for different pairs owes both a normal '
        'poke (B8)', () async {
      final other = await db().folderDao.createFolder(name: 'Other pair');
      // A mark of another pair stands only until the next share act clears
      // it; a merge can leave one meanwhile.
      await db().customStatement(
        "UPDATE folders SET shared_pair = 'pair-2' WHERE id = ?",
        [other.id],
      );

      await db().noteDao.moveNote(id: inside.id, targetFolderId: other.id);

      expect(await owed(), {sharePairId: 'normal', 'pair-2': 'normal'});
    });

    test('through the storage service\'s own move owes it once (B8)', () async {
      final notes = NoteStorageService(
        repository: NoteRepository(database: db()),
      );

      await notes.moveNote(noteId: inside.id, targetFolderId: plain.id);

      expect(await owed(), {sharePairId: 'normal'});
    });
  });

  test('a database that shares nothing pays no statement for a note\'s '
      'poke: a move, one or many, costs what it did before (P5)', () async {
    final a = await db().folderDao.createFolder(name: 'A');
    final b = await db().folderDao.createFolder(name: 'B');
    final one = await writeNote(
      pair.owner,
      folderId: a.id,
      title: 'One',
      body: 'x',
    );
    final two = await writeNote(
      pair.owner,
      folderId: a.id,
      title: 'Two',
      body: 'y',
    );
    final statements = pair.owner.statements..reset();

    await db().noteDao.moveNote(id: one.id, targetFolderId: b.id);
    final single = statements.count;
    statements.reset();
    await db().noteDao.moveNotes([one.id, two.id], a.id);
    final many = statements.count;

    // Measured before the DAO owed the poke: the marks are asked inside the
    // statement that reads the target's last position.
    expect((single: single, many: many), (single: 7, many: 7));
    expect(statements.matching('share_poke_owed'), isEmpty);
  });
}
