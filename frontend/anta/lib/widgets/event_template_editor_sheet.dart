import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/event_priorities.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/event_template.dart';
import '../models/recurrence_rule.dart';
import '../services/event_template_service.dart';
import '../services/event_time_formatter.dart';
import '../services/recurrence_formatter.dart';
import '../services/settings_service.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/markdown_plain_text.dart';
import 'app_dialogs.dart';
import 'automation_id.dart';
import 'category_picker_sheet.dart';
import 'event_avatar.dart';
import 'event_description_sheet.dart';
import 'event_look_sheet.dart';
import 'event_repeat_sheet.dart';
import 'form_rows.dart';
import 'overlay_snackbar.dart';
import 'time_pad_sheet.dart';
import 'value_change_highlight.dart';

/// Bottom-sheet form for creating or editing an [EventTemplate].
///
/// The event editor's twin (`docs/calendar-language-tier-2-roadmap.md`, D1):
/// its groups, its rows and its sub-sheets, in its order, minus what a
/// template cannot hold — a date, alerts, a linked note, skipped days. A
/// template is configured the way the event it stamps would be, and what the
/// editor would refuse cannot be stored from here either.
///
/// Persists through [EventTemplateService] and returns the saved template, or
/// `null` when the form was left. A form sheet on [FormSheetFrame]: leaving
/// asks first once anything differs from what the form opened with, and is
/// refused while the save is in flight.
class EventTemplateEditorSheet extends StatefulWidget {
  final EventTemplate? initial;

  /// Pre-filled draft for "save as template", where every field is already
  /// decided by the event form the user just built. Ignored when [initial] is
  /// set — editing an existing template starts from that template.
  final EventTemplate? draft;

  const EventTemplateEditorSheet({super.key, this.initial, this.draft});

  static Future<EventTemplate?> show(
    BuildContext context, {
    EventTemplate? initial,
    EventTemplate? draft,
  }) {
    return showModalBottomSheet<EventTemplate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      // The frame owns the drag (the route's own would pop past the guard)
      // and paints the ground and the radius itself.
      enableDrag: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (_) => FractionallySizedBox(
        heightFactor: FormMetrics.sheetHeightFactor,
        child: EventTemplateEditorSheet(initial: initial, draft: draft),
      ),
    );
  }

  @override
  State<EventTemplateEditorSheet> createState() =>
      _EventTemplateEditorSheetState();
}

class _EventTemplateEditorSheetState extends State<EventTemplateEditorSheet> {
  static const int _defaultStartMinute = 9 * 60;
  static const int _defaultDurationMinutes = 60;

  /// The name's limit and the length its counter shows from. Half an event
  /// title's, so Save as template can hand over a longer one: that name is
  /// kept as it came, and only typing stops at the limit.
  static const int _nameMaxLength = 60;
  static const int _nameCounterFrom = 50;

  late final TextEditingController _nameController;
  final FormHeaderHairline _hairline = FormHeaderHairline();

  late String _categoryId;

  /// The rule the form opened with, as a template can carry it (see
  /// [_templateRuleOf]). Saved back as this very object while
  /// [_ruleTouched] is false, so a rule the Repeat sheet cannot produce —
  /// an interval above its 99, a weekly rule with no weekday — survives an
  /// edit that never changed the repeat.
  late final RecurrenceRule _arrivedRule;

  /// The repeat as the Repeat sheet edits it: seeded from [_arrivedRule],
  /// replaced by whatever that sheet confirms. It also parks the weekdays,
  /// the interval and the before-start flag while the rule is one-time.
  late EventRepeatDraft _repeat;

  /// Whether the Repeat sheet has confirmed a repeat that differs from the
  /// one it was opened with. A Done on a sheet nobody changed is not a
  /// change: it must not swap [_arrivedRule] for a rebuilt one.
  bool _ruleTouched = false;

  /// The time is parked while [_allDay] is on, so a mistaken toggle is
  /// reversible.
  late bool _allDay;
  late int _startMinute;
  int? _durationMinutes;

  String? _iconKey;
  int? _colorValue;
  late bool _tintIcon;
  late int _priority;

  /// The repeat-only flags. Parked, not cleared, while the rule is one-time:
  /// [_buildTemplate] stores none of them for a rule that cannot carry them,
  /// and they come back if the rule repeats again before Save.
  late bool _tracksPresence;
  late bool _assumeAbsent;
  late bool _perOccurrenceDescriptions;
  late bool _countOccurrences;

  /// The count style the template came with, or the one picked here. What
  /// the chips show and what is stored is [_shownCountStyle].
  late OccurrenceCountStyle _countStyle;

  /// Whether [_countStyle] is a choice — picked here, or stored on a
  /// template that was counting. Until it is, the style follows the kind.
  late bool _countStyleTouched;

  late String _description;

  /// [_description] as the row reads it back; see [_previewOf].
  late String _descriptionPreview;

  /// The length the description had when the form opened. A longer text than
  /// the limit allows stays editable and saveable at that length, so lowering
  /// the setting blocks growth instead of locking a template out of its own
  /// form.
  late final int _initialDescriptionLength;

  /// The two settings below resolve after the first frame, like the event
  /// editor's; until then the defaults stand.
  int _descriptionLimit = SettingsKeys.defaultEventDescriptionLimit;
  MarkdownColorPalette _colorPalette = MarkdownColorPalette.presets;

  bool _saving = false;
  bool _leaving = false;

  /// What Save would have written when the form opened — all that leaving
  /// has to protect. Dirty means "Save would write something else now", not
  /// "something on the form was touched": a repeat changed and changed back
  /// or a name retyped as it was is nothing to ask about, while a stored
  /// Workdays count that a rule changed and restored would drop is.
  late final EventTemplate _initialTemplate;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final source = widget.initial ?? widget.draft;
    _nameController = TextEditingController(text: source?.name ?? '');
    _categoryId = source?.categoryId ?? kDefaultCategoryId;

    _arrivedRule = _templateRuleOf(source?.rule ?? const OneTimeRecurrence());
    _repeat = _repeatOf(
      _arrivedRule,
      retroactive: source?.retroactive ?? false,
    );

    final time = source?.time;
    _allDay = time == null;
    _startMinute = time?.startMinute ?? _defaultStartMinute;
    _durationMinutes = time?.durationMinutes;

    _iconKey = source?.iconKey;
    _colorValue = source?.colorValue;
    _tintIcon = source?.tintIcon ?? true;
    _priority = source?.priority ?? kDefaultEventPriority;
    _tracksPresence = source?.tracksPresence ?? false;
    _assumeAbsent = source?.assumeAbsent ?? false;
    _perOccurrenceDescriptions = source?.perOccurrenceDescriptions ?? false;
    _countOccurrences = source?.countOccurrences ?? false;
    _countStyle = source?.countStyle ?? OccurrenceCountStyle.numbered;
    // Only a template that was counting carries a style somebody chose;
    // otherwise the stored value is the column default.
    _countStyleTouched = _countOccurrences;

    _description = source?.description ?? '';
    _descriptionPreview = _previewOf(_description);
    _initialDescriptionLength = _description.length;

    _loadSheetSettings();
    // Last, so a form seeded from a draft opens clean.
    _initialTemplate = _buildTemplate();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hairline.dispose();
    super.dispose();
  }

  Future<void> _loadSheetSettings() async {
    final settings = await SettingsService.getInstance();
    final (palette, descriptionLimit) = await (
      settings.getColorPalette(),
      settings.getEventDescriptionLimit(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _colorPalette = palette;
      _descriptionLimit = descriptionLimit;
      // A colour run reads through the palette that resolves it.
      _descriptionPreview = _previewOf(_description);
    });
  }

  // --- The repeat ---------------------------------------------------------

  /// The rule a template can carry out of [rule]. Public holidays only has no
  /// knob a template could set and specific dates are dates, which a template
  /// has none of: both become one-time.
  static RecurrenceRule _templateRuleOf(RecurrenceRule rule) => switch (rule) {
    PublicHolidaysOnlyRecurrence() ||
    SpecificDatesRecurrence() => const OneTimeRecurrence(),
    _ => rule,
  };

  /// The draft the Repeat sheet opens on for [rule]. A rule that is not
  /// weekly carries no weekday: pre-selecting one is the event editor's
  /// doing, from its start date, and a template has no date to take it from.
  static EventRepeatDraft _repeatOf(
    RecurrenceRule rule, {
    required bool retroactive,
  }) {
    final (RepeatKind? kind, int interval) = switch (rule) {
      DailyRecurrence(:final interval) => (RepeatKind.daily, interval),
      WeeklyRecurrence(:final interval) => (RepeatKind.weekly, interval),
      MonthlyRecurrence(:final interval) => (RepeatKind.monthly, interval),
      YearlyRecurrence(:final interval) => (RepeatKind.yearly, interval),
      WorkdaysRecurrence() => (RepeatKind.workdays, 1),
      WeekendsRecurrence() => (RepeatKind.weekends, 1),
      OneTimeRecurrence() ||
      SpecificDatesRecurrence() ||
      PublicHolidaysOnlyRecurrence() => (null, 1),
    };
    return EventRepeatDraft(
      recurring: kind != null,
      kind: kind ?? RepeatKind.daily,
      interval: interval,
      weekdays: rule is WeeklyRecurrence
          ? Set<int>.unmodifiable(rule.weekdays)
          : const <int>{},
      retroactive: retroactive,
    );
  }

  static RecurrenceRule _ruleOf(EventRepeatDraft draft) {
    if (!draft.recurring) return const OneTimeRecurrence();
    return switch (draft.kind) {
      RepeatKind.daily => DailyRecurrence(interval: draft.interval),
      RepeatKind.weekly => WeeklyRecurrence(
        weekdays: Set<int>.unmodifiable(draft.weekdays),
        interval: draft.interval,
      ),
      RepeatKind.monthly => MonthlyRecurrence(interval: draft.interval),
      RepeatKind.yearly => YearlyRecurrence(interval: draft.interval),
      RepeatKind.workdays => const WorkdaysRecurrence(),
      RepeatKind.weekends => const WeekendsRecurrence(),
      // Never offered by the Repeat sheet's template variant; kept as the
      // collapse [_templateRuleOf] applies on the way in.
      RepeatKind.holidays => const OneTimeRecurrence(),
    };
  }

  RecurrenceRule get _rule => _ruleTouched ? _ruleOf(_repeat) : _arrivedRule;

  /// The repeat-only flags mean something only for a rule with more than one
  /// occurrence — the gate the event editor applies on save.
  bool get _repeats => _rule is! OneTimeRecurrence;

  /// Whether Count occurrences is on offer: only a kind with an interval has
  /// a unit to count in, the event editor's own gate.
  bool get _countOffered => _repeats && _repeat.kind.supportsInterval;

  /// What is stored for Count occurrences. A rule set in this form counts
  /// only where the switch is offered; a rule that arrived and was left alone
  /// keeps the flag it was stored with, offered or not, so opening an older
  /// Workdays template to rename it does not quietly stop its count.
  bool get _storesCount =>
      _repeats &&
      _countOccurrences &&
      (!_ruleTouched || _repeat.kind.supportsInterval);

  /// Yearly is **elapsed** — a yearly counted event is an anniversary, and
  /// someone born in 2000 turns 26 in 2026, not "Year 27". Shorter cadences
  /// number from 1, the training-program reading. The event editor's rule.
  static OccurrenceCountStyle _defaultCountStyleFor(RepeatKind kind) {
    return kind == RepeatKind.yearly
        ? OccurrenceCountStyle.elapsed
        : OccurrenceCountStyle.numbered;
  }

  /// The style in effect while the template counts: the kind's own until the
  /// user picks one. Derived rather than written into [_countStyle] on every
  /// change of kind, so a template that never counts keeps the style it was
  /// stored with and an untouched edit writes back what it read.
  OccurrenceCountStyle get _shownCountStyle =>
      _countStyleTouched ? _countStyle : _defaultCountStyleFor(_repeat.kind);

  // --- The description ----------------------------------------------------

  /// [text] as the description row shows it: the stripper's one line, every
  /// markdown marker dropped and the first meaningful line leading. Empty for
  /// a blank description, which is also what Save stores as none.
  ///
  /// Read without a ledger: money is off in a description, so a line that
  /// starts `$= 500` is that text here as it is in the sheet that edits it.
  String _previewOf(String text) => text.trim().isEmpty
      ? ''
      : MarkdownPlainText.strip(text, palette: _colorPalette, money: false);

  /// Over the limit is allowed only while the text is no longer than it
  /// already was — the description sheet's own rule, which is also why this
  /// can only fail for a text confirmed before the limit had loaded.
  bool get _descriptionWithinLimit =>
      _description.length <= _descriptionLimit ||
      _description.length <= _initialDescriptionLength;

  // --- Leaving and saving -------------------------------------------------

  bool get _canSave =>
      !_saving &&
      _nameController.text.trim().isNotEmpty &&
      _descriptionWithinLimit;

  bool get _isDirty => _buildTemplate() != _initialTemplate;

  /// Serves ✕, back, the system back gesture, the barrier and a dismissing
  /// drag. Ignored while the save is in flight: the write cannot be called
  /// back, and a form that closed under it reported nothing for a template it
  /// had just created.
  Future<void> _leave() async {
    if (_leaving || _saving) return;
    _leaving = true;
    try {
      final leave = !_isDirty || await AppDialogs.confirmDiscard(context);
      if (!leave || !mounted) return;
      Navigator.of(context).pop();
    } finally {
      _leaving = false;
    }
  }

  EventTemplate _buildTemplate() {
    final description = _description.trim();
    final repeats = _repeats;
    final storesCount = _storesCount;
    return EventTemplate(
      id: widget.initial?.id ?? '',
      name: _nameController.text.trim(),
      categoryId: _categoryId,
      rule: _rule,
      time: _allDay
          ? null
          : EventTime(
              startMinute: _startMinute,
              durationMinutes: _durationMinutes,
            ),
      description: description.isEmpty ? null : description,
      iconKey: _iconKey,
      colorValue: _colorValue,
      tintIcon: _tintIcon,
      priority: _priority,
      // Cleared rather than stored when the rule cannot carry them, so a
      // template never holds a flag its own rule contradicts.
      retroactive: repeats && _repeat.retroactive,
      countOccurrences: storesCount,
      countStyle: storesCount ? _shownCountStyle : _countStyle,
      tracksPresence: repeats && _tracksPresence,
      assumeAbsent: repeats && _tracksPresence && _assumeAbsent,
      perOccurrenceDescriptions: repeats && _perOccurrenceDescriptions,
      sortOrder: widget.initial?.sortOrder ?? 0,
    );
  }

  /// Persists and pops with the saved template. Never through the guard:
  /// saving is the one exit that keeps what was entered.
  ///
  /// The `try` is the point: `_saving` gates Save and every way out, so a
  /// throw escaping here would leave the form shut in for the life of the
  /// sheet with nothing said and the edit unsaved.
  Future<void> _onSave() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final service = await EventTemplateService.getInstance();
      final template = _buildTemplate();
      final EventTemplate saved;
      if (widget.initial == null) {
        saved = await service.create(template);
      } else {
        await service.updateTemplate(template);
        saved = template;
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      debugPrint('[EventTemplateEditorSheet] Save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      // In the overlay, not the page's `Scaffold`: this sheet is a route
      // above that page, and a bar raised there is drawn under the sheet.
      OverlaySnackbar.show(
        context,
        l10n.saveStatusError,
        duration: AppConstants.snackbarErrorDuration,
      );
    }
  }

  // --- Pickers ------------------------------------------------------------

  /// Before every picker: a name field left focused takes the focus back when
  /// the picker closes, and the keyboard comes up over a form the user had
  /// finished typing in.
  void _blur() => FocusManager.instance.primaryFocus?.unfocus();

  Future<void> _pickCategory() async {
    _blur();
    final picked = await CategoryPickerSheet.pickSingle(
      context,
      selectedId: _categoryId,
    );
    if (picked == null || !mounted) return;
    setState(() => _categoryId = picked);
  }

  Future<void> _pickLook() async {
    _blur();
    final result = await EventLookSheet.show(
      context,
      draft: EventLookDraft(
        iconKey: _iconKey,
        colorValue: _colorValue,
        tintIcon: _tintIcon,
      ),
      category: CalendarCategories.resolve(_categoryId),
    );
    if (result == null || !mounted) return;
    setState(() {
      _iconKey = result.iconKey;
      _colorValue = result.colorValue;
      _tintIcon = result.tintIcon;
    });
  }

  Future<void> _pickDescription() async {
    _blur();
    final initial = _description;
    final result = await EventDescriptionSheet.show(
      context,
      initialText: initial,
      heading: _nameController.text.trim(),
      limit: _descriptionLimit,
      grandfatheredLength: _initialDescriptionLength,
      colorPalette: _colorPalette,
    );
    if (result == null || !mounted || result == initial) return;
    setState(() {
      _description = result;
      _descriptionPreview = _previewOf(result);
    });
  }

  Future<void> _pickStartTime() async {
    _blur();
    final l10n = AppLocalizations.of(context)!;
    final duration = _durationMinutes;
    final picked = await TimePadSheet.pick(
      context,
      initialMinute: _startMinute,
      title: l10n.eventStartTime,
      caption: duration == null
          ? null
          : TimePadCaptions.endsAfter(l10n, duration),
    );
    if (picked == null || !mounted) return;
    // The duration stays: moving the start moves the end with it, as every
    // calendar does.
    setState(() => _startMinute = picked);
  }

  Future<void> _pickEndTime() async {
    _blur();
    final l10n = AppLocalizations.of(context)!;
    final end = _startMinute + (_durationMinutes ?? _defaultDurationMinutes);
    final picked = await TimePadSheet.pick(
      context,
      initialMinute: end % EventTime.minutesPerDay,
      title: l10n.eventEndTime,
      periodAfter: _startMinute,
      caption: TimePadCaptions.afterStart(l10n, _startMinute),
    );
    if (picked == null || !mounted) return;
    setState(() {
      // The pad has no day: an end at or before the start is the next day's.
      var duration = picked - _startMinute;
      if (duration <= 0) duration += EventTime.minutesPerDay;
      _durationMinutes = duration;
    });
  }

  Future<void> _pickRepeat() async {
    _blur();
    final opened = _repeat;
    final now = DateTime.now();
    final result = await EventRepeatSheet.show(
      context,
      draft: opened,
      // A template has no date. The variant shows this one nowhere; it only
      // has to be a day.
      startDate: DateTime.utc(now.year, now.month, now.day),
      // Read by the sheet's end-date picker alone, and the variant has no
      // Ends row to open it from.
      appearance: const CalendarAppearance(),
      forTemplate: true,
    );
    if (result == null || !mounted || result == opened) return;
    setState(() {
      _repeat = result;
      _ruleTouched = true;
    });
  }

  // --- Rows ---------------------------------------------------------------

  String _repeatValue(AppLocalizations l10n) {
    final rule = _rule;
    if (rule is OneTimeRecurrence) return l10n.recurrenceDoesNotRepeat;
    return RecurrenceFormatter.format(
      rule,
      l10n,
      l10n.localeName,
      retroactive: _repeat.retroactive,
    );
  }

  String _countStyleLabel(AppLocalizations l10n, OccurrenceCountStyle style) {
    return switch (style) {
      OccurrenceCountStyle.numbered => l10n.eventCountStyleNumbered,
      OccurrenceCountStyle.elapsed => l10n.eventCountStyleElapsed,
    };
  }

  static String _countStyleId(OccurrenceCountStyle style) => switch (style) {
    OccurrenceCountStyle.numbered => SemanticsIds.templateCountStyleNumbered,
    OccurrenceCountStyle.elapsed => SemanticsIds.templateCountStyleElapsed,
  };

  /// Labels for the first three occurrences under the kind and the style in
  /// effect, so the counting origin — the whole difference between the two
  /// styles — is read before saving rather than found on the calendar.
  String _countStyleExample(AppLocalizations l10n) {
    final style = _shownCountStyle;
    final kind = _repeat.kind;
    String at(int n) {
      return switch (style) {
        OccurrenceCountStyle.numbered => switch (kind) {
          RepeatKind.daily => l10n.eventNumberedDays(n),
          RepeatKind.weekly => l10n.eventNumberedWeeks(n),
          RepeatKind.monthly => l10n.eventNumberedMonths(n),
          RepeatKind.yearly => l10n.eventNumberedYears(n),
          _ => '',
        },
        OccurrenceCountStyle.elapsed => switch (kind) {
          RepeatKind.daily => l10n.eventElapsedDays(n),
          RepeatKind.weekly => l10n.eventElapsedWeeks(n),
          RepeatKind.monthly => l10n.eventElapsedMonths(n),
          RepeatKind.yearly => l10n.eventElapsedYears(n),
          _ => '',
        },
      };
    }

    final first = style == OccurrenceCountStyle.numbered ? 1 : 0;
    return '${at(first)} · ${at(first + 1)} · ${at(first + 2)}';
  }

  List<Widget> _buildCaptureRows(AppLocalizations l10n) {
    final category = CalendarCategories.resolve(_categoryId);
    final categoryColor = category.color;
    final colorValue = _colorValue;
    final eventColor = colorValue == null ? categoryColor : Color(colorValue);
    final icon =
        CalendarIcons.forKey(_iconKey) ??
        CalendarIcons.forKey(category.iconKey) ??
        Icons.event_rounded;
    return [
      FormTitleRow(
        // What the stamped event will wear: the colour reaches the icon only
        // while Tint is on.
        leading: EventAvatar(
          icon: icon,
          color: _tintIcon ? eventColor : categoryColor,
        ),
        controller: _nameController,
        hint: l10n.templateName,
        maxLength: _nameMaxLength,
        counterFrom: _nameCounterFrom,
        counterLabel: l10n.eventTitleCount,
        // Only a form opened blank: an edit and a draft arrive with a name.
        autofocus: !_isEditing && widget.draft == null,
        textCapitalization: TextCapitalization.sentences,
        identifier: SemanticsIds.templateName,
      ),
      FormPickerRow(
        glyph: Icons.label_outlined,
        identifier: SemanticsIds.templateCategory,
        label: l10n.eventCategory,
        value: CalendarCategories.labelOf(category, l10n),
        onTap: _pickCategory,
      ),
      FormPickerRow(
        glyph: Icons.palette_outlined,
        identifier: SemanticsIds.templateLook,
        label: l10n.eventAppearance,
        value: _iconKey != null || colorValue != null
            ? l10n.eventLookCustom
            : l10n.eventLookDefault,
        valueLeading: FormValueDot(color: eventColor),
        onTap: _pickLook,
      ),
      _DescriptionRow(
        name: l10n.eventDescription,
        placeholder: l10n.eventDescriptionAdd,
        preview: _descriptionPreview,
        onTap: _pickDescription,
      ),
    ];
  }

  Widget _buildEndsRow(AppLocalizations l10n) {
    final duration = _durationMinutes;
    if (duration == null) {
      return FormPickerRow(
        subRow: true,
        identifier: SemanticsIds.templateEnds,
        label: l10n.eventEnds,
        value: l10n.eventEndTimeNone,
        onTap: _pickEndTime,
      );
    }
    final end = _startMinute + duration;
    return FormPickerRow(
      subRow: true,
      identifier: SemanticsIds.templateEnds,
      // The editor's wording for an end on the next day, where a bare time
      // would read as earlier than the start.
      label: end >= EventTime.minutesPerDay
          ? l10n.eventCrossesMidnight
          : l10n.eventEnds,
      value:
          '${EventTimeFormatter.formatMinute(end, context)}'
          ' · '
          '${EventTimeFormatter.formatDuration(duration, l10n)}',
      onTap: _pickEndTime,
      trailingButton: FormTrailingButton(
        icon: Icons.close_rounded,
        tooltip: l10n.eventEndTimeRemove,
        identifier: SemanticsIds.templateEndsClear,
        onPressed: () => setState(() => _durationMinutes = null),
      ),
    );
  }

  List<Widget> _buildWhenRows(AppLocalizations l10n) {
    final duration = _durationMinutes;
    return [
      FormSwitchRow(
        glyph: Icons.schedule_outlined,
        identifier: SemanticsIds.templateAllDay,
        label: l10n.eventAllDay,
        value: _allDay,
        onChanged: (value) => setState(() => _allDay = value),
      ),
      if (!_allDay) ...[
        ValueChangeHighlight(
          value: _startMinute,
          child: FormPickerRow(
            subRow: true,
            identifier: SemanticsIds.templateStarts,
            label: l10n.eventStarts,
            value: EventTimeFormatter.formatMinute(_startMinute, context),
            onTap: _pickStartTime,
          ),
        ),
        ValueChangeHighlight(
          value: duration == null
              ? null
              : (_startMinute + duration) % EventTime.minutesPerDay,
          child: _buildEndsRow(l10n),
        ),
      ],
      FormPickerRow(
        glyph: Icons.repeat_rounded,
        identifier: SemanticsIds.templateRepeat,
        label: l10n.eventRepeat,
        value: _repeatValue(l10n),
        onTap: _pickRepeat,
      ),
    ];
  }

  List<Widget> _buildOccurrenceRows(AppLocalizations l10n) {
    return [
      if (_countOffered) ...[
        FormSwitchRow(
          glyph: Icons.numbers_rounded,
          identifier: SemanticsIds.templateCount,
          label: l10n.eventCountOccurrences,
          value: _countOccurrences,
          onChanged: (value) => setState(() => _countOccurrences = value),
        ),
        if (_countOccurrences)
          FormChipRow(
            chips: [
              for (final style in OccurrenceCountStyle.values)
                FormChip(
                  label: _countStyleLabel(l10n, style),
                  selected: _shownCountStyle == style,
                  identifier: _countStyleId(style),
                  onTap: () => setState(() {
                    _countStyle = style;
                    _countStyleTouched = true;
                  }),
                ),
            ],
            caption: FormCaption(text: _countStyleExample(l10n)),
          ),
      ],
      FormSwitchRow(
        glyph: Icons.how_to_reg_outlined,
        identifier: SemanticsIds.templatePresence,
        label: l10n.eventTrackPresence,
        value: _tracksPresence,
        onChanged: (value) => setState(() => _tracksPresence = value),
      ),
      // No from-date under the chips, unlike the event editor: a boundary is
      // a statement about one event's history, and a template has none.
      if (_tracksPresence)
        FormChipRow(
          chips: [
            FormChip(
              label: l10n.eventAssumePresent,
              selected: !_assumeAbsent,
              identifier: SemanticsIds.templateAssumePresent,
              onTap: () => setState(() => _assumeAbsent = false),
            ),
            FormChip(
              label: l10n.eventAssumeAbsent,
              selected: _assumeAbsent,
              identifier: SemanticsIds.templateAssumeAbsent,
              onTap: () => setState(() => _assumeAbsent = true),
            ),
          ],
        ),
      FormSwitchRow(
        glyph: Icons.event_note_outlined,
        identifier: SemanticsIds.templatePerDay,
        label: l10n.eventPerOccurrenceDescriptions,
        value: _perOccurrenceDescriptions,
        onChanged: (value) =>
            setState(() => _perOccurrenceDescriptions = value),
      ),
    ];
  }

  Widget _buildPriorityRow(AppLocalizations l10n) {
    return FormMenuRow<int>(
      glyph: Icons.flag_outlined,
      identifier: SemanticsIds.templatePriority,
      label: l10n.eventPriority,
      value: EventPriorities.labelOf(_priority, l10n),
      selected: _priority,
      menuWidth: FormMetrics.menuWidth,
      items: [
        for (var p = kMinEventPriority; p <= kMaxEventPriority; p++)
          FormMenuItem(
            value: p,
            label: EventPriorities.labelOf(p, l10n),
            icon: EventPriorities.iconFor(p),
            identifier: SemanticsIds.templatePriorityItem(p),
          ),
      ],
      onSelected: (priority) => setState(() => _priority = priority),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view, never the whole body: the sheet's box is a fixed share of
    // the screen and does not shrink for the keyboard, so padding the body
    // takes the inset out of the content and a tall keyboard leaves a blank
    // sheet that takes no touch (`sheet_bottom_clearance_test.dart`).
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    return FormSheetFrame(
      onLeave: _leave,
      // Never clean while the save is in flight: a fling then goes to
      // [_leave], which refuses it, instead of popping past the write.
      isClean: () => !_saving && !_isDirty,
      onDismiss: () => Navigator.of(context).pop(),
      chrome: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormSheetHandle(),
          FormSheetHeader(
            leadingIcon: Icons.close_rounded,
            leadingTooltip: l10n.cancel,
            leadingIdentifier: SemanticsIds.templateClose,
            onLeading: _leave,
            title: _isEditing ? l10n.editTemplate : l10n.createTemplate,
            scrolled: _hairline.scrolled,
            trailingInset: FormMetrics.headerActionInset,
            // The name is typed without a rebuild of the form; Save follows
            // its controller instead.
            trailing: ListenableBuilder(
              listenable: _nameController,
              builder: (context, _) => FormHeaderTextButton(
                label: l10n.save,
                identifier: SemanticsIds.templateSave,
                onPressed: _canSave ? _onSave : null,
              ),
            ),
          ),
        ],
      ),
      body: [
        Expanded(
          // Inert while the write is in flight: an edit made now could not
          // reach it, and a picker opened now would be the route the save
          // pops.
          child: AbsorbPointer(
            absorbing: _saving,
            child: _hairline.watch(
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
                    FormRowGroup(children: _buildCaptureRows(l10n)),
                    FormSectionLabel(text: l10n.eventSectionWhen),
                    FormRowGroup(children: _buildWhenRows(l10n)),
                    if (_repeats) ...[
                      FormSectionLabel(text: l10n.recurrenceScopeLabel),
                      FormRowGroup(children: _buildOccurrenceRows(l10n)),
                    ],
                    FormSectionLabel(text: l10n.eventSectionDetails),
                    FormRowGroup(
                      trailingGap: false,
                      children: [_buildPriorityRow(l10n)],
                    ),
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

/// The description as one row: the text is written in
/// [EventDescriptionSheet] and read back here, where the event editor has
/// its inline cell.
class _DescriptionRow extends FormDividedRow {
  /// The field's name, spoken before a description's text — the text alone
  /// does not say which row it is.
  final String name;

  /// What the row says while there is no description. A label, so it wraps
  /// whole where the description is clamped.
  final String placeholder;

  /// The description on one line with its markdown markers dropped, or empty
  /// when there is none.
  final String preview;
  final VoidCallback onTap;

  const _DescriptionRow({
    required this.name,
    required this.placeholder,
    required this.preview,
    required this.onTap,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentGlyph;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final empty = preview.isEmpty;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.only(
          left: RowMetrics.groupInset,
          right: FormMetrics.rowEndPadding,
        ),
        child: Row(
          children: [
            const FormGlyph(icon: Icons.notes_rounded),
            const SizedBox(width: FormMetrics.gap),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: FormMetrics.pairVerticalPadding,
                ),
                child: Text(
                  empty ? placeholder : preview,
                  // A description is read back like a value: clamped, where
                  // the placeholder is a label and wraps whole.
                  maxLines: empty ? null : FormMetrics.valueMaxLines,
                  overflow: empty ? null : TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: FormMetrics.labelSize,
                    height: FormMetrics.labelLineHeight / FormMetrics.labelSize,
                    // `onSurfaceVariant`, never `outline`: the latter is
                    // under AA for text on the group's ground.
                    color: empty
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(width: FormMetrics.gap),
            const FormChevron(),
          ],
        ),
      ),
    );
    return AutomationId(
      identifier: SemanticsIds.templateDescription,
      child: Semantics(
        button: true,
        label: empty ? placeholder : '$name, $preview',
        onTap: onTap,
        child: ExcludeSemantics(
          child: InkWell(onTap: onTap, child: row),
        ),
      ),
    );
  }
}
