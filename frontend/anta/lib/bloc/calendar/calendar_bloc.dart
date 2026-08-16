import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/calendar_event.dart';
import '../../services/calendar_event_service.dart';
import '../../services/event_occurrence_service.dart';
import '../../services/event_presence_service.dart';
import '../../services/note_money_ledger_service.dart';
import 'calendar_event.dart';
import 'calendar_state.dart';

export 'calendar_event.dart';
export 'calendar_state.dart';

class CalendarBloc extends Bloc<CalendarPageEvent, CalendarPageState> {
  final CalendarEventService _service;

  /// Memoizes recurrence expansion per calendar day. The first lookup for a
  /// day runs the O(N) scan over the event list; the result is cached so
  /// subsequent rebuilds (day selection, focus/format changes — none of
  /// which alter the result) are O(1) map lookups. Invalidated only when the
  /// event set or the visible-category filter changes. Bounded so a long
  /// month-paging session cannot grow it without limit.
  final Map<DateTime, List<CalendarEvent>> _dayCache = {};
  static const int _maxDayCacheEntries = 512;

  CalendarBloc({required CalendarEventService service})
    : _service = service,
      super(const CalendarPageInitial()) {
    on<LoadCalendarEvents>(_onLoad);
    on<SelectCalendarDay>(_onSelectDay);
    on<ChangeFocusedDay>(_onChangeFocusedDay);
    on<ChangeCalendarFormat>(_onChangeFormat);
    on<ChangeHiddenCategories>(_onChangeHiddenCategories);
    on<CreateCalendarEvent>(_onCreateEvent);
    on<UpdateCalendarEvent>(_onUpdateEvent);
    on<DeleteCalendarEvent>(_onDeleteEvent);
    on<SetOccurrenceDescription>(_onSetOccurrenceDescription);
    on<ClearOccurrenceDescription>(_onClearOccurrenceDescription);
    on<SetOccurrenceMissed>(_onSetOccurrenceMissed);
    on<ClearOccurrenceMissed>(_onClearOccurrenceMissed);
  }

  /// Amortized O(1) lookup over the in-memory cache populated by
  /// [CalendarEventService]. The first call for a given day expands the
  /// recurrence rules once (O(N) over the event list) and memoizes the
  /// result in [_dayCache]; later rebuilds reuse it. Stays synchronous so
  /// `TableCalendar.eventLoader` can call it directly during build.
  List<CalendarEvent> eventsForDay(DateTime day) {
    final current = state;
    if (current is! CalendarPageLoaded) return const [];
    final key = DateTime.utc(day.year, day.month, day.day);
    final cached = _dayCache[key];
    if (cached != null) return cached;
    final result = List<CalendarEvent>.unmodifiable([
      for (final e in current.allEvents)
        if (!current.hiddenCategoryIds.contains(e.categoryId) &&
            e.occursOn(key))
          e,
    ]);
    if (_dayCache.length >= _maxDayCacheEntries) _dayCache.clear();
    _dayCache[key] = result;
    return result;
  }

  /// Drops every memoized day so the next [eventsForDay] recomputes against
  /// the current event set / category filter. Called from the handlers that
  /// actually change those inputs — never from day/focus/format changes.
  void _invalidateDayCache() {
    if (_dayCache.isNotEmpty) _dayCache.clear();
  }

  Future<void> _onLoad(
    LoadCalendarEvents event,
    Emitter<CalendarPageState> emit,
  ) async {
    final today = _dateOnly(DateTime.now());
    try {
      await _service.reload();
    } catch (e) {
      debugPrint('[CalendarBloc] Load error: $e');
    }
    _invalidateDayCache();
    try {
      await (await NoteMoneyLedgerService.getInstance()).refresh(
        _service.events,
      );
    } catch (e) {
      debugPrint('[CalendarBloc] Money ledger refresh error: $e');
    }
    emit(
      CalendarPageLoaded(
        allEvents: List.unmodifiable(_service.events),
        focusedDay: today,
        selectedDay: today,
      ),
    );
  }

  void _onSelectDay(SelectCalendarDay event, Emitter<CalendarPageState> emit) {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    emit(
      current.copyWith(
        selectedDay: _dateOnly(event.day),
        focusedDay: _dateOnly(event.focusedDay),
      ),
    );
  }

  void _onChangeFocusedDay(
    ChangeFocusedDay event,
    Emitter<CalendarPageState> emit,
  ) {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    emit(current.copyWith(focusedDay: _dateOnly(event.focusedDay)));
  }

  void _onChangeFormat(
    ChangeCalendarFormat event,
    Emitter<CalendarPageState> emit,
  ) {
    final current = state;
    if (current is! CalendarPageLoaded || current.format == event.format) {
      return;
    }
    emit(current.copyWith(format: event.format));
  }

  void _onChangeHiddenCategories(
    ChangeHiddenCategories event,
    Emitter<CalendarPageState> emit,
  ) {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    final next = Set<String>.unmodifiable(event.hiddenCategoryIds);
    if (next.length == current.hiddenCategoryIds.length &&
        next.containsAll(current.hiddenCategoryIds)) {
      return;
    }
    _invalidateDayCache();
    emit(current.copyWith(hiddenCategoryIds: next));
  }

  Future<void> _onCreateEvent(
    CreateCalendarEvent event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    final normalized = event.event.copyWith(
      startDate: _dateOnly(event.event.startDate),
    );
    try {
      await _service.upsert(normalized);
    } catch (e) {
      debugPrint('[CalendarBloc] Create error: $e');
      return;
    }
    _invalidateDayCache();
    try {
      await (await NoteMoneyLedgerService.getInstance()).refresh(
        _service.events,
      );
    } catch (e) {
      debugPrint('[CalendarBloc] Money ledger refresh error: $e');
    }
    emit(
      current.copyWith(
        allEvents: List.unmodifiable(_service.events),
        selectedDay: normalized.startDate,
        focusedDay: normalized.startDate,
      ),
    );
  }

  Future<void> _onUpdateEvent(
    UpdateCalendarEvent event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    final normalized = event.event.copyWith(
      startDate: _dateOnly(event.event.startDate),
    );
    try {
      await _service.upsert(normalized);
    } catch (e) {
      debugPrint('[CalendarBloc] Update error: $e');
      return;
    }
    _invalidateDayCache();
    try {
      await (await NoteMoneyLedgerService.getInstance()).refresh(
        _service.events,
      );
    } catch (e) {
      debugPrint('[CalendarBloc] Money ledger refresh error: $e');
    }
    emit(current.copyWith(allEvents: List.unmodifiable(_service.events)));
  }

  Future<void> _onDeleteEvent(
    DeleteCalendarEvent event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    final hasEvent = current.allEvents.any((e) => e.id == event.eventId);
    if (!hasEvent) return;
    try {
      await _service.deleteById(event.eventId);
    } catch (e) {
      debugPrint('[CalendarBloc] Delete error: $e');
      return;
    }
    _invalidateDayCache();
    emit(current.copyWith(allEvents: List.unmodifiable(_service.events)));
  }

  /// Writes one occurrence's description override.
  ///
  /// Deliberately does **not** invalidate the day cache: that cache answers
  /// "which events occur on this day", and description text is not one of its
  /// inputs. Ticking a checkbox therefore no longer wipes 512 memoized days,
  /// which is what the whole-event update path used to do. It also skips the
  /// money-ledger refresh — descriptions never feed the ledger.
  ///
  /// Bumping `occurrenceRevision` is what makes the emit survive: the state is
  /// `Equatable`, so an otherwise-identical copy would be dropped, and the
  /// agenda's identity-based row memo would keep serving stale text.
  Future<void> _onSetOccurrenceDescription(
    SetOccurrenceDescription event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    try {
      final service = await EventOccurrenceService.getInstance();
      await service.setDescription(event.eventId, event.day, event.description);
    } catch (e) {
      debugPrint('[CalendarBloc] Occurrence write error: $e');
      return;
    }
    emit(
      current.copyWith(occurrenceRevision: current.occurrenceRevision + 1),
    );
  }

  /// Deletes one occurrence's override, returning that day to the event's
  /// template. Same cache reasoning as [_onSetOccurrenceDescription].
  Future<void> _onClearOccurrenceDescription(
    ClearOccurrenceDescription event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    try {
      final service = await EventOccurrenceService.getInstance();
      await service.clearDescription(event.eventId, event.day);
    } catch (e) {
      debugPrint('[CalendarBloc] Occurrence clear error: $e');
      return;
    }
    emit(
      current.copyWith(occurrenceRevision: current.occurrenceRevision + 1),
    );
  }

  /// Marks one occurrence missed.
  ///
  /// Same cache reasoning as [_onSetOccurrenceDescription], and for a stronger
  /// reason: presence is a **rendering** concern, never a membership one. A
  /// missed day still occurs, so "which events occur on this day" is unchanged
  /// and invalidating would wipe 512 memoized days for nothing. Hiding missed
  /// occurrences is a render-time filter — the moment a presence check lands in
  /// [eventsForDay], `EventAgenda` or `.ics`, those surfaces start disagreeing
  /// about what exists.
  Future<void> _onSetOccurrenceMissed(
    SetOccurrenceMissed event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    try {
      final service = await EventPresenceService.getInstance();
      await service.markMissed(event.eventId, event.day);
    } catch (e) {
      debugPrint('[CalendarBloc] Presence write error: $e');
      return;
    }
    emit(
      current.copyWith(occurrenceRevision: current.occurrenceRevision + 1),
    );
  }

  /// Returns one occurrence to present. Same cache reasoning as
  /// [_onSetOccurrenceMissed].
  Future<void> _onClearOccurrenceMissed(
    ClearOccurrenceMissed event,
    Emitter<CalendarPageState> emit,
  ) async {
    final current = state;
    if (current is! CalendarPageLoaded) return;
    try {
      final service = await EventPresenceService.getInstance();
      await service.unmark(event.eventId, event.day);
    } catch (e) {
      debugPrint('[CalendarBloc] Presence clear error: $e');
      return;
    }
    emit(
      current.copyWith(occurrenceRevision: current.occurrenceRevision + 1),
    );
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }
}
