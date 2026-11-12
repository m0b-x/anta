import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/day_bar.dart';
import 'package:anta/models/partner_look.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/services/day_bars_resolver.dart';
import 'package:anta/utils/marker_contrast.dart';
import 'package:anta/widgets/calendar_day_bars.dart';

/// A partner's event on the month grid (`docs/cloud-share-surfaces-roadmap.md`
/// §6.7): under the Outlined look its marker is the hollow twin of a filled
/// one — the same box, the ring alone, the ring's colour lifted to 3:1 on the
/// ground it actually sits on — and in every look the strip's one label says
/// whose it is. My own markers are untouched.
void main() {
  const yellow = Color(0xFFFDD835);
  const blue = Color(0xFF1E88E5);

  DayBar bar(String key, Color color, {bool hollow = false}) => DayBar(
    key: key,
    color: color,
    priority: 0,
    semanticLabel: key,
    hollow: hollow,
  );

  Future<void> pump(
    WidgetTester tester, {
    required List<DayBar> bars,
    CalendarMarkerStyle style = CalendarMarkerStyle.bars,
    ColorScheme scheme = AppTheme.lightScheme,
    Color? ground,
    double opacity = 1.0,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme, useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 48,
              child: CalendarDayBars(
                bars: bars,
                style: style,
                ground: ground,
                opacity: opacity,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The marker boxes in strip order — every decorated `Container`.
  List<Element> markers(WidgetTester tester) => find
      .byWidgetPredicate((w) => w is Container && w.decoration != null)
      .evaluate()
      .toList();

  BoxDecoration decorationOf(Element element) =>
      (element.widget as Container).decoration! as BoxDecoration;

  for (final style in CalendarMarkerStyle.values) {
    group(style.name, () {
      final stroke = style == CalendarMarkerStyle.dots
          ? CalendarDayBars.hollowDotStroke
          : CalendarDayBars.hollowBarStroke;

      testWidgets('the hollow twin takes the filled marker\'s box, with no '
          'fill and no hairline', (tester) async {
        await pump(
          tester,
          style: style,
          bars: [bar('mine', yellow), bar('theirs', yellow, hollow: true)],
        );

        final [filled, hollow] = markers(tester);
        expect(
          (hollow.renderObject! as RenderBox).size,
          (filled.renderObject! as RenderBox).size,
        );
        final ring = decorationOf(hollow);
        expect(ring.color, isNull);
        final side = (ring.border! as Border).top;
        expect(side.width, stroke);
        expect(side.strokeAlign, BorderSide.strokeAlignInside);
        expect(ring.shape, decorationOf(filled).shape);
        expect(ring.borderRadius, decorationOf(filled).borderRadius);
      });

      testWidgets('my filled marker is drawn exactly as before', (
        tester,
      ) async {
        await pump(tester, style: style, bars: [bar('mine', yellow)]);

        final filled = decorationOf(markers(tester).single);
        expect(filled.color, yellow);
      });

      for (final (name, scheme) in [
        ('light', AppTheme.lightScheme),
        ('dark', AppTheme.darkScheme),
      ]) {
        for (final cellStyle in CalendarCellStyle.values) {
          testWidgets('$name, a cell washed under ${cellStyle.name}: the ring '
              'reaches 3:1 on the composite ground', (tester) async {
            // My blue event at P1's wash under the partner's yellow.
            final ground = CalendarDayBars.groundOn(
              scheme.surface,
              blue.withValues(alpha: 0.28),
              cellStyle,
            );
            await pump(
              tester,
              style: style,
              scheme: scheme,
              ground: ground,
              bars: [bar('theirs', yellow, hollow: true)],
            );

            final side =
                (decorationOf(markers(tester).single).border! as Border).top;
            expect(
              MarkerContrast.contrastRatio(
                side.color.computeLuminance(),
                ground.computeLuminance(),
              ),
              greaterThanOrEqualTo(MarkerContrast.hollowMinContrastRatio),
            );
          });
        }
      }

      testWidgets('an outside-month ring fades like every other mark', (
        tester,
      ) async {
        const alpha = 0.35;
        await pump(
          tester,
          style: style,
          opacity: alpha,
          bars: [bar('theirs', yellow, hollow: true)],
        );

        final side =
            (decorationOf(markers(tester).single).border! as Border).top;
        final full = MarkerContrast.atLeast(
          yellow,
          AppTheme.lightScheme.surface,
        );
        expect(side.color, full.withValues(alpha: full.a * alpha));
      });
    });
  }

  test('a cell\'s ground is its wash as the cell paints it, over the '
      'surface', () {
    const surface = Color(0xFFFEF7FF);
    final wash = blue.withValues(alpha: 0.28);
    expect(
      CalendarDayBars.groundOn(surface, null, CalendarCellStyle.solid),
      surface,
    );
    expect(
      CalendarDayBars.groundOn(surface, wash, CalendarCellStyle.solid),
      Color.alphaBlend(wash, surface),
    );
    expect(
      CalendarDayBars.groundOn(surface, wash, CalendarCellStyle.fade),
      Color.alphaBlend(wash, surface),
    );
    expect(
      CalendarDayBars.groundOn(surface, wash, CalendarCellStyle.outline),
      Color.alphaBlend(
        wash.withValues(alpha: wash.a * CalendarColors.outlineStyleWashScale),
        surface,
      ),
    );
  });

  group('EventDayBarProvider', () {
    final l10n = AppLocalizationsEn();
    final day = DateTime.utc(2026, 11, 12);

    CalendarEvent event(String id, {bool fromPartner = false}) => CalendarEvent(
      id: id,
      title: id == 'mine' ? 'Leg day' : 'Night shift',
      categoryId: 'work',
      startDate: day,
      colorValue: yellow.toARGB32(),
      fromPartner: fromPartner,
    );

    final events = [event('mine'), event('theirs', fromPartner: true)];

    for (final look in ShareEventLook.values) {
      test('${look.name}: a partner\'s bar says whose it is; only Outlined '
          'draws it hollow; mine is unchanged', () {
        final bars = DayBarsResolver.defaults(
          l10n,
          showHolidays: false,
          showFasting: false,
          showMoney: false,
          partner: PartnerLook(
            look: look,
            partner: const AppUser(uid: 'maria'),
            name: 'Maria',
          ),
        ).resolve(day, events).where((bar) => bar.key.startsWith('event'));

        final [mine, theirs] = bars.toList();
        expect(mine.semanticLabel, 'Leg day');
        expect(mine.hollow, isFalse);
        expect(theirs.semanticLabel, 'Night shift, From Maria');
        expect(theirs.hollow, look == ShareEventLook.outlined);
      });
    }

    test('without a partner look every bar is drawn and named as before', () {
      final bars = const EventDayBarProvider().barsFor(day, events).toList();
      expect(bars.map((bar) => bar.semanticLabel), ['Leg day', 'Night shift']);
      expect(bars.any((bar) => bar.hollow), isFalse);
    });
  });

  testWidgets('the strip stays one node and reads the partner\'s words', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      bars: [
        bar('Leg day', blue),
        DayBar(
          key: 'event:theirs',
          color: yellow,
          priority: 1,
          semanticLabel: 'Night shift, From Maria',
          hollow: true,
        ),
      ],
    );

    expect(
      find.bySemanticsLabel('Leg day, Night shift, From Maria'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
