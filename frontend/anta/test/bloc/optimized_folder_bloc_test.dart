import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/optimized_folder/optimized_folder_bloc.dart';
import 'package:anta/bloc/optimized_folder/optimized_folder_event.dart';
import 'package:anta/bloc/optimized_folder/optimized_folder_state.dart';
import 'package:anta/database/database.dart' hide Folder;
import 'package:anta/models/folder.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/services/folder_storage_service.dart';

/// Colour labels on the folder half of the browser, with storage scripted.
///
/// The fake `extends` the real service over a lazily-opened in-memory
/// database, the way [optimized_note_bloc_test] does: every method the bloc
/// calls is overridden, so nothing here reaches SQLite, and the service can
/// still grow members without a wall of stubs going stale.
///
/// The one thing worth pinning beyond "the service is called": a write
/// reloads only the parent the bloc has open. The one bloc serves every
/// stacked folder page, so reloading another parent moved it off the page in
/// front; a page under it reads its own parent again on its return.
class _FakeFolderStorage extends FolderStorageService {
  _FakeFolderStorage(FolderRepository repository)
    : super(repository: repository);

  List<Folder> all = const [];
  final List<({String? parentId, int page})> loads = [];

  /// The `pageSize` of each read in [loads], kept beside it rather than in it
  /// so the cases that only care about "which parent, which page" can keep
  /// comparing whole records.
  final List<int> loadSizes = [];

  /// The `sortOrder` of each read in [loads], kept beside it as [loadSizes]
  /// is.
  final List<FoldersSortOrder> loadOrders = [];
  final List<({String id, ItemLabel label})> labels = [];
  final List<({List<String> ids, ItemLabel label})> bulkLabels = [];

  final StreamController<FolderChange> _changes =
      StreamController<FolderChange>.broadcast();

  /// Stands in for the repository's change stream, so a test can raise the
  /// event a write would have raised without going near SQLite.
  @override
  Stream<FolderChange> get changes => _changes.stream;

  void emitChange(FolderChange change) => _changes.add(change);

  Future<void> dispose() => _changes.close();

  /// What [setFolderLabel] answers. Null stands for "gone or tombstoned".
  Folder? labelResult;

  bool failLabels = false;

  /// Parks the next read, so a test can land another event while a page is
  /// still in flight.
  Completer<void>? loadGate;

  /// Makes the next read throw, for the load-more failure path.
  bool failNextLoad = false;

  /// Parks [initialize], so a test can land an event while a load waits on
  /// its first await.
  Completer<void>? initGate;

  @override
  Future<void> initialize() async {
    if (initGate != null) await initGate!.future;
  }

  @override
  void invalidateCache() {}

  @override
  Future<PaginatedFolders> loadFoldersPaginated({
    String? parentId,
    int page = 1,
    int pageSize = FolderStorageService.defaultPageSize,
    FoldersSortOrder sortOrder = FoldersSortOrder.nameAsc,
  }) async {
    loads.add((parentId: parentId, page: page));
    loadSizes.add(pageSize);
    loadOrders.add(sortOrder);
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('storage unavailable');
    }
    if (loadGate != null) await loadGate!.future;
    final matching = [
      for (final folder in all)
        if (folder.parentId == parentId) folder,
    ];
    final start = (page - 1) * pageSize;
    final slice = matching.skip(start).take(pageSize).toList(growable: false);
    return PaginatedFolders(
      folders: slice,
      currentPage: page,
      totalPages: (matching.length / pageSize).ceil().clamp(1, 1 << 30),
      totalCount: matching.length,
      hasMore: start + slice.length < matching.length,
    );
  }

  @override
  Future<Folder?> setFolderLabel(String folderId, ItemLabel label) async {
    labels.add((id: folderId, label: label));
    if (failLabels) throw StateError('storage unavailable');
    return labelResult;
  }

  @override
  Future<int> setLabelForFolders(
    List<String> folderIds,
    ItemLabel label,
  ) async {
    if (folderIds.isEmpty) return 0;
    bulkLabels.add((ids: folderIds, label: label));
    if (failLabels) throw StateError('storage unavailable');
    all = [
      for (final folder in all)
        if (folderIds.contains(folder.id))
          folder.copyWith(label: label)
        else
          folder,
    ];
    return folderIds.length;
  }
}

Folder _folder(int index, {String? parentId = 'p1'}) => Folder(
  id: 'f${index.toString().padLeft(3, '0')}',
  name: 'Block $index',
  parentId: parentId,
  createdAt: DateTime(2026, 9, 12),
);

void main() {
  late AppDatabase db;
  late _FakeFolderStorage storage;

  setUpAll(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDownAll(() async => db.close());

  setUp(() {
    storage = _FakeFolderStorage(FolderRepository(database: db));
    storage.all = [for (var i = 0; i < 6; i++) _folder(i)];
  });

  tearDown(() => storage.dispose());

  Future<OptimizedFolderBloc> openedOn(String? parentId) async {
    final bloc = OptimizedFolderBloc(storageService: storage);
    bloc.add(LoadFoldersPaginated(parentId: parentId, pageSize: 20));
    await pumpEventQueue();
    return bloc;
  }

  group('refreshing in place', () {
    /// Everything the bloc emits from now until [stop] is called.
    (List<OptimizedFolderState>, Future<void> Function()) record(
      OptimizedFolderBloc bloc,
    ) {
      final seen = <OptimizedFolderState>[];
      final sub = bloc.stream.listen(seen.add);
      return (seen, sub.cancel);
    }

    test('a refresh of the open list never passes through Loading', () async {
      final bloc = await openedOn('p1');
      final (seen, stop) = record(bloc);

      bloc.add(const RefreshFolders(parentId: 'p1'));
      await pumpEventQueue();
      await stop();

      expect(
        seen.whereType<OptimizedFolderLoading>(),
        isEmpty,
        reason:
            'the one Loading frame is the flash: the browser drops its cached '
            'rows when selection ends, so that frame renders a spinner',
      );
      expect(seen.last, isA<OptimizedFolderLoaded>());
      await bloc.close();
    });

    test('a list three pages deep comes back three pages deep', () async {
      storage.all = [for (var i = 0; i < 70; i++) _folder(i)];
      final bloc = await openedOn('p1');

      bloc.add(const LoadMoreFolders(parentId: 'p1'));
      await pumpEventQueue();
      bloc.add(const LoadMoreFolders(parentId: 'p1'));
      await pumpEventQueue();
      expect(
        (bloc.state as OptimizedFolderLoaded).paginatedFolders.folders,
        hasLength(60),
      );

      storage.loads.clear();
      storage.loadSizes.clear();

      bloc.add(const RefreshFolders(parentId: 'p1'));
      await pumpEventQueue();

      expect(storage.loads, [(parentId: 'p1', page: 1)]);
      expect(
        storage.loadSizes,
        [60],
        reason: 'three pages re-read as one statement, not three reads',
      );

      final loaded = bloc.state as OptimizedFolderLoaded;
      expect(loaded.paginatedFolders.currentPage, 3);
      expect(loaded.paginatedFolders.folders, hasLength(60));
      expect(loaded.paginatedFolders.folders.first.id, 'f000');
      expect(loaded.paginatedFolders.folders.last.id, 'f059');
      expect(loaded.paginatedFolders.hasMore, isTrue);
      await bloc.close();
    });

    test(
      'loading more after a refresh reads the page after the ones it has',
      () async {
        storage.all = [for (var i = 0; i < 70; i++) _folder(i)];
        final bloc = await openedOn('p1');
        bloc.add(const LoadMoreFolders(parentId: 'p1'));
        await pumpEventQueue();
        bloc.add(const LoadMoreFolders(parentId: 'p1'));
        await pumpEventQueue();
        bloc.add(const RefreshFolders(parentId: 'p1'));
        await pumpEventQueue();

        storage.loads.clear();
        storage.loadSizes.clear();

        bloc.add(const LoadMoreFolders(parentId: 'p1'));
        await pumpEventQueue();

        expect(storage.loads, [(parentId: 'p1', page: 4)]);
        expect(storage.loadSizes, [20]);

        final loaded = bloc.state as OptimizedFolderLoaded;
        expect(loaded.paginatedFolders.folders, hasLength(70));
        expect(loaded.paginatedFolders.folders.last.id, 'f069');
        expect(loaded.paginatedFolders.hasMore, isFalse);
        await bloc.close();
      },
    );

    // A page back in front names its parent and its order: the bloc is
    // re-aimed there without a Loading, which blanked the count and the rows
    // that page still had drawn (second review, finding 3).
    test('a refresh for another parent re-aims the bloc there quietly, in '
        'the order of the page that asked', () async {
      storage.all = [
        for (var i = 0; i < 6; i++) _folder(i),
        _folder(9, parentId: 'elsewhere'),
      ];
      final bloc = await openedOn('p1');
      storage.loads.clear();
      storage.loadOrders.clear();
      final (seen, stop) = record(bloc);

      bloc.add(
        const RefreshFolders(
          parentId: 'elsewhere',
          sortOrder: FoldersSortOrder.nameDesc,
        ),
      );
      await pumpEventQueue();
      await stop();

      expect(seen.whereType<OptimizedFolderLoading>(), isEmpty);
      expect(storage.loads, [(parentId: 'elsewhere', page: 1)]);
      expect(
        storage.loadOrders,
        [FoldersSortOrder.nameDesc],
        reason:
            'read in the order the bloc had open, the root showed a '
            'child\'s order (finding 2)',
      );
      final loaded = bloc.state as OptimizedFolderLoaded;
      expect(loaded.parentId, 'elsewhere');
      expect(loaded.paginatedFolders.folders.single.id, 'f009');
      await bloc.close();
    });

    test('a re-aimed bloc reads its new parent from the first page', () async {
      storage.all = [
        for (var i = 0; i < 70; i++) _folder(i),
        _folder(99, parentId: 'elsewhere'),
      ];
      final bloc = await openedOn('p1');
      bloc.add(const LoadMoreFolders(parentId: 'p1'));
      await pumpEventQueue();
      bloc.add(const LoadMoreFolders(parentId: 'p1'));
      await pumpEventQueue();
      storage.loadSizes.clear();

      bloc.add(
        const RefreshFolders(
          parentId: 'elsewhere',
          sortOrder: FoldersSortOrder.nameAsc,
        ),
      );
      await pumpEventQueue();

      expect(
        storage.loadSizes,
        [20],
        reason: 'the three pages were p1\'s; the new parent has read none',
      );
      expect(
        (bloc.state as OptimizedFolderLoaded).paginatedFolders.currentPage,
        1,
      );
      await bloc.close();
    });

    test('a refresh with no order keeps the one the open parent was loaded '
        'in', () async {
      final bloc = OptimizedFolderBloc(storageService: storage);
      bloc.add(
        const LoadFoldersPaginated(
          parentId: 'p1',
          pageSize: 20,
          sortOrder: FoldersSortOrder.createdDesc,
        ),
      );
      await pumpEventQueue();
      storage.loadOrders.clear();

      // What the bloc's own coalescer sends.
      bloc.add(const RefreshFolders(parentId: 'p1'));
      await pumpEventQueue();

      expect(storage.loadOrders, [FoldersSortOrder.createdDesc]);
      await bloc.close();
    });

    test('a change on the open parent reloads it in place', () async {
      final bloc = await openedOn('p1');
      storage.loads.clear();
      storage.loadSizes.clear();
      final (seen, stop) = record(bloc);

      storage.emitChange(
        const FolderChange(
          type: FolderChangeType.labelled,
          folderId: 'f000',
          parentId: 'p1',
        ),
      );
      await pumpEventQueue();
      await stop();

      expect(seen.whereType<OptimizedFolderLoading>(), isEmpty);
      expect(storage.loads, [(parentId: 'p1', page: 1)]);
      expect(storage.loadSizes, [20]);
      expect(bloc.state, isA<OptimizedFolderLoaded>());
      await bloc.close();
    });

    test('a refresh landing mid load-more keeps the refreshed rows', () async {
      storage.all = [for (var i = 0; i < 70; i++) _folder(i)];
      final bloc = await openedOn('p1');

      // Page two is parked, so the refresh below lands while it is in flight.
      final gate = Completer<void>();
      storage.loadGate = gate;
      bloc.add(const LoadMoreFolders(parentId: 'p1'));
      await pumpEventQueue();

      storage.loadGate = null;
      storage.all = [
        for (final folder in storage.all)
          folder.id == 'f000' ? folder.copyWith(label: ItemLabel.blue) : folder,
      ];
      bloc.add(const RefreshFolders(parentId: 'p1'));
      await pumpEventQueue();
      expect(
        (bloc.state as OptimizedFolderLoaded)
            .paginatedFolders
            .folders
            .first
            .label,
        ItemLabel.blue,
      );

      gate.complete();
      await pumpEventQueue();

      final loaded = bloc.state as OptimizedFolderLoaded;
      expect(
        loaded.paginatedFolders.folders.first.label,
        ItemLabel.blue,
        reason:
            'the load-more was appending to the state it emitted before its '
            'await; building on that snapshot puts the pre-refresh rows back',
      );
      expect(loaded.paginatedFolders.folders, hasLength(20));
      await bloc.close();
    });

    test(
      'a load-more that throws leaves the page counter where it was',
      () async {
        storage.all = [for (var i = 0; i < 70; i++) _folder(i)];
        final bloc = await openedOn('p1');
        storage.loads.clear();

        storage.failNextLoad = true;
        bloc.add(const LoadMoreFolders(parentId: 'p1'));
        await pumpEventQueue();

        expect(storage.loads, [(parentId: 'p1', page: 2)]);
        expect(
          (bloc.state as OptimizedFolderLoaded).isLoadingMore,
          isFalse,
          reason: 'a failed read must not leave the list spinning',
        );

        bloc.add(const LoadMoreFolders(parentId: 'p1'));
        await pumpEventQueue();

        expect(
          storage.loads.last,
          (parentId: 'p1', page: 2),
          reason:
              'counting the page up before it is in hand skips the rows the '
              'failed read was going to bring, for good',
        );
        final loaded = bloc.state as OptimizedFolderLoaded;
        expect(loaded.paginatedFolders.folders, hasLength(40));
        expect(loaded.paginatedFolders.folders.last.id, 'f039');
        await bloc.close();
      },
    );

    test('a burst of changes for one parent reloads it once', () async {
      final bloc = await openedOn('p1');
      storage.loads.clear();

      for (var i = 0; i < 10; i++) {
        storage.emitChange(
          FolderChange(
            type: FolderChangeType.labelled,
            folderId: 'f00$i',
            parentId: 'p1',
          ),
        );
      }
      await pumpEventQueue();

      expect(
        storage.loads,
        [(parentId: 'p1', page: 1)],
        reason:
            'a bulk label raises one change per row, and each reload is now a '
            'read of every page the list has',
      );
      await bloc.close();
    });

    test('a burst on the open parent, overtaken by a refresh a page asked of '
        'another, reads only that one', () async {
      final bloc = await openedOn('p1');
      storage.loads.clear();

      // The page's own parent, twice, plus a move out of it — which the bloc
      // answers for through `sourceParentId`.
      storage.emitChange(
        const FolderChange(
          type: FolderChangeType.labelled,
          folderId: 'f000',
          parentId: 'p1',
        ),
      );
      storage.emitChange(
        const FolderChange(
          type: FolderChangeType.labelled,
          folderId: 'f001',
          parentId: 'p1',
        ),
      );
      bloc.add(const RefreshFolders(parentId: 'elsewhere'));
      await pumpEventQueue();

      // The directly added refresh does not go through the coalescer, so it
      // runs ahead of the flush and moves the bloc to the page that asked.
      // The flush reloads only the parent open by then: reading p1 again
      // would move the bloc back off the page in front, and p1's own page
      // reads it on its return (`didPopNext`).
      expect(storage.loads, <({String? parentId, int page})>[
        (parentId: 'elsewhere', page: 1),
      ]);
      await bloc.close();
    });

    test(
      'a bulk label keeps the list at the depth it was scrolled to',
      () async {
        storage.all = [for (var i = 0; i < 70; i++) _folder(i)];
        final bloc = await openedOn('p1');
        bloc.add(const LoadMoreFolders(parentId: 'p1'));
        await pumpEventQueue();
        final (seen, stop) = record(bloc);

        bloc.add(
          const SetOptimizedFoldersLabel(
            folderIds: ['f000', 'f001'],
            label: ItemLabel.blue,
          ),
        );
        await pumpEventQueue();
        await stop();

        expect(seen.whereType<OptimizedFolderLoading>(), isEmpty);
        final loaded = bloc.state as OptimizedFolderLoaded;
        expect(loaded.paginatedFolders.folders, hasLength(40));
        expect(loaded.paginatedFolders.currentPage, 2);
        expect(loaded.paginatedFolders.folders.take(2).map((f) => f.label), [
          ItemLabel.blue,
          ItemLabel.blue,
        ]);
        await bloc.close();
      },
    );
  });

  group('labelling one folder', () {
    test('reaches storage and reloads the list behind it', () async {
      final bloc = await openedOn('p1');
      storage.loads.clear();
      storage.labelResult = _folder(0);

      bloc.add(
        const SetOptimizedFolderLabel(folderId: 'f000', label: ItemLabel.red),
      );
      await pumpEventQueue();

      expect(storage.labels, [(id: 'f000', label: ItemLabel.red)]);
      expect(storage.loads, [(parentId: 'p1', page: 1)]);
      expect(bloc.state, isA<OptimizedFolderLoaded>());
      await bloc.close();
    });

    test('a folder labelled under another parent leaves the open list where '
        'it is', () async {
      final bloc = await openedOn('p1');
      storage.loads.clear();
      storage.labelResult = _folder(0, parentId: 'elsewhere');

      bloc.add(
        const SetOptimizedFolderLabel(folderId: 'f000', label: ItemLabel.red),
      );
      await pumpEventQueue();

      expect(
        storage.loads,
        isEmpty,
        reason:
            'loading that parent moved the one bloc off the page in front; the '
            'page of that parent reads it again on its return',
      );
      expect((bloc.state as OptimizedFolderLoaded).parentId, 'p1');
      await bloc.close();
    });

    test(
      'falls back to the page\'s own parent when the write came back null',
      () async {
        final bloc = await openedOn('p1');
        storage.loads.clear();
        storage.labelResult = null;

        bloc.add(
          const SetOptimizedFolderLabel(folderId: 'gone', label: ItemLabel.red),
        );
        await pumpEventQueue();

        expect(
          storage.loads,
          [(parentId: 'p1', page: 1)],
          reason:
              'a null answer means the folder is gone, not that the page should '
              'reload the root',
        );
        await bloc.close();
      },
    );

    test('a throwing write reports the parent it failed in', () async {
      final bloc = await openedOn('p1');
      storage.failLabels = true;

      bloc.add(
        const SetOptimizedFolderLabel(folderId: 'f000', label: ItemLabel.red),
      );
      await pumpEventQueue();

      expect(bloc.state, isA<OptimizedFolderError>());
      expect((bloc.state as OptimizedFolderError).parentId, 'p1');
      await bloc.close();
    });
  });

  group('labelling a selection', () {
    test('is one bulk call and one reload', () async {
      final bloc = await openedOn('p1');
      storage.loads.clear();

      bloc.add(
        const SetOptimizedFoldersLabel(
          folderIds: ['f000', 'f001'],
          label: ItemLabel.blue,
        ),
      );
      await pumpEventQueue();

      expect(storage.bulkLabels, hasLength(1));
      expect(storage.bulkLabels.single.ids, ['f000', 'f001']);
      expect(storage.bulkLabels.single.label, ItemLabel.blue);
      expect(storage.loads, [(parentId: 'p1', page: 1)]);

      final loaded = bloc.state as OptimizedFolderLoaded;
      expect(loaded.paginatedFolders.folders.take(2).map((f) => f.label), [
        ItemLabel.blue,
        ItemLabel.blue,
      ]);
      await bloc.close();
    });

    test('an empty selection touches neither storage nor the list', () async {
      final bloc = await openedOn('p1');
      storage.loads.clear();

      bloc.add(
        const SetOptimizedFoldersLabel(folderIds: [], label: ItemLabel.blue),
      );
      await pumpEventQueue();

      expect(storage.bulkLabels, isEmpty);
      expect(storage.loads, isEmpty);
      await bloc.close();
    });

    test('a throwing bulk write reports the parent it failed in', () async {
      final bloc = await openedOn('p1');
      storage.failLabels = true;

      bloc.add(
        const SetOptimizedFoldersLabel(
          folderIds: ['f000'],
          label: ItemLabel.blue,
        ),
      );
      await pumpEventQueue();

      expect(bloc.state, isA<OptimizedFolderError>());
      expect((bloc.state as OptimizedFolderError).parentId, 'p1');
      await bloc.close();
    });
  });

  group('one bloc under stacked pages', () {
    test('a load as the browser asks for it reads the parent whole', () async {
      storage.all = [for (var i = 0; i < 25; i++) _folder(i)];
      final bloc = OptimizedFolderBloc(storageService: storage);

      bloc.add(const LoadFoldersPaginated(parentId: 'p1'));
      await pumpEventQueue();

      final loaded = bloc.state as OptimizedFolderLoaded;
      expect(
        loaded.paginatedFolders.folders,
        hasLength(25),
        reason: 'the page never asks for a second page of folders',
      );
      expect(loaded.paginatedFolders.hasMore, isFalse);
      await bloc.close();
    });

    // The root back in front after a child: its refresh re-aims the bloc, so
    // the coalescer now answers the root's changes, in the root's order, and
    // no longer the child's.
    test('a change after a re-aim reloads the parent re-aimed at, in its '
        'order, and no longer the one before', () async {
      storage.all = [
        for (var i = 0; i < 3; i++) _folder(i, parentId: null),
        _folder(9),
      ];
      final bloc = await openedOn(null);
      bloc.add(
        const LoadFoldersPaginated(
          parentId: 'p1',
          sortOrder: FoldersSortOrder.nameDesc,
        ),
      );
      await pumpEventQueue();
      bloc.add(
        const RefreshFolders(
          parentId: null,
          sortOrder: FoldersSortOrder.nameAsc,
        ),
      );
      await pumpEventQueue();
      storage.loads.clear();
      storage.loadOrders.clear();

      storage.emitChange(
        const FolderChange(
          type: FolderChangeType.created,
          folderId: 'f100',
          parentId: 'p1',
        ),
      );
      await pumpEventQueue();
      expect(storage.loads, isEmpty, reason: 'p1 is no longer open');

      storage.emitChange(
        const FolderChange(
          type: FolderChangeType.created,
          folderId: 'f101',
          parentId: null,
        ),
      );
      await pumpEventQueue();
      expect(storage.loads, [(parentId: null, page: 1)]);
      expect(storage.loadOrders, [FoldersSortOrder.nameAsc]);
      expect((bloc.state as OptimizedFolderLoaded).parentId, isNull);
      await bloc.close();
    });

    // Two loads in flight (second review, finding 4): the bloc's last state
    // and the parent it reloads must not come apart, and the page in front
    // must not lose the bloc to a read that ends late.
    test('a load overtaken by a re-aim neither emits its rows nor takes the '
        'bloc back', () async {
      storage.all = [
        for (var i = 0; i < 3; i++) _folder(i),
        _folder(9, parentId: 'stale'),
      ];
      final bloc = await openedOn('p1');

      final gate = Completer<void>();
      storage.loadGate = gate;
      bloc.add(const LoadFoldersPaginated(parentId: 'stale', pageSize: 20));
      await pumpEventQueue();
      storage.loadGate = null;
      bloc.add(
        const RefreshFolders(
          parentId: 'p1',
          sortOrder: FoldersSortOrder.nameAsc,
        ),
      );
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();

      expect((bloc.state as OptimizedFolderLoaded).parentId, 'p1');
      storage.loads.clear();
      storage.emitChange(
        const FolderChange(
          type: FolderChangeType.created,
          folderId: 'f100',
          parentId: 'p1',
        ),
      );
      await pumpEventQueue();
      expect(storage.loads, [(parentId: 'p1', page: 1)]);
      await bloc.close();
    });

    // The load is aimed before its first await: a re-aim asked while that
    // await is still out is the later request and must win.
    test('a re-aim asked while a load waits on its first await wins over '
        'it', () async {
      storage.all = [
        for (var i = 0; i < 3; i++) _folder(i),
        _folder(9, parentId: 'stale'),
      ];
      final bloc = await openedOn('p1');

      final gate = Completer<void>();
      storage.initGate = gate;
      bloc.add(const LoadFoldersPaginated(parentId: 'stale', pageSize: 20));
      await pumpEventQueue();
      storage.initGate = null;
      bloc.add(
        const RefreshFolders(
          parentId: 'p1',
          sortOrder: FoldersSortOrder.nameAsc,
        ),
      );
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();

      expect(bloc.isAimedAt('p1', FoldersSortOrder.nameAsc), isTrue);
      expect((bloc.state as OptimizedFolderLoaded).parentId, 'p1');
      await bloc.close();
    });

    // A page launch restore builds under another reads its rows without
    // taking the bloc from the page in front (third review, item 1).
    test(
      'a peek answers the rows and neither emits nor moves the aim',
      () async {
        storage.all = [
          for (var i = 0; i < 3; i++) _folder(i),
          _folder(9, parentId: 'covered'),
        ];
        final bloc = await openedOn('p1');
        storage.loadOrders.clear();
        final seen = <OptimizedFolderState>[];
        final sub = bloc.stream.listen(seen.add);

        final done = Completer<PaginatedFolders>();
        bloc.add(
          PeekFolders(
            parentId: 'covered',
            sortOrder: FoldersSortOrder.nameDesc,
            done: done,
          ),
        );
        final answer = await done.future;
        await pumpEventQueue();
        await sub.cancel();

        expect(answer.folders.single.id, 'f009');
        expect(storage.loadOrders, [FoldersSortOrder.nameDesc]);
        expect(seen, isEmpty);
        expect(bloc.isAimedAt('p1', FoldersSortOrder.nameAsc), isTrue);
        expect((bloc.state as OptimizedFolderLoaded).parentId, 'p1');
        await bloc.close();
      },
    );
  });
}
