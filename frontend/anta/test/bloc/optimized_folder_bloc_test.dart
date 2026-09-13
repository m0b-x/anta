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
  final List<({String id, ItemLabel label})> labels = [];
  final List<({List<String> ids, ItemLabel label})> bulkLabels = [];

  /// What [setFolderLabel] answers. Null stands for "gone or tombstoned".
  Folder? labelResult;

  bool failLabels = false;

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
  Future<int> setLabelForFolders(List<String> folderIds, ItemLabel label) async {
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

  Future<OptimizedFolderBloc> openedOn(String? parentId) async {
    final bloc = OptimizedFolderBloc(storageService: storage);
    bloc.add(LoadFoldersPaginated(parentId: parentId, pageSize: 20));
    await pumpEventQueue();
    return bloc;
  }

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

    test('falls back to the page\'s own parent when the write came back null',
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
    });

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
      expect(
        loaded.paginatedFolders.folders.take(2).map((f) => f.label),
        [ItemLabel.blue, ItemLabel.blue],
      );
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
