import 'package:alarm/alarm.dart';
import 'package:alarm/src/generated/platform_bindings.g.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Callback that is called when an alarm starts ringing.
typedef AlarmRangCallback = void Function(AlarmSettings alarm);

/// Callback that is called when an alarm is stopped.
typedef AlarmStoppedCallback = void Function(int alarmId);

/// Callback that is called when the host changed an alarm on its own.
///
/// Returns a future the host awaits before treating the change as observed, so
/// it must not complete until the change is durably applied. The host keeps its
/// own marker until then, so completing early costs the event rather than
/// duplicating it.
typedef AlarmEventCallback = Future<void> Function(AlarmEvent event);

/// Implements the API that handles calls coming from the host platform.
class AlarmTriggerApiImpl extends AlarmTriggerApi {
  AlarmTriggerApiImpl._({
    required AlarmRangCallback alarmRang,
    required AlarmStoppedCallback alarmStopped,
    required AlarmEventCallback alarmEvent,
  })  : _alarmRang = alarmRang,
        _alarmStopped = alarmStopped,
        _alarmEvent = alarmEvent,
        super() {
    AlarmTriggerApi.setUp(this);
  }

  static final _log = Logger('AlarmTriggerApiImpl');

  /// Cached instance of [AlarmTriggerApiImpl]
  static AlarmTriggerApiImpl? _instance;

  final AlarmRangCallback _alarmRang;

  final AlarmStoppedCallback _alarmStopped;

  final AlarmEventCallback _alarmEvent;

  /// Forgets the cached instance so the next [ensureInitialized] rebuilds it.
  ///
  /// Only for tests: the instance is `??=`-guarded, so without this the
  /// callbacks registered by the first test in a file are the ones every later
  /// test keeps using.
  @visibleForTesting
  static void resetForTesting() => _instance = null;

  /// Ensures that this Dart isolate is listening for method calls that may come
  /// from the host platform.
  static void ensureInitialized({
    required AlarmRangCallback alarmRang,
    required AlarmStoppedCallback alarmStopped,
    required AlarmEventCallback alarmEvent,
  }) {
    _instance ??= AlarmTriggerApiImpl._(
      alarmRang: alarmRang,
      alarmStopped: alarmStopped,
      alarmEvent: alarmEvent,
    );
  }

  @override
  Future<void> alarmRang(int alarmId) async {
    final settings = await Alarm.getAlarm(alarmId);
    if (settings == null) {
      _log.severe('Alarm with id $alarmId started ringing but the settings '
          'object could not be found. Please report this issue at: '
          'https://github.com/gdelataillade/alarm/issues');
      return;
    }
    _log.info('Alarm with id $alarmId started ringing.');
    _alarmRang(settings);
  }

  @override
  Future<void> alarmStopped(int alarmId) async {
    _log.info('Alarm with id $alarmId stopped.');
    _alarmStopped(alarmId);
  }

  @override
  Future<void> alarmEvent(AlarmEventWire event) async {
    final parsed = AlarmEvent.fromWire(event);
    switch (parsed) {
      case AlarmMoved():
        _log.info('Alarm with id ${parsed.id} moved to ${parsed.nextRingAt} '
            '(${parsed.cause.name}).');
      case AlarmDropped():
        _log.info('Alarm with id ${parsed.id} was dropped by the host '
            '(${parsed.cause.name}); it should have rung at '
            '${parsed.scheduledFor}.');
    }
    // Awaited so the reply to the host is sent only once Dart has applied the
    // change. The host uses that reply to decide whether it can drop its own
    // reconciliation marker.
    await _alarmEvent(parsed);
  }
}
