import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../constants/fasting_calendar.dart';
import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_guide_content.dart';
import '../models/calendar_guide_demo.dart';
import '../models/fasting_appearance.dart';
import '../models/fasting_schedule.dart';
import '../services/cell_tint_resolver.dart';
import '../services/day_bars_resolver.dart';
import '../services/day_summary_resolver.dart';
import '../utils/guide_locale_format.dart';
import 'calendar_guide_grid.dart';
import 'calendar_guide_stage_slot.dart';
import 'calendar_guide_try_card.dart';
import 'day_summary_panel.dart';
import 'fasting_schedule_sheet.dart';
import 'fasting_style_sheet.dart';
import 'form_rows.dart';

/// The fasting page's card (D60–D62, D67): a month grid drawn by the real
/// fasting providers, under it a chip per tradition, the real Appearance and
/// My practice sheets and the Orthodox multi-day fasts, then the picked
/// day's panel.
///
/// Nothing is saved, and the engine's configuration is never touched: the
/// traditions, the look, the practice and the flag live here, the years are
/// built through [FastingCalendar.computeYear], and the providers read them
/// through this demo's [FastingLookup] — so the owner's own fasting settings
/// paint her calendar exactly as before while she plays here.
class GuideFastingDemo extends GuideCardDemo {
  GuideFastingDemo({DateTime Function() now = DateTime.now})
    : _today = _todayUtc(now()),
      super(CalendarGuideTopic.fasting.cards.single) {
    _lookup = _GuideFastingLookup(this);
  }

  static const String slug = 'fasting';

  static DateTime _todayUtc(DateTime now) =>
      DateTime.utc(now.year, now.month, now.day);

  /// Date-only UTC, read once.
  final DateTime _today;

  late final FastingLookup _lookup;

  Set<FastingTradition> _traditions = const {};
  FastingAppearance _look = const FastingAppearance();
  FastingSchedule _schedule = const FastingSchedule();
  bool _greatFasts = true;

  /// The years the grid and the panel can show, built when the traditions,
  /// the practice or the flag change and when the grid pages into another
  /// year — never in a build, where the lookup only reads them. A change of
  /// look drops nothing: the providers read the styles live.
  final Map<int, Map<DateTime, List<FastingInfo>>> _years = {};

  /// Bumped on every change the grid's bars depend on, so the demo
  /// calendar's per-day bar memo starts over with a new resolver.
  int _generation = 0;

  /// The calendar's own three factories over [_lookup], so a change to what
  /// the real grid and panel draw reaches this card too. Holidays and money
  /// are left out: the lesson is the fast days; the weekend stays, as the
  /// factories give it.
  DayBarsResolver? _barsResolver;
  DaySummaryResolver? _summaryResolver;
  CellTintResolver? _tintResolver;
  Object? _resolverKey;

  /// An empty calendar: the fast days are the lesson, and an event's bars
  /// would only crowd them. Built on the first draw, which has a language.
  GuideDemoCalendar? _calendar;

  final GuideLocaleFormat _monthTitle = GuideLocaleFormat(DateFormat.yMMMM);

  @override
  bool get needsAppearance => true;

  @override
  bool get stageFullBleed => true;

  /// With every tradition off the other rows are disabled, so the line asks
  /// for a tradition again (D44: a line says where, and never at a row she
  /// cannot tap). The steps she did stay done; the closing line stands.
  @override
  String line(AppLocalizations l10n) => _traditions.isEmpty && !finished
      ? steps.first.line(l10n)
      : super.line(l10n);

  /// The first tradition that is on, in declaration order — whose look the
  /// Appearance row opens, as the grid colours a day only one marks.
  FastingTradition? get _firstOn {
    for (final tradition in FastingTradition.values) {
      if (_traditions.contains(tradition)) return tradition;
    }
    return null;
  }

  List<FastingInfo> _on(DateTime day) {
    if (_traditions.isEmpty) return const [];
    final key = DateTime.utc(day.year, day.month, day.day);
    return _years[key.year]?[key] ?? const [];
  }

  /// The years a six-row grid of [_calendar]'s focused month can show — a
  /// week either side of the month at most — and the picked day's, built if
  /// missing; the others dropped.
  void _ensureYears() {
    final calendar = _calendar;
    if (_traditions.isEmpty || calendar == null) {
      _years.clear();
      return;
    }
    final focused = calendar.focusedDay;
    final needed = {
      DateTime.utc(focused.year, focused.month, 1 - 7).year,
      DateTime.utc(focused.year, focused.month + 1, 14).year,
      calendar.selectedDay.year,
    };
    _years.removeWhere((year, _) => !needed.contains(year));
    for (final year in needed) {
      _years[year] ??= FastingCalendar.computeYear(
        year,
        traditions: _traditions,
        orthodoxGreatFasts: _greatFasts,
        schedule: _schedule,
      );
    }
  }

  /// Which days fast moved: every year is built again.
  void _rebuildYears() {
    _years.clear();
    _ensureYears();
    _generation++;
  }

  void _setTradition(FastingTradition tradition, bool on) {
    _traditions = Set.unmodifiable(
      on ? {..._traditions, tradition} : ({..._traditions}..remove(tradition)),
    );
    _rebuildYears();
    if (on) {
      did('tradition');
    } else {
      changed();
    }
  }

  void _setGreatFasts(bool value) {
    _greatFasts = value;
    _rebuildYears();
    changed();
  }

  /// The real style sheet for [tradition], in its sandbox, every change
  /// kept here; the step is marked once the sheet has closed — the card's
  /// line is a live region, and a new line under the sheet would be spoken
  /// over it.
  Future<void> _editStyle(
    BuildContext context,
    FastingTradition tradition,
  ) async {
    await FastingStyleSheet.show(
      context,
      tradition: tradition,
      initialStyle: _look.styleFor(tradition),
      sandbox: true,
      onChanged: (style) {
        _look = _look.withStyle(tradition, style);
        _generation++;
        changed();
      },
    );
    did('style');
  }

  /// The real practice sheet, every change kept here; marked once it has
  /// closed, as [_editStyle].
  Future<void> _editSchedule(BuildContext context) async {
    await FastingScheduleSheet.show(
      context,
      initialSchedule: _schedule,
      appearance: appearance,
      onChanged: (schedule) {
        _schedule = schedule;
        _rebuildYears();
        changed();
      },
    );
    did('practice');
  }

  void _pickDay(DateTime day, DateTime focused) {
    final calendar = _calendar!;
    calendar.selectedDay = day;
    calendar.focus(focused);
    _ensureYears();
    changed();
  }

  void _turnPage(DateTime focused) {
    _calendar!.focus(focused);
    _ensureYears();
    changed();
  }

  void _resolversFor(AppLocalizations l10n) {
    final key = (l10n, appearance, _generation);
    if (key == _resolverKey) return;
    _resolverKey = key;
    _barsResolver = DayBarsResolver.defaults(
      l10n,
      missedDisplay: appearance.missedDisplay,
      showHolidays: false,
      showMoney: false,
      fastingLookup: _lookup,
    );
    _summaryResolver = DaySummaryResolver.defaults(
      l10n,
      showRecurrence: appearance.showRecurrenceLabels,
      showHolidays: false,
      showMoney: false,
      fastingLookup: _lookup,
    );
    _tintResolver = CellTintResolver.defaults(
      appearance,
      fastingLookup: _lookup,
    );
  }

  /// The four traditions as one row of chips under the grid (D67): four
  /// switch rows above it stood 200 dp tall, and on a 360 × 780 phone the
  /// grid a tradition washes sat below the screen's edge.
  Widget _traditionChips(AppLocalizations l10n) => FormChipRow(
    indented: false,
    chips: [
      for (final tradition in FastingTradition.values)
        FormChip(
          label: FastingCalendar.traditionNameOf(tradition, l10n),
          selected: _traditions.contains(tradition),
          identifier: SemanticsIds.calendarGuideTryControl(
            slug,
            'tradition-${tradition.name}',
          ),
          onTap: () =>
              _setTradition(tradition, !_traditions.contains(tradition)),
        ),
    ],
  );

  Widget _appearanceRow(
    AppLocalizations l10n,
    FastingTradition? tradition, {
    VoidCallback? onTap,
    String? identifier,
  }) => FormPickerRow(
    glyph: Icons.tune_rounded,
    label: l10n.fastingAppearanceTitle,
    value: tradition == null
        ? null
        : FastingCalendar.traditionNameOf(tradition, l10n),
    enabled: tradition != null,
    identifier: identifier,
    onTap: onTap,
  );

  @override
  Widget buildStage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final calendar = _calendar ??= GuideDemoCalendar.empty(
      l10n: l10n,
      today: _today,
    );
    _resolversFor(l10n);
    String control(String name) =>
        SemanticsIds.calendarGuideTryControl(slug, name);
    final first = _firstOn;
    final orthodoxOn = _traditions.contains(FastingTradition.orthodox);
    // Inset like the other stages' rows until they too go edge to edge; the
    // grid always runs the stage's width.
    final rowsInset =
        MediaQuery.textScalerOf(context).scale(1) <
            GuideMetrics.stageFullBleedTextScale
        ? const EdgeInsets.symmetric(horizontal: GuideMetrics.stagePadding)
        : EdgeInsets.zero;
    // The grid first, the controls under it (D67): what a chip changes is
    // above the finger that taps it, and stays in view.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GuideCalendarGrid(
          demo: calendar,
          appearance: appearance,
          barsResolver: _barsResolver!,
          monthTitle: _monthTitle,
          onDaySelected: _pickDay,
          onPageChanged: _turnPage,
          holdsMonthHeight: true,
          tintResolver: _tintResolver!,
          numberColorFor: (day) => FastingCalendar.resolveCellStyle(
            _lookup.on(day),
            _lookup.appearance,
          ).numberColor,
        ),
        Padding(
          padding: rowsInset,
          child: FormRowGroup(
            children: [
              _traditionChips(l10n),
              // As tall as the row is under any tradition's name, so the
              // name arriving never moves the grid below.
              FormCaptionSlot(
                candidates: [
                  _appearanceRow(l10n, null),
                  for (final tradition in FastingTradition.values)
                    _appearanceRow(l10n, tradition),
                ],
                child: _appearanceRow(
                  l10n,
                  first,
                  identifier: control('appearance'),
                  onTap: first == null
                      ? null
                      : () => _editStyle(context, first),
                ),
              ),
              FormPickerRow(
                glyph: Icons.event_repeat_rounded,
                label: l10n.fastingScheduleTitle,
                enabled: first != null,
                identifier: control('practice'),
                onTap: first == null ? null : () => _editSchedule(context),
              ),
              FormSwitchRow(
                glyph: Icons.date_range_rounded,
                label: l10n.fastingOrthodoxGreatFasts,
                value: _greatFasts,
                identifier: control('great-fasts'),
                onChanged: orthodoxOn ? _setGreatFasts : null,
              ),
            ],
          ),
        ),
        GuideStageSlot(
          height: GuideMetrics.fastingPanelHeight,
          child: DaySummaryPanel(
            day: calendar.selectedDay,
            entries: _summaryResolver!.resolve(calendar.selectedDay, const []),
          ),
        ),
      ],
    );
  }
}

/// The card's own fasting days and look, for the real providers.
class _GuideFastingLookup extends FastingLookup {
  const _GuideFastingLookup(this._demo);

  final GuideFastingDemo _demo;

  @override
  List<FastingInfo> on(DateTime day) => _demo._on(day);

  @override
  FastingAppearance get appearance => _demo._look;
}
