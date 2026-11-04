import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/category_kinds.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/category_profile.dart';
import 'package:anta/widgets/category_goal_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

/// What `CategoryGoalSheet.show` resolved to.
class CategoryGoalOutcome {
  CategoryGoalResult? result;
  bool returned = false;
}

/// Drives the goal sheet — [CategoryGoalSheet] — for its own suite and the
/// editor's. Every control is reached by its id: the sheet lays each type's
/// value block out unseen under the one on show, so a label is on screen
/// more than once.
class CategoryGoalRobot {
  const CategoryGoalRobot(this.tester);

  final WidgetTester tester;

  static const String _openLabel = 'open goal';

  Finder get _sheet => find.byType(CategoryGoalSheet);

  Finder _byId(String id) =>
      find.descendant(of: _sheet, matching: find.bySemanticsIdentifier(id));

  /// Opens the sheet from a button, as the editor does.
  Future<CategoryGoalOutcome> show({
    ReportTarget? initial,
    required ReportMeasure? primary,
    List<TargetPreset> presets = const [],
    Locale locale = const Locale('en'),
    double? textScale,
    Size? surface,
  }) async {
    if (surface != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
    }
    final outcome = CategoryGoalOutcome();
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
                outcome.result = await CategoryGoalSheet.show(
                  context,
                  initial: initial,
                  primary: primary,
                  presets: presets,
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

  Rect get sheetRect => tester.getRect(_sheet);

  // --- Types -----------------------------------------------------------------

  List<FormCheckRow> get _typeRows => [
    for (final element
        in find
            .descendant(of: _sheet, matching: find.byType(FormCheckRow))
            .evaluate())
      element.widget as FormCheckRow,
  ];

  /// The type rows' ids, top to bottom.
  List<String?> get typeIds => [for (final row in _typeRows) row.identifier];

  List<String> get typeLabels => [for (final row in _typeRows) row.label];

  FormCheckRow _typeRow(TargetKind kind) => _typeRows.singleWhere(
    (row) => row.identifier == SemanticsIds.categoryGoalType(kind.name),
  );

  bool typeEnabled(TargetKind kind) => _typeRow(kind).onChanged != null;

  String? typeCaption(TargetKind kind) => _typeRow(kind).caption;

  TargetKind get selectedType => TargetKind.values.singleWhere(
    (kind) =>
        typeIds.contains(SemanticsIds.categoryGoalType(kind.name)) &&
        _typeRow(kind).checked,
  );

  Rect typeRect(TargetKind kind) =>
      tester.getRect(_byId(SemanticsIds.categoryGoalType(kind.name)));

  Future<void> tapType(TargetKind kind) =>
      _tap(_byId(SemanticsIds.categoryGoalType(kind.name)));

  // --- The value -------------------------------------------------------------

  /// The stepper on show — the one holding the field.
  FormStepperRow get _stepper => tester.widget<FormStepperRow>(
    find.ancestor(
      of: _byId(SemanticsIds.categoryGoalValue),
      matching: find.byType(FormStepperRow),
    ),
  );

  String get valueLabel => _stepper.label;

  String get valueText => _stepper.controller!.text;

  Finder get _field => find.descendant(
    of: _byId(SemanticsIds.categoryGoalValue),
    matching: find.byType(EditableText),
  );

  bool get valueFocused =>
      tester.widget<EditableText>(_field).focusNode.hasFocus;

  Future<void> typeValue(String text) async {
    await tester.enterText(_field, text);
    await tester.pump();
  }

  bool get canLess => _stepper.onDecrement != null;

  bool get canMore => _stepper.onIncrement != null;

  Future<void> less() => _tap(_byId(SemanticsIds.categoryGoalLess));

  Future<void> more() => _tap(_byId(SemanticsIds.categoryGoalMore));

  /// Where the − button stands — the one a switch of type must not move.
  Rect get lessRect => tester.getRect(_byId(SemanticsIds.categoryGoalLess));

  // --- The period ------------------------------------------------------------

  FormChip _chip(TargetPeriod period) => tester.widget<FormChip>(
    find.ancestor(
      of: _byId(SemanticsIds.categoryGoalPeriod(period.name)),
      matching: find.byType(FormChip),
    ),
  );

  bool periodEnabled(TargetPeriod period) => _chip(period).onTap != null;

  /// The chip drawn selected, or null under Days between, which has none.
  TargetPeriod? get selectedPeriod => TargetPeriod.values
      .where((period) => _chip(period).selected)
      .singleOrNull;

  Rect periodRect(TargetPeriod period) =>
      tester.getRect(_byId(SemanticsIds.categoryGoalPeriod(period.name)));

  Future<void> tapPeriod(TargetPeriod period) =>
      _tap(_byId(SemanticsIds.categoryGoalPeriod(period.name)));

  // --- The read-back ---------------------------------------------------------

  /// The line under the value as shown — the slot's own child, never one of
  /// the unseen sizes under it.
  String get readBack {
    final slot = tester.widget<FormCaptionSlot>(
      find.descendant(of: _sheet, matching: find.byType(FormCaptionSlot)),
    );
    final shown = slot.child as Column;
    return (shown.children.last as FormCaption).text;
  }

  // --- Leaving ---------------------------------------------------------------

  bool get canDone =>
      tester
          .widget<TextButton>(
            find.descendant(
              of: _byId(SemanticsIds.categoryGoalDone),
              matching: find.byType(TextButton),
            ),
          )
          .onPressed !=
      null;

  Future<void> done() => _tap(_byId(SemanticsIds.categoryGoalDone));

  Future<void> close() => _tap(_byId(SemanticsIds.categoryGoalClose));

  bool get removeShown =>
      _byId(SemanticsIds.categoryGoalRemove).evaluate().isNotEmpty;

  Future<void> remove() => _tap(_byId(SemanticsIds.categoryGoalRemove));

  Future<void> systemBack() async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Future<void> tapBarrier() async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width / 2, 8));
    await tester.pumpAndSettle();
  }

  Future<void> _tap(Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }
}
