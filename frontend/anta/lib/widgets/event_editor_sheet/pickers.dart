part of '../event_editor_sheet.dart';

/// The pickers and what they write: the date and the one-time set, the
/// cancelled days, the presence default, the times, the repeat and the
/// look — and the values their rows show.
mixin _EventEditorPickers on _EventEditorRules {
  /// Default duration the first time a user enables an end time on a new
  /// timed event (60 minutes — a typical session).
  static const int _defaultDurationMinutes = 60;
  static const Duration _revealDuration = Duration(milliseconds: 250);

  // --- Interactions -------------------------------------------------------

  Future<void> _pickDate() async {
    _blur();
    // The shared domain, not a window around the current date: a birthday's
    // start is the birth year, which a ±20-year slide could never reach.
    final picked = await CalendarDatePickerSheet.pickSingle(
      context,
      initialDate: _date,
      firstDate: CalendarBounds.earliest,
      lastDate: CalendarBounds.latest,
      dayLoad: widget.dayLoad,
      appearance: widget.appearance,
    );
    if (picked == null || !mounted) return;
    setState(() {
      final next = _normalize(picked);
      // Keep the weekday selection in sync when it was implicitly anchored
      // to the previous date (single weekday matching old _date.weekday).
      if (_kind == RepeatKind.weekly &&
          _weekdays.length == 1 &&
          _weekdays.first == _date.weekday) {
        _weekdays = {next.weekday};
      }
      _date = next;
      // A new primary date must never also live in the extra-dates list.
      _additionalDates = _additionalDates.where((d) => d != next).toList();
      // If the recurrence end is now before the new start, drop it rather
      // than silently producing an event that never occurs.
      if (_endDate != null && _endDate!.isBefore(next)) {
        _endDate = null;
      }
    });
  }

  /// The cancelled days currently in play: the draft once the picker has been
  /// opened, otherwise whatever is persisted.
  Set<DateTime> get _effectiveSkippedDays =>
      _skippedDays ??
      widget.initialSkippedDays ??
      EventSkips.daysFor(widget.initialEvent?.id ?? '');

  /// Reviews and edits the cancelled days as a set.
  ///
  /// `pickMulti` is exactly the right control here and needs no new UI: it is
  /// semantics-free, it already shows which days are busy, and un-skipping is
  /// just deselecting. Nothing is written until Save.
  Future<void> _pickSkippedDays() async {
    _blur();
    final picked = await CalendarDatePickerSheet.pickMulti(
      context,
      initialSelection: _effectiveSkippedDays,
      firstDate: CalendarBounds.earliest,
      lastDate: CalendarBounds.latest,
      dayLoad: widget.dayLoad,
      appearance: widget.appearance,
      allowEmpty: true,
    );
    if (picked == null || !mounted) return;
    setState(() => _skippedDays = {for (final d in picked) _normalize(d)});
  }

  /// Applies an Assume present / Assume absent pick, seeding the from-date the
  /// first time an existing event is flipped over.
  ///
  /// The seed is the day the editor was opened from — the occurrence whose
  /// detail sheet the user came through — falling back to today. It only fires
  /// for an event that was **saved** as assume-present: an event already on
  /// the inverted default keeps whatever boundary it has, including none, so
  /// toggling back and forth inside one session cannot invent one.
  ///
  /// Must run inside a `setState`; the caller owns that.
  void _selectAssumeAbsent(bool value) {
    _assumeAbsent = value;
    if (!value) return;
    if (_isEditing &&
        widget.initialEvent!.assumeAbsent == false &&
        _assumeAbsentFrom == null &&
        !_assumeAbsentFromTouched) {
      _assumeAbsentFrom = _normalize(widget.occurrenceDay ?? DateTime.now());
    }
  }

  /// Picks the day the inverted presence default starts from (**v37**).
  ///
  /// Single-date, [_pickEndDate]'s argument set, and the result goes through
  /// [_normalize] like every other date this form holds — the boundary is
  /// compared against date-only UTC days on every read path. Nothing is
  /// written until Save.
  Future<void> _pickAssumeAbsentFrom() async {
    _blur();
    final picked = await CalendarDatePickerSheet.pickSingle(
      context,
      initialDate: _assumeAbsentFrom ?? _date,
      firstDate: CalendarBounds.earliest,
      // A boundary past the last occurrence would leave "Assume absent"
      // selected with no day it could ever apply to.
      lastDate:
          (_mode == _RepeatMode.recurring ? _endDate : null) ??
          CalendarBounds.latest,
      dayLoad: widget.dayLoad,
      appearance: widget.appearance,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _assumeAbsentFrom = _normalize(picked);
      _assumeAbsentFromTouched = true;
    });
  }

  /// Edits the whole one-time date set in a single pass. The multi picker
  /// returns the edited set; [_setOneTimeDates] stays the one place that
  /// re-derives the anchor (earliest) and the extras list from it.
  Future<void> _pickOneTimeDates({
    CalendarDatePickerView view = CalendarDatePickerView.month,
  }) async {
    _blur();
    final current = <DateTime>{_date, ..._additionalDates};
    final picked = await CalendarDatePickerSheet.pickMulti(
      context,
      initialSelection: current,
      firstDate: CalendarBounds.earliest,
      lastDate: CalendarBounds.latest,
      dayLoad: widget.dayLoad,
      appearance: widget.appearance,
      initialView: view,
    );
    if (picked == null || !mounted || picked.isEmpty) return;
    _setOneTimeDates(picked);
  }

  void _removeOneTimeDate(DateTime date) {
    final next = <DateTime>{_date, ..._additionalDates}..remove(date);
    if (next.isEmpty) return;
    _setOneTimeDates(next);
  }

  /// Re-derives [_date] (earliest) and [_additionalDates] (the rest) from a
  /// full one-time date set so the chip list always reads as one uniform,
  /// sorted collection with the earliest auto-anchoring the event.
  void _setOneTimeDates(Set<DateTime> dates) {
    final sorted = dates.toList()..sort();
    setState(() {
      _date = sorted.first;
      _additionalDates = sorted.skip(1).toList();
      // [_pickDate]'s rule, for the row that moves the anchor as a set: an
      // Until left behind the new start is unused while the event is one-time
      // and would make it never occur the moment a repeat rule returns.
      if (_endDate != null && _endDate!.isBefore(_date)) _endDate = null;
      // Dropping back to a single date makes this a one-time event, which has
      // no occurrences to scope to.
      _syncScopeToRule();
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
    setState(() {
      final newStart = picked;
      // Preserve the visible duration: if a duration is set, keep the
      // *length* (so "1 hour" stays "1 hour"). This is what every native
      // calendar app does when you drag the start time.
      _startMinute = newStart;
    });
  }

  Future<void> _pickEndTime() async {
    _blur();
    // Initialize the picker on the current end time, or one hour after
    // start if no end is set yet.
    final currentEnd = _durationMinutes == null
        ? null
        : _startMinute + _durationMinutes!;
    final initial = currentEnd ?? (_startMinute + _defaultDurationMinutes);
    final clamped = initial % EventTime.minutesPerDay;
    final l10n = AppLocalizations.of(context)!;
    final picked = await TimePadSheet.pick(
      context,
      initialMinute: clamped,
      title: l10n.eventEndTime,
      periodAfter: _startMinute,
      caption: TimePadCaptions.afterStart(l10n, _startMinute),
    );
    if (picked == null || !mounted) return;
    final endMinute = picked;
    setState(() {
      // If user picks an end ≤ start, treat it as next-day (cross-midnight).
      // This is the only sane interpretation when the picker has no day
      // concept; the model and formatter both handle it.
      var duration = endMinute - _startMinute;
      if (duration <= 0) duration += EventTime.minutesPerDay;
      _durationMinutes = duration;
    });
  }

  void _clearEndTime() {
    setState(() => _durationMinutes = null);
  }

  void _setAllDay(bool value) {
    setState(() {
      _isAllDay = value;
      // Toggling on: keep _startMinute / _durationMinutes around so a
      // mistaken toggle is reversible. Toggling off: nothing to do — the
      // existing values become live again.
    });
  }

  int get _descriptionCounterFrom => (_descriptionLimit * 9 / 10).ceil();

  void _setPerOccurrenceDescriptions(bool value) {
    setState(() {
      _perOccurrenceDescriptions = value;
      if (!value) _syncScopeToRule();
    });
    if (!value || !_scopeControlVisible) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _descriptionKey.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: _revealDuration,
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickRepeat() async {
    _blur();
    final result = await EventRepeatSheet.show(
      context,
      draft: EventRepeatDraft(
        recurring: _mode == _RepeatMode.recurring,
        kind: _kind,
        interval: _interval,
        weekdays: _weekdays,
        endDate: _endDate,
        retroactive: _retroactive,
      ),
      startDate: _date,
      appearance: widget.appearance,
      dayLoad: widget.dayLoad,
    );
    if (result == null || !mounted) return;
    setState(() {
      _mode = result.recurring ? _RepeatMode.recurring : _RepeatMode.oneTime;
      _kind = result.kind;
      _interval = result.interval.clamp(1, EventRepeatDraft.maxInterval);
      _weekdays = Set<int>.of(result.weekdays);
      _endDate = result.endDate == null ? null : _normalize(result.endDate!);
      _retroactive = result.retroactive;
      // Same rule [_pickDate] applies, on the other row: the repeat sheet
      // floors only its own picker at the start date, so an Until the user
      // never touched comes back unchanged and can now precede a start the
      // Dates row has moved since — a rule whose end is before its start
      // occurs on no day at all.
      if (_endDate != null && _endDate!.isBefore(_date)) _endDate = null;
      // A recurring rule has no room for the one-time extras and the WHEN
      // group stops showing them, so keeping them would let a later "Does not
      // repeat" restore a date set no row has shown since the switch.
      if (_mode == _RepeatMode.recurring) _additionalDates = [];
      if (!_countStyleTouched) _countStyle = _defaultCountStyleFor(_kind);
      _syncScopeToRule();
    });
  }

  /// The bundled row's value: the count and span on the first line, then the
  /// next date and how many are still ahead, so the set reads back without
  /// opening the picker.
  String _datesValue(AppLocalizations l10n, List<DateTime> dates) =>
      CalendarDatePickerSheet.datesValue(l10n, dates, _today);

  String _repeatValue(AppLocalizations l10n) {
    if (_mode == _RepeatMode.oneTime) {
      return _additionalDates.isEmpty
          ? l10n.recurrenceDoesNotRepeat
          : l10n.recurrenceSpecificDates(_additionalDates.length + 1);
    }
    final rule = RecurrenceFormatter.format(
      _buildRule(),
      l10n,
      l10n.localeName,
      retroactive: _retroactive,
    );
    final end = _endDate;
    if (end == null) return rule;
    return l10n.recurrenceUntilSuffix(
      rule,
      DateFormat.yMMMd(l10n.localeName).format(end),
    );
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
      sandbox: widget.sandbox,
    );
    if (result == null || !mounted) return;
    setState(() {
      _iconKey = result.iconKey;
      _colorValue = result.colorValue;
      _tintIcon = result.tintIcon;
    });
  }

  String _dayRailLabel(AppLocalizations l10n, _DayRailChoice choice) {
    return switch (choice) {
      _DayRailChoice.auto => l10n.eventShowInDayRailAuto,
      _DayRailChoice.always => l10n.eventShowInDayRailAlways,
      _DayRailChoice.never => l10n.eventShowInDayRailNever,
    };
  }
}
