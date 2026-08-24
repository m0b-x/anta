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
    // Parsed once per call and handed to every field extractor below, rather
    // than each extractor re-running its own `jsonDecode` on the identical
    // string. `decode` runs once per event row on every load, so this scales
    // with the event count. `null` here means "absent/empty/malformed" and is
    // itself the one-and-only failure signal each extractor needs — a
    // malformed payload must still let the [kind] through with defaulted
    // fields, never throw and never fall back to [OneTimeRecurrence].
    final decoded = _decodePayload(payload, kind);
    switch (kind) {
      case kSpecificDates:
        final dates = _decodeDates(decoded);
        if (dates.isEmpty) return const OneTimeRecurrence();
        return SpecificDatesRecurrence(dates: dates);
      case kDaily:
        return DailyRecurrence(interval: _decodeInterval(decoded));
      case kWeekly:
        return WeeklyRecurrence(
          weekdays: _decodeWeekdays(decoded),
          interval: _decodeInterval(decoded),
        );
      case kMonthly:
        return MonthlyRecurrence(interval: _decodeInterval(decoded));
      case kYearly:
        return YearlyRecurrence(interval: _decodeInterval(decoded));
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

  /// Parses [payload] into a `Map` once, or `null` for an absent/empty/
  /// malformed payload — the single failure signal every field extractor
  /// below consumes. One `debugPrint` per malformed payload (not one per
  /// field) so a corrupt `rule_payload` row is not logged three times over.
  static Map? _decodePayload(String? payload, String kind) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) return decoded;
    } catch (e) {
      debugPrint('[RecurrenceCodec] Bad $kind payload: $e');
      return null;
    }
    debugPrint('[RecurrenceCodec] Bad $kind payload: not a JSON object');
    return null;
  }

  /// Reads the optional `interval`, defaulting to 1 for legacy payloads
  /// (which never carried it) or any malformed value.
  static int _decodeInterval(Map? decoded) {
    if (decoded != null && decoded['interval'] is int) {
      final value = decoded['interval'] as int;
      if (value >= 1) return value;
    }
    return 1;
  }

  static Set<int> _decodeWeekdays(Map? decoded) {
    final days = <int>{};
    if (decoded != null && decoded['weekdays'] is List) {
      for (final raw in decoded['weekdays'] as List) {
        if (raw is int && raw >= 1 && raw <= 7) days.add(raw);
      }
    }
    return days;
  }

  /// Parses the explicit one-off date set, normalizing each entry to date-only
  /// UTC. Malformed/missing entries are skipped; an empty result lets [decode]
  /// fall back to one-time.
  static Set<DateTime> _decodeDates(Map? decoded) {
    final dates = <DateTime>{};
    if (decoded != null && decoded['dates'] is List) {
      for (final raw in decoded['dates'] as List) {
        if (raw is int) {
          final asUtc = DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
          dates.add(DateTime.utc(asUtc.year, asUtc.month, asUtc.day));
        }
      }
    }
    return dates;
  }
}
