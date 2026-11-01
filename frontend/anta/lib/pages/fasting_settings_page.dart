import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_icons.dart';
import '../constants/fasting_calendar.dart';
import '../constants/form_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_guide_content.dart';
import '../models/fasting_appearance.dart';
import '../models/fasting_schedule.dart';
import '../services/app_navigator.dart';
import '../services/calendar_palette_service.dart';
import '../services/recurrence_formatter.dart';
import '../services/settings_service.dart';
import '../utils/settings_search.dart';
import '../widgets/fasting_schedule_sheet.dart';
import '../widgets/fasting_style_sheet.dart';
import '../widgets/form_rows.dart' show FormCaptionSlot;
import '../widgets/settings_section_list.dart';
import '../widgets/unified_app_bars.dart';

/// Every fasting option on one page (D6 of `docs/settings-rework-roadmap.md`).
///
/// The rows lived as a section of Calendar settings, where the look rows,
/// the multi-day fasts switch and the practice row were hidden until a
/// tradition was on — invisible to the eye and to search (S14). They moved
/// here whole, with their state, their writes and the palette prewarm, and
/// stay on screen disabled instead; the wording follows N109 (the multi-day
/// fasts switch says what its off means), N111 (inside the schedule sheet)
/// and N119 (the look row says where the look shows, not "Appearance"). The
/// two sheets stay live-apply. Calendar settings keeps a single row that
/// opens this page.
class FastingSettingsPage extends StatefulWidget {
  const FastingSettingsPage({super.key});

  /// "Wed, Fri · All year · 3 exceptions" — the three facts that decide which
  /// days get marked, in the order the engine applies them.
  static String practiceSummary(
    AppLocalizations l10n,
    FastingSchedule schedule,
  ) {
    final parts = <String>[
      schedule.weekdays.isEmpty
          ? l10n.fastingScheduleNoDays
          : RecurrenceFormatter.formatWeekdays(
              schedule.weekdays,
              l10n.localeName,
            ),
      if (schedule.keepsEveryMonth)
        l10n.fastingScheduleAllYear
      else if (schedule.months.isEmpty)
        l10n.fastingScheduleNoMonths
      else
        l10n.fastingMonthsCount(schedule.months.length),
      if (schedule.exceptionCount > 0)
        l10n.fastingExceptionsCount(schedule.exceptionCount),
    ];
    // A no-break space before each dot, so a wrapped line never ends on one.
    return parts.join('\u00A0· ');
  }

  /// The traditions on — the value line of Calendar settings' row to this
  /// page — or "Off" when none is on. The practice stays on this page: under
  /// the traditions it made the row a paragraph whose height changed with
  /// every visit, and that row sits above others.
  static String summary(
    AppLocalizations l10n, {
    required Set<FastingTradition> traditions,
  }) {
    if (traditions.isEmpty) return l10n.fastingTraditionsOff;
    return [
      for (final tradition in FastingTradition.values)
        if (traditions.contains(tradition))
          FastingCalendar.traditionNameOf(tradition, l10n),
    ].join('\u00A0· ');
  }

  @override
  State<FastingSettingsPage> createState() => _FastingSettingsPageState();
}

class _FastingSettingsPageState extends State<FastingSettingsPage> {
  // Persisted fold state is keyed on these, so they are frozen strings, not
  // titles and not positions. They share the calendar settings page's stored
  // set, as the alert page's do; the `fasting_` prefix keeps them apart from
  // that page's own `fasting` section.
  static const String _sectionTraditions = 'fasting_traditions';
  static const String _sectionPractice = 'fasting_practice';
  static const String _sectionHowItWorks = 'fasting_how_it_works';

  SettingsService? _settings;
  bool _isLoading = true;
  Set<String> _collapsedSections = const {};
  int _foldEdits = 0;
  bool _hapticFeedback = true;

  /// Handed to the schedule sheet, whose preview draws the grid as the
  /// calendar does.
  CalendarAppearance _appearance = const CalendarAppearance();

  Set<FastingTradition> _fastingTraditions = const {};
  FastingAppearance _fastingAppearance = const FastingAppearance();
  bool _fastingGreatFasts = true;
  FastingSchedule _fastingSchedule = const FastingSchedule();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    final appearance = await settings.getCalendarAppearance();
    final haptic = await settings.getHapticFeedback();
    final fastingTraditions = await settings.getFastingTraditions();
    final fastingAppearance = await settings.getFastingAppearance();
    final fastingGreatFasts = await settings.getFastingOrthodoxGreatFasts();
    final fastingSchedule = await settings.getFastingSchedule();
    final collapsedSections = await settings
        .getCalendarSettingsCollapsedSections();
    // Publishes the palette facade the style sheet's swatch picker reads
    // synchronously; without it a sheet opened from here before any other
    // picker would offer zero of the colours the user does have. The page
    // shows no row before this lands, so no sheet can open ahead of it.
    await CalendarPaletteService.getInstance();

    if (!mounted) return;
    setState(() {
      _settings = settings;
      _collapsedSections = collapsedSections;
      _appearance = appearance;
      _hapticFeedback = haptic;
      _fastingTraditions = fastingTraditions;
      _fastingAppearance = fastingAppearance;
      _fastingGreatFasts = fastingGreatFasts;
      _fastingSchedule = fastingSchedule;
      _isLoading = false;
    });
  }

  /// Optimistic like every other row on this page: the fold is a view
  /// preference, so a failed write costs nothing worth blocking the tap for.
  /// The write edits the stored row, which the other calendar pages share,
  /// and the last tap's answer is adopted (`CalendarSettingsPage`'s toggle
  /// says why).
  Future<void> _toggleSection(String id) async {
    _onHapticFeedback();
    final next = {..._collapsedSections};
    final collapsed = !next.remove(id);
    if (collapsed) next.add(id);
    final edit = ++_foldEdits;
    setState(() => _collapsedSections = next);
    final stored = await _settings?.setCalendarSettingsSectionCollapsed(
      id,
      collapsed: collapsed,
    );
    if (stored != null && mounted && edit == _foldEdits) {
      setState(() => _collapsedSections = stored);
    }
  }

  Future<void> _toggleFastingTradition(
    FastingTradition tradition,
    bool enabled,
  ) async {
    _onHapticFeedback();
    setState(() {
      final next = {..._fastingTraditions};
      enabled ? next.add(tradition) : next.remove(tradition);
      _fastingTraditions = next;
    });
    await _settings?.setFastingTraditions(_fastingTraditions);
  }

  FastingTraditionStyle _fastingStyleOf(FastingTradition tradition) =>
      _fastingAppearance.styleFor(tradition);

  /// "Subtle tint · After holidays" — the two choices that actually change
  /// where the user will see the fast.
  String _fastingStyleSummary(
    FastingTradition tradition,
    AppLocalizations l10n,
  ) {
    final style = _fastingStyleOf(tradition);
    return '${FastingCalendar.styleNameOf(style.style, l10n)}\u00A0· '
        '${FastingCalendar.placementNameOf(style.placement, l10n)}';
  }

  /// Opens the per-tradition appearance sheet. Edits arrive live through
  /// `onChanged`, so each tap persists and repaints the row behind the
  /// sheet — closing is never a "discard".
  Future<void> _editFastingStyle(FastingTradition tradition) async {
    await FastingStyleSheet.show(
      context,
      tradition: tradition,
      initialStyle: _fastingStyleOf(tradition),
      onChanged: (style) async {
        setState(() {
          _fastingAppearance = _fastingAppearance.withStyle(tradition, style);
        });
        await _settings?.setFastingAppearance(_fastingAppearance);
      },
    );
  }

  /// Opens the personal schedule sheet. Like the appearance sheet, edits
  /// arrive live through `onChanged`, so each tap persists and the summary
  /// row behind the sheet repaints — closing is never a "discard".
  Future<void> _editFastingSchedule() async {
    await FastingScheduleSheet.show(
      context,
      initialSchedule: _fastingSchedule,
      appearance: _appearance,
      onChanged: (schedule) async {
        setState(() => _fastingSchedule = schedule);
        await _settings?.setFastingSchedule(schedule);
      },
    );
  }

  void _onHapticFeedback() {
    if (_hapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  /// A row's leading glyph, at the disabled opacity while the row is: the
  /// tile greys its texts and chevron itself, but a glyph given a colour of
  /// its own keeps it.
  Widget _glyph(IconData icon, ColorScheme colorScheme, {bool enabled = true}) {
    return Icon(
      icon,
      color: enabled
          ? colorScheme.primary
          : colorScheme.primary.withValues(alpha: FormMetrics.disabledOpacity),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: colorScheme.pageGround,
      appBar: SettingsAppBar(
        title: l10n.fastingSettingsTitle,
        identifier: SemanticsIds.settingsBarFasting,
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SettingsSectionList(
                query: SettingsQuery.empty,
                listIdentifier: SemanticsIds.fastingSettingsList,
                sections: [
                  _buildTraditionsSection(colorScheme, l10n),
                  _buildPracticeSection(colorScheme, l10n),
                  _buildHowItWorksSection(colorScheme, l10n),
                ],
                collapsedSections: _collapsedSections,
                onToggleSection: _toggleSection,
              ),
      ),
    );
  }

  /// One switch per tradition, each followed by its look row, and Orthodox's
  /// also by its multi-day fasts. A sub-row stays while its tradition is
  /// off, disabled: hiding it moved every row below under the finger at each
  /// toggle and took it out of search (S14).
  SettingsSectionData _buildTraditionsSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final entries = <SettingsEntry>[];
    for (final tradition in FastingTradition.values) {
      final traditionName = FastingCalendar.traditionNameOf(tradition, l10n);
      final on = _fastingTraditions.contains(tradition);
      final style = _fastingStyleOf(tradition);
      entries
        ..add(
          SettingsEntry(
            title: traditionName,
            identifier: SemanticsIds.fastingTraditionSwitch(tradition.name),
            builder: (context, title, description) => SwitchListTile(
              value: on,
              // The tradition's own glyph names the row; the look's colour
              // stays on the look sheet, since a row's glyph never previews
              // a value.
              secondary: Icon(
                CalendarIcons.forKey(style.iconKey) ??
                    FastingCalendar.defaultIconOf(tradition),
                color: colorScheme.onSurfaceVariant,
              ),
              title: title,
              onChanged: (value) => _toggleFastingTradition(tradition, value),
            ),
          ),
        )
        ..add(
          SettingsEntry(
            title: l10n.fastingLookRow,
            description: _fastingStyleSummary(tradition, l10n),
            identifier: SemanticsIds.calendarFastingStyleOpen(tradition.name),
            builder: (context, title, description) => ListTile(
              enabled: on,
              // No glyph of its own, its words in the switch's title column:
              // the row belongs to the tradition above it, and a glyph there
              // too left German and Romanian at 2.0 a column narrower than
              // their longest words.
              contentPadding: FormMetrics.settingsRowPadding.copyWith(
                start: FormMetrics.settingsSubRowInset,
              ),
              // The four look rows share a title, so the spoken name leads
              // with the tradition; the visible words stay inside it.
              title: Semantics(
                label: '$traditionName, ${l10n.fastingLookRow}',
                child: ExcludeSemantics(child: title),
              ),
              subtitle: description,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: on ? () => _editFastingStyle(tradition) : null,
            ),
          ),
        );
      if (tradition == FastingTradition.orthodox) {
        entries.add(_greatFastsEntry(l10n, enabled: on));
      }
    }
    return SettingsSectionData(
      id: _sectionTraditions,
      icon: Icons.restaurant_menu_rounded,
      title: l10n.fastingSectionTraditions,
      intro: Padding(
        padding: FormMetrics.settingsRowPadding.copyWith(
          bottom: FormMetrics.settingsRowVerticalPadding,
        ),
        child: Text(l10n.fastingSectionDesc),
      ),
      entries: entries,
    );
  }

  /// The Orthodox multi-day fasts, a sub-row of the Orthodox switch set in
  /// like its look row, without a glyph, disabled while Orthodox is off. Its
  /// caption says what the switch's value means — the fasts it marks, or
  /// what is left without them (N109) — in a slot as tall as the taller of
  /// the two, so a toggle never moves the switch under the finger.
  SettingsEntry _greatFastsEntry(
    AppLocalizations l10n, {
    required bool enabled,
  }) {
    return SettingsEntry(
      title: l10n.fastingOrthodoxGreatFasts,
      description: _fastingGreatFasts
          ? l10n.fastingOrthodoxGreatFastsDesc
          : l10n.fastingGreatFastsOffDesc,
      identifier: SemanticsIds.fastingGreatFastsSwitch,
      builder: (context, title, description) => SwitchListTile(
        value: _fastingGreatFasts,
        contentPadding: FormMetrics.settingsRowPadding.copyWith(
          start: FormMetrics.settingsSubRowInset,
        ),
        title: title,
        subtitle: FormCaptionSlot(
          candidates: [
            Text(
              l10n.fastingOrthodoxGreatFastsDesc,
              style: settingsCaptionStyle,
            ),
            Text(l10n.fastingGreatFastsOffDesc, style: settingsCaptionStyle),
          ],
          child: description!,
        ),
        onChanged: enabled
            ? (value) async {
                _onHapticFeedback();
                setState(() => _fastingGreatFasts = value);
                await _settings?.setFastingOrthodoxGreatFasts(value);
              }
            : null,
      ),
    );
  }

  /// Disabled while no tradition is on, not only while Orthodox is off: the
  /// schedule subtracts from every tradition's weekly rule, so a
  /// Catholic-only install needs it for the Friday it controls.
  SettingsSectionData _buildPracticeSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final enabled = _fastingTraditions.isNotEmpty;
    return SettingsSectionData(
      id: _sectionPractice,
      icon: Icons.event_repeat_rounded,
      title: l10n.fastingPracticeRow,
      entries: [
        SettingsEntry(
          title: l10n.fastingPracticeRow,
          description: FastingSettingsPage.practiceSummary(
            l10n,
            _fastingSchedule,
          ),
          identifier: SemanticsIds.calendarFastingScheduleOpen,
          builder: (context, title, description) => ListTile(
            enabled: enabled,
            leading: _glyph(
              Icons.event_repeat_rounded,
              colorScheme,
              enabled: enabled,
            ),
            title: title,
            subtitle: description,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: enabled ? _editFastingSchedule : null,
          ),
        ),
      ],
    );
  }

  /// The guide's fasting topic, opened straight from here (D12).
  SettingsSectionData _buildHowItWorksSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      id: _sectionHowItWorks,
      icon: Icons.school_rounded,
      title: l10n.calendarGuideHowItWorks,
      entries: [
        SettingsEntry(
          // Titled by the topic it opens, as the guide's hub lists it; the
          // section header already says what kind of row this is.
          title: l10n.calendarGuidePageFasting,
          description: l10n.calendarGuidePageFastingCaption,
          identifier: SemanticsIds.fastingSettingsHowItWorksOpen,
          builder: (context, title, description) => ListTile(
            leading: _glyph(Icons.school_rounded, colorScheme),
            title: title,
            subtitle: description,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              _onHapticFeedback();
              AppNavigator.toCalendarGuideTopic(
                context,
                CalendarGuideTopic.fasting,
              );
            },
          ),
        ),
      ],
    );
  }
}
