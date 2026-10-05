import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/alert_excerpt.dart';
import 'package:anta/utils/alert_os_id.dart';
import 'package:anta/utils/alert_planner.dart';

import '../../tool/qa/src/placeholders.dart';

/// `tool/qa/fixtures/alerts_pair.json` is the seed
/// `tool/qa/flows/alerts_pair/` runs against: two events with an Alarm-tier
/// alert each, **due at the same instant**. The plugin sounds one and holds
/// the other until the first is stopped, but the app is told of both within
/// a second and pushes a page for each — so this is the seed that puts two
/// alarm pages on the navigator at once, which is where a page that closed
/// "whatever is on top" took the other ring's page and stayed behind itself.
///
/// What can rot without the flow saying why is what makes it that seed and
/// not another: the two instants drifting apart, one alert landing on the
/// other tier, the two entries collapsing into one, and — as with
/// `alerts.json` — the backup format and the minute arithmetic underneath.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const firstId = 'qa-pair-first';
  const secondId = 'qa-pair-second';

  /// How far ahead of the run both events are seeded. The flow does nothing
  /// before it waits, so this is all the lead it needs.
  const minutesAhead = 2;

  /// Mid-minute on an ordinary day, as a run is: the seed is resolved on the
  /// host, pushed, and imported a few seconds later.
  final now = DateTime(2026, 9, 26, 14, 30, 45);

  late Directory tempDir;
  late AppDatabase db;
  late String raw;

  /// What `{{minute+N}}` beside `{{minuteday+N}}` has to mean, for any
  /// reference: the wall clock [minutes] on, to the minute.
  DateTime wallClockAhead(DateTime reference, int minutes) => DateTime(
    reference.year,
    reference.month,
    reference.day,
    reference.hour,
    reference.minute + minutes,
  );

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_qa_pair_fixture');
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
    final fixture = File('tool/qa/fixtures/alerts_pair.json');
    expect(
      await fixture.exists(),
      isTrue,
      reason: 'run from the package root: ${fixture.absolute.path}',
    );
    raw = await fixture.readAsString();
    final backup = await BackupService.getInstance();
    final result = await backup.importFromJson(
      resolvePlaceholders(raw, now: now),
    );
    expect(result.success, isTrue, reason: 'error: ${result.error}');
    // The `[qa] seed:` line a launch prints counts these two and nothing
    // else, so a fixture with neither reads as a seed that imported nothing.
    expect(result.foldersImported, 1);
    expect(result.notesImported, 1);
    await CategoryService.getInstance();
    await CalendarEventService.getInstance();
    await EventAlertService.getInstance();
  });

  tearDownAll(() async {
    await GetIt.I.reset();
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<Map<String, CalendarEvent>> eventsById() async {
    final service = await CalendarEventService.getInstance();
    return {for (final event in service.events) event.id: event};
  }

  Future<List<PlannedFire>> plan() async {
    final service = await CalendarEventService.getInstance();
    final settings = await (await SettingsService.getInstance())
        .getAlertSettings();
    return AlertPlanner.plan(
      events: service.events,
      alertsByEvent: {
        for (final event in service.events)
          event.id: EventAlerts.alertsFor(event.id),
      },
      defaults: settings,
      horizon: kAlertHorizon,
      now: now,
    );
  }

  test('the two events land, each in a category the app has', () async {
    final events = await eventsById();
    expect(events.keys, unorderedEquals([firstId, secondId]));
    for (final event in events.values) {
      expect(event.rule, isA<OneTimeRecurrence>(), reason: event.id);
      expect(
        CalendarCategories.byId(event.categoryId),
        isNotNull,
        reason:
            '${event.title} names category ${event.categoryId}, which a '
            'fresh database does not have',
      );
    }
  });

  test('the two can be told apart, whichever rings first', () async {
    // The flow cannot say which page comes up first; a person looking at its
    // two screenshots has to be able to.
    final events = await eventsById();
    final first = events[firstId]!;
    final second = events[secondId]!;

    expect(first.title, isNot(second.title));
    expect(first.colorValue, isNot(second.colorValue));
    expect(first.iconKey, isNot(second.iconKey));
    expect(
      alertExcerptFor(first.description),
      isNot(alertExcerptFor(second.description)),
    );
    // The word the flow reads on either page.
    for (final event in [first, second]) {
      expect(event.title, startsWith('Squat'), reason: event.id);
      // An end, so each page draws the event's own time under its title.
      expect(event.time?.endMinute, isNotNull, reason: event.id);
      // Neither is removed by Stop: the second Stop lands on the calendar
      // with both rows still on it.
      expect(event.removeAfterAlert, isFalse, reason: event.id);
    }
  });

  test('each alert lands on its event, on the Alarm tier, at the start', () {
    for (final eventId in [firstId, secondId]) {
      final alert = EventAlerts.alertsFor(eventId).single;
      expect(alert.mode, AlertMode.ring, reason: eventId);
      expect(alert.offsetMinutes, 0, reason: '$eventId rings at the start');
      expect(alert.enabled, isTrue, reason: eventId);
      expect(alert.sound, isNull, reason: eventId);
    }
  });

  test('the settings keep a run quiet and short', () async {
    final settings = await (await SettingsService.getInstance())
        .getAlertSettings();
    expect(settings.snoozeMinutes, SettingsKeys.minAlertSnoozeMinutes);
    expect(
      settings.noticeLeadMinutes,
      0,
      reason: 'zero is the upcoming notice switched off',
    );
    expect(settings.timedDefault, isNull);
    expect(settings.allDayDefault, isNull);
  });

  test('the planner arms both ahead of the clock, at one and the same '
      'instant, as two entries', () async {
    final fires = await plan();

    expect(fires.map((fire) => fire.event.id), [firstId, secondId]);
    final due = wallClockAhead(now, minutesAhead);
    for (final fire in fires) {
      expect(fire.fireAt, due, reason: fire.event.id);
    }
    // Long enough for the relaunch that pushed the seed to import it and arm
    // both: the ring is never less than a minute away.
    expect(due.difference(now), greaterThan(const Duration(minutes: 1)));
    // Two entries on the platform, not one armed twice.
    final osIds = {
      for (final fire in fires)
        alertOsIdSeed(
          database: 'qa',
          alertId: fire.alert.id,
          dayUtc: fire.day,
          kind: AlertKind.scheduled,
        ),
    };
    expect(osIds, hasLength(2));
  });

  test('seeded just before midnight, both land on tomorrow', () {
    final lateNight = DateTime(2026, 9, 26, 23, 58, 20);
    final seed =
        jsonDecode(resolvePlaceholders(raw, now: lateNight))
            as Map<String, dynamic>;

    for (final event in seed['calendarEvents'] as List) {
      final map = event as Map<String, dynamic>;
      final day = DateTime.fromMillisecondsSinceEpoch(
        map['startDateMs'] as int,
        isUtc: true,
      );
      expect(day, DateTime.utc(2026, 9, 27), reason: '${map['id']}');
      // The instant the app fires it at, built the way the planner builds it.
      expect(
        DateTime(day.year, day.month, day.day, 0, map['startMinute'] as int),
        wallClockAhead(lateNight, minutesAhead),
        reason: '${map['id']}',
      );
    }
  });

  test('every time in the fixture is relative, and the same for both', () {
    // A literal epoch or minute of day would ring once and then sit in the
    // past for good; two different offsets would be two rings a minute
    // apart, which is the other fixture.
    final seed = jsonDecode(raw) as Map<String, dynamic>;
    final events = seed['calendarEvents'] as List;
    expect(events, hasLength(2));
    for (final event in events) {
      final map = event as Map<String, dynamic>;
      expect(map['startDateMs'], '{{minuteday+$minutesAhead}}', reason: '$map');
      expect(map['startMinute'], '{{minute+$minutesAhead}}', reason: '$map');
    }
  });
}
