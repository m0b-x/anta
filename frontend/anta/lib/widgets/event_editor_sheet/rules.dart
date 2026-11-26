part of '../event_editor_sheet.dart';

/// What the form currently describes: the rule it would save, the count
/// style and its example, the length limits, the category's profile, which
/// controls are on offer, and the description's move between the template
/// and this day.
mixin _EventEditorRules on _EventEditorDescription {
  void _blur() => FocusManager.instance.primaryFocus?.unfocus();

  RecurrenceRule _buildRule() {
    if (_mode == _RepeatMode.oneTime) {
      if (_additionalDates.isEmpty) return const OneTimeRecurrence();
      return SpecificDatesRecurrence(
        dates: Set.unmodifiable(<DateTime>{_date, ..._additionalDates}),
      );
    }
    return switch (_kind) {
      RepeatKind.daily => DailyRecurrence(interval: _interval),
      RepeatKind.weekly => WeeklyRecurrence(
        weekdays: Set.unmodifiable(_weekdays),
        interval: _interval,
      ),
      RepeatKind.monthly => MonthlyRecurrence(interval: _interval),
      RepeatKind.yearly => YearlyRecurrence(interval: _interval),
      RepeatKind.workdays => const WorkdaysRecurrence(),
      RepeatKind.weekends => const WeekendsRecurrence(),
      RepeatKind.holidays => const PublicHolidaysOnlyRecurrence(),
    };
  }

  String _countStyleLabel(AppLocalizations l10n, OccurrenceCountStyle style) {
    return switch (style) {
      OccurrenceCountStyle.numbered => l10n.eventCountStyleNumbered,
      OccurrenceCountStyle.elapsed => l10n.eventCountStyleElapsed,
    };
  }

  /// Labels for the **first three occurrences** under the current kind and
  /// style ("Day 1 · Day 2 · Day 3" against "0 years · 1 year · 2 years"),
  /// so the counting origin — the entire difference between the two styles —
  /// is visible before saving rather than discovered on the calendar.
  String _countStyleExample(AppLocalizations l10n) {
    String at(int n) {
      return switch (_countStyle) {
        OccurrenceCountStyle.numbered => switch (_kind) {
          RepeatKind.daily => l10n.eventNumberedDays(n),
          RepeatKind.weekly => l10n.eventNumberedWeeks(n),
          RepeatKind.monthly => l10n.eventNumberedMonths(n),
          RepeatKind.yearly => l10n.eventNumberedYears(n),
          _ => '',
        },
        OccurrenceCountStyle.elapsed => switch (_kind) {
          RepeatKind.daily => l10n.eventElapsedDays(n),
          RepeatKind.weekly => l10n.eventElapsedWeeks(n),
          RepeatKind.monthly => l10n.eventElapsedMonths(n),
          RepeatKind.yearly => l10n.eventElapsedYears(n),
          _ => '',
        },
      };
    }

    final first = _countStyle == OccurrenceCountStyle.numbered ? 1 : 0;
    return '${at(first)} · ${at(first + 1)} · ${at(first + 2)}';
  }

  bool get _canSave {
    if (_titleController.text.trim().isEmpty) return false;
    if (_mode == _RepeatMode.recurring &&
        _kind == RepeatKind.weekly &&
        _weekdays.isEmpty) {
      return false;
    }
    // Both scopes, not just the visible one: text parked in the inactive
    // buffer is still about to be saved, so checking only the live controller
    // would let an over-limit day override through from the template view.
    if (!_withinLimit(_templateText, _initialTemplateLength)) return false;
    if (_scopeControlVisible && !_withinLimit(_dayText, _initialDayLength)) {
      return false;
    }
    return true;
  }

  /// Whether [text] may be saved at its current length. Over the limit is
  /// allowed only while it is no longer than it already was, so lowering the
  /// setting blocks growth instead of locking the user out.
  bool _withinLimit(String text, int grandfathered) =>
      text.length <= _descriptionLimit || text.length <= grandfathered;

  /// Whether the *active* scope is within its own budget — what the counter
  /// and the over-limit hint report.
  bool get _activeScopeWithinLimit => _scope == _DescriptionScope.thisDay
      ? _withinLimit(_dayText, _initialDayLength)
      : _withinLimit(_templateText, _initialTemplateLength);

  /// The template's current text — from the controller when it is the active
  /// scope, otherwise from its buffer.
  String get _templateText => _scope == _DescriptionScope.allDays
      ? _descriptionController.text
      : _templateBuffer;

  /// This day's current text, same rule as [_templateText].
  String get _dayText => _scope == _DescriptionScope.thisDay
      ? _descriptionController.text
      : _dayBuffer;

  /// Whether the rule the form currently describes has more than one
  /// occurrence. Equivalent to `_buildRule() is! OneTimeRecurrence` without
  /// building a rule object on every frame — `_mode == oneTime` with extra
  /// dates is a `SpecificDatesRecurrence`, which *is* multi-occurrence.
  bool get _ruleHasManyOccurrences =>
      _mode == _RepeatMode.recurring || _additionalDates.isNotEmpty;

  /// The picked category's kind under its overrides, resolved as rendering
  /// resolves the category. The guide's sandbox reads none of the owner's
  /// profiles (decision V): its practice pre-fills and labels as an
  /// unprofiled calendar does, whatever the owner made of a category.
  EffectiveProfile get _profile => widget.sandbox
      ? EffectiveProfile.unprofiled
      : CategoryProfiles.effectiveFor(
          CalendarCategories.resolve(_categoryId).id,
        );

  /// Whether the event was tracked when the sheet opened, latched in
  /// `initState` for [_presenceOffered].
  late final bool _trackedAtOpen;

  /// Whether Track presence is on offer. A series always; a one-off only
  /// where its kind marks, so an unprofiled calendar's one-off editor stays
  /// the one it was (lead decision AI). A tracked event keeps it whatever
  /// its kind, or a mark nobody can see could never be switched off — read
  /// as it opened, never live, or switching it off would take the switch
  /// out from under the finger.
  bool get _presenceOffered =>
      _ruleHasManyOccurrences || _trackedAtOpen || _profile.marks;

  /// A new event's presence flags as its kind sets them, until the owner has
  /// answered for them. An existing event keeps what it has (decision U).
  void _applyKindPresenceDefaults() {
    if (_isEditing || _presenceTouched) return;
    final profile = _profile;
    _tracksPresence = profile.marksNew;
    _assumeAbsent = profile.assumeAbsentNew;
  }

  /// Whether the form currently describes an event whose days are separable:
  /// a rule with more than one occurrence, opted into per-occurrence
  /// descriptions. Read from the draft flag rather than the saved row, so the
  /// switch takes effect the moment it is flipped.
  bool get _scopeGateOpen =>
      _ruleHasManyOccurrences && _perOccurrenceDescriptions;

  /// Whether to offer the "this day / all days" control.
  ///
  /// Requires a saved event (a new one has no id until `_onSave`), an
  /// occurrence to scope to (the FAB path has none), and an open scope gate.
  /// Flipping the form to one-time — or the switch off — mid-edit hides it,
  /// see [_syncScopeToRule].
  bool get _scopeControlVisible =>
      _isEditing && widget.occurrenceDay != null && _scopeGateOpen;

  /// Moves the field between the template and this day's text.
  ///
  /// One controller throughout — only its content changes. The swap goes
  /// through `loadText`, never `set text`: a revocable write would let the
  /// toolbar's undo pull the *other* scope's text into the active one, and
  /// Save would persist it.
  void _setScope(_DescriptionScope next) {
    if (next == _scope) return;
    if (_scope == _DescriptionScope.allDays) {
      _templateBuffer = _descriptionController.text;
    } else {
      _dayBuffer = _descriptionController.text;
    }
    setState(() {
      _scope = next;
      _descriptionController.loadText(
        next == _DescriptionScope.thisDay ? _dayBuffer : _templateBuffer,
      );
      _descriptionEdits.syncLength();
    });
  }

  /// Returns this day to the template. Deleting the row is the only way back
  /// once a day has been materialized, so it is an explicit action rather
  /// than something inferred from the text matching again.
  void _resetDayToTemplate() {
    setState(() {
      _dayResetRequested = true;
      _dayBuffer = _templateText;
      _dayResetBaseline = _dayBuffer;
      if (_scope == _DescriptionScope.thisDay) {
        _descriptionController.loadText(_dayBuffer);
        _descriptionEdits.syncLength();
      }
    });
  }

  /// Drops back to the template scope when the form stops describing separable
  /// days — the rule is no longer repeating, or the per-day switch went off —
  /// so the field can never show a day's text while the control that explains
  /// it is hidden. The day buffer is kept in memory and simply not written:
  /// closing the gate must not silently merge one occurrence's text into the
  /// template.
  void _syncScopeToRule() {
    if (_scopeGateOpen || _scope == _DescriptionScope.allDays) return;
    _dayBuffer = _descriptionController.text;
    _scope = _DescriptionScope.allDays;
    _descriptionController.loadText(_templateBuffer);
    _descriptionEdits.syncLength();
  }

  /// Whether the form offers the share switch: only while paired (D7), and
  /// never in the guide's sandbox, whose demo event must not leave the phone.
  bool get _shareRowShown =>
      !widget.sandbox && _shareAvailability is! ShareNotPaired;
}
