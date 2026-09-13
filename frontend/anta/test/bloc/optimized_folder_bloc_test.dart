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
/// The one thing worth pinning beyond "the service is called": a single-folder
/// label reloads the list the *labelled folder* lives in, falling back to the
/// page's own parent when the write came back null. Refreshing the wrong
/// parent leaves the row on screen showing its old colour.
class _FakeFolderStorage extends FolderStorageService {
  _FakeFolderStorage(FolderRepository repository)
    : super(repository: repository);

  List<Folder> all = const [];
  final List<({String? parentId, int page})> loads = [];

  /// The `pageSize` of each read in [loads], kept beside it rather than in it
  /// so the cases that only care about "which parent, which page" can keep
  /// comparing whole records.
  final List<int> loadSizes = [];
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

  @override
  Future<void> initialize() async {}

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

    test(
      'a refresh aimed at another parent still runs the full load',
      () async {
        storage.all = [
          for (var i = 0; i < 6; i++) _folder(i),
          _folder(9, parentId: 'elsewhere'),
        ];
        final bloc = await openedOn('p1');
        storage.loads.clear();
        final (seen, stop) = record(bloc);

        bloc.add(const RefreshFolders(parentId: 'elsewhere'));
        await pumpEventQueue();
        await stop();

        expect(seen.whereType<OptimizedFolderLoading>(), hasLength(1));
        expect(storage.loads, [(parentId: 'elsewhere', page: 1)]);
        final loaded = bloc.state as OptimizedFolderLoaded;
        expect(loaded.parentId, 'elsewhere');
        expect(loaded.paginatedFolders.folders.single.id, 'f009');
        await bloc.close();
      },
    );

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

    test('a burst touching two parents reloads both, once each', () async {
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

      // Unordered: the directly added refresh does not go through the
      // coalescer, so it runs ahead of the flushed one. What is pinned is
      // that each parent is read exactly once.
      expect(
        storage.loads,
        unorderedEquals(<({String? parentId, int page})>[
          (parentId: 'p1', page: 1),
          (parentId: 'elsewhere', page: 1),
        ]),
      );
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

    test('reloads the parent the labelled folder actually lives in', () async {
      final bloc = await openedOn('p1');
      storage.loads.clear();
      storage.labelResult = _folder(0, parentId: 'elsewhere');

      bloc.add(
        const SetOptimizedFolderLabel(folderId: 'f000', label: ItemLabel.red),
      );
      await pumpEventQueue();

      expect(storage.loads, [(parentId: 'elsewhere', page: 1)]);
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
}
