import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/utils/event_search_query.dart';

/// Unit tests for the agenda's query parser. Pure: no widget tree, no
/// database, no localizations delegate — only the locale name the view already
/// hands down, which is all the month-name lookup needs.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  final anyDay = DateTime.utc(2026, 3, 17);

  bool hits(EventSearchQuery query, String text, [DateTime? day]) =>
      query.matchesText(text, day ?? anyDay);

  group('empty query', () {
    test('an empty string parses to the shared empty instance', () {
      expect(
        identical(EventSearchQuery.parse(''), EventSearchQuery.empty),
        isTrue,
      );
      expect(EventSearchQuery.parse('').isEmpty, isTrue);
    });

    test('whitespace only is still empty', () {
      final query = EventSearchQuery.parse('   \t  ');
      expect(query.isEmpty, isTrue);
      expect(query.isNotEmpty, isFalse);
    });

    test('an empty query matches everything and allocates no terms', () {
      final query = EventSearchQuery.parse('');
      expect(query.terms, isEmpty);
      expect(query.clauses, isEmpty);
      expect(query.maskOf('anything at all'), 0);
      expect(query.satisfied(0, anyDay), isTrue);
      expect(query.couldSatisfy(0), isTrue);
      expect(query.hasDateClauses, isFalse);
    });
  });

  group('single term', () {
    test('matches as a substring', () {
      final query = EventSearchQuery.parse('squat');
      expect(hits(query, 'Barbell squat programme'), isTrue);
      expect(hits(query, 'Deadlift day'), isFalse);
    });

    test('folds case', () {
      final query = EventSearchQuery.parse('SQUAT');
      expect(hits(query, 'barbell Squat'), isTrue);
    });

    test('folds diacritics both ways', () {
      final query = EventSearchQuery.parse('sarbatoare');
      expect(hits(query, 'Sărbătoare de vară'), isTrue);

      final accented = EventSearchQuery.parse('Sărbătoare');
      expect(hits(accented, 'sarbatoare'), isTrue);
    });
  });

  group('multi-term AND', () {
    test('every term must match, in any order and any field', () {
      final query = EventSearchQuery.parse('leg day');
      expect(query.terms, ['leg', 'day']);

      expect(hits(query, 'Leg day'), isTrue);
      expect(hits(query, 'day of the leg'), isTrue);
      expect(hits(query, 'Leg press'), isFalse);
      expect(hits(query, 'Rest day'), isFalse);
    });

    test('terms may be satisfied by different fields', () {
      final query = EventSearchQuery.parse('leg gym');
      final mask = query.maskOf('Leg day') | query.maskOf('Gym');
      expect(query.satisfied(mask, anyDay), isTrue);
      expect(query.satisfied(query.maskOf('Leg day'), anyDay), isFalse);
    });

    test('extra whitespace is collapsed, not turned into empty terms', () {
      final query = EventSearchQuery.parse('  leg \t\n  day  ');
      expect(query.terms, ['leg', 'day']);
      expect(query.clauses, hasLength(2));
      expect(hits(query, 'leg day'), isTrue);
    });

    test('a repeated word is one term, not two constraints', () {
      final query = EventSearchQuery.parse('leg leg');
      expect(query.terms, ['leg']);
      expect(hits(query, 'leg day'), isTrue);
    });

    test('a single-term query is unchanged by the AND machinery', () {
      final query = EventSearchQuery.parse('gym');
      expect(query.clauses, hasLength(1));
      expect(query.hasDateClauses, isFalse);
    });
  });

  group('date terms - English', () {
    test('a month name alone selects that month, any year', () {
      final query = EventSearchQuery.parse('august');
      expect(query.hasDateClauses, isTrue);
      expect(hits(query, 'Nothing relevant', DateTime.utc(2026, 8, 3)), isTrue);
      expect(hits(query, 'Nothing relevant', DateTime.utc(2027, 8, 31)), isTrue);
      expect(hits(query, 'Nothing relevant', DateTime.utc(2026, 9, 1)), isFalse);
    });

    test('an abbreviated month works too', () {
      final query = EventSearchQuery.parse('aug');
      expect(query.hasDateClauses, isTrue);
      expect(hits(query, 'x', DateTime.utc(2026, 8, 3)), isTrue);
      expect(hits(query, 'x', DateTime.utc(2026, 7, 3)), isFalse);
    });

    test('month then day pins the day of month', () {
      final query = EventSearchQuery.parse('aug 26');
      expect(query.hasDateClauses, isTrue);
      expect(query.clauses, hasLength(1));
      expect(hits(query, 'x', DateTime.utc(2026, 8, 26)), isTrue);
      expect(hits(query, 'x', DateTime.utc(2026, 8, 25)), isFalse);
      expect(hits(query, 'x', DateTime.utc(2026, 9, 26)), isFalse);
    });

    test('day then month is the same clause', () {
      final query = EventSearchQuery.parse('26 aug');
      expect(query.clauses, hasLength(1));
      expect(hits(query, 'x', DateTime.utc(2026, 8, 26)), isTrue);
      expect(hits(query, 'x', DateTime.utc(2026, 8, 25)), isFalse);
    });

    test('a date clause is still satisfiable by text', () {
      final query = EventSearchQuery.parse('aug 26');
      expect(hits(query, 'Aug 26 planning', DateTime.utc(2026, 1, 2)), isTrue);
      expect(hits(query, 'Aug planning', DateTime.utc(2026, 1, 2)), isFalse);
    });

    test('an ISO date pins the year too', () {
      final query = EventSearchQuery.parse('2026-08-26');
      expect(query.hasDateClauses, isTrue);
      expect(hits(query, 'x', DateTime.utc(2026, 8, 26)), isTrue);
      expect(hits(query, 'x', DateTime.utc(2025, 8, 26)), isFalse);
    });

    test('a date term ANDs with a text term', () {
      final query = EventSearchQuery.parse('gym aug 26');
      expect(query.clauses, hasLength(2));
      expect(hits(query, 'Gym session', DateTime.utc(2026, 8, 26)), isTrue);
      expect(hits(query, 'Gym session', DateTime.utc(2026, 8, 25)), isFalse);
      expect(hits(query, 'Yoga', DateTime.utc(2026, 8, 26)), isFalse);
    });
  });

  group('date terms - German', () {
    test('a German month name resolves', () {
      final query = EventSearchQuery.parse('dezember', localeName: 'de');
      expect(query.hasDateClauses, isTrue);
      expect(hits(query, 'x', DateTime.utc(2026, 12, 4)), isTrue);
      expect(hits(query, 'x', DateTime.utc(2026, 11, 4)), isFalse);
    });

    test('a diacritic month name resolves folded', () {
      final query = EventSearchQuery.parse('marz', localeName: 'de');
      expect(hits(query, 'x', DateTime.utc(2026, 3, 4)), isTrue);
      expect(hits(query, 'x', DateTime.utc(2026, 5, 4)), isFalse);
    });

    test('the German trailing-dot day form parses', () {
      final query = EventSearchQuery.parse('26. august', localeName: 'de');
      expect(query.clauses, hasLength(1));
      expect(hits(query, 'x', DateTime.utc(2026, 8, 26)), isTrue);
      expect(hits(query, 'x', DateTime.utc(2026, 8, 27)), isFalse);
    });

    test('an English month name is not a date in the German locale', () {
      final query = EventSearchQuery.parse('march', localeName: 'de');
      expect(query.hasDateClauses, isFalse);
    });
  });

  group('date terms - Romanian', () {
    test('a Romanian month name resolves', () {
      final query = EventSearchQuery.parse('septembrie', localeName: 'ro');
      expect(query.hasDateClauses, isTrue);
      expect(hits(query, 'x', DateTime.utc(2026, 9, 9)), isTrue);
      expect(hits(query, 'x', DateTime.utc(2026, 10, 9)), isFalse);
    });

    test('the abbreviated form keeps working past the trailing dot', () {
      final query = EventSearchQuery.parse('iun 3', localeName: 'ro');
      expect(query.clauses, hasLength(1));
      expect(hits(query, 'x', DateTime.utc(2026, 6, 3)), isTrue);
      expect(hits(query, 'x', DateTime.utc(2026, 6, 4)), isFalse);
    });

    test('an ambiguous prefix stays plain text', () {
      final query = EventSearchQuery.parse('ma', localeName: 'ro');
      expect(query.hasDateClauses, isFalse);
    });
  });

  group('garbage never parses as a date', () {
    void expectTextOnly(String raw, {String? localeName}) {
      final query = EventSearchQuery.parse(raw, localeName: localeName);
      expect(
        query.hasDateClauses,
        isFalse,
        reason: '$raw must not be read as a date',
      );
    }

    test('a bare number is not a day of month', () => expectTextOnly('26'));
    test('a bare year is not a date', () => expectTextOnly('2026'));
    test('a plain word is not a date', () => expectTextOnly('deadlift'));
    test('a two-letter fragment is not a month', () => expectTextOnly('au'));
    test('an impossible ISO month', () => expectTextOnly('2026-13-01'));
    test('an impossible ISO day', () => expectTextOnly('2026-02-30'));
    test('a rolled-over ISO day', () => expectTextOnly('2026-04-31'));
    test('a slashed date is not supported', () => expectTextOnly('26/08/2026'));

    test('an impossible day for a real month drops the pairing', () {
      final query = EventSearchQuery.parse('feb 30');
      expect(query.hasDateClauses, isTrue);
      expect(query.clauses, hasLength(2));
      expect(hits(query, 'x', DateTime.utc(2026, 2, 3)), isFalse);
      expect(hits(query, '30 reps', DateTime.utc(2026, 2, 3)), isTrue);
    });

    test('a day beyond any month is text on both halves', () {
      final query = EventSearchQuery.parse('aug 44');
      expect(query.clauses, hasLength(2));
      expect(hits(query, 'x', DateTime.utc(2026, 8, 3)), isFalse);
      expect(hits(query, '44 laps', DateTime.utc(2026, 8, 3)), isTrue);
    });

    test('an unparseable locale falls back to no month names', () {
      final query = EventSearchQuery.parse(
        'august',
        localeName: 'zz_NOT_A_LOCALE',
      );
      expect(query.hasDateClauses, isFalse);
      expect(hits(query, 'August picnic'), isTrue);
    });
  });

  group('mask helpers', () {
    test('couldSatisfy treats a date clause as still open', () {
      final query = EventSearchQuery.parse('gym aug 26');
      expect(query.couldSatisfy(query.maskOf('Gym session')), isTrue);
      expect(query.couldSatisfy(query.maskOf('Yoga')), isFalse);
    });

    test('maskOf ignores null and empty text', () {
      final query = EventSearchQuery.parse('gym');
      expect(query.maskOf(null), 0);
      expect(query.maskOf(''), 0);
    });
  });
}
