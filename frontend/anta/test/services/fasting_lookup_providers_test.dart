import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/constants/fasting_calendar.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/services/cell_tint_resolver.dart';
import 'package:anta/services/day_bars_resolver.dart';
import 'package:anta/services/day_summary_resolver.dart';

/// A lookup over a fixed day map and look, as the guide's fasting card
/// passes one.
class _FixedLookup extends FastingLookup {
  _FixedLookup(this.days, this.appearance);

  final Map<DateTime, List<FastingInfo>> days;

  @override
  final FastingAppearance appearance;

  @override
  List<FastingInfo> on(DateTime day) =>
      days[DateTime.utc(day.year, day.month, day.day)] ?? const [];
}

/// The three fasting providers' read seam (D62): given a lookup they read
/// its days and its look and never the configured facade; without one they
/// read the facade as before.
void main() {
  final en = AppLocalizationsEn();
  // A Wednesday: no weekend row or bar to tell apart.
  final day = DateTime.utc(2027, 3, 17);
  const lookupColor = 0xFF43A047;
  const facadeColor = 0xFFE53935;

  // The facade marks the day Catholic, washed red.
  setUp(() {
    FastingCalendar.configure(
      traditions: const {FastingTradition.catholic},
      appearance: const FastingAppearance().withStyle(
        FastingTradition.catholic,
        const FastingTraditionStyle(colorValue: facadeColor),
      ),
    );
    expect(FastingCalendar.on(day), isNotEmpty);
  });
  tearDown(FastingCalendar.resetConfiguration);

  _FixedLookup orthodox(FastingDisplayStyle style) => _FixedLookup(
    {
      day: const [
        FastingInfo(
          FastingTradition.orthodox,
          FastingPeriod.greatLent,
          FastingRegime.strict,
        ),
      ],
    },
    const FastingAppearance().withStyle(
      FastingTradition.orthodox,
      FastingTraditionStyle(style: style, colorValue: lookupColor),
    ),
  );

  test('the summary row is the lookup\'s fast in the lookup\'s look', () {
    final revision = FastingCalendar.revision;
    final entries = FastingSummaryProvider(
      en,
      lookup: orthodox(FastingDisplayStyle.tint),
    ).summaryFor(day, const []).toList();

    expect(entries, hasLength(1));
    expect(entries.single.key, 'fasting:orthodox');
    expect(entries.single.title, en.fastingGreatLent);
    expect(entries.single.subtitle, en.fastingRegimeStrict);
    expect(entries.single.color, const Color(lookupColor));
    expect(
      entries.single.icon,
      FastingCalendar.defaultIconOf(FastingTradition.orthodox),
    );
    expect(FastingCalendar.revision, revision);

    // No lookup: the facade's Catholic row, as every calendar surface reads.
    final facade = FastingSummaryProvider(en).summaryFor(day, const []);
    expect(facade.single.key, 'fasting:catholic');
    expect(facade.single.color, const Color(facadeColor));
  });

  test('the bar is the lookup\'s, only for its bar style', () {
    final bars = FastingDayBarProvider(
      en,
      lookup: orthodox(FastingDisplayStyle.bar),
    ).barsFor(day, const []).toList();
    expect(bars.single.key, 'fasting:orthodox');
    expect(bars.single.color, const Color(lookupColor));
    expect(bars.single.semanticLabel, en.fastingGreatLent);

    expect(
      FastingDayBarProvider(
        en,
        lookup: orthodox(FastingDisplayStyle.tint),
      ).barsFor(day, const []),
      isEmpty,
    );
    // The facade's Catholic tint draws no bar either.
    expect(FastingDayBarProvider(en).barsFor(day, const []), isEmpty);
  });

  test('the wash is the lookup\'s, never the facade\'s memo', () {
    final tinted = FastingCellTintProvider(
      priority: CellTintResolver.winnerPriority,
      lookup: orthodox(FastingDisplayStyle.tint),
    ).tintFor(day, const []);
    expect(
      tinted?.wash,
      const Color(
        lookupColor,
      ).withValues(alpha: CalendarColors.fastingTintAlpha),
    );

    // A lookup that marks nothing washes nothing, whatever the facade says.
    expect(
      FastingCellTintProvider(
        priority: CellTintResolver.winnerPriority,
        lookup: _FixedLookup(const {}, const FastingAppearance()),
      ).tintFor(day, const []),
      isNull,
    );
    expect(
      FastingCellTintProvider(
        priority: CellTintResolver.winnerPriority,
      ).tintFor(day, const [])?.wash,
      const Color(
        facadeColor,
      ).withValues(alpha: CalendarColors.fastingTintAlpha),
    );
  });

  // The factories every calendar surface builds through carry the lookup to
  // their fasting provider; without one they build what they always built.
  group('the defaults factories', () {
    test('DayBarsResolver.defaults', () {
      final lookup = orthodox(FastingDisplayStyle.bar);
      final resolver = DayBarsResolver.defaults(en, fastingLookup: lookup);
      expect(
        resolver.providers.whereType<FastingDayBarProvider>().single.lookup,
        same(lookup),
      );
      expect(
        resolver.resolve(day, const []).map((bar) => bar.key),
        contains('fasting:orthodox'),
      );
      expect(
        DayBarsResolver.defaults(
          en,
        ).providers.whereType<FastingDayBarProvider>().single.lookup,
        isNull,
      );
    });

    test('DaySummaryResolver.defaults', () {
      final lookup = orthodox(FastingDisplayStyle.tint);
      final resolver = DaySummaryResolver.defaults(en, fastingLookup: lookup);
      expect(
        resolver.providers.whereType<FastingSummaryProvider>().single.lookup,
        same(lookup),
      );
      expect(resolver.resolve(day, const []).map((entry) => entry.key), [
        'fasting:orthodox',
      ]);
      expect(
        DaySummaryResolver.defaults(
          en,
        ).providers.whereType<FastingSummaryProvider>().single.lookup,
        isNull,
      );
    });

    for (final eventTint in [false, true]) {
      test('CellTintResolver.defaults, event tint $eventTint', () {
        final lookup = orthodox(FastingDisplayStyle.tint);
        final appearance = CalendarAppearance(eventTint: eventTint);
        final resolver = CellTintResolver.defaults(
          appearance,
          fastingLookup: lookup,
        );
        expect(
          resolver.providers.whereType<FastingCellTintProvider>().single.lookup,
          same(lookup),
        );
        expect(
          resolver.resolve(day, const []).wash,
          const Color(
            lookupColor,
          ).withValues(alpha: CalendarColors.fastingTintAlpha),
        );
        expect(
          CellTintResolver.defaults(
            appearance,
          ).providers.whereType<FastingCellTintProvider>().single.lookup,
          isNull,
        );
      });
    }
  });
}
