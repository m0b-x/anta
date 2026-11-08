import 'dart:async';

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_alerts.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/category_alert.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/services/event_alert_service.dart';

import '../database/support/db_test_support.dart';

/// `EventAlertService`'s whole reads build their maps aside and swap them in
/// once, reading again when a write committed under them (scalability
/// record §5.6, S14 part D). The event half used to empty the working copy
/// before the read, so an editor save landing while the rows were in flight
/// was mixed with rows read before it; a swap with no second read would drop
/// that save outright.
void main() {
  late AppDatabase db;
  late _HeldRead gate;
  late EventAlertService service;

  setUp(() async {
    EventAlertService.reset();
    gate = _HeldRead();
    db = await openTestDatabase(interceptor: gate);
    service = await EventAlertService.forTesting(db);
    await service.replaceForEvent('gym', const [
      EventAlert(id: 'old', eventId: 'gym'),
    ]);
    await service.replaceForEvent('swim', const [
      EventAlert(id: 'kept', eventId: 'swim'),
    ]);
    await service.replaceForCategory('work', const [
      CategoryAlert(id: 'old', categoryId: 'work'),
    ]);
  });

  tearDown(() async {
    gate.release();
    EventAlertService.reset();
    await db.close();
  });

  List<String> idsOf(String eventId) => [
    for (final alert in EventAlerts.alertsFor(eventId)) alert.id,
  ];

  List<String> categoryIdsOf(String categoryId) => [
    for (final alert in EventAlerts.categoryAlertsFor(categoryId)) alert.id,
  ];

  test('a save inside a reload is the set the reload ends on', () async {
    gate.hold('"calendar_event_alerts"');
    final reload = service.reload();
    await pumpEventQueue();
    expect(gate.held, isTrue);

    await service.replaceForEvent('gym', const [
      EventAlert(id: 'new', eventId: 'gym'),
    ]);
    expect(idsOf('gym'), ['new']);
    expect(idsOf('swim'), ['kept'], reason: 'nothing emptied mid-read');

    gate.release();
    await reload;

    expect(idsOf('gym'), ['new']);
    expect(idsOf('swim'), ['kept']);
  });

  test(
    'a category save inside a reload is the set the reload ends on',
    () async {
      gate.hold('"calendar_category_alerts"');
      final reload = service.reload();
      await pumpEventQueue();
      expect(gate.held, isTrue);

      await service.replaceForCategory('work', const [
        CategoryAlert(id: 'new', categoryId: 'work'),
      ]);

      gate.release();
      await reload;

      expect(categoryIdsOf('work'), ['new']);
    },
  );

  test('a category tombstoned inside a reload stays gone', () async {
    gate.hold('"calendar_category_alerts"');
    final reload = service.reload();
    await pumpEventQueue();
    expect(gate.held, isTrue);

    await service.tombstoneForCategory('work');

    gate.release();
    await reload;

    expect(categoryIdsOf('work'), isEmpty);
  });
}

/// Hands one whole read's rows back only on [release]: the first `SELECT`
/// naming the held table and ordered (the whole read; a keyed write's own
/// reads are not ordered); one shot.
class _HeldRead extends QueryInterceptor {
  Completer<void>? _hold;
  String? _table;
  bool held = false;

  void hold(String table) {
    _table = table;
    _hold = Completer<void>();
  }

  void release() {
    final hold = _hold;
    _hold = null;
    if (hold != null && !hold.isCompleted) hold.complete();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await super.runSelect(executor, statement, args);
    final hold = _hold;
    final table = _table;
    if (hold != null &&
        !held &&
        table != null &&
        statement.contains(table) &&
        statement.contains('ORDER BY')) {
      held = true;
      await hold.future;
    }
    return rows;
  }
}
