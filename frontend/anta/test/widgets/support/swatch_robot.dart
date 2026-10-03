import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_palette.dart';
import 'package:anta/widgets/color_palette_sheet.dart';
import 'package:anta/widgets/color_picker_sheet.dart';
import 'package:anta/widgets/color_swatch_picker.dart';
import 'package:anta/widgets/form_menu_item.dart';

/// Drives the colour strip — [ColorSwatchPicker] — wherever it stands: on
/// its own, or inside a sheet named by [within]. The suites say which dot
/// the user taps and read which is selected, and never name a widget type.
///
/// The seam is what let the Tier 3 rebuild of the strip's menu, ids and
/// refusals (`docs/calendar-language-tier-3-roadmap.md`, slice 1) land under
/// the suites that pinned it before. A swatch is addressed by its colour and
/// found by the hex it announces; the default, add, manage and show-more dots
/// by the glyph or tooltip they wear; the long-press menu's items by the
/// menu rows of the language they are drawn with.
class SwatchRobot {
  const SwatchRobot(this.tester, {Finder? within}) : _within = within;

  final WidgetTester tester;

  final Finder? _within;

  Finder _scope(Finder matching) {
    final within = _within;
    return within == null
        ? matching
        : find.descendant(of: within, matching: matching);
  }

  Finder get _dots => _scope(find.byType(ColorSwatchDot));

  /// The swatch of [argb]: a palette colour or an orphan, each named by its
  /// hex. The default dot is never one — it announces its meaning, not a
  /// colour — so a default wearing the same colour cannot be mistaken for it.
  Finder _swatch(int argb) => _scope(
    find.byWidgetPredicate(
      (w) => w is ColorSwatchDot && w.semanticLabel == CalendarPalette.hexOf(argb),
    ),
  );

  /// The leading "no colour of my own" dot: a coloured dot with no hex.
  Finder get _defaultDot => _scope(
    find.byWidgetPredicate(
      (w) => w is ColorSwatchDot && w.color != null && w.semanticLabel == null,
    ),
  );

  Finder _glyphDot(IconData icon) => _scope(
    find.byWidgetPredicate((w) => w is ColorSwatchDot && w.icon == icon),
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

  /// A strip inside a sheet can sit under the fold on a phone-sized
  /// surface, so a dot is brought into view before it is tapped.
  Future<void> _tap(Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Every dot the strip draws, in order: the default and orphan first, the
  /// palette, the show-more dot while collapsed, then add and manage.
  List<ColorSwatchDot> dots() =>
      tester.widgetList<ColorSwatchDot>(_dots).toList();

  /// The swatch of [argb], read for its state.
  ColorSwatchDot dot(int argb) => tester.widget<ColorSwatchDot>(_swatch(argb));

  bool hasSwatch(int argb) => _shown(_swatch(argb));

  bool isSelected(int argb) => dot(argb).selected;

  /// The colour whose swatch wears the check, or null while the check is on
  /// the default dot or on nothing.
  int? get selectedColor {
    final selected = [
      for (final dot in dots())
        if (dot.selected && dot.semanticLabel != null) dot.color!.toARGB32(),
    ];
    if (selected.length > 1) {
      fail('Expected at most one selected swatch, found $selected');
    }
    return selected.firstOrNull;
  }

  int get selectedCount => dots().where((dot) => dot.selected).length;

  bool get hasDefault => _shown(_defaultDot);

  /// Whether the default dot wears the check: no colour of one's own.
  bool get defaultSelected =>
      tester.widget<ColorSwatchDot>(_defaultDot).selected;

  /// The glyph the default dot is told to draw — the caller's, or the one
  /// the strip falls back to. Read from the widget, which keeps it while the
  /// check covers it.
  IconData? get defaultGlyph => tester.widget<ColorSwatchDot>(_defaultDot).icon;

  /// The semantics of the node carrying [id] — a dot's own, with its label,
  /// tooltip and selected state.
  SemanticsData nodeOf(String id) =>
      tester.getSemantics(find.bySemanticsIdentifier(id)).getSemanticsData();

  /// The target of the swatch of [argb].
  Rect dotRect(int argb) => tester.getRect(_swatch(argb));

  /// Whether a swatch offers the long-press menu — the user's own do, the
  /// built-ins never.
  bool offersMenu(int argb) => dot(argb).onLongPress != null;

  /// Whether the strip hides part of the palette behind a show-more dot.
  bool get isCollapsed => _shown(_glyphDot(Icons.more_horiz_rounded));

  /// Whether the strip was told it may fold the palette at all.
  bool get collapsible => tester
      .widget<ColorSwatchPicker>(_scope(find.byType(ColorSwatchPicker)))
      .collapsible;

  bool get hasAdd => _shown(_glyphDot(Icons.colorize_rounded));

  bool get hasManage => _shown(_glyphDot(Icons.palette_outlined));

  Future<void> tap(int argb) => _tap(_swatch(argb));

  Future<void> tapDefault() => _tap(_defaultDot);

  /// The add dot: opens the colour picker, which resolves its remembered
  /// geometry before it presents and so arrives a frame late.
  Future<void> tapAdd() async {
    await _tap(_glyphDot(Icons.colorize_rounded));
    await tester.pumpAndSettle();
  }

  Future<void> tapManage() => _tap(_glyphDot(Icons.palette_outlined));

  Future<void> tapShowMore() => _tap(_glyphDot(Icons.more_horiz_rounded));

  bool get pickerOpen => _shown(find.byType(ColorPickerSheet));

  bool get paletteSheetOpen => _shown(find.byType(ColorPaletteSheet));

  /// Holds a finger on the swatch of [argb], which opens its menu.
  Future<void> longPress(int argb) async {
    await tester.ensureVisible(_swatch(argb));
    await tester.pumpAndSettle();
    await tester.longPress(_swatch(argb));
    await tester.pumpAndSettle();
  }

  Finder get _menuRows => find.byType(FormMenuItemRow);

  /// The items of the open swatch menu, top to bottom; empty while no menu
  /// is up. The menu is a popup of the language's menu rows, which nothing
  /// hosting the strip draws, so the rows on screen are the menu's.
  List<String> get menuItems => [
    for (final row in tester.widgetList<FormMenuItemRow>(_menuRows)) row.label,
  ];

  bool get menuOpen => menuItems.isNotEmpty;

  /// Whether the open menu carries the item a flow addresses by [id].
  bool hasMenuItem(String id) => _shown(find.bySemanticsIdentifier(id));

  /// The open menu's first item, as the popup lays it out — where the menu
  /// hangs and how wide it is.
  Rect get menuFirstItemRect => tester.getRect(
    find
        .ancestor(
          of: _menuRows.first,
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        )
        .first,
  );

  /// Picks the open menu's item reading [label].
  Future<void> pickMenu(String label) async {
    await tester.tap(find.widgetWithText(FormMenuItemRow, label));
    await tester.pumpAndSettle();
  }

  // --- The delete confirmation -----------------------------------------------

  Finder get _dialog => find.byType(AlertDialog);

  bool get dialogShown => _shown(_dialog);

  /// The question's confirming button, whatever it is labelled.
  Future<void> confirmDelete() =>
      _tap(find.descendant(of: _dialog, matching: find.byType(FilledButton)));

  /// The question's way out: nothing happens.
  Future<void> cancelDelete() =>
      _tap(find.descendant(of: _dialog, matching: find.byType(TextButton)));
}
