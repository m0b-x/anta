import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_bar_metrics.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/folder_sliver_app_bar.dart';
import 'package:anta/widgets/leading_nav_pair.dart';

/// The browser's bar measured on its own, away from the page that fills it.
///
/// The heights here are the ones `_compensateBarSwap` subtracts, so a change
/// that slips past this suite moves every row on the browser by the amount it
/// changed.
void main() {
  const collapseThreshold =
      FolderSliverAppBar.expandedHeightNested -
      FolderSliverAppBar.collapsedHeight +
      8;

  /// The bar is a sliver, so its extent is geometry rather than a box size.
  double barHeight(WidgetTester tester) {
    final sliver = tester.renderObject<RenderSliver>(
      find.byType(FolderSliverAppBar),
    );
    return sliver.geometry!.paintExtent;
  }

  /// The large title, told apart from the toolbar's copy of the same string
  /// by the [OverflowBox] the flexible space measures it in.
  Finder largeTitle(String title) =>
      find.descendant(of: find.byType(OverflowBox), matching: find.text(title));

  Widget host({
    required String title,
    required bool isRootPage,
    String? eyebrow,
    ScrollController? controller,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: CustomScrollView(
          controller: controller,
          slivers: [
            FolderSliverAppBar(
              title: title,
              isRootPage: isRootPage,
              eyebrow: eyebrow,
              onMenuPressed: () {},
              onBackPressed: () {},
              actions: [
                IconButton(icon: const Icon(Icons.search), onPressed: () {}),
                IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
              ],
            ),
            SliverList.builder(
              itemCount: 40,
              itemBuilder: (context, index) =>
                  SizedBox(height: 48, child: Text('row $index')),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('the collapsed bar is 48 dp above the status bar', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        title: 'Winter block',
        isRootPage: false,
        eyebrow: 'Training',
        controller: controller,
      ),
    );
    controller.jumpTo(collapseThreshold);
    await tester.pumpAndSettle();

    expect(barHeight(tester), 24 + AppBarMetrics.toolbarHeight);
  });

  testWidgets('the expanded bar is 116 nested and 102 at the root', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(title: 'Winter block', isRootPage: false, eyebrow: 'Training'),
    );
    expect(barHeight(tester), FolderSliverAppBar.expandedHeightNested);

    await tester.pumpWidget(host(title: 'Folders', isRootPage: true));
    expect(barHeight(tester), FolderSliverAppBar.expandedHeightRoot);
  });

  testWidgets('the eyebrow owns one line right under the toolbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(title: 'Winter block', isRootPage: false, eyebrow: 'Training'),
    );

    final toolbar = tester.getRect(find.byType(NavigationToolbar).first);
    final eyebrow = tester.getRect(find.text('Training'));
    final large = tester.getRect(largeTitle('Winter block'));

    expect(toolbar.height, AppBarMetrics.toolbarHeight);
    // No band: the eyebrow's line starts where the toolbar ends and the large
    // title starts one eyebrow line later.
    expect(eyebrow.top, greaterThanOrEqualTo(toolbar.bottom));
    expect(
      eyebrow.bottom,
      lessThanOrEqualTo(toolbar.bottom + AppBarMetrics.eyebrowHeight),
    );
    expect(
      large.top,
      moreOrLessEquals(
        toolbar.bottom + AppBarMetrics.eyebrowHeight,
        epsilon: 1,
      ),
    );
    expect(
      large.bottom + AppBarMetrics.largeTitleBottomPadding,
      moreOrLessEquals(FolderSliverAppBar.expandedHeightNested, epsilon: 1),
    );
    expect(
      tester.widget<Text>(find.text('Training')).style!.fontSize,
      AppBarMetrics.eyebrowFontSize,
    );

    final largeStyle = tester.widget<Text>(largeTitle('Winter block')).style!;
    expect(largeStyle.fontSize, AppBarMetrics.largeTitleFontSize);
    expect(largeStyle.fontWeight, FontWeight.w500);
    expect(largeStyle.height, AppBarMetrics.largeTitleHeight);
    expect(largeStyle.letterSpacing, AppBarMetrics.largeTitleLetterSpacing);
  });

  testWidgets('a 40-character folder name truncates rather than overflows in '
      'the collapsed bar', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const longName = 'Winter block programmes with a long name';
    expect(longName.length, 40);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      host(
        title: longName,
        isRootPage: false,
        eyebrow: 'Training',
        controller: controller,
      ),
    );
    controller.jumpTo(collapseThreshold);
    await tester.pumpAndSettle();

    final collapsed = find.descendant(
      of: find.byType(NavigationToolbar),
      matching: find.text(longName),
    );
    expect(collapsed, findsOneWidget);
    final style = tester.widget<Text>(collapsed).style!;
    expect(style.fontSize, AppBarMetrics.titleFontSize);
    expect(style.fontWeight, AppBarMetrics.titleFontWeight);
    expect(tester.widget<Text>(collapsed).overflow, TextOverflow.ellipsis);
    expect(tester.getSize(collapsed).width, greaterThanOrEqualTo(140));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pair reserves what it draws and the root draws one glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(title: 'Winter block', isRootPage: false, eyebrow: 'Training'),
    );
    expect(
      tester.getSize(find.byType(LeadingNavPair)).width,
      LeadingNavPair.width,
    );

    await tester.pumpWidget(host(title: 'Folders', isRootPage: true));
    expect(find.byType(LeadingNavPair), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.menu_rounded),
              matching: find.byType(IconButton),
            ),
          )
          .iconSize,
      AppBarMetrics.glyphSize,
    );
  });

  testWidgets('the actions carry 22 px glyphs', (tester) async {
    await tester.pumpWidget(
      host(title: 'Winter block', isRootPage: false, eyebrow: 'Training'),
    );

    for (final icon in [Icons.search, Icons.more_vert]) {
      expect(
        tester.widget<Icon>(find.byIcon(icon)).size ??
            IconTheme.of(tester.element(find.byIcon(icon))).size,
        AppBarMetrics.glyphSize,
      );
    }
  });
}
