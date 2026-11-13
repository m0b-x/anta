import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/row_metrics.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_de.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/widgets/content_rows.dart';
import 'package:anta/widgets/user_avatar.dart';

/// "From {name} · Read only" (share surfaces §6.13, spec §0.2): one node,
/// a long German name or an address at text scale 2.0 wraps inside the
/// phone's width and stops at three lines, and the sheet variant draws no
/// band.
void main() {
  const width = 360.0;
  const maria = AppUser(uid: 'p', displayName: 'Maria');

  Future<void> pumpLine(
    WidgetTester tester, {
    required String text,
    Locale locale = const Locale('en'),
    double scale = 1.0,
    bool banded = true,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(width, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: ThemeData(brightness: brightness),
        // Each pump is its own theme, never a lerp between two.
        themeAnimationDuration: Duration.zero,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(width, 780),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Column(
              children: [
                SharedReadOnlyLine(
                  partner: maria,
                  text: text,
                  banded: banded,
                  identifier: 'shared-note-line',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int linesOf(WidgetTester tester, String text) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    final line = paragraph.getFullHeightForCaret(const TextPosition(offset: 0));
    return (paragraph.size.height / line).round();
  }

  testWidgets('one line at 1.0, the face before the words, one node that '
      'says the whole line', (tester) async {
    final semantics = tester.ensureSemantics();
    final text = AppLocalizationsEn().sharedNoteLine('Maria');
    await pumpLine(tester, text: text);

    expect(find.text('From Maria · Read only'), findsOneWidget);
    expect(linesOf(tester, text), 1);
    final avatar = tester.widget<UserAvatar>(find.byType(UserAvatar));
    expect(avatar.radius, RowMetrics.partnerAvatarRadius);
    expect(avatar.user, maria);
    expect(
      tester.getTopLeft(find.byType(UserAvatar)).dx,
      RowMetrics.sharedLinePadding.left,
    );
    expect(
      tester.getTopLeft(find.text(text)).dx -
          tester.getTopRight(find.byType(UserAvatar)).dx,
      RowMetrics.sharedLineGap,
    );
    expect(find.bySemanticsIdentifier('shared-note-line'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('shared-note-line')),
      matchesSemantics(label: text, identifier: 'shared-note-line'),
    );
    semantics.dispose();
  });

  for (final (name, why) in [
    ('Maximilian Mustermann', 'a long name'),
    ('maximilian.mustermann@example.com', 'an address'),
  ]) {
    testWidgets('German at 2.0 with $why: wraps, no overflow, at most three '
        'lines', (tester) async {
      final text = AppLocalizationsDe().sharedNoteLine(name);
      await pumpLine(
        tester,
        text: text,
        locale: const Locale('de'),
        scale: 2.0,
      );
      expect(tester.takeException(), isNull);
      final lines = linesOf(tester, text);
      expect(lines, greaterThan(1));
      expect(lines, lessThanOrEqualTo(RowMetrics.sharedLineMaxLines));
      expect(tester.getSize(find.byType(SharedReadOnlyLine)).width, width);
    });
  }

  testWidgets('banded on the editor, one tone off the ground in each theme; '
      'clear in a sheet', (tester) async {
    ColoredBox band() => tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(SharedReadOnlyLine),
        matching: find.byType(ColoredBox),
      ),
    );
    await pumpLine(tester, text: 'From Maria · Read only');
    final light = Theme.of(
      tester.element(find.byType(SharedReadOnlyLine)),
    ).colorScheme;
    expect(band().color, light.surfaceContainerHigh);

    await pumpLine(
      tester,
      text: 'From Maria · Read only',
      brightness: Brightness.dark,
    );
    final dark = Theme.of(
      tester.element(find.byType(SharedReadOnlyLine)),
    ).colorScheme;
    expect(band().color, dark.surfaceContainer);

    await pumpLine(tester, text: 'From Maria · Read only', banded: false);
    expect(band().color, Colors.transparent);
  });
}
