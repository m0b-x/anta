part of '../event_editor_sheet.dart';

/// The form's rows: the title, when, the occurrences, the alerts, the
/// linked note and the share switch.
mixin _EventEditorRows on _EventEditorDescriptionViews {
  static const int _maxInlineDates = 3;
  static const double _dayRailMenuWidth = 180;

  Widget _buildTitleRow(AppLocalizations l10n, IconData icon, Color accent) {
    return FormTitleRow(
      leading: EventAvatar(icon: icon, color: accent),
      controller: _titleController,
      hint: l10n.eventTitle,
      maxLength: kEventTitleMaxLength,
      counterFrom: kEventTitleCounterFrom,
      counterLabel: l10n.eventTitleCount,
      autofocus: !_isEditing,
      identifier: SemanticsIds.eventTitle,
    );
  }

  List<Widget> _buildWhenRows(
    AppLocalizations l10n,
    DateFormat dateFormat,
    List<DateTime> oneTimeDates,
  ) {
    final oneTime = _mode == _RepeatMode.oneTime;
    final endMinute = _durationMinutes == null
        ? null
        : (_startMinute + _durationMinutes!) % EventTime.minutesPerDay;
    final crossesMidnight =
        _durationMinutes != null &&
        _startMinute + _durationMinutes! >= EventTime.minutesPerDay;
    return [
      if (oneTime && oneTimeDates.length == 1)
        FormPickerRow(
          glyph: Icons.calendar_today_outlined,
          identifier: SemanticsIds.eventDate,
          label: l10n.eventDateLabel,
          value: dateFormat.format(_date),
          onTap: _pickDate,
        )
      else if (oneTime && oneTimeDates.length > _maxInlineDates)
        FormPickerRow(
          glyph: Icons.calendar_today_outlined,
          identifier: SemanticsIds.eventDates,
          label: l10n.eventDatesLabel,
          value: _datesValue(l10n, oneTimeDates),
          onTap: () => _pickOneTimeDates(view: CalendarDatePickerView.list),
        )
      else if (oneTime)
        for (final date in oneTimeDates)
          FormPickerRow(
            glyph: Icons.calendar_today_outlined,
            label: dateFormat.format(date),
            onTap: _pickOneTimeDates,
            trailingButton: FormTrailingButton(
              icon: Icons.close_rounded,
              tooltip: l10n.eventRemoveDate,
              onPressed: () => _removeOneTimeDate(date),
            ),
          )
      else
        FormPickerRow(
          glyph: Icons.calendar_today_outlined,
          identifier: SemanticsIds.eventDate,
          label: l10n.eventDate,
          value: dateFormat.format(_date),
          onTap: _pickDate,
        ),
      if (oneTime)
        FormActionRow(
          glyph: Icons.add_rounded,
          identifier: SemanticsIds.eventAddDate,
          label: l10n.eventAddDate,
          onTap: _pickOneTimeDates,
        ),
      FormSwitchRow(
        glyph: Icons.schedule_outlined,
        identifier: SemanticsIds.eventAllDay,
        label: l10n.eventAllDay,
        value: _isAllDay,
        onChanged: _setAllDay,
      ),
      if (!_isAllDay) ...[
        ValueChangeHighlight(
          value: _startMinute,
          child: FormPickerRow(
            subRow: true,
            identifier: SemanticsIds.eventStarts,
            label: l10n.eventStarts,
            value: EventTimeFormatter.formatMinute(_startMinute, context),
            onTap: _pickStartTime,
          ),
        ),
        ValueChangeHighlight(
          value: endMinute,
          child: endMinute == null
              ? FormPickerRow(
                  subRow: true,
                  identifier: SemanticsIds.eventEnds,
                  label: l10n.eventEnds,
                  value: l10n.eventEndTimeNone,
                  onTap: _pickEndTime,
                )
              : FormPickerRow(
                  subRow: true,
                  label: crossesMidnight
                      ? l10n.eventCrossesMidnight
                      : l10n.eventEnds,
                  value:
                      '${EventTimeFormatter.formatMinute(endMinute, context)}'
                      ' · '
                      '${EventTimeFormatter.formatDuration(_durationMinutes!, l10n)}',
                  onTap: _pickEndTime,
                  trailingButton: FormTrailingButton(
                    icon: Icons.close_rounded,
                    tooltip: l10n.eventEndTimeRemove,
                    onPressed: _clearEndTime,
                  ),
                ),
        ),
      ],
      FormPickerRow(
        glyph: Icons.repeat_rounded,
        identifier: SemanticsIds.eventRepeat,
        label: l10n.eventRepeat,
        value: _repeatValue(l10n),
        onTap: _pickRepeat,
      ),
    ];
  }

  List<Widget> _buildOccurrenceRows(
    AppLocalizations l10n,
    DateFormat dateFormat,
  ) {
    final recurring = _mode == _RepeatMode.recurring;
    return [
      if (recurring && _kind.supportsInterval) ...[
        FormSwitchRow(
          glyph: Icons.numbers_rounded,
          label: l10n.eventCountOccurrences,
          value: _countOccurrences,
          onChanged: (v) => setState(() => _countOccurrences = v),
        ),
        if (_countOccurrences)
          FormChipRow(
            chips: [
              for (final style in OccurrenceCountStyle.values)
                FormChip(
                  label: _countStyleLabel(l10n, style),
                  selected: _countStyle == style,
                  onTap: () => setState(() {
                    _countStyle = style;
                    _countStyleTouched = true;
                  }),
                ),
            ],
            caption: FormCaption(text: _countStyleExample(l10n)),
          ),
      ],
      if (_presenceOffered)
        FormSwitchRow(
          glyph: Icons.how_to_reg_outlined,
          label: l10n.eventTrackPresence,
          value: _tracksPresence,
          onChanged: (v) => setState(() {
            _tracksPresence = v;
            _presenceTouched = true;
          }),
        ),
      if (_tracksPresence) ...[
        FormChipRow(
          chips: [
            FormChip(
              label: l10n.eventAssumePresent,
              selected: !_assumeAbsent,
              onTap: () => setState(() {
                _selectAssumeAbsent(false);
                _presenceTouched = true;
              }),
            ),
            FormChip(
              label: l10n.eventAssumeAbsent,
              selected: _assumeAbsent,
              onTap: () => setState(() {
                _selectAssumeAbsent(true);
                _presenceTouched = true;
              }),
            ),
          ],
        ),
        if (_assumeAbsent && _isEditing)
          FormPickerRow(
            subRow: true,
            label: l10n.eventAssumeAbsentFrom,
            value: _assumeAbsentFrom == null
                ? l10n.eventAssumeAbsentFromStart
                : dateFormat.format(_assumeAbsentFrom!),
            onTap: _pickAssumeAbsentFrom,
            trailingButton: _assumeAbsentFrom == null
                ? null
                : FormTrailingButton(
                    icon: Icons.close_rounded,
                    tooltip: l10n.resetToDefault,
                    onPressed: () => setState(() {
                      _assumeAbsentFrom = null;
                      _assumeAbsentFromTouched = true;
                    }),
                  ),
          ),
      ],
      // A one-off reaches this group for its presence alone: the rest stays
      // a series' (the rail's membership, the per-day texts, the skips).
      if (_ruleHasManyOccurrences) ...[
        if (_dayRailEnabled)
          FormMenuRow<_DayRailChoice>(
            glyph: Icons.vertical_split_outlined,
            label: l10n.eventShowInDayRail,
            value: _dayRailLabel(l10n, _DayRailChoice.of(_showInDayRail)),
            selected: _DayRailChoice.of(_showInDayRail),
            menuWidth: _dayRailMenuWidth,
            items: [
              for (final choice in _DayRailChoice.values)
                FormMenuItem(value: choice, label: _dayRailLabel(l10n, choice)),
            ],
            onSelected: (choice) =>
                setState(() => _showInDayRail = choice.value),
          ),
        FormSwitchRow(
          glyph: Icons.event_note_outlined,
          label: l10n.eventPerOccurrenceDescriptions,
          value: _perOccurrenceDescriptions,
          onChanged: _setPerOccurrenceDescriptions,
        ),
        if (_isEditing)
          FormPickerRow(
            glyph: Icons.event_busy_outlined,
            label: l10n.eventSkippedDays,
            value: _effectiveSkippedDays.isEmpty
                ? l10n.eventNoSkippedDays
                : l10n.eventSkippedDaysCount(_effectiveSkippedDays.length),
            onTap: _pickSkippedDays,
          ),
      ],
    ];
  }

  /// The event's own alerts, then its category's as read rows in this event's
  /// wording (M4 · A: information, never a control; the switch at the end is
  /// the one control), Add alert counting own rows only, the remove-after
  /// switch and the Category alerts switch, which exists only while the
  /// category hands something down. Switched off, the inherited rows stay
  /// and dim rather than leave: nothing in the group moves under the finger.
  List<Widget> _buildAlertRows(AppLocalizations l10n) {
    final previewEvent = _alertPreviewEvent;
    final categoryLabel = CalendarCategories.labelOf(
      CalendarCategories.resolve(_categoryId),
      l10n,
    );
    return [
      ...eventAlertRows(
        context,
        l10n: l10n,
        previewEvent: previewEvent,
        alerts: _alerts,
        inherited: [
          for (final inherited in _inheritedAlerts)
            inherited.toEventAlert(previewEvent.id),
        ],
        categoryLabel: categoryLabel,
        onEdit: _editAlert,
        onRemove: _removeAlert,
        onAdd: _addAlert,
        addIdentifier: SemanticsIds.eventAlertAdd,
        inheritedEnabled: _categoryAlerts,
      ),
      if (_isOneTimeEvent && _hasAlarmAlert)
        AutomationId(
          identifier: SemanticsIds.eventAlertRemoveAfter,
          child: FormSwitchRow(
            glyph: Icons.auto_delete_outlined,
            label: l10n.eventAlertRemoveAfter,
            value: _removeAfterAlert,
            onChanged: (value) => setState(() => _removeAfterAlert = value),
          ),
        ),
      if (_inheritedAlerts.isNotEmpty)
        AutomationId(
          identifier: SemanticsIds.eventCategoryAlerts,
          child: FormSwitchRow(
            glyph: Icons.layers_outlined,
            label: l10n.eventCategoryAlerts,
            subtitle: l10n.eventCategoryAlertsDesc(categoryLabel),
            value: _categoryAlerts,
            onChanged: (value) => setState(() => _categoryAlerts = value),
          ),
        ),
    ];
  }

  Widget _buildLinkedNoteRow(AppLocalizations l10n, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    if (_noteId == null) {
      return FormPickerRow(
        glyph: Icons.sticky_note_2_outlined,
        identifier: SemanticsIds.eventLinkedNote,
        label: l10n.eventLinkedNote,
        value: l10n.eventLinkedNoteNone,
        onTap: _pickNote,
      );
    }
    final unlink = FormTrailingButton(
      icon: Icons.link_off_rounded,
      tooltip: l10n.eventRemoveNoteLink,
      onPressed: _clearNote,
    );
    if (_noteMissing) {
      return FormPickerRow(
        glyph: Icons.warning_amber_rounded,
        glyphColor: colorScheme.error,
        identifier: SemanticsIds.eventLinkedNote,
        label: l10n.eventLinkedNote,
        value: l10n.eventLinkedNoteNotFound,
        valueColor: colorScheme.error,
        semanticsLabel: l10n.eventLinkedNoteMissing,
        onTap: _pickNote,
        trailingButton: unlink,
      );
    }
    final title = _noteTitle;
    return FormPickerRow(
      glyph: Icons.sticky_note_2_outlined,
      identifier: SemanticsIds.eventLinkedNote,
      label: l10n.eventLinkedNote,
      value: title == null ? '' : (title.isEmpty ? l10n.untitledNote : title),
      onTap: _pickNote,
      trailingButton: unlink,
    );
  }

  /// The share switch (`EventShareRow`, the one the guide's stages draw).
  ///
  /// The category reading follows the picked category at once and uses its
  /// stored id, as `CalendarCategories.shareOf` does: an event on a missing
  /// id drawn under Other is not shared through Other.
  Widget _buildShareRow(AppLocalizations l10n) {
    final availability = _shareAvailability;
    final category = CalendarCategories.byId(_categoryId);
    return EventShareRow(
      partnerName: ShareCopy.partnerName(
        l10n,
        availability.audience?.displayName,
      ),
      ready: availability is ShareReady,
      value: _markedShared,
      onChanged: (value) => setState(() => _markedShared = value),
      sharedThrough: category != null && category.sharedByMe
          ? CalendarCategories.labelOf(category, l10n)
          : null,
      identifier: SemanticsIds.eventShare,
      onOpenSync: _openSyncSettings,
    );
  }

  /// D8: the one step missing is on Sync & sharing, pushed over the form so
  /// the draft is still there when the person comes back — and the row
  /// follows what they did there: the switch reads the mark as stored now,
  /// unless the person had moved it, whose choice stays.
  Future<void> _openSyncSettings() async {
    _blur();
    await AppNavigator.toSyncSettings(context);
    final reread = widget.rereadShare;
    if (reread == null || !mounted) return;
    final next = await reread();
    if (!mounted) return;
    final touched = _markedShared != _storedMark;
    setState(() {
      _shareAvailability = next.availability;
      _storedMark = next.markedShared;
      if (!touched) _markedShared = _storedMark;
    });
  }
}
