import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/category_kinds.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/category_kind_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

/// What `CategoryKindSheet.show` resolved to.
class CategoryKindOutcome {
  CategoryKind? result;
  bool returned = false;
}

/// Drives the kind picker — [CategoryKindSheet] — for its own suite and the
/// editor's: rows by their `category-kind-<name>` ids, the groups by their
/// section labels, never a widget type in a test body.
class CategoryKindRobot {
  const CategoryKindRobot(this.tester);

  final WidgetTester tester;

  static const String _openLabel = 'open kinds';

  Finder get _sheet => find.byType(CategoryKindSheet);

  Finder _in(Finder matching) =>
      find.descendant(of: _sheet, matching: matching);

  Finder _row(CategoryKind kind) =>
      _in(find.bySemanticsIdentifier(SemanticsIds.categoryKind(kind.name)));

  /// Opens the picker on [selected] from a button, as the editor does.
  Future<CategoryKindOutcome> show({
    CategoryKind selected = CategoryKind.custom,
    Locale locale = const Locale('en'),
    double? textScale,
    Size? surface,
  }) async {
    if (surface != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
    }
    final outcome = CategoryKindOutcome();
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
              onPressed: () async {
                outcome.result = await CategoryKindSheet.show(
                  context,
                  selected: selected,
                );
                outcome.returned = true;
              },
              child: const Text(_openLabel),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(_openLabel));
    await tester.pumpAndSettle();
    return outcome;
  }

  bool get isOpen => _sheet.evaluate().isNotEmpty;

  /// The group labels, top to bottom, as handed in.
  List<String> get sectionLabels => [
    for (final element in _in(find.byType(FormSectionLabel)).evaluate())
      (element.widget as FormSectionLabel).text,
  ];

  /// Every kind row, top to bottom.
  List<FormCheckRow> get _rows => [
    for (final element in _in(find.byType(FormCheckRow)).evaluate())
      element.widget as FormCheckRow,
  ];

  /// The kinds' row ids, top to bottom.
  List<String?> get rowIds => [for (final row in _rows) row.identifier];

  /// The labels and captions of every row, top to bottom.
  List<String> get rowLabels => [for (final row in _rows) row.label];

  List<String?> get rowCaptions => [for (final row in _rows) row.caption];

  /// The ids of the checked rows — one at most.
  List<String?> get checkedIds => [
    for (final row in _rows)
      if (row.checked) row.identifier,
  ];

  /// The top of [kind]'s row on screen.
  double topOf(CategoryKind kind) => tester.getTopLeft(_row(kind)).dy;

  double heightOf(CategoryKind kind) => tester.getSize(_row(kind)).height;

  Rect get sheetRect => tester.getRect(_sheet);

  /// Whether [text] is drawn whole: inside its line limit and the sheet.
  bool textWhole(String text) {
    final finder = _in(find.text(text));
    if (tester.renderObject<RenderParagraph>(finder).didExceedMaxLines) {
      return false;
    }
    final rect = tester.getRect(finder);
    return rect.left >= sheetRect.left && rect.right <= sheetRect.right;
  }

  /// Picks [kind]: the sheet scrolls to it and closes with it.
  Future<void> pick(CategoryKind kind) async {
    await tester.ensureVisible(_row(kind));
    await tester.pumpAndSettle();
    await tester.tap(_row(kind));
    await tester.pumpAndSettle();
  }

  Future<void> close() async {
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.categoryKindClose),
    );
    await tester.pumpAndSettle();
  }

  Future<void> systemBack() async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Future<void> tapBarrier() async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width / 2, 8));
    await tester.pumpAndSettle();
  }
}
