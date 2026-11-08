import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/database/database.dart';
import 'package:anta/repositories/note_repository.dart';

import '../database/support/db_test_support.dart';

/// S5 — the content cache is bounded by weight as well as by count: fifty
/// multi-megabyte bodies must not all stay resident.
void main() {
  late AppDatabase db;
  late NoteRepository repository;

  setUp(() async {
    db = await openTestDatabase();
    repository = NoteRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<String> create(String content) async {
    final note = await repository.createNote(
      folderId: 'root',
      title: 'Body ${content.length}',
      content: content,
      preview: '',
      contentLength: content.length,
      chunkCount: 1,
      isCompressed: false,
    );
    return note.id;
  }

  test('three bodies of 4 Mi code units keep only the newest two', () async {
    const half = AppConstants.maxContentCacheCodeUnits ~/ 2;
    final first = await create('a' * half);
    final second = await create('b' * half);
    final third = await create('c' * half);

    expect(repository.isContentCached(first), isFalse);
    expect(repository.isContentCached(second), isTrue);
    expect(repository.isContentCached(third), isTrue);
  });

  test('a body past the whole bound is still cached, alone', () async {
    final small = await create('small');
    final huge = await create(
      'h' * (AppConstants.maxContentCacheCodeUnits + 1),
    );

    expect(repository.isContentCached(huge), isTrue);
    expect(repository.isContentCached(small), isFalse);
  });
}
