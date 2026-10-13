import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/overview_list_options.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/overview_options_sheet.dart';

/// Drives the overview list's options sheet — [OverviewOptionsSheet] — for
/// the suites: they say what the user does and read what the sheet shows.
///
/// The finders are the sheet's ids: the ✕, the Order and Rows menu rows and
/// their items, the Missed only switch.
class OverviewOptionsRobot {
  const OverviewOptionsRobot(this.tester);

  final WidgetTester tester;

  static const String _openLabel = 'open';

  /// Tall enough that the sheet shows every row; the layout cases size their
  /// own phone.
  static const Size defaultSurface = Size(800, 1600);

  Finder get _sheet => find.byType(OverviewOptionsSheet);

  Finder _byId(String id) =>
      find.descendant(of: _sheet, matching: find.bySemanticsIdentifier(id));

  FormMenuRow<T> _menuRow<T>(String id) => tester.widget(
    find.descendant(
      of: _sheet,
      matching: find.byWidgetPredicate(
        (widget) => widget is FormMenuRow<T> && widget.identifier == id,
      ),
    ),
  );

  FormSwitchRow get _switchRow => tester.widget(
    find.descendant(of: _sheet, matching: find.byType(FormSwitchRow)),
  );

  Future<void> _tap(Finder target) async {
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Opens the sheet the way the overview's tune button does — through
  /// `show`, from a button on a page. Every change goes out through
  /// [onChanged]; there is nothing to return.
  Future<void> show({
    OverviewListOptions initial = OverviewListOptions.defaults,
    bool listMode = true,
    required ValueChanged<OverviewListOptions> onChanged,
    Locale locale = const Locale('en'),
    Size surface = defaultSurface,
    double? textScale,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: textScale == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => OverviewOptionsSheet.show(
                context,
                initial: initial,
                listMode: listMode,
                onChanged: onChanged,
              ),
              child: const Text(_openLabel),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(_openLabel));
    await tester.pumpAndSettle();
  }

  bool get isOpen => _sheet.evaluate().isNotEmpty;

  AppLocalizations get l10n => AppLocalizations.of(tester.element(_sheet))!;

  // --- The rows --------------------------------------------------------------

  static String _orderItemId(OverviewOrder order) => switch (order) {
    OverviewOrder.oldestFirst => SemanticsIds.overviewOrderOldest,
    OverviewOrder.newestFirst => SemanticsIds.overviewOrderNewest,
  };

  static String _rowsItemId(OverviewRows rows) => switch (rows) {
    OverviewRows.everyOccurrence => SemanticsIds.overviewRowsEvery,
    OverviewRows.perEvent => SemanticsIds.overviewRowsPerEvent,
  };

  Future<void> pickOrder(OverviewOrder order) async {
    await _tap(_byId(SemanticsIds.overviewOrder));
    await _tap(find.bySemanticsIdentifier(_orderItemId(order)));
  }

  Future<void> pickRows(OverviewRows rows) async {
    await _tap(_byId(SemanticsIds.overviewRows));
    await _tap(find.bySemanticsIdentifier(_rowsItemId(rows)));
  }

  Future<void> toggleMissedOnly() =>
      _tap(_byId(SemanticsIds.overviewMissedOnly));

  /// Taps a row that may be disabled; a disabled one opens nothing.
  Future<void> tapRow(String id) async {
    await tester.tap(_byId(id), warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  OverviewOrder get order =>
      _menuRow<OverviewOrder>(SemanticsIds.overviewOrder).selected;

  String get orderLabel =>
      _menuRow<OverviewOrder>(SemanticsIds.overviewOrder).value;

  OverviewRows get rows =>
      _menuRow<OverviewRows>(SemanticsIds.overviewRows).selected;

  String get rowsLabel =>
      _menuRow<OverviewRows>(SemanticsIds.overviewRows).value;

  bool get missedOnly => _switchRow.value;

  /// Whether the control carrying [id] is enabled, as a screen reader hears
  /// it: a picker row marks only its disabled state, a switch both.
  bool enabled(String id) {
    final flags = tester
        .getSemantics(_byId(id))
        .getSemanticsData()
        .flagsCollection;
    return flags.isEnabled != Tristate.isFalse;
  }

  /// Whether a menu is up: the popup's items are on screen.
  bool get menuOpen =>
      find.byWidgetPredicate((w) => w is PopupMenuItem).evaluate().isNotEmpty;

  /// Whether the open menu's item carrying [id] wears the check.
  bool menuItemChecked(String id) =>
      tester
          .getSemantics(find.bySemanticsIdentifier(id))
          .getSemanticsData()
          .flagsCollection
          .isChecked ==
      CheckedState.isTrue;

  // --- Geometry --------------------------------------------------------------

  Rect get sheetRect => tester.getRect(_sheet);

  /// Whether the label of the control carrying [id] — a row's first line —
  /// is drawn whole: nothing cut by an ellipsis, inside the sheet's width.
  bool controlLabelWhole(String id) {
    final text = find
        .descendant(of: _byId(id), matching: find.byType(Text))
        .first;
    if (tester.renderObject<RenderParagraph>(text).didExceedMaxLines) {
      return false;
    }
    final rect = tester.getRect(text);
    final sheet = sheetRect;
    return rect.left >= sheet.left && rect.right <= sheet.right;
  }

  // --- Leaving ---------------------------------------------------------------

  Future<void> close() => _tap(_byId(SemanticsIds.overviewOptionsClose));

  /// A tap on the barrier above the sheet.
  Future<void> tapBarrier() async {
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
  }

  /// Drags the sheet down by its handle, far enough to dismiss it.
  Future<void> dragDown() async {
    await tester.drag(
      find.descendant(of: _sheet, matching: find.byType(FormSheetHandle)),
      Offset(0, sheetRect.height),
    );
    await tester.pumpAndSettle();
  }
}
