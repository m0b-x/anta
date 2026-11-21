import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_grid_filters.dart';
import 'package:anta/models/calendar_selection_source.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/note_money_ledger_service.dart';

/// `CalendarBloc.monthNetFor` memoizes an O(all events) scan that the month
/// header runs on every grid rebuild. The cache has two independent inputs and
/// this suite pins both:
///
///  - the event set / category filter, cleared through `_invalidateDayCache`;
///  - the ledger itself, which the per-note change stream rewrites **outside**
///    every handler that invalidates. That is why the entry is paired with
///    `NoteMoneyLedgerService.revision` — without it, editing a linked note's
///    amounts leaves the header showing the old total for the rest of the
///    session while every day cell already shows the new one.
///
/// Neither service has an injection seam, so this drives the real stack over a
/// throwaway database, as `calendar_bloc_presence_test.dart` does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;
  late NoteRepository repository;
  late NoteMoneyLedgerService ledger;
  late String noteId;

  final month = DateTime.utc(2026, 8, 1);
  final startDate = DateTime.utc(2026, 8, 10);

  Future<String> createNote(String content) async {
    final note = await repository.createNote(
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
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_month_net');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );

    final db = await AppDatabase.getInstance();
    // The money ledger reads its config through settings and its content
    // through the repository; both must exist before the first refresh.
    await db.userSettingsDao.setValue(SettingsKeys.moneyLedgerEnabled, 'true');
    repository = NoteRepository(database: db);
    GetIt.I.registerSingleton<NoteRepository>(repository);
    ledger = await NoteMoneyLedgerService.getInstance();
  });

  tearDownAll(() async {
    await GetIt.I.reset();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Dispatches and waits for the emit it causes — every handler awaits real
  /// SQLite work on drift's background isolate.
  Future<void> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    await next;
  }

  setUp(() async {
    final service = await CalendarEventService.getInstance();
    await service.tombstoneAll();
    noteId = await createNote(r'$+ 10.00 protein');

    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'e1',
          title: 'Shop',
          categoryId: 'gym',
          startDate: startDate,
          rule: const OneTimeRecurrence(),
          noteId: noteId,
        ),
      ),
    );
    await ledger.refresh([
      ...(await CalendarEventService.getInstance()).events,
    ]);
  });

  tearDown(() async {
    await bloc.close();
  });

  test('sums the linked note net for the month', () async {
    expect(bloc.monthNetFor(month), 1000);
    expect(bloc.monthNetFor(DateTime.utc(2026, 9, 1)), 0);
  });

  // Review A11, second leg: my event linked, before the picker listed my
  // notes alone, to a note that is the partner's.
  test('an event of mine never counts a partner\'s note', () async {
    expect(bloc.monthNetFor(month), 1000);

    NoteMoneyLedgerService.seedForTesting({
      noteId: (balance: 1000, net: 1000, title: 'Ledger', fromPartner: true),
    });

    expect(bloc.monthNetFor(month), 0);
  });

  // Review A11, third leg: one partner's note named on one day by an event
  // of mine and by one of the partner's. The cells' rule decides before
  // their dedup, so the partner's event counts the note once, whichever of
  // the two comes first.
  group('one note named by my event and by the partner\'s', () {
    late AppDatabase db;

    setUp(() async {
      db = await AppDatabase.getInstance();
      addTearDown(() async {
        await db.sharedRowDao.writing(
          () => db.customStatement(
            "UPDATE calendar_events SET owner_id = NULL "
            "WHERE owner_id = 'maria'",
          ),
        );
        await db.syncDao.deleteValue(SyncDao.keySharedOwner);
      });
      await dispatch(
        CreateCalendarEvent(
          event: CalendarEvent(
            id: 'e2',
            title: 'Shop too',
            categoryId: 'gym',
            startDate: startDate,
            rule: const OneTimeRecurrence(),
            noteId: noteId,
          ),
        ),
      );
    });

    /// [partners] made the partner's events, the events read again, and
    /// the note the partner's; answers the events naming it, in the order
    /// the bloc walks them, as `id:fromPartner`.
    Future<List<String>> theirs(String partners) async {
      await db.syncDao.setValue(SyncDao.keySharedOwner, 'maria');
      await db.sharedRowDao.writing(
        () => db.customStatement(
          "UPDATE calendar_events SET owner_id = 'maria' WHERE id = ?",
          [partners],
        ),
      );
      await (await CalendarEventService.getInstance()).reload();
      await dispatch(const LoadCalendarEvents());
      NoteMoneyLedgerService.seedForTesting({
        noteId: (balance: 1000, net: 1000, title: 'Ledger', fromPartner: true),
      });
      return [
        for (final event in (bloc.state as CalendarPageLoaded).allEvents)
          if (event.noteId == noteId) '${event.id}:${event.fromPartner}',
      ];
    }

    test('mine first: the partner\'s event still counts the note', () async {
      expect(await theirs('e2'), ['e1:false', 'e2:true']);

      expect(bloc.monthNetFor(month), 1000);
    });

    test('the partner\'s first: mine adds nothing', () async {
      expect(await theirs('e1'), ['e1:true', 'e2:false']);

      expect(bloc.monthNetFor(month), 1000);
    });
  });

  test('serves the memoized value while nothing changed', () async {
    expect(bloc.monthNetFor(month), 1000);

    // A day selection changes neither the event set nor the ledger, so the
    // cached entry must survive it — that is the whole point of the memo.
    // `_onCreateEvent` already selected `startDate`, so pick another day or
    // the emit is value-equal and never arrives.
    final other = DateTime.utc(2026, 8, 20);
    await dispatch(
      SelectCalendarDay(
        day: other,
        focusedDay: other,
        source: CalendarSelectionSource.grid,
      ),
    );

    expect(bloc.monthNetFor(month), 1000);
  });

  test('recomputes after the event set changes', () async {
    expect(bloc.monthNetFor(month), 1000);

    await dispatch(const DeleteCalendarEvent(eventId: 'e1'));

    expect(bloc.monthNetFor(month), 0);
  });

  test('recomputes when the ledger changes under it', () async {
    expect(bloc.monthNetFor(month), 1000);

    // Rewrites the note's amounts without touching the calendar at all —
    // the exact path that bypasses every cache-invalidating handler.
    await repository.updateNote(id: noteId, content: r'$+ 25.00 protein');
    await ledger.refresh([
      ...(await CalendarEventService.getInstance()).events,
    ]);

    expect(bloc.monthNetFor(month), 2500);
  });

  test('excludes events whose category is hidden', () async {
    expect(bloc.monthNetFor(month), 1000);

    await dispatch(
      const ChangeCalendarFilters(
        filters: CalendarGridFilters(hiddenCategoryIds: {'gym'}),
      ),
    );

    expect(bloc.monthNetFor(month), 0);
  });

  /// The header total is the sum of what the cells show, and the money layer
  /// removes the cells' money bar — so it has to remove the total too.
  test('the money layer takes the header total with it', () async {
    expect(bloc.monthNetFor(month), 1000);

    await dispatch(
      const ChangeCalendarFilters(
        filters: CalendarGridFilters(showMoney: false),
      ),
    );

    expect(bloc.monthNetFor(month), 0);

    await dispatch(const ChangeCalendarFilters(filters: CalendarGridFilters()));

    expect(bloc.monthNetFor(month), 1000);
  });
}
