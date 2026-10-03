import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/agenda_day_list.dart';
import 'package:anta/models/agenda_day_list_mode.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/widgets/agenda_day_list_sheet.dart';
import 'package:anta/widgets/agenda_month_grid.dart';
import 'package:anta/widgets/agenda_period_nav.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/month_dot_matrix.dart';
import 'package:anta/widgets/month_year_picker_sheet.dart';

/// What `AgendaDayListSheet.show` resolved to. Mutable, because the sheet is
/// awaited inside a button callback and the value arrives after the tap that
/// dismissed it.
class DayListOutcome {
  AgendaDayListResult? result;
  bool returned = false;
}

/// Stands in for the agenda's own widened re-scan, recording every range the
/// sheet asks for so a suite can pin *when* resolution happens as well as
/// what it returns.
class ResolverSpy {
  ResolverSpy(this.pool);

  final List<AgendaDayListEntry> pool;
  final List<(DateTime, DateTime)> calls = [];

  List<AgendaDayListEntry> resolve(DateTime start, DateTime end) {
    calls.add((start, end));
    return [
      for (final entry in pool)
        if (!entry.day.isBefore(start) && !entry.day.isAfter(end)) entry,
    ];
  }
}

/// Drives the agenda's day list — [AgendaDayListSheet] — for the suites: they
/// say what the user does and read what the sheet shows, and never name a
/// widget type.
///
/// The seam is what let the Tier 3 rebuild of the sheet
/// (`docs/calendar-language-tier-3-roadmap.md`, slice 2) land under the
/// suites that pinned the old chrome: the rebuild rewrote this file and left
/// the bodies alone, but for the behaviour that record changes on purpose.
/// Inlining a finder back into a suite gives that up.
///
/// The finders are the language's: the mode and scope chips by their ids,
/// the header's ✕ / ← by theirs, the read and entry rows as `FormPickerRow`s
/// in their shells, the picked day's "Whole month" ✕ as the read row's
/// trailing button, the month separators as section labels. The nav, the
/// grid, the year tiles and their semantics labels are shared pieces the
/// rebuild kept.
class DayListRobot {
  const DayListRobot(this.tester);

  final WidgetTester tester;

  /// The harness button [show] builds; also what [hostVisible] reads, which
  /// is how a suite proves a double pop did not take the page under the
  /// sheet with it.
  static const String _openLabel = 'open';

  Finder get _sheet => find.byType(AgendaDayListSheet);

  Finder _in(Finder matching) =>
      find.descendant(of: _sheet, matching: matching);

  AppLocalizations get _l10n => AppLocalizations.of(tester.element(_sheet))!;

  /// The widget that puts [id] on a control: unlike the control's semantics
  /// node it exists wherever the body is scrolled to, and it matches with
  /// no semantics handle in play.
  Finder _carrier(String id) => _in(
    find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.identifier == id,
    ),
  );

  Finder _chip(String id) => _in(
    find.byWidgetPredicate(
      (widget) => widget is FormChip && widget.identifier == id,
    ),
  );

  Finder _trailingButton(String id) => _in(
    find.byWidgetPredicate(
      (widget) => widget is FormTrailingButton && widget.identifier == id,
    ),
  );

  Finder _chipRowOf(String chipId) => find
      .ancestor(of: _chip(chipId), matching: find.byType(FormChipRow))
      .first;

  Finder get _modeChipRow => _chipRowOf(SemanticsIds.dayListModeList);

  Finder get _scopeChipRow => _chipRowOf(SemanticsIds.dayListScopeUpcoming);

  Finder get _header => _in(find.byType(FormSheetHeader));

  Finder get _grid => _in(find.byType(GridView));

  AgendaPeriodNav get _nav => tester.widget(_in(find.byType(AgendaPeriodNav)));

  Finder _dayCell(int day) => _in(
    find.byWidgetPredicate((w) => w is CalendarDayCell && w.day.day == day),
  );

  /// The row drawn for the entry titled [title] — the first one, where a
  /// recurring event puts the same title on many rows.
  Finder _entryRow(String title) => find
      .ancestor(of: _in(find.text(title)), matching: find.byType(FormPickerRow))
      .first;

  /// The read row heading the day labelled [label].
  Finder _readRow(String label) => _in(
    find.byWidgetPredicate(
      (widget) => widget is FormPickerRow && widget.label == label,
    ),
  );

  /// The picked day's read row in month mode: the one carrying the "Whole
  /// month" ✕.
  Finder get _pickedDayRow => _in(
    find.byWidgetPredicate(
      (widget) =>
          widget is FormPickerRow &&
          widget.trailingButton?.identifier == SemanticsIds.dayListWholeMonth,
    ),
  );

  static String _modeId(AgendaDayListMode mode) => switch (mode) {
    AgendaDayListMode.list => SemanticsIds.dayListModeList,
    AgendaDayListMode.month => SemanticsIds.dayListModeMonth,
    AgendaDayListMode.year => SemanticsIds.dayListModeYear,
  };

  static String _scopeId(AgendaDayListYearScope scope) => switch (scope) {
    AgendaDayListYearScope.upcoming => SemanticsIds.dayListScopeUpcoming,
    AgendaDayListYearScope.calendarYear =>
      SemanticsIds.dayListScopeCalendarYear,
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

  Future<void> _tap(Finder target) async {
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// The node a screen reader lands on for [finder]: the merged row's for a
  /// text inside a row, the control's own for a button.
  SemanticsNode _node(Finder finder) => tester.getSemantics(finder);

  SemanticsData _nodeOf(Finder finder) => _node(finder).getSemanticsData();

  /// Whether the paragraph drawn for [text] shows all of it — no ellipsis,
  /// no line past its limit.
  bool _whole(Finder text) =>
      !tester.renderObject<RenderParagraph>(text).didExceedMaxLines;

  /// How many lines the one text [text] took: its drawn height over one line
  /// of its own style at the ambient scale. Only for a text whose style
  /// names its line height, as every text of the language does.
  int _linesOf(Finder text) {
    final style = tester.widget<Text>(text).style!;
    final scaled = MediaQuery.textScalerOf(
      tester.element(text),
    ).scale(style.fontSize!);
    return (tester.getSize(text).height / (scaled * style.height!)).round();
  }

  // --- Opening ---------------------------------------------------------------

  /// Opens the sheet the way the agenda does — through `show`, from a button
  /// on a page — and captures its result. [settle] false stops after the
  /// first frame, for a suite that pins what the sheet did before it.
  /// [textScale] and [surface] stand in for a phone's accessibility setting
  /// and size.
  Future<DayListOutcome> show(
    AgendaDayList list, {
    required AgendaDayListResolver resolve,
    AgendaDayMarkResolver? resolveMarks,
    AgendaYearBounds? yearBounds,
    CalendarAppearance appearance = const CalendarAppearance(),
    required DateTime today,
    required DateTime windowStart,
    required DateTime windowEnd,
    AgendaDayListMode initialMode = AgendaDayListMode.list,
    ValueChanged<AgendaDayListMode>? onModeChanged,
    Locale locale = const Locale('en'),
    double? textScale,
    Size? surface,
    bool settle = true,
  }) async {
    if (surface != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = surface;
    }
    final outcome = DayListOutcome();
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
                outcome.result = await AgendaDayListSheet.show(
                  context,
                  list,
                  resolve: resolve,
                  resolveMarks: resolveMarks,
                  yearBounds: yearBounds,
                  appearance: appearance,
                  today: today,
                  windowStart: windowStart,
                  windowEnd: windowEnd,
                  initialMode: initialMode,
                  onModeChanged: onModeChanged,
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
      await tester.pump();
    }
    return outcome;
  }

  /// Opens the sheet from an agenda summary card already on screen, through
  /// the card's own button — the one card's, or the card keyed [key] among
  /// several (`SemanticsIds.agendaCardDays`).
  Future<void> openFromCard({String? key}) async {
    final prefix = SemanticsIds.agendaCardDays('');
    await _tap(
      find.bySemanticsIdentifier(
        key == null
            ? RegExp('^${RegExp.escape(prefix)}')
            : SemanticsIds.agendaCardDays(key),
      ),
    );
  }

  bool get isOpen => _shown(_sheet);

  /// Whether the page the sheet was opened from is still there.
  bool get hostVisible => _shown(find.text(_openLabel));

  // --- The header ------------------------------------------------------------

  /// The card's title, repeated by the sheet's header.
  String get headerTitle => tester.widget<FormSheetHeader>(_header).title;

  /// The card's subtitle, repeated by the line pinned under the header: the
  /// first caption of the sheet in tree order, before any the body draws.
  FormCaption get _subtitleCaption =>
      tester.widgetList<FormCaption>(_in(find.byType(FormCaption))).first;

  String get headerSubtitle => _subtitleCaption.text;

  Finder get _subtitleText => find.descendant(
    of: find.byWidget(_subtitleCaption),
    matching: find.byType(Text),
  );

  /// How many lines the subtitle took.
  int get headerSubtitleLines => _linesOf(_subtitleText);

  bool get headerSubtitleWhole => _whole(_subtitleText);

  bool get headerSubtitleWrapsFreely => _subtitleCaption.maxLines == null;

  /// Whether the scrolling body carries its id, as one container node.
  bool get bodyNodeShown =>
      _shown(find.bySemanticsIdentifier(SemanticsIds.dayListBody));

  /// The rect of the header's own box — the 48 dp row with the ✕ or the ←.
  Rect get headerRect => tester.getRect(_header);

  bool get modeControlShown => _shown(_modeChipRow);

  /// The rect of the mode chip row: the bottom of the pinned chrome, so its
  /// rect is the chrome's own.
  Rect get pinnedHeaderRect => tester.getRect(_modeChipRow);

  AgendaDayListMode get currentMode => AgendaDayListMode.values.singleWhere(
    (mode) => tester.widget<FormChip>(_chip(_modeId(mode))).selected,
  );

  /// The mode the body is drawn in, told from the body itself rather than
  /// the control: a flat list, the month's slivers under the grid, or the
  /// year's tiles. Null while the body is none of the three.
  AgendaDayListMode? get drawnMode {
    final list = _shown(_in(find.byType(ListView)));
    final month = _shown(_in(find.byType(CustomScrollView)));
    final year = _shown(_in(find.byType(GridView)));
    final drawn = [
      if (list) AgendaDayListMode.list,
      if (month) AgendaDayListMode.month,
      if (year) AgendaDayListMode.year,
    ];
    if (drawn.length > 1) fail('More than one body is drawn: $drawn');
    return drawn.singleOrNull;
  }

  Future<void> pickMode(AgendaDayListMode mode) => _tap(_chip(_modeId(mode)));

  /// Whether the chip for [mode] exists and is the selected one — read off
  /// the widget, and off its node when [announced].
  bool modeChipSelected(AgendaDayListMode mode, {bool announced = false}) {
    final id = _modeId(mode);
    if (!announced) return tester.widget<FormChip>(_chip(id)).selected;
    return _nodeOf(find.bySemanticsIdentifier(id)).flagsCollection.isSelected ==
        Tristate.isTrue;
  }

  bool scopeChipSelected(
    AgendaDayListYearScope scope, {
    bool announced = false,
  }) {
    final id = _scopeId(scope);
    if (!announced) return tester.widget<FormChip>(_chip(id)).selected;
    return _nodeOf(find.bySemanticsIdentifier(id)).flagsCollection.isSelected ==
        Tristate.isTrue;
  }

  /// Whether every chip of [row] draws its whole label.
  bool _chipsWhole(Finder row) {
    final labels = find.descendant(of: row, matching: find.byType(Text));
    for (var i = 0; i < labels.evaluate().length; i++) {
      if (!_whole(labels.at(i))) return false;
    }
    return true;
  }

  bool get modeChipsWhole => _chipsWhole(_modeChipRow);

  bool get scopeChipsWhole => _chipsWhole(_scopeChipRow);

  /// The header's one leading control: the ✕, or the ← while a year tile has
  /// drilled the sheet into a month.
  bool get showsClose => _shown(_carrier(SemanticsIds.dayListClose));

  bool get showsBack => _shown(_carrier(SemanticsIds.dayListBack));

  /// Which id the header gives its leading slot — null while the header
  /// carries none.
  String? get headerLeadingIdentifier =>
      tester.widget<FormSheetHeader>(_header).leadingIdentifier;

  /// The back arrow's glyph, as big as a finger can hit it.
  Size get backGlyphSize =>
      tester.getSize(_in(find.byIcon(Icons.arrow_back_rounded)).hitTestable());

  Size get backTargetSize => _targetSize(Icons.arrow_back_rounded);

  Size get todayTargetSize => _targetSize(Icons.today_rounded);

  Size _targetSize(IconData icon) => tester.getSize(
    find.ancestor(
      of: _in(find.byIcon(icon)),
      matching: find.byType(IconButton),
    ),
  );

  /// The arrow back to the year overview, shown only after a tile was opened.
  Future<void> back() => _tap(_carrier(SemanticsIds.dayListBack));

  /// The header's ✕.
  Future<void> close() => _tap(_carrier(SemanticsIds.dayListClose));

  // --- The year scope --------------------------------------------------------

  AgendaDayListYearScope get currentScope =>
      AgendaDayListYearScope.values.singleWhere(
        (scope) => tester.widget<FormChip>(_chip(_scopeId(scope))).selected,
      );

  Future<void> pickScope(AgendaDayListYearScope scope) =>
      _tap(_chip(_scopeId(scope)));

  /// The rect of the scope chip row — one 48 dp row per run of chips.
  Rect get scopeControlRect => tester.getRect(_scopeChipRow);

  /// The rect the scope chips themselves take, as one box.
  Rect get scopeChipsRect {
    final chips = find.descendant(
      of: _scopeChipRow,
      matching: find.byType(FormChip),
    );
    var union = tester.getRect(chips.first);
    for (var i = 1; i < chips.evaluate().length; i++) {
      union = union.expandToInclude(tester.getRect(chips.at(i)));
    }
    return union;
  }

  /// The rects of the scope chips' labels, in order.
  List<Rect> get scopeLabelRects {
    final labels = find.descendant(
      of: _scopeChipRow,
      matching: find.byType(Text),
    );
    return [
      for (var i = 0; i < labels.evaluate().length; i++)
        tester.getRect(labels.at(i)),
    ];
  }

  // --- The body --------------------------------------------------------------

  /// The line an empty body shows, or null while there are rows.
  String? get emptyCaption {
    for (final candidate in [
      _l10n.dayListEmptyRange,
      _l10n.dayListEmptyMonth,
    ]) {
      if (_shown(_in(find.text(candidate)))) return candidate;
    }
    return null;
  }

  /// What the sheet draws for [text]: a text as written, or a month
  /// separator — a section label, which draws its text in capitals and keeps
  /// the words it was given.
  Finder _drawing(String text) => _in(
    find.byWidgetPredicate(
      (widget) =>
          (widget is Text && widget.data == text) ||
          (widget is FormSectionLabel && widget.text == text),
    ),
  );

  /// Whether the sheet draws [text] exactly once.
  bool shows(String text) => _shown(_drawing(text));

  /// How many times the sheet draws [text].
  int countOf(String text) => _drawing(text).evaluate().length;

  /// How many lines the one text [text] took.
  int textLines(String text) => _linesOf(_in(find.text(text)));

  /// Whether the one text [text] is drawn whole — nothing cut by an ellipsis.
  bool textWhole(String text) => _whole(_in(find.text(text)));

  /// How many rows offer an edit.
  int get editButtonCount =>
      _in(find.byIcon(Icons.edit_outlined)).evaluate().length;

  Future<void> tapEntry(String title) => _tap(_in(find.text(title)));

  Finder _pencilOf(String title) => find.descendant(
    of: _entryRow(title),
    matching: find.byTooltip(_l10n.upcomingEditEvent),
  );

  Future<void> tapEdit(String title) => _tap(_pencilOf(title));

  /// Fires the entry's tap twice before anything has rebuilt, as a same-frame
  /// double tap does; a second `tester.tap` cannot reproduce it, since the
  /// route stops hit-testing the instant the first pop starts.
  void tapEntryTwiceInOneFrame(String title) {
    final row = tester.widget<FormPickerRow>(_entryRow(title));
    row.onTap!();
    row.onTap!();
  }

  /// The edit button's twin of [tapEntryTwiceInOneFrame].
  void tapEditTwiceInOneFrame(String title) {
    final button = tester
        .widget<FormPickerRow>(_entryRow(title))
        .trailingButton!;
    button.onPressed!();
    button.onPressed!();
  }

  /// How far the entry titled [title] is faded, or null when it is drawn at
  /// full strength.
  double? entryOpacity(String title) {
    final faded = find.ancestor(
      of: _in(find.text(title)),
      matching: find.byType(Opacity),
    );
    if (faded.evaluate().isEmpty) return null;
    return tester.widget<Opacity>(faded.first).opacity;
  }

  /// Whether the entry titled [title] shows a chevron — it never should: a
  /// tap selects a day, it opens nothing.
  bool entryShowsChevron(String title) => find
      .descendant(of: _entryRow(title), matching: find.byType(FormChevron))
      .evaluate()
      .isNotEmpty;

  /// What a screen reader hears for the entry titled [title]: one node for
  /// the row.
  SemanticsNode entryNode(String title) => _node(_in(find.text(title)));

  /// The pencil's own node beside the entry's.
  SemanticsNode pencilNode(String title) => _node(_pencilOf(title));

  /// Whether the day labelled [label] heads its group with a read row.
  bool showsReadRow(String label) => _shown(_readRow(label));

  bool readRowShowsChevron(String label) => find
      .descendant(of: _readRow(label), matching: find.byType(FormChevron))
      .evaluate()
      .isNotEmpty;

  /// Whether the read row labelled [label] is inert — drawn in full, with
  /// nothing a tap could do.
  bool readRowInert(String label) {
    final row = tester.widget<FormPickerRow>(_readRow(label));
    return row.onTap == null && row.enabled;
  }

  /// What a screen reader hears for the day labelled [label]: one node for
  /// the label and its count.
  SemanticsNode readRowNode(String label) => _node(_in(find.text(label)));

  // --- Month mode ------------------------------------------------------------

  /// Scrolls the month body to its end directly on the `ScrollPosition`, so
  /// the rows below the nav row and grid come into the lazy sliver's build
  /// range — `find.text` cannot see a `SliverList` item that has never been
  /// laid out. A position jump rather than a drag gesture: a drag's
  /// synthetic pointer travels across the day grid on the way down, and the
  /// grid is interactive.
  Future<void> scrollMonthBody() async {
    final scrollable = find.descendant(
      of: _in(find.byType(CustomScrollView)),
      matching: find.byType(Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable.first);
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pumpAndSettle();
  }

  Future<void> tapDay(int day) => _tap(_dayCell(day));

  /// Whether the mini grid draws [day] through its faded, inert path.
  bool isDayFaded(int day) =>
      tester.widget<CalendarDayCell>(_dayCell(day)).isOutside;

  bool isDayToday(int day) =>
      tester.widget<CalendarDayCell>(_dayCell(day)).isToday;

  /// Whether the mini grid draws [day]'s number whole inside its chip, on
  /// one line — the chip being the nearest box around the number. Read off
  /// the laid-out cell, so a row of the grid under the fold counts too.
  bool dayNumberWhole(int day) {
    final number = find.descendant(
      of: _dayCell(day),
      matching: find.text('$day'),
    );
    if (!_whole(number)) return false;
    final chip = tester.getRect(
      find.ancestor(of: number, matching: find.byType(Container)).first,
    );
    final rect = tester.getRect(number);
    return rect.left >= chip.left - 0.01 &&
        rect.right <= chip.right + 0.01 &&
        rect.top >= chip.top - 0.01 &&
        rect.bottom <= chip.bottom + 0.01;
  }

  /// Whether the weekday row above the mini grid draws [label] — "Mo." in
  /// German — whole and where a finger finds it.
  bool weekdayShown(String label) =>
      _shown(_in(find.text(label)).hitTestable()) && textWhole(label);

  /// How many day cells carry marker bars.
  int get dayBarCount => _in(find.byType(CalendarDayBars)).evaluate().length;

  /// Starts a horizontal swipe on the mini grid and leaves the frames to the
  /// caller, for a suite that reads a mid-swipe frame.
  Future<void> dragGrid(Offset delta) =>
      tester.drag(_in(find.byType(AgendaMonthGrid)), delta);

  /// The picked day's "Whole month" ✕, on its read row.
  Future<void> wholeMonth() =>
      _tap(_trailingButton(SemanticsIds.dayListWholeMonth));

  /// Whether a day is picked: its read row then carries the "Whole month" ✕,
  /// and no row does otherwise.
  bool get wholeMonthActive =>
      _shown(_trailingButton(SemanticsIds.dayListWholeMonth));

  /// The count the picked day's read row carries beside its label.
  String get pickedDayCount =>
      tester.widget<FormPickerRow>(_pickedDayRow).value!;

  // --- The period nav, month or year -----------------------------------------

  String get navTitle => _nav.title;

  String? get navCount => _nav.subtitle;

  bool get canGoPrevious => _nav.onPrevious != null;

  bool get canGoNext => _nav.onNext != null;

  bool get canJumpToToday => _nav.onToday != null;

  Finder get _navTitleText => _in(find.text(_nav.title));

  /// How many lines the nav's title took.
  int get navTitleLines => _linesOf(_navTitleText);

  /// Whether the nav's title may wrap to its second line rather than drop
  /// its year on one.
  bool get navTitleMayWrap {
    final text = tester.widget<Text>(_navTitleText);
    return text.maxLines == FormMetrics.periodTitleMaxLines &&
        text.softWrap == true;
  }

  Future<void> _tapNav(String id, int times) async {
    for (var i = 0; i < times; i++) {
      await _tap(_carrier(id));
    }
  }

  Future<void> previous({int times = 1}) =>
      _tapNav(SemanticsIds.dayListNavPrevious, times);

  Future<void> next({int times = 1}) =>
      _tapNav(SemanticsIds.dayListNavNext, times);

  Future<void> jumpToToday() => _tapNav(SemanticsIds.dayListNavToday, 1);

  /// Taps the period title, the jump control.
  Future<void> pickDate() => _tap(_carrier(SemanticsIds.dayListNavTitle));

  bool get jumpPickerOpen => _shown(find.byType(MonthYearPickerSheet));

  // --- Year mode -------------------------------------------------------------

  List<Text> get _tileTexts => tester
      .widgetList<Text>(find.descendant(of: _grid, matching: find.byType(Text)))
      .toList();

  /// The year tiles' month labels, in grid order. The count beside each label
  /// is a bare number, so anything unparseable is a label.
  List<String> get tileLabels => [
    for (final text in _tileTexts)
      if (int.tryParse(text.data ?? '') == null) text.data ?? '',
  ];

  /// The bare numbers the tiles carry, in grid order.
  List<String> get tileCounts => [
    for (final text in _tileTexts)
      if (int.tryParse(text.data ?? '') != null) text.data!,
  ];

  Future<void> tapTile(String label) =>
      _tap(find.descendant(of: _grid, matching: find.text(label)));

  /// Whether exactly one tile announces itself as [label] to a screen reader.
  bool announcesTile(Pattern label) {
    final handle = tester.ensureSemantics();
    try {
      return _shown(find.bySemanticsLabel(label));
    } finally {
      handle.dispose();
    }
  }

  /// The dot matrix of the tile labelled [label]. `find.ancestor` walks
  /// outward from the label, so the first `Material` is the tile's own.
  MonthDotMatrix matrixOf(String label) => tester.widget<MonthDotMatrix>(
    find.descendant(
      of: find
          .ancestor(of: _in(find.text(label)), matching: find.byType(Material))
          .first,
      matching: find.byType(MonthDotMatrix),
    ),
  );

  Future<void> flingYears(Offset delta) async {
    await tester.fling(_in(find.byType(PageView)), delta, 1000);
    await tester.pumpAndSettle();
  }

  // --- Leaving ---------------------------------------------------------------

  /// A tap on the scrim above the sheet.
  Future<void> tapBarrier() async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width / 2, 8));
    await tester.pumpAndSettle();
  }

  Future<void> systemBack() async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }
}
