part of '../calendar_overview_page.dart';

/// The rows: what a tap opens, the presence button, and the builder the
/// list and month mode both draw them with.
mixin _OverviewRowActions on _OverviewYears {
  void _openOccurrence(AgendaDayListEntry entry) =>
      _openOn(entry.day, entry.eventId);

  /// The day panel's presence toggle from the row's button (2026-10-17): the
  /// explicit status through the bloc, and the row's dimming and its day's
  /// counts are the feedback once the state comes back.
  void _onEntryPresence(AgendaDayListEntry entry, bool missed) {
    final eventId = entry.eventId;
    if (eventId == null) return;
    _click();
    _pendingMarks.add((eventId, entry.day));
    EventSheetsFlow.setOccurrencePresence(
      context.read<CalendarBloc>(),
      eventId,
      entry.day,
      missed,
    );
  }

  /// A per-event row opens the event's last day in the period (D10 · A):
  /// the most recent of what the row counts.
  void _openEventRow(AgendaDayListEventRow row) =>
      _openOn(row.last, row.entry.eventId);

  /// The occurrence's detail sheet over the list (D14 · A): no calendar is
  /// pushed, so back closes the sheet onto the row it came from. Read from
  /// the loaded events, so an event gone since the list was drawn opens
  /// nothing. The bloc states the trip's writes emit are parked while it
  /// runs ([_onStateChanged]) and adopted once at its end.
  void _openOn(DateTime day, String? eventId) {
    if (eventId == null) return;
    _blur();
    // [_events], not [_eventsById]: the list is taken with every adopted
    // state, the map only when the store is resolved anew.
    final events = _events;
    if (events == null) return;
    for (final event in events) {
      if (event.id != eventId) continue;
      unawaited(_openDetail(event, day));
      return;
    }
  }

  Future<void> _openDetail(CalendarEvent event, DateTime day) async {
    await _sheets.openDetail(context, event, day);
    if (!mounted || _covered || _sheetGuard.isOpen) return;
    final pending = _pendingState;
    if (pending == null) return;
    _pendingState = null;
    _adopt(pending);
  }

  /// The rows of the list and of month mode, one geometry per kind (T4, T8):
  /// titles on one line, a caption clamped to one, no pencil — a row opens
  /// its occurrence's detail sheet, where it is edited, and a day row of an
  /// event that keeps attendance carries the day panel's presence button
  /// ([_presenceOffered]). The list's headers take [headers], its slots'
  /// layout; month mode's sliver sizes each row itself, so its headers wrap
  /// as their text needs.
  AgendaDayListRowBuilder _rowBuilder(
    List<AgendaDayListRow> rows, {
    AgendaHeaderSlots? headers,
    bool? dayHeaderWithYear,
  }) {
    return AgendaDayListRowBuilder(
      rows: rows,
      today: _today,
      onEntryTap: _openOccurrence,
      onEntryPresence: _presenceOffered ? _onEntryPresence : null,
      presenceIdentifier: (entry) => switch (entry.eventId) {
        final id? => SemanticsIds.overviewRowPresence(id, entry.day),
        null => null,
      },
      onEventTap: _openEventRow,
      captionMaxLines: 1,
      dayHeaderWithYear:
          dayHeaderWithYear ??
          (_mode == AgendaDayListMode.list && _spanCrossesYear),
      monthCounts: true,
      headerSlots: headers,
      singleLineTitles: true,
      rowIdentifier: (entry) => switch (entry.eventId) {
        final id? => SemanticsIds.overviewRow(id, entry.day),
        null => null,
      },
      eventRowIdentifier: (row) => switch (row.entry.eventId) {
        final id? => SemanticsIds.overviewEventRow(id),
        null => null,
      },
      partnerLook: _partnerLook,
    );
  }

  Color _tileColor(ColorScheme colorScheme) {
    if (CategoryAllowlist.soleTicked(_categoryIds) case final category?) {
      return category.color;
    }
    return _appearance.accentOr(colorScheme.primary);
  }
}
