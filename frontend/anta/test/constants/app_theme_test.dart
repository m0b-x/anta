import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';

/// The palette is the one thing in the app that is *declared* rather than
/// derived, and the reason is that deriving it does not work: every
/// `ColorScheme.fromSeed` run puts `primary` somewhere near `#65558F`–`#68548E`
/// and never on the mock's `#6750A4`. These cases spell the roles out in hex so
/// a well-meant "just seed it" cannot pass.
void main() {
  String hex(Color color) => color
      .toARGB32()
      .toRadixString(16)
      .padLeft(8, '0')
      .substring(2)
      .toUpperCase();

  void expectRoles(ColorScheme scheme, Map<String, String> expected) {
    final roles = <String, Color>{
      'primary': scheme.primary,
      'primaryContainer': scheme.primaryContainer,
      'secondaryContainer': scheme.secondaryContainer,
      'tertiary': scheme.tertiary,
      'error': scheme.error,
      'surface': scheme.surface,
      'surfaceContainerLow': scheme.surfaceContainerLow,
      'surfaceContainer': scheme.surfaceContainer,
      'surfaceContainerHigh': scheme.surfaceContainerHigh,
      'surfaceContainerHighest': scheme.surfaceContainerHighest,
      'onSurface': scheme.onSurface,
      'onSurfaceVariant': scheme.onSurfaceVariant,
      'outline': scheme.outline,
      'outlineVariant': scheme.outlineVariant,
    };
    expect(roles.map((name, color) => MapEntry(name, hex(color))), expected);
  }

  group('AppTheme.lightScheme', () {
    test('carries the Material 3 baseline light roles', () {
      expectRoles(AppTheme.lightScheme, const {
        'primary': '6750A4',
        'primaryContainer': 'EADDFF',
        'secondaryContainer': 'E8DEF8',
        'tertiary': '7D5260',
        'error': 'B3261E',
        'surface': 'FEF7FF',
        'surfaceContainerLow': 'F7F2FA',
        'surfaceContainer': 'F3EDF7',
        'surfaceContainerHigh': 'ECE6F0',
        'surfaceContainerHighest': 'E6E0E9',
        'onSurface': '1D1B20',
        'onSurfaceVariant': '49454F',
        'outline': '79747E',
        'outlineVariant': 'CAC4D0',
      });
    });

    test('is light', () {
      expect(AppTheme.lightScheme.brightness, Brightness.light);
    });
  });

  group('AppTheme.darkScheme', () {
    test('carries the Material 3 baseline dark roles', () {
      expectRoles(AppTheme.darkScheme, const {
        'primary': 'D0BCFF',
        'primaryContainer': '4F378B',
        'secondaryContainer': '4A4458',
        'tertiary': 'EFB8C8',
        'error': 'F2B8B5',
        'surface': '141218',
        'surfaceContainerLow': '1D1B20',
        'surfaceContainer': '211F26',
        'surfaceContainerHigh': '2B2930',
        'surfaceContainerHighest': '36343B',
        'onSurface': 'E6E0E9',
        'onSurfaceVariant': 'CAC4D0',
        'outline': '938F99',
        'outlineVariant': '49454F',
      });
    });

    test('is dark', () {
      expect(AppTheme.darkScheme.brightness, Brightness.dark);
    });
  });

  group('SurfaceRoles', () {
    test('light stacks a surface group on a surfaceContainer ground', () {
      expect(hex(AppTheme.lightScheme.pageGround), 'F3EDF7');
      expect(hex(AppTheme.lightScheme.rowGroup), 'FEF7FF');
    });

    test('dark stacks a surfaceContainer group on a surface ground', () {
      expect(hex(AppTheme.darkScheme.pageGround), '141218');
      expect(hex(AppTheme.darkScheme.rowGroup), '211F26');
    });

    test('the group is one step lighter than the ground in both themes', () {
      for (final scheme in [AppTheme.lightScheme, AppTheme.darkScheme]) {
        expect(
          scheme.rowGroup.computeLuminance(),
          greaterThan(scheme.pageGround.computeLuminance()),
          reason: '${scheme.brightness}',
        );
      }
    });

    test('the divider and the menu surface are the shared tones', () {
      for (final scheme in [AppTheme.lightScheme, AppTheme.darkScheme]) {
        expect(scheme.rowDivider, scheme.surfaceContainerHighest);
        expect(scheme.menuSurface, scheme.surfaceContainerHigh);
      }
    });
  });

  group('AppTheme.light() / AppTheme.dark()', () {
    test('hand the declared scheme straight through', () {
      expect(AppTheme.light().colorScheme, AppTheme.lightScheme);
      expect(AppTheme.dark().colorScheme, AppTheme.darkScheme);
    });

    test('carry the matching brightness', () {
      expect(AppTheme.light().brightness, Brightness.light);
      expect(AppTheme.dark().brightness, Brightness.dark);
    });

    test('put menus on surfaceContainerHigh at radius 12', () {
      for (final (theme, scheme) in [
        (AppTheme.light(), AppTheme.lightScheme),
        (AppTheme.dark(), AppTheme.darkScheme),
      ]) {
        expect(theme.popupMenuTheme.color, scheme.surfaceContainerHigh);
        final shape = theme.popupMenuTheme.shape;
        expect(shape, isA<RoundedRectangleBorder>());
        expect(
          (shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(12),
        );
      }
    });

    test('use Material 3', () {
      expect(AppTheme.light().useMaterial3, isTrue);
      expect(AppTheme.dark().useMaterial3, isTrue);
    });

    test('hand back the identical instance every call', () {
      // `MaterialApp` is rebuilt on every settings emission; a fresh
      // `ThemeData` there invalidates every theme-keyed cache below it.
      expect(identical(AppTheme.light(), AppTheme.light()), isTrue);
      expect(identical(AppTheme.dark(), AppTheme.dark()), isTrue);
    });

    test('carry the mock menu anatomy', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final label = theme.popupMenuTheme.labelTextStyle!.resolve(
          const <WidgetState>{},
        )!;
        expect(label.fontSize, AppTheme.menuLabelSize);
        expect(label.fontWeight, FontWeight.w400);
        expect(label.color, theme.colorScheme.onSurface);
        expect(
          theme.popupMenuTheme.menuPadding,
          const EdgeInsets.symmetric(vertical: AppTheme.menuVerticalPadding),
        );
      }
    });
  });
}
