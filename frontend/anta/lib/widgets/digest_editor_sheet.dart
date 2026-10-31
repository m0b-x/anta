import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, toBeginningOfSentenceCase;

import '../constants/alert_constants.dart';
import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/event_digests.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/event_digest.dart';
import '../services/event_time_formatter.dart';
import '../utils/alert_labels.dart';
import '../utils/calendar_week_start.dart';
import '../utils/digest_labels.dart';
import '../utils/digest_planner.dart';
import 'app_dialogs.dart';
import 'category_picker_sheet.dart';
import 'form_rows.dart';
import 'overlay_snackbar.dart';
import 'time_pad_sheet.dart';

/// What the digest sheet hands back; `null` when it was left, or saved with
/// nothing changed.
sealed class DigestEditorResult {
  const DigestEditorResult();
}

/// The digest as the sheet left it, with the id it has: `''` for a new one,
/// enabled — the service mints its id and its position on create — or an
/// existing one with its id, switch and position kept.
final class DigestEditorSaved extends DigestEditorResult {
  final EventDigest digest;

  const DigestEditorSaved(this.digest);
}

/// The digest with [id] is to go — already confirmed inside the sheet.
final class DigestEditorDeleted extends DigestEditorResult {
  final String id;

  const DigestEditorDeleted(this.id);
}

/// The form for one digest (`docs/category-alerts-and-digests-roadmap.md`
/// §6.5): its name, what it lists, when it fires and what it covers, with
/// the next fire the draft would make read back under the rows.
///
/// Writes nothing: the caller — the Alerts hub, which owns no data either —
/// dispatches the result to `CalendarBloc`. A form sheet on
/// [FormSheetFrame]: leaving asks first once anything differs from what the
/// form opened with.
class DigestEditorSheet extends StatefulWidget {
  /// The digest to edit, or with an empty id the draft a new one starts
  /// from; null starts from the defaults.
  final EventDigest? initial;

  /// What the caption counts over — the calendar's events as the bloc holds
  /// them, handed in by the caller, which is under the calendar's load.
  final List<CalendarEvent> events;

  /// The app's week start: the On menu's weekday order and whether a weekly
  /// span is "this week" — the calendar never reads the locale's first day.
  final CalendarWeekStart weekStart;

  /// The clock the caption is planned from — a seam, so a test can name the
  /// fire it expects instead of reading the wall clock it races.
  final DateTime Function() now;

  const DigestEditorSheet({
    super.key,
    this.initial,
    this.events = const [],
    this.weekStart = CalendarWeekStart.monday,
    this.now = DateTime.now,
  });

  static Future<DigestEditorResult?> show(
    BuildContext context, {
    EventDigest? initial,
    List<CalendarEvent> events = const [],
    CalendarWeekStart weekStart = CalendarWeekStart.monday,
    DateTime Function() now = DateTime.now,
  }) {
    return showModalBottomSheet<DigestEditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      // The frame owns the drag (the route's own would pop past the guard)
      // and paints the ground and the radius itself.
      enableDrag: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      // The On row comes and goes on the Shows and Every menus' answers.
      builder: (_) => FormSheetSemanticsRefresh(
        child: FractionallySizedBox(
          heightFactor: FormMetrics.sheetHeightFactor,
          child: DigestEditorSheet(
            initial: initial,
            events: events,
            weekStart: weekStart,
            now: now,
          ),
        ),
      ),
    );
  }

  @override
  State<DigestEditorSheet> createState() => _DigestEditorSheetState();
}

/// What the Shows row offers. Not stored: it is read from the cadence, whose
/// two report values are what a report digest saves.
enum _DigestShows {
  upcoming('upcoming'),
  weekReport('week-report'),
  monthReport('month-report');

  const _DigestShows(this.slug);

  /// The item's id suffix.
  final String slug;

  static _DigestShows of(DigestCadence cadence) => switch (cadence) {
    DigestCadence.weeklyReport => weekReport,
    DigestCadence.monthlyReport => monthReport,
    DigestCadence.daily ||
    DigestCadence.weekly ||
    DigestCadence.monthly => upcoming,
  };
}

class _DigestEditorSheetState extends State<DigestEditorSheet> {
  /// The template form's name limits: a name is a label, never a sentence.
  static const int _nameMaxLength = 60;
  static const int _nameCounterFrom = 50;

  /// How many fires the caption looks through for one that sends something
  /// — a year of a monthly digest's.
  static const int _captionLookahead = 12;

  /// A count wider than any span holds, for the caption's height template.
  static const int _widestCount = 8888;

  /// The caption's height templates per locale, text scale and clock: the
  /// year's widest dates and times are measured once, not per sheet.
  static final Map<String, List<String>> _candidateCache = {};

  late final TextEditingController _nameController;
  final FormHeaderHairline _hairline = FormHeaderHairline();

  late Set<String> _categoryIds;
  late DigestCadence _cadence;

  /// The upcoming cadence Upcoming restores after a report Shows: what the
  /// draft last had, weekly for a digest opened as a report.
  late DigestCadence _upcomingCadence;

  /// Both anchors are held, so Week → Day → Week finds Monday again.
  late int _weekday;

  /// The week report's weekday, held apart from [_weekday] (D45): entered
  /// from an upcoming cadence it is the week's first day — a Sunday kept
  /// from an upcoming weekly digest would report the week that ended seven
  /// days before it — and a week report opened for an edit keeps its own.
  late int _reportWeekday;
  late int _dayOfMonth;
  late int _minute;
  late int _leadDays;
  late bool _includeEmpty;

  late final EventDigest _initialDraft;

  /// The one clock read the caption is planned from: at open, and again
  /// after each change, so a sheet left open past a fire never names it.
  late DateTime _now;

  /// The draft's next fire that sends something, or null when none of the
  /// next [_captionLookahead] would. Planned at open and after each change,
  /// never in `build`: the sheet rebuilds on every keyboard frame.
  PlannedDigest? _next;

  /// The caption's words for [_next], memoized on what they are written
  /// from.
  String? _captionText;
  Object? _captionKey;

  bool _leaving = false;

  /// Held while a picker is up, so a second tap during its opening
  /// animation cannot stack a second one.
  bool _pickerOpen = false;

  /// A digest without an id is a new one pre-filled by its caller — the
  /// report's Send row — and saves, and meets the cap, as a new one does.
  bool get _isEditing => widget.initial?.id.isNotEmpty ?? false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial ?? const EventDigest(id: '');
    _nameController = TextEditingController(text: initial.name);
    _categoryIds = initial.categoryIds;
    _cadence = initial.cadence;
    _upcomingCadence = initial.cadence.isReport
        ? DigestCadence.weekly
        : initial.cadence;
    _weekday = switch (initial.cadence) {
      DigestCadence.weekly || DigestCadence.weeklyReport =>
        EventDigest.clampAnchor(initial.cadence, initial.anchor),
      _ => DateTime.monday,
    };
    _reportWeekday = initial.cadence == DigestCadence.weeklyReport
        ? _weekday
        : firstWeekdayOf(widget.weekStart);
    _dayOfMonth = switch (initial.cadence) {
      DigestCadence.monthly || DigestCadence.monthlyReport =>
        EventDigest.clampAnchor(initial.cadence, initial.anchor),
      _ => 1,
    };
    _minute = initial.minute;
    _leadDays = initial.leadDays;
    _includeEmpty = initial.includeEmpty;
    _now = widget.now();
    _initialDraft = _buildDraft();
    _next = _plan();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hairline.dispose();
    super.dispose();
  }

  int get _anchor => switch (_cadence) {
    DigestCadence.daily => 0,
    DigestCadence.weekly => _weekday,
    DigestCadence.weeklyReport => _reportWeekday,
    DigestCadence.monthly || DigestCadence.monthlyReport => _dayOfMonth,
  };

  /// Everything the form edits, as the digest it would save; the identity —
  /// id, switch, position — passes through as the form opened with it.
  EventDigest _buildDraft() {
    final initial = widget.initial;
    return EventDigest(
      id: initial?.id ?? '',
      name: _nameController.text.trim(),
      cadence: _cadence,
      anchor: _anchor,
      minute: _minute,
      leadDays: _leadDays,
      categoryIds: _categoryIds,
      includeEmpty: _includeEmpty,
      enabled: initial?.enabled ?? true,
      sortOrder: initial?.sortOrder ?? 0,
    );
  }

  /// The form's fingerprint: [EventDigest] compares by every field.
  bool get _isDirty => _buildDraft() != _initialDraft;

  /// Every change to the draft goes through here, so the caption is planned
  /// from a fresh clock read and never from the one the sheet opened with.
  void _update(VoidCallback change) {
    setState(() {
      change();
      _now = widget.now();
      _next = _plan();
    });
  }

  /// The draft planned as the scheduler plans a digest — the allowlist and
  /// Also when empty applied by the planner itself, so the caption and the
  /// hub's rows agree — switched on, since an edit of a paused digest still
  /// asks what it would send.
  PlannedDigest? _plan() {
    final plan = DigestPlanner.plan(
      digests: [_buildDraft().copyWith(enabled: true)],
      events: widget.events,
      horizon: const DigestHorizon(perDigest: _captionLookahead, maxDigests: 1),
      now: _now,
      weekStart: widget.weekStart,
    );
    return plan.isEmpty ? null : plan.first;
  }

  // --- Leaving and saving -------------------------------------------------

  /// Serves ✕, back, the system back gesture, the barrier and a dismissing
  /// drag.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      final leave = !_isDirty || await AppDialogs.confirmDiscard(context);
      if (!leave || !mounted) return;
      Navigator.of(context).pop();
    } finally {
      _leaving = false;
    }
  }

  /// Never through the guard: saving is the one exit that keeps what was
  /// entered. An edit that changed nothing hands back `null`, so no write
  /// bumps the digest's version for nothing. A new digest past the cap is
  /// refused here, in the overlay — the twin of the saved views' rule — and
  /// the form stays.
  void _onSave() {
    if (_isEditing) {
      Navigator.of(
        context,
      ).pop(_isDirty ? DigestEditorSaved(_buildDraft()) : null);
      return;
    }
    if (EventDigests.all.length >= kDigestHorizon.maxDigests) {
      OverlaySnackbar.show(
        context,
        AppLocalizations.of(
          context,
        )!.digestLimitReached(kDigestHorizon.maxDigests),
        duration: AppConstants.snackbarDuration,
      );
      return;
    }
    Navigator.of(context).pop(DigestEditorSaved(_buildDraft()));
  }

  Future<void> _delete() async {
    final id = widget.initial?.id;
    if (id == null) return;
    _blur();
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await AppDialogs.confirm(
      context,
      title: l10n.digestDelete,
      content: l10n.digestDeleteConfirm,
      confirmText: l10n.delete,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop(DigestEditorDeleted(id));
  }

  // --- Pickers ------------------------------------------------------------

  /// Before every picker: a name field left focused takes the focus back when
  /// the picker closes, and the keyboard comes up over a form the user had
  /// finished typing in.
  void _blur() => FocusManager.instance.primaryFocus?.unfocus();

  /// The multi picker over the allowlist, the overview's inversion: an empty
  /// allowlist means every category, so it opens with every offered row
  /// ticked, and a result that ticks every offered row — or none — is every
  /// category again rather than today's catalog frozen into a list.
  Future<void> _pickCategories() async {
    if (_pickerOpen) return;
    _pickerOpen = true;
    _blur();
    try {
      final offered = {
        for (final category in CalendarCategories.visiblePlus(_categoryIds))
          category.id,
      };
      final picked = await CategoryPickerSheet.pickMulti(
        context,
        selected: _categoryIds.isEmpty ? offered : _categoryIds,
      );
      if (picked == null || !mounted) return;
      final next = picked.containsAll(offered)
          ? const <String>{}
          : Set<String>.unmodifiable(picked);
      if (setEquals(next, _categoryIds)) return;
      _update(() => _categoryIds = next);
    } finally {
      _pickerOpen = false;
    }
  }

  Future<void> _pickTime() async {
    if (_pickerOpen) return;
    _pickerOpen = true;
    _blur();
    try {
      final picked = await TimePadSheet.pick(
        context,
        initialMinute: _minute,
        title: AppLocalizations.of(context)!.digestAt,
      );
      if (picked == null || !mounted) return;
      _update(() => _minute = picked);
    } finally {
      _pickerOpen = false;
    }
  }

  // --- Words --------------------------------------------------------------

  String _categoryLabel(String id, AppLocalizations l10n) =>
      CalendarCategories.labelOf(CalendarCategories.resolve(id), l10n);

  String _cadenceLabel(DigestCadence cadence, AppLocalizations l10n) =>
      switch (cadence) {
        DigestCadence.daily => l10n.panelModeDay,
        DigestCadence.weekly ||
        DigestCadence.weeklyReport => l10n.calendarFormatWeek,
        DigestCadence.monthly ||
        DigestCadence.monthlyReport => l10n.calendarFormatMonth,
      };

  /// A weekday as a menu value: the name `intl` writes, sentence-cased the
  /// way the appearance page's week start reads.
  String _weekdayLabel(int weekday, String localeName) {
    final name = digestWeekdayName(weekday, localeName);
    return toBeginningOfSentenceCase(name, localeName) ?? name;
  }

  String _showsLabel(_DigestShows shows, AppLocalizations l10n) =>
      switch (shows) {
        _DigestShows.upcoming => l10n.digestShowsUpcoming,
        _DigestShows.weekReport => l10n.digestShowsWeekReport,
        _DigestShows.monthReport => l10n.digestShowsMonthReport,
      };

  String _leadLabel(int lead, AppLocalizations l10n) =>
      lead == 0 ? l10n.digestCoversSameDay : l10n.digestCoversNextDay;

  /// The week in the app's order, from its first day.
  List<int> get _weekdaysInOrder {
    final first = firstWeekdayOf(widget.weekStart);
    return [
      for (var i = 0; i < DateTime.daysPerWeek; i++)
        (first - 1 + i) % DateTime.daysPerWeek + 1,
    ];
  }

  /// "Next: Sat, Nov 1 09:00 · 3 events this month" for [_next], in the
  /// notification's own words; "Nothing to send yet" when no fire ahead
  /// would send anything. Written again only when [_next], the language or
  /// the clock style moved.
  String _caption(AppLocalizations l10n) {
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final next = _next;
    final key = (next, l10n.localeName, use24Hour);
    final cached = _captionText;
    if (cached != null && key == _captionKey) return cached;
    final String text;
    if (next == null) {
      text = l10n.digestNextNone;
    } else {
      final period = digestPeriodOf(
        next.digest,
        spanStart: next.spanStart,
        spanEnd: next.spanEnd,
        strings: l10n,
        labels: AlertLabels(strings: l10n, use24Hour: use24Hour),
        weekStart: widget.weekStart,
      );
      text = l10n.digestNext(
        '${DateFormat.MMMEd(l10n.localeName).format(next.fireAt)} '
        '${EventTimeFormatter.formatMinute(next.digest.minute, context)}',
        l10n.digestCountPeriod(next.entries.length, period),
      );
    }
    _captionKey = key;
    return _captionText = text;
  }

  /// The caption's height templates, independent of the draft: the line
  /// under every calendar-unit phrase and under a span between the year's
  /// two widest dates, each with the widest day and time the language
  /// writes, at the text scale in use — so no pick ever changes the slot.
  List<String> _captionCandidates(AppLocalizations l10n) {
    final scaler = MediaQuery.textScalerOf(context);
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final key =
        '${l10n.localeName}|${scaler.scale(FormMetrics.captionSize)}|'
        '$use24Hour';
    return _candidateCache[key] ??= _measureCandidates(l10n, scaler, use24Hour);
  }

  static List<String> _measureCandidates(
    AppLocalizations l10n,
    TextScaler scaler,
    bool use24Hour,
  ) {
    final localeName = l10n.localeName;
    final style = const TextStyle(fontSize: FormMetrics.captionSize);
    double widthOf(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    List<String> byWidth(Iterable<String> texts) {
      final measured = [
        for (final text in texts.toSet()) (text: text, width: widthOf(text)),
      ]..sort((a, b) => b.width.compareTo(a.width));
      return [for (final entry in measured) entry.text];
    }

    final labels = AlertLabels(strings: l10n, use24Hour: use24Hour);
    final year = DateTime.now().year;
    final days = [
      for (
        var day = DateTime.utc(year, 1, 1);
        day.year == year;
        day = DateTime.utc(day.year, day.month, day.day + 1)
      )
        day,
    ];
    final dates = byWidth(days.map(labels.entryDateLabel));
    final dayFormat = DateFormat.MMMEd(localeName);
    final widestDay = byWidth(days.map(dayFormat.format)).first;
    String clock(int minute) => EventTimeFormatter.formatMinuteFor(
      minute,
      localeName: localeName,
      use24Hour: use24Hour,
    );
    final widestHour = byWidth([
      for (var hour = 0; hour < 24; hour++) clock(hour * 60 + 58),
    ]).first;
    final hour = [
      for (var h = 0; h < 24; h++) h,
    ].firstWhere((h) => clock(h * 60 + 58) == widestHour);
    final widestTime = byWidth([
      for (var minute = 0; minute < 60; minute++) clock(hour * 60 + minute),
    ]).first;
    final when = '$widestDay $widestTime';
    return [
      l10n.digestNextNone,
      for (final phrase in [
        l10n.digestPeriodToday,
        l10n.digestPeriodTomorrow,
        l10n.digestPeriodThisWeek,
        l10n.digestPeriodNextWeek,
        l10n.digestPeriodThisMonth,
        l10n.digestPeriodNextMonth,
        l10n.digestPeriodLastWeek,
        l10n.digestPeriodLastMonth,
        l10n.digestPeriodSpan(dates.first, dates[1]),
      ])
        l10n.digestNext(when, l10n.digestCountPeriod(_widestCount, phrase)),
    ];
  }

  // --- Rows ---------------------------------------------------------------

  /// A report Shows *is* the cadence it saves; Upcoming takes back the
  /// upcoming cadence the draft last had.
  void _pickShows(_DigestShows shows) {
    if (shows == _DigestShows.of(_cadence)) return;
    _update(
      () => _cadence = switch (shows) {
        _DigestShows.upcoming => _upcomingCadence,
        _DigestShows.weekReport => DigestCadence.weeklyReport,
        _DigestShows.monthReport => DigestCadence.monthlyReport,
      },
    );
  }

  List<Widget> _buildRows(AppLocalizations l10n) {
    final localeName = l10n.localeName;
    final shows = _DigestShows.of(_cadence);
    // A report's schedule is implied by what it shows, and its span is the
    // period that ended, so Every and Covers dim where they stand.
    final isReport = _cadence.isReport;
    return [
      FormPickerRow(
        glyph: Icons.category_rounded,
        identifier: SemanticsIds.digestCategories,
        label: l10n.calendarCategories,
        value: digestCategoriesLabel(
          _categoryIds,
          l10n,
          categoryLabel: (id) => _categoryLabel(id, l10n),
        ),
        onTap: _pickCategories,
      ),
      FormMenuRow<_DigestShows>(
        glyph: Icons.summarize_outlined,
        identifier: SemanticsIds.digestShows,
        label: l10n.digestShows,
        value: _showsLabel(shows, l10n),
        selected: shows,
        menuWidth: FormMetrics.menuWidth,
        items: [
          for (final item in _DigestShows.values)
            FormMenuItem(
              value: item,
              label: _showsLabel(item, l10n),
              identifier: SemanticsIds.digestShowsItem(item.slug),
            ),
        ],
        onSelected: _pickShows,
      ),
      FormMenuRow<DigestCadence>(
        glyph: Icons.repeat_rounded,
        identifier: SemanticsIds.digestCadence,
        label: l10n.digestEvery,
        value: _cadenceLabel(_cadence, l10n),
        selected: _cadence,
        menuWidth: FormMetrics.menuWidth,
        items: [
          for (final cadence in DigestCadence.values)
            if (!cadence.isReport)
              FormMenuItem(
                value: cadence,
                label: _cadenceLabel(cadence, l10n),
                identifier: SemanticsIds.digestCadenceItem(cadence.name),
              ),
        ],
        onSelected: isReport
            ? null
            : (cadence) => _update(() {
                _cadence = cadence;
                _upcomingCadence = cadence;
              }),
      ),
      // A daily digest fires every day: there is no day to pick, so the row
      // goes rather than dims. It goes on the Every menu's answer, never under
      // the finger.
      if (_cadence == DigestCadence.weekly ||
          _cadence == DigestCadence.weeklyReport)
        FormMenuRow<int>(
          glyph: Icons.calendar_month_outlined,
          identifier: SemanticsIds.digestAnchor,
          label: l10n.digestOn,
          value: _weekdayLabel(_anchor, localeName),
          selected: _anchor,
          menuWidth: FormMetrics.menuWidth,
          items: [
            for (final weekday in _weekdaysInOrder)
              FormMenuItem(
                value: weekday,
                label: _weekdayLabel(weekday, localeName),
                identifier: SemanticsIds.digestAnchorItem(weekday),
              ),
          ],
          onSelected: (weekday) => _update(() {
            if (_cadence.isReport) {
              _reportWeekday = weekday;
            } else {
              _weekday = weekday;
            }
          }),
        )
      else if (_cadence == DigestCadence.monthly ||
          _cadence == DigestCadence.monthlyReport)
        FormMenuRow<int>(
          glyph: Icons.calendar_month_outlined,
          identifier: SemanticsIds.digestAnchor,
          label: l10n.digestOn,
          value: digestDayOfMonth(_dayOfMonth, l10n),
          selected: _dayOfMonth,
          menuWidth: FormMetrics.menuWidth,
          items: [
            for (var day = 1; day <= EventDigest.lastMonthAnchor; day++)
              FormMenuItem(
                value: day,
                label: digestDayOfMonth(day, l10n),
                identifier: SemanticsIds.digestAnchorItem(day),
              ),
          ],
          onSelected: (day) => _update(() => _dayOfMonth = day),
        ),
      FormPickerRow(
        glyph: Icons.schedule_outlined,
        identifier: SemanticsIds.digestTime,
        label: l10n.digestAt,
        value: EventTimeFormatter.formatMinute(_minute, context),
        onTap: _pickTime,
      ),
      FormMenuRow<int>(
        glyph: Icons.start_rounded,
        identifier: SemanticsIds.digestLead,
        label: l10n.digestCovers,
        value: _leadLabel(_leadDays, l10n),
        selected: _leadDays,
        menuWidth: FormMetrics.menuWidth,
        items: [
          for (final lead in const [0, 1])
            FormMenuItem(
              value: lead,
              label: _leadLabel(lead, l10n),
              identifier: SemanticsIds.digestLeadItem(lead),
            ),
        ],
        onSelected: isReport ? null : (lead) => _update(() => _leadDays = lead),
      ),
      FormSwitchRow(
        glyph: Icons.inbox_outlined,
        identifier: SemanticsIds.digestIncludeEmpty,
        label: l10n.digestIncludeEmpty,
        subtitle: l10n.digestIncludeEmptyDesc,
        value: _includeEmpty,
        onChanged: (value) => _update(() => _includeEmpty = value),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view, never the whole body (`sheet_bottom_clearance_test.dart`).
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    return FormSheetFrame(
      onLeave: _leave,
      isClean: () => !_isDirty,
      onDismiss: () => Navigator.of(context).pop(),
      chrome: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormSheetHandle(),
          FormSheetHeader(
            leadingIcon: Icons.close_rounded,
            leadingTooltip: l10n.cancel,
            leadingIdentifier: SemanticsIds.digestSheetClose,
            onLeading: _leave,
            title: _isEditing ? l10n.digestEdit : l10n.digestNew,
            scrolled: _hairline.scrolled,
            trailingInset: FormMetrics.headerActionInset,
            trailing: FormHeaderTextButton(
              label: l10n.save,
              identifier: SemanticsIds.digestSheetSave,
              onPressed: _onSave,
            ),
          ),
        ],
      ),
      body: [
        Expanded(
          child: _hairline.watch(
            child: Semantics(
              identifier: SemanticsIds.digestSheetBody,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  RowMetrics.groupInset,
                  FormMetrics.bodyTop,
                  RowMetrics.groupInset,
                  FormMetrics.bodyBottom + clearance,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FormRowGroup(
                      children: [
                        FormTitleRow(
                          // A field's glyph, not an avatar: the kit keeps the
                          // title row's avatar for previewing an event.
                          leading: const FormGlyph(
                            icon: Icons.drive_file_rename_outline_rounded,
                          ),
                          controller: _nameController,
                          // The title the digest takes while it has no name.
                          hint: digestCategoriesLabel(
                            _categoryIds,
                            l10n,
                            categoryLabel: (id) => _categoryLabel(id, l10n),
                          ),
                          maxLength: _nameMaxLength,
                          counterFrom: _nameCounterFrom,
                          counterLabel: l10n.eventTitleCount,
                          textCapitalization: TextCapitalization.sentences,
                          identifier: SemanticsIds.digestName,
                        ),
                      ],
                    ),
                    FormRowGroup(
                      trailingGap: false,
                      children: _buildRows(l10n),
                    ),
                    FormCaptionSlot(
                      candidates: [
                        for (final text in _captionCandidates(l10n))
                          FormCaption(
                            text: text,
                            padding: FormMetrics.groupCaptionPadding,
                          ),
                      ],
                      child: FormCaption(
                        text: _caption(l10n),
                        padding: FormMetrics.groupCaptionPadding,
                      ),
                    ),
                    if (_isEditing) ...[
                      const SizedBox(height: RowMetrics.groupGap),
                      FormRowGroup(
                        trailingGap: false,
                        children: [
                          FormActionRow(
                            glyph: Icons.delete_outline_rounded,
                            label: l10n.digestDelete,
                            destructive: true,
                            identifier: SemanticsIds.digestDelete,
                            onTap: _delete,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
