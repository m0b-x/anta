import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/calendar_report/calendar_report_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/models/report_look.dart';
import 'package:anta/pages/calendar_report_page.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/calendar_report_service.dart';
import 'package:anta/widgets/agenda_period_nav.dart';
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/report_totals_card.dart';

/// Drives [CalendarReportPage] for its suite: opens it over a loaded
/// calendar bloc with the overview suite's shape — the app-wide blocs above
/// the app, a locale, a text scale, a surface, a theme — and reads what the
/// bar, the band and the body show by their `SemanticsIds`.
class ReportRobot {
  const ReportRobot(this.tester);

  final WidgetTester tester;

  Finder byId(String id) => find.bySemanticsIdentifier(id);

  /// Pumps the page and waits for its first report: the settings read is a
  /// real async gap, so a bounded number of short frames, never a settle on
  /// a page that may be waiting for nothing.
  Future<void> open({
    required CalendarBloc bloc,
    required ImportExportBloc importExport,
    required CalendarReportService service,
    required DateTime Function() clock,
    ReportLook? look,
    Future<void> Function()? nextFrame,
    Locale locale = const Locale('en'),
    double? textScale,
    Size? surface,
    Brightness brightness = Brightness.light,
    EdgeInsets viewPadding = EdgeInsets.zero,
  }) async {
    if (surface != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
    }
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<CalendarBloc>.value(value: bloc),
          BlocProvider<ImportExportBloc>.value(value: importExport),
        ],
        child: MaterialApp(
          theme: brightness == Brightness.light
              ? AppTheme.light()
              : AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          // The app's key, so Show as list reaches the navigator it uses.
          navigatorKey: AppNavigator.navigatorKey,
          navigatorObservers: [AppNavigator.routeObserver],
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: textScale == null
                    ? media.textScaler
                    : TextScaler.linear(textScale),
                viewPadding: media.viewPadding + viewPadding,
                padding: media.padding + viewPadding,
              ),
              child: child!,
            );
          },
          home: CalendarReportPage.forTesting(
            look: look,
            service: service,
            clock: clock,
            nextFrame: nextFrame,
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      if (isReady) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
  }

  /// Whether the body draws a folded report: the footer only comes with one.
  bool get isReady {
    final card = find.byType(ReportTotalsCard);
    if (card.evaluate().isEmpty) return false;
    return tester.element(card).read<CalendarReportBloc>().state is ReportReady;
  }

  AppLocalizations get l10n =>
      AppLocalizations.of(tester.element(find.byType(ReportTotalsCard)))!;

  ReportState get state => tester
      .element(find.byType(ReportTotalsCard))
      .read<CalendarReportBloc>()
      .state;

  /// The refold's dim over the body: its opacity, and whether it swallows
  /// taps — the nearest of each above the body.
  double get bodyOpacity => tester
      .widget<Opacity>(
        find
            .ancestor(
              of: byId(SemanticsIds.reportBody),
              matching: find.byType(Opacity),
            )
            .first,
      )
      .opacity;

  bool get bodyAbsorbsTaps => tester
      .widget<AbsorbPointer>(
        find
            .ancestor(
              of: byId(SemanticsIds.reportBody),
              matching: find.byType(AbsorbPointer),
            )
            .first,
      )
      .absorbing;

  Future<void> tapId(String id) async {
    await tester.tap(byId(id));
    await tester.pump();
  }

  AgendaPeriodNav get nav => tester.widget(find.byType(AgendaPeriodNav));

  Finder tile(ReportTile tile) => byId(SemanticsIds.reportTile(tile.name));

  /// The tiles drawn, in order of their ids' appearance.
  List<ReportTile> get tiles => [
    for (final value in ReportTile.values)
      if (tile(value).evaluate().isNotEmpty) value,
  ];

  Rect tileRect(ReportTile value) => tester.getRect(tile(value));

  Rect get totalsRect => tester.getRect(find.byType(ReportTotalsCard));

  /// The caption under the Totals card, or null when there is none.
  String? get caption {
    final captions = find.descendant(
      of: byId(SemanticsIds.reportBody),
      matching: find.byType(FormCaption),
    );
    if (captions.evaluate().isEmpty) return null;
    return tester.widget<FormCaption>(captions).text;
  }

  Future<void> openPeriodMenu() async {
    await tester.tap(byId(SemanticsIds.reportNavTitle));
    await tester.pumpAndSettle();
  }

  /// The id of the menu row checked, read with the menu up.
  String get checkedPeriodId => tester
      .widgetList<FormMenuItemRow>(find.byType(FormMenuItemRow))
      .where((row) => row.checked)
      .single
      .identifier!;

  Future<void> closeMenu() async {
    Navigator.of(tester.element(find.byType(FormMenuItemRow).first)).pop();
    await tester.pumpAndSettle();
  }

  /// Picks the Period menu row [id] from the menu [openPeriodMenu] left up,
  /// then waits for the refold.
  Future<void> pickPeriod(String id) async {
    await tester.tap(byId(id));
    await tester.pumpAndSettle();
  }

  Badge get categoriesBadge => tester.widget<Badge>(
    find.descendant(
      of: find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.identifier == SemanticsIds.reportCategoriesOpen,
      ),
      matching: find.byType(Badge),
    ),
  );

  /// Taps Show as list and returns the look it handed the overview, then
  /// takes the app down before the overview it pushed is ever built: what
  /// this suite checks is the hand-over, the overview suite the landing.
  Future<OverviewLook?> showAsListAndLeave() async {
    final row = byId(SemanticsIds.reportShowList);
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    final look = AppNavigator.pendingOverviewLook.value;
    AppNavigator.pendingOverviewLook.value = null;
    await tester.pumpWidget(const SizedBox.shrink());
    return look;
  }

  FormActionRow footerRow(String id) => tester.widget<FormActionRow>(
    find.byWidgetPredicate((w) => w is FormActionRow && w.identifier == id),
  );

  /// The body's scroll padding, which carries the bottom clearance.
  EdgeInsets get bodyPadding => tester
      .widget<SliverPadding>(
        find.descendant(
          of: byId(SemanticsIds.reportBody),
          matching: find.byType(SliverPadding),
        ),
      )
      .padding
      .resolve(TextDirection.ltr);
}
