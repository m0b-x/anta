import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/daos/folder_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/item_label.dart';

import 'support/db_test_support.dart';

/// The folder twin of [note_pagination_test].
///
/// Subfolder paging has the same failure mode notes have — rows tied on the
/// sort key can come back in a different order for page 2 than they did for
/// page 1, so one folder is served twice and another on neither page — and the
/// colour-label sort (roadmap Slice B) is the first folder ordering whose ties
/// are wide by construction: a palette of seven puts every subfolder of one
/// colour into a single run. Every folder sort ends on `id`, as the note sorts
/// do, and these tests are what says so.
void main() {
  late AppDatabase db;
  late StatementCounter counter;

  setUp(() async {
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
  });
  tearDown(() async => db.close());

  const parentId = 'p1';
  final stamp = DateTime.utc(2026, 3, 1, 10, 30, 15);

  /// One subfolder per entry, each with the exact `(label, name)` pair the
  /// test needs. Insertion order is deliberately not sorted order.
  Future<void> seedLabelledFolders(
    Map<String, (ItemLabel, String)> children,
  ) async {
    await db.folderDao.insertFolder(
      FoldersCompanion.insert(
        id: parentId,
        name: 'Training',
        hlcTimestamp: '0',
        deviceId: 'test',
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
    await db.batch((batch) {
      for (final entry in children.entries) {
        final (label, name) = entry.value;
        batch.insert(
          db.folders,
          FoldersCompanion.insert(
            id: entry.key,
            name: name,
            parentId: Value(parentId),
            hlcTimestamp: '0',
            deviceId: 'test',
            createdAt: stamp,
            updatedAt: stamp,
            position: const Value(0),
            label: Value(label.storageValue),
          ),
        );
      }
    });
  }

  Future<List<String>> page({
    required FolderSortField sortField,
    required int offset,
    int limit = 20,
    bool ascending = true,
  }) async {
    final folders = await db.folderDao.getFoldersPaginated(
      parentId: parentId,
      limit: limit,
      offset: offset,
      sortField: sortField,
      ascending: ascending,
    );
    return [for (final folder in folders) folder.id];
  }

  test(
    'labelled folders come first in palette order, unlabelled last',
    () async {
      // `none` stores 0, so a plain `ORDER BY label` would lead with the
      // unlabelled folders — the opposite of what picking "sort by label" asks
      // for. The leading CASE term is what inverts that.
      await seedLabelledFolders({
        'f-pink': (ItemLabel.pink, 'Zeta'),
        'f-none-a': (ItemLabel.none, 'Alpha'),
        'f-red': (ItemLabel.red, 'Mu'),
        'f-none-b': (ItemLabel.none, 'Beta'),
        'f-teal': (ItemLabel.teal, 'Nu'),
      });

      expect(await page(sortField: FolderSortField.label, offset: 0), [
        'f-red',
        'f-teal',
        'f-pink',
        // Within the unlabelled run the name decides, exactly as it does for
        // `FolderSortField.name`.
        'f-none-a',
        'f-none-b',
      ]);
    },
  );

  test('folders sharing a label fall back to name then id', () async {
    await seedLabelledFolders({
      'f-c': (ItemLabel.red, 'Squat'),
      'f-a': (ItemLabel.red, 'Bench'),
      'f-b': (ItemLabel.red, 'Squat'),
      'f-z': (ItemLabel.none, 'Accessories'),
    });

    expect(await page(sortField: FolderSortField.label, offset: 0), [
      'f-a',
      // The two that tie on name, in id order.
      'f-b',
      'f-c',
      'f-z',
    ]);
  });

  // Two devices creating a subfolder in the same parent both compute
  // `max(position) + 1`, and the position syncs verbatim; `created_at` is
  // stored to the second. Without `id` the tie falls to insertion order,
  // which differs per device, and so would the list and every later drag.
  test('every folder sort lists ties in id order, whatever the insertion '
      'order (R71)', () async {
    await seedLabelledFolders({
      'f-c': (ItemLabel.none, 'Block'),
      'f-a': (ItemLabel.none, 'Block'),
      'f-b': (ItemLabel.none, 'Block'),
    });

    for (final field in FolderSortField.values) {
      for (final ascending in [true, false]) {
        expect(
          await page(sortField: field, offset: 0, ascending: ascending),
          ['f-a', 'f-b', 'f-c'],
          reason: '$field, ascending: $ascending',
        );
      }
    }
  });

  test(
    'a page boundary inside a run of ties serves each folder once',
    () async {
      // Forty subfolders, two labels, one shared name: every folder ties with
      // nineteen others on both ordering terms before `id`, so the boundary at
      // twenty falls in the middle of a run.
      await seedLabelledFolders({
        for (var i = 0; i < 40; i++)
          'f${i.toString().padLeft(3, '0')}': (
            i.isEven ? ItemLabel.red : ItemLabel.none,
            'Block',
          ),
      });

      final first = await page(sortField: FolderSortField.label, offset: 0);
      final second = await page(sortField: FolderSortField.label, offset: 20);

      expect(first, hasLength(20));
      expect(second, hasLength(20));
      expect(
        {...first, ...second},
        hasLength(40),
        reason: 'the label sort repeated or dropped a row across its pages',
      );
      expect(first, [
        for (var i = 0; i < 40; i += 2) 'f${i.toString().padLeft(3, '0')}',
      ]);
      expect(second, [
        for (var i = 1; i < 40; i += 2) 'f${i.toString().padLeft(3, '0')}',
      ]);
    },
  );

  test('sorting subfolders by label is one statement', () async {
    await seedLabelledFolders({'f-a': (ItemLabel.red, 'Bench')});

    counter.reset();
    await db.folderDao.getFoldersPaginated(
      parentId: parentId,
      limit: 20,
      offset: 0,
      sortField: FolderSortField.label,
      ascending: true,
    );
    expect(
      counter.count,
      1,
      reason: 'issued:\n${counter.statements.join('\n')}',
    );
  });

  // The unpaged reads behind the move picker, the move undo's "first folder"
  // and the folder-archive walk, and the watched list: rowid order differs
  // per device a sync copies the folders to (P review PR8).
  test('the unpaged subfolder lists end on id too', () async {
    await seedLabelledFolders({
      'f-c': (ItemLabel.none, 'Block'),
      'f-a': (ItemLabel.none, 'Block'),
      'f-d': (ItemLabel.none, 'Accessories'),
      'f-b': (ItemLabel.none, 'Block'),
    });
    await db.customStatement(
      "UPDATE folders SET position = 1 WHERE id IN ('f-c', 'f-a')",
    );
    await db.customStatement(
      "UPDATE folders SET position = 2 WHERE id = 'f-d'",
    );

    final listed = await db.folderDao.getFoldersByParent(parentId);
    expect([for (final f in listed) f.id], ['f-b', 'f-a', 'f-c', 'f-d']);

    final watched = await db.folderDao.watchFoldersByParent(parentId).first;
    expect([for (final f in watched) f.id], ['f-d', 'f-a', 'f-b', 'f-c']);
  });
}
