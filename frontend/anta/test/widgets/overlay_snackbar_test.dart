import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/overlay_snackbar.dart';

/// The overlay bar paints from `ThemeData.snackBarTheme`, the popup menu's
/// surface: until 2026-10-17 it painted `inverseSurface` by hand, a near-white
/// card in the dark theme. Its box still takes taps only on its text and its ✕,
/// so a short sheet's header under it stays reachable.
void main() {
  const message = 'Saved as Weekdays';

  Future<int Function()> pumpAndShow(
    WidgetTester tester,
    ThemeData theme,
  ) async {
    var underTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => underTaps++,
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => OverlaySnackbar.show(context, message),
                    child: const Text('show'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pump();
    return () => underTaps;
  }

  Future<void> takeDown(WidgetTester tester) async {
    OverlaySnackbar.hide();
    await tester.pump();
  }

  Finder bar() => find
      .ancestor(of: find.text(message), matching: find.byType(PhysicalModel))
      .first;

  for (final (name, theme) in [
    ('dark', AppTheme.dark()),
    ('light', AppTheme.light()),
  ]) {
    final scheme = theme.colorScheme;

    group('under the $name theme', () {
      testWidgets('paints the popup menu surface, never inverseSurface', (
        tester,
      ) async {
        await pumpAndShow(tester, theme);

        final model = tester.widget<PhysicalModel>(bar());
        expect(model.color, scheme.surfaceContainerHigh);
        expect(model.color, isNot(scheme.inverseSurface));
        expect(model.elevation, AppTheme.menuElevation);
        // The theme's content style replaces the ambient one, as in a
        // `SnackBar`: height and spacing too, not only the colour.
        final resolved = DefaultTextStyle.of(
          tester.element(find.text(message)),
        ).style;
        expect(resolved, theme.snackBarTheme.contentTextStyle);
        expect(resolved.color, scheme.onSurface);
        // The hairline is the outer transparency's shape.
        final outer = tester.widget<Material>(
          find.ancestor(of: bar(), matching: find.byType(Material)).first,
        );
        expect(
          (outer.shape! as RoundedRectangleBorder).side.color,
          scheme.outlineVariant,
        );

        await takeDown(tester);
      });

      testWidgets('draws the ✕ in onSurfaceVariant with the close tooltip', (
        tester,
      ) async {
        await pumpAndShow(tester, theme);

        expect(
          tester.widget<Icon>(find.byIcon(Icons.close)).color,
          scheme.onSurfaceVariant,
        );
        final close = find.widgetWithIcon(IconButton, Icons.close);
        final l10n = AppLocalizations.of(tester.element(close))!;
        expect(tester.widget<IconButton>(close).tooltip, l10n.close);
        expect(find.byTooltip(l10n.close), findsOneWidget);

        await takeDown(tester);
      });

      testWidgets('lets a tap beside the text reach what lies under the bar', (
        tester,
      ) async {
        final underTaps = await pumpAndShow(tester, theme);

        final box = tester.getRect(bar());
        final text = tester.getRect(find.text(message));
        // Inside the bar's box, in the padding above the text line.
        final beside = Offset(text.center.dx, box.top + 4);
        expect(box.contains(beside), isTrue);
        expect(text.contains(beside), isFalse);

        await tester.tapAt(beside);
        await tester.pump();
        expect(underTaps(), 1);
        expect(find.text(message), findsOneWidget);

        await takeDown(tester);
      });
    });
  }
}
