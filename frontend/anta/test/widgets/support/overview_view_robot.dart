import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/overview_view.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/overview_view_sheet.dart';

import 'semantics_geometry.dart';

/// Drives the overview's saved views sheet — [OverviewViewSheet] — for the
/// suites: they say what the user does and read what the sheet shows.
///
/// The finders are the sheet's ids: the ✕, the save row, one row per view
/// with its ⋮ and the menu's items. Names go in through the shared name
/// dialog's one field.
class OverviewViewRobot {
  const OverviewViewRobot(this.tester);

  final WidgetTester tester;

  static const String _openLabel = 'open';

  /// Tall enough that fifty-one rows never push the save row off screen;
  /// the layout case sizes its own phone.
  static const Size defaultSurface = Size(800, 4400);

  Finder get _sheet => find.byType(OverviewViewSheet);

  Finder _byId(String id) => find.bySemanticsIdentifier(id);

  Future<void> _tap(Finder target) async {
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Opens the sheet the way the overview's bar button does — through
  /// `show`, from a button on a page — with every apply recorded in
  /// [applied].
  Future<void> show({
    required OverviewView current,
    required List<OverviewView> applied,
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
              onPressed: () => OverviewViewSheet.show(
                context,
                current: current,
                onApply: applied.add,
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

  // --- Reading -----------------------------------------------------------

  bool hasRow(String viewId) =>
      _byId(SemanticsIds.overviewViewRow(viewId)).evaluate().isNotEmpty;

  FormCheckRow _row(String viewId) => tester.widget(
    find.byWidgetPredicate(
      (widget) =>
          widget is FormCheckRow &&
          widget.identifier == SemanticsIds.overviewViewRow(viewId),
    ),
  );

  /// Whether the row carries the ✓ of the list shown.
  bool isChecked(String viewId) => _row(viewId).checked;

  String rowName(String viewId) => _row(viewId).label;

  bool get canSave =>
      tester
          .widget<FormActionRow>(
            find.ancestor(
              of: _byId(SemanticsIds.overviewViewsSave),
              matching: find.byType(FormActionRow),
            ),
          )
          .onTap !=
      null;

  /// Whether [message] is up where a finger can reach it — above the sheet.
  bool reports(String message) =>
      find.text(message).hitTestable().evaluate().isNotEmpty;

  bool get dialogOpen => find.byType(AlertDialog).evaluate().isNotEmpty;

  /// Where the ✕ is painted and where its semantics node says it is, in
  /// logical pixels — the pair the QA harness's tap by id depends on.
  (Rect painted, Rect reported) get closeRects {
    final close = _byId(SemanticsIds.overviewViewsClose);
    return (
      tester.getRect(close),
      semanticsGlobalRect(tester.getSemantics(close), tester.view),
    );
  }

  /// The save row's pair, as [closeRects].
  (Rect painted, Rect reported) get saveRects {
    final save = _byId(SemanticsIds.overviewViewsSave);
    return (
      tester.getRect(save),
      semanticsGlobalRect(tester.getSemantics(save), tester.view),
    );
  }

  // --- Acting ------------------------------------------------------------

  Future<void> close() => _tap(_byId(SemanticsIds.overviewViewsClose));

  /// Taps the ✕ where the overlay report [message] covers it, as a finger on
  /// a short sheet does; fails when the two do not overlap at all.
  Future<void> closeUnder(String message) async {
    final close = tester.getRect(_byId(SemanticsIds.overviewViewsClose));
    final report = tester.getRect(
      find
          .ancestor(of: find.text(message), matching: find.byType(Positioned))
          .first,
    );
    final overlap = close.intersect(report);
    expect(overlap.isEmpty, isFalse, reason: 'the report covers the ✕');
    await tester.tapAt(overlap.center);
    await tester.pumpAndSettle();
  }

  Future<void> apply(String viewId) =>
      _tap(_byId(SemanticsIds.overviewViewRow(viewId)));

  /// Taps the save row; when the name dialog opens, names the view [name].
  Future<void> saveCurrent(String name) async {
    await _tap(_byId(SemanticsIds.overviewViewsSave));
    if (!dialogOpen) return;
    await _name(name);
  }

  Future<void> _name(String name) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      name,
    );
    await _tap(find.text(l10n.save));
  }

  Future<void> _menu(String viewId, String itemId) async {
    await _tap(_byId(SemanticsIds.overviewViewOptions(viewId)));
    await _tap(_byId(itemId));
  }

  Future<void> rename(String viewId, String name) async {
    await _menu(viewId, SemanticsIds.overviewViewsRename);
    await _name(name);
  }

  Future<void> updateToCurrent(String viewId) =>
      _menu(viewId, SemanticsIds.overviewViewsUpdate);

  Future<void> moveToTop(String viewId) =>
      _menu(viewId, SemanticsIds.overviewViewsMoveTop);

  /// Deletes through the confirmation, answering it [confirm].
  Future<void> delete(String viewId, {bool confirm = true}) async {
    await _menu(viewId, SemanticsIds.overviewViewsDelete);
    await _tap(find.text(confirm ? l10n.delete : l10n.cancel).last);
  }
}
