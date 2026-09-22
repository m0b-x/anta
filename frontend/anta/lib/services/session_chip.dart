import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../models/alert_payload.dart';
import '../models/calendar_event.dart';
import '../models/note_metadata.dart';
import '../repositories/note_repository.dart';
import 'alert_gateway.dart';
import 'calendar_event_service.dart';
import 'database_manager.dart';

/// How far a session has run, as the whole percent the platform's progress
/// bar takes, or null when the end is not known — an indeterminate bar.
///
/// Clamped at both ends: a chip posted for an alarm that rang before the
/// occurrence started reads 0 until it does, and one refreshed a moment past
/// the end reads 100 rather than overflowing.
int? sessionProgress({
  required DateTime startedAt,
  required DateTime? endsAt,
  required DateTime now,
}) {
  if (endsAt == null) return null;
  final total = endsAt.difference(startedAt).inMilliseconds;
  if (total <= 0) return 100;
  final elapsed = now.difference(startedAt).inMilliseconds;
  return (elapsed * 100 ~/ total).clamp(0, 100);
}

/// When an occurrence of [event] on [dayUtc] ends, in local time, or null
/// when the event has no duration — an all-day event, or a timed one with no
/// end — in which case the session has no known end either.
///
/// The constructor form, like the planner's fire instant: a minute past
/// midnight is wall-clock time, and adding a `Duration` would land an hour
/// off on the day the clocks change.
DateTime? sessionEndFor(CalendarEvent event, DateTime dayUtc) {
  final endMinute = event.time?.endMinute;
  if (endMinute == null) return null;
  return DateTime(dayUtc.year, dayUtc.month, dayUtc.day, 0, endMinute);
}

/// The note the chip's *Open note* lands on: what an editor needs to open
/// it, or null when the event has no linked note or the note is in the
/// trash.
typedef LinkedSessionNote = ({
  String folderId,
  String noteId,
  NoteMetadata metadata,
});

/// Resolves [event]'s linked note through `getNotesByIds`, the one lookup
/// that leaves tombstones out — the calendar's own rule for a linked note —
/// and carries the metadata the editor seeds its title from.
Future<LinkedSessionNote?> linkedSessionNote(
  CalendarEvent? event,
  NoteRepository notes,
) async {
  final noteId = event?.noteId;
  if (noteId == null) return null;
  final found = await notes.getNotesByIds([noteId]);
  if (found.isEmpty) return null;
  final note = found.first;
  return (
    folderId: note.folderId,
    noteId: note.id,
    metadata: notes.noteToMetadata(note),
  );
}

/// The session chip (**B8**, OS-5): the one ongoing notification that says a
/// session is under way, posted when an alarm is acknowledged and cleared by
/// its Done, by the event's end, or by the next ring.
///
/// A process-global like [AlertRemovalNotice], for the same reason: the
/// acknowledgement reaches it from more than one route for the same ring —
/// the alarm page's Stop and then, when the event is set to be removed, the
/// A3 path it runs next; or a Stop on the platform's own notification and
/// the ring-end settle `main.dart` runs for it, which are concurrent. One
/// chip per ring is this class's job, keyed on the os id; the binding only
/// draws what it is handed.
///
/// Ring tier only, and only for the database that is open: a reminder is not
/// a session, a test alarm is nobody's, and an alarm from *work* stopped
/// while *personal* is open would open the wrong note.
class SessionChip {
  SessionChip();

  static final SessionChip instance = SessionChip();

  /// How often a chip with a known end is re-posted so its progress moves.
  /// The platform draws a static bar; the chronometer under it ticks on its
  /// own, so the refresh only has to keep the two roughly in step.
  static const Duration refreshEvery = Duration(minutes: 1);

  AlertGateway? Function() _gateway = _registeredGateway;
  Future<String?> Function() _activeDatabase = _registeredDatabase;
  Future<CalendarEvent?> Function(String eventId) _findEvent = _registeredEvent;
  DateTime Function() _clock = DateTime.now;

  int? _shownOsId;
  AlertPayload? _payload;
  DateTime? _startedAt;
  DateTime? _endsAt;
  Timer? _endTimer;
  Timer? _refresh;

  /// The os id of the ring the chip on the shade belongs to, or null.
  int? get shownOsId => _shownOsId;

  /// Posts the chip for an acknowledged alarm, once per ring.
  ///
  /// The dedupe is claimed **before** the first await: two routes can
  /// acknowledge the same ring within milliseconds of each other, and a
  /// check that waited for the database would let both through.
  Future<void> show(AlertPayload payload) async {
    if (!payload.isAlarm || payload.isTest) return;
    if (_shownOsId == payload.osId) return;
    final gateway = _gateway();
    if (gateway == null) return;
    final previous = _shownOsId;
    _shownOsId = payload.osId;
    try {
      final database = await _activeDatabase();
      if (database == null || database != payload.database) {
        _shownOsId = previous;
        return;
      }
      final startedAt = _clock();
      final event = await _findEvent(payload.eventId);
      final endsAt = event == null ? null : sessionEndFor(event, payload.dayUtc);
      if (endsAt != null && !endsAt.isAfter(startedAt)) {
        _shownOsId = previous;
        return;
      }
      _cancelTimers();
      _payload = payload;
      _startedAt = startedAt;
      _endsAt = endsAt;
      if (!await _post(gateway)) return;
      if (endsAt != null) {
        _endTimer = Timer(endsAt.difference(startedAt), () => unawaited(clear()));
        _refresh = Timer.periodic(
          refreshEvery,
          (_) => unawaited(_post(gateway, refresh: true)),
        );
      }
    } catch (e) {
      debugPrint('[SessionChip] show failed: $e');
      _shownOsId = previous;
    }
  }

  /// Hands the chip to the platform and answers whether it stands there.
  ///
  /// A refusal ends the chip on this side too: a first post the platform
  /// would not take (notifications off) has nothing to keep alive, and a
  /// refresh refused is a chip the user has already taken down with *Done*
  /// — the receiver runs with no Dart, so this answer is how Dart learns of
  /// it, and re-posting over it would bring back what was dismissed.
  Future<bool> _post(AlertGateway gateway, {bool refresh = false}) async {
    final payload = _payload;
    final startedAt = _startedAt;
    if (payload == null || startedAt == null) return false;
    var standing = false;
    try {
      standing = await gateway.showSessionChip(
        payload,
        startedAt: startedAt,
        endsAt: _endsAt,
        progress: sessionProgress(
          startedAt: startedAt,
          endsAt: _endsAt,
          now: _clock(),
        ),
        refresh: refresh,
      );
    } catch (e) {
      debugPrint('[SessionChip] post failed: $e');
    }
    if (!standing) _forget();
    return standing;
  }

  void _forget() {
    _cancelTimers();
    _shownOsId = null;
    _payload = null;
    _startedAt = null;
    _endsAt = null;
  }

  /// Takes the chip down. Always asks the platform, whatever this process
  /// remembers: a chip posted by the process before this one is on the shade
  /// with nothing here to say so, and the next ring must still clear it.
  Future<void> clear() async {
    _forget();
    final gateway = _gateway();
    if (gateway == null) return;
    try {
      await gateway.clearSessionChip();
    } catch (e) {
      debugPrint('[SessionChip] clear failed: $e');
    }
  }

  void _cancelTimers() {
    _endTimer?.cancel();
    _endTimer = null;
    _refresh?.cancel();
    _refresh = null;
  }

  static AlertGateway? _registeredGateway() =>
      GetIt.I.isRegistered<AlertGateway>() ? GetIt.I<AlertGateway>() : null;

  static Future<String?> _registeredDatabase() async {
    try {
      return (await DatabaseManager.getInstance()).getActiveDatabaseName();
    } catch (e) {
      debugPrint('[SessionChip] active database unknown: $e');
      return null;
    }
  }

  static Future<CalendarEvent?> _registeredEvent(String eventId) async {
    try {
      final service = await CalendarEventService.getInstance();
      for (final event in service.events) {
        if (event.id == eventId) return event;
      }
    } catch (e) {
      debugPrint('[SessionChip] event lookup failed: $e');
    }
    return null;
  }

  /// Swaps every seam for a test double. The chip is a process-global, so a
  /// suite that leaves a gateway behind would post into the next one.
  @visibleForTesting
  void configureForTesting({
    required AlertGateway? Function() gateway,
    required Future<String?> Function() activeDatabase,
    required Future<CalendarEvent?> Function(String eventId) findEvent,
    required DateTime Function() clock,
  }) {
    _gateway = gateway;
    _activeDatabase = activeDatabase;
    _findEvent = findEvent;
    _clock = clock;
  }

  /// Drops the state and restores the production seams.
  @visibleForTesting
  void resetForTesting() {
    _forget();
    _gateway = _registeredGateway;
    _activeDatabase = _registeredDatabase;
    _findEvent = _registeredEvent;
    _clock = DateTime.now;
  }
}
