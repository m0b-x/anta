import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_bar_metrics.dart';
import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/auto_save_service.dart';
import 'package:anta/widgets/leading_nav_pair.dart';
import 'package:anta/widgets/unified_app_bars.dart';

/// The editor's and the settings pages' bars, measured away from the pages
/// they sit on.
///
/// Every claim here is one the mock makes and the tree used to break: one
/// toolbar height, a 17 px title, the editor's bar on the page's own ground,
/// a save indicator that cannot reflow the title, and a drawer button that is
/// only drawn where a drawer exists.
void main() {
  final l10n = AppLocalizations.supportedLocales;

  Widget host(Widget bar, {Widget? drawer, ThemeData? theme}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: l10n,
      theme: theme,
      home: Scaffold(
        appBar: bar as PreferredSizeWidget,
        drawer: drawer,
        body: const SizedBox.shrink(),
      ),
    );
  }

  group('NoteAppBar', () {
    testWidgets('the title is 17 px at weight 500 and ellipsises', (
      tester,
    ) async {
      await tester.pumpWidget(host(const NoteAppBar(title: 'Wednesday')));

      final text = tester.widget<Text>(find.text('Wednesday'));
      expect(text.style!.fontSize, AppBarMetrics.titleFontSize);
      expect(text.style!.fontWeight, AppBarMetrics.titleFontWeight);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('the bar is 48 dp on the page ground', (tester) async {
      final theme = AppTheme.light();
      await tester.pumpWidget(
        host(const NoteAppBar(title: 'Wednesday'), theme: theme),
      );

      expect(
        tester.getSize(find.byType(AppBar)).height,
        AppBarMetrics.toolbarHeight,
      );
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
        theme.colorScheme.pageGround,
      );
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).surfaceTintColor,
        Colors.transparent,
      );
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).scrolledUnderElevation,
        0,
      );
    });

    testWidgets('a long title keeps 120 dp on a 360 dp screen', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      const long = 'Wednesday heavy squat session with a long title';

      await tester.pumpWidget(
        host(
          NoteAppBar(
            title: long,
            actions: [
              IconButton(icon: const Icon(Icons.search), onPressed: () {}),
              IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
            ],
          ),
        ),
      );

      expect(tester.getSize(find.text(long)).width, greaterThanOrEqualTo(120));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the save indicator keeps one width across every status', (
      tester,
    ) async {
      final status = ValueNotifier<SaveStatus>(SaveStatus.saved);
      addTearDown(status.dispose);

      await tester.pumpWidget(
        host(NoteAppBar(title: 'Wednesday', saveStatusNotifier: status)),
      );

      final slot = find.byKey(const ValueKey('note-app-bar-save-status'));
      final width = tester.getSize(slot).width;
      final titleWidth = tester.getSize(find.text('Wednesday')).width;

      for (final next in SaveStatus.values) {
        status.value = next;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getSize(slot).width, width, reason: next.name);
        expect(
          tester.getSize(find.text('Wednesday')).width,
          titleWidth,
          reason: next.name,
        );
      }
    });

    testWidgets('the unsaved dot is 8 dp in primary on both paths', (
      tester,
    ) async {
      final theme = AppTheme.light();
      final status = ValueNotifier<SaveStatus>(SaveStatus.unsaved);
      addTearDown(status.dispose);

      for (final bar in [
        const NoteAppBar(title: 'Wednesday', hasChanges: true),
        NoteAppBar(title: 'Wednesday', saveStatusNotifier: status),
      ]) {
        await tester.pumpWidget(host(bar, theme: theme));
        await tester.pumpAndSettle();

        final dot = find.byKey(const ValueKey('dot'));
        expect(dot, findsOneWidget);
        expect(
          tester.getSize(dot),
          const Size(
            AppBarMetrics.saveStatusDotSize,
            AppBarMetrics.saveStatusDotSize,
          ),
        );
        final decoration =
            tester.widget<Container>(dot).decoration! as BoxDecoration;
        expect(decoration.color, theme.colorScheme.primary);
        expect(decoration.shape, BoxShape.circle);
      }
    });
  });

  group('SettingsAppBar', () {
    testWidgets('the title is 17 px at weight 500 in a 48 dp bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const SettingsAppBar(title: 'Settings'),
          drawer: const Drawer(child: SizedBox.shrink()),
        ),
      );

      final text = tester.widget<Text>(find.text('Settings'));
      expect(text.style!.fontSize, AppBarMetrics.titleFontSize);
      expect(text.style!.fontWeight, AppBarMetrics.titleFontWeight);
      expect(
        tester.getSize(find.byType(AppBar)).height,
        AppBarMetrics.toolbarHeight,
      );
      expect(
        tester.getSize(find.byType(LeadingNavPair)).width,
        LeadingNavPair.width,
      );
    });

    testWidgets('the menu half is not drawn over a Scaffold without a drawer', (
      tester,
    ) async {
      await tester.pumpWidget(host(const SettingsAppBar(title: 'Counters')));

      expect(find.byType(LeadingNavPair), findsNothing);
      expect(find.byIcon(Icons.menu_rounded), findsNothing);
      expect(find.byType(BackButtonIcon), findsOneWidget);
    });

    testWidgets('only a drawer-owned page pops with openDrawer', (
      tester,
    ) async {
      Future<Object?> pushAndPop({required bool popsToDrawer}) async {
        Object? result;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: l10n,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await AppNavigator.push<SettingsResult>(
                        context,
                        Scaffold(
                          appBar: SettingsAppBar(
                            title: 'Settings',
                            popsToDrawer: popsToDrawer,
                          ),
                          drawer: const Drawer(child: SizedBox.shrink()),
                          body: const SizedBox.shrink(),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(BackButtonIcon));
        await tester.pumpAndSettle();
        return result;
      }

      expect(await pushAndPop(popsToDrawer: true), SettingsResult.openDrawer);
      expect(await pushAndPop(popsToDrawer: false), isNull);
    });
  });
}
