part of '../event_editor_sheet.dart';

/// The event's alerts, its category and its linked note: seeding, adding,
/// editing and removing an alert, the sheet's settings, and the two
/// pickers.
mixin _EventEditorAlertsAndLinks on _EventEditorSaving {
  /// Gives a brand-new event the alert the Calendar settings say it should
  /// start with (§5.1). Runs inside [_loadSheetSettings]'s `setState`.
  ///
  /// Three guards, each closing a way the seed could be a lie: an existing
  /// event's alerts are its own, a user who already added one has said what
  /// they want, and a default of `none` means new events get nothing at all.
  ///
  /// Reports whether it seeded, so the caller re-baselines the alert
  /// fingerprint for the seed and for nothing else.
  bool _seedDefaultAlert() {
    if (_isEditing || _alertsTouched || _alerts.isNotEmpty) return false;
    final hasDefault = _isAllDay
        ? _allDayAlertDefault != null
        : _timedAlertDefault != null;
    if (!hasDefault) return false;
    _alerts = [
      AlertEditorSheet.draft(
        eventId: '',
        allDay: _isAllDay,
        timedDefault: _timedAlertDefault,
        allDayDefault: _allDayAlertDefault,
      ),
    ];
    return true;
  }

  /// Opens the alert sheet on a brand-new alert, and keeps it only if the user
  /// saves. Never offers Remove there: closing the sheet already means "no".
  Future<void> _addAlert() async {
    _blur();
    if (_alerts.length >= kMaxAlertsPerEvent) return;
    final draft = AlertEditorSheet.draft(
      eventId: widget.initialEvent?.id ?? '',
      allDay: _isAllDay,
      timedDefault: _timedAlertDefault,
      allDayDefault: _allDayAlertDefault,
    );
    final result = await AlertEditorSheet.show(
      context,
      alert: draft,
      event: _alertPreviewEvent,
      canRemove: false,
      showRemoveAfter: _isOneTimeEvent,
      removeAfterAlert: _removeAfterAlert,
    );
    if (!mounted) return;
    switch (result) {
      case null:
      case AlertEditorRemoved():
        return;
      case AlertEditorSaved(:final alert, :final removeAfterAlert):
        setState(() {
          _alertsTouched = true;
          _alerts = [..._alerts, alert];
          if (_isOneTimeEvent) _removeAfterAlert = removeAfterAlert;
        });
    }
  }

  Future<void> _editAlert(EventAlert alert) async {
    _blur();
    final result = await AlertEditorSheet.show(
      context,
      alert: alert,
      event: _alertPreviewEvent,
      showRemoveAfter: _isOneTimeEvent,
      removeAfterAlert: _removeAfterAlert,
    );
    if (!mounted || result == null) return;
    setState(() {
      _alertsTouched = true;
      switch (result) {
        case AlertEditorRemoved():
          _alerts = [
            for (final a in _alerts)
              if (a.id != alert.id) a,
          ];
        case AlertEditorSaved(:final alert, :final removeAfterAlert):
          _alerts = [
            for (final existing in _alerts)
              if (existing.id == alert.id) alert else existing,
          ];
          if (_isOneTimeEvent) _removeAfterAlert = removeAfterAlert;
      }
    });
  }

  void _removeAlert(EventAlert alert) {
    setState(() {
      _alertsTouched = true;
      _alerts = [
        for (final a in _alerts)
          if (a.id != alert.id) a,
      ];
    });
  }

  Future<void> _loadSheetSettings() async {
    final settings = await SettingsService.getInstance();
    final palette = await settings.getColorPalette();
    final liveRendering = await settings.getLiveMarkdownRendering();
    final descriptionLimit = await settings.getEventDescriptionLimit();
    final railStyle = await settings.getCalendarDayRailStyle();
    final alertSettings = await settings.getAlertSettings();
    final haptics = await settings.getHapticFeedback();
    if (!mounted) return;
    // Both reach the editor surface non-destructively: the span memos are
    // cleared and re_editor is nudged to rebuild its display paragraphs.
    // Money stays disabled (the builder's default) — the ledger is a
    // per-note concept, so `$` rows in a description are literal text.
    _descriptionSpanBuilder.configureColors(palette);
    final rerender =
        palette != _colorPalette || liveRendering != _liveMarkdownRendering;
    var seeded = false;
    setState(() {
      _colorPalette = palette;
      _liveMarkdownRendering = liveRendering;
      _hapticsEnabled = haptics;
      _descriptionLimit = descriptionLimit;
      _dayRailEnabled = railStyle != DayRailStyle.none;
      _timedAlertDefault = alertSettings.timedDefault;
      _allDayAlertDefault = alertSettings.allDayDefault;
      seeded = _seedDefaultAlert();
    });
    // The seed is the settings' work, not the user's, so it is folded into
    // the alert baseline alone — never gated on the rest of the form, which a
    // keystroke may already have moved while this future was in flight.
    if (seeded) _initialAlertsFingerprint = _alertsFingerprint();
    if (rerender) {
      _descriptionController.forceRepaint();
      _relayDescriptionChange();
    }
  }

  Future<void> _pickCategory() async {
    _blur();
    final picked = await CategoryPickerSheet.pickSingle(
      context,
      selectedId: _categoryId,
      sandbox: widget.sandbox,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _categoryId = picked;
      _applyKindPresenceDefaults();
      // Birthdays are inherently yearly. When the user tags a brand-new,
      // still-one-time event as a birthday, pre-fill a yearly recurrence so it
      // repeats every year with no extra taps. A recurrence the user already
      // configured is left untouched.
      if (picked == kBirthdayCategoryId && _mode == _RepeatMode.oneTime) {
        _mode = _RepeatMode.recurring;
        _kind = RepeatKind.yearly;
        // Birthdays are the canonical occurrence-count use: with the birth
        // date as start, every occurrence shows the age. Pre-filled only on
        // the same fresh-event path as the yearly rule above; the style
        // follows yearly's default unless the user already chose one.
        _countOccurrences = true;
        if (!_countStyleTouched) {
          _countStyle = _defaultCountStyleFor(RepeatKind.yearly);
        }
      }
    });
  }

  /// Resolve the display title for the currently linked note. If the note
  /// no longer exists — hard-deleted or soft-deleted — flag it so the tile
  /// shows a "missing" state instead of a blank label. The stale id is kept
  /// until the user explicitly removes or replaces the link.
  ///
  /// Uses [NoteRepository.getNotesByIds] rather than `getNoteById` because
  /// only the former filters out soft-deleted notes (the app deletes notes
  /// soft), so a deleted note correctly reads as missing here.
  Future<void> _loadLinkedNoteTitle() async {
    final id = _noteId;
    if (id == null) return;
    final notes = await GetIt.I<NoteRepository>().getNotesByIds([id]);
    if (!mounted) return;
    final note = notes.isEmpty ? null : notes.first;
    setState(() {
      if (note == null) {
        _noteMissing = true;
        _noteTitle = null;
      } else {
        _noteMissing = false;
        _noteTitle = note.title;
      }
    });
  }

  Future<void> _pickNote() async {
    _blur();
    // A partner's note never: its money lines would count for my event.
    final picked = await showNotePickerDialog(context, ownOnly: true);
    if (picked == null || !mounted) return;
    setState(() {
      _noteId = picked.id;
      _noteTitle = picked.title;
      _noteMissing = false;
    });
  }

  void _clearNote() {
    setState(() {
      _noteId = null;
      _noteTitle = null;
      _noteMissing = false;
    });
  }
}
