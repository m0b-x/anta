import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/note_money_ledger_service.dart';

/// `NoteMoneyLedgerService.refresh` resolves every linked note in two batched
/// reads. The statement counts in `test/database/query_count_test.dart` pin the
/// shape; these two cases pin the *membership* of the resulting ledger, which
/// no statement count can see:
///
///  - a linked note with no chunks still gets an entry. The batch returns no
///    rows for it, so a reader that walks only the returned rows drops it, and
///    its day bars and month-net contribution vanish with no error anywhere.
///  - a soft-deleted linked note gets none. `getNotesByIds` filters tombstones
///    and the fold loop iterates *those notes*, never the linked id set.
///
/// The service has no injection seam, so this drives the real stack over a
/// throwaway database, as `calendar_bloc_month_net_test.dart` does. Notes are
/// seeded through a **separate** repository instance so the registered one
/// starts with a cold content LRU — otherwise every read is served from the
/// cache the writes populated and the batch is never exercised.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late NoteRepository seedRepository;
  late NoteRepository repository;
  late NoteMoneyLedgerService ledger;

  final startDate = DateTime.utc(2026, 8, 10);

  CalendarEvent linkedEvent(String id, String noteId) => CalendarEvent(
    id: id,
    title: 'Shop',
    categoryId: 'gym',
    startDate: startDate,
    rule: const OneTimeRecurrence(),
    noteId: noteId,
  );

  Future<String> createNote(String content) async {
    final note = await seedRepository.createNote(
      folderId: 'root',
      title: 'Ledger',
      content: content,
      preview: content,
      contentLength: content.length,
      chunkCount: 1,
      isCompressed: false,
    );
    return note.id;
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_money_ledger');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );

    final db = await AppDatabase.getInstance();
    await db.userSettingsDao.setValue(SettingsKeys.moneyLedgerEnabled, 'true');
    seedRepository = NoteRepository(database: db);
    repository = NoteRepository(database: db);
    GetIt.I.registerSingleton<NoteRepository>(repository);
    ledger = await NoteMoneyLedgerService.getInstance();
  });

  tearDownAll(() async {
    NoteMoneyLedgerService.reset();
    await GetIt.I.reset();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('a linked note with no chunks still gets a ledger entry', () async {
    final empty = await createNote('');
    final funded = await createNote(r'$+ 10.00 protein');
    expect(await seedRepository.loadContent(empty), '');

    await ledger.refresh([
      linkedEvent('e-empty', empty),
      linkedEvent('e-funded', funded),
    ]);

    expect(ledger.ledgerFor(empty), isNotNull);
    expect(ledger.ledgerFor(empty)!.net, 0);
    expect(ledger.ledgerFor(empty)!.title, 'Ledger');
    // The companion entry proves the refresh ran at all, so a ledger that is
    // simply empty cannot pass this test.
    expect(ledger.ledgerFor(funded)!.net, 1000);
  });

  test('a soft-deleted linked note gets no ledger entry', () async {
    final deleted = await createNote(r'$+ 99.00 gone');
    await seedRepository.deleteNote(deleted);

    await ledger.refresh([linkedEvent('e-deleted', deleted)]);

    expect(ledger.ledgerFor(deleted), isNull);
  });

  test('one unreadable note does not take the others down with it', () async {
    final corrupt = await createNote('placeholder');
    final healthy = await createNote(r'$+ 25.00 shoes');

    // Flag the chunk compressed while leaving plain text in it, so decoding
    // throws — the shape a truncated or half-written chunk takes on disk.
    final db = await AppDatabase.getInstance();
    await db.customStatement(
      'UPDATE content_chunks SET is_compressed = 1 WHERE note_id = ?',
      [corrupt],
    );

    await ledger.refresh([
      linkedEvent('e-corrupt', corrupt),
      linkedEvent('e-healthy', healthy),
    ]);

    // Batching moved decompression out of the per-note try/catch, so before
    // the fix a single bad chunk threw out of refresh() and wiped the money
    // surfaces for *every* linked note.
    expect(
      ledger.ledgerFor(healthy),
      isNotNull,
      reason: 'a corrupt note must not hide the rest',
    );
    expect(ledger.ledgerFor(healthy)!.net, 2500);
    // And the corrupt note is skipped, not zeroed: a balance of 0 would be a
    // claim about its content that we cannot make.
    expect(ledger.ledgerFor(corrupt), isNull);
  });
}
