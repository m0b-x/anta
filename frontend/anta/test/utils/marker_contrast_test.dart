import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/utils/marker_contrast.dart';
import 'package:anta/widgets/calendar_day_bars.dart';

/// `MarkerContrast.atLeast`, the one rule a partner's outlined avatar and
/// hollow grid markers are drawn by (`docs/cloud-share-surfaces-roadmap.md`
/// §6.7): every colour the app ships reaches the graphics floor on every
/// ground it is drawn on, and a colour that already does is left alone.
void main() {
  final palette = <Color>{
    for (final value in CalendarColors.swatchPalette) Color(value),
    for (final seed in CalendarCategories.builtInSeeds) Color(seed.colorValue),
  };

  double ratio(Color a, Color b) =>
      MarkerContrast.contrastRatio(a.computeLuminance(), b.computeLuminance());

  /// What the screen shows of [color]: 8 bits a channel.
  Color painted(Color color) => Color(color.toARGB32());

  const schemes = {'light': AppTheme.lightScheme, 'dark': AppTheme.darkScheme};

  test('amber on a light cell washed grey at P5 reaches 3:1 as painted', () {
    // The design review's measured 2.99:1 (solid, light).
    final ground = CalendarDayBars.groundOn(
      AppTheme.lightScheme.surface,
      const Color(0xFF757575).withValues(alpha: 0.08),
      CalendarCellStyle.solid,
    );
    final drawn = MarkerContrast.atLeast(const Color(0xFFFFA000), ground);
    expect(
      ratio(painted(drawn), painted(ground)),
      greaterThanOrEqualTo(MarkerContrast.hollowMinContrastRatio),
      reason: 'drew $drawn on $ground',
    );
  });

  for (final MapEntry(key: theme, value: scheme) in schemes.entries) {
    final grounds = {'rowGroup': scheme.rowGroup, 'surface': scheme.surface};
    for (final MapEntry(key: name, value: ground) in grounds.entries) {
      test('every palette colour reaches 3:1 on the $theme $name', () {
        for (final color in palette) {
          final drawn = MarkerContrast.atLeast(color, ground);
          expect(
            ratio(drawn, ground),
            greaterThanOrEqualTo(MarkerContrast.hollowMinContrastRatio),
            reason: '$color on $ground drew $drawn',
          );
        }
      });
    }

    test('every palette colour reaches 3:1 on a $theme cell washed by any '
        'of my colours at every priority, under every cell style', () {
      for (final alpha in CalendarColors.eventTintAlphaByPriority) {
        for (final mine in palette) {
          final wash = mine.withValues(alpha: alpha);
          for (final style in CalendarCellStyle.values) {
            final ground = CalendarDayBars.groundOn(
              scheme.surface,
              wash,
              style,
            );
            for (final color in palette) {
              final drawn = MarkerContrast.atLeast(color, ground);
              expect(
                ratio(painted(drawn), painted(ground)),
                greaterThanOrEqualTo(MarkerContrast.hollowMinContrastRatio),
                reason:
                    '$color on $ground (${style.name}, $alpha) drew '
                    '$drawn',
              );
            }
          }
        }
      }
    });
  }

  test('a colour that already passes is returned unchanged', () {
    final ground = AppTheme.lightScheme.rowGroup;
    for (final color in palette) {
      if (ratio(color, ground) < MarkerContrast.hollowMinContrastRatio) {
        continue;
      }
      expect(MarkerContrast.atLeast(color, ground), color);
    }
    // And at least one does, so the loop above proved something.
    expect(
      MarkerContrast.atLeast(const Color(0xFF1E88E5), ground),
      const Color(0xFF1E88E5),
    );
  });

  test('a failing colour darkens on a light ground and lightens on a dark '
      'one, as far as the floor and no further', () {
    const yellow = Color(0xFFFDD835);
    final light = MarkerContrast.atLeast(yellow, AppTheme.lightScheme.rowGroup);
    expect(
      HSLColor.fromColor(light).lightness,
      lessThan(HSLColor.fromColor(yellow).lightness),
    );
    // The spec's measured output for the worst light case.
    expect(light, const Color(0xFFA28402));

    const brown = Color(0xFF6D4C41);
    final dark = MarkerContrast.atLeast(brown, AppTheme.darkScheme.rowGroup);
    expect(
      HSLColor.fromColor(dark).lightness,
      greaterThan(HSLColor.fromColor(brown).lightness),
    );
    expect(dark, const Color(0xFF936758));
  });

  test('the answer is the same from the memo and after it turns over', () {
    final ground = AppTheme.darkScheme.rowGroup;
    const indigo = Color(0xFF3949AB);
    final first = MarkerContrast.atLeast(indigo, ground);
    expect(identical(MarkerContrast.atLeast(indigo, ground), first), isTrue);
    // Far more pairs than the cap, so the memo turns over on the way.
    for (var i = 0; i < 500; i++) {
      MarkerContrast.atLeast(Color(0xFF000000 | i), ground);
    }
    expect(
      MarkerContrast.atLeastCacheLength,
      lessThanOrEqualTo(MarkerContrast.atLeastCacheCap),
    );
    expect(MarkerContrast.atLeast(indigo, ground), first);
  });

  test('a pair asked on every frame stays while new pairs come and go', () {
    final ground = AppTheme.lightScheme.surface;
    const indigo = Color(0xFF3949AB);
    final first = MarkerContrast.atLeast(indigo, ground);
    // Three caps' worth of new pairs, the hot pair asked between them as
    // the grid asks it each frame: the least recently used goes first.
    for (var i = 0; i < 3 * MarkerContrast.atLeastCacheCap; i++) {
      MarkerContrast.atLeast(Color(0xFF000000 | i), ground);
      expect(identical(MarkerContrast.atLeast(indigo, ground), first), isTrue);
    }
  });
}
