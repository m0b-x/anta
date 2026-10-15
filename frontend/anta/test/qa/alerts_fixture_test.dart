import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/event_digests.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/alert_scheduler.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_digest_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/alert_excerpt.dart';
import 'package:anta/utils/alert_labels.dart';
import 'package:anta/utils/alert_planner.dart';
import 'package:anta/utils/digest_notification_content.dart';
import 'package:anta/utils/digest_planner.dart';
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
///
/// Since v42 it also carries what `03_category_alerts` and `04_digests` read:
/// a yearly birthday two days ahead, the Birthday category's one alert it
/// inherits, a monthly Birthday digest, and "Next days" — a daily digest
/// nine minutes out, after the alarm flows, whose one fire lists the
/// birthday, so the pass has a digest notification on the shade.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const plainId = 'qa-alert-plain';
  const removeId = 'qa-alert-remove';
  const reminderId = 'qa-alert-reminder';
  const birthdayId = 'qa-alert-birthday';
  const categoryAlertId = 'qa-alert-category-birthday';
  const digestId = 'qa-alert-digest-birthdays';
  const soonDigestId = 'qa-alert-digest-soon';

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
    await EventDigestService.getInstance();
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

  test('the four events land, each in a category the app has', () async {
    final events = await eventsById();
    expect(events.keys, unorderedEquals([...minutesAhead.keys, birthdayId]));
    for (final event in events.values) {
      if (minutesAhead.containsKey(event.id)) {
        expect(event.rule, isA<OneTimeRecurrence>(), reason: event.id);
      }
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
      if (map['id'] == birthdayId) {
        // All-day: a day and no minute.
        expect(map['startDateMs'], '{{today+2}}', reason: '$map');
        expect(map['startMinute'], isNull, reason: '$map');
        continue;
      }
      final minutes = minutesAhead[map['id']];
      expect(map['startDateMs'], '{{minuteday+$minutes}}', reason: '$map');
      expect(map['startMinute'], '{{minute+$minutes}}', reason: '$map');
    }
  });

  test('the birthday is yearly, all-day and counted, with no alert of its '
      'own', () async {
    final ana = (await eventsById())[birthdayId]!;
    expect(ana.title, 'Ana');
    expect(ana.categoryId, kBirthdayCategoryId);
    expect(ana.rule, isA<YearlyRecurrence>());
    expect(ana.allDay, isTrue);
    expect(ana.countOccurrences, isTrue);
    expect(ana.categoryAlerts, isTrue);
    expect(EventAlerts.alertsFor(birthdayId), isEmpty);
  });

  test('the Birthday category alert lands with both offsets, and the '
      'birthday inherits it', () async {
    final alert = EventAlerts.categoryAlertsFor(kBirthdayCategoryId).single;
    expect(alert.id, categoryAlertId);
    expect(alert.mode, AlertMode.notify);
    expect(alert.offsetMinutes, 30);
    expect(alert.daysBefore, 1);
    expect(alert.dayMinute, 540);
    expect(alert.sound, isNull);
    expect(alert.enabled, isTrue);

    final ana = (await eventsById())[birthdayId]!;
    final inherited = EventAlerts.effectiveFor(ana).single;
    expect(inherited.id, categoryAlertId);
    expect(inherited.categoryId, kBirthdayCategoryId);
    // The alarm flows' events are in other categories and inherit nothing.
    for (final eventId in minutesAhead.keys) {
      final event = (await eventsById())[eventId]!;
      expect(EventAlerts.effectiveFor(event), hasLength(1), reason: eventId);
    }
  });

  test('the inherited reminder is planned for the day before at 09:00, after '
      'the alarm flows and inside the hub\'s window', () async {
    final service = await CalendarEventService.getInstance();
    final settings = await (await SettingsService.getInstance())
        .getAlertSettings();
    final ana = service.events.firstWhere((event) => event.id == birthdayId);
    final plan = AlertPlanner.plan(
      events: [ana],
      alertsByEvent: {birthdayId: EventAlerts.effectiveFor(ana)},
      defaults: settings,
      horizon: kAlertHorizon,
      now: now,
    );
    expect(plan.single.alert.id, categoryAlertId);
    expect(plan.single.fireAt, DateTime(2026, 9, 27, 9));

    // Two days ahead puts the fire on tomorrow's morning whatever the hour
    // the seed goes in — tomorrow would put it this morning, behind the
    // clock for most of the day, and the hub would list nothing to read.
    for (final seededAt in [
      DateTime(2026, 9, 26, 0, 0, 10),
      DateTime(2026, 9, 26, 8, 59, 50),
      DateTime(2026, 9, 26, 23, 59, 50),
    ]) {
      final seed =
          jsonDecode(resolvePlaceholders(raw, now: seededAt))
              as Map<String, dynamic>;
      final map = (seed['calendarEvents'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((event) => event['id'] == birthdayId);
      final day = DateTime.fromMillisecondsSinceEpoch(
        map['startDateMs'] as int,
        isUtc: true,
      );
      final fireAt = DateTime(day.year, day.month, day.day - 1, 0, 540);
      expect(
        fireAt.isAfter(wallClockAhead(seededAt, minutesAhead[reminderId]!)),
        isTrue,
        reason: 'seeded at $seededAt',
      );
      expect(
        fireAt.difference(seededAt),
        lessThan(Duration(days: kAlertHorizon.days)),
        reason: 'seeded at $seededAt',
      );
    }
  });

  test('the digest lands as a monthly Birthday digest that fires when '
      'empty', () async {
    final digest = EventDigests.byId(digestId)!;
    expect(digest.name, '');
    expect(digest.isReadable, isTrue);
    expect(digest.cadence, DigestCadence.monthly);
    expect(digest.anchor, 1);
    expect(digest.minute, 540);
    expect(digest.leadDays, 0);
    expect(digest.categoryIds, {kBirthdayCategoryId});
    expect(digest.includeEmpty, isTrue);
    expect(digest.enabled, isTrue);

    // The next fire is the coming 1st and lists that month, which the
    // birthday two days out is usually not in: Also when empty is what puts
    // the fire row in the hub on every run.
    final service = await CalendarEventService.getInstance();
    final plan = DigestPlanner.plan(
      digests: [digest],
      events: service.events,
      horizon: kDigestHorizon,
      now: now,
    );
    expect(plan, hasLength(kDigestHorizon.perDigest));
    expect(plan.first.fireAt, DateTime(2026, 10, 1, 9));
    expect(plan.first.spanStart, DateTime.utc(2026, 10, 1));
    expect(plan.first.entries, isEmpty);
  });

  test('"Next days" lands as a daily digest two days ahead, nine minutes '
      'out', () {
    final digest = EventDigests.byId(soonDigestId)!;
    expect(digest.name, 'Next days');
    expect(digest.isReadable, isTrue, reason: 'the minute resolved in place');
    expect(digest.cadence, DigestCadence.daily);
    final ninth = wallClockAhead(now, 9);
    expect(digest.minute, ninth.hour * 60 + ninth.minute);
    expect(digest.leadDays, 2);
    expect(digest.categoryIds, {kBirthdayCategoryId});
    expect(digest.includeEmpty, isFalse);
    expect(digest.enabled, isTrue);
    expect(
      EventDigests.all.map((digest) => digest.id),
      [digestId, soonDigestId],
      reason: 'the hub lists the monthly digest first',
    );
  });

  test('"Next days" fires once, after the alarm flows, listing Ana in the '
      'words the shade shows', () async {
    final service = await CalendarEventService.getInstance();
    final plan = DigestPlanner.plan(
      digests: [EventDigests.byId(soonDigestId)!],
      events: service.events,
      horizon: kDigestHorizon,
      now: now,
    );
    // Tomorrow's fire lists today + 3, which is empty, and an empty span
    // with Also when empty off plans nothing.
    final fire = plan.single;
    expect(fire.fireAt, wallClockAhead(now, 9));
    expect(
      fire.fireAt.isAfter(wallClockAhead(now, minutesAhead[reminderId]!)),
      isTrue,
    );
    expect(fire.spanStart, DateTime.utc(2026, 9, 28));
    expect(fire.spanEnd, fire.spanStart);
    expect(fire.entries.single.event.id, birthdayId);

    final content = digestNotificationContent(
      fire,
      lookupAppLocalizations(const Locale('en')),
      AlertLabels.fixed,
      categoryLabel: (_) => 'Birthday',
      weekStart: CalendarWeekStart.monday,
    );
    expect(content.title, 'Next days');
    // A daily digest names only today and tomorrow; two days ahead is
    // written as a span of one day.
    expect(content.text, '1 event from Sep 28 to Sep 28 · Sep 28 · Ana');
    expect(content.lines, ['Mon, Sep 28 · Ana · Year 1']);
    expect(content.summary, isNull);
  });

  test('"Next days" lists Ana for a seed at any hour that leaves nine '
      'minutes in the day', () {
    PlannedDigest? firstFire(DateTime seededAt) {
      final seed =
          jsonDecode(resolvePlaceholders(raw, now: seededAt))
              as Map<String, dynamic>;
      final row = (seed['eventDigests'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((digest) => digest['id'] == soonDigestId);
      final map = (seed['calendarEvents'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((event) => event['id'] == birthdayId);
      final ana = CalendarEvent(
        id: birthdayId,
        title: 'Ana',
        categoryId: kBirthdayCategoryId,
        startDate: DateTime.fromMillisecondsSinceEpoch(
          map['startDateMs'] as int,
          isUtc: true,
        ),
        rule: const YearlyRecurrence(),
        countOccurrences: true,
      );
      final plan = DigestPlanner.plan(
        digests: [
          EventDigest.fromRow(
            id: row['id'] as String,
            name: row['name'] as String,
            payload: row['payload'] as String,
          ),
        ],
        events: [ana],
        horizon: kDigestHorizon,
        now: seededAt,
      );
      return plan.isEmpty ? null : plan.single;
    }

    for (final seededAt in [
      DateTime(2026, 9, 26, 0, 0, 10),
      DateTime(2026, 9, 26, 8, 59, 50),
      DateTime(2026, 9, 26, 23, 50, 10),
    ]) {
      final fire = firstFire(seededAt)!;
      expect(fire.fireAt, wallClockAhead(seededAt, 9), reason: '$seededAt');
      expect(fire.spanStart, DateTime.utc(2026, 9, 28), reason: '$seededAt');
      expect(fire.entries.single.event.id, birthdayId, reason: '$seededAt');
    }

    // Past 23:50 the ninth minute is tomorrow's: the fire moves to tomorrow,
    // its span to today + 3, where Ana is not, and nothing is planned — the
    // ring part of the pass needs a seed before 23:50.
    final lateSeed = DateTime(2026, 9, 26, 23, 55, 10);
    expect(firstFire(lateSeed), isNull);
    final digest = EventDigests.byId(soonDigestId)!;
    expect(
      DigestPlanner.spanFor(digest, DateTime.utc(2026, 9, 27)).start,
      DateTime.utc(2026, 9, 29),
    );
  });
}
