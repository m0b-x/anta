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
    List<ShownNotification> pending = const [],
  }) => quietQaAlerts(
    gateway: gateway,
    databaseName: 'qa',
    shown: () async => shown,
    pending: () async => pending,
    dismiss: (n) async => dismissed.add(n),
  );

  setUp(() => dismissed = []);

  test(
    'a ring in progress is stopped, and leaves the plugin with it',
    () async {
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
    },
  );

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
    final line = await quiet(_HoldingGateway(), shown: [ours, owners, foreign]);
    expect(dismissed, [ours]);
    expect(line, endsWith('took down 1 notification(s)'));
  });

  group('an alarm no list names any more (device leg 3c)', () {
    // The entries leave a notice out — it is its alarm's shadow, not an
    // entry the plan made — so a notice whose alarm the plugin's Dart-side
    // list has lost is cancelled by nothing, while the plugin's native
    // store may still hold that alarm and arm it again. The notice names
    // the alarm's id: both go by it.
    ShownNotification notice(String database, int osId) => (
      id: 9000 + osId,
      tag: null,
      payload: _payload(database, osId).copyWith(notice: true).encode(),
    );

    test('is ended through its notice, and the notice with it — the QA '
        'database\'s alone', () async {
      final gateway = _HoldingGateway();
      final ours = notice('qa', 21);

      final line = await quiet(
        gateway,
        pending: [
          ours,
          notice('gym_notes', 22),
          (id: 23, tag: null, payload: _payload('qa', 23).encode()),
          (id: 24, tag: null, payload: 'not an alert'),
        ],
      );

      expect(gateway.cancelled, [21]);
      expect(dismissed, [ours]);
      expect(
        line,
        'stopped 0 ring(s), cancelled 1 alarm(s), took down 0 '
        'notification(s), 1 alarm(s) named by a notice alone',
      );
    });

    test('one an entry still names, or that rings, is cancelled once', () async {
      final gateway = _HoldingGateway(
        entries: [
          (osId: 21, payload: _payload('qa', 21)),
          (osId: 22, payload: _payload('qa', 22)),
        ],
        rings: {22},
      );

      final line = await quiet(
        gateway,
        pending: [notice('qa', 21), notice('qa', 22)],
      );

      expect(gateway.cancelled, [22, 21]);
      expect(dismissed, isEmpty);
      expect(
        line,
        'stopped 1 ring(s), cancelled 1 alarm(s), took down 0 notification(s)',
      );
    });

    test('a pending list that cannot be read costs the rest nothing', () async {
      final gateway = _HoldingGateway(
        entries: [(osId: 1, payload: _payload('qa', 1))],
      );

      final line = await quietQaAlerts(
        gateway: gateway,
        databaseName: 'qa',
        shown: () async => const [],
        pending: () async => throw StateError('no plugin'),
        dismiss: (n) async => dismissed.add(n),
      );

      expect(gateway.cancelled, [1]);
      expect(line, startsWith('stopped 0 ring(s), cancelled 1 alarm(s)'));
    });
  });

  test('an alarm the plugin\'s own list holds and no entry reports — its '
      'payload reads as no alert of this build — goes too: the list is the '
      'QA namespace\'s, so a QA build armed it; one already cancelled is '
      'not asked twice', () async {
    final gateway = _HoldingGateway(
      entries: [(osId: 1, payload: _payload('qa', 1))],
    );

    final line = await quietQaAlerts(
      gateway: gateway,
      databaseName: 'qa',
      shown: () async => const [],
      pending: () async => const [],
      listed: () async => [1, 31],
      dismiss: (n) async => dismissed.add(n),
    );

    expect(gateway.cancelled, [1, 31]);
    expect(
      line,
      'stopped 0 ring(s), cancelled 2 alarm(s), took down 0 '
      'notification(s), 1 by the plugin\'s list alone',
    );
  });
}
