import '../constants/public_holidays.dart';
import '../models/calendar_event.dart';
import '../models/recurrence_rule.dart';

/// Serializes [CalendarEvent]s to an RFC 5545 iCalendar (`.ics`) document so
/// a training plan can be handed to a phone calendar.
///
/// Times are written as **floating local time** (no `Z`, no `TZID`), which is
/// the honest encoding: [EventTime] stores minutes since local midnight and
/// the app never records a timezone, so an 18:00 session is 18:00 wherever
/// the user happens to be.
///
/// Recurrence is emitted as an `RRULE` whenever the rule maps exactly. The
/// two rules RFC 5545 cannot express — "workdays excluding public holidays"
/// and "public holidays only" — are reconciled against the holiday calendar
/// instead: workdays emit the weekday `RRULE` plus `EXDATE`s for the
/// holidays it must skip, and holidays-only is expanded to explicit
/// `RDATE`s. Both expansions are bounded by [expansionHorizonDays], so an
/// export is always finite.
abstract final class IcsSerializer {
  static const String productId = '-//Gym Notes//Calendar Export//EN';

  /// Bound on how far ahead rules that must be expanded to explicit dates
  /// are walked. Two years keeps a plan useful without unbounded output.
  static const int expansionHorizonDays = 730;

  /// Bound on the search for an event's first real occurrence. Every rule
  /// that fires at all fires within a year of its anchor.
  static const int _firstOccurrenceSearchDays = 366;

  static const String _crlf = '\r\n';

  /// RFC 5545 weekday tokens indexed by `DateTime.weekday` (1 = Monday).
  static const List<String> _weekdayTokens = [
    'MO',
    'TU',
    'WE',
    'TH',
    'FR',
    'SA',
    'SU',
  ];

  /// Builds the full `.ics` document. Events with no occurrence inside the
  /// search window (an empty specific-date set, a holidays-only rule with no
  /// holiday ahead of it) are skipped rather than written as broken entries.
  static String serialize({
    required List<CalendarEvent> events,
    DateTime? now,
  }) {
    final stamp = _formatUtcStamp((now ?? DateTime.now()).toUtc());
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:$productId',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
    ];
    for (final event in events) {
      lines.addAll(_serializeEvent(event, stamp));
    }
    lines.add('END:VCALENDAR');
    return '${lines.map(_fold).join(_crlf)}$_crlf';
  }

  static List<String> _serializeEvent(CalendarEvent event, String stamp) {
    final anchor = _dateOnly(event.startDate);
    final first = _firstOccurrenceOf(event, anchor);
    if (first == null) return const [];

    final time = event.time;
    final lines = <String>[
      'BEGIN:VEVENT',
      'UID:${event.id}@gym-notes',
      'DTSTAMP:$stamp',
      if (time == null)
        'DTSTART;VALUE=DATE:${_formatDate(first)}'
      else
        'DTSTART:${_formatDateTime(first, time.startMinute)}',
      if (time == null)
        'DTEND;VALUE=DATE:${_formatDate(first.add(const Duration(days: 1)))}'
      else if (time.endMinute != null)
        'DTEND:${_formatDateTime(first, time.endMinute!)}',
      'SUMMARY:${_escape(event.title)}',
      if (event.description != null && event.description!.trim().isNotEmpty)
        'DESCRIPTION:${_escape(event.description!)}',
      'CATEGORIES:${_escape(event.categoryId)}',
      'PRIORITY:${_icsPriority(event.priority)}',
    ];

    final rrule = _ruleToRrule(event.rule, first, event.endDate, time);
    if (rrule != null) lines.add(rrule);

    final exDates = _exceptionDates(event, first);
    if (exDates.isNotEmpty) {
      lines.add(_dateListProperty('EXDATE', exDates, time));
    }
    final rDates = _additionalDates(event, first);
    if (rDates.isNotEmpty) {
      lines.add(_dateListProperty('RDATE', rDates, time));
    }

    lines.add('END:VEVENT');
    return lines;
  }

  /// First day on or after [anchor] the event's rule actually fires.
  ///
  /// Used as `DTSTART` so the anchor is always a real occurrence. That
  /// matters for `BYDAY` rules: a weekly Mon/Wed event created on a Saturday
  /// would otherwise hand consumers a `DTSTART` that the `RRULE` does not
  /// produce, and interval phase would drift by a week.
  ///
  /// Deliberately queries the rule **without** `retroactive`: RFC 5545 has no
  /// way to express occurrences before `DTSTART`, so a retroactive event
  /// exports forward-only from its start date rather than emitting something
  /// no consumer could represent.
  static DateTime? _firstOccurrenceOf(CalendarEvent event, DateTime anchor) {
    final end = event.endDate == null ? null : _dateOnly(event.endDate!);
    for (var i = 0; i < _firstOccurrenceSearchDays; i++) {
      final day = anchor.add(Duration(days: i));
      if (end != null && day.isAfter(end)) return null;
      if (event.rule.occursOn(day, anchor)) return day;
    }
    return null;
  }

  /// `RRULE` for the rules RFC 5545 expresses directly. Returns `null` for
  /// one-time events, explicit date sets, and holidays-only rules — those
  /// carry their occurrences as `RDATE`s instead.
  static String? _ruleToRrule(
    RecurrenceRule rule,
    DateTime first,
    DateTime? endDate,
    EventTime? time,
  ) {
    final parts = switch (rule) {
      OneTimeRecurrence() => null,
      SpecificDatesRecurrence() => null,
      PublicHolidaysOnlyRecurrence() => null,
      DailyRecurrence(:final interval) => <String>[
        'FREQ=DAILY',
        if (interval > 1) 'INTERVAL=$interval',
      ],
      WeeklyRecurrence(:final weekdays, :final interval) => <String>[
        'FREQ=WEEKLY',
        if (interval > 1) 'INTERVAL=$interval',
        // Monday-aligned to match the app's fixed week grid, which is what
        // makes an every-N-weeks split land on the same weeks here.
        'WKST=MO',
        if (weekdays.isNotEmpty) 'BYDAY=${_byDay(weekdays)}',
      ],
      MonthlyRecurrence(:final interval) => <String>[
        'FREQ=MONTHLY',
        if (interval > 1) 'INTERVAL=$interval',
      ],
      YearlyRecurrence(:final interval) => <String>[
        'FREQ=YEARLY',
        if (interval > 1) 'INTERVAL=$interval',
      ],
      WorkdaysRecurrence() => <String>[
        'FREQ=WEEKLY',
        'WKST=MO',
        'BYDAY=MO,TU,WE,TH,FR',
      ],
      WeekendsRecurrence() => <String>['FREQ=WEEKLY', 'WKST=MO', 'BYDAY=SA,SU'],
    };
    if (parts == null) return null;
    if (endDate != null) {
      final until = _dateOnly(endDate);
      // UNTIL must use DTSTART's value type: a date for all-day events, a
      // floating date-time for timed ones.
      parts.add(
        time == null
            ? 'UNTIL=${_formatDate(until)}'
            : 'UNTIL=${_formatDateTime(until, time.startMinute)}',
      );
    }
    return 'RRULE:${parts.join(';')}';
  }

  /// Days the emitted `RRULE` produces but the app's rule does not.
  ///
  /// Only workdays needs this: its `BYDAY=MO..FR` approximation fires on
  /// public holidays the real rule skips.
  static List<DateTime> _exceptionDates(CalendarEvent event, DateTime first) {
    if (event.rule is! WorkdaysRecurrence) return const [];
    final dates = <DateTime>[];
    final last = _expansionEnd(event, first);
    for (
      var day = first;
      !day.isAfter(last);
      day = day.add(const Duration(days: 1))
    ) {
      if (day.weekday > DateTime.friday) continue;
      if (PublicHolidays.isHoliday(day)) dates.add(day);
    }
    return dates;
  }

  /// Occurrences carried as explicit `RDATE`s because no `RRULE` describes
  /// them: an author-picked date set, or "every public holiday".
  static List<DateTime> _additionalDates(CalendarEvent event, DateTime first) {
    final rule = event.rule;
    if (rule is SpecificDatesRecurrence) {
      final dates = rule.dates.map(_dateOnly).where((d) => d != first).toList()
        ..sort();
      return dates;
    }
    if (rule is PublicHolidaysOnlyRecurrence) {
      final dates = <DateTime>[];
      final last = _expansionEnd(event, first);
      for (
        var day = first.add(const Duration(days: 1));
        !day.isAfter(last);
        day = day.add(const Duration(days: 1))
      ) {
        if (PublicHolidays.isHoliday(day)) dates.add(day);
      }
      return dates;
    }
    return const [];
  }

  /// Last day an expansion may reach: the event's own end date when it has
  /// one, otherwise the horizon.
  static DateTime _expansionEnd(CalendarEvent event, DateTime first) {
    final horizon = first.add(const Duration(days: expansionHorizonDays));
    final end = event.endDate;
    if (end == null) return horizon;
    final endDay = _dateOnly(end);
    return endDay.isBefore(horizon) ? endDay : horizon;
  }

  static String _dateListProperty(
    String name,
    List<DateTime> dates,
    EventTime? time,
  ) {
    if (time == null) {
      final values = dates.map(_formatDate).join(',');
      return '$name;VALUE=DATE:$values';
    }
    final values = dates
        .map((d) => _formatDateTime(d, time.startMinute))
        .join(',');
    return '$name:$values';
  }

  static String _byDay(Set<int> weekdays) {
    final sorted = weekdays.toList()..sort();
    return sorted.map((d) => _weekdayTokens[d - 1]).join(',');
  }

  /// Maps the app's 1..5 priority (1 = highest, matching RFC 5545's
  /// direction) onto the RFC's 1..9 scale: 1 → 1, 3 → 5, 5 → 9.
  static int _icsPriority(int priority) {
    final clamped = priority.clamp(kMinEventPriority, kMaxEventPriority);
    return 2 * clamped - 1;
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  static String _formatDate(DateTime day) {
    return '${_pad4(day.year)}${_pad2(day.month)}${_pad2(day.day)}';
  }

  /// Floating local date-time. [minute] may exceed a day (an event running
  /// past midnight), which rolls the date forward.
  static String _formatDateTime(DateTime day, int minute) {
    final moment = day.add(Duration(minutes: minute));
    return '${_formatDate(moment)}T${_pad2(moment.hour)}'
        '${_pad2(moment.minute)}00';
  }

  static String _formatUtcStamp(DateTime utc) {
    return '${_formatDate(utc)}T${_pad2(utc.hour)}${_pad2(utc.minute)}'
        '${_pad2(utc.second)}Z';
  }

  static String _escape(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,')
        .replaceAll('\r\n', '\\n')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\n');
  }

  /// RFC 5545 content-line folding: break at 75 octets and continue the
  /// line with a single leading space. Measured in UTF-8 bytes, and never
  /// split inside a multi-byte character.
  static String _fold(String line) {
    if (line.length <= 73) return line;
    final buffer = StringBuffer();
    var octets = 0;
    var isContinuation = false;
    for (final rune in line.runes) {
      final char = String.fromCharCode(rune);
      final width = _utf8Width(rune);
      final limit = isContinuation ? 74 : 75;
      if (octets + width > limit) {
        buffer.write('$_crlf ');
        octets = 1;
        isContinuation = true;
      }
      buffer.write(char);
      octets += width;
    }
    return buffer.toString();
  }

  static int _utf8Width(int rune) {
    if (rune <= 0x7F) return 1;
    if (rune <= 0x7FF) return 2;
    if (rune <= 0xFFFF) return 3;
    return 4;
  }

  static String _pad2(int value) => value.toString().padLeft(2, '0');

  static String _pad4(int value) => value.toString().padLeft(4, '0');
}
