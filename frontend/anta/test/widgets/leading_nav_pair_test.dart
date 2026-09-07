import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/leading_nav_pair.dart';

/// The leading pair's geometry, which is a promise to every bar that hosts
/// it: `leadingWidth: LeadingNavPair.width` reserves exactly what the pair
/// draws, and anything reserved and not drawn is width stolen from a title
/// that has little of it to begin with.
void main() {
  Widget host({
    ThemeData? theme,
    void Function(BuildContext anchorContext)? onBackLongPress,
    String? backLongPressLabel,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: LeadingNavPair(
            onBack: () {},
            onMenu: () {},
            onBackLongPress: onBackLongPress,
            backLongPressLabel: backLongPressLabel,
          ),
        ),
      ),
    );
  }

  testWidgets('the pair draws exactly the width its hosts reserve', (
    tester,
  ) async {
    await tester.pumpWidget(host());

    expect(
      tester.getSize(find.byType(LeadingNavPair)).width,
      LeadingNavPair.width,
    );
    for (final button in find.byType(IconButton).evaluate()) {
      expect(
        tester.getSize(find.byWidget(button.widget)),
        const Size(LeadingNavPair.halfSize, LeadingNavPair.halfSize),
      );
    }

    final back = tester.getRect(
      find.ancestor(
        of: find.byType(BackButtonIcon),
        matching: find.byType(IconButton),
      ),
    );
    final menu = tester.getRect(
      find.ancestor(
        of: find.byIcon(Icons.menu_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(
      menu.right - back.left + LeadingNavPair.leadingPadding,
      LeadingNavPair.width,
    );
  });

  testWidgets('the divider is outlineVariant in both themes', (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(host(theme: theme));
      // MaterialApp lerps between themes, so the first frame after a swap
      // still carries the outgoing palette.
      await tester.pumpAndSettle();

      final divider = tester.widget<Container>(
        find.descendant(
          of: find.byType(LeadingNavPair),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.constraints?.maxHeight == LeadingNavPair.dividerHeight,
          ),
        ),
      );
      expect(divider.color, theme.colorScheme.outlineVariant);
      expect(divider.color!.a, 1.0);
    }
  });

  testWidgets('only the arrow half offers the ancestor action', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(onBackLongPress: (_) {}, backLongPressLabel: 'Show ancestors'),
    );

    List<String?> actionsOf(Finder finder) {
      final ids =
          tester
              .getSemantics(finder)
              .getSemanticsData()
              .customSemanticsActionIds ??
          const <int>[];
      return ids
          .map((id) => CustomSemanticsAction.getAction(id)?.label)
          .toList();
    }

    expect(
      actionsOf(
        find.ancestor(
          of: find.byType(BackButtonIcon),
          matching: find.byType(IconButton),
        ),
      ),
      contains('Show ancestors'),
    );
    expect(
      actionsOf(
        find.ancestor(
          of: find.byIcon(Icons.menu_rounded),
          matching: find.byType(IconButton),
        ),
      ),
      isNot(contains('Show ancestors')),
    );

    semantics.dispose();
  });
}
