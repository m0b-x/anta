import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/constants/sync_limits.dart';
import 'package:anta/database/crdt/merge_outcome.dart';
import 'package:anta/database/daos/content_chunk_dao.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/tables/notes_binding.dart';
import 'package:anta/utils/sync_moment_format.dart';

import '../../support/scale_fixtures.dart';
import 'support/sync_pair.dart';

/// What a notes sync holds the database for (the stall after the S6
/// install). On the pull: the bodies are assembled, cut and encoded before
/// the page's transaction, and so is the local text the conflict check
/// compares; a page whose bodies outgrow [SyncEngine.pullBodyBudget] is
/// stored in parts, the run that cuts over to the chunked wire says so, and
/// "Stop syncing" in the middle of it settles. On the push: each body is
/// hashed for its manifest before any transaction opens.
void main() {
  late SyncPair pair;
  SyncDevice a() => pair.a;
  SyncDevice b() => pair.b;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  /// A body of [length] code units no other note's chunks share.
  String bodyOf(int note, int length) =>
      bigBody(length).replaceAll('Week', 'Note $note, week');

  Future<String> bodyOn(SyncDevice device, String id) =>
      device.db.contentChunkDao.loadContent(id);

  /// The rows each `afterPage` of `notes` on [device] carried.
  List<int> notesParts(SyncDevice device) => [
    for (final (table, rows) in device.hooks.pages)
      if (table == 'notes') rows.length,
  ];

  test('no body is cut and no chunk encoded while a transaction holds the '
      'database of the device pulling, whether a note is new to it or '
      'edited', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Logs');
    final notes = [
      for (final (i, length) in [300000, 120000, 70000, 900, 40].indexed)
        await writeNote(
          a(),
          folderId: folder.id,
          title: 'Log $i',
          body: bodyOf(i, length),
        ),
    ];
    await a().sync();

    final inside = <String>[];
    var cuts = 0;
    var encodes = 0;
    b().statements.onTransaction = (begins) {
      if (begins) {
        cuts = BodyCut.cutCount;
        encodes = ContentChunkDao.encodeCount;
      } else if (BodyCut.cutCount != cuts ||
          ContentChunkDao.encodeCount != encodes) {
        inside.add(
          '${BodyCut.cutCount - cuts} cuts, '
          '${ContentChunkDao.encodeCount - encodes} encodes',
        );
      }
    };
    final cutsBefore = BodyCut.cutCount;
    final encodesBefore = ContentChunkDao.encodeCount;

    final pulled = await b().sync();

    expect(pulled.failure, isNull);
    expect(inside, isEmpty);
    expect(BodyCut.cutCount - cutsBefore, notes.length, reason: 'one each');
    expect(ContentChunkDao.encodeCount, greaterThan(encodesBefore));
    for (final (i, note) in notes.indexed) {
      expect(
        await bodyOn(b(), note.id),
        await bodyOn(a(), note.id),
        reason: i.toString(),
      );
    }

    final edited = '${await bodyOn(a(), notes[0].id)}\nOne more set.';
    await editNote(a(), notes[0].id, edited);
    await a().sync();
    final encodesBeforeEdit = ContentChunkDao.encodeCount;

    final again = await b().sync();

    expect(again.failure, isNull);
    expect(inside, isEmpty);
    expect(await bodyOn(b(), notes[0].id), edited);
    expect(
      ContentChunkDao.encodeCount - encodesBeforeEdit,
      lessThanOrEqualTo(2),
      reason: 'only the chunks the edit changed are encoded',
    );
  });

  test('a notes page whose bodies outgrow the budget is stored in parts, '
      'each its own transaction, and only the last moves the cursor', () async {
    const length = 800000;
    expect(2 * length, lessThanOrEqualTo(SyncEngine.pullBodyBudget));
    expect(3 * length, greaterThan(SyncEngine.pullBodyBudget));
    final folder = await a().db.folderDao.createFolder(name: 'Years');
    final notes = [
      for (var i = 0; i < 5; i++)
        await writeNote(
          a(),
          folderId: folder.id,
          title: 'Year $i',
          body: bodyOf(i, length),
        ),
    ];
    final (pushed, _) = await a().syncFiringSpacing();
    expect(pushed.failure, isNull);
    final cursors = <String?>[];
    b().hooks.onAfterPage = (table, rows) async {
      if (table != 'notes' || rows.isEmpty) return;
      cursors.add(await b().db.syncDao.getValue(SyncDao.keyPullCursor(table)));
    };

    final pulled = await b().sync();

    expect(pulled.failure, isNull);
    expect(notesParts(b()), [2, 2, 1]);
    expect(cursors.take(2), everyElement(isNull));
    expect(cursors.last, isNotNull);
    for (final note in notes) {
      expect(await bodyOn(b(), note.id), await bodyOn(a(), note.id));
    }
  });

  test('a run stopped between two parts leaves the page unread, and the '
      'next run reads it again and stores the rest', () async {
    const length = 800000;
    final folder = await a().db.folderDao.createFolder(name: 'Years');
    final notes = [
      for (var i = 0; i < 3; i++)
        await writeNote(
          a(),
          folderId: folder.id,
          title: 'Year $i',
          body: bodyOf(i, length),
        ),
    ];
    await a().syncFiringSpacing();
    // An unbind halts the run at its next part, as a stop does at its next
    // page; the rebind starts the pull over.
    b().hooks.onAfterPage = (table, rows) async {
      if (table != 'notes' || rows.isEmpty) return;
      b().hooks.onAfterPage = null;
      await b().binding.unbind();
    };

    final cut = await b().sync();

    expect(cut.skipped, SyncRunSkip.unbound);
    expect(notesParts(b()), [2]);
    expect(
      await b().db.syncDao.getValue(SyncDao.keyPullCursor('notes')),
      isNull,
    );

    await pair.bind(b());
    final report = await b().sync();

    expect(report.failure, isNull);
    for (final note in notes) {
      expect(await bodyOn(b(), note.id), await bodyOn(a(), note.id));
    }
  });

  /// The results each `afterPage` of `notes` on [device] carried for [id].
  List<MergeResult> resultsOf(SyncDevice device, String id) => [
    for (final (table, rows) in device.hooks.pages)
      if (table == 'notes')
        for (final row in rows)
          if (row.rowKey == id) row.result,
  ];

  test('a body the preparation skipped that a later part\'s merge needs after '
      'all, its chunk replaced by a save before that part, fails the part '
      'instead of parking the note, and the next run keeps the save', () async {
    const length = 1100000;
    expect(length, lessThanOrEqualTo(SyncEngine.pullBodyBudget));
    expect(2 * length, greaterThan(SyncEngine.pullBodyBudget));
    final folder = await a().db.folderDao.createFolder(name: 'Logs');
    final target = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Log',
      body: 'base',
    );
    await a().sync();
    await b().sync();
    final years = [
      for (var i = 0; i < 2; i++)
        await writeNote(
          a(),
          folderId: folder.id,
          title: 'Year $i',
          body: bodyOf(i, length),
        ),
    ];
    await a().syncFiringSpacing();
    // The target again after them, at the stamp B holds: its preparation
    // reads no body, and it lands in the second part, with the second year.
    pair.gateway.plant(
      pair.space,
      pair.gateway.rowsOf(pair.space, 'notes')[target.id]!,
    );
    final cursor = await b().db.syncDao.getValue(
      SyncDao.keyPullCursor('notes'),
    );
    b().hooks.clear();
    var notesHooks = 0;
    b().hooks.onBeforePage = (table) async {
      if (table == 'notes' && ++notesHooks == 2) {
        await editNote(b(), target.id, 'typed on B');
      }
    };

    final failed = await b().sync();

    expect(notesHooks, 2);
    expect(failed.failure, isNotNull);
    expect(failed.parked, 0, reason: 'a replaced chunk is no missing text');
    expect(notesParts(b()), [1], reason: 'the first part stays committed');
    expect(await bodyOn(b(), years[0].id), await bodyOn(a(), years[0].id));
    expect(
      await b().db.syncDao.getValue(SyncDao.keyPullCursor('notes')),
      cursor,
    );

    b().hooks.onBeforePage = null;
    b().hooks.clear();
    final again = await b().sync();

    expect(again.failure, isNull);
    expect(again.parked, 0);
    expect(resultsOf(b(), target.id), [MergeResult.keptLocal]);
    expect(resultsOf(b(), years[0].id), [MergeResult.unchanged]);
    expect(b().hooks.conflicts, isEmpty);
    expect(await bodyOn(b(), target.id), 'typed on B');
    for (final note in years) {
      expect(await bodyOn(b(), note.id), await bodyOn(a(), note.id));
    }
  });

  test('a page cut after its first part is read again by the next run: the '
      'stored rows merge unchanged, each legacy-shape note is re-queued once, '
      'no copy is filed, and the cursor ends past the page', () async {
    const length = 1100000;
    final folder = await a().db.folderDao.createFolder(name: 'Logs');
    final legacy = [
      for (var i = 0; i < 2; i++)
        await writeNote(a(), folderId: folder.id, title: 'Log $i', body: '$i'),
    ];
    await a().sync();
    await b().sync();
    final years = [
      for (var i = 0; i < 2; i++)
        await writeNote(
          a(),
          folderId: folder.id,
          title: 'Year $i',
          body: bodyOf(i, length),
        ),
    ];
    await a().syncFiringSpacing();
    // Both logs as the build before the chunked wire left them, at the
    // stamps B holds — whole bodies — and the years after them, so the logs
    // merge in the first part. Planted after A's run, whose own pull would
    // re-queue the logs and push their manifests over the legacy shape.
    for (final note in legacy) {
      final manifest = pair.gateway.rowsOf(pair.space, 'notes')[note.id]!;
      pair.gateway.plant(
        pair.space,
        SyncEnvelope(
          table: manifest.table,
          rowKey: manifest.rowKey,
          hlc: manifest.hlc,
          deviceId: manifest.deviceId,
          version: manifest.version,
          op: manifest.op,
          ownerId: manifest.ownerId,
          data: {...manifest.data!}
            ..remove(NotesBinding.chunksKey)
            ..remove(NotesBinding.bodyHashKey)
            ..[JsonKeys.content] = await bodyOn(a(), note.id),
        ),
      );
    }
    for (final note in years) {
      pair.gateway.plant(
        pair.space,
        pair.gateway.rowsOf(pair.space, 'notes')[note.id]!,
      );
    }
    final cursor = await b().db.syncDao.getValue(
      SyncDao.keyPullCursor('notes'),
    );
    Future<List<(String, bool)>> queued() async => [
      for (final entry in await b().db.syncOutboxDao.pendingForTable('notes'))
        (entry.rowKey, entry.republish),
    ];
    final requeued = {for (final note in legacy) (note.id, true)};
    b().hooks.clear();
    // Signed out once the first part committed: the next part halts.
    b().hooks.onAfterPage = (table, rows) async {
      if (table == 'notes') b().user = null;
    };

    final cut = await b().sync();

    expect(cut.skipped, SyncRunSkip.signedOut);
    expect(notesParts(b()), [3], reason: 'the two logs and the first year');
    expect(
      await b().db.syncDao.getValue(SyncDao.keyPullCursor('notes')),
      cursor,
    );
    expect((await queued()).toSet(), requeued);

    b().user = const AppUser(uid: syncUid);
    List<(String, bool)>? afterPull;
    b().hooks.onAfterPage = (table, rows) async {
      if (table == 'notes') afterPull = await queued();
    };
    b().hooks.clear();
    pair.gateway.pushes.clear();
    final again = await b().sync();

    expect(again.failure, isNull);
    // The first year is stored now and merges unchanged, so the page fits
    // one part.
    expect(notesParts(b()), [4]);
    for (final note in [...legacy, years[0]]) {
      expect(resultsOf(b(), note.id), [MergeResult.unchanged], reason: note.id);
    }
    expect(afterPull, hasLength(legacy.length), reason: 'one entry per note');
    expect(afterPull!.toSet(), requeued);
    final pushed = [
      for (final batch in pair.gateway.pushes)
        for (final envelope in batch)
          if (envelope.table == 'notes') envelope.rowKey,
    ];
    expect(pushed..sort(), [for (final note in legacy) note.id]..sort());
    expect(b().hooks.conflicts, isEmpty);
    expect(
      await b().db.syncDao.getValue(SyncDao.keyPullCursor('notes')),
      isNot(cursor),
    );
    b().hooks.onAfterPage = null;
    b().hooks.clear();
    // Past the page: the next run reads only the echoes of the manifests
    // this one pushed.
    await b().sync();
    for (final note in years) {
      expect(resultsOf(b(), note.id), isEmpty, reason: note.id);
    }
    for (final note in legacy) {
      expect(resultsOf(b(), note.id), [MergeResult.unchanged], reason: note.id);
    }
    for (final note in years) {
      expect(await bodyOn(b(), note.id), await bodyOn(a(), note.id));
    }
  });

  test('the run that cuts over says it is finishing the update, counting the '
      'notes it read again toward the live notes, and stops saying so with '
      'the run; a bind\'s first run never says it', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Logs');
    for (var i = 0; i < 3; i++) {
      await writeNote(
        a(),
        folderId: folder.id,
        title: 'Log $i',
        body: 'Set $i',
      );
    }
    await a().sync();
    await b().sync();
    expect(b().statuses.where((s) => s.updating), isEmpty);
    await b().db.syncDao.setValue(SyncDao.keyWireVersion, '${syncSchema - 1}');
    b().statuses.clear();

    final report = await b().sync();

    expect(report.failure, isNull);
    final updating = b().statuses.where((s) => s.updating).toList();
    expect(updating, isNotEmpty);
    expect(updating.map((s) => s.updatingTotal).toSet(), {3});
    expect(updating.map((s) => s.activity).toSet(), {SyncActivity.pulling});
    expect(updating.last.downloadedRows, 3);
    expect(b().statuses.last.updating, isFalse);
    expect(b().statuses.last.updatingTotal, isNull);
    expect(b().statuses.last.downloadedRows, 0);
    expect(
      await b().db.syncDao.getValue(SyncDao.keyWireVersion),
      '$syncSchema',
    );
  });

  test('the cutover\'s re-read counts only the live notes that merged, so '
      'tombstones on its pages never carry the count past the total', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Logs');
    for (var i = 0; i < 5; i++) {
      final note = await writeNote(
        a(),
        folderId: folder.id,
        title: 'Log $i',
        body: 'Set $i',
      );
      if (i.isOdd) await a().db.noteDao.softDeleteNote(note.id);
    }
    await a().sync();
    await b().sync();
    await b().db.syncDao.setValue(SyncDao.keyWireVersion, '${syncSchema - 1}');
    b().statuses.clear();

    final report = await b().sync();

    expect(report.failure, isNull);
    final pulling = [
      for (final status in b().statuses)
        if (status.updating && status.activity == SyncActivity.pulling) status,
    ];
    expect(pulling.map((s) => s.updatingTotal).toSet(), {3});
    expect(
      pulling.map((s) => s.downloadedRows),
      everyElement(lessThanOrEqualTo(3)),
      reason: 'two of the five notes on the page are tombstones',
    );
    expect(pulling.last.downloadedRows, 3);
  });

  /// B as the phone that installed the chunked wire first left it: [ids]
  /// synced before and still held as slices no hash names, as every row
  /// written before v46 is; the space holding them as the whole-body
  /// documents the older build pushed; B's wire one below the schema. Its
  /// next run cuts over, re-queues each note at the equal stamp, and re-cuts
  /// each on its way out ([ContentChunkDao.hashLegacy]).
  Future<void> legacyPhone(List<String> ids) async {
    for (final id in ids) {
      final manifest = pair.gateway.rowsOf(pair.space, 'notes')[id]!;
      pair.gateway.plant(
        pair.space,
        SyncEnvelope(
          table: manifest.table,
          rowKey: manifest.rowKey,
          hlc: manifest.hlc,
          deviceId: manifest.deviceId,
          version: manifest.version,
          op: manifest.op,
          ownerId: manifest.ownerId,
          data: {...manifest.data!}
            ..remove(NotesBinding.chunksKey)
            ..remove(NotesBinding.bodyHashKey)
            ..[JsonKeys.content] = await bodyOn(a(), id),
        ),
      );
    }
    await b().db.customStatement(
      'UPDATE content_chunks SET content_hash = NULL',
    );
    await b().db.syncDao.setValue(SyncDao.keyWireVersion, '${syncSchema - 1}');
  }

  test('re-cutting a legacy note for its first push encodes no chunk inside '
      'a transaction', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Logs');
    final notes = [
      for (final (i, length) in [300000, 70000, 900].indexed)
        await writeNote(
          a(),
          folderId: folder.id,
          title: 'Log $i',
          body: bodyOf(i, length),
        ),
    ];
    await a().sync();
    await b().sync();
    await legacyPhone([for (final note in notes) note.id]);
    final inside = <int>[];
    var encodes = 0;
    b().statements.onTransaction = (begins) {
      if (begins) {
        encodes = ContentChunkDao.encodeCount;
      } else if (ContentChunkDao.encodeCount != encodes) {
        inside.add(ContentChunkDao.encodeCount - encodes);
      }
    };
    final encodesBefore = ContentChunkDao.encodeCount;

    final report = await b().sync();

    expect(report.failure, isNull);
    expect(inside, isEmpty, reason: 'chunks encoded inside a transaction');
    expect(
      ContentChunkDao.encodeCount,
      greaterThan(encodesBefore),
      reason: 'the re-cut encoded every chunk, ahead of its transaction',
    );
    for (final note in notes) {
      expect(
        await b().db.contentChunkDao.hashesOf(note.id),
        everyElement(isNotNull),
        reason: note.id,
      );
      expect(await bodyOn(b(), note.id), await bodyOn(a(), note.id));
      expect(
        pair.gateway.rowsOf(pair.space, 'notes')[note.id]!.data,
        contains(NotesBinding.chunksKey),
        reason: 'the manifest replaced the legacy document',
      );
    }
  });

  test('the run that cuts over goes on saying it is finishing the update '
      'while it sends the notes the re-read left queued, counting them '
      'toward the notes queued as the drain began', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Logs');
    final notes = [
      for (var i = 0; i < 3; i++)
        await writeNote(
          a(),
          folderId: folder.id,
          title: 'Log $i',
          body: 'Set $i',
        ),
    ];
    await a().sync();
    await b().sync();
    await legacyPhone([for (final note in notes) note.id]);
    b().statuses.clear();

    final report = await b().sync();

    expect(report.failure, isNull);
    final sending = [
      for (final status in b().statuses)
        if (status.updating && status.activity == SyncActivity.pushing) status,
    ];
    expect(sending, isNotEmpty);
    expect(sending.map((s) => s.updatingTotal).toSet(), {notes.length});
    expect(sending.first.updatingSent, 0);
    expect(sending.last.updatingSent, notes.length);
    final last = b().statuses.last;
    expect(last.updating, isFalse);
    expect(last.updatingTotal, isNull);
    expect(last.updatingSent, 0);
    expect(last.activity, SyncActivity.idle);
  });

  test('a status emitted after the cutover\'s re-read ends and before its '
      'drain begins still words the re-read, counted against the live '
      'notes rather than the notes queued for the drain', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Logs');
    final notes = [
      for (var i = 0; i < 3; i++)
        await writeNote(
          a(),
          folderId: folder.id,
          title: 'Log $i',
          body: 'Set $i',
        ),
    ];
    await a().sync();
    await b().sync();
    // Newer in the space: the re-read retires its re-queued entry, so the
    // drain's total falls short of the live notes.
    await editNote(a(), notes[0].id, 'Set 0, again');
    await a().sync();
    await legacyPhone([for (final note in notes) note.id]);
    final live = await b().db.noteDao.getNoteCount(null);
    // A signal failure is emitted whatever the run is doing: forced while
    // the run reads the wire version back after storing it — the re-read
    // over, the drain's queue counted, the drain not begun — and the run
    // held there until the emit has gone out.
    var stored = false;
    b().statements.onStatement = (statement, args) {
      if (!args.contains(SyncDao.keyWireVersion)) return null;
      if (statement.startsWith('INSERT')) {
        stored = true;
        return null;
      }
      if (!stored) return null;
      stored = false;
      pair.gateway.failWatches(pair.space, SyncGatewayFailure.offline);
      return pumpEventQueue();
    };
    await b().engine.start();
    await b().settle();
    await pumpEventQueue();
    await b().settle();

    final forced = b().statuses.firstWhere(
      (status) => status.lastFailure?.failure == SyncGatewayFailure.offline,
    );
    expect(forced.updating, isTrue);
    expect(forced.updatingSending, isFalse);
    expect(forced.activity, SyncActivity.pulling);
    expect(forced.updatingTotal, live);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
      syncUpdatingText(l10n, forced),
      l10n.syncUpdatingNotes(math.min(forced.downloadedRows, live), live),
    );
    final sending = [
      for (final status in b().statuses)
        if (status.updatingSending) status,
    ];
    expect(sending, isNotEmpty);
    expect(
      sending.map((s) => s.updatingTotal).toSet(),
      {live - 1},
      reason: 'the drain counts toward the notes it found queued',
    );
  });

  test('"Stop syncing" while a cutover page applies settles within the '
      'engine stop limit with no error escaping, unbinds, and a later bind '
      'cuts over again cleanly', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Logs');
    await a().sync();
    await b().sync();
    // Bigger than one part, so the stop lands in a page still applying.
    final notes = [
      for (var i = 0; i < 3; i++)
        await writeNote(
          a(),
          folderId: folder.id,
          title: 'Log $i',
          body: bodyOf(i, 800000),
        ),
    ];
    await a().syncFiringSpacing();
    await b().db.syncDao.setValue(SyncDao.keyWireVersion, '${syncSchema - 1}');

    final errors = <Object>[];
    final flutterOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception);
    addTearDown(() => FlutterError.onError = flutterOnError);
    Duration? stopTook;
    Future<void>? stopping;
    var notesPage = false;
    await runZonedGuarded(() async {
      // The bloc's step: the engine stopped under its limit, the binding
      // dropped, the engine started again — begun as the first transaction
      // of the cutover's notes page opens.
      b().hooks.onBeforePage = (table) async => notesPage = table == 'notes';
      b().statements.onTransaction = (begins) {
        if (!begins || !notesPage || stopping != null) return;
        stopping = () async {
          final watch = Stopwatch()..start();
          await b().engine.stop().timeout(SyncLimits.engineStop);
          stopTook = watch.elapsed;
          await b().binding.unbind();
          await b().engine.start();
        }();
      };
      await b().engine.start();
      await b().settle();
      while (stopping == null) {
        await Future<void>.delayed(Duration.zero);
      }
      await stopping;
      await b().settle();
    }, (error, stack) => errors.add(error));

    expect(errors, isEmpty);
    expect(stopTook, isNotNull);
    expect(stopTook!, lessThan(SyncLimits.engineStop));
    expect(b().statuses.where((s) => s.updating), isNotEmpty);
    expect(b().engine.current.updating, isFalse);
    expect(notesParts(b()), [2], reason: 'halted after the part in flight');
    expect(await b().binding.read(), isNull);
    expect(
      await b().db.syncDao.getValue(SyncDao.keyWireVersion),
      '${syncSchema - 1}',
      reason: 'the cutover did not complete',
    );

    b().hooks.onBeforePage = null;
    b().statements.onTransaction = null;
    await pair.bind(b());
    final report = await b().sync();

    expect(report.failure, isNull);
    expect(
      await b().db.syncDao.getValue(SyncDao.keyWireVersion),
      '$syncSchema',
    );
    for (final note in notes) {
      expect(await bodyOn(b(), note.id), await bodyOn(a(), note.id));
    }
    await b().engine.stop();
  });

  test('no transaction holds the database of the pushing device while a body '
      'is hashed for its manifest', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Logs');
    final notes = [
      for (final (i, length) in [300000, 70000, 900].indexed)
        await writeNote(
          a(),
          folderId: folder.id,
          title: 'Log $i',
          body: bodyOf(i, length),
        ),
    ];
    final inside = <int>[];
    var hashes = 0;
    a().statements.onTransaction = (begins) {
      if (begins) {
        hashes = ContentChunkDao.bodyHashCount;
      } else if (ContentChunkDao.bodyHashCount != hashes) {
        inside.add(ContentChunkDao.bodyHashCount - hashes);
      }
    };
    final hashesBefore = ContentChunkDao.bodyHashCount;

    final pushed = await a().sync();

    expect(pushed.failure, isNull);
    expect(inside, isEmpty, reason: 'bodies hashed inside a transaction');
    expect(
      ContentChunkDao.bodyHashCount - hashesBefore,
      notes.length,
      reason: 'one manifest each',
    );
    final pulled = await b().sync();
    expect(pulled.failure, isNull);
    expect(pulled.parked, 0, reason: 'every bodyHash matches its chunks');
    for (final note in notes) {
      expect(await bodyOn(b(), note.id), await bodyOn(a(), note.id));
    }
  });

  group('the conflict check of a cutover page', () {
    /// The statements reading a note's whole body ([loadContent]) that ran
    /// while a transaction was open on [device], by note id.
    List<String> bodyReadsInside(SyncDevice device, Set<String> ids) {
      final reads = <String>[];
      var from = 0;
      device.statements.onTransaction = (begins) {
        final captured = device.statements.captured;
        if (begins) {
          from = captured.length;
          return;
        }
        for (final statement in captured.skip(from)) {
          if (statement.sql.startsWith('SELECT * FROM "content_chunks"') &&
              statement.args.any(ids.contains)) {
            reads.add(statement.args.whereType<String>().first);
          }
        }
      };
      return reads;
    }

    test(
      'reads no local body inside the page\'s transaction when the remote '
      'is newer than an edit not pushed yet, and still files the copy',
      () async {
        final folder = await a().db.folderDao.createFolder(name: 'Logs');
        final note = await writeNote(
          a(),
          folderId: folder.id,
          title: 'Log',
          body: bodyOf(0, 70000),
        );
        await a().sync();
        await b().sync();
        await editNote(b(), note.id, 'typed on B');
        await editNote(a(), note.id, 'typed on A');
        await a().sync();
        await b().db.syncDao.setValue(
          SyncDao.keyWireVersion,
          '${syncSchema - 1}',
        );
        b().hooks.clear();
        final reads = bodyReadsInside(b(), {note.id});

        final report = await b().sync();

        expect(report.failure, isNull);
        expect(reads, isEmpty);
        final conflict = b().hooks.conflicts.single;
        expect(conflict.loser.id, note.id);
        expect(conflict.loserContent, 'typed on B');
        expect(await bodyOn(b(), note.id), 'typed on A');
      },
    );

    test('a save landing between the page\'s preparation and its merge files '
        'the copy with the text it saved', () async {
      // A's clock ahead of B's, so B's save during the page — stamped just
      // past the first part B adopted — still sorts below A's later edit.
      await pair.close();
      pair = await SyncPair.open(wallAhead: {'A': const Duration(minutes: 10)});
      const length = 800000;
      final folder = await a().db.folderDao.createFolder(name: 'Years');
      final notes = [
        for (var i = 0; i < 3; i++)
          await writeNote(
            a(),
            folderId: folder.id,
            title: 'Year $i',
            body: bodyOf(i, length),
          ),
      ];
      final target = notes.last;
      await a().syncFiringSpacing();
      await b().syncFiringSpacing();
      await editNote(b(), target.id, 'typed on B');
      for (final (i, note) in notes.indexed) {
        await editNote(a(), note.id, bodyOf(i + 10, length));
      }
      await a().syncFiringSpacing();
      b().hooks.clear();
      // `beforePage` runs ahead of the page's preparation and again ahead of
      // each later part, so the second is the save between the two.
      var notesHooks = 0;
      b().hooks.onBeforePage = (table) async {
        if (table == 'notes' && ++notesHooks == 2) {
          await editNote(b(), target.id, 'typed on B again');
        }
      };
      final reads = bodyReadsInside(b(), {target.id});

      final report = await b().sync();

      expect(report.failure, isNull);
      expect(notesHooks, 2);
      final parts = [
        for (final (table, rows) in b().hooks.pages)
          if (table == 'notes') [for (final row in rows) row.rowKey],
      ];
      expect(parts.last, [target.id], reason: 'the target merged after it');
      expect(b().hooks.conflicts.single.loserContent, 'typed on B again');
      expect(reads, [target.id], reason: 'its stamp moved: read again');
      expect(await bodyOn(b(), target.id), await bodyOn(a(), target.id));
    });
  });
}
