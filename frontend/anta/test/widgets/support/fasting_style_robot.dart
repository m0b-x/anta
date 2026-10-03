import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/widgets/color_swatch_picker.dart';
import 'package:anta/widgets/event_description_sheet.dart';
import 'package:anta/widgets/fasting_style_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/icon_picker_sheet.dart';

import 'swatch_robot.dart';

/// Drives the fasting style sheet — [FastingStyleSheet] — for the suites:
/// they say what the user does and read what the sheet shows, and never
/// name a widget type.
///
/// The seam is what let the Tier 3 rebuild of the sheet
/// (`docs/calendar-language-tier-3-roadmap.md`, slice 4) land under the
/// suite that pinned the old chrome: the rebuild rewrote this file and left
/// the bodies alone, but for the behaviour that record changes on purpose.
/// The finders are the sub-sheet's: the ✕, the two menu rows and their
/// items, the Icon row and its reset, the Custom title row and its clear,
/// the Description row by their ids; the preview as the first group; the
/// title in its dialog and the description in its sheet.
///
/// The icon picker, the description sheet and the colour strip are driven
/// through their own handles — the first two have been on the UI language
/// since Tier 1, and the strip through [SwatchRobot].
class FastingStyleRobot {
  const FastingStyleRobot(this.tester);

  final WidgetTester tester;

  static const String _openLabel = 'open';

  /// Tall enough that the sheet shows every row without scrolling; the
  /// layout cases size their own phone.
  static const Size defaultSurface = Size(800, 1600);

  Finder get _sheet => find.byType(FastingStyleSheet);

  Finder _in(Finder matching) =>
      find.descendant(of: _sheet, matching: matching);

  Finder _byId(String id) => _in(find.bySemanticsIdentifier(id));

  AppLocalizations get _l10n => AppLocalizations.of(tester.element(_sheet))!;

  /// The sheet's own strings, for a case that pins layout rather than copy.
  AppLocalizations get l10n => _l10n;

  Finder get _picker => find.byType(IconPickerSheet);

  Finder get _descriptionSheet => find.byType(EventDescriptionSheet);

  Finder get _titleDialog => find.byType(AlertDialog);

  /// The preview leads the body: the first group.
  Finder get _preview => _in(find.byType(FormRowGroup)).first;

  FormPickerRow _pickerRow(String id) => tester.widget(
    _in(
      find.byWidgetPredicate(
        (widget) => widget is FormPickerRow && widget.identifier == id,
      ),
    ),
  );

  FormMenuRow<T> _menuRow<T>(String id) => tester.widget(
    _in(
      find.byWidgetPredicate(
        (widget) => widget is FormMenuRow<T> && widget.identifier == id,
      ),
    ),
  );

  static String _gridItemId(FastingDisplayStyle style) => switch (style) {
    FastingDisplayStyle.tint => SemanticsIds.fastingStyleGridTint,
    FastingDisplayStyle.bar => SemanticsIds.fastingStyleGridBar,
    FastingDisplayStyle.strong => SemanticsIds.fastingStyleGridStrong,
    FastingDisplayStyle.none => SemanticsIds.fastingStyleGridNone,
  };

  static String _placementItemId(FastingRowPlacement placement) =>
      switch (placement) {
        FastingRowPlacement.first => SemanticsIds.fastingStylePlacementFirst,
        FastingRowPlacement.beforeHolidays =>
          SemanticsIds.fastingStylePlacementBeforeHolidays,
        FastingRowPlacement.afterHolidays =>
          SemanticsIds.fastingStylePlacementAfterHolidays,
        FastingRowPlacement.last => SemanticsIds.fastingStylePlacementLast,
      };

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

  /// The body's scroll view, whose bounds decide whether a control has to be
  /// brought into view first.
  Finder get _body => _in(find.byType(SingleChildScrollView));

  /// Whether [target] already sits inside the body's viewport. `ensureVisible`
  /// scrolls its target to the leading edge whether or not it was visible,
  /// and a tap must not move the body under a suite comparing rects.
  bool _inView(Finder target) {
    if (_body.evaluate().isEmpty) return true;
    final rect = tester.getRect(target);
    final body = tester.getRect(_body);
    return rect.top >= body.top && rect.bottom <= body.bottom;
  }

  Future<void> _tap(Finder target) async {
    if (!_inView(target)) {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// A control on a route above the sheet — a menu item, a dialog button —
  /// which is never under the fold.
  Future<void> _tapAbove(Finder target) async {
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  SemanticsData _dataOf(Finder target) =>
      tester.getSemantics(target).getSemanticsData();

  /// Opens the sheet the way Calendar settings does — through `show`, from a
  /// button on a page. Every change goes out through [onChanged]; there is
  /// nothing to return.
  ///
  /// [barBloc] is the app-wide markdown bar bloc the description sheet reads
  /// from its `initState`; it sits above the `MaterialApp` as `main.dart`
  /// provides it, because a sheet is a route and a provider inside `home`
  /// would be below it. A suite that never opens the description leaves it
  /// out.
  Future<void> show({
    FastingTradition tradition = FastingTradition.orthodox,
    FastingTraditionStyle initialStyle = const FastingTraditionStyle(),
    required ValueChanged<FastingTraditionStyle> onChanged,
    Locale locale = const Locale('en'),
    Size surface = defaultSurface,
    double? textScale,
    MarkdownBarBloc? barBloc,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    final app = MaterialApp(
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
            onPressed: () => FastingStyleSheet.show(
              context,
              tradition: tradition,
              initialStyle: initialStyle,
              onChanged: onChanged,
            ),
            child: const Text(_openLabel),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      barBloc == null
          ? app
          : BlocProvider<MarkdownBarBloc>.value(value: barBloc, child: app),
    );
    await tester.tap(find.text(_openLabel));
    await tester.pumpAndSettle();
  }

  bool get isOpen => _shown(_sheet);

  /// The header's title: the tradition's name, as the header was handed it.
  String get title =>
      tester.widget<FormSheetHeader>(_in(find.byType(FormSheetHeader))).title;

  /// Lets [duration] of fake time pass. Every write is immediate now; kept
  /// for the bodies that still pace themselves by it.
  Future<void> elapse(Duration duration) => tester.pump(duration);

  // --- The grid style and the placement --------------------------------------

  Future<void> openGridMenu() => _tap(_byId(SemanticsIds.fastingStyleGrid));

  Future<void> pickStyle(FastingDisplayStyle style) async {
    await openGridMenu();
    await _tapAbove(find.bySemanticsIdentifier(_gridItemId(style)));
  }

  FastingDisplayStyle get style =>
      _menuRow<FastingDisplayStyle>(SemanticsIds.fastingStyleGrid).selected;

  /// What the grid row reads back.
  String get styleLabel =>
      _menuRow<FastingDisplayStyle>(SemanticsIds.fastingStyleGrid).value;

  Future<void> openPlacementMenu() =>
      _tap(_byId(SemanticsIds.fastingStylePlacement));

  Future<void> pickPlacement(FastingRowPlacement placement) async {
    await openPlacementMenu();
    await _tapAbove(find.bySemanticsIdentifier(_placementItemId(placement)));
  }

  FastingRowPlacement get placement => _menuRow<FastingRowPlacement>(
    SemanticsIds.fastingStylePlacement,
  ).selected;

  String get placementLabel =>
      _menuRow<FastingRowPlacement>(SemanticsIds.fastingStylePlacement).value;

  /// Whether the open menu offers the item carrying [id].
  bool menuItemShown(String id) => _shown(find.bySemanticsIdentifier(id));

  /// Whether the open menu's item carrying [id] wears the check — what a
  /// screen reader hears as the current choice.
  bool menuItemChecked(String id) =>
      tester
          .getSemantics(find.bySemanticsIdentifier(id))
          .getSemanticsData()
          .flagsCollection
          .isChecked ==
      CheckedState.isTrue;

  /// Whether a menu is up: the popup's items are on screen.
  bool get menuOpen =>
      find.byWidgetPredicate((w) => w is PopupMenuItem).evaluate().isNotEmpty;

  /// Leaves the open menu through its barrier, picking nothing.
  Future<void> dismissMenu() async {
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
  }

  // --- The colour ------------------------------------------------------------

  SwatchRobot get swatches => SwatchRobot(tester, within: _sheet);

  Future<void> pickSwatch(int argb) => swatches.tap(argb);

  /// The leading dot: back to the shared fasting colour.
  Future<void> useDefaultColor() => swatches.tapDefault();

  /// Whether the strip's row is a container above the swatches' own nodes
  /// — never a merge that would fold them into one.
  bool get swatchRowIsContainer =>
      tester.getSemantics(_byId(SemanticsIds.swatchRow)).childrenCount > 1;

  /// The on-screen size of every dot the strip draws, default, add and
  /// manage included.
  List<Size> get dotTargets => [
    for (final dot in _in(find.byType(ColorSwatchDot)).evaluate())
      tester.getSize(find.byWidget(dot.widget)),
  ];

  // --- The icon --------------------------------------------------------------

  /// What the Icon row reads: the tradition's default, or a custom icon.
  String get iconLabel => _pickerRow(SemanticsIds.fastingStyleIcon).value!;

  bool get hasIconReset => _shown(_byId(SemanticsIds.fastingStyleIconReset));

  /// Back to the tradition's own icon.
  Future<void> resetIcon() => _tap(_byId(SemanticsIds.fastingStyleIconReset));

  /// Opens the icon picker from the Icon row; returns with it up.
  Future<void> tapIcon() => _tap(_byId(SemanticsIds.fastingStyleIcon));

  bool get iconPickerOpen => _shown(_picker);

  /// Picks the icon with [key] in the icon picker, through its search.
  Future<void> chooseIcon(String key) async {
    if (!iconPickerOpen) await tapIcon();
    final name = key.replaceAll('_', ' ');
    await tester.enterText(
      find.descendant(of: _picker, matching: find.byType(TextField)),
      name,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: _picker, matching: find.byTooltip(name)),
    );
    await tester.pumpAndSettle();
  }

  /// ✕ on the icon picker: the style keeps the icon it had.
  Future<void> cancelIconPicker() async {
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.iconPickClose));
    await tester.pumpAndSettle();
  }

  // --- The title -------------------------------------------------------------

  /// Opens the title's dialog from the Custom title row; returns with it up.
  Future<void> openTitle() => _tap(_byId(SemanticsIds.fastingStyleTitle));

  bool get titleDialogOpen => _shown(_titleDialog);

  Finder get _titleDialogField =>
      find.descendant(of: _titleDialog, matching: find.byType(TextField));

  /// Types [text] into the open dialog and confirms it. Leaves the text
  /// exactly as typed — trimming is the model's to do.
  Future<void> typeTitle(String text) async {
    if (!titleDialogOpen) await openTitle();
    await tester.enterText(_titleDialogField, text);
    await tester.pump();
    await confirmTitle();
  }

  /// The dialog's confirming button.
  Future<void> confirmTitle() =>
      _tapAbove(find.bySemanticsIdentifier(SemanticsIds.sheetConfirm));

  /// The dialog's way out: the title stays what it was.
  Future<void> cancelTitle() =>
      _tapAbove(find.bySemanticsIdentifier(SemanticsIds.sheetCancel));

  /// The override the Custom title row reads back, or '' while it reads the
  /// default.
  String get titleText {
    final row = _pickerRow(SemanticsIds.fastingStyleTitle);
    return row.trailingButton == null ? '' : row.value!;
  }

  /// What the Custom title row reads as its value, override or default.
  String get titleLabel => _pickerRow(SemanticsIds.fastingStyleTitle).value!;

  /// What the empty title shows: the name the calendar works out, as the
  /// dialog's hint. Read by opening the dialog and leaving it unchanged.
  Future<String> titleHint() async {
    await openTitle();
    final hint = tester
        .widget<TextField>(_titleDialogField)
        .decoration
        ?.hintText;
    await cancelTitle();
    return hint ?? '';
  }

  bool get hasTitleClear => _shown(_byId(SemanticsIds.fastingStyleTitleClear));

  /// The title's clear button, shown while an override is set.
  Future<void> clearTitle() => _tap(_byId(SemanticsIds.fastingStyleTitleClear));

  // --- The description -------------------------------------------------------

  /// Opens the description sheet from the Description row; returns with it
  /// up.
  Future<void> openDescription() =>
      _tap(_byId(SemanticsIds.fastingStyleDescription));

  bool get descriptionSheetOpen => _shown(_descriptionSheet);

  CodeLineEditingController get _descriptionController => tester
      .widget<CodeEditor>(
        find.descendant(
          of: _descriptionSheet,
          matching: find.byType(CodeEditor),
        ),
      )
      .controller!;

  /// Rewrites the text in the open description sheet the way the app does,
  /// through the controller: its editor is not an `EditableText`, so
  /// `enterText` has nothing to drive.
  Future<void> replaceDescription(String text) async {
    _descriptionController.text = text;
    await tester.pump();
  }

  /// Done on the description sheet: its text becomes the style's.
  Future<void> confirmDescription() =>
      _tapAbove(find.bySemanticsIdentifier(SemanticsIds.descriptionDone));

  /// ✕ on the description sheet, through its own question when the text was
  /// changed: the style keeps the description it had.
  Future<void> cancelDescription() async {
    await _tapAbove(find.bySemanticsIdentifier(SemanticsIds.descriptionClose));
    if (_shown(find.text(_l10n.discardChanges))) {
      await _tapAbove(find.text(_l10n.discardChanges));
    }
  }

  /// Opens the description sheet, replaces its text with [text] and
  /// confirms with Done.
  Future<void> typeDescription(String text) async {
    if (!descriptionSheetOpen) await openDescription();
    await replaceDescription(text);
    await confirmDescription();
  }

  /// The description the Description row reads back — the text with its
  /// markdown markers dropped — or '' while it shows the hint.
  String get descriptionText {
    final caption = _pickerRow(SemanticsIds.fastingStyleDescription).caption!;
    return caption == _l10n.fastingDescriptionHint ? '' : caption;
  }

  /// What the Description row's line reads, hint or text.
  String get descriptionCaption =>
      _pickerRow(SemanticsIds.fastingStyleDescription).caption!;

  Finder get _descriptionCaptionText => find.descendant(
    of: _byId(SemanticsIds.fastingStyleDescription),
    matching: find.text(descriptionCaption),
  );

  /// Whether the Description row's line is cut short by an ellipsis.
  bool get descriptionCaptionClamped => tester
      .renderObject<RenderParagraph>(_descriptionCaptionText)
      .didExceedMaxLines;

  /// How many lines the Description row's line is drawn on: its height over
  /// the line its style sets.
  int get descriptionCaptionLines {
    final style = tester.widget<Text>(_descriptionCaptionText).style!;
    final lineHeight = style.fontSize! * style.height!;
    return (tester.getSize(_descriptionCaptionText).height / lineHeight)
        .round();
  }

  // --- The preview -----------------------------------------------------------

  IconData get previewIcon => tester
      .widget<Icon>(find.descendant(of: _preview, matching: find.byType(Icon)))
      .icon!;

  /// The preview's lines: the sample day number, the title, the regime and,
  /// when set, the description.
  List<String> get _previewLines => [
    for (final text in tester.widgetList<Text>(
      find.descendant(of: _preview, matching: find.byType(Text)),
    ))
      text.data ?? '',
  ];

  String get previewTitle => _previewLines[1];

  String get previewSubtitle => _previewLines[2];

  String? get previewDescription =>
      _previewLines.length > 3 ? _previewLines[3] : null;

  /// The preview's sample day number as drawn, for its box.
  Rect get previewDayNumberRect => tester.getRect(
    find.descendant(of: _preview, matching: find.text(_previewLines[0])),
  );

  /// Whether the preview sits on a card of its own, which the language
  /// forbids in a sheet.
  bool get previewOnCard => _in(find.byType(Card)).evaluate().isNotEmpty;

  // --- Geometry and semantics ------------------------------------------------

  /// The on-screen rect of the control carrying [id].
  Rect targetOf(String id) => tester.getRect(_byId(id));

  Rect get sheetRect => tester.getRect(_sheet);

  /// The semantics of the control carrying [id].
  SemanticsData nodeOf(String id) => _dataOf(_byId(id));

  /// Whether every drawing of [text] in the sheet is whole — no line limit,
  /// nothing cut by an ellipsis — and inside the sheet's width. False when
  /// the sheet draws it nowhere.
  bool textWhole(String text) {
    final matches = _in(find.text(text)).evaluate();
    if (matches.isEmpty) return false;
    final sheet = sheetRect;
    for (final element in matches) {
      final finder = find.byElementPredicate((e) => identical(e, element));
      if (tester.widget<Text>(finder).maxLines != null) return false;
      if (tester.renderObject<RenderParagraph>(finder).didExceedMaxLines) {
        return false;
      }
      final rect = tester.getRect(finder);
      if (rect.left < sheet.left || rect.right > sheet.right) return false;
    }
    return true;
  }

  /// Whether the label of the control carrying [id] — a row's first line —
  /// is drawn whole: no line limit, nothing cut, inside the sheet's width.
  bool controlLabelWhole(String id) {
    final text = find
        .descendant(of: _byId(id), matching: find.byType(Text))
        .first;
    if (tester.widget<Text>(text).maxLines != null) return false;
    if (tester.renderObject<RenderParagraph>(text).didExceedMaxLines) {
      return false;
    }
    final rect = tester.getRect(text);
    final sheet = sheetRect;
    return rect.left >= sheet.left && rect.right <= sheet.right;
  }

  /// Whether the section label built from [source] is drawn whole; the
  /// label draws capitals, so it is found by its source text.
  bool sectionLabelWhole(String source) {
    final label = _in(
      find.byWidgetPredicate(
        (widget) => widget is FormSectionLabel && widget.text == source,
      ),
    );
    final text = find.descendant(of: label, matching: find.byType(Text));
    if (tester.widget<Text>(text).maxLines != null) return false;
    if (tester.renderObject<RenderParagraph>(text).didExceedMaxLines) {
      return false;
    }
    final rect = tester.getRect(text);
    final sheet = sheetRect;
    return rect.left >= sheet.left && rect.right <= sheet.right;
  }

  // --- Leaving ---------------------------------------------------------------

  Future<void> close() => _tap(_byId(SemanticsIds.fastingStyleClose));

  Future<void> systemBack() async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }
}
