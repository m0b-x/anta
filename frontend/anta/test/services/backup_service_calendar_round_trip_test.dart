import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_palette.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/models/event_template.dart';
import 'package:anta/models/fasting_schedule.dart';
import 'package:anta/models/overview_list_options.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_digest_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/event_template_service.dart';
import 'package:anta/services/overview_view_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';

/// Drives the exact code path onboarding takes to restore a backup —
/// `BackupService.getInstance()` then `importFromJson()` — over a database
/// seeded with one of every calendar entity.
///
/// This is the regression guard for the crash class Phase 2.1 nearly shipped:
/// nineteen call sites across `BackupService` used to resolve the seven
/// calendar services **synchronously from GetIt**, which is reachable from
/// onboarding without ever opening the calendar. Removing those registrations
/// without migrating every site would throw `StateError: not registered` — and
/// `importFromJson` swallows that into `ImportResult(success: false)`, so the
/// failure is a silent snackbar rather than a crash a manual click-through
/// would necessarily notice.
///
/// There is no "v7 backup" fixture to import — v7 is simply the format the app
/// writes today, so exporting fresh data and re-importing it exercises the same
/// services, in the same order, that consuming an old file would.
///
/// **The wipe between export and import is what makes this a round-trip test
/// rather than a smoke test.** Importing back into the database it was exported
/// from, while the services still hold the caches seeding populated, means
/// every assertion passes whether or not the import did anything — verified by
/// renaming the `calendarEvents` key so its branch never runs, which left the
/// earlier version of this test green. Clearing the tables *and* resetting the
/// singletons first means a skipped import branch leaves the data missing, and
/// makes the `getInstance()` calls inside `importFromJson` genuinely construct
/// their services, exactly as they do on a fresh install.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_backup_roundtrip');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    // CounterService is the one service `BackupService` still resolves from
    // GetIt, so it stays registered here exactly as production does.
    GetIt.I.registerSingleton<CounterService>(
      await CounterService.getInstance(),
    );
  });

  tearDownAll(() async {
    await GetIt.I.reset();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('export then import round-trips one of every calendar entity', () async {
    final db = await AppDatabase.getInstance();
    await db.folderDao.createFolder(name: 'Errands');
    final categories = await CategoryService.getInstance();
    final categoryId = categories.categories.first.id;
    // A custom category carrying every field the archive has to preserve, and
    // archived on top of it — `is_hidden` is the newest column here (v33) and
    // the one nothing but this path exercises end to end.
    final archived = await categories.create(
      name: 'Retired',
      colorValue: 0xFF123456,
      iconKey: 'savings',
    );
    await categories.setHidden(archived.id, true);

    final missedDay = DateTime.utc(2026, 8, 3);
    final skippedDay = DateTime.utc(2026, 8, 10);
    final holidayDay = DateTime.utc(2026, 8, 15);
    // v37: the event is flipped to assume-absent from the 17th, so the three
    // Mondays around that boundary each restore for a different reason — one
    // explicit miss before it, one explicit confirmation after it, and the
    // unmarked days on either side reading opposite ways.
    final absentFromDay = DateTime.utc(2026, 8, 17);
    final presentDay = DateTime.utc(2026, 8, 24);

    final events = await CalendarEventService.getInstance();
    await events.upsert(
      CalendarEvent(
        id: 'roundtrip-event',
        title: 'Standing meeting',
        categoryId: categoryId,
        startDate: DateTime.utc(2026, 8, 1),
        rule: const WeeklyRecurrence(weekdays: {DateTime.monday}),
        tracksPresence: true,
        assumeAbsent: true,
        assumeAbsentFrom: absentFromDay,
        perOccurrenceDescriptions: true,
      ),
    );
    await (await EventOccurrenceService.getInstance()).setDescription(
      'roundtrip-event',
      missedDay,
      'Standup instead',
    );
    final presence = await EventPresenceService.getInstance();
    await presence.setStatus(
      'roundtrip-event',
      missedDay,
      PresenceStatus.missed,
    );
    await presence.setStatus(
      'roundtrip-event',
      presentDay,
      PresenceStatus.present,
    );
    await (await EventSkipService.getInstance()).markSkipped(
      'roundtrip-event',
      skippedDay,
    );
    // create() mints its own id and ignores the draft's, so the name is what
    // survives to identify this template after a restore.
    await (await EventTemplateService.getInstance()).create(
      EventTemplate(
        id: 'draft',
        name: 'Dentist',
        categoryId: categoryId,
        rule: const OneTimeRecurrence(),
      ),
    );
    await (await PublicHolidayService.getInstance()).addCustom(
      holidayDay,
      'Company day',
    );
    const paletteColor = 0xFF0FF00F;
    await (await CalendarPaletteService.getInstance()).add(paletteColor);

    // The fasting schedule is hand-authored like the palette — weekdays, kept
    // months and dates typed in one by one — and nothing else in the archive
    // could rebuild it.
    final fasting = FastingSchedule(
      weekdays: const {DateTime.wednesday, DateTime.friday},
      weekdayScope: FastingWeekdayScope.allFasts,
      months: const {1, 2, 3, 11, 12},
      skipDates: {DateTime.utc(2026, 3, 4)},
      forceDates: {DateTime.utc(2026, 1, 7)},
    );
    await (await SettingsService.getInstance()).setFastingSchedule(fasting);

    final backup = await BackupService.getInstance();
    final exported = await backup.exportAllData();
    expect(exported['version'], 7);
    final json = jsonEncode(exported);

    // Everything the calendar owns, gone — then every singleton dropped so the
    // static facades go with them. What survives the import can only have come
    // from the backup.
    await db.calendarEventDao.deleteAll();
    await db.eventOccurrenceDao.deleteAll();
    await db.eventAbsenceDao.deleteAll();
    await db.eventSkipDao.deleteAll();
    await db.eventTemplateDao.deleteAll();
    await db.publicHolidayDao.deleteAll();
    await db.calendarCategoryDao.deleteAll();
    // The palette lives in user_settings, so the table wipe above cannot
    // reach it — clearing the row is what makes its assertion prove the
    // import restored it rather than that it was never gone.
    await db.userSettingsDao.setValue(SettingsKeys.calendarCustomColors, '');
    await db.userSettingsDao.setValue(SettingsKeys.calendarFastingSchedule, '');
    DatabaseLifecycle.notifyDatabaseSwitching();

    expect(
      (await CalendarEventService.getInstance()).events,
      isEmpty,
      reason:
          'the wipe must actually land, or every assertion below passes on '
          'leftovers and this stops being a round-trip test',
    );
    DatabaseLifecycle.notifyDatabaseSwitching();

    // Only CounterService is in GetIt, as in production after 2.1, and no
    // calendar singleton exists yet — so the `getInstance()` calls inside
    // importFromJson construct their services here, exactly as they do on a
    // fresh install. A site still using `GetIt.I<X>()` throws
    // `StateError: not registered` and lands in ImportResult.error.
    final result = await backup.importFromJson(json);

    expect(
      result.success,
      isTrue,
      reason:
          'A false here with no thrown exception means one of the migrated '
          'getInstance() calls failed and was swallowed. error: '
          '${result.error}',
    );

    // Categories import *before* events, and a restore that lost one would
    // leave every event on it falling through to `other` — grey, permanently,
    // with nothing to say it happened. `is_hidden` rides the same key with no
    // backup version bump, so this is the only end-to-end proof it survives.
    final restoredCategories = await CategoryService.getInstance();
    final restoredArchived = restoredCategories.categories
        .where((c) => c.id == archived.id)
        .toList();
    expect(
      restoredArchived,
      hasLength(1),
      reason: 'the custom category must come back from the archive, by id',
    );
    expect(restoredArchived.single.name, 'Retired');
    expect(restoredArchived.single.colorValue, 0xFF123456);
    expect(restoredArchived.single.iconKey, 'savings');
    expect(restoredArchived.single.sortOrder, archived.sortOrder);
    expect(
      restoredArchived.single.isHidden,
      isTrue,
      reason: 'an archived category restores archived, not visible',
    );
    expect(
      CalendarCategories.visible.map((c) => c.id),
      isNot(contains(archived.id)),
      reason: 'the facade must be republished from the restored rows',
    );
    expect(
      CalendarCategories.byId(categoryId),
      isNotNull,
      reason: 'the built-in the restored event points at must resolve',
    );

    final restoredEvents = await CalendarEventService.getInstance();
    expect(restoredEvents.events.map((e) => e.id), contains('roundtrip-event'));
    final restoredEvent = restoredEvents.events.firstWhere(
      (e) => e.id == 'roundtrip-event',
    );

    await EventOccurrenceService.getInstance();
    expect(
      OccurrenceDescriptions.descriptionFor(restoredEvent, missedDay),
      'Standup instead',
    );

    // The v37 pair rides the `calendarEvents` key with no version bump, so
    // this is the only end-to-end proof the boundary survives — and a lost
    // one silently rewrites the meaning of every day before it.
    expect(restoredEvent.assumeAbsent, isTrue);
    expect(restoredEvent.assumeAbsentFromUtc, absentFromDay);

    await EventPresenceService.getInstance();
    expect(EventPresence.isMissed(restoredEvent, missedDay), isTrue);
    // A `present` row is a statement of its own since v37: the status column
    // is what carries it, and losing it would restore this day as a miss on an
    // event whose every unmarked day already reads as one.
    expect(EventPresence.isMissed(restoredEvent, presentDay), isFalse);
    // Unmarked on either side of the boundary, answered by the event alone.
    expect(
      EventPresence.isMissed(restoredEvent, DateTime.utc(2026, 8, 31)),
      isTrue,
    );
    expect(EventPresence.isMissed(restoredEvent, skippedDay), isFalse);

    await EventSkipService.getInstance();
    expect(EventSkips.isSkipped('roundtrip-event', skippedDay), isTrue);

    expect(
      (await EventTemplateService.getInstance()).templates.map((t) => t.name),
      contains('Dentist'),
    );

    expect(
      (await PublicHolidayService.getInstance()).cache[holidayDay]?.customLabel,
      'Company day',
    );

    // The palette rides in the settings map rather than a table of its own, so
    // nothing above would notice it being dropped from the export allow-list —
    // and a lost swatch is silent: every picker just stops offering a colour
    // the user mixed.
    expect(CalendarPalette.custom, [paletteColor]);

    // Same silence as the palette, one row over: a restore to a new install
    // that loses the schedule starts marking days the user had turned off.
    expect(
      await (await SettingsService.getInstance()).getFastingSchedule(),
      fasting,
    );
  });

  test('an archive written before v37 restores the old reading', () async {
    // Version 7 covers both, so there is no fixture to import and no flag to
    // branch on: a pre-v37 archive is simply this one with three keys absent,
    // which is exactly what the import's `Value.absent()` fallbacks and
    // `PresenceStatus.fromName(null)` are for. Stripping them from a real
    // export is the closest thing to the file an older build would have
    // written.
    final db = await AppDatabase.getInstance();
    await db.calendarEventDao.deleteAll();
    await db.eventAbsenceDao.deleteAll();
    DatabaseLifecycle.notifyDatabaseSwitching();

    final markedDay = DateTime.utc(2026, 8, 24);
    await (await CalendarEventService.getInstance()).upsert(
      CalendarEvent(
        id: 'legacy-event',
        title: 'Standing meeting',
        categoryId: 'other',
        startDate: DateTime.utc(2026, 8, 1),
        rule: const WeeklyRecurrence(weekdays: {DateTime.monday}),
        tracksPresence: true,
        assumeAbsent: true,
        assumeAbsentFrom: DateTime.utc(2026, 8, 17),
      ),
    );
    await (await EventPresenceService.getInstance()).setStatus(
      'legacy-event',
      markedDay,
      PresenceStatus.present,
    );

    final backup = await BackupService.getInstance();
    final exported = await backup.exportAllData();
    for (final raw in exported['calendarEvents'] as List) {
      (raw as Map)
        ..remove('assumeAbsent')
        ..remove('assumeAbsentFromMs');
    }
    for (final raw in exported['eventAbsences'] as List) {
      (raw as Map).remove('status');
    }
    final json = jsonEncode(exported);

    await db.calendarEventDao.deleteAll();
    await db.eventAbsenceDao.deleteAll();
    DatabaseLifecycle.notifyDatabaseSwitching();

    final result = await backup.importFromJson(json);
    expect(result.success, isTrue, reason: 'error: ${result.error}');

    final restored = (await CalendarEventService.getInstance()).events
        .firstWhere((e) => e.id == 'legacy-event');
    expect(restored.assumeAbsent, isFalse);
    expect(restored.assumeAbsentFrom, isNull);

    await EventPresenceService.getInstance();
    // A live row in a pre-v37 archive could only ever mean one thing, and
    // reading it as anything else would invent confirmations no one made.
    expect(EventPresence.isMissed(restored, markedDay), isTrue);
    expect(
      EventPresence.isMissed(restored, DateTime.utc(2026, 8, 31)),
      isFalse,
      reason: 'an unmarked day of a pre-v37 event was attended by default',
    );
  });

  group('event alerts (v40)', () {
    late AppDatabase db;
    late BackupService backup;

    /// One alerted event, exported, then wiped along with every singleton that
    /// caches it — so anything asserted afterwards can only have come from the
    /// archive.
    Future<String> seedAndExport() async {
      db = await AppDatabase.getInstance();
      await db.calendarEventDao.deleteAll();
      await db.eventAlertDao.deleteAll();
      DatabaseLifecycle.notifyDatabaseSwitching();

      await (await CalendarEventService.getInstance()).upsert(
        CalendarEvent(
          id: 'alerted-event',
          title: 'Bench',
          categoryId: 'other',
          startDate: DateTime.utc(2026, 8, 1),
          rule: const OneTimeRecurrence(),
          time: const EventTime(startMinute: 18 * 60),
          removeAfterAlert: true,
        ),
      );
      await (await EventAlertService.getInstance()).replaceForEvent(
        'alerted-event',
        const [
          EventAlert(
            id: 'alert-1',
            eventId: 'alerted-event',
            mode: AlertMode.ring,
            offsetMinutes: 15,
            sound: 'chime',
          ),
          EventAlert(
            id: 'alert-2',
            eventId: 'alerted-event',
            daysBefore: 1,
            dayMinute: 1200,
            enabled: false,
          ),
        ],
      );

      backup = await BackupService.getInstance();
      final exported = await backup.exportAllData();
      expect(
        exported['version'],
        7,
        reason: 'alerts are additive; the format version must not move',
      );
      expect(
        exported.keys,
        isNot(contains('alertRegistrations')),
        reason: 'registrations mirror one phone\'s OS scheduler and are never '
            'carried to another device',
      );
      return jsonEncode(exported);
    }

    Future<void> wipe() async {
      await db.calendarEventDao.deleteAll();
      await db.eventAlertDao.deleteAll();
      DatabaseLifecycle.notifyDatabaseSwitching();
      // Reconstructing the service here republishes from the emptied table,
      // which is what proves the wipe landed — without it every assertion
      // below would pass on leftovers.
      await EventAlertService.getInstance();
      expect(
        EventAlerts.alertsFor('alerted-event'),
        isEmpty,
        reason: 'the wipe must land or the assertions below prove nothing',
      );
      DatabaseLifecycle.notifyDatabaseSwitching();
    }

    test('alerts and the removal flag round-trip', () async {
      final json = await seedAndExport();
      await wipe();

      final result = await backup.importFromJson(json);
      expect(result.success, isTrue, reason: 'error: ${result.error}');

      await EventAlertService.getInstance();
      final restored = EventAlerts.alertsFor('alerted-event');
      expect(restored, hasLength(2));
      final alarm = restored.firstWhere((a) => a.id == 'alert-1');
      expect(alarm.mode, AlertMode.ring);
      expect(alarm.offsetMinutes, 15);
      expect(alarm.sound, 'chime');
      // Both offset sets ride the archive, so an event flipped to all-day
      // after a restore still finds an alert that means something.
      final reminder = restored.firstWhere((a) => a.id == 'alert-2');
      expect(reminder.daysBefore, 1);
      expect(reminder.dayMinute, 1200);
      expect(
        reminder.enabled,
        isFalse,
        reason: 'a disabled alert is kept data, not absent data',
      );

      // The flag rides `calendarEvents` as an additive key, so nothing else
      // proves it survives a real export.
      final event = (await CalendarEventService.getInstance()).events
          .firstWhere((e) => e.id == 'alerted-event');
      expect(event.removeAfterAlert, isTrue);
    });

    test('an archive with events but no alerts clears the table', () async {
      final json = await seedAndExport();
      final stripped = jsonDecode(json) as Map<String, dynamic>
        ..remove('eventAlerts');

      // Not a wipe first: the alerts are still there, which is the whole
      // point. The event import wipes and reinserts the id space, so an alert
      // left behind would not draw a stale badge — it would ring for whatever
      // event later takes that id.
      final result = await backup.importFromJson(jsonEncode(stripped));
      expect(result.success, isTrue, reason: 'error: ${result.error}');

      await EventAlertService.getInstance();
      expect(EventAlerts.alertsFor('alerted-event'), isEmpty);
      expect(await db.select(db.eventAlerts).get(), isEmpty);
    });

    test('a pre-v40 archive imports cleanly', () async {
      final json = await seedAndExport();
      final legacy = jsonDecode(json) as Map<String, dynamic>
        ..remove('eventAlerts');
      for (final raw in legacy['calendarEvents'] as List) {
        (raw as Map).remove('removeAfterAlert');
      }
      await wipe();

      final result = await backup.importFromJson(jsonEncode(legacy));

      expect(result.success, isTrue, reason: 'error: ${result.error}');
      await EventAlertService.getInstance();
      expect(EventAlerts.alertsFor('alerted-event'), isEmpty);
      final event = (await CalendarEventService.getInstance()).events
          .firstWhere((e) => e.id == 'alerted-event');
      expect(
        event.removeAfterAlert,
        isFalse,
        reason: 'an install that could not set an alarm could not have asked '
            'to be deleted by one',
      );
    });
  });

  group('overview views (v41)', () {
    late AppDatabase db;
    late BackupService backup;
    final q1 = OverviewCustomPeriod(
      DateTime.utc(2026, 1, 1),
      DateTime.utc(2026, 3, 31),
    );

    Future<Map<String, dynamic>> seedAndExport() async {
      db = await AppDatabase.getInstance();
      await db.overviewViewDao.deleteAll();
      DatabaseLifecycle.notifyDatabaseSwitching();
      await (await OverviewViewService.getInstance()).create(
        name: 'Q1 gym',
        period: q1,
        options: const OverviewListOptions(rows: OverviewRows.perEvent),
        categoryIds: const {'gym'},
      );
      backup = await BackupService.getInstance();
      final exported = await backup.exportAllData();
      expect(
        exported['version'],
        7,
        reason: 'views are additive; the format version must not move',
      );
      return jsonDecode(jsonEncode(exported)) as Map<String, dynamic>;
    }

    test('views round-trip under their own key', () async {
      final exported = await seedAndExport();
      expect(exported['overviewViews'], hasLength(1));
      await db.overviewViewDao.deleteAll();
      DatabaseLifecycle.notifyDatabaseSwitching();

      final result = await backup.importFromJson(jsonEncode(exported));
      expect(result.success, isTrue, reason: 'error: ${result.error}');

      final view = (await OverviewViewService.getInstance()).views.single;
      expect(view.name, 'Q1 gym');
      expect(view.period, q1);
      expect(view.options.rows, OverviewRows.perEvent);
      expect(view.categoryIds, {'gym'});
    });

    test('an archive without the key leaves existing views alone', () async {
      final exported = await seedAndExport()
        ..remove('overviewViews');

      final result = await backup.importFromJson(jsonEncode(exported));
      expect(result.success, isTrue, reason: 'error: ${result.error}');

      DatabaseLifecycle.notifyDatabaseSwitching();
      expect(
        (await OverviewViewService.getInstance()).views.map((v) => v.name),
        ['Q1 gym'],
      );
    });
  });

  group('category alerts and digests (v42)', () {
    late AppDatabase db;
    late BackupService backup;

    const dayBefore = CategoryAlert(
      id: 'cat-alert-1',
      categoryId: kBirthdayCategoryId,
      daysBefore: 1,
      dayMinute: 1200,
      sound: 'chime',
    );

    /// A birthday that opted out of its category's alerts, the category's
    /// alert, an own alert, a template and a digest — exported, then the v42
    /// rows wiped along with every singleton that caches them.
    Future<Map<String, dynamic>> seedAndExport() async {
      db = await AppDatabase.getInstance();
      await db.calendarEventDao.deleteAll();
      await db.eventAlertDao.deleteAll();
      await db.categoryAlertDao.deleteAll();
      await db.eventDigestDao.deleteAll();
      await db.delete(db.eventTemplates).go();
      DatabaseLifecycle.notifyDatabaseSwitching();

      await (await CalendarEventService.getInstance()).upsert(
        CalendarEvent(
          id: 'opted-out',
          title: 'Ana',
          categoryId: kBirthdayCategoryId,
          startDate: DateTime.utc(2026, 10, 4),
          rule: const OneTimeRecurrence(),
          categoryAlerts: false,
        ),
      );
      final alerts = await EventAlertService.getInstance();
      await alerts.replaceForCategory(kBirthdayCategoryId, const [dayBefore]);
      await alerts.replaceForEvent('opted-out', const [
        EventAlert(id: 'own-1', eventId: 'opted-out', daysBefore: 2),
      ]);
      await (await EventTemplateService.getInstance()).create(
        EventTemplate(
          id: 'draft',
          name: 'Party',
          categoryId: kBirthdayCategoryId,
          rule: const OneTimeRecurrence(),
        ),
      );
      await (await EventDigestService.getInstance()).create(
        const EventDigest(
          id: 'draft',
          name: 'Birthdays',
          cadence: DigestCadence.monthly,
          anchor: 25,
          leadDays: 1,
          categoryIds: {kBirthdayCategoryId},
        ),
      );

      backup = await BackupService.getInstance();
      final exported = await backup.exportAllData();
      expect(
        exported['version'],
        7,
        reason: 'both keys are additive; the format version must not move',
      );
      return jsonDecode(jsonEncode(exported)) as Map<String, dynamic>;
    }

    Future<void> wipe() async {
      await db.categoryAlertDao.deleteAll();
      await db.eventDigestDao.deleteAll();
      DatabaseLifecycle.notifyDatabaseSwitching();
      await EventAlertService.getInstance();
      expect(
        EventAlerts.categoryAlertsFor(kBirthdayCategoryId),
        isEmpty,
        reason: 'the wipe must land or the assertions below prove nothing',
      );
      expect((await EventDigestService.getInstance()).digests, isEmpty);
      DatabaseLifecycle.notifyDatabaseSwitching();
    }

    test('both keys round-trip, and the opt-out rides the event', () async {
      final exported = await seedAndExport();
      expect(exported['categoryAlerts'], hasLength(1));
      expect(exported['eventDigests'], hasLength(1));
      await wipe();

      final result = await backup.importFromJson(jsonEncode(exported));
      expect(result.success, isTrue, reason: 'error: ${result.error}');

      await EventAlertService.getInstance();
      expect(EventAlerts.categoryAlertsFor(kBirthdayCategoryId), [dayBefore]);
      final digest = (await EventDigestService.getInstance()).digests.single;
      expect(digest.name, 'Birthdays');
      expect(digest.anchor, 25);
      expect(digest.leadDays, 1);
      expect(digest.categoryIds, {kBirthdayCategoryId});
      final event = (await CalendarEventService.getInstance()).events.single;
      expect(event.categoryAlerts, isFalse);
      expect(
        EventAlerts.effectiveFor(event).map((a) => a.id),
        ['own-1'],
        reason: 'the restored opt-out still drops the inherited alert',
      );
    });

    test(
      'an archive with categories and no categoryAlerts clears the table',
      () async {
        final exported = await seedAndExport()
          ..remove('categoryAlerts');
        expect(exported['calendarCategories'], isNotEmpty);

        // Not a wipe first: the alerts are still there, which is the point.
        // The categories import replaces the id space, so a kept alert would
        // orphan on an old custom id or quietly ring for restored events.
        final result = await backup.importFromJson(jsonEncode(exported));
        expect(result.success, isTrue, reason: 'error: ${result.error}');

        await EventAlertService.getInstance();
        expect(EventAlerts.categoryAlertsFor(kBirthdayCategoryId), isEmpty);
        expect(await db.select(db.calendarCategoryAlerts).get(), isEmpty);
      },
    );

    test('an archive with neither key leaves the digests alone', () async {
      final exported = await seedAndExport()
        ..remove('categoryAlerts')
        ..remove('eventDigests');

      final result = await backup.importFromJson(jsonEncode(exported));
      expect(result.success, isTrue, reason: 'error: ${result.error}');

      DatabaseLifecycle.notifyDatabaseSwitching();
      expect(
        (await EventDigestService.getInstance()).digests.map((d) => d.name),
        ['Birthdays'],
      );
    });

    test('an archive without categories keeps category alerts', () async {
      final exported = await seedAndExport()
        ..remove('categoryAlerts')
        ..remove('calendarCategories');

      final result = await backup.importFromJson(jsonEncode(exported));
      expect(result.success, isTrue, reason: 'error: ${result.error}');

      DatabaseLifecycle.notifyDatabaseSwitching();
      await EventAlertService.getInstance();
      expect(EventAlerts.categoryAlertsFor(kBirthdayCategoryId), [dayBefore]);
    });

    test('an event written before v42 imports as inheriting', () async {
      final exported = await seedAndExport();
      for (final raw in exported['calendarEvents'] as List) {
        (raw as Map).remove('categoryAlerts');
      }
      await wipe();

      final result = await backup.importFromJson(jsonEncode(exported));
      expect(result.success, isTrue, reason: 'error: ${result.error}');

      final event = (await CalendarEventService.getInstance()).events.single;
      expect(event.categoryAlerts, isTrue);
      await EventAlertService.getInstance();
      expect(EventAlerts.effectiveFor(event).map((a) => a.id), [
        'own-1',
        'cat-alert-1',
      ]);
    });

    test('category alerts import right after the categories', () async {
      final exported = await seedAndExport();
      await wipe();

      final result = await backup.importFromJson(jsonEncode(exported));
      expect(result.success, isTrue, reason: 'error: ${result.error}');

      // Every import stamps a fresh, monotonic HLC, so the stamps spell out
      // the order the branches ran in. The categories themselves carry no
      // stamp; the templates are the next category-keyed import after them,
      // and the events' own alerts come last.
      Future<String> stampOf(String table) async {
        final row = await db
            .customSelect('SELECT MAX(hlc_timestamp) AS stamp FROM $table')
            .getSingle();
        return row.read<String>('stamp');
      }

      final categoryAlert = await stampOf('calendar_category_alerts');
      final template = await stampOf('calendar_event_templates');
      final eventAlert = await stampOf('calendar_event_alerts');
      expect(categoryAlert.compareTo(template), lessThan(0));
      expect(categoryAlert.compareTo(eventAlert), lessThan(0));
    });
  });
}

