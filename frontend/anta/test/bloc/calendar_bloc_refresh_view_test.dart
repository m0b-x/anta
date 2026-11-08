import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/note_money_ledger_service.dart';

import '../database/support/db_test_support.dart';

/// The bloc trusting a cache it is told is current (scalability record §5.6,
/// S14): a page return re-emits the service's cache with no read, a change
/// announced `cacheCurrent` rebuilds from it, and everything else — an
/// un-flagged change, a revision it did not see, a cache whose last read
/// failed — still reads the store.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late _FailingCounter counter;
  late CalendarEventService service;
  late CalendarBloc bloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_refresh_view');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<CalendarPageLoaded> next(void Function() act) async {
    final emitted = bloc.stream.first.timeout(const Duration(seconds: 30));
    act();
    return await emitted as CalendarPageLoaded;
  }

  setUp(() async {
    CalendarEventService.reset();
    counter = _FailingCounter();
    db = await openTestDatabase(interceptor: counter);
    service = await CalendarEventService.forTesting(db);
    await service.upsert(
      CalendarEvent(
        id: 'gym',
        title: 'Gym',
        categoryId: 'gym',
        startDate: DateTime.utc(2026, 11, 2),
      ),
    );
    bloc = CalendarBloc(service: service);
    await next(() => bloc.add(const LoadCalendarEvents()));
  });

  tearDown(() async {
    await bloc.close();
    CalendarEventService.reset();
    await db.close();
  });

  List<String> eventReads() => counter.matching('"calendar_events"');

  test('RefreshCalendarView re-emits the cache as a fresh list with both '
      'revisions bumped, and reads nothing', () async {
    final before = bloc.state as CalendarPageLoaded;
    counter.reset();

    final after = await next(() => bloc.add(const RefreshCalendarView()));

    expect(identical(after.allEvents, before.allEvents), isFalse);
    expect(after.allEvents, before.allEvents);
    expect(after.membershipRevision, before.membershipRevision + 1);
    expect(after.occurrenceRevision, before.occurrenceRevision + 1);
    expect(counter.count, 0, reason: counter.statements.join('\n'));
  });

  test('a change announced cacheCurrent rebuilds from the cache without a '
      'read', () async {
    await service.upsert(
      CalendarEvent(
        id: 'pulled',
        title: 'Pulled',
        categoryId: 'gym',
        startDate: DateTime.utc(2026, 11, 3),
      ),
    );
    final before = bloc.state as CalendarPageLoaded;
    counter.reset();

    final after = await next(
      () => CalendarEventService.notifyExternalChange(cacheCurrent: true),
    );

    expect([for (final e in after.allEvents) e.id], ['gym', 'pulled']);
    expect(after.membershipRevision, before.membershipRevision + 1);
    expect(after.occurrenceRevision, before.occurrenceRevision + 1);
    expect(eventReads(), isEmpty);
    expect(bloc.isStale, isFalse);
  });

  test('an un-flagged change still reads the store', () async {
    counter.reset();

    await next(CalendarEventService.notifyExternalChange);

    expect(eventReads(), hasLength(1));
  });

  test('a revision the bloc did not see makes a flagged change read', () async {
    // What a restore's import bumps without a signal of its own.
    CalendarEventService.externalRevision++;
    counter.reset();

    await next(
      () => CalendarEventService.notifyExternalChange(cacheCurrent: true),
    );

    expect(eventReads(), hasLength(1));
  });

  test('a cache whose last read failed is read again, never trusted', () async {
    counter.failNext('ORDER BY "start_date"');
    expect(await service.reload(), isFalse);
    expect(service.events, isNotEmpty, reason: 'the cache was kept');
    counter.reset();

    await next(
      () => CalendarEventService.notifyExternalChange(cacheCurrent: true),
    );
    expect(eventReads(), hasLength(1));
    expect(service.lastLoadFailed, isFalse);

    counter.failNext('ORDER BY "start_date"');
    expect(await service.reload(), isFalse);
    counter.reset();
    await next(() => bloc.add(const RefreshCalendarView()));
    expect(eventReads(), hasLength(1), reason: 'the refresh loads instead');
  });

  test('a refresh after the store was replaced loads', () async {
    // What a restore or a switch leaves: a revision this bloc never saw.
    CalendarEventService.externalRevision++;
    expect(bloc.isStale, isTrue);
    counter.reset();

    await next(() => bloc.add(const RefreshCalendarView()));

    expect(eventReads(), hasLength(1));
    expect(bloc.isStale, isFalse);
  });

  /// The ledger over a repository on the counted database; its refresh
  /// bumps the revision whether or not any event links a note.
  Future<NoteMoneyLedgerService> ledgerOverRepository() async {
    NoteMoneyLedgerService.reset();
    GetIt.I.registerSingleton<NoteRepository>(NoteRepository(database: db));
    addTearDown(() async {
      NoteMoneyLedgerService.reset();
      await GetIt.I.reset();
    });
    return NoteMoneyLedgerService.getInstance();
  }

  test('only a settings return refreshes the money ledger', () async {
    final ledger = await ledgerOverRepository();
    final before = ledger.revision;

    await next(() => bloc.add(const RefreshCalendarView()));
    expect(ledger.revision, before);

    await next(() => bloc.add(const RefreshCalendarView(refreshLedger: true)));
    expect(ledger.revision, greaterThan(before));
  });

  test('pulled event rows refresh the money ledger on the light path, a '
      'mark does not', () async {
    final ledger = await ledgerOverRepository();
    final before = ledger.revision;

    await next(
      () => CalendarEventService.notifyExternalChange(cacheCurrent: true),
    );
    expect(ledger.revision, before);

    counter.reset();
    await next(
      () => CalendarEventService.notifyExternalChange(
        cacheCurrent: true,
        eventsMerged: true,
      ),
    );
    expect(ledger.revision, greaterThan(before));
    expect(eventReads(), isEmpty);
  });

  test('a refresh before the first load emitted makes that load read '
      'again', () async {
    await bloc.close();
    final seed = Completer<CalendarEventService>();
    bloc = CalendarBloc(service: seed.future);
    counter.reset();

    bloc.add(const LoadCalendarEvents());
    bloc.add(const RefreshCalendarView());
    await pumpEventQueue();
    final loaded = bloc.stream.first.timeout(const Duration(seconds: 30));
    seed.complete(service);
    await loaded;

    // The seed was built with its read: without the refresh the first load
    // reads nothing more; with it, once.
    expect(eventReads(), hasLength(1));
  });
}

/// [StatementCounter] that can fail the next read whose SQL holds a fragment.
class _FailingCounter extends StatementCounter {
  String? _failing;

  void failNext(String fragment) => _failing = fragment;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    final failing = _failing;
    if (failing != null && statement.contains(failing)) {
      _failing = null;
      throw StateError('read failed on purpose');
    }
    return super.runSelect(executor, statement, args);
  }
}
