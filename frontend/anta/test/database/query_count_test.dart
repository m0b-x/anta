import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/daos/note_dao.dart';
import 'package:anta/database/daos/content_chunk_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/repositories/note_repository.dart';

import 'support/db_test_support.dart';

/// Guards that operations stay **O(1) in statements**, not O(rows).
///
/// A query in a loop is what actually makes a local-SQLite app feel slow —
/// each individual statement looks fine in a profile and in a query plan, and
/// only the count gives it away. These assertions are hardware-independent for
/// the same reason the query-plan ones are: they count work, not time.
void main() {
  late StatementCounter counter;
  late AppDatabase db;

  setUp(() async {
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
    await _seedNotes(db, 60);
  });
  tearDown(() async => db.close());

  test('resolving many notes by id is a single IN query', () async {
    final ids = [for (var i = 0; i < 50; i++) 'n$i'];
    counter.reset();
    final notes = await db.noteDao.getNotesByIds(ids);

    expect(notes, hasLength(50));
    expect(
      counter.count,
      1,
      reason:
          'getNotesByIds must stay one `WHERE id IN (…)` query. The calendar '
          'resolves linked notes through it, and rewriting it as a loop would '
          'be invisible in a query plan: 50 fast statements still beat one. '
          'Issued:\n${counter.statements.join('\n')}',
    );
  });

  test('an empty id list touches the database not at all', () async {
    counter.reset();
    await db.noteDao.getNotesByIds(const []);
    expect(counter.count, 0);
  });

  test('resolving a wiki link title is one statement', () async {
    counter.reset();
    final found = await db.noteDao.getNotesByTitle('Note 7');

    expect(found, hasLength(1));
    expect(
      counter.count,
      1,
      reason:
          'getNotesByTitle must stay one indexed SELECT. A tapped [[link]] '
          'runs it on the interaction path, so a second statement is a second '
          'round trip before the editor opens. Issued:\n'
          '${counter.statements.join('\n')}',
    );
  });

  test('a wiki link that matches nothing still costs one statement', () async {
    counter.reset();
    expect(await db.noteDao.getNotesByTitle('Nothing here'), isEmpty);
    // A miss is the common case while a link is being typed; it must not
    // widen into a fallback query.
    expect(counter.count, 1);
  });

  test('a blank wiki link title touches the database not at all', () async {
    counter.reset();
    expect(await db.noteDao.getNotesByTitle('   '), isEmpty);
    expect(await db.noteDao.getNotesByTitle(''), isEmpty);
    expect(counter.count, 0);
  });

  test(
    'an over-long wiki link title touches the database not at all',
    () async {
      counter.reset();
      // `notes.title` is capped at 500, so nothing longer can be stored and
      // nothing longer can match. A `[[…]]` can hold a whole pasted paragraph,
      // which is how a title this long reaches the DAO at all.
      expect(await db.noteDao.getNotesByTitle('x' * 501), isEmpty);
      expect(counter.count, 0);
    },
  );

  test('a title exactly at the column cap is still looked up', () async {
    counter.reset();
    // The boundary, counted in the UTF-16 code units Drift enforces the cap
    // in: 500 is storable, so refusing it would make real notes unreachable.
    expect(await db.noteDao.getNotesByTitle('x' * 500), isEmpty);
    expect(counter.count, 1);
  });

  test('listing a folder page is a constant number of statements', () async {
    counter.reset();
    await db.noteDao.getNotesPaginated(
      folderId: _folderId,
      limit: 50,
      offset: 0,
      sortField: NoteSortField.position,
      ascending: true,
    );
    // One SELECT for the page. Anything more means per-row work crept in.
    expect(
      counter.count,
      1,
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
  });

  test('note count does not read the rows it counts', () async {
    counter.reset();
    final total = await db.noteDao.getNoteCount(_folderId);
    expect(total, 60);
    expect(counter.count, 1);
    expect(
      counter.statements.single.toUpperCase(),
      contains('COUNT('),
      reason: 'counting must stay a COUNT(*), never a fetch-and-length',
    );
  });

  group('a page of folder rows and their counts', () {
    // Every folder row in the browser shows how many notes live under it,
    // descendants included. That used to be two statements per row, so a
    // 40-folder page cost 80 round trips before it could finish painting.
    test('one statement answers a whole page, however many rows', () async {
      await _seedTree(db, roots: 30, depth: 3, notesPerFolder: 2);
      final ids = [for (var i = 0; i < 30; i++) 'root$i'];

      counter.reset();
      final counts = await db.folderDao.noteCountsWithDescendants(ids);

      expect(counts, hasLength(30));
      expect(
        counter.count,
        1,
        reason:
            'the batched count must stay one WITH RECURSIVE statement. Per-row '
            'counting is invisible in a query plan — 60 indexed statements '
            'still lose to one. Issued:\n${counter.statements.join('\n')}',
      );
    });

    test(
      'the statement count does not move with the number of folders',
      () async {
        await _seedTree(db, roots: 30, depth: 3, notesPerFolder: 2);

        counter.reset();
        await db.folderDao.noteCountsWithDescendants(const ['root0']);
        final forOne = counter.count;

        counter.reset();
        await db.folderDao.noteCountsWithDescendants([
          for (var i = 0; i < 30; i++) 'root$i',
        ]);
        final forThirty = counter.count;

        expect(forOne, forThirty);
      },
    );

    test('an empty folder list touches the database not at all', () async {
      counter.reset();
      expect(await db.folderDao.noteCountsWithDescendants(const []), isEmpty);
      expect(counter.count, 0);
    });

    test(
      'the count reaches every descendant, and stops at deleted ones',
      () async {
        await _seedTree(db, roots: 2, depth: 3, notesPerFolder: 2);
        // 2 notes in the root, 2 in its child, 2 in its grandchild.
        expect(await db.folderDao.noteCountsWithDescendants(const ['root0']), {
          'root0': 6,
        });

        // Tombstoned directly rather than through
        // `softDeleteFolderWithDescendants`: that path also rewrites `notes_fts`,
        // which these batch-inserted rows were never added to.
        await db.customStatement(
          "UPDATE folders SET is_deleted = 1 WHERE id = 'root0_1'",
        );
        expect(
          await db.folderDao.noteCountsWithDescendants(const ['root0']),
          {'root0': 2},
          reason:
              'a tombstoned subtree must leave the traversal, notes and all — '
              'the same rule getAllDescendantIds follows',
        );
      },
    );

    test('a folder with nothing under it still answers, with zero', () async {
      await _seedTree(db, roots: 1, depth: 1, notesPerFolder: 0);
      expect(
        await db.folderDao.noteCountsWithDescendants(const ['root0']),
        {'root0': 0},
        reason:
            'the row draws its count before it can be told there is none; a '
            'missing key and a zero must not look different to it',
      );
    });
  });

  group('a bulk delete', () {
    late List<String> ids;

    // Through the DAO rather than the file's batch seed: these rows have to
    // exist in `notes_fts` for a delete to be allowed to remove them.
    setUp(() async {
      ids = [];
      for (var i = 0; i < 40; i++) {
        final note = await db.noteDao.createNote(
          folderId: _folderId,
          title: 'Selected $i',
          preview: 'squat',
        );
        ids.add(note.id);
      }
    });

    // Selecting forty rows and deleting them used to be forty independent
    // tombstone writes, each with its own transaction, its own FTS delete and
    // its own read of the row it was about to write.
    test('issues one statement per table, not one per item', () async {
      counter.reset();

      await db.noteDao.softDeleteNotesWithChunks(ids);

      expect(
        counter.matching('UPDATE notes'),
        hasLength(1),
        reason:
            'the tombstone write must stay one `WHERE id IN (…)` update; SQL '
            'can do the `version + 1` itself. Issued:\n'
            '${counter.statements.join('\n')}',
      );
      expect(counter.matching('content_chunks'), hasLength(1));
      expect(
        counter.selects,
        isEmpty,
        reason: 'no row is read on the way to writing it',
      );
      // Two, and only two: the notes update and the chunks update. The FTS
      // delete rides on `customStatement`, which this interceptor does not
      // see — the count below is therefore about the two tables it can.
      expect(
        counter.count,
        2,
        reason: 'issued:\n${counter.statements.join('\n')}',
      );
    });

    test(
      'the statement count does not move with the size of the selection',
      () async {
        counter.reset();
        await db.noteDao.softDeleteNotesWithChunks([ids.first]);
        final forOne = counter.count;

        counter.reset();
        await db.noteDao.softDeleteNotesWithChunks(ids.skip(1).toList());

        expect(counter.count, forOne);
      },
    );

    test('every deleted row is a proper tombstone', () async {
      final before = await db.noteDao.getNoteById(ids[3]);
      await db.noteDao.softDeleteNotesWithChunks([ids[3], ids[4]]);

      final after = await (db.select(
        db.notes,
      )..where((n) => n.id.equals(ids[3]))).getSingle();
      expect(after.isDeleted, isTrue);
      expect(after.deletedAt, isA<DateTime>());
      expect(
        after.version,
        before!.version + 1,
        reason: 'a merge orders by version; a bulk delete is not exempt',
      );
      expect(after.deviceId, db.deviceId);
      expect(after.hlcTimestamp, isNot(before.hlcTimestamp));
      expect(await db.noteDao.getNotesByIds([ids[3], ids[4]]), isEmpty);
    });

    test('an already tombstoned row is not rewritten', () async {
      await db.noteDao.softDeleteNotesWithChunks([ids[5]]);
      final first = await (db.select(
        db.notes,
      )..where((n) => n.id.equals(ids[5]))).getSingle();

      await db.noteDao.softDeleteNotesWithChunks([ids[5]]);
      final second = await (db.select(
        db.notes,
      )..where((n) => n.id.equals(ids[5]))).getSingle();

      expect(
        second.version,
        first.version,
        reason:
            'a repeated delete must not churn versions the merge reads as '
            'ordering events',
      );
    });

    test('an empty selection touches the database not at all', () async {
      counter.reset();
      await db.noteDao.softDeleteNotesWithChunks(const []);
      expect(counter.count, 0);
    });
  });

  test('reordering never reads a row to write it', () async {
    final positions = {for (var i = 0; i < 50; i++) 'n$i': 50 - i};
    counter.reset();
    await db.noteDao.setNotePositions(positions);

    // One UPDATE per note is inherent — each row gets a different position.
    // What is *not* inherent is a SELECT per note, which is what this had:
    // 100 statements for 50 rows, purely to read `version` so it could write
    // `version + 1`. SQL can do that arithmetic itself.
    expect(
      counter.matching('SELECT'),
      isEmpty,
      reason:
          'reorder must not read each row before writing it. Issued:\n'
          '${counter.statements.take(6).join('\n')}',
    );
    expect(counter.count, lessThanOrEqualTo(positions.length));
  });

  test('reordering still bumps the CRDT version of each moved row', () async {
    final before = await db.noteDao.getNoteById('n0');
    await db.noteDao.setNotePositions({'n0': 99});
    final after = await db.noteDao.getNoteById('n0');

    expect(after!.position, 99);
    // The whole reason the old code read the row first. Doing it in SQL must
    // not quietly drop the increment.
    expect(after.version, before!.version + 1);
    expect(after.deviceId, db.deviceId);
  });

  test('reordering an unknown id is a no-op, not an insert', () async {
    final countBefore = await db.noteDao.getNoteCount(_folderId);
    await db.noteDao.setNotePositions({'does-not-exist': 1});
    expect(await db.noteDao.getNoteCount(_folderId), countBefore);
  });

  test('deleting an event cascades in one statement per table', () async {
    await db.calendarEventDao.upsert(_event('e1'));
    for (var i = 0; i < 20; i++) {
      await db.eventOccurrenceDao.upsert(
        EventOccurrenceDescriptionsCompanion.insert(
          eventId: 'e1',
          day: DateTime.utc(2026, 1, i + 1),
          description: 'day $i',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }

    for (var i = 0; i < 20; i++) {
      await db.eventAbsenceDao.setStatus(
        'e1',
        DateTime.utc(2026, 1, i + 1),
        PresenceStatus.missed,
      );
    }
    // An already-tombstoned child must not be rewritten by the cascade, or a
    // repeated delete churns versions the merge reads as ordering events.
    await db.eventAbsenceDao.clearMark('e1', DateTime.utc(2026, 1, 1));
    await db.eventOccurrenceDao.tombstone('e1', DateTime.utc(2026, 1, 1));

    counter.reset();
    await db.calendarEventDao.softDeleteById('e1');
    await db.eventAbsenceDao.tombstoneForEvent('e1');
    await db.eventOccurrenceDao.tombstoneForEvent('e1');

    // The parent is read-then-write (it needs `version + 1` for exactly one
    // row); everything below it is a single set-based statement covering every
    // row, not one per materialized day. Since v28 both children tombstone,
    // so "one statement per table" is now an UPDATE on each.
    expect(
      counter.matching('calendar_events'),
      hasLength(2),
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
    expect(
      [
        for (final s in counter.selects)
          if (s.sql.contains('calendar_events')) s,
      ],
      hasLength(1),
      reason:
          'the single SELECT is the intended read; a second one means the '
          'cascade started reading rows it could have updated in SQL. '
          'Issued:\n${counter.statements.join('\n')}',
    );
    expect(
      counter.matching('calendar_event_occurrences'),
      hasLength(1),
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
    expect(
      counter.matching('calendar_event_absences'),
      hasLength(1),
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
  });

  test('reassigning a category is one statement whatever the row count', () async {
    for (var i = 0; i < 20; i++) {
      await db.calendarEventDao.upsert(_event('e$i'));
    }

    counter.reset();
    final moved = await db.calendarEventDao.reassignCategory('gym', 'other');

    expect(moved, 20);
    // Deleting a category can touch an unbounded number of events, so this one
    // cannot read-then-write: the version bump has to happen in SQL. Forgetting
    // the stamping entirely would break nothing visible today and corrupt merge
    // ordering the moment transport exists — that is what this pins.
    expect(
      counter.count,
      1,
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
  });

  test('an upsert reads the row it overwrites exactly once', () async {
    counter.reset();
    await db.calendarEventDao.upsert(_event('e1'));
    // SELECT (miss) + INSERT. The extra read is the price of `version 1` vs
    // `version + 1`, paid on a table that writes at human speed.
    expect(
      counter.count,
      2,
      reason: 'issued:\n${counter.statements.join('\n')}',
    );

    counter.reset();
    await db.calendarEventDao.upsert(_event('e1'));
    // SELECT (hit) + UPDATE — never a blind UPDATE-then-INSERT, which would be
    // two writes and could not compute the version bump.
    expect(
      counter.count,
      2,
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
    expect(counter.selects, hasLength(1));
  });

  test('a bulk event import reads nothing and scales in one batch', () async {
    const rows = 40;
    final entries = [for (var i = 0; i < rows; i++) _event('e$i')];

    counter.reset();
    await db.calendarEventDao.importAll(entries);

    // The whole point of 5.1: not one `SELECT` in the restore path. `upsert`
    // issued one per row, and every one was a guaranteed miss — `deleteAll`
    // is a documented hard wipe, so the table is empty when this runs.
    expect(
      counter.selects,
      isEmpty,
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
    // Statements must not scale at `upsert`'s 2-per-row. The batch collapses
    // the inserts; the bound is deliberately far below `rows * 2` rather than
    // an exact figure, so a drift version that batches differently does not
    // fail this for the wrong reason.
    expect(
      counter.count,
      lessThan(rows),
      reason: 'issued:\n${counter.statements.join('\n')}',
    );

    final stored = await db.calendarEventDao.getAll();
    expect(stored, hasLength(rows));
  });

  test('a bulk import of nothing touches the database not at all', () async {
    counter.reset();
    await db.calendarEventDao.importAll(const []);
    expect(counter.count, 0);
  });

  test('a bulk import stamps every row as a live version-1 original', () async {
    // A restore is this device's own authorship, never a replayed merge — the
    // same contract the single-row import methods carried before 5.1 widened
    // them to lists.
    await db.calendarEventDao.importAll([_event('e1'), _event('e2')]);

    final rows = await db.calendarEventDao.getAll();
    expect(rows, hasLength(2));
    for (final row in rows) {
      expect(row.version, 1);
      expect(row.isDeleted, isFalse);
      expect(row.deletedAt, null);
      expect(row.deviceId, db.deviceId);
      expect(row.hlcTimestamp, isNotEmpty);
    }
  });

  test('a duplicate id inside one archive keeps the last row', () async {
    // `upsert` was last-one-wins by construction; `insertOrReplace` preserves
    // that for a malformed archive instead of failing the whole batch.
    await db.calendarEventDao.importAll([
      _event('dup'),
      _event('dup').copyWith(title: const Value('Overwritten')),
    ]);

    final rows = await db.calendarEventDao.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.title, 'Overwritten');
  });

  test('an occurrence upsert reads the row it overwrites exactly once', () async {
    counter.reset();
    await db.eventOccurrenceDao.upsert(_occurrence(1));
    // SELECT (miss) + INSERT. The extra read is the price of `version 1` vs
    // `version + 1` and of keeping `created_at` when a reset day is
    // re-described, paid on a table that writes at human speed.
    expect(
      counter.count,
      2,
      reason: 'issued:\n${counter.statements.join('\n')}',
    );

    counter.reset();
    await db.eventOccurrenceDao.upsert(_occurrence(1));
    // SELECT (hit) + UPDATE — never a blind UPDATE-then-INSERT, which could not
    // compute the version bump.
    expect(
      counter.count,
      2,
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
    expect(counter.selects, hasLength(1));
  });

  group('note content batching', () {
    test('loading content for many notes is a single query', () async {
      await _seedChunks(db, {
        for (var i = 0; i < 50; i++) 'n$i': ['body $i'],
      });
      final ids = [for (var i = 0; i < 50; i++) 'n$i'];
      counter.reset();
      final contents = await db.contentChunkDao.loadContentForNotes(ids);

      expect(contents, hasLength(50));
      expect(contents['n7'], 'body 7');
      expect(
        counter.count,
        1,
        reason:
            'loadContentForNotes must stay one `WHERE note_id IN (…)` query. '
            'The money ledger refreshes on every event create and every event '
            'edit, and a per-note loop would be invisible in a query plan: 50 '
            'fast statements still beat one. '
            'Issued:\n${counter.statements.join('\n')}',
      );
    });

    test('an empty id list touches the database not at all', () async {
      counter.reset();
      final contents = await db.contentChunkDao.loadContentForNotes(const []);
      expect(contents, isEmpty);
      expect(counter.count, 0);
    });

    test('a note with no chunks still gets an empty entry', () async {
      await _seedChunks(db, {
        'n0': ['alpha'],
        'n2': ['gamma'],
      });

      final contents = await db.contentChunkDao.loadContentForNotes([
        'n0',
        'n1',
        'n2',
      ]);

      // The map is pre-seeded before the query for exactly this row: a
      // chunkless note returns nothing, but `loadContent` answers `''` for it
      // and the ledger writes an entry. Accumulating only over the returned
      // rows drops the note from the ledger, and its day bars and month-net
      // contribution vanish with no error anywhere.
      expect(contents.keys, hasLength(3));
      expect(contents['n1'], '');
      expect(contents['n1'], await db.contentChunkDao.loadContent('n1'));
    });

    test('a note mixing compressed and plain chunks round-trips', () async {
      // Chunk size (10000) and the compression threshold (5000) are
      // independent, so a note longer than one chunk ends with a compressed
      // head and — here — a short, plain tail. Branching on `isCompressed` per
      // *note* instead of per *row* corrupts one of the two.
      final content = 'x' * ContentChunkDao.defaultChunkSize + 'tail';
      await db.contentChunkDao.saveContent(noteId: 'n0', content: content);
      final chunks = await db.contentChunkDao.getChunksForNote('n0');
      expect(chunks.map((c) => c.isCompressed), [true, false]);

      final contents = await db.contentChunkDao.loadContentForNotes(['n0']);
      expect(contents['n0'], await db.contentChunkDao.loadContent('n0'));
      expect(contents['n0'], content);
    });

    test('chunks reassemble in index order, not id order', () async {
      // Chunk ids are `<noteId>_chunk_<i>`, so a string sort puts `_chunk_10`
      // between `_chunk_1` and `_chunk_2`. Anything that groups or orders by
      // id instead of (note_id, chunk_index) silently scrambles long notes.
      await _seedChunks(db, {
        'n0': [for (var i = 0; i < 12; i++) '<$i>'],
      });

      final contents = await db.contentChunkDao.loadContentForNotes(['n0']);
      expect(contents['n0'], await db.contentChunkDao.loadContent('n0'));
      expect(contents['n0'], '<0><1><2><3><4><5><6><7><8><9><10><11>');
    });

    test('soft-deleted chunks are excluded, exactly as loadContent', () async {
      await _seedChunks(db, {
        'n0': ['one', 'two', 'three'],
      });
      await (db.update(db.contentChunks)
            ..where((c) => c.id.equals('n0_chunk_1')))
          .write(const ContentChunksCompanion(isDeleted: Value(true)));

      final contents = await db.contentChunkDao.loadContentForNotes(['n0']);
      expect(contents['n0'], await db.contentChunkDao.loadContent('n0'));
      expect(contents['n0'], 'onethree');
    });

    test('the repository serves a second batch from its LRU', () async {
      await _seedChunks(db, {
        for (var i = 0; i < 40; i++) 'n$i': ['body $i'],
      });
      final repository = NoteRepository(database: db);
      final ids = [for (var i = 0; i < 40; i++) 'n$i'];

      counter.reset();
      final first = await repository.loadContentForNotes(ids);
      expect(first['n39'], 'body 39');
      expect(
        counter.count,
        1,
        reason: 'issued:\n${counter.statements.join('\n')}',
      );

      counter.reset();
      final second = await repository.loadContentForNotes(ids);
      // The batch populates the same content LRU the N sequential
      // `loadContent` calls it replaces did, so a repeated refresh over an
      // unchanged event set costs nothing.
      expect(second, first);
      expect(
        counter.count,
        0,
        reason: 'issued:\n${counter.statements.join('\n')}',
      );
    });
  });

  group('categories', () {
    test('counting events per category is a single GROUP BY', () async {
      for (var i = 0; i < 30; i++) {
        await db.calendarEventDao.upsert(
          _event('e$i', category: 'cat${i % 10}'),
        );
      }

      counter.reset();
      final counts = await db.calendarEventDao.countByCategory();

      expect(counts['cat0'], 3);
      expect(counts, hasLength(10));
      // The categories page renders this figure on every row. A count per row
      // is the exact shape this suite exists for: forty individually-fast
      // statements look fine in a query plan and only the count gives them
      // away.
      expect(
        counter.count,
        1,
        reason: 'issued:\n${counter.statements.join('\n')}',
      );
      expect(
        counter.statements.single.toUpperCase(),
        allOf(contains('COUNT('), contains('GROUP BY')),
        reason: 'counting must stay a GROUP BY, never a fetch-and-tally',
      );
    });

    test('a category with no live events is absent, not zero', () async {
      await db.calendarEventDao.upsert(_event('e1', category: 'gym'));
      await db.calendarEventDao.softDeleteById('e1');

      final counts = await db.calendarEventDao.countByCategory();
      expect(
        counts.containsKey('gym'),
        isFalse,
        reason:
            'tombstones must not be counted, and callers read the map with '
            '?? 0 — which is also what makes an unknown id free',
      );
    });

    test('reordering categories is one batch and reads nothing', () async {
      final now = DateTime.now();
      final ids = [for (var i = 0; i < 40; i++) 'c$i'];
      await db.batch((b) {
        for (final id in ids) {
          b.insert(
            db.calendarCategories,
            CalendarCategoriesCompanion.insert(
              id: id,
              name: id,
              colorValue: 1,
              iconKey: 'event',
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      });

      counter.reset();
      await db.calendarCategoryDao.reorder(ids.reversed.toList());

      // No CRDT columns on this table, so unlike the vocabulary reorder there
      // is no `version + 1` to read first — every statement must be a write.
      expect(
        counter.selects,
        isEmpty,
        reason:
            'reorder must not read a row to write it. Issued:\n'
            '${counter.statements.take(6).join('\n')}',
      );
      // One `batch` is one transaction and one commit; drift may collapse the
      // updates into fewer prepared statements than rows, never more.
      expect(
        counter.count,
        lessThanOrEqualTo(ids.length),
        reason: 'issued:\n${counter.statements.take(6).join('\n')}',
      );

      final rows = await db.calendarCategoryDao.getAll();
      expect(rows.map((r) => r.id), ids.reversed);
      expect(
        rows.map((r) => r.sortOrder),
        [for (var i = 0; i < ids.length; i++) i],
        reason:
            'dense 0..N-1: CalendarCategories._byOrder tie-breaks on id, so '
            'gaps or duplicates let rows shuffle on the next load',
      );
    });

    test('reordering nothing touches the database not at all', () async {
      counter.reset();
      await db.calendarCategoryDao.reorder(const []);
      expect(counter.count, 0);
    });
  });
}

Future<void> _seedChunks(
  AppDatabase db,
  Map<String, List<String>> contentsByNote,
) async {
  await db.batch((batch) {
    for (final entry in contentsByNote.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        batch.insert(
          db.contentChunks,
          ContentChunksCompanion.insert(
            id: '${entry.key}_chunk_$i',
            noteId: entry.key,
            chunkIndex: i,
            content: entry.value[i],
            hlcTimestamp: '0',
            deviceId: 'test',
          ),
        );
      }
    }
  });
}

EventOccurrenceDescriptionsCompanion _occurrence(int day) {
  return EventOccurrenceDescriptionsCompanion.insert(
    eventId: 'e1',
    day: DateTime.utc(2026, 1, day),
    description: 'day $day',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

CalendarEventsCompanion _event(String id, {String category = 'gym'}) {
  return CalendarEventsCompanion.insert(
    id: id,
    title: 'Leg day',
    category: category,
    startDate: DateTime.utc(2026, 1, 1),
    ruleKind: 'daily',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

/// [roots] chains of folders [depth] deep, each folder holding
/// [notesPerFolder] notes. Ids are `root<i>`, `root<i>_1`, `root<i>_2`, …, so
/// a test can name any level without looking one up.
Future<void> _seedTree(
  AppDatabase db, {
  required int roots,
  required int depth,
  required int notesPerFolder,
}) async {
  final now = DateTime.now();
  await db.batch((batch) {
    for (var r = 0; r < roots; r++) {
      String? parent;
      for (var d = 0; d < depth; d++) {
        final id = d == 0 ? 'root$r' : 'root${r}_$d';
        batch.insert(
          db.folders,
          FoldersCompanion.insert(
            id: id,
            name: id,
            parentId: Value(parent),
            hlcTimestamp: '0',
            deviceId: 'test',
            createdAt: now,
            updatedAt: now,
          ),
        );
        for (var n = 0; n < notesPerFolder; n++) {
          batch.insert(
            db.notes,
            NotesCompanion.insert(
              id: '${id}_n$n',
              folderId: id,
              title: '$id note $n',
              hlcTimestamp: '0',
              deviceId: 'test',
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
        parent = id;
      }
    }
  });
}

const _folderId = 'f1';

Future<void> _seedNotes(AppDatabase db, int count) async {
  final now = DateTime.now();
  await db.batch((batch) {
    batch.insert(
      db.folders,
      FoldersCompanion.insert(
        id: _folderId,
        name: 'Bench',
        hlcTimestamp: '0',
        deviceId: 'test',
        createdAt: now,
        updatedAt: now,
      ),
    );
    for (var i = 0; i < count; i++) {
      batch.insert(
        db.notes,
        NotesCompanion.insert(
          id: 'n$i',
          folderId: _folderId,
          title: 'Note $i',
          hlcTimestamp: '0',
          deviceId: 'test',
          createdAt: now,
          updatedAt: now,
          position: Value(i),
        ),
      );
    }
  });
}
