import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/public_holidays.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';

/// Holiday state is a third membership input, alongside the event rows and the
/// skip set, and it is the only one no bloc handler can observe.
///
/// `WorkdaysRecurrence` and `PublicHolidaysOnlyRecurrence` call
/// `PublicHolidays.isHoliday` from inside `occursOn`, but `PublicHolidayService`
/// publishes straight into the static facade — so a profile switch, a backup
/// restore or a database switch changes which days those events occur on with
/// no event dispatched. Without a generation check the day cache keeps serving
/// the pre-change answer for up to 512 memoized days.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;

  // 2026-08-11 is a Tuesday, so the workdays rule includes it unless a holiday
  // lands there.
  final workday = DateTime.utc(2026, 8, 11);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_holiday');
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

  Future<void> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    await next;
  }

  setUp(() async {
    final service = await CalendarEventService.getInstance();
    await service.deleteAll();
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'w1',
          title: 'Standup',
          categoryId: 'gym',
          startDate: DateTime.utc(2026, 8, 1),
          rule: const WorkdaysRecurrence(),
        ),
      ),
    );
  });

  tearDown(() async {
    await bloc.close();
    // The facade is process-wide static state; other suites rely on the
    // uninitialized fallback.
    PublicHolidays.resetCache();
  });

  test('declaring a holiday drops the memoized day', () async {
    // Warm the cache first: this is exactly the entry that would keep being
    // served.
    expect(bloc.eventsForDay(workday), hasLength(1));

    PublicHolidays.configure(
      profile: HolidayProfile.generic,
      overrides: {workday: const PublicHolidayInfo.custom('Company day')},
      suppressed: const {},
    );

    expect(PublicHolidays.isHoliday(workday), isTrue);
    expect(bloc.eventsForDay(workday), isEmpty);
  });

  test('resetting the facade drops the memoized day', () async {
    PublicHolidays.configure(
      profile: HolidayProfile.generic,
      overrides: {workday: const PublicHolidayInfo.custom('Company day')},
      suppressed: const {},
    );
    expect(bloc.eventsForDay(workday), isEmpty);

    PublicHolidays.resetCache();

    expect(bloc.eventsForDay(workday), hasLength(1));
  });

  test('both republish paths bump the revision', () async {
    final start = PublicHolidays.revision;

    PublicHolidays.configure(
      profile: HolidayProfile.generic,
      overrides: {workday: const PublicHolidayInfo.custom('Company day')},
      suppressed: const {},
    );
    final afterConfigure = PublicHolidays.revision;
    expect(afterConfigure, greaterThan(start));

    // resetCache is the database-switch path. A reset that did not bump would
    // leave the calendar expanding against a closed database's holidays.
    PublicHolidays.resetCache();
    expect(PublicHolidays.revision, greaterThan(afterConfigure));
  });
}
