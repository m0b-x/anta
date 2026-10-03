import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/widgets/color_palette_sheet.dart';
import 'package:anta/widgets/color_picker_sheet.dart';
import 'package:anta/widgets/color_swatch_picker.dart';
import 'package:anta/widgets/form_rows.dart';

/// Drives the palette — [ColorPaletteSheet] — for the suites: they say what
/// the user does and read what the sheet shows, and never name a widget
/// type.
///
/// The seam is what let the Tier 3 rebuild of the sheet
/// (`docs/calendar-language-tier-3-roadmap.md`, slice 5) land under the
/// suite that pinned the old chrome: the rebuild rewrote this file and left
/// the bodies alone, but for the behaviour that record changes on purpose.
/// The finders are the sub-sheet's: the ✕, the Add color and Reset colors
/// rows, each custom colour's row, handle and delete by their ids; the
/// "n of 24" count as the section label's trailing text; the built-ins as
/// the bare dots of the read-only strip; a message as the overlay bar.
class PaletteRobot {
  const PaletteRobot(this.tester);

  final WidgetTester tester;

  static const String _openLabel = 'open';

  Finder get _sheet => find.byType(ColorPaletteSheet);

  Finder _in(Finder matching) =>
      find.descendant(of: _sheet, matching: matching);

  Finder _byId(String id) => _in(find.bySemanticsIdentifier(id));

  AppLocalizations get _l10n => AppLocalizations.of(tester.element(_sheet))!;

  /// The rows of the user's colours, in row order: the picker rows wearing
  /// a handle.
  Finder get _customRows => _in(
    find.byWidgetPredicate((w) => w is FormPickerRow && w.handle != null),
  );

  /// The row of the user's colour reading [hex] ("#123456").
  Finder _row(String hex) => _byId(SemanticsIds.paletteRow(hex));

  Finder get _handles => _in(find.byType(FormDragHandle));

  Finder get _add => _byId(SemanticsIds.paletteAdd);

  Finder get _reset => _byId(SemanticsIds.paletteReset);

  /// The action row carrying [id], read for its state. An id lands on the
  /// node inside the row, so the row is the id's nearest ancestor of its
  /// type.
  FormActionRow _actionRow(Finder id) => tester.widget<FormActionRow>(
    find.ancestor(of: id, matching: find.byType(FormActionRow)).first,
  );

  Finder get _dialog => find.byType(AlertDialog);

  /// The read-only strip's dots: the swatches with no tap.
  Finder get _builtInDots => _in(
    find.byWidgetPredicate((w) => w is ColorSwatchDot && w.onTap == null),
  );

  /// The overlay bar a message is raised in: a live region outside the
  /// sheet, which draws none of its own.
  Finder get _overlayBar => find.byWidgetPredicate(
    (w) =>
        w is Semantics &&
        w.properties.liveRegion == true &&
        find
            .ancestor(of: find.byWidget(w), matching: _sheet)
            .evaluate()
            .isEmpty,
  );

  /// Whether [finder] matches, with the strength of the `findsOneWidget` /
  /// `findsNothing` pair it stands for: a second match fails the test
  /// whichever answer the caller expected.
  bool _shown(Finder finder) {
    final matches = finder.evaluate().length;
    if (matches > 1) {
      fail('Expected at most one match, found $matches: $finder');
    }
    return matches == 1;
  }

  Future<void> _tap(Finder target) async {
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// The body is one scrollable of slivers; what sits past its end has to
  /// be scrolled to before it can be read or tapped.
  Future<void> _reveal(Finder target) async {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: _in(find.byType(Scrollable)).last,
    );
    await tester.pumpAndSettle();
  }

  /// Opens the sheet the way its callers do — through `show`, from a button
  /// on a page.
  Future<void> show({
    Locale locale = const Locale('en'),
    double? textScale,
    Size? surface,
  }) async {
    if (surface != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
    }
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
              onPressed: () => ColorPaletteSheet.show(context),
              child: const Text(_openLabel),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(_openLabel));
    await tester.pumpAndSettle();
  }

  bool get isOpen => _shown(_sheet);

  // --- The user's colours ----------------------------------------------------

  /// The hex of every colour of the user's own that is built, in row order.
  /// The run is a lazy sliver list: past a screenful only the rows in and
  /// near the viewport exist, so a long palette is counted through the
  /// section label's [capText], not here.
  List<String> get customRows => [
    for (final row in tester.widgetList<FormPickerRow>(_customRows)) row.label,
  ];

  /// The "n of 24" count the section label carries, or null while the label
  /// is not drawn. The label draws it in capitals; this is the text it was
  /// handed.
  String? get capText {
    final label = _in(
      find.byWidgetPredicate(
        (w) => w is FormSectionLabel && w.text == _l10n.colorPaletteCustomLabel,
      ),
    );
    if (!_shown(label)) return null;
    return tester.widget<FormSectionLabel>(label).trailing;
  }

  bool get emptyCaptionShown => _shown(_in(find.text(_l10n.colorPaletteEmpty)));

  /// Whether the Add color row takes a tap. Brought into view first: past
  /// a screenful of rows it has no semantics node to be found by until it
  /// is.
  Future<bool> get addEnabled async {
    await _reveal(_add);
    return _actionRow(_add).onTap != null;
  }

  /// Brings the control carrying [id] into view, for a read of a row past
  /// the fold — an id is a semantics node, and a sliver outside the
  /// viewport's reach has none.
  Future<void> reveal(String id) => _reveal(_byId(id));

  /// Add color: opens the colour picker, which resolves its remembered
  /// geometry before it presents and so arrives a frame late. Does nothing
  /// while the row is dimmed.
  Future<void> add() async {
    await _reveal(_add);
    await _tap(_add);
    await tester.pumpAndSettle();
  }

  /// A tap on the row of [hex]: opens the colour picker on that colour.
  Future<void> edit(String hex) async {
    await _tap(_row(hex));
    await tester.pumpAndSettle();
  }

  bool get pickerOpen => _shown(find.byType(ColorPickerSheet));

  /// The delete button of the row of [hex]; returns with the question up.
  Future<void> delete(String hex) =>
      _tap(_byId(SemanticsIds.paletteDelete(hex)));

  /// Drags the row at [from] to where the row at [to] stands by its handle,
  /// in steps: the reorder target is recomputed per pointer event, so one
  /// jump past the other row would prove nothing. The handle is the drag
  /// target, not the row — tapping the row edits it.
  Future<void> dragRow(int from, int to) async {
    final start = tester.getCenter(_handles.at(from));
    final end = tester.getCenter(_handles.at(to));
    await _drag(start, end);
  }

  /// Lifts the row at [from] by holding a finger on its label — anywhere on
  /// the row, not the handle — and carries it to where the row at [to]
  /// stands.
  Future<void> dragRowByLongPress(int from, int to) async {
    final rows = _customRows;
    final start = tester.getCenter(
      find.descendant(of: rows.at(from), matching: find.byType(Text)),
    );
    final end = tester.getCenter(rows.at(to));
    final gesture = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await _carry(gesture, end - start);
  }

  Future<void> _drag(Offset start, Offset end) async {
    final gesture = await tester.startGesture(start);
    await tester.pump(kPressTimeout);
    await _carry(gesture, end - start);
  }

  Future<void> _carry(TestGesture gesture, Offset travel) async {
    final overshoot = travel * 1.2;
    const steps = 6;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(overshoot / steps.toDouble());
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  // --- The built-ins and the reset -------------------------------------------

  /// How many built-in colours the sheet shows as samples.
  int get builtInCount => _builtInDots.evaluate().length;

  /// What each sample announces, in strip order.
  List<String?> get builtInLabels => [
    for (final dot in tester.widgetList<ColorSwatchDot>(_builtInDots))
      dot.semanticLabel,
  ];

  /// The semantics of each sample, in strip order.
  List<SemanticsData> get builtInNodes => [
    for (final dot in _builtInDots.evaluate())
      tester.getSemantics(find.byWidget(dot.widget)).getSemanticsData(),
  ];

  Future<bool> get resetEnabled async {
    await _reveal(_reset);
    return _actionRow(_reset).onTap != null;
  }

  /// Reset colors; returns with the question up, or does nothing while the
  /// action is dimmed.
  Future<void> reset() async {
    await _reveal(_reset);
    await _tap(_reset);
  }

  // --- The confirmation ------------------------------------------------------

  bool get dialogShown => _shown(_dialog);

  /// Whether the open question is titled [title].
  bool dialogTitled(String title) => find
      .descendant(of: _dialog, matching: find.text(title))
      .evaluate()
      .isNotEmpty;

  /// The question's confirming button, whatever it is labelled.
  Future<void> confirm() =>
      _tap(find.descendant(of: _dialog, matching: find.byType(FilledButton)));

  /// The question's way out: nothing happens.
  Future<void> cancelDialog() =>
      _tap(find.descendant(of: _dialog, matching: find.byType(TextButton)));

  // --- Messages --------------------------------------------------------------

  /// The message on screen, or null.
  String? get message {
    final bar = _overlayBar;
    if (!_shown(bar)) return null;
    return tester
        .widget<Text>(find.descendant(of: bar, matching: find.byType(Text)))
        .data;
  }

  /// Whether the message is where a finger can reach it — above the sheet,
  /// not on the page under it.
  bool get messageReachable {
    final text = message;
    return text != null && _shown(find.text(text).hitTestable());
  }

  // --- Geometry and semantics ------------------------------------------------

  /// The semantics of the control carrying [id].
  SemanticsData nodeOf(String id) =>
      tester.getSemantics(_byId(id)).getSemanticsData();

  /// The on-screen rect of the control carrying [id].
  Rect targetOf(String id) => tester.getRect(_byId(id));

  Rect get sheetRect => tester.getRect(_sheet);

  /// The on-screen rect of the whole row of [hex], handle and delete
  /// included.
  Rect rowRect(String hex) => tester.getRect(
    find.ancestor(of: _row(hex), matching: find.byType(FormRowShell)).first,
  );

  /// The on-screen size of every sample dot.
  List<Size> get builtInTargets => [
    for (final dot in _builtInDots.evaluate())
      tester.getSize(find.byWidget(dot.widget)),
  ];

  Future<void> close() => _tap(_byId(SemanticsIds.paletteClose));
}
