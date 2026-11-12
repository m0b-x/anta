import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/share_overview.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/share_service.dart';

import '../support/fake_share_service.dart';

/// The editor's share switch reaches the share service through the
/// calendar's bloc (share surfaces §6.6): one write, its answer handed back
/// to the dispatch site, and a refusal handed back as one — never swallowed
/// as a share that silently did nothing.
void main() {
  const audience = ShareAudience(
    id: 'pair-1',
    displayName: 'Maria',
    members: [],
  );

  late FakeShareService share;
  late CalendarBloc bloc;

  setUp(() {
    share = FakeShareService(availability: const ShareReady(audience));
    bloc = CalendarBloc(
      // The share write reads no event store.
      service: Completer<CalendarEventService>().future,
      shareService: () async => share,
    );
  });

  tearDown(() => bloc.close());

  test('writes the mark and completes with what the service wrote', () async {
    final change = ShareChange(
      sharedEvents: [
        CalendarEvent(
          id: 'e1',
          title: 'Dinner',
          categoryId: 'gym',
          startDate: DateTime.utc(2026, 9, 20),
        ),
      ],
    );
    share.nextChange = change;
    final outcome = Completer<ShareChange>();

    bloc.add(SetEventShared(eventId: 'e1', shared: true, outcome: outcome));

    expect(await outcome.future, change);
    expect(share.eventShares, [('e1', true)]);
  });

  test('an Undo with no one waiting still writes', () async {
    bloc.add(const SetEventShared(eventId: 'e1', shared: false));
    await pumpEventQueue();

    expect(share.eventShares, [('e1', false)]);
  });

  test('a database that stopped syncing refuses, and the dispatch site '
      'hears why', () async {
    share.emit(const ShareNotSyncing(audience));
    final outcome = Completer<ShareChange>();

    bloc.add(SetEventShared(eventId: 'e1', shared: true, outcome: outcome));

    await expectLater(outcome.future, throwsA(isA<ShareRefused>()));
    expect(share.eventShares, isEmpty);
  });

  test('a share riding a save the bloc could not make writes nothing, and '
      'the dispatch site hears "nothing changed"', () async {
    final event = CalendarEvent(
      id: 'e1',
      title: 'Dinner',
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 9, 20),
    );
    // The store never opens, so the calendar never loads: neither save is
    // made, and neither may mark anything.
    final created = Completer<ShareChange>();
    final updated = Completer<ShareChange>();

    bloc.add(
      CreateCalendarEvent(event: event, shared: true, shareOutcome: created),
    );
    bloc.add(
      UpdateCalendarEvent(event: event, shared: true, shareOutcome: updated),
    );

    expect(await created.future, ShareChange.none);
    expect(await updated.future, ShareChange.none);
    expect(share.eventShares, isEmpty);
  });

  test('the outcome is not part of the event\'s equality', () {
    expect(
      SetEventShared(eventId: 'e1', shared: true, outcome: Completer()),
      const SetEventShared(eventId: 'e1', shared: true),
    );
  });
}
