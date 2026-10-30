import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/models/calendar_panel_mode.dart';
import 'package:anta/models/day_bar.dart';
import 'package:anta/models/day_summary_entry.dart';
import 'package:anta/pages/calendar_guide_practice_page.dart';
import 'package:anta/widgets/calendar_bottom_panel.dart';
import 'package:anta/widgets/calendar_date_picker_sheet.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/widgets/day_summary_panel.dart';
import 'package:anta/widgets/day_timeline_view.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/simple_markdown_preview.dart';

/// Drives [CalendarGuidePracticePage] for its suite: the tests say what the
/// newcomer does and read what the page shows, and never name a widget type.
///
/// Controls are tapped by their `SemanticsIds`, the handles a device flow
/// uses; the grid's days, which `table_calendar` leaves without ids, by the
/// cell drawn for the day.
class PracticeCalendarRobot {
  const PracticeCalendarRobot(this.tester);

  final WidgetTester tester;

  Finder _byId(String id) => find.bySemanticsIdentifier(id);

  Finder get _band => _byId(SemanticsIds.calendarGuidePracticeBanner);

  Future<void> _tap(Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// The band's tour line as it reads now.
  String get caption {
    final slot = tester.widget<FormCaptionSlot>(
      find.descendant(of: _band, matching: find.byType(FormCaptionSlot)),
    );
    return ((slot.child as Semantics).child! as Text).data!;
  }

  Size get bandSize => tester.getSize(_band);

  bool get canSkip =>
      tester
          .widget<IconButton>(
            find.descendant(
              of: _byId(SemanticsIds.practiceSkip),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed !=
      null;

  /// The band's skip past the tour's current step.
  Future<void> skip() => _tap(_byId(SemanticsIds.practiceSkip));

  // The grid.

  Finder get _gridFinder =>
      find.byWidgetPredicate((widget) => widget is TableCalendar);

  TableCalendar<dynamic> get _grid => tester.widget(_gridFinder);

  CalendarFormat get format => _grid.calendarFormat;

  /// The day cells the grid draws, outside days included.
  int get cellCount => find.byType(CalendarDayCell).evaluate().length;

  Finder _cell(DateTime day) => find.descendant(
    of: _gridFinder,
    matching: find.byWidgetPredicate(
      (widget) => widget is CalendarDayCell && isSameDay(widget.day, day),
    ),
  );

  /// The gesture surface `table_calendar` wraps [day]'s cell in: the cell's
  /// own box sits under the marker layer and takes no hit.
  Finder _cellTarget(DateTime day) => find
      .ancestor(of: _cell(day).first, matching: find.byType(GestureDetector))
      .first;

  /// Taps [day]'s cell, paging the grid by its chevrons first when the day
  /// is on another page — a date relative to today can cross a month end.
  Future<void> pickDay(DateTime day) async {
    for (var page = 0; page < 2 && _cell(day).evaluate().isEmpty; page++) {
      final forward = day.isAfter(_grid.focusedDay);
      await _tap(
        find.descendant(
          of: _gridFinder,
          matching: find.byIcon(
            forward ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
          ),
        ),
      );
    }
    // Tapped where it stands: the grid is always on screen, and
    // `ensureVisible` would scroll its month pager and page it away.
    await tester.tap(_cellTarget(day));
    await tester.pumpAndSettle();
  }

  /// Every bar's spoken label on the grid.
  List<String> get barLabels => [
    for (final bars in tester.widgetList<CalendarDayBars>(
      find.byType(CalendarDayBars),
    ))
      for (final bar in bars.bars) bar.semanticLabel,
  ];

  /// The bars drawn on [day]'s cell, which must be on the shown page.
  List<DayBar> barsOn(DateTime day) => [
    for (final bars in tester.widgetList<CalendarDayBars>(
      find.descendant(
        of: _cellTarget(day),
        matching: find.byType(CalendarDayBars),
      ),
    ))
      ...bars.bars,
  ];

  // The panel.

  Finder get _dayPanel => find.byType(DaySummaryPanel);

  /// The entries the Day panel lists, event rows only.
  List<DaySummaryEntry> get dayPanelEntries => [
    for (final entry in tester.widget<DaySummaryPanel>(_dayPanel).entries)
      if (entry.event != null) entry,
  ];

  /// The event titles the Day panel lists.
  List<String> get dayPanelTitles => [
    for (final entry in dayPanelEntries) entry.title,
  ];

  /// The id of the Day panel's row titled [title].
  String rowIdOf(String title) =>
      dayPanelEntries.firstWhere((entry) => entry.title == title).event!.id;

  Future<void> showPanel(CalendarPanelMode mode) =>
      _tap(_byId(SemanticsIds.panelMode(mode.name)));

  Future<void> openRow(String eventId) =>
      _tap(_byId(SemanticsIds.eventRow(eventId)));

  /// The Day panel's presence button on [eventId]'s row, its tooltip naming
  /// what a press writes.
  Future<void> pressPresence(String eventId, String tooltip) => _tap(
    find.descendant(
      of: _byId(SemanticsIds.eventRow(eventId)),
      matching: find.byTooltip(tooltip),
    ),
  );

  /// Whether the panel bar's expand button takes a press.
  bool get canExpandPanel =>
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byType(PanelModeBar),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed !=
      null;

  /// The Timeline's block or chip for [title].
  Finder timelineEvent(String title) => find.descendant(
    of: find.byType(DayTimelineView),
    matching: find.text(title),
  );

  /// The opacity the Timeline draws [title] at.
  double timelineOpacityOf(String title) => tester
      .widget<Opacity>(
        find
            .ancestor(of: timelineEvent(title), matching: find.byType(Opacity))
            .first,
      )
      .opacity;

  Future<void> tapTimelineEvent(String title) => _tap(timelineEvent(title));

  /// The Upcoming list's first entry row among [titles]: the one drawn
  /// highest.
  String firstUpcomingOf(Iterable<String> titles) {
    final drawn = [
      for (final title in titles)
        for (final element
            in find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.text(title),
                )
                .evaluate())
          (title, tester.getTopLeft(find.byWidget(element.widget)).dy),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return drawn.first.$1;
  }

  // The bar.

  bool get canReset =>
      tester
          .widget<IconButton>(
            find.descendant(
              of: _byId(SemanticsIds.practiceReset),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed !=
      null;

  Future<void> reset() => _tap(_byId(SemanticsIds.practiceReset));

  /// The funnel's badge: its count, or null while it is hidden.
  int? get filterBadge {
    final badge = tester.widget<Badge>(
      find.descendant(
        of: _byId(SemanticsIds.practiceFilterOpen),
        matching: find.byType(Badge),
      ),
    );
    if (!badge.isLabelVisible) return null;
    return int.parse((badge.label! as Text).data!);
  }

  Future<void> openFilters() => _tap(_byId(SemanticsIds.practiceFilterOpen));

  Future<void> tapId(String id) => _tap(_byId(id));

  Future<void> pickFormat(String formatId) async {
    await _tap(_byId(SemanticsIds.calendarViewMenu));
    await _tap(_byId(formatId));
  }

  Future<void> pickMore(String rowId) async {
    await _tap(_byId(SemanticsIds.practiceMore));
    await _tap(_byId(rowId));
  }

  // The sheets.

  Future<void> add() => _tap(_byId(SemanticsIds.practiceAddEvent));

  /// The add button's long press: the template picker.
  Future<void> longPressAdd() async {
    await tester.longPress(_byId(SemanticsIds.practiceAddEvent));
    await tester.pumpAndSettle();
  }

  /// The system back, delivered at once — nothing is settled first.
  Future<void> systemBack() async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Future<void> typeTitle(String title) async {
    await tester.enterText(
      find
          .descendant(
            of: find.byType(EventEditorSheet),
            matching: find.byType(TextField),
          )
          .first,
      title,
    );
    await tester.pumpAndSettle();
  }

  Future<void> saveEditor() => _tap(_byId(SemanticsIds.eventSave));

  /// The editor's Delete, confirmed.
  Future<void> deleteInEditor(String confirm) async {
    await _tap(_byId(SemanticsIds.eventDelete));
    await _tap(find.widgetWithText(FilledButton, confirm));
  }

  bool get detailOpen => find.byType(EventDetailSheet).evaluate().isNotEmpty;

  Future<void> detailEdit() => _tap(_byId(SemanticsIds.eventDetailEdit));
  Future<void> detailSkip() => _tap(_byId(SemanticsIds.eventDetailSkip));
  Future<void> detailClose() => _tap(_byId(SemanticsIds.eventDetailClose));
  Future<void> detailAddDate() => _tap(_byId(SemanticsIds.eventDetailAddDate));

  /// Toggles [day] in the open date picker's month grid.
  /// Tapped where it stands: `ensureVisible` would scroll the picker's
  /// month pager and page it away.
  Future<void> pickInDatePicker(DateTime day) async {
    await tester.tap(
      find.descendant(
        of: find.byType(CalendarDatePickerSheet),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CalendarDayCell &&
              isSameDay(widget.day, day) &&
              !widget.isOutside,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Whether the detail sheet's presence chip [id] is the selected one.
  bool chipSelected(String id) => tester
      .widget<FormChip>(
        find.byWidgetPredicate(
          (widget) => widget is FormChip && widget.identifier == id,
        ),
      )
      .selected;

  /// Ticks the detail sheet's first task box with a finger on its glyph,
  /// and pumps one frame only: the sheet's delayed write stays pending.
  Future<void> tickFirstTask() async {
    await tester.tap(
      find
          .descendant(
            of: find.descendant(
              of: find.byType(EventDetailSheet),
              matching: find.byType(SimpleMarkdownPreview),
            ),
            matching: find.byWidgetPredicate(
              (widget) => widget is GestureDetector && widget.onTap != null,
            ),
          )
          .first,
    );
    await tester.pump();
  }

  /// The detail sheet's quick description edit, its text replaced through
  /// the editor's controller — a `CodeEditor` takes no `enterText` — then
  /// Done.
  Future<void> quickEditDescription(String text) async {
    await _tap(_byId(SemanticsIds.eventDetailDescription));
    tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!.text = text;
    await tester.pump();
    await _tap(
      find.descendant(
        of: _byId(SemanticsIds.descriptionDone),
        matching: find.byType(TextButton),
      ),
    );
  }

  /// The editor's switch row labelled [label].
  Future<void> toggleEditorSwitch(String label) async {
    final row = find.ancestor(
      of: find.text(label),
      matching: find.byType(FormSwitchRow),
    );
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find
          .descendant(
            of: find.byType(EventEditorSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await _tap(find.descendant(of: row, matching: find.byType(Switch)));
  }

  /// Scrolls the editor until [finder] is built and visible.
  Future<void> scrollEditorTo(Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byType(EventEditorSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }
}
