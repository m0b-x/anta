import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/widgets/category_editor_sheet.dart';
import 'package:anta/widgets/color_swatch_picker.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/icon_picker_sheet.dart';

import 'swatch_robot.dart';

/// What `CategoryEditorSheet.show` resolved to. Mutable, because the sheet is
/// awaited inside a button callback and the value arrives after the tap that
/// dismissed it.
class CategoryEditorOutcome {
  CalendarCategory? result;
  bool returned = false;
}

/// Drives the category editor — [CategoryEditorSheet] — for the suites: they
/// say what the user does and read what the sheet shows, and never name a
/// widget type.
///
/// The seam is what let the Tier 3 rebuild of the sheet
/// (`docs/calendar-language-tier-3-roadmap.md`, slice 3) land under the
/// suite that pinned the old chrome: the rebuild rewrote this file and left
/// the bodies alone, but for the behaviour that record changes on purpose.
/// The finders are the sub-sheet's: the ✕, Save, the name field and the Icon
/// row by their ids; the name as the title row with its warning and counter
/// lines; a built-in's name as a read row; the draft's avatar on either; the
/// failure message as the overlay bar above the sheet.
///
/// The icon picker and the colour strip it opens or embeds are driven
/// through their own handles — the picker has been on the UI language since
/// Tier 1, and the strip through [SwatchRobot].
class CategoryEditorRobot {
  const CategoryEditorRobot(this.tester);

  final WidgetTester tester;

  static const String _openLabel = 'open';

  static final RegExp _counterPattern = RegExp(r'^\d+/\d+$');

  Finder get _sheet => find.byType(CategoryEditorSheet);

  Finder _in(Finder matching) =>
      find.descendant(of: _sheet, matching: matching);

  Finder _byId(String id) => _in(find.bySemanticsIdentifier(id));

  AppLocalizations get _l10n => AppLocalizations.of(tester.element(_sheet))!;

  Finder get _close => _byId(SemanticsIds.categoryEditorClose);

  Finder get _save => _byId(SemanticsIds.categoryEditorSave);

  Finder get _iconRow => _byId(SemanticsIds.categoryEditorIcon);

  /// The title row a custom category's name is typed into.
  Finder get _nameRow => _in(find.byType(FormTitleRow));

  /// The field inside it, reached through the id a device script types by.
  Finder get _nameField => find.descendant(
    of: _byId(SemanticsIds.categoryEditorName),
    matching: find.byType(EditableText),
  );

  /// The read row a built-in's name is: the one picker row wearing the
  /// avatar (the Icon row carries a glyph).
  Finder get _builtInRow => _in(
    find.byWidgetPredicate((w) => w is FormPickerRow && w.leading != null),
  );

  /// The avatar previewing the draft — the title row's, or the read row's.
  Finder get _avatar => _in(find.byType(EventAvatar));

  /// The warning line under the name: the title row's own, in the error
  /// colour.
  Finder get _warningLine => find.descendant(
    of: _nameRow,
    matching: find.byWidgetPredicate((w) => w is FormCaption && w.error),
  );

  /// The "n/40" line under the name.
  Finder get _counter => find.descendant(
    of: _nameRow,
    matching: find.byWidgetPredicate(
      (w) => w is Text && w.data != null && _counterPattern.hasMatch(w.data!),
    ),
  );

  Finder get _picker => find.byType(IconPickerSheet);

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
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  SemanticsData _dataOf(Finder target) =>
      tester.getSemantics(target).getSemanticsData();

  /// Opens the editor the way its callers do — through `show`, from a button
  /// on a page — and captures its result.
  Future<CategoryEditorOutcome> show({
    CalendarCategory? initial,
    String? initialName,
    Locale locale = const Locale('en'),
    double? textScale,
    Size? surface,
  }) async {
    if (surface != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
    }
    final outcome = CategoryEditorOutcome();
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
                outcome.result = await CategoryEditorSheet.show(
                  context,
                  initial: initial,
                  initialName: initialName,
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

  bool get isOpen => _shown(_sheet);

  /// The header's title: create or edit.
  String get title {
    for (final candidate in [_l10n.createCategory, _l10n.editCategory]) {
      if (_shown(_in(find.text(candidate)))) return candidate;
    }
    fail('The sheet carries neither title');
  }

  /// The header's title as the header was handed it, whatever the width
  /// made of it on screen.
  String get headerTitle =>
      tester.widget<FormSheetHeader>(_in(find.byType(FormSheetHeader))).title;

  /// The trailing action's label, as handed to it.
  String get saveLabel => tester
      .widget<FormHeaderTextButton>(_in(find.byType(FormHeaderTextButton)))
      .label;

  // --- The name --------------------------------------------------------------

  /// Leaves the text exactly as typed — trimming is the sheet's to do on Save.
  Future<void> typeName(String text) async {
    await tester.enterText(_nameField, text);
    await tester.pump();
  }

  String get nameText =>
      tester.widget<EditableText>(_nameField).controller.text;

  /// Whether the name holds the focus, which is what keeps a keyboard up.
  bool get nameFocused =>
      tester.widget<EditableText>(_nameField).focusNode.hasFocus;

  /// Whether the name is a built-in's: a read row — fully drawn, no tap, no
  /// chevron — where a custom category has the field.
  bool get isBuiltInName {
    if (!_shown(_builtInRow)) return false;
    final row = tester.widget<FormPickerRow>(_builtInRow);
    return row.onTap == null && !row.showChevron && !_shown(_nameRow);
  }

  /// The read-only name a built-in shows, or null for a custom category.
  String? get builtInNameText =>
      _shown(_builtInRow) ? tester.widget<FormPickerRow>(_builtInRow).label : null;

  bool get builtInCaptionShown => _shown(_in(find.text(_l10n.categoryDefault)));

  /// The read row's one semantics node: what a screen reader hears for a
  /// built-in's name.
  SemanticsData get builtInRowSemantics => _dataOf(_builtInRow);

  /// Whether the read row is one node with nothing of its own folded under
  /// it — the avatar excluded, the caption merged in.
  bool get builtInRowIsOneNode =>
      tester.getSemantics(_builtInRow).childrenCount == 0;

  /// The duplicate warning under the name, or null while there is none.
  String? get warningText =>
      _shown(_warningLine) ? tester.widget<FormCaption>(_warningLine).text : null;

  /// The colour the warning is drawn in.
  Color? get warningColor => tester
      .widget<Text>(find.descendant(of: _warningLine, matching: find.byType(Text)))
      .style
      ?.color;

  /// The "n/40" line under the name, or null while it is not drawn.
  String? get counterText =>
      _shown(_counter) ? tester.widget<Text>(_counter).data : null;

  /// The colour the counter is drawn in.
  Color? get counterColor => tester.widget<Text>(_counter).style?.color;

  // --- The preview -----------------------------------------------------------

  IconData get previewIcon => tester.widget<EventAvatar>(_avatar).icon;

  Color get previewColor => tester.widget<EventAvatar>(_avatar).color;

  // --- The icon --------------------------------------------------------------

  /// Opens the icon picker from the Icon row; returns with it up.
  Future<void> tapIcon() => _tap(_iconRow);

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
    await tester.tap(find.descendant(of: _picker, matching: find.byTooltip(name)));
    await tester.pumpAndSettle();
  }

  /// ✕ on the icon picker: the draft keeps the icon it had.
  Future<void> cancelIconPicker() async {
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.iconPickClose));
    await tester.pumpAndSettle();
  }

  // --- The colour ------------------------------------------------------------

  SwatchRobot get swatches => SwatchRobot(tester, within: _sheet);

  Future<void> pickSwatch(int argb) => swatches.tap(argb);

  int? get selectedSwatch => swatches.selectedColor;

  /// Whether the strip's row is a container above the swatches' own nodes
  /// — never a merge that would fold them into one.
  bool get swatchRowIsContainer =>
      tester.getSemantics(_byId(SemanticsIds.swatchRow)).childrenCount > 1;

  /// The on-screen size of every dot the strip draws, add and manage
  /// included.
  List<Size> get dotTargets => [
    for (final dot in _in(find.byType(ColorSwatchDot)).evaluate())
      tester.getSize(find.byWidget(dot.widget)),
  ];

  // --- Geometry ---------------------------------------------------------------

  /// The on-screen rect of the control carrying [id].
  Rect targetOf(String id) => tester.getRect(_byId(id));

  Rect get nameRowRect => tester.getRect(_nameRow);

  Rect get builtInRowRect => tester.getRect(_builtInRow);

  Rect get sheetRect => tester.getRect(_sheet);

  /// The semantics of the control carrying [id].
  SemanticsData nodeOf(String id) => _dataOf(_byId(id));

  /// Whether the one text [text] in the sheet is drawn whole — no line
  /// limit, nothing cut by an ellipsis — and inside the sheet's width.
  bool textWhole(String text) {
    final finder = _in(find.text(text));
    if (tester.widget<Text>(finder).maxLines != null) return false;
    if (tester.renderObject<RenderParagraph>(finder).didExceedMaxLines) {
      return false;
    }
    final rect = tester.getRect(finder);
    final sheet = sheetRect;
    return rect.left >= sheet.left && rect.right <= sheet.right;
  }

  /// The sheet's colours, for a line whose colour says what it is.
  ColorScheme get colorScheme => Theme.of(tester.element(_sheet)).colorScheme;

  // --- Saving and leaving ----------------------------------------------------

  bool get canSave =>
      tester
          .widget<TextButton>(
            find.descendant(of: _save, matching: find.byType(TextButton)),
          )
          .onPressed !=
      null;

  Future<void> save() => _tap(_save);

  /// Whether the "Couldn't save" notice is on screen anywhere.
  bool get saveFailureShown => _shown(find.text(_l10n.categorySaveFailed));

  /// Whether that notice is where a finger can reach it — above the sheet,
  /// not on the page under it.
  bool get saveFailureReachable =>
      _shown(find.text(_l10n.categorySaveFailed).hitTestable());

  Future<void> close() => _tap(_close);

  Future<void> systemBack() async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  /// A tap on the scrim above the sheet.
  Future<void> tapBarrier() async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width / 2, 8));
    await tester.pumpAndSettle();
  }
}
