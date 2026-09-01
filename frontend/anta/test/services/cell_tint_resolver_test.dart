import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/day_cell_tint.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/cell_tint_resolver.dart';
import 'package:anta/utils/event_agenda.dart';

/// The day-cell wash is the only surface where priority is *visible* rather
/// than just an ordering key, so these tests pin the two things that make the
/// claim true: exactly one event contributes (a blend would show a colour no
/// event on the day actually has), and the alpha ramp is monotonic in
/// priority with P1 strongest.
///
/// The fasting provider needs the fasting engine configured, which these
/// tests deliberately do not do — with no traditions enabled it returns null,
/// which is exactly the "event tint only" case. Conflict resolution is
/// covered through the resolver's own layering rules instead.
void main() {
  final day = DateTime.utc(2026, 8, 10);

  CalendarEvent event(
    String id, {
    int priority = kDefaultEventPriority,
    EventTime? time,
    bool tracksPresence = false,
    int? colorValue,
  }) {
    return CalendarEvent(
      id: id,
      title: id,
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 8, 1),
      rule: const DailyRecurrence(),
      priority: priority,
      time: time,
      tracksPresence: tracksPresence,
      colorValue: colorValue,
    );
  }

  const provider = EventCellTintProvider(
    priority: CellTintResolver.winnerPriority,
  );

  setUp(EventPresence.resetCache);
  tearDown(EventPresence.resetCache);

  group('EventCellTintProvider', () {
    test('an empty day contributes nothing', () {
      expect(provider.tintFor(day, const []), isNull);
    });

    test('alpha follows priority, P1 strongest', () {
      final alphas = [
        for (var p = kMinEventPriority; p <= kMaxEventPriority; p++)
          provider.tintFor(day, [event('e', priority: p)])!.wash.a,
      ];

      expect(
        alphas,
        orderedEquals(List.of(alphas)..sort((a, b) => b.compareTo(a))),
      );
      expect(alphas.first, greaterThan(alphas.last));
      expect(
        alphas.first,
        closeTo(CalendarColors.eventTintAlphaByPriority.first, 0.01),
      );
    });

    test('the top event by the shared comparator supplies the colour', () {
      const winner = 0xFF112233;
      const loser = 0xFF445566;
      final events = [
        event('low', priority: 4, colorValue: loser),
        event('high', priority: 1, colorValue: winner),
      ];
      // Sanity-check the fixture against the comparator itself rather than
      // trusting the hand-picked order.
      final expected = ([...events]..sort(EventAgenda.compareWithinDay)).first;
      expect(expected.id, 'high');

      final layer = provider.tintFor(day, events)!;

      expect(layer.wash.r, const Color(winner).r);
      expect(layer.wash.g, const Color(winner).g);
      expect(layer.wash.b, const Color(winner).b);
    });

    test('all-day beats timed at equal priority, as the panel orders them', () {
      const allDayColor = 0xFF010203;
      final events = [
        event('timed', time: const EventTime(startMinute: 60)),
        event('allDay', colorValue: allDayColor),
      ];

      final layer = provider.tintFor(day, events)!;

      expect(layer.wash.r, const Color(allDayColor).r);
    });

    test('an override wins over the category colour', () {
      const override = 0xFF7A00FF;

      final layer = provider.tintFor(day, [event('e', colorValue: override)])!;

      expect(layer.wash.r, const Color(override).r);
      expect(layer.wash.b, const Color(override).b);
    });

    test('the edge is far stronger than the wash', () {
      final layer = provider.tintFor(day, [event('e')])!;

      expect(layer.edge.a, greaterThan(layer.wash.a));
      expect(layer.edge.a, closeTo(CalendarColors.cellEdgeAlpha, 0.01));
    });

    group('presence', () {
      setUp(() {
        EventPresence.updateCache(
          byEvent: {
            'missed': {day},
          },
        );
      });

      test('a hidden missed event cannot claim the wash', () {
        const hidden = EventCellTintProvider(
          priority: CellTintResolver.winnerPriority,
          missedDisplay: CalendarMissedDisplay.hidden,
        );
        const keptColor = 0xFF00FF00;
        final events = [
          event('missed', priority: 1, tracksPresence: true),
          event('kept', priority: 5, colorValue: keptColor),
        ];

        final layer = hidden.tintFor(day, events)!;

        expect(layer.wash.r, const Color(keptColor).r);
        expect(layer.wash.g, const Color(keptColor).g);
      });

      test(
        'a hidden missed event on an otherwise empty day yields nothing',
        () {
          const hidden = EventCellTintProvider(
            priority: CellTintResolver.winnerPriority,
            missedDisplay: CalendarMissedDisplay.hidden,
          );

          expect(
            hidden.tintFor(day, [event('missed', tracksPresence: true)]),
            isNull,
          );
        },
      );

      test('a faded missed event keeps the wash but loses strength', () {
        final missed = provider.tintFor(day, [
          event('missed', tracksPresence: true),
        ])!;
        final present = provider.tintFor(day, [event('present')])!;

        expect(missed.wash.a, lessThan(present.wash.a));
        expect(
          missed.wash.a,
          closeTo(present.wash.a * CalendarColors.missedEventAlpha, 0.005),
        );
      });

      test('an untracked event on a marked day is unaffected', () {
        final layer = provider.tintFor(day, [event('missed')])!;

        expect(
          layer.wash.a,
          closeTo(CalendarColors.eventTintAlphaByPriority[2], 0.01),
        );
      });
    });
  });

  group('CellTintResolver layering', () {
    CellTintLayer layer(String key, int priority) => CellTintLayer(
      key: key,
      wash: const Color(0x11223344),
      edge: const Color(0x55667788),
      priority: priority,
    );

    test('the lowest band takes the wash', () {
      final resolver = CellTintResolver(
        providers: [
          _FixedProvider(layer('b', 100)),
          _FixedProvider(layer('a', 0)),
        ],
      );

      expect(resolver.resolve(day, const []).wash, layer('a', 0).wash);
    });

    test('the runner-up is dropped unless layering is on', () {
      final resolver = CellTintResolver(
        providers: [
          _FixedProvider(layer('a', 0)),
          _FixedProvider(layer('b', 100)),
        ],
      );

      expect(resolver.resolve(day, const []).edge, isNull);
    });

    test('layering gives the runner-up the edge stripe', () {
      final resolver = CellTintResolver(
        providers: [
          _FixedProvider(layer('a', 0)),
          _FixedProvider(layer('b', 100)),
        ],
        layerRunnerUp: true,
      );

      expect(resolver.resolve(day, const []).edge, layer('b', 100).edge);
    });

    test('no contributing source yields the empty tint', () {
      const resolver = CellTintResolver(providers: []);

      expect(resolver.resolve(day, const []), DayCellTint.empty);
    });
  });

  group('CellTintResolver.defaults', () {
    test('with the tint off no event provider exists at all', () {
      final resolver = CellTintResolver.defaults(const CalendarAppearance());

      expect(resolver.providers, hasLength(1));
      expect(resolver.providers.single, isA<FastingCellTintProvider>());
      expect(resolver.layerRunnerUp, isFalse);
    });

    /// The grid filter's fasting layer composes the fasting provider out —
    /// which is also what takes the day rail's base band with it, since that
    /// band *is* the runner-up wash.
    test('the fasting layer composes the fasting provider out', () {
      final resolver = CellTintResolver.defaults(
        const CalendarAppearance(eventTint: true),
        showFasting: false,
      );

      expect(resolver.providers.whereType<FastingCellTintProvider>(), isEmpty);
      expect(resolver.providers.whereType<EventCellTintProvider>(), hasLength(1));
    });

    /// With the event wash off too there is no source left, so the resolver
    /// collapses to the canonical empty one rather than an instance holding an
    /// empty provider list.
    test('no event tint and no fasting layer leaves nothing to resolve', () {
      final resolver = CellTintResolver.defaults(
        const CalendarAppearance(),
        showFasting: false,
      );

      expect(resolver.providers, isEmpty);
      expect(resolver.resolve(day, const []), DayCellTint.empty);
    });

    /// The lone survivor still wins its own band: `resolve` picks the lowest
    /// priority *present*, not an absolute one, so composing out the provider
    /// that held `winnerPriority` must not leave the cell unwashed.
    test('fastingWins with the layer off still washes the event', () {
      final resolver = CellTintResolver.defaults(
        const CalendarAppearance(
          eventTint: true,
          tintConflict: CalendarTintConflict.fastingWins,
        ),
        showFasting: false,
      );

      expect(
        resolver.providers.whereType<EventCellTintProvider>().single.priority,
        CellTintResolver.runnerUpPriority,
      );
    });

    test('eventWins puts the event in the winning band', () {
      final resolver = CellTintResolver.defaults(
        const CalendarAppearance(eventTint: true),
      );
      final events = resolver.providers.whereType<EventCellTintProvider>();
      final fasting = resolver.providers.whereType<FastingCellTintProvider>();

      expect(events.single.priority, CellTintResolver.winnerPriority);
      expect(fasting.single.priority, CellTintResolver.runnerUpPriority);
      expect(resolver.layerRunnerUp, isFalse);
    });

    test('fastingWins flips the bands', () {
      final resolver = CellTintResolver.defaults(
        const CalendarAppearance(
          eventTint: true,
          tintConflict: CalendarTintConflict.fastingWins,
        ),
      );

      expect(
        resolver.providers.whereType<EventCellTintProvider>().single.priority,
        CellTintResolver.runnerUpPriority,
      );
      expect(
        resolver.providers.whereType<FastingCellTintProvider>().single.priority,
        CellTintResolver.winnerPriority,
      );
    });

    test('both keeps the event on top and turns layering on', () {
      final resolver = CellTintResolver.defaults(
        const CalendarAppearance(
          eventTint: true,
          tintConflict: CalendarTintConflict.both,
        ),
      );

      expect(
        resolver.providers.whereType<EventCellTintProvider>().single.priority,
        CellTintResolver.winnerPriority,
      );
      expect(resolver.layerRunnerUp, isTrue);
    });

    test('the missed-display setting reaches the event provider', () {
      final resolver = CellTintResolver.defaults(
        const CalendarAppearance(
          eventTint: true,
          missedDisplay: CalendarMissedDisplay.hidden,
        ),
      );

      expect(
        resolver.providers
            .whereType<EventCellTintProvider>()
            .single
            .missedDisplay,
        CalendarMissedDisplay.hidden,
      );
    });
  });
}

class _FixedProvider implements CellTintProvider {
  final CellTintLayer layer;

  const _FixedProvider(this.layer);

  @override
  CellTintLayer? tintFor(DateTime day, List<CalendarEvent> events) => layer;
}
