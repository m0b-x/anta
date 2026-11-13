import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_profile_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_digest_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/sync/app_sync_apply_hooks.dart';
import 'package:anta/services/sync/sync_apply_hooks.dart';
import 'package:anta/services/sync/sync_table_binding.dart';

import '../../database/support/db_test_support.dart';

void _resetCalendar() {
  CalendarEventService.reset();
  CategoryService.reset();
  CategoryProfileService.reset();
  EventOccurrenceService.reset();
  EventPresenceService.reset();
  EventSkipService.reset();
  EventAlertService.reset();
  EventDigestService.reset();
}

/// What a pull costs the calendar once the hooks know the run's tables
/// (scalability record §5.6, S14): the services whose tables merged reload,
/// categories always, a pulled event is one keyed read, and a remote mark
/// re-plans the alerts only under an enabled report digest. Every service is
/// live over one counted database, as it is while the calendar is open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StatementCounter counter;
  late AppDatabase db;
  late CalendarEventService events;
  late List<String> calls;
  late AppSyncApplyHooks hooks;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_hooks_scope');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    _resetCalendar();
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
    await CategoryService.forTesting(db);
    await CategoryProfileService.forTesting(db);
    await EventOccurrenceService.forTesting(db);
    await EventPresenceService.forTesting(db);
    await EventSkipService.forTesting(db);
    await EventAlertService.forTesting(db);
    await EventDigestService.forTesting(db);
    events = await CalendarEventService.forTesting(db);
    await events.upsert(
      CalendarEvent(
        id: 'gym',
        title: 'Gym',
        categoryId: 'gym',
        startDate: DateTime.utc(2026, 11, 2),
      ),
    );
    calls = [];
    hooks = AppSyncApplyHooks(
      reconcileAlerts: () async => calls.add('reconcile'),
      strings: () async => lookupAppLocalizations(const Locale('en')),
      now: () => DateTime(2026, 11, 8, 9),
    );
  });

  tearDown(() async {
    _resetCalendar();
    await db.close();
  });

  SyncAppliedRow applied(String key) => SyncAppliedRow(
    rowKey: key,
    result: MergeResult.applied,
    tombstone: false,
  );

  /// A run the way the puller announces it: the page, then the run.
  Future<void> pull(String table, List<SyncAppliedRow> rows) async {
    await hooks.beforePage(table);
    await hooks.afterPage(table, rows);
    await hooks.afterRun({SyncInvalidation.calendar, SyncInvalidation.alerts});
  }

  List<String> selectsOn(String table) => [
    for (final s in counter.selects)
      if (RegExp('"$table"').hasMatch(s.sql)) s.sql,
  ];

  group('a remote presence mark', () {
    Future<void> markRemotely() async {
      final day = DateTime.utc(2026, 11, 2);
      await db.eventAbsenceDao.setStatus('gym', day, PresenceStatus.missed);
      counter.reset();
      await pull('calendar_event_absences', [
        applied(dayEnvelopeKey('gym', day)),
      ]);
    }

    test('reloads the presence facade and categories, reads no event and '
        're-plans nothing while no report digest is on', () async {
      await markRemotely();

      expect(EventPresence.marksFor('gym'), {
        DateTime.utc(2026, 11, 2): PresenceStatus.missed,
      });
      expect(selectsOn('calendar_events'), isEmpty);
      expect(selectsOn('calendar_event_absences'), hasLength(1));
      for (final untouched in [
        'calendar_event_occurrences',
        'calendar_event_skips',
        'calendar_event_alerts',
        'calendar_category_alerts',
        'event_digests',
        'calendar_category_profiles',
      ]) {
        expect(selectsOn(untouched), isEmpty, reason: untouched);
      }
      // The categories' reload is three reads (the bind check, the built-in
      // seed check, the list); the presence table is the fourth.
      expect(
        counter.selects,
        hasLength(4),
        reason:
            'the presence table and the categories, nothing else:\n'
            '${counter.statements.join('\n')}',
      );
      expect(calls, isEmpty);
    });

    test('re-plans the alerts when a report digest is on', () async {
      await (await EventDigestService.forTesting(db)).create(
        const EventDigest(id: 'monthly', cadence: DigestCadence.monthlyReport),
      );

      await markRemotely();

      expect(calls, ['reconcile']);
    });
  });

  test('a pulled event is one keyed read of the event table, patched into '
      'the cache and announced as current', () async {
    final now = DateTime.now();
    await db.calendarEventDao.upsert(
      CalendarEventsCompanion.insert(
        id: 'pulled',
        title: 'Pulled',
        category: 'gym',
        startDate: DateTime.utc(2026, 11, 1),
        ruleKind: 'oneTime',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final heard = <CalendarExternalChange>[];
    final subscription = CalendarEventService.externalChanges.listen(heard.add);
    addTearDown(subscription.cancel);
    counter.reset();

    await pull('calendar_events', [applied('pulled')]);
    await pumpEventQueue();

    final reads = selectsOn('calendar_events');
    expect(reads, hasLength(1));
    expect(reads.single, contains(' IN '));
    expect([for (final e in events.events) e.id], ['pulled', 'gym']);
    expect(heard.single.cacheCurrent, isTrue);
    expect(calls, ['reconcile']);
  });

  test('a run whose shared read took a category out of the hidden set reads '
      'the events whole, not only the ids its pages named', () async {
    final now = DateTime.now();
    await db.calendarEventDao.upsert(
      CalendarEventsCompanion.insert(
        id: 'pulled',
        title: 'Pulled',
        category: 'gym',
        startDate: DateTime.utc(2026, 11, 1),
        ruleKind: 'oneTime',
        createdAt: now,
        updatedAt: now,
      ),
    );
    counter.reset();

    await hooks.beforePage('calendar_events');
    await hooks.afterPage('calendar_events', [applied('pulled')]);
    await hooks.afterRun({
      SyncInvalidation.calendar,
      SyncInvalidation.alerts,
      SyncInvalidation.unhidden,
    });

    final reads = selectsOn('calendar_events');
    expect(reads, hasLength(1));
    expect(reads.single, isNot(contains(' IN ')));
    expect([for (final e in events.events) e.id], ['pulled', 'gym']);
  });

  test('a pull whose tables were never heard reloads every service, as '
      'before', () async {
    counter.reset();

    await hooks.afterRun({SyncInvalidation.calendar, SyncInvalidation.alerts});

    expect(selectsOn('calendar_events'), hasLength(1));
    expect(selectsOn('calendar_event_absences'), hasLength(1));
    // Every live service's whole table, once — eleven reads: no row names an
    // owner, so the events never ask whose rows are a partner's; the
    // templates, presets and views are not live here, so none is built to
    // be read.
    expect(
      counter.selects,
      hasLength(11),
      reason: counter.statements.join('\n'),
    );
    expect(calls, ['reconcile']);
  });

  test('the tables heard are spent by the run: the next run starts '
      'empty', () async {
    await pull('calendar_event_absences', [
      applied(dayEnvelopeKey('gym', DateTime.utc(2026, 11, 2))),
    ]);
    counter.reset();

    await hooks.afterRun({SyncInvalidation.calendar, SyncInvalidation.alerts});

    expect(selectsOn('calendar_events'), hasLength(1));
  });

  test('a page announced after the run was told belongs to no run: the '
      'next mark still skips the re-plan', () async {
    // The puller's re-filed notes come after `afterRun`, with no
    // `beforePage` of their own.
    await pull('calendar_event_absences', [
      applied(dayEnvelopeKey('gym', DateTime.utc(2026, 11, 2))),
    ]);
    await hooks.afterPage('notes', [applied('stranded')]);
    calls.clear();

    await pull('calendar_event_absences', [
      applied(dayEnvelopeKey('gym', DateTime.utc(2026, 11, 3))),
    ]);

    expect(calls, isEmpty);
  });

  test('a run that changed nothing is never told, and the re-filed notes '
      'after it still widen no run', () async {
    // The puller skips `afterRun` when no page changed a row.
    await hooks.beforePage('calendar_event_absences');
    await hooks.afterPage('calendar_event_absences', const [
      SyncAppliedRow(
        rowKey: 'gym|0',
        result: MergeResult.keptLocal,
        tombstone: false,
      ),
    ]);
    await hooks.afterPage('notes', [applied('stranded')]);

    await pull('calendar_event_absences', [
      applied(dayEnvelopeKey('gym', DateTime.utc(2026, 11, 3))),
    ]);

    expect(calls, isEmpty);
  });

  test('a profile-only pull re-plans nothing while no report digest is '
      'on', () async {
    await pull('calendar_category_profiles', [applied('gym')]);

    expect(calls, isEmpty);
  });

  test('a page whose rows all came out unchanged adds no table', () async {
    counter.reset();

    await pull('calendar_events', const [
      SyncAppliedRow(
        rowKey: 'gym',
        result: MergeResult.unchanged,
        tombstone: false,
      ),
    ]);

    // No table heard: the run reloads whole, as an unknown run does.
    expect(selectsOn('calendar_events'), hasLength(1));
    expect(selectsOn('calendar_events').single, isNot(contains(' IN ')));
  });

  test('a table outside both known sets reloads the calendar whole', () async {
    counter.reset();

    await hooks.beforePage('some_new_table');
    await hooks.afterPage('some_new_table', [applied('x')]);
    await hooks.beforePage('calendar_event_absences');
    await hooks.afterPage('calendar_event_absences', [
      applied(dayEnvelopeKey('gym', DateTime.utc(2026, 11, 2))),
    ]);
    await hooks.afterRun({SyncInvalidation.calendar, SyncInvalidation.alerts});

    expect(selectsOn('calendar_events'), hasLength(1));
    expect(selectsOn('calendar_event_skips'), hasLength(1));
    expect(calls, ['reconcile']);
  });
}
