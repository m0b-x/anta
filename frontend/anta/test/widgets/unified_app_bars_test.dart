import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_bar_metrics.dart';
import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
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

  Widget host(Widget bar, {ThemeData? theme}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: l10n,
      theme: theme,
      home: Scaffold(
        appBar: bar as PreferredSizeWidget,
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

    // U2.9: the glyph alone says nothing to TalkBack.
    testWidgets('each save state has its own label, and only a failed save '
        'is a live region', (tester) async {
      final semantics = tester.ensureSemantics();
      final en = lookupAppLocalizations(const Locale('en'));
      final status = ValueNotifier<SaveStatus>(SaveStatus.saved);
      addTearDown(status.dispose);
      await tester.pumpWidget(
        host(NoteAppBar(title: 'Wednesday', saveStatusNotifier: status)),
      );

      final labels = {
        SaveStatus.saved: en.saveStateSaved,
        SaveStatus.unsaved: en.saveStateUnsaved,
        SaveStatus.saving: en.saveStateSaving,
        SaveStatus.error: en.saveStateError,
      };
      for (final MapEntry(key: next, value: label) in labels.entries) {
        status.value = next;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(label: label, isLiveRegion: next == SaveStatus.error),
          reason: next.name,
        );
      }
      semantics.dispose();
    });

    testWidgets('a clean note with no notifier has no save-state node', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final en = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(host(const NoteAppBar(title: 'Wednesday')));

      expect(find.bySemanticsLabel(en.saveStateSaved), findsNothing);
      expect(find.bySemanticsLabel(en.saveStateUnsaved), findsNothing);
      semantics.dispose();
    });

    testWidgets('the title is a button named Edit title with a tap action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final en = lookupAppLocalizations(const Locale('en'));
      var taps = 0;
      await tester.pumpWidget(
        host(NoteAppBar(title: 'Wednesday', onTitleTap: () => taps++)),
      );

      final title = find.bySemanticsLabel(RegExp(RegExp.escape(en.editTitle)));
      expect(
        tester.getSemantics(title),
        isSemantics(isButton: true, hasTapAction: true),
      );
      await tester.tap(find.text('Wednesday'));
      expect(taps, 1);
      semantics.dispose();
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
      await tester.pumpWidget(host(const SettingsAppBar(title: 'Settings')));

      final text = tester.widget<Text>(find.text('Settings'));
      expect(text.style!.fontSize, AppBarMetrics.titleFontSize);
      expect(text.style!.fontWeight, AppBarMetrics.titleFontWeight);
      expect(
        tester.getSize(find.byType(AppBar)).height,
        AppBarMetrics.toolbarHeight,
      );
    });

    // A review probe: without an id the title was `AppBar`'s heading of no
    // level, and the kit's level-2 section headers sat under nothing.
    for (final identifier in [null, SemanticsIds.settingsBarCalendar]) {
      testWidgets('the title is the bar\'s one labelled level-1 heading, '
          '${identifier == null ? 'without' : 'with'} an id', (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          host(SettingsAppBar(title: 'Settings', identifier: identifier)),
        );

        final headings = find.semantics
            .byPredicate((node) {
              final data = node.getSemanticsData();
              return data.flagsCollection.isHeader || data.headingLevel > 0;
            })
            .evaluate()
            .map((node) => node.getSemanticsData())
            .toList();
        expect(headings, hasLength(1));
        final title = headings.single;
        expect(title.label, 'Settings');
        expect(title.headingLevel, 1);
        expect(title.flagsCollection.isHeader, isTrue);
        expect(title.flagsCollection.namesRoute, isTrue);
        expect(title.identifier, identifier ?? '');
        semantics.dispose();
      });
    }

    // A pushed page either way, so the route implies a dismissal: the drawer
    // alone decides between Material's own drawer button and the arrow.
    for (final (withDrawer, leading) in const [
      (true, 'over a drawer, the stock drawer button'),
      (false, 'without one, the identified arrow'),
    ]) {
      testWidgets('a settings bar never draws the back-and-menu pair: '
          '$leading (D3)', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: l10n,
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AppNavigator.push<void>(
                  context,
                  Scaffold(
                    appBar: const SettingsAppBar(title: 'Settings'),
                    drawer: withDrawer
                        ? const Drawer(child: SizedBox.shrink())
                        : null,
                    body: const SizedBox.shrink(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.byType(LeadingNavPair), findsNothing);
        expect(find.byIcon(Icons.menu_rounded), findsNothing);
        expect(
          find.byType(DrawerButton),
          withDrawer ? findsOneWidget : findsNothing,
        );
        expect(
          find.descendant(
            of: find.bySemanticsIdentifier(SemanticsIds.navBack),
            matching: find.byType(BackButton),
          ),
          withDrawer ? findsNothing : findsOneWidget,
        );
        expect(
          find.byType(BackButton),
          withDrawer ? findsNothing : findsOneWidget,
        );
      });
    }

    testWidgets('the arrow pops null to the route beneath (D3)', (
      tester,
    ) async {
      Object? result = #unset;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: l10n,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await AppNavigator.push<Object?>(
                      context,
                      const Scaffold(
                        appBar: SettingsAppBar(title: 'Settings'),
                        body: SizedBox.shrink(),
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

      expect(find.text('open'), findsOneWidget);
      expect(result, isNull);
    });

    testWidgets('by default a page draws the identified arrow alone', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: l10n,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AppNavigator.push<void>(
                context,
                const Scaffold(
                  appBar: SettingsAppBar(title: 'Settings'),
                  body: SizedBox.shrink(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(LeadingNavPair), findsNothing);
      expect(find.byIcon(Icons.menu_rounded), findsNothing);
      expect(find.bySemanticsIdentifier(SemanticsIds.navBack), findsOneWidget);
    });
  });
}
