import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_palette.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_template.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/event_template_service.dart';
import 'package:anta/services/public_holiday_service.dart';

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

    final events = await CalendarEventService.getInstance();
    await events.upsert(
      CalendarEvent(
        id: 'roundtrip-event',
        title: 'Standing meeting',
        categoryId: categoryId,
        startDate: DateTime.utc(2026, 8, 1),
        rule: const WeeklyRecurrence(weekdays: {DateTime.monday}),
        tracksPresence: true,
        perOccurrenceDescriptions: true,
      ),
    );
    await (await EventOccurrenceService.getInstance()).setDescription(
      'roundtrip-event',
      missedDay,
      'Standup instead',
    );
    await (await EventPresenceService.getInstance()).markMissed(
      'roundtrip-event',
      missedDay,
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

    await EventPresenceService.getInstance();
    expect(EventPresence.isMissed('roundtrip-event', missedDay), isTrue);

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
  });
}
