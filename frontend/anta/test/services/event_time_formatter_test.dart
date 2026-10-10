import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/services/event_time_formatter.dart';

/// `formatRangeFor` is `formatRangeOfContext` for a caller with no context:
/// an alert's labels are written by a scheduler, and the line they put on a
/// notification has to be the line the event's own detail sheet shows.
///
/// The two are different code — Material's formatter can only be had from a
/// widget tree, so the context-free one restates its rule over `intl` — and
/// this suite is what holds them to one string. It walks every language the
/// app ships, so a language added later whose Material clock the restatement
/// does not reproduce fails here.
///
/// **The date tables are the running app's** from the first case on:
/// `intl`'s, as `main()` loads them, then Flutter's over them, as the app's
/// first `MaterialApp` does. Left to the widget cases, the context-free
/// formatter read Flutter's tables only once some case had pumped an app,
/// and `intl`'s in a case run by its name alone — tables from another
/// `intl` on each of the owner's machines.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    for (final locale in AppLocalizations.supportedLocales) {
      await GlobalMaterialLocalizations.delegate.load(locale);
    }
  });

  const times = <String, EventTime>{
    'a morning point': EventTime(startMinute: 7 * 60 + 5),
    'noon': EventTime(startMinute: 12 * 60),
    'just past midnight': EventTime(startMinute: 5),
    'an evening range': EventTime(startMinute: 18 * 60, durationMinutes: 90),
    'a range over noon': EventTime(
      startMinute: 11 * 60 + 30,
      durationMinutes: 60,
    ),
    'a range past midnight': EventTime(
      startMinute: 23 * 60 + 30,
      durationMinutes: 90,
    ),
  };

  /// What a widget under [locale], on a phone with the 24-hour switch as
  /// given, writes for [time].
  Future<String> ofContext(
    WidgetTester tester, {
    required Locale locale,
    required bool use24Hour,
    required EventTime time,
  }) async {
    late String written;
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(alwaysUse24HourFormat: use24Hour),
            child: Builder(
              builder: (inner) {
                written = EventTimeFormatter.formatRangeOfContext(time, inner);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return written;
  }

  for (final locale in AppLocalizations.supportedLocales) {
    for (final use24Hour in [true, false]) {
      final clock = use24Hour ? '24-hour' : 'the language\'s own clock';

      testWidgets('$locale on $clock: with and without a context agree', (
        tester,
      ) async {
        for (final entry in times.entries) {
          final expected = await ofContext(
            tester,
            locale: locale,
            use24Hour: use24Hour,
            time: entry.value,
          );

          expect(
            EventTimeFormatter.formatRangeFor(
              entry.value,
              localeName: locale.toString(),
              use24Hour: use24Hour,
            ),
            expected,
            reason: entry.key,
          );
        }
      });
    }
  }

  test('the strings themselves, so agreement is not two wrong answers', () {
    const session = EventTime(startMinute: 18 * 60, durationMinutes: 90);

    expect(
      EventTimeFormatter.formatRangeFor(
        session,
        localeName: 'en',
        use24Hour: false,
      ),
      '6:00 PM – 7:30 PM',
    );
    expect(
      EventTimeFormatter.formatRangeFor(
        session,
        localeName: 'en',
        use24Hour: true,
      ),
      '18:00 – 19:30',
    );
    expect(
      EventTimeFormatter.formatRangeFor(
        session,
        localeName: 'de',
        use24Hour: false,
      ),
      '18:00 – 19:30',
    );
    expect(
      EventTimeFormatter.formatMinuteFor(
        7 * 60 + 5,
        localeName: 'ro',
        use24Hour: false,
      ),
      '07:05',
    );
    // A minute past the day wraps, as the context formatter's does.
    expect(
      EventTimeFormatter.formatMinuteFor(
        24 * 60 + 5,
        localeName: 'en',
        use24Hour: true,
      ),
      '00:05',
    );
  });

  test('the neutral range is unchanged by the shared grammar', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(
      EventTimeFormatter.formatRange(
        const EventTime(startMinute: 9 * 60 + 30),
        l10n,
      ),
      '09:30',
    );
    expect(
      EventTimeFormatter.formatRange(
        const EventTime(startMinute: 9 * 60 + 30, durationMinutes: 60),
        l10n,
      ),
      '09:30 – 10:30',
    );
    expect(
      EventTimeFormatter.formatRange(
        const EventTime(startMinute: 23 * 60 + 30, durationMinutes: 60),
        l10n,
      ),
      '23:30 – 00:30 (+1)',
    );
  });
}
