import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/color_picker_mode.dart';
import 'package:anta/widgets/color_picker_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

/// What `ColorPickerSheet.show` resolved to. Mutable, because the sheet is
/// awaited inside a button callback and the value arrives after the tap that
/// dismissed it.
class ColorPickerOutcome {
  int? result;
  bool returned = false;
}

/// Drives the colour picker — [ColorPickerSheet] — for the suites: they say
/// what the user does and read what the sheet shows, and never name a widget
/// type.
///
/// The seam is what let the Tier 3 chrome swap of the picker
/// (`docs/calendar-language-tier-3-roadmap.md`, slice 5) land under the
/// suite that pinned the old chrome: the rebuild rewrote this file and left
/// the bodies alone, but for the actions that record moves on purpose. The
/// geometry box, the slider, the hex field and the before/after dots are the
/// picker's own and stay; ✕ and Select are the header's, by their ids, and
/// the Square / Wheel choice is the chip row under it.
///
/// Every read and act works on whatever picker is open — [show] is one way
/// to get one; a page that opens the picker itself (the markdown colours
/// page) drives it through the same handle.
class ColorPickerRobot {
  const ColorPickerRobot(this.tester);

  final WidgetTester tester;

  static const String _openLabel = 'open';

  static const Key _squareKey = ValueKey('color_picker_square');
  static const Key _wheelKey = ValueKey('color_picker_wheel');

  Finder get _sheet => find.byType(ColorPickerSheet);

  Finder _in(Finder matching) =>
      find.descendant(of: _sheet, matching: matching);

  Finder _byId(String id) => _in(find.bySemanticsIdentifier(id));

  AppLocalizations get _l10n => AppLocalizations.of(tester.element(_sheet))!;

  Finder get _hexField => _in(find.byType(TextField));

  Finder get _select => _byId(SemanticsIds.colorPickerSelect);

  Finder get _close => _byId(SemanticsIds.colorPickerClose);

  /// The geometry the picker draws now: the square or the wheel.
  Finder get _geometry => _in(
    find.byWidgetPredicate((w) => w.key == _squareKey || w.key == _wheelKey),
  );

  static String _modeId(ColorPickerMode mode) => switch (mode) {
    ColorPickerMode.square => SemanticsIds.colorModeSquare,
    ColorPickerMode.wheel => SemanticsIds.colorModeWheel,
  };

  /// The chip of [mode], read for its state. An id lands on the node inside
  /// the chip, so the chip is the id's nearest ancestor of its type.
  FormChip _chip(ColorPickerMode mode) => tester.widget<FormChip>(
    find
        .ancestor(of: _byId(_modeId(mode)), matching: find.byType(FormChip))
        .first,
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

  /// Opens the picker the way its callers do — through `show`, from a button
  /// on a page — and captures its result. The sheet resolves its remembered
  /// geometry before presenting, so it arrives a microtask after the tap:
  /// two settles.
  Future<ColorPickerOutcome> show({
    int? initialColor,
    Locale locale = const Locale('en'),
    double? textScale,
    Size? surface,
  }) async {
    if (surface != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
    }
    final outcome = ColorPickerOutcome();
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
                outcome.result = await ColorPickerSheet.show(
                  context,
                  initialColor: initialColor,
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
    await tester.pumpAndSettle();
    return outcome;
  }

  bool get isOpen => _shown(_sheet);

  // --- The hex field ---------------------------------------------------------

  Future<void> typeHex(String text) async {
    await tester.enterText(_hexField, text);
    await tester.pumpAndSettle();
  }

  String get hexText => tester.widget<TextField>(_hexField).controller!.text;

  /// The error the field shows under a rejected code, or null.
  String? get hexError =>
      tester.widget<TextField>(_hexField).decoration?.errorText;

  Rect get hexFieldRect => tester.getRect(_hexField);

  Rect get copyButtonRect => tester.getRect(_byId(SemanticsIds.colorCopyHex));

  Future<void> copyHex() => _tap(_byId(SemanticsIds.colorCopyHex));

  /// Whether the "Copied" confirmation is on screen.
  bool get copiedMessageShown => _shown(find.text(_l10n.colorHexCopied));

  /// Whether that confirmation is where a finger can reach it — above the
  /// sheet, not on the page under it.
  bool get copiedMessageReachable =>
      _shown(find.text(_l10n.colorHexCopied).hitTestable());

  // --- The geometry ----------------------------------------------------------

  /// The mode the chips say is on — and the geometry drawn under them, which
  /// has to agree.
  ColorPickerMode get currentMode {
    final selected = [
      for (final mode in ColorPickerMode.values)
        if (_chip(mode).selected) mode,
    ];
    if (selected.length != 1) fail('Expected one chip on, found $selected');
    final mode = selected.single;
    final drawn = _shown(
      _in(find.byKey(mode == ColorPickerMode.square ? _squareKey : _wheelKey)),
    );
    if (!drawn) fail('The chips say $mode but the geometry drawn is not it');
    return mode;
  }

  Future<void> pickMode(ColorPickerMode mode) => _tap(_byId(_modeId(mode)));

  Rect get geometryRect => tester.getRect(_geometry);

  /// Drags from the centre of the geometry by [delta].
  Future<void> dragGeometry(Offset delta) async {
    await tester.dragFrom(geometryRect.center, delta);
    await tester.pumpAndSettle();
  }

  int get sliderCount => _in(find.byType(Slider)).evaluate().length;

  /// Drags the one slider by [dx] along its track.
  Future<void> dragSlider(double dx) async {
    await tester.drag(_in(find.byType(Slider)), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  // --- The before/after pair -------------------------------------------------

  bool get currentDotShown =>
      _shown(_in(find.byTooltip(_l10n.colorPickerCurrent)));

  bool get newDotShown => _shown(_in(find.byTooltip(_l10n.colorPickerNew)));

  /// Taps the colour the picker opened on, which puts it back.
  Future<void> tapCurrentDot() =>
      _tap(_in(find.byTooltip(_l10n.colorPickerCurrent)));

  /// The on-screen size of each preview dot's target: the current colour's
  /// while replacing, then the new colour's.
  List<Size> get dotTargets => [
    for (final tooltip in [_l10n.colorPickerCurrent, _l10n.colorPickerNew])
      if (_shown(_in(find.byTooltip(tooltip))))
        tester.getSize(_in(find.byTooltip(tooltip))),
  ];

  // --- Select and cancel -----------------------------------------------------

  bool get selectShown => _shown(_select);

  /// What the header's action reads.
  String get selectLabel => tester
      .widget<FormHeaderTextButton>(
        find
            .ancestor(of: _select, matching: find.byType(FormHeaderTextButton))
            .first,
      )
      .label;

  Rect get selectRect => tester.getRect(_select);

  Future<void> select() => _tap(_select);

  Future<void> cancel() => _tap(_close);

  // --- Geometry and semantics ------------------------------------------------

  /// The semantics of the control carrying [id].
  SemanticsData nodeOf(String id) =>
      tester.getSemantics(_byId(id)).getSemanticsData();

  /// The on-screen rect of the control carrying [id].
  Rect targetOf(String id) => tester.getRect(_byId(id));

  Rect get sheetRect => tester.getRect(_sheet);
}
