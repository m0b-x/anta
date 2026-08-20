import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';

/// Guards `CalendarPageLoaded.sameGridInputs`, which drives the grid's
/// `buildWhen`.
///
/// The grid and the day panel subscribe separately so a panel-only tick does
/// not rebuild 42 cells. The line between them is not "everything except
/// `occurrenceRevision`": `DayBarsResolver` and `CellTintResolver` both read
/// `EventPresence.isMissed`, so presence *is* a grid input even though it
/// rides the same overlay revision as descriptions. That is why
/// `presenceRevision` exists, and the second case below is the only thing
/// standing between a future presence write path that forgets to bump it and
/// a permanently stale missed marker.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;

  final day = DateTime.utc(2026, 8, 10);

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_grid');
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

  Future<CalendarPageLoaded> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    return await next as CalendarPageLoaded;
  }

  CalendarPageLoaded loaded() => bloc.state as CalendarPageLoaded;

  setUp(() async {
    final service = await CalendarEventService.getInstance();
    await service.deleteAll();
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'e1',
          title: 'Leg day',
          categoryId: 'gym',
          startDate: DateTime.utc(2026, 8, 1),
          rule: const DailyRecurrence(),
          tracksPresence: true,
          perOccurrenceDescriptions: true,
        ),
      ),
    );
  });

  tearDown(() async {
    await bloc.close();
  });

  test('an occurrence description leaves the grid inputs untouched', () async {
    final before = loaded();

    final after = await dispatch(
      SetOccurrenceDescription(eventId: 'e1', day: day, description: 'note'),
    );

    expect(after, isNot(equals(before)));
    expect(after.occurrenceRevision, greaterThan(before.occurrenceRevision));
    expect(before.sameGridInputs(after), isTrue);
  });

  test('a presence mark changes the grid inputs', () async {
    final before = loaded();

    final after = await dispatch(SetOccurrenceMissed(eventId: 'e1', day: day));

    expect(after.presenceRevision, greaterThan(before.presenceRevision));
    expect(before.sameGridInputs(after), isFalse);
  });

  test('clearing a presence mark changes the grid inputs', () async {
    await dispatch(SetOccurrenceMissed(eventId: 'e1', day: day));
    final before = loaded();

    final after = await dispatch(
      ClearOccurrenceMissed(eventId: 'e1', day: day),
    );

    expect(after.presenceRevision, greaterThan(before.presenceRevision));
    expect(before.sameGridInputs(after), isFalse);
  });

  test('a skip changes the grid inputs', () async {
    final before = loaded();

    final after = await dispatch(SetOccurrenceSkipped(eventId: 'e1', day: day));

    expect(after.membershipRevision, greaterThan(before.membershipRevision));
    expect(before.sameGridInputs(after), isFalse);
  });

  test('selecting a day changes the grid inputs', () async {
    final before = loaded();

    final after = await dispatch(SelectCalendarDay(day: day, focusedDay: day));

    expect(before.sameGridInputs(after), isFalse);
  });

  test('an unchanged event list keeps its identity across a day tap', () async {
    final before = loaded();

    final after = await dispatch(SelectCalendarDay(day: day, focusedDay: day));

    // sameGridInputs compares the two collections by identity, which is only
    // sound because copyWith passes the same instances through.
    expect(identical(before.allEvents, after.allEvents), isTrue);
    expect(
      identical(before.hiddenCategoryIds, after.hiddenCategoryIds),
      isTrue,
    );
  });
}
