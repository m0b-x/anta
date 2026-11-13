import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_digest_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/app_sync_apply_hooks.dart';
import 'package:anta/services/sync/sync_binding_service.dart';

import '../../database/support/db_test_support.dart';

/// Arms everything and remembers what it was asked to cancel.
class _RecordingGateway extends NoOpAlertGateway {
  final List<int> cancelled = [];

  @override
  Future<void> cancel(int osId) async => cancelled.add(osId);
}

/// D31 (`docs/cloud-share-surfaces-roadmap.md` §16.2): what leaves this
/// phone takes its armed alerts off the platform at once — "Stop syncing"
/// too, where no sync run follows to do it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late _RecordingGateway gateway;
  late CalendarEventService events;
  late SettingsService settings;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_shared_leave');
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

  void resetSingletons() {
    AlertScheduler.reset();
    CalendarEventService.reset();
    EventAlertService.reset();
    EventSkipService.reset();
    EventOccurrenceService.reset();
    EventPresenceService.reset();
    CategoryService.reset();
    EventDigestService.reset();
    PublicHolidayService.reset();
    SettingsService.reset();
    SyncBindingService.reset();
    SyncBindingService.onSharedRowsRemoved = null;
  }

  setUp(() async {
    resetSingletons();
    db = await openTestDatabase();
    gateway = _RecordingGateway();
    settings = SettingsService.forTesting(db);
    events = await CalendarEventService.forTesting(db);
    await EventAlertService.forTesting(db);
    await EventSkipService.forTesting(db);
    await EventOccurrenceService.forTesting(db);
    await EventPresenceService.forTesting(db);
    await CategoryService.forTesting(db);
    await EventDigestService.forTesting(db);
    AlertScheduler.forTesting(
      db: db,
      gateway: gateway,
      databaseName: 'gym_notes',
      clock: () => DateTime(2026, 9, 15, 12),
    );
  });

  tearDown(() async {
    resetSingletons();
    await db.close();
  });

  CalendarEvent eventOf(String id) => CalendarEvent(
    id: id,
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 9, 20),
    rule: const OneTimeRecurrence(),
    time: const EventTime(startMinute: 18 * 60),
  );

  /// A bound database holding the partner's event `theirs` and my own
  /// `mine`, an alert of mine armed on each.
  Future<List<int>> seedArmed() async {
    await settings.setSyncBinding(
      const SyncBinding(
        spaceId: 'space-1',
        ownerUid: 'me',
        accountUid: 'me',
      ),
    );
    final alerts = await EventAlertService.getInstance();
    for (final id in ['theirs', 'mine']) {
      await events.upsert(eventOf(id));
      await alerts.replaceForEvent(id, [
        EventAlert(
          id: 'a-$id',
          eventId: id,
          mode: AlertMode.ring,
          offsetMinutes: 0,
        ),
      ]);
    }
    await db.customStatement(
      "UPDATE calendar_events SET owner_id = 'partner' WHERE id = 'theirs'",
    );
    await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');
    await events.reload();
    await (await AlertScheduler.getInstance()).reconcileAll(
      AlertReconcileReason.launch,
    );
    final armed = [
      for (final row in await db.alertRegistrationDao.pending())
        if (row.eventId == 'theirs') row.osId,
    ];
    expect(armed, isNotEmpty);
    return armed;
  }

  test('"Stop syncing" cancels what was armed on the partner\'s event and '
      'drops it from the calendar\'s cache, with no run after it', () async {
    final armed = await seedArmed();
    // What DI sets: the one call the unbind makes above itself.
    SyncBindingService.onSharedRowsRemoved =
        AppSyncApplyHooks.afterSharedRowsRemoved;

    await SyncBindingService.forTesting(db, settings).unbind();

    expect(gateway.cancelled, unorderedEquals(armed));
    expect(events.events.map((event) => event.id), ['mine']);
    expect(
      {for (final row in await db.alertRegistrationDao.pending()) row.eventId},
      {'mine'},
    );
  });

  test('an unbind of a database that holds nothing of the partner\'s runs '
      'no pass of its own', () async {
    await settings.setSyncBinding(
      const SyncBinding(
        spaceId: 'space-1',
        ownerUid: 'me',
        accountUid: 'me',
      ),
    );
    var told = 0;
    SyncBindingService.onSharedRowsRemoved = () async => told++;

    await SyncBindingService.forTesting(db, settings).unbind();

    expect(told, 0);
  });
}
