import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'recurrence_rule.dart';

/// The one encoding of a [RecurrenceRule] into the `rule_kind` / `rule_payload`
/// column pair.
///
/// Extracted from `CalendarEventService` when event templates gained the same
/// pair: two hand-written copies of this switch would drift the first time a
/// rule kind is added, and a template that encodes `weekly` differently from
/// an event is a rule that silently changes meaning when applied.
///
/// The kind strings and the payload shape are **persisted values** — changing
/// one is a data migration, not a refactor. The `interval` deliberately rides
/// inside the payload rather than in a column of its own.
abstract final class RecurrenceCodec {
  static const String kOneTime = 'oneTime';
  static const String kSpecificDates = 'specificDates';
  static const String kDaily = 'daily';
  static const String kWeekly = 'weekly';
  static const String kMonthly = 'monthly';
  static const String kYearly = 'yearly';
  static const String kWorkdays = 'workdays';
  static const String kWeekends = 'weekends';
  static const String kHolidaysOnly = 'holidaysOnly';

  static String kindOf(RecurrenceRule rule) {
    return switch (rule) {
      OneTimeRecurrence() => kOneTime,
      SpecificDatesRecurrence() => kSpecificDates,
      DailyRecurrence() => kDaily,
      WeeklyRecurrence() => kWeekly,
      MonthlyRecurrence() => kMonthly,
      YearlyRecurrence() => kYearly,
      WorkdaysRecurrence() => kWorkdays,
      WeekendsRecurrence() => kWeekends,
      PublicHolidaysOnlyRecurrence() => kHolidaysOnly,
    };
  }

  static String? payloadOf(RecurrenceRule rule) {
    final map = <String, Object>{};
    if (rule is WeeklyRecurrence) {
      final days = rule.weekdays.toList()..sort();
      map['weekdays'] = days;
    }
    if (rule is SpecificDatesRecurrence) {
      final ms = rule.dates.map((d) => d.millisecondsSinceEpoch).toList()
        ..sort();
      map['dates'] = ms;
    }
    final interval = intervalOf(rule);
    if (interval > 1) map['interval'] = interval;
    return map.isEmpty ? null : jsonEncode(map);
  }

  static int intervalOf(RecurrenceRule rule) => switch (rule) {
    DailyRecurrence(:final interval) => interval,
    WeeklyRecurrence(:final interval) => interval,
    MonthlyRecurrence(:final interval) => interval,
    YearlyRecurrence(:final interval) => interval,
    _ => 1,
  };

  static RecurrenceRule decode(String kind, String? payload) {
    switch (kind) {
      case kSpecificDates:
        final dates = _decodeDates(payload);
        if (dates.isEmpty) return const OneTimeRecurrence();
        return SpecificDatesRecurrence(dates: dates);
      case kDaily:
        return DailyRecurrence(interval: _decodeInterval(payload));
      case kWeekly:
        return WeeklyRecurrence(
          weekdays: _decodeWeekdays(payload),
          interval: _decodeInterval(payload),
        );
      case kMonthly:
        return MonthlyRecurrence(interval: _decodeInterval(payload));
      case kYearly:
        return YearlyRecurrence(interval: _decodeInterval(payload));
      case kWorkdays:
        return const WorkdaysRecurrence();
      case kWeekends:
        return const WeekendsRecurrence();
      case kHolidaysOnly:
        return const PublicHolidaysOnlyRecurrence();
      case kOneTime:
      default:
        return const OneTimeRecurrence();
    }
  }

  /// Reads the optional `interval`, defaulting to 1 for legacy payloads
  /// (which never carried it) or any malformed value.
  static int _decodeInterval(String? payload) {
    if (payload == null || payload.isEmpty) return 1;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map && decoded['interval'] is int) {
        final value = decoded['interval'] as int;
        if (value >= 1) return value;
      }
    } catch (e) {
      debugPrint('[RecurrenceCodec] Bad interval payload: $e');
    }
    return 1;
  }

  static Set<int> _decodeWeekdays(String? payload) {
    final days = <int>{};
    if (payload == null || payload.isEmpty) return days;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map && decoded['weekdays'] is List) {
        for (final raw in decoded['weekdays'] as List) {
          if (raw is int && raw >= 1 && raw <= 7) days.add(raw);
        }
      }
    } catch (e) {
      debugPrint('[RecurrenceCodec] Bad weekly payload: $e');
    }
    return days;
  }

  /// Parses the explicit one-off date set, normalizing each entry to date-only
  /// UTC. Malformed/missing entries are skipped; an empty result lets [decode]
  /// fall back to one-time.
  static Set<DateTime> _decodeDates(String? payload) {
    final dates = <DateTime>{};
    if (payload == null || payload.isEmpty) return dates;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map && decoded['dates'] is List) {
        for (final raw in decoded['dates'] as List) {
          if (raw is int) {
            final asUtc = DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
            dates.add(DateTime.utc(asUtc.year, asUtc.month, asUtc.day));
          }
        }
      }
    } catch (e) {
      debugPrint('[RecurrenceCodec] Bad specificDates payload: $e');
    }
    return dates;
  }
}
