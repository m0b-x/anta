import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/widgets/category_delete_sheet.dart';
import 'package:anta/widgets/category_picker_sheet.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/value_change_highlight.dart';

/// What `CategoryDeleteSheet.show` resolved to. Mutable, because the sheet is
/// awaited inside a button callback and the value arrives after the tap that
/// dismissed it.
class CategoryDeleteOutcome {
  bool? result;
  bool returned = false;
}

/// Drives the delete sheet — [CategoryDeleteSheet] — for its suite: the
/// suite says what the user does and reads what the sheet shows, by the ids
/// a device flow taps and the rows' own texts.
///
/// The sheet writes through the real `CategoryService` over an in-memory
/// database, and `testWidgets` runs its body under `FakeAsync`, where a drift
/// transaction completes only once `runAsync` hands the real event loop
/// back: [confirm] drains it, [tapDelete] leaves it running.
class CategoryDeleteRobot {
  const CategoryDeleteRobot(this.tester);

  final WidgetTester tester;

  static const String _openLabel = 'open';

  Finder get _sheet => find.byType(CategoryDeleteSheet);

  Finder _in(Finder matching) =>
      find.descendant(of: _sheet, matching: matching);

  Finder get close =>
      find.bySemanticsIdentifier(SemanticsIds.categoryDeleteClose);

  Finder get delete =>
      find.bySemanticsIdentifier(SemanticsIds.categoryDeleteConfirm);

  Finder get target =>
      find.bySemanticsIdentifier(SemanticsIds.categoryDeleteTarget);

  Finder get _picker => find.byType(CategoryPickerSheet);

  SemanticsData _dataOf(Finder finder) =>
      tester.getSemantics(finder).getSemanticsData();

  /// Opens the sheet the way the page does — through `show`, from a button —
  /// and captures its result. [settle] false stops at the sheet's first
  /// frame, for a case that measures it before anything has moved. [share]
  /// is the phone's share availability, as the page hands it over.
  Future<CategoryDeleteOutcome> show({
    required CalendarCategory category,
    Locale locale = const Locale('en'),
    double? textScale,
    Size? surface,
    bool dark = false,
    bool settle = true,
    ShareAvailability share = const ShareNotPaired(),
  }) async {
    if (surface != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
    }
    final outcome = CategoryDeleteOutcome();
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
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
                outcome.result = await CategoryDeleteSheet.show(
                  context,
                  category: category,
                  share: share,
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // `show` reads the counts before it pushes the route.
      for (var i = 0; i < 20 && !isOpen; i++) {
        await tester.pump();
      }
    }
    return outcome;
  }

  bool get isOpen => _sheet.evaluate().isNotEmpty;

  /// The strings of the sheet's own locale.
  AppLocalizations get l10n => AppLocalizations.of(tester.element(_sheet))!;

  Finder get _caption => _in(
    find.descendant(
      of: find.byType(FormReadTitleRow),
      matching: find.text(_rawCaption),
    ),
  );

  String get _rawCaption => tester
      .widget<FormReadTitleRow>(_in(find.byType(FormReadTitleRow)))
      .caption!;

  /// The line under the category's name — "n events · m alerts · k
  /// templates" — as read: the no-break spaces that hold each segment
  /// together read as spaces here, and [captionParagraph] is where a case
  /// checks where the line may break.
  String get impactCaption =>
      _rawCaption.replaceAll(String.fromCharCode(0xA0), ' ');

  /// The laid-out counts line, for where it breaks.
  RenderParagraph get captionParagraph =>
      tester.renderObject<RenderParagraph>(_caption);

  /// The laid-out title in the header, for whether it was cut.
  RenderParagraph get titleParagraph => tester.renderObject<RenderParagraph>(
    find.descendant(
      of: _in(find.byType(FormSheetHeader)),
      matching: find.text(l10n.deleteCategory),
    ),
  );

  /// The category's name in the read row, for how many lines it takes.
  Size nameSize(String name) => tester.getSize(
    find.descendant(
      of: _in(find.byType(FormReadTitleRow)),
      matching: find.text(name),
    ),
  );

  /// Whether the read row leads with the avatar rather than the bare glyph.
  bool get leadsWithAvatar =>
      _in(find.byType(EventAvatar)).evaluate().isNotEmpty;

  /// Where [finder] sits in the sheet, so an entrance's slide is not read
  /// as a move.
  Rect inSheet(Finder finder) =>
      tester.getRect(finder).shift(-tester.getTopLeft(_sheet));

  Finder get header => _in(find.byType(FormSheetHeader));

  /// Whether the Move row draws the flash a picker's write starts.
  bool get moveFlashes {
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: _in(find.byType(ValueChangeHighlight)),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    return (box.decoration as BoxDecoration).border != null;
  }

  /// The category the events move to, as the Move row reads it.
  String get targetLabel =>
      tester.widget<FormPickerRow>(_in(find.byType(FormPickerRow))).value!;

  /// The caption under the group, as shown — never the slot's sizing twin.
  String get consequences {
    final slot = tester.widget<FormCaptionSlot>(
      _in(find.byType(FormCaptionSlot)),
    );
    return (slot.child as FormCaption).text;
  }

  /// The caption slot's height, which must not follow what it says.
  double get consequencesHeight =>
      tester.getSize(_in(find.byType(FormCaptionSlot))).height;

  /// An enabled picker row carries no enabled state at all; a disabled one
  /// says so.
  bool get moveEnabled =>
      _dataOf(target).flagsCollection.isEnabled != Tristate.isFalse;

  bool get deleteEnabled =>
      _dataOf(delete).flagsCollection.isEnabled == Tristate.isTrue;

  bool get closeEnabled =>
      _dataOf(close).flagsCollection.isEnabled == Tristate.isTrue;

  /// Opens the picker from the Move row.
  Future<void> openPicker() async {
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Whether the open picker lists a row reading [label].
  bool pickerOffers(String label) => find
      .descendant(of: _picker, matching: find.text(label))
      .evaluate()
      .isNotEmpty;

  /// Picks [label] in the open picker; single mode picks on the tap.
  /// [settle] false lets one frame through, the picker still leaving.
  Future<void> pick(String label, {bool settle = true}) async {
    final row = find.descendant(of: _picker, matching: find.text(label));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  /// Taps Delete and lets one frame through, the write still running.
  Future<void> tapDelete() async {
    await tester.tap(delete);
    await tester.pump();
  }

  /// Taps Delete and drains the write to the pop.
  Future<void> confirm() async {
    await tapDelete();
    await settleWrites();
  }

  /// Hands the real event loop back until a drift transaction has landed.
  Future<void> settleWrites() async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapClose() async {
    await tester.tap(close);
    await tester.pumpAndSettle();
  }

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

  /// Drags the sheet down by its handle, past where a bottom sheet closes.
  Future<void> dragDown() async {
    await tester.drag(_in(find.byType(FormSheetHandle)), const Offset(0, 600));
    await tester.pumpAndSettle();
  }

  Size sizeOf(Finder finder) => tester.getSize(finder);
}
