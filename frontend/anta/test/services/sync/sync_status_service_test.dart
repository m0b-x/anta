import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/sync_status_service.dart';

import '../../database/support/db_test_support.dart';
import 'support/sync_pair.dart' show eventRow;

const _accountA = AppUser(uid: 'uid-a');
const _accountB = AppUser(uid: 'uid-b');

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late SyncStatusService service;

  setUp(() async {
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    service = SyncStatusService.forTesting(
      db,
      SyncBindingService.forTesting(db, settings),
    );
  });

  tearDown(() async {
    SyncStatusService.reset();
    SyncBindingService.reset();
    SettingsService.reset();
    await db.close();
  });

  const binding = SyncBinding(
    spaceId: 'space-1',
    ownerUid: 'uid-a',
    accountUid: 'uid-a',
  );

  test('a fresh database reads as the empty status', () async {
    expect(await service.read(user: _accountA), SyncStatus.empty);
  });

  test('another account on a bound database pauses sync', () async {
    await settings.setSyncBinding(binding);

    final status = await service.read(user: _accountB);

    expect(status.pause, SyncPause.accountMismatch);
    expect(status.binding, binding);
  });

  test('the binding account runs unpaused', () async {
    await settings.setSyncBinding(binding);

    expect((await service.read(user: _accountA)).pause, SyncPause.none);
  });

  test('signed out on a bound database pauses as signed out', () async {
    await settings.setSyncBinding(binding);

    expect((await service.read()).pause, SyncPause.signedOut);
  });

  test('an unbound database never pauses', () async {
    expect((await service.read(user: _accountB)).pause, SyncPause.none);
    expect((await service.read()).pause, SyncPause.none);
  });

  test('the push and pull times read back as stored', () async {
    final pushed = DateTime.utc(2026, 10, 24, 8);
    final pulled = DateTime.utc(2026, 10, 24, 9);
    await db.syncDao.setValue(
      SyncDao.keyLastPushAt,
      '${pushed.millisecondsSinceEpoch}',
    );
    await db.syncDao.setValue(
      SyncDao.keyLastPullAt,
      '${pulled.millisecondsSinceEpoch}',
    );

    final status = await service.read(user: _accountA);

    expect(status.lastPushAt, pushed);
    expect(status.lastPullAt, pulled);
    expect(status.activity, SyncActivity.idle);
    expect(status.lastFailure, isNull);
  });

  group('SyncStatus', () {
    test('copyWith replaces what it names and keeps the rest', () {
      final failure = SyncFailureInfo(
        SyncGatewayFailure.offline,
        at: DateTime.utc(2026, 10, 24),
      );
      const start = SyncStatus(pendingCount: 3, binding: binding);

      final busy = start.copyWith(
        activity: SyncActivity.pulling,
        downloadedRows: 120,
        parkedCount: 1,
        lastFailure: failure,
      );

      expect(busy.pendingCount, 3);
      expect(busy.binding, binding);
      expect(busy.activity, SyncActivity.pulling);
      expect(busy.downloadedRows, 120);
      expect(busy.parkedCount, 1);
      expect(busy.lastFailure, failure);
      expect(busy, isNot(start), reason: 'every new field is in props');
      expect(busy.copyWith(clearLastFailure: true).lastFailure, isNull);
      expect(busy.copyWith(clearBinding: true).binding, isNull);
      expect(busy.copyWith(), busy);
    });

    test('each new field alone tells two statuses apart', () {
      const base = SyncStatus();
      for (final changed in [
        base.copyWith(lastPullAt: DateTime.utc(2026)),
        base.copyWith(activity: SyncActivity.pushing),
        base.copyWith(
          lastFailure: SyncFailureInfo(
            SyncGatewayFailure.unknown,
            at: DateTime.utc(2026),
          ),
        ),
        base.copyWith(parkedCount: 1),
        base.copyWith(downloadedRows: 1),
      ]) {
        expect(changed, isNot(base));
      }
      expect(const SyncStatus(), SyncStatus.empty);
    });
  });

  test('the pending count follows the outbox', () async {
    await db.folderDao.createFolder(name: 'One');
    await db.folderDao.createFolder(name: 'Two');
    expect((await service.read()).pendingCount, 2);

    await db.syncOutboxDao.clear();
    expect((await service.read()).pendingCount, 0);
  });

  test('a fresh clock is not ahead and has clamped nothing', () async {
    final status = await service.read(user: _accountA);

    expect(status.clockAhead, Duration.zero);
    expect(status.clampedRemotes, 0);
    expect(status.lastPushAt, isNull);
  });

  /// The rows the Sync page lists as held back (scalability record S7).
  group('held back', () {
    late Folder folder;

    setUp(() async {
      folder = await db.folderDao.createFolder(name: 'Training');
    });

    Future<Note> note(String title, {String content = 'Body'}) => db.noteDao
        .createNote(folderId: folder.id, title: title, content: content);

    SyncParkedRow park(
      String table,
      String rowKey,
      SyncHeldReason reason, {
      String stamp = '0001',
    }) => SyncParkedRow(table, rowKey, stamp, reason);

    test('nothing parked lists nothing', () async {
      expect(await service.heldBack(const []), isEmpty);
    });

    test('a row parked by its pull and its push is one item, under the '
        'stronger reason', () async {
      final leg = await note('Leg day');
      final arms = await note('Arms');

      final items = await service.heldBack([
        park('notes', leg.id, SyncHeldReason.refused),
        park('notes', leg.id, SyncHeldReason.unreadable),
        park('notes', arms.id, SyncHeldReason.unencodable),
        park('notes', arms.id, SyncHeldReason.awaitingText),
        park('notes', arms.id, SyncHeldReason.refused),
      ]);

      expect(items, hasLength(2));
      expect(
        {for (final item in items) item.name: item.reason},
        {
          'Leg day': SyncHeldReason.unreadable,
          'Arms': SyncHeldReason.awaitingText,
        },
      );
    });

    test('a chunk\'s park is its note\'s, folded with the note\'s own '
        'park', () async {
      final leg = await note('Leg day', content: 'Squat 5x5');
      final hash = (await db.contentChunkDao.hashesOf(leg.id)).single!;

      final alone = await service.heldBack([
        park('content_chunks', hash, SyncHeldReason.refused),
      ]);
      final folded = await service.heldBack([
        park('content_chunks', hash, SyncHeldReason.refused),
        park('notes', leg.id, SyncHeldReason.unencodable),
      ]);

      for (final items in [alone, folded]) {
        expect(items, [
          SyncHeldItem(
            table: 'notes',
            rowKey: leg.id,
            kind: SyncHeldKind.note,
            name: 'Leg day',
            reason: SyncHeldReason.refused,
          ),
        ]);
      }
    });

    test('names a live note, a deleted one and a folder; labels an event by '
        'its kind; sorts notes, then folders, then the other kinds', () async {
      final live = await note('zucchini log');
      final gone = await note('Arms');
      await db.noteDao.softDeleteNote(gone.id);
      final untitled = await note('   ');
      final archive = await db.folderDao.createFolder(name: 'Archive');
      await db.calendarEventDao.upsert(eventRow('e1'));
      await db.calendarEventDao.upsert(eventRow('e2'));
      await db.calendarEventDao.softDeleteById('e2');

      final items = await service.heldBack([
        park('calendar_events', 'e2', SyncHeldReason.refused, stamp: '0002'),
        park('calendar_events', 'e1', SyncHeldReason.refused, stamp: '0001'),
        park('folders', archive.id, SyncHeldReason.unreadable),
        park('notes', live.id, SyncHeldReason.refused),
        park('notes', gone.id, SyncHeldReason.refused),
        park('notes', untitled.id, SyncHeldReason.refused),
      ]);

      expect(
        [
          for (final item in items)
            (item.kind, item.rowKey, item.name, item.deleted),
        ],
        [
          (SyncHeldKind.note, untitled.id, '', false),
          (SyncHeldKind.note, gone.id, 'Arms', true),
          (SyncHeldKind.note, live.id, 'zucchini log', false),
          (SyncHeldKind.folder, archive.id, 'Archive', false),
          (SyncHeldKind.event, 'e1', null, false),
          (SyncHeldKind.event, 'e2', null, true),
        ],
      );
    });

    test('a note or folder this device holds no copy of goes unnamed, apart '
        'from one whose title is empty', () async {
      final items = await service.heldBack([
        park('notes', 'remote-note', SyncHeldReason.unreadable),
        park('folders', 'remote-folder', SyncHeldReason.unreadable),
      ]);

      expect(
        [for (final item in items) (item.kind, item.name, item.deleted)],
        [(SyncHeldKind.note, null, false), (SyncHeldKind.folder, null, false)],
      );
    });

    test('a chunk no live note holds is left out', () async {
      final leg = await note('Leg day', content: 'Squat 5x5');
      final hash = (await db.contentChunkDao.hashesOf(leg.id)).single!;
      await db.noteDao.softDeleteNote(leg.id);

      expect(
        await service.heldBack([
          park('content_chunks', hash, SyncHeldReason.refused),
          park('content_chunks', 'no-such-hash', SyncHeldReason.refused),
        ]),
        isEmpty,
      );
    });

    test('every synced table has a kind; a chunk alone is "other"', () {
      expect(SyncHeldKind.ofTable('calendar_event_skips'), SyncHeldKind.event);
      expect(SyncHeldKind.ofTable('counter_values'), SyncHeldKind.counter);
      expect(SyncHeldKind.ofTable('vocabulary_items'), SyncHeldKind.vocabulary);
      expect(SyncHeldKind.ofTable('content_chunks'), SyncHeldKind.other);
    });
  });
}
