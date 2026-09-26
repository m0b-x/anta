import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/occurrence_descriptions.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/event_template_service.dart';
import 'package:anta/services/filter_preset_service.dart';
import 'package:anta/services/public_holiday_service.dart';

import '../../tool/qa/src/placeholders.dart';

/// `tool/qa/fixtures/calendar.json` is the seed the calendar flows under
/// `tool/qa/flows/calendar/` run against. It is hand-written with relative
/// dates, so two things can silently rot: the backup format underneath it,
/// and the placeholder arithmetic that keeps "today" in the window. Both are
/// pinned here structurally — an event that imports but never occurs, or an
/// alert that lands on no event, would leave a flow tapping at nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);
  DateTime day(int offset) => today.add(Duration(days: offset));

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_qa_calendar_fixture');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    GetIt.I.registerSingleton<CounterService>(
      await CounterService.getInstance(),
    );
    db = await AppDatabase.getInstance();
    final fixture = File('tool/qa/fixtures/calendar.json');
    expect(
      await fixture.exists(),
      isTrue,
      reason: 'run from the package root: ${fixture.absolute.path}',
    );
    final raw = await fixture.readAsString();
    expect(countPlaceholders(raw), greaterThan(20));
    final backup = await BackupService.getInstance();
    final result = await backup.importFromJson(
      resolvePlaceholders(raw, now: now),
    );
    expect(result.success, isTrue, reason: 'error: ${result.error}');
    await CategoryService.getInstance();
    await CalendarEventService.getInstance();
    await EventAlertService.getInstance();
    await EventSkipService.getInstance();
    await EventPresenceService.getInstance();
    await EventOccurrenceService.getInstance();
    await EventTemplateService.getInstance();
    await FilterPresetService.getInstance();
    await PublicHolidayService.getInstance();
  });

  tearDownAll(() async {
    await GetIt.I.reset();
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('every event lands, in a category the picker can show', () async {
    final service = await CalendarEventService.getInstance();
    final events = service.events;
    expect(events.map((e) => e.title), containsAll(<String>[
      'Lifting session',
      'Morning walk',
      'Physio',
      "Mara's birthday",
      'Standup',
      'Old checkup',
      'Archived plan',
    ]));
    for (final event in events) {
      expect(
        CalendarCategories.byId(event.categoryId),
        isNotNull,
        reason: '${event.title} names category ${event.categoryId}, '
            'which the import did not produce',
      );
    }
    final hidden = CalendarCategories.byId('qa-cal-hidden');
    expect(hidden?.isHidden, isTrue);
    expect(CalendarCategories.visible.map((c) => c.id), isNot(contains('qa-cal-hidden')));
  });

  test('the relative dates put the fixture around today', () async {
    final service = await CalendarEventService.getInstance();
    final byTitle = {for (final e in service.events) e.title: e};

    final lift = byTitle['Lifting session']!;
    expect(lift.occursOn(today), isTrue, reason: 'weekly on today\'s weekday');
    expect(lift.occursOn(day(2)), isTrue);
    expect(lift.occursOn(day(7)), isFalse, reason: 'that occurrence is skipped');
    expect(EventSkips.isSkipped(lift.id, day(7)), isTrue);
    expect(EventPresence.marksFor(lift.id)[day(-7)], PresenceStatus.missed);
    expect(EventPresence.marksFor(lift.id)[day(-14)], PresenceStatus.present);
    expect(OccurrenceDescriptions.overrideFor(lift.id, today), 'Deload: 3×5 at 80 %.');
    final notes = await db.noteDao.getAllNotes(includeDeleted: false);
    final session = notes.firstWhere((n) => n.title == 'Session 1');
    expect(
      lift.noteId,
      session.id,
      reason: 'the importer assigns fresh note ids and remaps the link',
    );

    final walk = byTitle['Morning walk']!;
    expect(walk.occursOn(today), isTrue);
    expect(EventAlerts.alertsFor(walk.id), hasLength(5),
        reason: 'the five-alert cap check needs an event at the cap');

    final physio = byTitle['Physio']!;
    final rule = physio.rule;
    expect(rule, isA<SpecificDatesRecurrence>());
    expect(<DateTime>{physio.startDate, ...(rule as SpecificDatesRecurrence).dates}, hasLength(6));
    expect(physio.occursOn(day(1)), isTrue);
    expect(physio.occursOn(day(29)), isTrue);
    expect(physio.occursOn(today), isFalse);

    final birthday = byTitle["Mara's birthday"]!;
    expect(birthday.occursOn(day(10)), isTrue);
    expect(birthday.colorValue, isNotNull);
    expect(birthday.tintIcon, isTrue);

    final checkup = byTitle['Old checkup']!;
    expect(checkup.occursOn(day(-40)), isTrue);
    expect(checkup.occursOn(today), isFalse);
  });

  test('templates, presets and the custom holiday land', () async {
    final templates = (await EventTemplateService.getInstance()).templates;
    expect(templates.map((t) => t.name), contains('Leg day'));
    final presets = (await FilterPresetService.getInstance()).presets;
    expect(presets.map((p) => p.name), contains('Top priority'));
    final holiday = PublicHolidays.holidayOn(day(20));
    expect(holiday, isNotNull, reason: 'the custom holiday is 20 days out');
  });

  test('the seeded settings are what the flows assume', () async {
    expect(await db.userSettingsDao.getValue('holiday_profile'), 'germany');
    expect(await db.userSettingsDao.getValue('calendar_fasting_traditions'), 'orthodox');
    expect(await db.userSettingsDao.getValue('money_ledger_enabled'), 'true');
  });
}
