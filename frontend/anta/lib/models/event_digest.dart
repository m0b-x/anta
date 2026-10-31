import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../constants/event_alerts.dart';

/// How often a digest fires. Persisted by [name] inside the payload; an
/// unknown value decodes to [monthly], the cadence the feature exists for.
///
/// The two report cadences look back instead of ahead: they fire on the
/// weekly or monthly schedule and list the week or month that just ended.
/// They are new names rather than a flag so that an older build, which does
/// not know them, decodes the digest disabled instead of firing it as an
/// upcoming monthly one.
enum DigestCadence {
  daily,
  weekly,
  monthly,
  weeklyReport,
  monthlyReport;

  /// Whether the digest lists the span that just ended; its `leadDays` is
  /// kept in the payload and never read.
  bool get isReport =>
      this == DigestCadence.weeklyReport || this == DigestCadence.monthlyReport;

  static DigestCadence fromName(String? raw) {
    for (final cadence in DigestCadence.values) {
      if (cadence.name == raw) return cadence;
    }
    return DigestCadence.monthly;
  }
}

/// One scheduled digest (**v42**): a single bundled notification on a
/// cadence that lists the occurrences of a span — "3 birthdays this month".
///
/// Persisted in `event_digests` as `overview_views` persists a view: [id],
/// [name], [enabled] and [sortOrder] are the row's own columns, everything
/// about *what* it lists and *when* it fires is the one blob
/// [encodePayload] writes and [EventDigest.fromRow] reads forward-compatibly.
///
/// The defaults are the digest an unreadable blob decodes to — monthly on the
/// 1st at 09:00 over every category — so a row a newer build wrote still
/// shows in the hub rather than vanishing; it decodes switched off, and a
/// re-save from the sheet makes it this version's.
class EventDigest extends Equatable {
  final String id;

  /// What the user called it, or `''` for a title derived from the
  /// categories it covers.
  final String name;

  final DigestCadence cadence;

  /// The day the digest fires on: weekly (and weekly report) `1..7`
  /// ([DateTime.monday] .. [DateTime.sunday]), monthly (and monthly report)
  /// `1..28` (every month has the day), daily `0`.
  final int anchor;

  /// Minute of day it fires at, `0..1439`.
  final int minute;

  /// Days between the fire and the span it lists — `0` is "this month",
  /// `1` "from tomorrow". Stored up to [maxLeadDays].
  final int leadDays;

  /// The categories it lists; empty means every category, as the overview
  /// lists them.
  final Set<String> categoryIds;

  /// Whether an empty span still fires ("No events this month").
  final bool includeEmpty;

  /// The hub switch. A disabled digest is kept and arms nothing.
  final bool enabled;

  /// Display position: appended on create, rewritten dense by
  /// `EventDigestService.reorder`.
  final int sortOrder;

  /// False when [EventDigest.fromRow] could not read the stored payload and
  /// fell back to the defaults. Never stored and not part of equality: it is
  /// how this build read the row, not what the digest is. A surface must not
  /// write such a digest back — a re-save would replace a newer build's
  /// payload with these defaults.
  final bool isReadable;

  /// The widest [leadDays] a payload may carry; the sheet offers 0 and 1.
  static const int maxLeadDays = 7;

  /// The last [minute] of a day.
  static const int lastMinute = Duration.minutesPerDay - 1;

  /// The last day a monthly [anchor] may name: every month has it.
  static const int lastMonthAnchor = 28;

  /// The ranges are asserted in debug, so a draft built out of range fails
  /// where it is built; what reads a digest still clamps, because a release
  /// build carries no asserts.
  const EventDigest({
    required this.id,
    this.name = '',
    this.cadence = DigestCadence.monthly,
    this.anchor = 1,
    this.minute = kDefaultAlertDayMinute,
    this.leadDays = 0,
    this.categoryIds = const {},
    this.includeEmpty = false,
    this.enabled = true,
    this.sortOrder = 0,
    this.isReadable = true,
  }) : assert(minute >= 0 && minute <= lastMinute),
       assert(leadDays >= 0 && leadDays <= maxLeadDays),
       assert(
         (cadence != DigestCadence.weekly &&
                 cadence != DigestCadence.weeklyReport) ||
             (anchor >= DateTime.monday && anchor <= DateTime.sunday),
       ),
       assert(
         (cadence != DigestCadence.monthly &&
                 cadence != DigestCadence.monthlyReport) ||
             (anchor >= 1 && anchor <= lastMonthAnchor),
       );

  EventDigest copyWith({
    String? id,
    String? name,
    DigestCadence? cadence,
    int? anchor,
    int? minute,
    int? leadDays,
    Set<String>? categoryIds,
    bool? includeEmpty,
    bool? enabled,
    int? sortOrder,
  }) {
    return EventDigest(
      id: id ?? this.id,
      name: name ?? this.name,
      cadence: cadence ?? this.cadence,
      anchor: anchor ?? this.anchor,
      minute: minute ?? this.minute,
      leadDays: leadDays ?? this.leadDays,
      categoryIds: categoryIds ?? this.categoryIds,
      includeEmpty: includeEmpty ?? this.includeEmpty,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
      isReadable: isReadable,
    );
  }

  static const String _cadence = 'cadence';
  static const String _anchor = 'anchor';
  static const String _minute = 'minute';
  static const String _leadDays = 'leadDays';
  static const String _categories = 'categories';
  static const String _includeEmpty = 'includeEmpty';

  /// The stored blob: everything but the row's own columns. The categories
  /// are sorted so one digest always writes one blob.
  String encodePayload() => jsonEncode({
    _cadence: cadence.name,
    _anchor: anchor,
    _minute: minute,
    _leadDays: leadDays,
    _categories: categoryIds.toList()..sort(),
    _includeEmpty: includeEmpty,
  });

  /// Reads [encodePayload]'s output forward-compatibly: an unknown cadence is
  /// monthly, an out-of-range anchor, minute or lead is clamped to its
  /// cadence's range, an absent field is its default, an unknown key is
  /// ignored. A payload that is not a JSON object at all is the default
  /// digest. Never throws, so one bad blob cannot hide the other digests.
  ///
  /// A payload this version cannot read — empty, malformed, or naming no
  /// cadence it knows — decodes **disabled** whatever [enabled] says: a later
  /// version's digest kind must never fire monthly here, and nothing arms
  /// what nobody configured.
  factory EventDigest.fromRow({
    required String id,
    required String name,
    required String payload,
    bool enabled = true,
    int sortOrder = 0,
  }) {
    Object? json;
    try {
      json = payload.isEmpty ? null : jsonDecode(payload);
    } catch (e) {
      debugPrint('[EventDigest] Malformed digest payload: $e');
    }
    final map = json is Map ? json : const {};
    final rawCadence = map[_cadence];
    final cadence = DigestCadence.fromName(
      rawCadence is String ? rawCadence : null,
    );
    final understood = cadence.name == rawCadence;
    final anchor = map[_anchor];
    final minute = map[_minute];
    final leadDays = map[_leadDays];
    final categories = map[_categories];
    final includeEmpty = map[_includeEmpty];
    return EventDigest(
      id: id,
      name: name,
      cadence: cadence,
      anchor: clampAnchor(cadence, anchor is int ? anchor : null),
      minute: minute is int
          ? minute.clamp(0, lastMinute)
          : kDefaultAlertDayMinute,
      leadDays: leadDays is int ? leadDays.clamp(0, maxLeadDays) : 0,
      categoryIds: {
        if (categories is List)
          for (final id in categories)
            if (id is String && id.isNotEmpty) id,
      },
      includeEmpty: includeEmpty is bool && includeEmpty,
      enabled: enabled && understood,
      sortOrder: sortOrder,
      isReadable: understood,
    );
  }

  /// [raw] within [cadence]'s range, or the range's first day when absent: a
  /// weekly digest on Monday, a monthly one on the 1st. The decoder's rule
  /// and the planner's, so the two can never read one anchor two ways.
  static int clampAnchor(DigestCadence cadence, int? raw) {
    return switch (cadence) {
      DigestCadence.daily => 0,
      DigestCadence.weekly || DigestCadence.weeklyReport =>
        (raw ?? DateTime.monday).clamp(DateTime.monday, DateTime.sunday),
      DigestCadence.monthly ||
      DigestCadence.monthlyReport => (raw ?? 1).clamp(1, lastMonthAnchor),
    };
  }

  @override
  List<Object?> get props => [
    id,
    name,
    cadence,
    anchor,
    minute,
    leadDays,
    categoryIds,
    includeEmpty,
    enabled,
    sortOrder,
  ];
}
