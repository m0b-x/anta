import 'dart:convert';

import 'package:equatable/equatable.dart';

import '../constants/calendar_categories.dart';
import '../constants/settings_keys.dart';
import 'event_alert.dart';

/// The JSON keys the payload round-trips through.
///
/// Short, because the whole map is handed to the platform as one string and
/// two backends copy it verbatim through a reboot; and spelled once, because
/// the alarm page decodes what the scheduler encoded across a process death
/// and a drifting key would show a blank page rather than fail.
abstract final class AlertPayloadKeys {
  static const String database = 'db';
  static const String eventId = 'eventId';
  static const String alertId = 'alertId';
  static const String dayUtcMs = 'dayUtcMs';
  static const String osId = 'osId';
  static const String mode = 'mode';
  static const String title = 'title';
  static const String timeLabel = 'timeLabel';
  static const String colorValue = 'colorValue';
  static const String tintIcon = 'tintIcon';
  static const String iconKey = 'iconKey';
  static const String categoryId = 'categoryId';
  static const String removeAfterAlert = 'removeAfterAlert';
  static const String snooze = 'snooze';
  static const String snoozeMinutes = 'snoozeMin';
  static const String notice = 'notice';
  static const String excerpt = 'excerpt';
  static const String fireAt = 'fireAt';
  static const String reRing = 'reRing';
  static const String whenLabel = 'when';
  static const String tintValue = 'tint';
  static const String glyphKey = 'glyph';
  static const String languageCode = 'lang';
  static const String iconFile = 'iconFile';
  static const String grouped = 'grp';
  static const String isDigest = 'dg';
  static const String digestId = 'di';
  static const String spanStartMs = 'ss';
  static const String spanEndMs = 'se';
  static const String categoryIds = 'cat';
  static const String digestText = 'dtx';
  static const String digestLines = 'dln';
  static const String digestSummary = 'dsm';
  static const String inherited = 'inh';
}

/// Everything a ring needs to draw itself, carried by the platform entry.
///
/// **Self-describing on purpose.** The alarm page renders from this alone and
/// never opens a database: an alarm that belongs to a database the user is not
/// currently in still has to show a title, a colour and a time (**A9**), and a
/// ring recovered after a reboot arrives in a process where nothing is loaded
/// yet. Reading the event instead would make both cases blank.
///
/// [database] is what scopes reconcile: a platform entry whose payload names
/// another database is never cancelled and never re-registered, so switching
/// databases cannot silently disarm the alarms of the one left behind.
///
/// [timeLabel] is formatted **at schedule time, on the UI thread**. The app
/// never sets `Intl.defaultLocale`, so formatting a time in a background
/// isolate — which is where a notification action runs — would render in the
/// system locale rather than the app's.
///
/// **Everything from [fireAtMs] down is optional, for good.** Those fields
/// are left out of the wire form while they say nothing, and every reader
/// keeps what it did before they existed: an entry of another database and a
/// standing snooze are never re-armed, so a payload written without them can
/// ring years after the build that wrote it is gone.
class AlertPayload extends Equatable {
  /// Active database name at schedule time.
  final String database;

  final String eventId;
  final String alertId;

  /// The occurrence day this fire belongs to, date-only UTC as epoch ms.
  final int dayUtcMs;

  /// The id the platform holds this entry under.
  final int osId;

  final AlertMode mode;

  final String title;

  /// Wall-clock label of the fire instant, pre-formatted on the clock the
  /// phone was on when the entry was armed. A notification names the alarm's
  /// own time with it, and the event's wherever [whenLabel] is empty; the
  /// alarm page draws it only for an entry that carries no [fireAtMs].
  final String timeLabel;

  /// The event's own colour override, or null to resolve from the category.
  final int? colorValue;

  /// Whether [colorValue] also tints the icon — the rule every in-app icon
  /// surface applies, carried so the alarm page and the notification agree
  /// with them. Absent in entries written before it existed, which read as
  /// the model's own default.
  final bool tintIcon;

  /// The event's own icon override, or null for the category's icon.
  final String? iconKey;

  final String categoryId;

  /// Whether acknowledging this alert deletes the event (**A3**).
  final bool removeAfterAlert;

  /// Whether this entry is a snooze rather than the planned occurrence.
  final bool snooze;

  /// How many minutes Snooze postpones this alert by.
  ///
  /// Carried rather than looked up because the reminder tier's Snooze action
  /// runs in a **background isolate**: it has no database, no settings service
  /// and no facade, and re-schedules from this map alone.
  final int snoozeMinutes;

  /// The first line of the event's description, stripped of markdown and
  /// capped (OS-4) — the line a notification adds under its text when it is
  /// expanded, and the alarm page's second row.
  /// Stamped at schedule time on the UI isolate like [timeLabel], so nothing
  /// that posts from a payload has to open a database to draw it. Empty when
  /// the event has no description.
  final String excerpt;

  /// Whether this entry is the alarm's upcoming notice (OS-3) rather than the
  /// alarm itself. The notice carries its alarm's payload — that is what lets
  /// Skip and Open name the right occurrence — so this is the one field that
  /// tells the two apart when the notification id is not to hand.
  final bool notice;

  /// The instant this entry is due, as epoch milliseconds, or null on an
  /// entry armed before the field existed.
  ///
  /// [timeLabel] says the same thing as text frozen in one clock style and
  /// one language; this is what lets a surface with a context write the time
  /// and its day the way the phone does now. It also tells a ring that was
  /// moved from one that was not: the platform reports the instant it really
  /// rang at, and only a stamped payload has something to compare it with.
  final int? fireAtMs;

  /// Whether this process saw the platform move this ring by a Snooze taken
  /// on its notification.
  ///
  /// The one honest source for "snoozed" on a ring the app did not snooze
  /// itself: [snooze] is true for every test ring and false for a native
  /// snooze, and a moved instant alone is also what a ring the platform
  /// deferred looks like. Set on the ring report, never armed into an entry.
  final bool reRing;

  /// The event's own time as a line — "18:00 – 19:30", "18:00", "All day" —
  /// with its day when the occurrence is not on the day the entry is due.
  ///
  /// **Empty when it would only repeat the due time**, which is the everyday
  /// alert at the event's start: a caption reading what the clock above it
  /// already reads is noise. Empty on an older entry too, where the event's
  /// time is simply not known; [languageCode] is what tells the two apart.
  final String whenLabel;

  /// The colour the event's avatar wears, by the one icon rule, resolved
  /// when the entry was armed — or null for [iconColorValue] over the
  /// category's colour, as before.
  ///
  /// Carried because the category facade is empty wherever no database is
  /// open: in the background isolate, and for another database's alarm.
  final int? tintValue;

  /// The icon key the event's avatar draws, resolved when the entry was
  /// armed — or null for [iconKey], then the category's, as before.
  final String? glyphKey;

  /// The language every string in this payload was written in, or null on an
  /// older entry — which a reader with no settings to ask answers with the
  /// device's language, as it always has.
  final String? languageCode;

  /// Where the rendered avatar is kept for a notification's large icon, or
  /// null for none.
  ///
  /// Stamped by the platform binding into a **reminder's** entry alone, when
  /// it is armed: a reminder's Snooze re-posts it from a background isolate
  /// that can hand a path on and cannot draw. Every other notification is
  /// posted where the binding can find the file, or draw it, by itself.
  final String? iconFile;

  /// Whether this entry's notification was armed in the app's own group
  /// (`kAlertGroupKey`), which a reminder's is on Android 16 and above.
  ///
  /// Stamped by the platform binding beside [iconFile], and for the same
  /// reader: the isolate that re-posts a snoozed reminder cannot ask the
  /// platform which Android it is running on, so the entry says which shape
  /// it was armed in and comes back in that one. False on every other entry
  /// and on an older one, which is the loose notification both always were.
  final bool grouped;

  /// Whether this entry is a digest (**v42**) — one notification listing a
  /// span's events — rather than an alert of one event. A digest carries no
  /// event ([eventId] is `''`), [alertId] is the digest's id, [dayUtcMs] the
  /// span's first day; its tap opens the overview on the span.
  final bool isDigest;

  /// The digest this entry was armed for, or null on every alert's entry.
  final String? digestId;

  /// The span a digest lists, inclusive, each a date-only UTC day as epoch
  /// ms — what its tap opens the overview on. Null on every alert's entry.
  final int? spanStartMs;
  final int? spanEndMs;

  /// The categories a digest lists, comma-separated; null or empty for every
  /// category, as the overview reads an empty allowlist.
  final String? categoryIdsCsv;

  /// A digest's collapsed line, written at arm time on the UI isolate like
  /// every other label — a digest's words are a list of days no field could
  /// carry unwritten.
  final String? digestText;

  /// A digest's expanded lines, one occurrence each; empty on every alert's
  /// entry.
  final List<String> digestLines;

  /// The note under [digestLines] ("+2 more"), or null for none.
  final String? digestSummary;

  /// Whether the alert this entry was armed for is inherited from the
  /// event's category (**v42**) rather than the event's own. [categoryId] is
  /// the event's category either way, so only this says it; a snooze taken
  /// from the payload alone — the reminder's, in the background isolate —
  /// seeds its id with the event when it is set, as the scheduler does,
  /// because one category alert is shared by every event in the category.
  final bool inherited;

  const AlertPayload({
    required this.database,
    required this.eventId,
    required this.alertId,
    required this.dayUtcMs,
    required this.osId,
    required this.mode,
    required this.title,
    required this.timeLabel,
    this.colorValue,
    this.tintIcon = true,
    this.iconKey,
    required this.categoryId,
    this.removeAfterAlert = false,
    this.snooze = false,
    this.snoozeMinutes = SettingsKeys.defaultAlertSnoozeMinutes,
    this.notice = false,
    this.excerpt = '',
    this.fireAtMs,
    this.reRing = false,
    this.whenLabel = '',
    this.tintValue,
    this.glyphKey,
    this.languageCode,
    this.iconFile,
    this.grouped = false,
    this.isDigest = false,
    this.digestId,
    this.spanStartMs,
    this.spanEndMs,
    this.categoryIdsCsv,
    this.digestText,
    this.digestLines = const <String>[],
    this.digestSummary,
    this.inherited = false,
  });

  /// The event id a **test alarm** carries (§5.7's `Test alarm in 10 s`).
  ///
  /// A sentinel rather than a flag of its own: a test ring has no event, no
  /// alert row and no occurrence, so every consumer that resolves one already
  /// has to cope with finding nothing. The alarm page reads [isTest] to title
  /// itself, and the scheduler records the registration as a snooze so the
  /// diff — which owns only what the plan produced — leaves it alone.
  static const String testEventId = '__anta_test_alarm__';

  /// Whether this is the settings page's test ring rather than a real alert.
  bool get isTest => eventId == testEventId;

  /// The occurrence day, rebuilt as the date-only UTC day it was stored as.
  DateTime get dayUtc => DateTime.fromMillisecondsSinceEpoch(
    dayUtcMs,
    isUtc: true,
  );

  bool get isAlarm => mode == AlertMode.ring;

  /// The categories a digest lists — empty for every category.
  Set<String> get categoryIdSet => {
    for (final id in (categoryIdsCsv ?? '').split(','))
      if (id.isNotEmpty) id,
  };

  /// The colour the payload's icon wears, by the one icon rule: its own
  /// colour only while it tints the icon, else the category's.
  int iconColorValue(int categoryColorValue) {
    final own = colorValue;
    return own != null && tintIcon ? own : categoryColorValue;
  }

  AlertPayload copyWith({
    int? osId,
    String? timeLabel,
    bool? snooze,
    bool? removeAfterAlert,
    int? snoozeMinutes,
    bool? notice,
    int? fireAtMs,
    bool? reRing,
    String? whenLabel,
    int? tintValue,
    String? glyphKey,
    String? languageCode,
    String? iconFile,
    bool? grouped,
    bool? inherited,
  }) {
    return AlertPayload(
      database: database,
      eventId: eventId,
      alertId: alertId,
      dayUtcMs: dayUtcMs,
      osId: osId ?? this.osId,
      mode: mode,
      title: title,
      timeLabel: timeLabel ?? this.timeLabel,
      colorValue: colorValue,
      tintIcon: tintIcon,
      iconKey: iconKey,
      categoryId: categoryId,
      removeAfterAlert: removeAfterAlert ?? this.removeAfterAlert,
      snooze: snooze ?? this.snooze,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      notice: notice ?? this.notice,
      excerpt: excerpt,
      fireAtMs: fireAtMs ?? this.fireAtMs,
      reRing: reRing ?? this.reRing,
      whenLabel: whenLabel ?? this.whenLabel,
      tintValue: tintValue ?? this.tintValue,
      glyphKey: glyphKey ?? this.glyphKey,
      languageCode: languageCode ?? this.languageCode,
      iconFile: iconFile ?? this.iconFile,
      grouped: grouped ?? this.grouped,
      isDigest: isDigest,
      digestId: digestId,
      spanStartMs: spanStartMs,
      spanEndMs: spanEndMs,
      categoryIdsCsv: categoryIdsCsv,
      digestText: digestText,
      digestLines: digestLines,
      digestSummary: digestSummary,
      inherited: inherited ?? this.inherited,
    );
  }

  Map<String, dynamic> toJson() => {
    AlertPayloadKeys.database: database,
    AlertPayloadKeys.eventId: eventId,
    AlertPayloadKeys.alertId: alertId,
    AlertPayloadKeys.dayUtcMs: dayUtcMs,
    AlertPayloadKeys.osId: osId,
    AlertPayloadKeys.mode: mode.name,
    AlertPayloadKeys.title: title,
    AlertPayloadKeys.timeLabel: timeLabel,
    AlertPayloadKeys.colorValue: colorValue,
    AlertPayloadKeys.tintIcon: tintIcon,
    AlertPayloadKeys.iconKey: iconKey,
    AlertPayloadKeys.categoryId: categoryId,
    AlertPayloadKeys.removeAfterAlert: removeAfterAlert,
    AlertPayloadKeys.snooze: snooze,
    AlertPayloadKeys.snoozeMinutes: snoozeMinutes,
    AlertPayloadKeys.notice: notice,
    if (excerpt.isNotEmpty) AlertPayloadKeys.excerpt: excerpt,
    if (fireAtMs != null) AlertPayloadKeys.fireAt: fireAtMs,
    if (reRing) AlertPayloadKeys.reRing: true,
    if (whenLabel.isNotEmpty) AlertPayloadKeys.whenLabel: whenLabel,
    if (tintValue != null) AlertPayloadKeys.tintValue: tintValue,
    if (glyphKey != null) AlertPayloadKeys.glyphKey: glyphKey,
    if (languageCode != null) AlertPayloadKeys.languageCode: languageCode,
    if (iconFile != null) AlertPayloadKeys.iconFile: iconFile,
    if (grouped) AlertPayloadKeys.grouped: true,
    if (isDigest) AlertPayloadKeys.isDigest: true,
    if (digestId != null) AlertPayloadKeys.digestId: digestId,
    if (spanStartMs != null) AlertPayloadKeys.spanStartMs: spanStartMs,
    if (spanEndMs != null) AlertPayloadKeys.spanEndMs: spanEndMs,
    if (categoryIdsCsv != null) AlertPayloadKeys.categoryIds: categoryIdsCsv,
    if (digestText != null) AlertPayloadKeys.digestText: digestText,
    if (digestLines.isNotEmpty) AlertPayloadKeys.digestLines: digestLines,
    if (digestSummary != null) AlertPayloadKeys.digestSummary: digestSummary,
    if (inherited) AlertPayloadKeys.inherited: true,
  };

  /// Decodes one payload, or `null` when the map carries no usable identity.
  ///
  /// Everything but the four identity fields falls back to a default rather
  /// than rejecting the entry: an entry written by a newer build, or one whose
  /// title the platform truncated, is still an alarm that has to be stoppable.
  /// A digest's identity has no event, so its empty [eventId] is the one
  /// that is accepted.
  static AlertPayload? fromJson(Map<String, dynamic> map) {
    final database = map[AlertPayloadKeys.database];
    final eventId = map[AlertPayloadKeys.eventId];
    final alertId = map[AlertPayloadKeys.alertId];
    final osId = map[AlertPayloadKeys.osId];
    final dayUtcMs = map[AlertPayloadKeys.dayUtcMs];
    final isDigest = map[AlertPayloadKeys.isDigest] == true;
    if (database is! String || database.isEmpty) return null;
    if (eventId is! String || (eventId.isEmpty && !isDigest)) return null;
    if (alertId is! String || alertId.isEmpty) return null;
    if (osId is! int || dayUtcMs is! int) return null;
    return AlertPayload(
      database: database,
      eventId: eventId,
      alertId: alertId,
      dayUtcMs: dayUtcMs,
      osId: osId,
      mode: AlertMode.fromName(map[AlertPayloadKeys.mode] as String?),
      title: map[AlertPayloadKeys.title] is String
          ? map[AlertPayloadKeys.title] as String
          : '',
      timeLabel: map[AlertPayloadKeys.timeLabel] is String
          ? map[AlertPayloadKeys.timeLabel] as String
          : '',
      colorValue: map[AlertPayloadKeys.colorValue] is int
          ? map[AlertPayloadKeys.colorValue] as int
          : null,
      tintIcon: map[AlertPayloadKeys.tintIcon] is bool
          ? map[AlertPayloadKeys.tintIcon] as bool
          : true,
      iconKey: map[AlertPayloadKeys.iconKey] is String
          ? map[AlertPayloadKeys.iconKey] as String
          : null,
      // The same fallback every other unresolvable category id takes, rather
      // than a second literal that could drift from it.
      categoryId: map[AlertPayloadKeys.categoryId] is String
          ? map[AlertPayloadKeys.categoryId] as String
          : CalendarCategories.fallback.id,
      removeAfterAlert:
          map[AlertPayloadKeys.removeAfterAlert] == true,
      snooze: map[AlertPayloadKeys.snooze] == true,
      snoozeMinutes: map[AlertPayloadKeys.snoozeMinutes] is int
          ? (map[AlertPayloadKeys.snoozeMinutes] as int).clamp(
              SettingsKeys.minAlertSnoozeMinutes,
              SettingsKeys.maxAlertSnoozeMinutes,
            )
          : SettingsKeys.defaultAlertSnoozeMinutes,
      notice: map[AlertPayloadKeys.notice] == true,
      excerpt: map[AlertPayloadKeys.excerpt] is String
          ? map[AlertPayloadKeys.excerpt] as String
          : '',
      fireAtMs: map[AlertPayloadKeys.fireAt] is int
          ? map[AlertPayloadKeys.fireAt] as int
          : null,
      reRing: map[AlertPayloadKeys.reRing] == true,
      whenLabel: map[AlertPayloadKeys.whenLabel] is String
          ? map[AlertPayloadKeys.whenLabel] as String
          : '',
      tintValue: map[AlertPayloadKeys.tintValue] is int
          ? map[AlertPayloadKeys.tintValue] as int
          : null,
      glyphKey: map[AlertPayloadKeys.glyphKey] is String
          ? map[AlertPayloadKeys.glyphKey] as String
          : null,
      languageCode: map[AlertPayloadKeys.languageCode] is String
          ? map[AlertPayloadKeys.languageCode] as String
          : null,
      iconFile: map[AlertPayloadKeys.iconFile] is String
          ? map[AlertPayloadKeys.iconFile] as String
          : null,
      grouped: map[AlertPayloadKeys.grouped] == true,
      isDigest: isDigest,
      digestId: map[AlertPayloadKeys.digestId] is String
          ? map[AlertPayloadKeys.digestId] as String
          : null,
      spanStartMs: map[AlertPayloadKeys.spanStartMs] is int
          ? map[AlertPayloadKeys.spanStartMs] as int
          : null,
      spanEndMs: map[AlertPayloadKeys.spanEndMs] is int
          ? map[AlertPayloadKeys.spanEndMs] as int
          : null,
      categoryIdsCsv: map[AlertPayloadKeys.categoryIds] is String
          ? map[AlertPayloadKeys.categoryIds] as String
          : null,
      digestText: map[AlertPayloadKeys.digestText] is String
          ? map[AlertPayloadKeys.digestText] as String
          : null,
      digestLines: map[AlertPayloadKeys.digestLines] is List
          ? List<String>.unmodifiable(
              (map[AlertPayloadKeys.digestLines] as List).whereType<String>(),
            )
          : const <String>[],
      digestSummary: map[AlertPayloadKeys.digestSummary] is String
          ? map[AlertPayloadKeys.digestSummary] as String
          : null,
      inherited: map[AlertPayloadKeys.inherited] == true,
    );
  }

  /// The wire form the platform stores.
  String encode() => jsonEncode(toJson());

  /// Inverse of [encode]. Returns `null` for anything that is not a JSON
  /// object carrying an identity — a truncated or foreign payload must read as
  /// "not ours" rather than throw inside a notification callback.
  static AlertPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  @override
  List<Object?> get props => [
    database,
    eventId,
    alertId,
    dayUtcMs,
    osId,
    mode,
    title,
    timeLabel,
    colorValue,
    tintIcon,
    iconKey,
    categoryId,
    removeAfterAlert,
    snooze,
    snoozeMinutes,
    notice,
    excerpt,
    fireAtMs,
    reRing,
    whenLabel,
    tintValue,
    glyphKey,
    languageCode,
    iconFile,
    grouped,
    isDigest,
    digestId,
    spanStartMs,
    spanEndMs,
    categoryIdsCsv,
    digestText,
    digestLines,
    digestSummary,
    inherited,
  ];
}
