import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/fasting_schedule.dart';
import 'package:anta/widgets/calendar_date_picker_sheet.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/widgets/fasting_schedule_sheet.dart';
import 'package:anta/widgets/form_rows.dart';

/// The two exception lists of the schedule: days never marked, days always
/// marked. The names are the ids' (`fasting-skip-remove-…`).
enum FastingDateKind { skip, force }

/// Drives the fasting schedule sheet — [FastingScheduleSheet] — for the
/// suites: they say what the user does and read what the sheet shows, and
/// never name a widget type.
///
/// The seam is what let the Tier 3 rebuild of the sheet
/// (`docs/calendar-language-tier-3-roadmap.md`, slice 4) land under the
/// suite that pinned the old chrome: the rebuild rewrote this file and left
/// the bodies alone, but for the behaviour that record changes on purpose.
/// The finders are the sub-sheet's: the ✕, every chip, the Select all / None
/// rows, the scope chips, the two exception rows and each date's remove
/// button by their ids; a scope's hint as the caption its slot shows; the
/// dates as the sub-rows between the two exception rows.
///
/// The Dates sheet the exception rows open has been on the UI language since
/// Tier 1 and is driven through its own ids.
class FastingScheduleRobot {
  const FastingScheduleRobot(this.tester);

  final WidgetTester tester;

  static const String _openLabel = 'open';

  /// Tall enough that the sheet shows every group without scrolling, so a
  /// case that reads two sections against each other reads them on one
  /// screen; the layout cases size their own phone.
  static const Size defaultSurface = Size(1200, 3000);

  Finder get _sheet => find.byType(FastingScheduleSheet);

  Finder _in(Finder matching) =>
      find.descendant(of: _sheet, matching: matching);

  Finder _byId(String id) => _in(find.bySemanticsIdentifier(id));

  AppLocalizations get _l10n => AppLocalizations.of(tester.element(_sheet))!;

  /// The sheet's own strings, for a case that pins layout rather than copy.
  AppLocalizations get l10n => _l10n;

  Finder get _datesSheet => find.byType(CalendarDatePickerSheet);

  /// A chip of the sheet by the id it was built with, read for its state.
  FormChip _chip(String id) => tester.widget(
    _in(
      find.byWidgetPredicate(
        (widget) => widget is FormChip && widget.identifier == id,
      ),
    ),
  );

  FormActionRow _action(String id) => tester.widget(
    _in(
      find.byWidgetPredicate(
        (widget) => widget is FormActionRow && widget.identifier == id,
      ),
    ),
  );

  FormPickerRow _pickerRow(String id) => tester.widget(
    _in(
      find.byWidgetPredicate(
        (widget) => widget is FormPickerRow && widget.identifier == id,
      ),
    ),
  );

  /// The labelled chip row reading [label] — a scope row.
  Finder _chipRow(String label) => _in(
    find.byWidgetPredicate(
      (widget) => widget is FormChipRow && widget.label == label,
    ),
  );

  Finder _slotOf(Finder row) =>
      find.descendant(of: row, matching: find.byType(FormCaptionSlot));

  static String _weekdayScopeId(FastingWeekdayScope scope) => switch (scope) {
    FastingWeekdayScope.weeklyOnly => SemanticsIds.fastingWeekdayScopeWeekly,
    FastingWeekdayScope.allFasts => SemanticsIds.fastingWeekdayScopeAll,
  };

  static String _monthScopeId(FastingMonthScope scope) => switch (scope) {
    FastingMonthScope.weeklyOnly => SemanticsIds.fastingMonthScopeWeekly,
    FastingMonthScope.allFasts => SemanticsIds.fastingMonthScopeAll,
  };

  static String _addId(FastingDateKind kind) => switch (kind) {
    FastingDateKind.skip => SemanticsIds.fastingDaysOff,
    FastingDateKind.force => SemanticsIds.fastingExtraDays,
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
  /// and a suite that compares a chip's rect across a tap must not have the
  /// tap move the body under it.
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

  SemanticsData _dataOf(Finder target) =>
      tester.getSemantics(target).getSemanticsData();

  /// Opens the sheet the way Calendar settings does — through `show`, from a
  /// button on a page. Every change goes out through [onChanged] at once;
  /// there is nothing to return.
  Future<void> show({
    FastingSchedule initialSchedule = const FastingSchedule(),
    CalendarAppearance appearance = const CalendarAppearance(),
    required ValueChanged<FastingSchedule> onChanged,
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
              onPressed: () => FastingScheduleSheet.show(
                context,
                initialSchedule: initialSchedule,
                appearance: appearance,
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

  bool get isOpen => _shown(_sheet);

  /// The header's title as the header was handed it, whatever the width
  /// made of it on screen.
  String get headerTitle =>
      tester.widget<FormSheetHeader>(_in(find.byType(FormSheetHeader))).title;

  // --- Weekdays --------------------------------------------------------------

  /// [weekday] as `DateTime` counts it: Monday is 1, Sunday is 7.
  Future<void> toggleWeekday(int weekday) =>
      _tap(_byId(SemanticsIds.fastingWeekday(weekday)));

  bool weekdaySelected(int weekday) =>
      _chip(SemanticsIds.fastingWeekday(weekday)).selected;

  Future<void> weekdaysSelectAll() =>
      _tap(_byId(SemanticsIds.fastingWeekdaysAll));

  Future<void> weekdaysNone() => _tap(_byId(SemanticsIds.fastingWeekdaysNone));

  Future<void> pickWeekdayScope(FastingWeekdayScope scope) =>
      _tap(_byId(_weekdayScopeId(scope)));

  FastingWeekdayScope get weekdayScope => FastingWeekdayScope.values
      .singleWhere((scope) => _chip(_weekdayScopeId(scope)).selected);

  /// The line under the weekday scope, which has to describe the selected
  /// scope: what its slot shows now.
  String get weekdayScopeHint =>
      _shownCaption(_chipRow(_l10n.fastingWeekdayScopeTitle));

  // --- Months ----------------------------------------------------------------

  Future<void> toggleMonth(int month) =>
      _tap(_byId(SemanticsIds.fastingMonth(month)));

  bool monthSelected(int month) =>
      _chip(SemanticsIds.fastingMonth(month)).selected;

  Future<void> monthsSelectAll() => _tap(_byId(SemanticsIds.fastingMonthsAll));

  Future<void> monthsNone() => _tap(_byId(SemanticsIds.fastingMonthsNone));

  Future<void> pickMonthScope(FastingMonthScope scope) =>
      _tap(_byId(_monthScopeId(scope)));

  FastingMonthScope get monthScope => FastingMonthScope.values.singleWhere(
    (scope) => _chip(_monthScopeId(scope)).selected,
  );

  String get monthScopeHint =>
      _shownCaption(_chipRow(_l10n.fastingMonthScopeTitle));

  /// The caption the slot under [row] shows — the one that is drawn and can
  /// be hit, where every candidate (the shown one's twin included) is laid
  /// out unseen under it.
  String _shownCaption(Finder row) {
    final slot = tester.widget<FormCaptionSlot>(_slotOf(row));
    final shown = (slot.child as FormCaption).text;
    final drawn = find
        .descendant(of: row, matching: find.text(shown).hitTestable())
        .evaluate()
        .length;
    if (drawn != 1) {
      fail('The shown caption "$shown" is drawn $drawn times under its row');
    }
    return shown;
  }

  /// The height of the caption slot under the scope row reading [label].
  double scopeSlotHeight(String label) =>
      tester.getSize(_slotOf(_chipRow(label))).height;

  // --- Exception dates -------------------------------------------------------

  /// Opens the Dates sheet for the days off; returns with it up.
  Future<void> addDaysOff() => _tap(_byId(SemanticsIds.fastingDaysOff));

  /// Opens the Dates sheet for the extra fast days; returns with it up.
  Future<void> addExtraDays() => _tap(_byId(SemanticsIds.fastingExtraDays));

  /// Whether the exception row of [kind] is switched off — at the cap.
  Future<bool> addDisabled(FastingDateKind kind) async =>
      !_pickerRow(_addId(kind)).enabled;

  /// What the exception row of [kind] reads as its value: the count, or the
  /// cap.
  Future<String> addLabel(FastingDateKind kind) async =>
      _pickerRow(_addId(kind)).value!;

  /// The date as the sheet prints it in the open locale.
  String dateLabel(DateTime date) =>
      DateFormat.yMMMEd(_l10n.localeName).format(date);

  /// The sub-rows of [kind]: the picker rows between that list's own row and
  /// the next list's (or the end), in the order the sheet draws them.
  List<FormPickerRow> _dateRows(FastingDateKind kind) {
    final rows = tester
        .widgetList<FormPickerRow>(_in(find.byType(FormPickerRow)))
        .toList();
    final start = rows.indexWhere((row) => row.identifier == _addId(kind)) + 1;
    final end = switch (kind) {
      FastingDateKind.skip => rows.indexWhere(
        (row) => row.identifier == SemanticsIds.fastingExtraDays,
      ),
      FastingDateKind.force => rows.length,
    };
    return rows.sublist(start, end);
  }

  /// The dates listed under [kind], as printed, in row order.
  List<String> datesShown(FastingDateKind kind) => [
    for (final row in _dateRows(kind)) row.label,
  ];

  /// The ids of the remove buttons under [kind], in row order.
  List<String?> removeIdsShown(FastingDateKind kind) => [
    for (final row in _dateRows(kind)) row.trailingButton?.identifier,
  ];

  Future<void> removeDate(FastingDateKind kind, DateTime date) =>
      _tap(_byId(SemanticsIds.fastingDateRemove(kind.name, date)));

  // --- The Dates sheet -------------------------------------------------------

  bool get datesSheetOpen => _shown(_datesSheet);

  /// Ticks [days] on the open Dates sheet's month grid and saves. The days
  /// have to be in the month the sheet opened on.
  Future<void> pickDates(Iterable<DateTime> days) async {
    for (final day in days) {
      await tester.tap(
        find.descendant(
          of: _datesSheet,
          matching: find.byWidgetPredicate(
            (w) => w is CalendarDayCell && w.day == day && !w.isOutside,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.datePickerSave));
    await tester.pumpAndSettle();
  }

  /// Leaves the open Dates sheet with nothing picked.
  Future<void> cancelDates() async {
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.datePickerCancel));
    await tester.pumpAndSettle();
  }

  // --- Geometry and semantics ------------------------------------------------

  /// The on-screen rect of the control carrying [id].
  Rect targetOf(String id) => tester.getRect(_byId(id));

  Rect get sheetRect => tester.getRect(_sheet);

  /// The semantics of the control carrying [id].
  SemanticsData nodeOf(String id) => _dataOf(_byId(id));

  /// Whether the Select all / None row carrying [id] can be tapped.
  bool actionEnabled(String id) => _action(id).onTap != null;

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

  /// Whether the label of the control carrying [id] — a chip's text, an
  /// action row's, a picker row's — is drawn whole: no line limit, nothing
  /// cut, inside the sheet's width.
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

  Future<void> close() => _tap(_byId(SemanticsIds.fastingScheduleClose));
}
