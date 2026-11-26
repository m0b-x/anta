part of '../event_editor_sheet.dart';

/// The ways out: save, save as template, delete and leaving — with what a
/// save does to this day's own text, and the fingerprint that tells a
/// dirty form.
mixin _EventEditorSaving on _EventEditorPickers {
  /// Captures the current form as a reusable template.
  ///
  /// Opens the template editor pre-filled rather than saving silently: the
  /// template needs a name of its own (the event's title is only a default),
  /// and seeing the captured fields before they are stored is what makes the
  /// action trustworthy. The event form is left untouched and the sheet stays
  /// open — this is a side action, not a save.
  ///
  /// Persisting goes straight through `EventTemplateService`, the same
  /// service-direct pattern `CategoryPickerSheet`'s inline create already uses
  /// from inside this sheet, so no result-type plumbing is involved.
  Future<void> _onSaveAsTemplate() async {
    _blur();
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final description = _templateText.trim();
    // A template carries no dates, so a multi-date one-time event collapses
    // to a plain one-time rule; the same repeat-only guards as `_onSave`
    // otherwise apply, and the template editor re-applies them on its save.
    final rule = _mode == _RepeatMode.recurring
        ? _buildRule()
        : const OneTimeRecurrence();
    final draft = EventTemplate(
      id: '',
      name: title,
      categoryId: _categoryId,
      rule: rule,
      time: _isAllDay
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
      retroactive: _mode == _RepeatMode.recurring && _retroactive,
      countOccurrences:
          _mode == _RepeatMode.recurring &&
          _kind.supportsInterval &&
          _countOccurrences,
      countStyle: _countStyle,
      tracksPresence: _tracksPresence,
      assumeAbsent: _tracksPresence && _assumeAbsent,
      perOccurrenceDescriptions:
          _ruleHasManyOccurrences && _perOccurrenceDescriptions,
    );

    final saved = await EventTemplateEditorSheet.show(context, draft: draft);
    if (saved == null || !mounted) return;
    // In the overlay, not the page's `Scaffold`: this sheet is a route above
    // that page, and a bar raised there is drawn under the sheet.
    OverlaySnackbar.show(
      context,
      AppLocalizations.of(context)!.templateSaved,
      duration: AppConstants.snackbarSuccessDuration,
    );
  }

  void _onSave() {
    if (!_canSave) return;
    final title = _titleController.text.trim();
    // Always the template, whichever scope the field happens to be showing —
    // `description` on the event row is the shared text by definition.
    final description = _templateText.trim();
    final effectiveDescription = description.isEmpty ? null : description;
    final base = widget.initialEvent;
    // One-time events ignore endDate — their start date is their end.
    final effectiveEnd = _mode == _RepeatMode.recurring ? _endDate : null;
    // Same guard for the scope flag: an exact-membership rule can never be
    // retroactive, so a one-time event never carries a stale `true`.
    final effectiveRetroactive = _mode == _RepeatMode.recurring && _retroactive;
    // And for the occurrence count: only periodic kinds have a unit to count
    // in, so kind switches can never persist a stale `true`.
    final effectiveCountOccurrences =
        _mode == _RepeatMode.recurring &&
        _kind.supportsInterval &&
        _countOccurrences;
    // Presence is not one of them since decision B: a one-off keeps its mark,
    // so editing a series down to a single day keeps the opt-in it had.
    final effectiveTracksPresence = _tracksPresence;
    // The presence **default** rides the opt-in it qualifies: an untracked
    // event has no unmarked days to reinterpret, so it never persists an
    // inverted default. The from-date only means something while the default
    // is inverted, so it clears with it rather than lingering as a boundary
    // for nothing.
    final effectiveAssumeAbsent = effectiveTracksPresence && _assumeAbsent;
    final effectiveAssumeAbsentFrom = effectiveAssumeAbsent
        ? _assumeAbsentFrom
        : null;
    // The rail override follows the same gate, but resolves to NULL rather
    // than `false` when it closes: NULL is *auto*, so an event edited down to
    // one day and back again returns to following its presence flag instead of
    // carrying a "never" nobody chose.
    final effectiveShowInDayRail = _ruleHasManyOccurrences
        ? _showInDayRail
        : null;
    // Same shape for the per-day descriptions opt-in, and the same guarantee:
    // editing the event down to a single day clears the flag while the
    // occurrence rows survive, so re-ticking the switch brings every day's
    // text back.
    final effectivePerOccurrenceDescriptions =
        _ruleHasManyOccurrences && _perOccurrenceDescriptions;
    final effectiveTime = _isAllDay
        ? null
        : EventTime(
            startMinute: _startMinute,
            durationMinutes: _durationMinutes,
          );
    // A3 rides the same rule its switch is gated on, for the same reason the
    // flags above do: an event edited into a series, or left with nothing that
    // rings, must not keep a promise to delete itself.
    final savedRule = _buildRule();
    final effectiveRemoveAfterAlert =
        _removeAfterAlert && _hasAlarmAlert && savedRule is OneTimeRecurrence;
    // For a multi-date one-time event, anchor the start on the earliest date
    // so ordering / "starts on" reflect the real first occurrence.
    final effectiveStart =
        (_mode == _RepeatMode.oneTime && _additionalDates.isNotEmpty)
        ? <DateTime>{
            _date,
            ..._additionalDates,
          }.reduce((a, b) => a.isBefore(b) ? a : b)
        : _date;
    final event = base == null
        ? CalendarEvent(
            id: const Uuid().v4(),
            title: title,
            categoryId: _categoryId,
            startDate: effectiveStart,
            rule: savedRule,
            endDate: effectiveEnd,
            retroactive: effectiveRetroactive,
            countOccurrences: effectiveCountOccurrences,
            countStyle: _countStyle,
            tracksPresence: effectiveTracksPresence,
            assumeAbsent: effectiveAssumeAbsent,
            assumeAbsentFrom: effectiveAssumeAbsentFrom,
            showInDayRail: effectiveShowInDayRail,
            perOccurrenceDescriptions: effectivePerOccurrenceDescriptions,
            removeAfterAlert: effectiveRemoveAfterAlert,
            categoryAlerts: _categoryAlerts,
            time: effectiveTime,
            description: effectiveDescription,
            noteId: _noteId,
            iconKey: _iconKey,
            colorValue: _colorValue,
            tintIcon: _tintIcon,
            priority: _priority,
          )
        : base.copyWith(
            title: title,
            categoryId: _categoryId,
            startDate: effectiveStart,
            rule: savedRule,
            endDate: effectiveEnd,
            retroactive: effectiveRetroactive,
            countOccurrences: effectiveCountOccurrences,
            countStyle: _countStyle,
            tracksPresence: effectiveTracksPresence,
            assumeAbsent: effectiveAssumeAbsent,
            assumeAbsentFrom: effectiveAssumeAbsentFrom,
            showInDayRail: effectiveShowInDayRail,
            perOccurrenceDescriptions: effectivePerOccurrenceDescriptions,
            removeAfterAlert: effectiveRemoveAfterAlert,
            categoryAlerts: _categoryAlerts,
            time: effectiveTime,
            description: effectiveDescription,
            noteId: _noteId,
            iconKey: _iconKey,
            colorValue: _colorValue,
            tintIcon: _tintIcon,
            priority: _priority,
            clearShowInDayRail: effectiveShowInDayRail == null,
            clearAssumeAbsentFrom: effectiveAssumeAbsentFrom == null,
            clearEndDate: effectiveEnd == null,
            clearTime: effectiveTime == null,
            clearDescription: effectiveDescription == null,
            clearNoteId: _noteId == null,
            clearIconKey: _iconKey == null,
            clearColorValue: _colorValue == null,
          );
    final (occurrenceDay, occurrenceDescription) = _resolveOccurrenceOutcome(
      event,
      description,
    );
    Navigator.of(context).pop(
      EventEditorSaved(
        event,
        occurrenceDay: occurrenceDay,
        occurrenceDescription: occurrenceDescription,
        // Only when the picker was actually opened, and only while the saved
        // rule is a series — a one-off's one skip is its cancel, which the
        // detail sheet owns. A save that makes the event a one-off or moves
        // one clears its skips instead, so an old row on the new day cannot
        // hide it (`CalendarEvent.strandsSkipsOf`).
        skippedDays: base != null && event.strandsSkipsOf(base)
            ? const <DateTime>{}
            : _skippedDays != null && event.rule is! OneTimeRecurrence
            ? _skippedDays
            : null,
        alerts: List<EventAlert>.unmodifiable(_alerts),
        knownAlertIds: Set<String>.unmodifiable(_seededAlertIds),
        shared: _shareRowShown ? _markedShared : null,
      ),
    );
  }

  /// What saving should do to this day's row, as `(day, description)`.
  ///
  /// A null day means "leave the occurrence table alone"; a non-null day with
  /// a null description means "delete that row". The copy-on-write rule lives
  /// here: a day with no row of its own writes nothing while its text is
  /// still what it was seeded with — or equals [template] again — so a sparse
  /// table stays sparse and editing the shared description in front of an
  /// untouched day leaves that day following it. A day that already had a row
  /// keeps it even when its text matches again — only the explicit reset
  /// removes one.
  ///
  /// Returns nothing at all once the scope gate is closed — a rule that no
  /// longer repeats, or the per-day switch turned off: closing it must not
  /// merge an occurrence's text anywhere.
  ///
  /// Nor once [event]'s rule has stopped covering the day this editor was
  /// opened from: the save itself would make that row unreachable from every
  /// surface, so none is created. A row that already exists is left alone —
  /// an occurrence row is never deleted to clean up, and it comes back with
  /// the rule. The explicit reset is the one thing that outranks that gate:
  /// it is a user action rather than cleanup, so it removes its row whatever
  /// the saved rule goes on to cover.
  (DateTime?, String?) _resolveOccurrenceOutcome(
    CalendarEvent event,
    String template,
  ) {
    final day = widget.occurrenceDay;
    if (day == null || !_isEditing || !_scopeGateOpen) return (null, null);
    final dayText = _dayText.trim();
    // The reset survives a scope switch (which is why it isn't cleared there)
    // and survives editing the template afterwards — the day should follow the
    // *new* shared text, which is what deleting the row achieves. Only typing
    // something else into the day scope outranks it.
    if (_dayResetRequested && dayText == _dayResetBaseline.trim()) {
      return (day, null);
    }
    if (!_ruleOccursOn(event, day)) return (null, null);
    if (!_dayMaterialized &&
        (dayText == template || dayText == _daySeedText.trim())) {
      return (null, null);
    }
    return (day, dayText);
  }

  /// Whether the rule about to be saved still produces an occurrence on [day].
  ///
  /// `CalendarEvent.occursOnUtcDay` without its skip filter, deliberately: a
  /// cancelled day's occurrence returns the moment the skip is lifted, so its
  /// row is dormant rather than orphaned, while a day the saved rule no longer
  /// covers is reachable from nowhere (`calendar_event_service.dart` keeps
  /// both kinds of row through a rule change on purpose).
  bool _ruleOccursOn(CalendarEvent event, DateTime day) {
    final utcDay = _normalize(day);
    final end = event.endDateUtc;
    if (end != null && utcDay.isAfter(end)) return false;
    return event.rule.occursOn(
      utcDay,
      event.startDateUtc,
      retroactive: event.retroactive,
    );
  }

  Future<void> _onDelete() async {
    _blur();
    final base = widget.initialEvent;
    if (base == null) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.deleteEvent),
          content: Text(l10n.deleteEventConfirm(base.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop(EventEditorDeleted(base.id));
  }

  String _fingerprint() {
    final weekdays = _weekdays.toList()..sort();
    final skipped = (_skippedDays ?? _initialSkippedDays).toList()..sort();
    return [
      _titleController.text,
      _templateText,
      _dayText,
      _dayResetRequested,
      _categoryId,
      _iconKey,
      _colorValue,
      _tintIcon,
      _date,
      _additionalDates,
      _mode,
      _kind,
      _interval,
      weekdays,
      _endDate,
      _retroactive,
      _isAllDay,
      _startMinute,
      _durationMinutes,
      _removeAfterAlert,
      _categoryAlerts,
      _countOccurrences,
      _countStyle,
      _tracksPresence,
      _assumeAbsent,
      _assumeAbsentFrom,
      _showInDayRail,
      _perOccurrenceDescriptions,
      skipped,
      _noteId,
      _priority,
      _markedShared != _storedMark,
    ].join('\u0000');
  }

  /// The alert rows' side of the dirty comparison.
  ///
  /// Kept out of [_fingerprint] so the Calendar-settings seed, which lands
  /// after the first frame, can be re-baselined **on its own**: gating the
  /// whole re-baseline on the form being clean at that instant left the seeded
  /// alert folded into the current fingerprint and absent from the baseline
  /// whenever a keystroke landed first — which, with the title autofocused, is
  /// the normal path.
  String _alertsFingerprint() =>
      _alerts.map((alert) => alert.props.join(',')).join(';');

  bool get _isDirty =>
      _fingerprint() != _initialFingerprint ||
      _alertsFingerprint() != _initialAlertsFingerprint;

  Future<bool> _confirmLeave() async {
    if (!_isDirty) return true;
    return AppDialogs.confirmDiscard(context);
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      final leave = await _confirmLeave();
      if (!leave || !mounted) return;
      _popDiscarding();
    } finally {
      _leaving = false;
    }
  }

  void _popDiscarding() {
    Navigator.of(context).pop(widget.showBack ? const EventEditorBack() : null);
  }
}
