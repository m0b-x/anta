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
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/alert_excerpt.dart';
import 'package:anta/utils/alert_planner.dart';
import 'package:anta/utils/quick_alarm.dart';

import '../../tool/qa/src/placeholders.dart';

/// `tool/qa/fixtures/alerts.json` is the seed the alert flows under
/// `tool/qa/flows/alerts/` run against: three events a few minutes ahead of
/// the run, one alert each, so a device pass has something that rings without
/// anyone setting it by hand. It is hand-written with relative times, and
/// three things can rot without a flow saying why — the backup format
/// underneath it, an alert that imports onto no event or onto the other tier,
/// and the minute arithmetic. That last one fails silently: an event that
/// lands in the past arms nothing, and the flow waits out its timeout on a
/// phone that never rings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const plainId = 'qa-alert-plain';
  const removeId = 'qa-alert-remove';
  const reminderId = 'qa-alert-reminder';

  /// The minutes each event is seeded ahead of the run, which is the order
  /// the flows wait for them in.
  const minutesAhead = {plainId: 3, removeId: 5, reminderId: 7};

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
    tempDir = await Directory.systemTemp.createTemp('anta_qa_alerts_fixture');
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
    final fixture = File('tool/qa/fixtures/alerts.json');
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

  test('the three events land, each in a category the app has', () async {
    final events = await eventsById();
    expect(events.keys, unorderedEquals(minutesAhead.keys));
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

  test('each event is the shape its flow rings', () async {
    final events = await eventsById();

    // The ordinary alarm: an end for the session chip to count towards, a
    // first description line short enough to be a notification body whole,
    // and a colour of its own on the icon.
    final plain = events[plainId]!;
    expect(plain.title, 'Leg day');
    expect(plain.time?.durationMinutes, 60);
    expect(alertExcerptFor(plain.description), 'Squats first.');
    expect(plain.colorValue, 0xFF00897B);
    expect(plain.tintIcon, isTrue);
    expect(plain.removeAfterAlert, isFalse);
    final notes = await db.noteDao.getAllNotes(includeDeleted: false);
    expect(
      plain.noteId,
      notes.single.id,
      reason: 'the importer assigns fresh note ids and remaps the link',
    );

    // The quick alarm's shape, field for field: `buildQuickAlarmEvent`.
    final remove = events[removeId]!;
    expect(remove.title, 'Tea timer');
    expect(remove.time, isNotNull);
    expect(remove.time!.durationMinutes, isNull);
    expect(remove.categoryId, kFallbackCategoryId);
    expect(remove.iconKey, kQuickAlarmIconKey);
    expect(remove.removeAfterAlert, isTrue);

    final reminder = events[reminderId]!;
    expect(reminder.title, 'Stretch');
    expect(reminder.time, isNotNull);
    expect(alertExcerptFor(reminder.description), 'Hips and hamstrings.');
    expect(reminder.removeAfterAlert, isFalse);
  });

  test('each alert lands on its event, on the tier its flow expects', () {
    const tiers = {
      plainId: AlertMode.ring,
      removeId: AlertMode.ring,
      reminderId: AlertMode.notify,
    };
    for (final MapEntry(key: eventId, value: tier) in tiers.entries) {
      final alert = EventAlerts.alertsFor(eventId).single;
      expect(alert.mode, tier, reason: eventId);
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
    // No default alert either: an event made by hand during a pass starts
    // with none, so nothing rings that the fixture did not put there.
    expect(settings.timedDefault, isNull);
    expect(settings.allDayDefault, isNull);
  });

  test('the planner arms all three ahead of the clock, in flow order and '
      'two minutes apart', () async {
    final service = await CalendarEventService.getInstance();
    final settings = await (await SettingsService.getInstance())
        .getAlertSettings();
    final plan = AlertPlanner.plan(
      events: service.events,
      alertsByEvent: {
        for (final event in service.events)
          event.id: EventAlerts.alertsFor(event.id),
      },
      defaults: settings,
      horizon: kAlertHorizon,
      now: now,
    );

    expect(plan.map((fire) => fire.event.id), minutesAhead.keys);
    for (final fire in plan) {
      expect(
        fire.fireAt,
        wallClockAhead(now, minutesAhead[fire.event.id]!),
        reason: fire.event.id,
      );
      expect(
        noticeInstantFor(
          fire: fire,
          leadMinutes: settings.noticeLeadMinutes,
          now: now,
        ),
        isNull,
        reason: '${fire.event.id} posts no upcoming notice',
      );
    }
    // The test-alarm flow runs first — a launch, five taps, a scroll and a
    // ten-second ring — and a ring that arrives during another is queued or
    // dropped by the plugin, so the first alarm keeps clear of it.
    expect(
      plan.first.fireAt.difference(now),
      greaterThan(const Duration(minutes: 2)),
    );
    for (var i = 1; i < plan.length; i++) {
      expect(
        plan[i].fireAt.difference(plan[i - 1].fireAt),
        const Duration(minutes: 2),
        reason:
            '${plan[i - 1].event.id} is stopped long before '
            '${plan[i].event.id} rings',
      );
    }
  });

  test('seeded just before midnight, every event lands on tomorrow', () {
    // The pair `{{minuteday+N}}` / `{{minute+N}}` is what makes this hold; a
    // fixture written with `{{today}}` would put all three 24 hours back,
    // where the planner arms nothing.
    final lateNight = DateTime(2026, 9, 26, 23, 58, 20);
    final seed =
        jsonDecode(resolvePlaceholders(raw, now: lateNight))
            as Map<String, dynamic>;
    final events = {
      for (final event in seed['calendarEvents'] as List)
        (event as Map<String, dynamic>)['id'] as String: event,
    };

    for (final MapEntry(key: eventId, value: minutes) in minutesAhead.entries) {
      final event = events[eventId]!;
      final day = DateTime.fromMillisecondsSinceEpoch(
        event['startDateMs'] as int,
        isUtc: true,
      );
      expect(day, DateTime.utc(2026, 9, 27), reason: eventId);
      // The instant the app fires it at, built the way the planner builds it.
      expect(
        DateTime(day.year, day.month, day.day, 0, event['startMinute'] as int),
        wallClockAhead(lateNight, minutes),
        reason: eventId,
      );
    }
  });

  test('every time in the fixture is relative', () {
    // A literal epoch or minute of day would ring once and then sit in the
    // past for good.
    final seed = jsonDecode(raw) as Map<String, dynamic>;
    for (final event in seed['calendarEvents'] as List) {
      final map = event as Map<String, dynamic>;
      final minutes = minutesAhead[map['id']];
      expect(map['startDateMs'], '{{minuteday+$minutes}}', reason: '$map');
      expect(map['startMinute'], '{{minute+$minutes}}', reason: '$map');
    }
  });
}
