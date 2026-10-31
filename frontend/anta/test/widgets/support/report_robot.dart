import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
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
import 'package:anta/models/nav_destination.dart';
import 'package:anta/models/report_look.dart';
import 'package:anta/pages/calendar_report_page.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/calendar_report_service.dart';
import 'package:anta/utils/report_labels.dart';
import 'package:anta/widgets/agenda_period_nav.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
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
    ValueListenable<EdgeInsets>? viewInsets,
    bool? alwaysUse24HourFormat,
    bool stamped = false,
  }) async {
    final page = CalendarReportPage.forTesting(
      look: look,
      service: service,
      clock: clock,
      nextFrame: nextFrame,
    );
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
            Widget framed(EdgeInsets keyboard) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  textScaler: textScale == null
                      ? media.textScaler
                      : TextScaler.linear(textScale),
                  viewPadding: media.viewPadding + viewPadding,
                  padding: media.padding + viewPadding,
                  viewInsets: media.viewInsets + keyboard,
                  alwaysUse24HourFormat:
                      alwaysUse24HourFormat ?? media.alwaysUse24HourFormat,
                ),
                child: child!,
              );
            }

            // [viewInsets] is a keyboard a case raises and lowers while the
            // page is up.
            final keyboard = viewInsets;
            if (keyboard == null) return framed(EdgeInsets.zero);
            return ValueListenableBuilder<EdgeInsets>(
              valueListenable: keyboard,
              builder: (_, insets, _) => framed(insets),
            );
          },
          // [stamped] puts the page on a route stamped as the real push
          // stamps it, which a digest's tap collapses onto.
          home: stamped ? null : page,
          onGenerateRoute: stamped
              ? (settings) => MaterialPageRoute<void>(
                  settings: RouteSettings(
                    name: settings.name,
                    arguments: const NavDestination(
                      NavDestinationKind.calendarReport,
                    ),
                  ),
                  builder: (_) => page,
                )
              : null,
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

  /// Read through the body, which is there however far it is scrolled.
  ReportState get state => tester
      .element(byId(SemanticsIds.reportBody))
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

  /// The caption under the Totals card, or null when there is none — the
  /// body's one caption of its own; the group rows carry theirs inside.
  String? get caption {
    final captions = find.descendant(
      of: byId(SemanticsIds.reportBody),
      matching: find.byWidgetPredicate(
        (w) => w is SliverToBoxAdapter && w.child is FormCaption,
      ),
    );
    if (captions.evaluate().isEmpty) return null;
    final adapter = tester.widget<SliverToBoxAdapter>(captions);
    return (adapter.child! as FormCaption).text;
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

  /// A category group's header in [card].
  Finder group(ReportCard card, String categoryId) =>
      byId(SemanticsIds.reportGroup(card.name, categoryId));

  /// A group's "n more" / "Show less" row.
  Finder groupMore(ReportCard card, String categoryId) =>
      byId(SemanticsIds.reportGroupMore(card.name, categoryId));

  /// A dated row.
  Finder row(String eventId, DateTime day) =>
      byId(SemanticsIds.reportRow(eventId, day));

  /// The detail sheet a row tap opened, or null while none is up.
  EventDetailSheet? get detailSheet {
    final sheet = find.byType(EventDetailSheet);
    if (sheet.evaluate().isEmpty) return null;
    return tester.widget<EventDetailSheet>(sheet);
  }

  /// Taps [finder] and runs the sheet it opens in.
  Future<void> openSheet(Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// The detail sheet's ✕, and the sheet run out.
  Future<void> closeSheet() async {
    await tester.tap(byId(SemanticsIds.eventDetailClose));
    await tester.pumpAndSettle();
  }

  /// The body's one scroll.
  ScrollController get scroll => tester
      .widget<CustomScrollView>(
        find.descendant(
          of: byId(SemanticsIds.reportBody),
          matching: find.byType(CustomScrollView),
        ),
      )
      .controller!;

  /// Brings [finder] into view, jumping the body half a screen at a time
  /// until it is built: below the cards it is not built at first, and a
  /// jump, unlike a drag, lets no time pass for a held refold's dim.
  Future<void> reveal(Finder finder) async {
    final position = scroll.position;
    while (finder.evaluate().isEmpty &&
        position.pixels < position.maxScrollExtent) {
      scroll.jumpTo(
        math.min(
          position.pixels + position.viewportDimension / 2,
          position.maxScrollExtent,
        ),
      );
      await tester.pump();
    }
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  /// Taps Show as list — the footer's, or the row [id] — and returns the
  /// look it handed the overview, then takes the app down before the
  /// overview it pushed is ever built: what this suite checks is the
  /// hand-over, the overview suite the landing.
  Future<OverviewLook?> showAsListAndLeave({
    String id = SemanticsIds.reportShowList,
  }) async {
    final row = byId(id);
    await reveal(row);
    await tester.tap(row);
    final look = AppNavigator.pendingOverviewLook.value;
    AppNavigator.pendingOverviewLook.value = null;
    await tester.pumpWidget(const SizedBox.shrink());
    return look;
  }

  /// Taps Send me this report, which opens the digest sheet.
  Future<void> send() async {
    final row = byId(SemanticsIds.reportSend);
    await reveal(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
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
