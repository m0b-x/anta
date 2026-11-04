import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_report.dart';
import 'package:anta/utils/report_labels.dart';
import 'package:anta/widgets/report_totals_card.dart';

/// The Totals card's tile ids (S5 §2.5): the page's card keeps
/// `report-tile-*`, a saved view's second card takes `report-view-tile-*`,
/// so the two can share one page.
void main() {
  const tiles = [
    ReportTileValue(tile: ReportTile.events, value: 12),
    ReportTileValue(tile: ReportTile.attended, value: 9, of: 10),
    ReportTileValue(tile: ReportTile.hours, value: 300),
  ];

  Future<void> pump(WidgetTester tester, List<Widget> Function() cards) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(body: ListView(children: cards())),
        ),
      );

  Widget card({String Function(String)? tileIdentifier}) => Builder(
    builder: (context) {
      final labels = ReportLabels(AppLocalizations.of(context)!);
      return tileIdentifier == null
          ? ReportTotalsCard(tiles: tiles, labels: labels)
          : ReportTotalsCard(
              tiles: tiles,
              labels: labels,
              tileIdentifier: tileIdentifier,
            );
    },
  );

  testWidgets('the default ids are the page\'s report-tile-*', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, () => [card()]);
    for (final value in tiles) {
      expect(
        find.bySemanticsIdentifier('report-tile-${value.tile.name}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reportTile(value.tile.name)),
        findsOneWidget,
      );
    }
    handle.dispose();
  });

  testWidgets('a view\'s card carries report-view-tile-*', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      () => [card(tileIdentifier: SemanticsIds.reportViewTile)],
    );
    for (final value in tiles) {
      expect(
        find.bySemanticsIdentifier('report-view-tile-${value.tile.name}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reportTile(value.tile.name)),
        findsNothing,
      );
    }
    handle.dispose();
  });

  testWidgets('two cards in one tree keep every id unique', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      () => [card(), card(tileIdentifier: SemanticsIds.reportViewTile)],
    );
    for (final value in tiles) {
      expect(
        find.bySemanticsIdentifier(SemanticsIds.reportTile(value.tile.name)),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(
          SemanticsIds.reportViewTile(value.tile.name),
        ),
        findsOneWidget,
      );
    }
    handle.dispose();
  });
}
