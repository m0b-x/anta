import 'dart:ui' show CheckedState, SemanticsRole, Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart' show CalendarFormat;

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/calendar_header_menus.dart';

/// The calendar's header menus (`docs/calendar-header-roadmap.md`): the view
/// menu behind the title and the ⋮ menu, as the calendar and the overview
/// both wear them.
void main() {
  Widget host({
    required Widget title,
    List<Widget> actions = const [],
    Widget? body,
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('en'),
  }) {
    return MaterialApp(
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(
        appBar: AppBar(
          titleSpacing: CalendarViewMenu.titleSpacing,
          excludeHeaderSemantics: true,
          title: title,
          actions: actions,
        ),
        body: body,
      ),
    );
  }

  // Late: a semantics finder needs the test binding, which only exists once
  // a test is running.
  late final title = find.bySemanticsIdentifier(SemanticsIds.calendarViewMenu);
  late final more = find.bySemanticsIdentifier(SemanticsIds.calendarMore);
  late final calendarRow = find.bySemanticsIdentifier(
    SemanticsIds.calendarViewCalendar,
  );
  late final overviewRow = find.bySemanticsIdentifier(
    SemanticsIds.calendarOverviewOpen,
  );
  late final monthRow = find.bySemanticsIdentifier(
    SemanticsIds.calendarFormatMonth,
  );
  late final weekRow = find.bySemanticsIdentifier(
    SemanticsIds.calendarFormatWeek,
  );

  SemanticsData dataOf(WidgetTester tester, Finder finder) =>
      tester.getSemantics(finder).getSemanticsData();

  Future<void> open(WidgetTester tester, Finder button) async {
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  group('view menu', () {
    Widget calendarTitle({
      CalendarFormat format = CalendarFormat.month,
      ValueChanged<CalendarViewPage>? onPage,
      ValueChanged<CalendarFormat>? onFormat,
      bool formatEnabled = true,
    }) {
      return CalendarViewMenu(
        page: CalendarViewPage.calendar,
        onPageSelected: onPage ?? (_) {},
        format: format,
        onFormatSelected: formatEnabled ? (onFormat ?? (_) {}) : null,
      );
    }

    testWidgets('the title names its page and opens the menu under itself', (
      tester,
    ) async {
      await tester.pumpWidget(host(title: calendarTitle()));
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);

      await open(tester, title);

      for (final label in ['Overview', 'Month', '2 weeks', 'Week']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.byType(PopupMenuDivider), findsOneWidget);
      expect(
        tester.getTopLeft(calendarRow).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
        reason: 'a dropdown opens under its title, not over it',
      );
    });

    testWidgets('the current page and the current format wear the check', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(title: calendarTitle(format: CalendarFormat.twoWeeks)),
      );
      await open(tester, title);

      Finder checkIn(Finder row) => find.descendant(
        of: row,
        matching: find.byIcon(Icons.check_rounded),
      );
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
      expect(checkIn(calendarRow), findsOneWidget);
      expect(
        checkIn(
          find.bySemanticsIdentifier(SemanticsIds.calendarFormatTwoWeeks),
        ),
        findsOneWidget,
      );
      expect(checkIn(overviewRow), findsNothing);
      expect(checkIn(monthRow), findsNothing);
    });

    testWidgets('every row is a radio item carrying its checked state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(title: calendarTitle()));
      await open(tester, title);

      final calendar = dataOf(tester, calendarRow);
      expect(calendar.role, SemanticsRole.menuItemRadio);
      expect(calendar.flagsCollection.isChecked, CheckedState.isTrue);
      expect(calendar.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(calendar.label, contains('Calendar'));

      final overview = dataOf(tester, overviewRow);
      expect(overview.role, SemanticsRole.menuItemRadio);
      expect(overview.flagsCollection.isChecked, CheckedState.isFalse);
      expect(overview.hasAction(SemanticsAction.tap), isTrue);

      expect(
        dataOf(tester, monthRow).flagsCollection.isChecked,
        CheckedState.isTrue,
      );
      expect(
        dataOf(tester, weekRow).flagsCollection.isChecked,
        CheckedState.isFalse,
      );
      handle.dispose();
    });

    testWidgets('the title is one button node: label, tooltip, id and tap', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(title: calendarTitle()));

      final data = dataOf(tester, title);
      expect(data.label, 'Calendar');
      expect(data.tooltip, 'Switch view');
      expect(data.identifier, SemanticsIds.calendarViewMenu);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      // The page's name for the route announcement lives on the labelled
      // node: Android reads the first named node that has a label.
      expect(data.flagsCollection.isHeader, isTrue);
      expect(data.flagsCollection.namesRoute, isTrue);
      // Android never speaks a tooltip beside a label on focus, so the
      // tooltip's words are the hint there too.
      expect(data.hint, 'Switch view');
      expect(
        tester.getSize(title).height,
        greaterThanOrEqualTo(kMinInteractiveDimension),
      );
      handle.dispose();
    });

    testWidgets('on iOS the tooltip is the only carrier of "Switch view"', (
      tester,
    ) async {
      // VoiceOver folds a tooltip into the label, so a hint would say it
      // twice; iOS names routes its own way, as `AppBar` leaves it.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(host(title: calendarTitle()));
        final data = dataOf(tester, title);
        expect(data.tooltip, 'Switch view');
        expect(data.hint, isEmpty);
        expect(data.flagsCollection.namesRoute, isFalse);
        expect(data.flagsCollection.isHeader, isTrue);
        handle.dispose();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('picking the other page calls back; the current one only '
        'closes the menu', (tester) async {
      final picked = <CalendarViewPage>[];
      await tester.pumpWidget(host(title: calendarTitle(onPage: picked.add)));

      await open(tester, title);
      await tester.tap(calendarRow);
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
      expect(overviewRow, findsNothing, reason: 'the menu closed');

      await open(tester, title);
      await tester.tap(overviewRow);
      await tester.pumpAndSettle();
      expect(picked, [CalendarViewPage.overview]);
    });

    testWidgets('picking another format calls back; the current one does '
        'not', (tester) async {
      final picked = <CalendarFormat>[];
      await tester.pumpWidget(
        host(title: calendarTitle(onFormat: picked.add)),
      );

      await open(tester, title);
      await tester.tap(monthRow);
      await tester.pumpAndSettle();
      expect(picked, isEmpty);

      await open(tester, title);
      await tester.tap(weekRow);
      await tester.pumpAndSettle();
      expect(picked, [CalendarFormat.week]);
    });

    testWidgets('the format rows are disabled, never hidden, until the grid '
        'can take one', (tester) async {
      final handle = tester.ensureSemantics();
      final colorScheme = AppTheme.lightScheme;
      await tester.pumpWidget(host(title: calendarTitle(formatEnabled: false)));
      await open(tester, title);

      expect(find.text('Week'), findsOneWidget);
      expect(dataOf(tester, weekRow).flagsCollection.isEnabled, Tristate.isFalse);
      expect(
        tester.widget<Text>(find.text('Week')).style?.color,
        colorScheme.onSurface.withValues(alpha: FormMetrics.disabledOpacity),
      );

      // A disabled row takes no tap: the menu stays up.
      await tester.tap(weekRow, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(weekRow, findsOneWidget);

      // The page rows are unaffected.
      expect(
        dataOf(tester, overviewRow).flagsCollection.isEnabled,
        Tristate.isTrue,
      );
      handle.dispose();
    });

    testWidgets('the overview names itself and has no format group', (
      tester,
    ) async {
      final picked = <CalendarViewPage>[];
      await tester.pumpWidget(
        host(
          title: CalendarViewMenu(
            page: CalendarViewPage.overview,
            onPageSelected: picked.add,
          ),
        ),
      );
      expect(find.text('Overview'), findsOneWidget);

      await open(tester, title);
      expect(find.text('Month'), findsNothing);
      expect(find.byType(PopupMenuDivider), findsNothing);
      expect(
        find.descendant(
          of: overviewRow,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );

      await tester.tap(calendarRow);
      await tester.pumpAndSettle();
      expect(picked, [CalendarViewPage.calendar]);
    });

    testWidgets('opening the menu drops focus, so closing it cannot raise the '
        'keyboard again', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        host(
          title: calendarTitle(),
          body: TextField(focusNode: focusNode),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      // Only the check after closing means anything: an open popup route
      // holds focus whether or not the field was let go first.
      await open(tester, title);
      await tester.tapAt(const Offset(5, 500));
      await tester.pumpAndSettle();
      expect(overviewRow, findsNothing);
      expect(focusNode.hasFocus, isFalse);
    });

    testWidgets('a long title ellipsizes before the glyph on a narrow bar', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(240, 600);
      await tester.pumpWidget(
        host(
          locale: const Locale('ro'),
          title: CalendarViewMenu(
            page: CalendarViewPage.overview,
            onPageSelected: (_) {},
          ),
          actions: [
            CalendarOverflowMenu(
              onAlerts: () {},
              onExport: () {},
              onSettings: () {},
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      final glyph = tester.getRect(find.byIcon(Icons.arrow_drop_down_rounded));
      expect(glyph.width, CalendarViewMenu.glyphSize);
      expect(glyph.right, lessThanOrEqualTo(tester.getTopLeft(more).dx));
    });
  });

  group('overflow menu', () {
    Widget overflow({
      VoidCallback? onAlerts,
      VoidCallback? onExport,
      VoidCallback? onSettings,
      bool exportEnabled = true,
    }) {
      return CalendarOverflowMenu(
        onAlerts: onAlerts ?? () {},
        onExport: exportEnabled ? (onExport ?? () {}) : null,
        onSettings: onSettings ?? () {},
      );
    }

    testWidgets('Alerts, Export, then Calendar settings below a divider', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(title: const Text('Calendar'), actions: [overflow()]),
      );
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      await open(tester, more);

      final alerts = tester.getTopLeft(find.text('Alerts')).dy;
      final export = tester.getTopLeft(find.text('Export events (.ics)')).dy;
      final divider = tester.getTopLeft(find.byType(PopupMenuDivider)).dy;
      final settings = tester.getTopLeft(find.text('Calendar settings')).dy;
      expect(alerts, lessThan(export));
      expect(export, lessThan(divider));
      expect(divider, lessThan(settings));
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('each row calls its own callback', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        host(
          title: const Text('Calendar'),
          actions: [
            overflow(
              onAlerts: () => calls.add('alerts'),
              onExport: () => calls.add('export'),
              onSettings: () => calls.add('settings'),
            ),
          ],
        ),
      );
      for (final (id, call) in [
        (SemanticsIds.calendarAlertsOpen, 'alerts'),
        (SemanticsIds.calendarExport, 'export'),
        (SemanticsIds.calendarSettingsOpen, 'settings'),
      ]) {
        await open(tester, more);
        await tester.tap(find.bySemanticsIdentifier(id));
        await tester.pumpAndSettle();
        expect(calls.last, call);
      }
      expect(calls, ['alerts', 'export', 'settings']);
    });

    testWidgets('Export is disabled while there is nothing to export', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var exports = 0;
      await tester.pumpWidget(
        host(
          title: const Text('Calendar'),
          actions: [overflow(onExport: () => exports++, exportEnabled: false)],
        ),
      );
      await open(tester, more);
      final export = find.bySemanticsIdentifier(SemanticsIds.calendarExport);
      expect(dataOf(tester, export).flagsCollection.isEnabled, Tristate.isFalse);
      await tester.tap(export, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(exports, 0);
      handle.dispose();
    });

    testWidgets('opening it drops focus, so closing it cannot raise the '
        'keyboard again', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        host(
          title: const Text('Calendar'),
          actions: [overflow()],
          body: TextField(focusNode: focusNode),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await open(tester, more);
      await tester.tapAt(const Offset(5, 500));
      await tester.pumpAndSettle();
      expect(find.text('Alerts'), findsNothing);
      expect(focusNode.hasFocus, isFalse);
    });
  });

  group('anatomy', () {
    for (final brightness in Brightness.values) {
      testWidgets('rows match the app menus (${brightness.name})', (
        tester,
      ) async {
        final scheme = brightness == Brightness.light
            ? AppTheme.lightScheme
            : AppTheme.darkScheme;
        await tester.pumpWidget(
          host(
            brightness: brightness,
            title: CalendarViewMenu(
              page: CalendarViewPage.calendar,
              onPageSelected: (_) {},
              format: CalendarFormat.month,
              onFormatSelected: (_) {},
            ),
          ),
        );
        await open(tester, title);

        final items = find.byWidgetPredicate((w) => w is PopupMenuItem);
        expect(items, findsNWidgets(5));
        for (final element in items.evaluate()) {
          final size = tester.getSize(find.byWidget(element.widget));
          expect(size.height, AppTheme.menuItemHeight);
          expect(size.width, greaterThanOrEqualTo(AppTheme.menuWidth));
          expect(size.width, lessThanOrEqualTo(AppTheme.menuMaxWidth));
        }
        expect(
          (tester.widget(find.byType(PopupMenuDivider)) as PopupMenuDivider)
              .height,
          AppTheme.menuDividerHeight,
        );

        final glyph = tester.widget<Icon>(
          find.byIcon(Icons.calendar_view_month_outlined),
        );
        expect(glyph.size, AppTheme.menuIconSize);
        expect(glyph.color, scheme.onSurfaceVariant);
        for (final check in tester.widgetList<Icon>(
          find.byIcon(Icons.check_rounded),
        )) {
          expect(check.size, AppTheme.menuIconSize);
          expect(check.color, scheme.primary);
        }

        final label = find.text('Overview');
        final style = DefaultTextStyle.of(
          tester.element(label),
        ).style.merge(tester.widget<Text>(label).style);
        expect(style.fontSize, AppTheme.menuLabelSize);
        expect(style.fontWeight, FontWeight.w400);
        expect(style.color, scheme.onSurface);
      });
    }

    testWidgets('at text scale 2.0 a long label wraps instead of being cut '
        'off, and its row grows', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        host(
          title: const Text('Calendar'),
          actions: [
            CalendarOverflowMenu(
              onAlerts: () {},
              onExport: () {},
              onSettings: () {},
            ),
          ],
        ),
      );
      await open(tester, more);
      expect(tester.takeException(), isNull);

      final label = find.text('Export events (.ics)');
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: label, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse, reason: 'nothing cut off');
      expect(
        paragraph.size.height,
        greaterThan(paragraph.getFullHeightForCaret(TextPosition(offset: 0))),
        reason: 'the label wrapped onto more than one line',
      );
      final row = find.ancestor(
        of: label,
        matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
      );
      expect(tester.getSize(row).height, greaterThan(AppTheme.menuItemHeight));
      expect(tester.getSize(row).width, AppTheme.menuMaxWidth);
    });

    testWidgets('a German ⋮ grows past 236 but never past 280', (tester) async {
      await tester.pumpWidget(
        host(
          locale: const Locale('de'),
          title: const Text('Kalender'),
          actions: [
            CalendarOverflowMenu(
              onAlerts: () {},
              onExport: () {},
              onSettings: () {},
            ),
          ],
        ),
      );
      await open(tester, more);
      expect(tester.takeException(), isNull);
      final width = tester
          .getSize(
            find
                .byWidgetPredicate((w) => w is PopupMenuItem)
                .first,
          )
          .width;
      expect(width, greaterThan(AppTheme.menuWidth));
      expect(width, lessThanOrEqualTo(AppTheme.menuMaxWidth));
    });
  });
}
