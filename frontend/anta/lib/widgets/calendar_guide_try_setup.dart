import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/guide_metrics.dart';
import '../constants/public_holidays.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../services/app_navigator.dart';
import 'calendar_appearance_preview.dart';
import 'calendar_guide_try_card.dart';
import 'form_rows.dart';

/// The setup page's card: the holiday set as a menu over the real holiday
/// builders, the next three holidays of the set picked, the first day of
/// the week turning the appearance page's sample week, and the way to the
/// real Calendar settings. Nothing is saved: the set and the first day she
/// picks here stay here.
class GuideSetupDemo extends GuideCardDemo {
  GuideSetupDemo({DateTime Function() now = DateTime.now})
    : _today = _todayUtc(now());

  static const String slug = 'setup';

  /// How many of the set's next holidays the stage names.
  static const int nextShown = 3;

  static DateTime _todayUtc(DateTime now) =>
      DateTime.utc(now.year, now.month, now.day);

  /// Date-only UTC, read once.
  final DateTime _today;

  /// The set shown: the owner's own once the page has read it, then hers.
  HolidayProfile _profile = HolidayProfile.generic;
  bool _profilePicked = false;
  CalendarWeekStart? _weekStart;

  @override
  bool get needsAppearance => true;

  /// The owner's holiday set, read by the page with her calendar look; a
  /// set she already picked here stays.
  set holidayProfile(HolidayProfile value) {
    if (_profilePicked) return;
    _profile = value;
    changed();
  }

  String get _year => '${_today.year}';

  /// The set's count this year: the caption before and after every pick.
  @override
  String idle(AppLocalizations l10n) =>
      l10n.calendarGuideDemoHolidays(_countOf(_profile), _year);

  /// [profile]'s holidays inside this year, worked out once per set. A
  /// year's seeds may hold a day of the year before (a Saturday 1 January
  /// observed on 31 December), which is not this year's to count.
  int _countOf(HolidayProfile profile) =>
      _counts[profile] ??= HolidaySeeds.forYear(
        profile,
        _today.year,
      ).keys.where((day) => day.year == _today.year).length;

  final Map<HolidayProfile, int> _counts = {};

  final GuideLocaleFormat _dates = GuideLocaleFormat(DateFormat.yMMMMEEEEd);

  /// Each plural form at its widest digits.
  @override
  List<String> candidates(AppLocalizations l10n) => [
    for (final count in const [1, 19, 88])
      l10n.calendarGuideDemoHolidays(count, _year),
  ];

  static String _nameOf(HolidayOccurrence occurrence, AppLocalizations l10n) {
    final name = PublicHolidays.nameOf(occurrence.holiday, l10n);
    return occurrence.observed ? l10n.publicHolidayObserved(name) : name;
  }

  static String _line(String date, String name) => '$date · $name';

  /// [profile]'s next [nextShown] holidays from today, one a line, into
  /// next year when this one runs out. Both years' seeds go into one map
  /// first: next year's may hold this year's 31 December too, and a day
  /// is listed once.
  String _nextLines(AppLocalizations l10n, HolidayProfile profile) {
    final dates = _dates.of(l10n);
    final holidays = <DateTime, HolidayOccurrence>{
      ...HolidaySeeds.forYear(profile, _today.year + 1),
      ...HolidaySeeds.forYear(profile, _today.year),
    };
    final days = holidays.keys.where((day) => !day.isBefore(_today)).toList()
      ..sort();
    return [
      for (final day in days.take(nextShown))
        _line(dates.format(day), _nameOf(holidays[day]!, l10n)),
    ].join('\n');
  }

  /// Every set's next days: the only texts the slot can show, since today
  /// does not move while the card is open, so it is sized for exactly
  /// those and never grows with the set picked. Built once per language;
  /// the line shown is the picked set's among them.
  List<String> _everySetsLines(AppLocalizations l10n) {
    if (_linesLocale != l10n.localeName) {
      _linesLocale = l10n.localeName;
      _lines = [
        for (final profile in HolidayProfile.values) _nextLines(l10n, profile),
      ];
    }
    return _lines;
  }

  List<String> _lines = const [];
  String? _linesLocale;

  /// The week start's label as the appearance page writes it
  /// (`_weekStartLabel` in `calendar_appearance_page.dart`): the weekday's
  /// own name from `intl`, never an ARB matrix — here its short form, so the
  /// three segments sit side by side on a stage narrower than that page.
  static String _weekStartLabel(
    CalendarWeekStart start,
    DateFormat weekdays,
    String localeName,
  ) {
    final anchor = DateTime.utc(2024, 1, start.weekday);
    final name = weekdays.format(anchor);
    return toBeginningOfSentenceCase(name, localeName) ?? name;
  }

  final GuideLocaleFormat _weekdays = GuideLocaleFormat(DateFormat.E);

  /// The three labels, made once per language.
  Map<CalendarWeekStart, String> _weekStartLabels(AppLocalizations l10n) {
    final localeName = l10n.localeName;
    if (_labelsLocale != localeName) {
      _labelsLocale = localeName;
      final weekdays = _weekdays.of(l10n);
      _labels = {
        for (final start in CalendarWeekStart.values)
          start: _weekStartLabel(start, weekdays, localeName),
      };
    }
    return _labels;
  }

  Map<CalendarWeekStart, String> _labels = const {};
  String? _labelsLocale;

  /// [_wordsFit]'s last answer and what it was measured for: the width, the
  /// label size and the language, the only things it reads that change. A
  /// layout pass otherwise laid every word out again.
  (double, double, String)? _fitKey;
  bool _fits = true;

  /// The spaces the line breaker breaks at, as `settings_page.dart` lists
  /// them: the no-break ones hold their words together.
  static final RegExp _breakingSpaces = RegExp(
    '[ \\t\\n\\u1680\\u2000-\\u2006\\u2008-\\u200A\\u205F\\u3000]+',
  );

  /// Whether every word of [labels] fits a segment [segmentWidth] wide on
  /// one line — `_choiceWordsFit` in `settings_page.dart`, the settings
  /// kit's rule for a choice row: a segment never moves a word to the next
  /// segment, so a word wider than its third would break mid-word.
  static bool _wordsFit(
    BuildContext context,
    Iterable<String> labels,
    double segmentWidth,
  ) {
    final style = Theme.of(context).textTheme.labelLarge;
    final textScaler = MediaQuery.textScalerOf(context);
    final fontSize = style?.fontSize ?? 14;
    final padding = ButtonStyleButton.scaledPadding(
      const EdgeInsets.symmetric(horizontal: 12),
      const EdgeInsets.symmetric(horizontal: 8),
      const EdgeInsets.symmetric(horizontal: 4),
      textScaler.scale(fontSize) / 14,
    ).resolve(Directionality.of(context));
    final room = segmentWidth - padding.horizontal;
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: textScaler,
      maxLines: 1,
    );
    try {
      for (final label in labels) {
        for (final word in label.split(_breakingSpaces)) {
          painter
            ..text = TextSpan(text: word, style: style)
            ..layout();
          if (room - painter.width < 0.5) return false;
        }
      }
      return true;
    } finally {
      painter.dispose();
    }
  }

  Widget _holidayRow(
    AppLocalizations l10n,
    HolidayProfile shown, {
    required ValueChanged<HolidayProfile>? onSelected,
  }) => FormMenuRow<HolidayProfile>(
    glyph: Icons.public_rounded,
    label: l10n.holidayProfileTitle,
    value: PublicHolidays.profileNameOf(shown, l10n),
    selected: shown,
    items: [
      for (final profile in HolidayProfile.values)
        FormMenuItem(
          value: profile,
          label: PublicHolidays.profileNameOf(profile, l10n),
          identifier: SemanticsIds.calendarGuideTryControl(
            slug,
            'holidays-${profile.name}',
          ),
        ),
    ],
    menuWidth: FormMetrics.menuWidth,
    identifier: onSelected == null
        ? null
        : SemanticsIds.calendarGuideTryControl(slug, 'holidays'),
    onSelected: onSelected,
  );

  Widget _weekStartChoice(BuildContext context, CalendarWeekStart selected) {
    final l10n = AppLocalizations.of(context)!;
    final labels = _weekStartLabels(l10n);
    return LayoutBuilder(
      builder: (context, constraints) {
        final key = (
          constraints.maxWidth,
          MediaQuery.textScalerOf(context).scale(1),
          l10n.localeName,
        );
        if (key != _fitKey) {
          _fitKey = key;
          _fits = _wordsFit(
            context,
            labels.values,
            constraints.maxWidth / labels.length,
          );
        }
        final horizontal = _fits;
        return SizedBox(
          width: double.infinity,
          child: SegmentedButton<CalendarWeekStart>(
            direction: horizontal ? Axis.horizontal : Axis.vertical,
            style: horizontal
                ? null
                : const ButtonStyle(
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(FormMetrics.menuRadius),
                        ),
                      ),
                    ),
                  ),
            showSelectedIcon: false,
            segments: [
              for (final entry in labels.entries)
                ButtonSegment<CalendarWeekStart>(
                  value: entry.key,
                  // A segment takes no id of its own; the label's merges
                  // into the segment's node.
                  label: Semantics(
                    identifier: SemanticsIds.calendarGuideTryControl(
                      slug,
                      'week-${entry.key.name}',
                    ),
                    child: Text(entry.value, textAlign: TextAlign.center),
                  ),
                ),
            ],
            selected: {selected},
            onSelectionChanged: (selection) {
              _weekStart = selection.first;
              changed();
            },
          ),
        );
      },
    );
  }

  @override
  Widget buildStage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final weekStart = _weekStart ?? appearance.weekStart;
    String control(String name) =>
        SemanticsIds.calendarGuideTryControl(slug, name);
    // Under the menu row's label, past its glyph column.
    const captionPadding = EdgeInsets.only(
      left: RowMetrics.groupInset + FormMetrics.glyphSize + FormMetrics.gap,
      right: RowMetrics.groupInset,
      bottom: FormMetrics.rowCaptionBottomPadding,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormRowGroup(
          children: [
            // The menu and the set's next days as one row: the days are
            // the value's continuation, so no hairline between them.
            FormIndentedRow(
              dividerIndent: FormMetrics.dividerIndentGlyph,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // As tall as the row is under any set's name: a name that
                  // takes a second line would otherwise move everything
                  // under the menu when she picks it.
                  FormCaptionSlot(
                    candidates: [
                      for (final profile in HolidayProfile.values)
                        _holidayRow(l10n, profile, onSelected: null),
                    ],
                    child: _holidayRow(
                      l10n,
                      _profile,
                      onSelected: (profile) {
                        _profile = profile;
                        _profilePicked = true;
                        changed();
                      },
                    ),
                  ),
                  Padding(
                    padding: captionPadding,
                    child: FormCaptionSlot(
                      candidates: [
                        for (final lines in _everySetsLines(l10n))
                          FormCaption(text: lines),
                      ],
                      child: FormCaption(
                        text: _everySetsLines(l10n)[_profile.index],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            FormIndentedRow(
              dividerIndent: FormMetrics.dividerIndentPlain,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  RowMetrics.groupInset,
                  FormMetrics.pairVerticalPadding,
                  RowMetrics.groupInset,
                  FormMetrics.pairVerticalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.calendarWeekStartTitle,
                      style: FormLabelValue.labelStyle(colorScheme.onSurface),
                    ),
                    const SizedBox(height: FormMetrics.pairVerticalPadding),
                    _weekStartChoice(context, weekStart),
                  ],
                ),
              ),
            ),
          ],
        ),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: GuideMetrics.sampleWeekMaxTextScale,
          child: CalendarAppearancePreview(
            appearance: appearance.copyWith(weekStart: weekStart),
          ),
        ),
        const SizedBox(height: RowMetrics.groupGap),
        FormRowGroup(
          trailingGap: false,
          children: [
            FormActionRow(
              glyph: Icons.open_in_new_rounded,
              label: l10n.calendarGuideOpenSettings(l10n.calendarSettingsRow),
              identifier: control('settings'),
              onTap: () => AppNavigator.toCalendarSettings(context),
            ),
          ],
        ),
      ],
    );
  }
}
