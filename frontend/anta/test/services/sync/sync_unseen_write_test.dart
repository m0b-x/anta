import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/chunking/chunk_hasher.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/tables/notes_binding.dart';

import 'support/sync_pair.dart';

/// A push never writes over a version of a note this device has not seen
/// (scalability record §11.1, D4 B): the push names each note's `note_seen`,
/// the gateway compares it with the stored document inside the write, and a
/// version this device never saw is merged first — under the copy rules that
/// already exist — before the batch goes again.
void main() {
  late SyncPair pair;
  SyncDevice a() => pair.a;
  SyncDevice b() => pair.b;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  /// A note written on A and pulled by B, both devices past the initial
  /// merge, the recorders cleared.
  Future<Note> sharedNote() async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    final note = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Log',
      body: 'base',
    );
    await a().sync();
    await b().sync();
    a().hooks.clear();
    b().hooks.clear();
    return note;
  }

  /// [device] started and then sent away, so it hears no signal and its
  /// next leave drains without pulling.
  Future<void> away(SyncDevice device) async {
    await device.engine.start();
    await device.settle();
    await device.engine.onAppBackgrounded();
  }

  /// Back in front, its runs settled.
  Future<void> back(SyncDevice device) async {
    device.engine.onAppResumed();
    await device.settle();
  }

  int pushCalls(SyncDevice device) =>
      pair.gateway.calls.where((c) => c == 'push:${device.id}').length;

  SyncEnvelope stored(String noteId) =>
      pair.gateway.rowsOf(pair.space, 'notes')[noteId]!;

  Future<String> stampOn(SyncDevice device, String noteId) async =>
      (await device.db.noteDao.getNoteById(noteId))!.hlcTimestamp;

  Future<SyncOutboxRow?> entryOn(SyncDevice device, String noteId) async =>
      (await device.db.syncOutboxDao.pendingKeys('notes', [noteId]))[noteId];

  /// While [active] says so, every hold plants each version the push found
  /// one step above itself — a device that writes the note again as fast as
  /// this one merges it. One entry per hold that planted.
  List<int> rivalWhile(bool Function() active) {
    final rounds = <int>[];
    pair.gateway.onUnseenVersions = (page) {
      if (!active()) return;
      rounds.add(page.envelopes.length);
      for (final version in page.envelopes) {
        pair.gateway.plant(pair.space, _restamped(version), pushedBy: 'A');
      }
    };
    return rounds;
  }

  /// Every line the engine logs from here to the end of the test.
  List<String> captureLog() {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = original);
    return printed;
  }

  Future<void> expectBody(
    List<SyncDevice> devices,
    String noteId,
    String body,
  ) async {
    for (final device in devices) {
      expect(
        await device.db.contentChunkDao.loadContent(noteId),
        body,
        reason: device.id,
      );
    }
  }

  test('a newer edit drained blind merges the older one pushed first: its '
      'text is filed as one copy and the newer text lands', () async {
    final note = await sharedNote();
    await away(b());
    await editNote(a(), note.id, 'typed on A');
    await a().sync();
    await editNote(b(), note.id, 'typed on B');
    pair.gateway.calls.clear();
    final accepted = pair.gateway.pushes.length;

    final report = await b().engine.onAppBackgrounded();

    expect(report.failure, isNull);
    final conflict = b().hooks.conflicts.single;
    expect(conflict.incoming, isTrue);
    expect(conflict.loserContent, 'typed on A');
    expect(pushCalls(b()), 2);
    expect(pair.gateway.pushes.length - accepted, 1);
    expect(stored(note.id).deviceId, b().id);

    await back(b());
    await a().sync();
    await b().sync();
    expect(a().hooks.conflicts, isEmpty);
    expect(b().hooks.conflicts, hasLength(1));
    await expectBody([a(), b()], note.id, 'typed on B');
  });

  test('an edit with the older stamp drained blind lands nothing: its text '
      'is the copy and the space keeps the newer text', () async {
    final note = await sharedNote();
    await away(b());
    await editNote(b(), note.id, 'typed on B');
    await editNote(a(), note.id, 'typed on A');
    await a().sync();
    final newer = await stampOn(a(), note.id);
    pair.gateway.calls.clear();

    final report = await b().engine.onAppBackgrounded();

    expect(report.failure, isNull);
    expect(report.pushedRows, 0);
    expect(pushCalls(b()), 1);
    expect(stored(note.id).hlc, newer);
    expect(await entryOn(b(), note.id), isNull);
    final conflict = b().hooks.conflicts.single;
    expect(conflict.incoming, isFalse);
    expect(conflict.loserContent, 'typed on B');

    await back(b());
    await a().sync();
    await b().sync();
    expect(a().hooks.conflicts, isEmpty);
    await expectBody([a(), b()], note.id, 'typed on A');
  });

  test(
    'a third device whose clock runs behind, draining blind over an edit '
    'made on top of an edit it never saw, keeps its text as one copy',
    () async {
      final note = await sharedNote();
      final c = await pair.addDevice('C', ahead: const Duration(hours: -1));
      await c.sync();
      await away(c);
      await editNote(a(), note.id, 'typed on A');
      await a().sync();
      final first = await stampOn(a(), note.id);
      await b().sync();
      await editNote(b(), note.id, 'typed on B');
      await b().sync();
      await a().sync();
      await editNote(c, note.id, 'typed on C');
      // Stamped below what A and B have both seen: the version (T) loses.
      expect((await stampOn(c, note.id)).compareTo(first), lessThan(0));

      final report = await c.engine.onAppBackgrounded();

      expect(report.failure, isNull);
      final written = stored(note.id).deviceId;
      await back(c);
      for (final device in [a(), b(), c, a(), b()]) {
        await device.sync();
      }
      final conflict = c.hooks.conflicts.single;
      expect(conflict.loserContent, 'typed on C');
      expect(a().hooks.conflicts, isEmpty);
      expect(b().hooks.conflicts, isEmpty);
      await expectBody([a(), b(), c], note.id, 'typed on B');
      expect(written, b().id);
    },
  );

  test('a tombstone drained over an unseen edit files that edit as a copy, '
      'then lands', () async {
    final note = await sharedNote();
    await away(b());
    await editNote(a(), note.id, 'typed on A');
    await a().sync();
    await b().db.noteDao.softDeleteNoteWithChunks(note.id);
    pair.gateway.calls.clear();

    final report = await b().engine.onAppBackgrounded();

    expect(report.failure, isNull);
    final conflict = b().hooks.conflicts.single;
    expect(conflict.incoming, isTrue);
    expect(conflict.loserContent, 'typed on A');
    expect(pushCalls(b()), 2);
    expect(stored(note.id).op, OutboxOp.tombstone);
    expect(stored(note.id).deviceId, b().id);
  });

  test('the device\'s own version stored — a lost acknowledgement, then '
      'another edit — goes in one call with no merge', () async {
    final note = await sharedNote();
    await away(a());
    await editNote(a(), note.id, 'typed on A');
    var lose = true;
    pair.gateway.onPushBatch = (_) async {
      if (!lose) return;
      lose = false;
      throw const SyncGatewayException(SyncGatewayFailure.offline, 'lost');
    };
    expect(
      (await a().engine.onAppBackgrounded()).failure,
      SyncGatewayFailure.offline,
    );
    expect(stored(note.id).deviceId, a().id);
    await editNote(a(), note.id, 'typed again on A');
    pair.gateway.calls.clear();
    a().hooks.clear();

    final report = await a().engine.onAppBackgrounded();

    expect(report.failure, isNull);
    expect(pushCalls(a()), 1);
    expect(a().hooks.calls.where((c) => c == 'before:notes'), isEmpty);
    expect(a().hooks.conflicts, isEmpty);
    expect(await stampOn(a(), note.id), stored(note.id).hlc);
  });

  test('a note nobody else touched goes in one call, its guard reading one '
      'document', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    final note = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Log',
      body: 'base',
    );

    final report = await a().sync();

    expect(report.failure, isNull);
    expect(pushCalls(a()), 1);
    expect(pair.gateway.guardReads, 1);
    expect(pair.gateway.seenMaps.single, {('notes', note.id): ''});
    expect(a().hooks.calls.where((c) => c == 'before:notes'), isEmpty);
    expect(stored(note.id).deviceId, a().id);
  });

  test('a stored document this build cannot read does not refuse the '
      'write', () async {
    final note = await sharedNote();
    await away(b());
    await editNote(a(), note.id, 'typed on A');
    await a().sync();
    pair.gateway.unreadable.add(('notes', note.id));
    await editNote(b(), note.id, 'typed on B');
    pair.gateway.calls.clear();

    final report = await b().engine.onAppBackgrounded();

    expect(report.failure, isNull);
    expect(pushCalls(b()), 1);
    expect(stored(note.id).deviceId, b().id);
    expect(b().hooks.conflicts, isEmpty);
  });

  test('a rival writing a new version after every merge ends the drain '
      'quietly after the rounds allowed, the entry still queued; the next '
      'drain lands it', () async {
    final note = await sharedNote();
    await away(b());
    await editNote(a(), note.id, 'typed on A');
    await a().sync();
    await editNote(b(), note.id, 'typed on B');
    var rival = true;
    final rounds = rivalWhile(() => rival);
    final printed = captureLog();

    final held = await b().engine.onAppBackgrounded();

    expect(held.failure, isNull);
    expect(rounds.length, SyncEngine.maxUnseenRounds + 1);
    expect(await entryOn(b(), note.id), isNotNull);
    expect(stored(note.id).deviceId, a().id);
    expect(
      printed.where((line) => line.contains('unseen version')),
      hasLength(1),
    );

    rival = false;
    final landed = await b().engine.onAppBackgrounded();

    expect(landed.failure, isNull);
    expect(stored(note.id).deviceId, b().id);
    expect(await entryOn(b(), note.id), isNull);
  });

  test('a batch with no note names nothing and reads nothing', () async {
    await a().db.calendarEventDao.upsert(eventRow('e1'));

    final report = await a().sync();

    expect(report.failure, isNull);
    expect(pair.gateway.seenMaps, isNotEmpty);
    expect(pair.gateway.seenMaps, everyElement(isEmpty));
    expect(pair.gateway.guardReads, 0);
  });

  group('a note whose foreign version no merge recorded as seen', () {
    Future<String?> seenOn(SyncDevice device, String noteId) =>
        device.db.syncDao.getValue(SyncDao.keyNoteSeen(noteId));

    test('accepted before note_seen existed: a start seeds it once, and an '
        'edit drained after files no copy', () async {
      final note = await sharedNote();
      final accepted = await stampOn(b(), note.id);
      await b().db.customStatement(
        'DELETE FROM sync_metadata WHERE key IN (?, ?)',
        [SyncDao.keyNoteSeen(note.id), SyncDao.keyNoteSeenSeeded],
      );
      await b().engine.stop();
      await b().engine.start();
      await b().settle();
      await b().sync();
      expect(await seenOn(b(), note.id), accepted);
      expect(await b().db.syncDao.getValue(SyncDao.keyNoteSeenSeeded), '1');

      await editNote(b(), note.id, 'typed on B');
      pair.gateway.calls.clear();
      final report = await b().sync();

      expect(report.failure, isNull);
      expect(pushCalls(b()), 1);
      expect(b().hooks.conflicts, isEmpty);
      expect(stored(note.id).deviceId, b().id);
    });

    test('left unchanged by an initial merge: its end seeds it, and an edit '
        'drained after files no copy', () async {
      final note = await sharedNote();
      final accepted = await stampOn(b(), note.id);
      // The state a restore or a merge of identical data leaves: the row as
      // the space holds it, no `note_seen`, the bind's merge still to run.
      await b().db.customStatement('DELETE FROM sync_metadata WHERE key = ?', [
        SyncDao.keyNoteSeen(note.id),
      ]);
      await b().db.syncDao.deleteByPrefix(SyncDao.pullCursorPrefix);
      await b().db.syncDao.setValue(SyncDao.keyBindMergePending, '1');

      await b().sync();
      expect(
        await b().db.syncDao.getValue(SyncDao.keyBindMergePending),
        isNull,
      );
      expect(await seenOn(b(), note.id), accepted);

      await editNote(b(), note.id, 'typed on B');
      pair.gateway.calls.clear();
      final report = await b().sync();

      expect(report.failure, isNull);
      expect(pushCalls(b()), 1);
      expect(b().hooks.conflicts, isEmpty);
      expect(stored(note.id).deviceId, b().id);
    });
  });

  test('a mixed batch with an unseen note lands neither row in the first '
      'call and both after the merge', () async {
    final note = await sharedNote();
    await away(b());
    await editNote(a(), note.id, 'typed on A');
    await a().sync();
    await editNote(b(), note.id, 'typed on B');
    await b().db.calendarEventDao.upsert(eventRow('e1'));
    pair.gateway.calls.clear();
    final accepted = pair.gateway.pushes.length;

    final report = await b().engine.onAppBackgrounded();

    expect(report.failure, isNull);
    expect(pushCalls(b()), 2);
    final landed = pair.gateway.pushes.sublist(accepted).single;
    expect({
      for (final envelope in landed) envelope.table,
    }, containsAll(['notes', 'calendar_events']));
    expect(stored(note.id).deviceId, b().id);
    expect(b().hooks.conflicts.single.loserContent, 'typed on A');
  });

  group('a merge of the held version that fails', () {
    for (final failure in [
      const SyncGatewayException.timedOut(),
      const SyncGatewayException(SyncGatewayFailure.permissionDenied, 'x'),
      const SyncGatewayException(SyncGatewayFailure.offline, 'x'),
    ]) {
      test('${failure.timedOut ? 'timedOut' : failure.failure.name} ends the '
          'run as a pull page\'s would: nothing parked, the part budget kept, '
          'the entry queued; the next run lands it', () async {
        final note = await sharedNote();
        await away(b());
        await editNote(a(), note.id, 'typed on A');
        await a().sync();
        await editNote(b(), note.id, 'typed on B');
        final budget = b().engine.partBudgetForTesting;
        var armed = true;
        // The merge's first call is its read of A's chunk.
        pair.gateway.onUnseenVersions = (_) {
          if (!armed) return;
          armed = false;
          pair.gateway.failNextWithException(failure);
        };

        final report = await b().engine.onAppBackgrounded();

        expect(report.failure, failure.failure);
        expect(report.parked, 0);
        expect(b().engine.partBudgetForTesting, budget);
        expect(await entryOn(b(), note.id), isNotNull);
        expect(stored(note.id).deviceId, a().id);

        await back(b());
        final next = await b().sync();
        expect(next.failure, isNull);
        expect(stored(note.id).deviceId, b().id);
        expect(b().engine.current.parkedCount, 0);
      });
    }
  });

  test('a rival that keeps a note held holds back only that note: the event '
      'of the same part lands in the same drain', () async {
    final note = await sharedNote();
    await away(b());
    await editNote(a(), note.id, 'typed on A');
    await a().sync();
    await editNote(b(), note.id, 'typed on B');
    await b().db.calendarEventDao.upsert(eventRow('e1'));
    rivalWhile(() => true);
    final printed = captureLog();

    final report = await b().engine.onAppBackgrounded();

    expect(report.failure, isNull);
    expect(
      pair.gateway.rowsOf(pair.space, 'calendar_events')['e1']?.deviceId,
      b().id,
    );
    expect(await entryOn(b(), note.id), isNotNull);
    final waits = printed.where((l) => l.contains('unseen version')).single;
    expect(waits, contains('notes/${note.id}'));
    // By its table, never by the bare id: the note's id is random, and one
    // in eight of them holds the letters "e1".
    expect(waits, isNot(contains('calendar_events')));
  });

  test('a hold inside a bisect: the refused row parks, the unseen note is '
      'merged and lands, nothing else parks', () async {
    final note = await sharedNote();
    await away(b());
    await b().db.calendarEventDao.upsert(eventRow('e1'));
    await editNote(b(), note.id, 'typed on B');
    pair.gateway.refuse(
      'calendar_events',
      'e1',
      SyncGatewayFailure.permissionDenied,
    );
    // A's write lands while B bisects: after the whole batch was denied,
    // before the half holding the note goes.
    var call = 0;
    pair.gateway.beforePushBatch = (_) {
      if (++call == 2) {
        pair.gateway.plant(pair.space, _restamped(stored(note.id)));
      }
    };
    pair.gateway.calls.clear();

    final report = await b().engine.onAppBackgrounded();

    expect(report.failure, isNull);
    expect(report.parked, 1);
    expect(b().engine.current.parkedCount, 1);
    expect(pair.gateway.rowsOf(pair.space, 'calendar_events'), isEmpty);
    expect(stored(note.id).deviceId, b().id);
    expect(b().hooks.conflicts.single.loserContent, 'base');
  });

  test('a held version whose merge parks holds its entry back: the note is '
      'not pushed again, the entry queued', () async {
    final note = await sharedNote();
    await away(b());
    await editNote(a(), note.id, 'typed on A');
    await a().sync();
    // The space's version names a chunk it was never sent.
    const missing = 'Deadlift 1x5';
    final version = stored(note.id);
    pair.gateway.plant(
      pair.space,
      _restamped(
        version,
        data: {
          ...version.data!,
          NotesBinding.chunksKey: [ChunkHasher.hash(missing)],
          NotesBinding.bodyHashKey: ChunkHasher.hash(missing),
        },
      ),
    );
    await editNote(b(), note.id, 'typed on B');
    final accepted = pair.gateway.pushes.length;

    final report = await b().engine.onAppBackgrounded();

    expect(report.failure, isNull);
    // Only the note's new chunk goes again: it names no note.
    expect([
      for (final batch in pair.gateway.pushes.sublist(accepted))
        for (final envelope in batch) envelope.table,
    ], everyElement('content_chunks'));
    expect(
      await b().db.syncDao.getValue(SyncDao.keyPullParked('notes', note.id)),
      isNotNull,
    );
    expect(await entryOn(b(), note.id), isNotNull);
    expect(stored(note.id).deviceId, a().id);
  });

  test('two unseen notes in one batch: one hold, both merged, one more '
      'push', () async {
    final note = await sharedNote();
    final other = await writeNote(
      a(),
      folderId: note.folderId,
      title: 'Other',
      body: 'other',
    );
    await a().sync();
    await b().sync();
    await away(b());
    await editNote(a(), note.id, 'typed on A');
    await editNote(a(), other.id, 'other on A');
    await a().sync();
    await editNote(b(), note.id, 'typed on B');
    await editNote(b(), other.id, 'other on B');
    final holds = <int>[];
    pair.gateway.onUnseenVersions = (page) => holds.add(page.envelopes.length);
    pair.gateway.calls.clear();

    final report = await b().engine.onAppBackgrounded();

    expect(report.failure, isNull);
    expect(holds, [2]);
    expect(pushCalls(b()), 2);
    expect(b().hooks.conflicts, hasLength(2));
    expect(stored(note.id).deviceId, b().id);
    expect(stored(other.id).deviceId, b().id);
  });

  group('the blind runs go through the guard', () {
    /// B in front with its listener current, then deaf to A's push.
    Future<Note> deafB() async {
      final note = await sharedNote();
      await b().engine.start();
      await b().settle();
      pair.gateway.muteSignals = true;
      await editNote(a(), note.id, 'typed on A');
      await a().sync();
      await editNote(b(), note.id, 'typed on B');
      pair.gateway.calls.clear();
      return note;
    }

    test('pushNow', () async {
      final note = await deafB();

      final report = await b().engine.pushNow();

      expect(report.failure, isNull);
      expect(pushCalls(b()), 2);
      expect(b().hooks.conflicts.single.loserContent, 'typed on A');
      expect(stored(note.id).deviceId, b().id);
    });

    test('a stale run whose snapshot names no table', () async {
      final note = await deafB();

      expect(
        b().scheduler.fire(const SyncEngineTiming().pushDebounce),
        greaterThan(0),
      );
      await b().settle();

      expect(pair.gateway.calls.where((c) => c.startsWith('pull:')), isEmpty);
      expect(pushCalls(b()), 2);
      expect(b().hooks.conflicts.single.loserContent, 'typed on A');
      expect(stored(note.id).deviceId, b().id);
    });
  });

  test('a held batch with a grant owes its poke only once it lands', () async {
    final note = await sharedNote();
    await a().db.folderDao.setSharedPair(note.folderId, sharePairId);
    await a().sync();
    await b().sync();
    await b().db.syncDao.deleteValue(SyncDao.keySharePokeOwed(sharePairId));
    await away(b());
    await editNote(a(), note.id, 'typed on A');
    await a().sync();
    await editNote(b(), note.id, 'typed on B');
    var rival = true;
    rivalWhile(() => rival);
    Future<String?> owed() =>
        b().db.syncDao.getValue(SyncDao.keySharePokeOwed(sharePairId));

    await b().engine.onAppBackgrounded();

    expect(await entryOn(b(), note.id), isNotNull);
    expect(await owed(), isNull);

    rival = false;
    await b().engine.onAppBackgrounded();

    expect(stored(note.id).sharedPair, sharePairId);
    expect(await owed(), isNotNull);
  });

  group('the seed', () {
    Future<String?> seenOn(SyncDevice device, String noteId) =>
        device.db.syncDao.getValue(SyncDao.keyNoteSeen(noteId));

    int flagReads(SyncDevice device) => device.statements.captured
        .where((s) => s.args.contains(SyncDao.keyNoteSeenSeeded))
        .where((s) => s.isSelect)
        .length;

    test('runs before the drain of a bind\'s first pull that faulted on a '
        'table, so a row it left unchanged and then edited files no '
        'copy', () async {
      final note = await sharedNote();
      // The bind's merge to run again over rows it will find unchanged, no
      // `note_seen` for them, and the flag set: no start seeds them.
      await b().db.customStatement('DELETE FROM sync_metadata WHERE key = ?', [
        SyncDao.keyNoteSeen(note.id),
      ]);
      await b().db.syncDao.deleteByPrefix(SyncDao.pullCursorPrefix);
      await b().db.syncDao.setValue(SyncDao.keyBindMergePending, '1');
      var fault = true;
      b().hooks.onBeforePage = (table) async {
        if (fault && table == 'folders') throw StateError('scripted');
      };

      final first = await b().sync();
      expect(first.failure, isNotNull);
      expect(
        await b().db.syncDao.getValue(SyncDao.keyBindMergePending),
        isNotNull,
      );
      expect(await seenOn(b(), note.id), await stampOn(a(), note.id));

      fault = false;
      await editNote(b(), note.id, 'typed on B');
      pair.gateway.calls.clear();
      final report = await b().sync();

      expect(report.failure, isNull);
      expect(pushCalls(b()), 1);
      expect(b().hooks.conflicts, isEmpty);
      expect(stored(note.id).deviceId, b().id);
    });

    test('is dropped with note_seen at a bind to another space, whose merge '
        'seeds again; its check reads the flag once per start', () async {
      final note = await sharedNote();
      final accepted = await stampOn(b(), note.id);
      final other = (await pair.gateway.createSpace(
        ownerUid: syncUid,
        name: 'Other',
        deviceId: b().id,
        schema: syncSchema,
      )).ref;
      await b().binding.unbind();
      await b().binding.bind(space: other, accountUid: syncUid);
      expect(await b().db.syncDao.getValue(SyncDao.keyNoteSeenSeeded), isNull);
      expect(await seenOn(b(), note.id), isNull);

      await b().sync();
      expect(await b().db.syncDao.getValue(SyncDao.keyNoteSeenSeeded), '1');
      expect(await seenOn(b(), note.id), accepted);

      b().statements.reset();
      await b().engine.stop();
      await b().engine.start();
      await b().settle();
      await b().sync();
      await b().sync();
      expect(flagReads(b()), 1);
    });
  });

  test('a blind older overwrite by a build that names nothing is still '
      'repaired: the newer row is kept, the older text filed once, and the '
      're-push lands through the guard', () async {
    final note = await sharedNote();
    await away(b());
    pair.gateway.olderBuilds.add(b().id);
    await editNote(b(), note.id, 'typed on B');
    await editNote(a(), note.id, 'typed on A');
    await a().sync();
    final older = await stampOn(b(), note.id);

    await b().engine.onAppBackgrounded();
    expect(stored(note.id).deviceId, b().id);
    await a().sync();

    final conflict = a().hooks.conflicts.single;
    expect(conflict.incoming, isTrue);
    expect(conflict.loserContent, 'typed on B');
    expect(stored(note.id).deviceId, a().id);
    expect(pair.gateway.seenMaps.last[('notes', note.id)], older);
    await back(b());
    await b().sync();
    await a().sync();
    expect(b().hooks.conflicts, isEmpty);
    expect(a().hooks.conflicts, hasLength(1));
    await expectBody([a(), b()], note.id, 'typed on A');
  });
}

/// [version] as its device's next write would store it: one step above its
/// stamp, its text unless [data] says otherwise.
SyncEnvelope _restamped(SyncEnvelope version, {Map<String, Object?>? data}) {
  final stamp = HlcTimestamp.parse(version.hlc);
  return SyncEnvelope(
    table: version.table,
    rowKey: version.rowKey,
    hlc: HlcTimestamp(
      wallTime: stamp.wallTime,
      logicalCounter: stamp.logicalCounter + 1,
      nodeId: stamp.nodeId,
    ).toString(),
    deviceId: version.deviceId,
    version: version.version + 1,
    op: version.op,
    ownerId: version.ownerId,
    data: data ?? version.data,
    sharedPair: version.sharedPair,
  );
}
