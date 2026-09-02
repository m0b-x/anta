import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/calendar_event_service.dart';

import '../database/support/db_test_support.dart';

/// Guards the fix that stopped `CalendarBloc` re-wrapping
/// `CalendarEventService.events` in a second `List.unmodifiable(...)` on
/// every create/update/delete. The service already reassigns its cache to a
/// fresh, already-unmodifiable list on every mutation, so the bloc can pass
/// it straight through — but only because every mutation path really does
/// produce a new identity, which is the property `sameGridInputs`,
/// `_visibleEvents` and `_partitionFor` all rely on via `identical()`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late CalendarEventService service;
  late CalendarBloc bloc;

  Future<void> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    await next;
  }

  CalendarPageLoaded loaded() => bloc.state as CalendarPageLoaded;

  setUp(() async {
    CalendarEventService.reset();
    db = await openTestDatabase();
    service = await CalendarEventService.forTesting(db);
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
  });

  tearDown(() async {
    await bloc.close();
    CalendarEventService.reset();
    await db.close();
  });

  test(
    'create publishes the service list with no extra copy, and its identity moves on',
    () async {
      final before = loaded();

      await dispatch(
        CreateCalendarEvent(
          event: CalendarEvent(
            id: 'e1',
            title: 'Leg day',
            categoryId: 'gym',
            startDate: DateTime.utc(2026, 8, 1),
            rule: const DailyRecurrence(),
          ),
        ),
      );

      final after = loaded();
      expect(identical(after.allEvents, service.events), isTrue);
      expect(identical(before.allEvents, after.allEvents), isFalse);
    },
  );

  test(
    'update publishes the service list with no extra copy, and its identity moves on',
    () async {
      await dispatch(
        CreateCalendarEvent(
          event: CalendarEvent(
            id: 'e1',
            title: 'Leg day',
            categoryId: 'gym',
            startDate: DateTime.utc(2026, 8, 1),
            rule: const DailyRecurrence(),
          ),
        ),
      );
      final before = loaded();

      await dispatch(
        UpdateCalendarEvent(
          event: CalendarEvent(
            id: 'e1',
            title: 'Leg day (updated)',
            categoryId: 'gym',
            startDate: DateTime.utc(2026, 8, 1),
            rule: const DailyRecurrence(),
          ),
        ),
      );

      final after = loaded();
      expect(identical(after.allEvents, service.events), isTrue);
      expect(identical(before.allEvents, after.allEvents), isFalse);
    },
  );

  test(
    'delete publishes the service list with no extra copy, and its identity moves on',
    () async {
      await dispatch(
        CreateCalendarEvent(
          event: CalendarEvent(
            id: 'e1',
            title: 'Leg day',
            categoryId: 'gym',
            startDate: DateTime.utc(2026, 8, 1),
            rule: const DailyRecurrence(),
          ),
        ),
      );
      final before = loaded();

      await dispatch(const DeleteCalendarEvent(eventId: 'e1'));

      final after = loaded();
      expect(identical(after.allEvents, service.events), isTrue);
      expect(identical(before.allEvents, after.allEvents), isFalse);
    },
  );
}
