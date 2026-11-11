import 'package:anta/core/qa/qa_alert_quiet.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

AlertPayload _payload(String database, int osId) => AlertPayload(
  database: database,
  eventId: 'e$osId',
  alertId: 'a$osId',
  dayUtcMs: 1789862400000,
  osId: osId,
  mode: AlertMode.ring,
  title: 'Test alarm',
  timeLabel: '18:00',
  categoryId: 'gym',
);

/// A binding holding [entries], ringing [rings], recording each cancel.
class _HoldingGateway extends NoOpAlertGateway {
  _HoldingGateway({this.entries = const [], this.rings = const {}});

  final List<PendingAlertEntry> entries;
  final Set<int> rings;
  final List<int> cancelled = [];

  @override
  Set<int> get ringingIds => rings.difference(cancelled.toSet());

  @override
  Future<List<PendingAlertEntry>> pendingEntries() async => entries;

  @override
  Future<void> cancel(int osId) async => cancelled.add(osId);
}

void main() {
  late List<ShownNotification> dismissed;

  Future<String> quiet(
    _HoldingGateway gateway, {
    List<ShownNotification> shown = const [],
  }) => quietQaAlerts(
    gateway: gateway,
    databaseName: 'qa',
    shown: () async => shown,
    dismiss: (n) async => dismissed.add(n),
  );

  setUp(() => dismissed = []);

  test('a ring in progress is stopped, and leaves the plugin with it', () async {
    // The ring of a pass that died: its row went with the database, so the
    // reconcile leaves it sounding; only this ends it.
    final gateway = _HoldingGateway(
      entries: [(osId: 7, payload: _payload('qa', 7))],
      rings: {7},
    );
    final line = await quiet(gateway);
    expect(gateway.cancelled, [7]);
    expect(gateway.ringingIds, isEmpty);
    expect(
      line,
      'stopped 1 ring(s), cancelled 0 alarm(s), took down 0 notification(s)',
    );
  });

  test('stored entries of the QA database go; the owner\'s stay', () async {
    final gateway = _HoldingGateway(
      entries: [
        (osId: 1, payload: _payload('qa', 1)),
        (osId: 2, payload: _payload('gym_notes', 2)),
        (osId: 3, payload: _payload('qa', 3)),
      ],
    );
    final line = await quiet(gateway);
    expect(gateway.cancelled, [1, 3]);
    expect(line, startsWith('stopped 0 ring(s), cancelled 2 alarm(s)'));
  });

  test('only the QA database\'s alert notifications are taken down', () async {
    final ours = (id: 11, tag: null, payload: _payload('qa', 11).encode());
    final owners = (
      id: 12,
      tag: null,
      payload: _payload('gym_notes', 12).encode(),
    );
    const foreign = (id: 13, tag: 'x', payload: 'not an alert');
    final line = await quiet(
      _HoldingGateway(),
      shown: [ours, owners, foreign],
    );
    expect(dismissed, [ours]);
    expect(line, endsWith('took down 1 notification(s)'));
  });
}
