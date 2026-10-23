import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/services/sync/sync_suspension.dart';

/// Records whether sync was suspended each time the restore's reconcile
/// reaches the platform — the last step inside the restore.
class _SuspensionProbeGateway extends NoOpAlertGateway {
  final List<bool> suspended = [];

  @override
  Future<String> refreshArmContext() async {
    suspended.add(SyncSuspension.isSuspended);
    return backendName;
  }

  @override
  Future<List<PendingAlertEntry>> pendingEntries() async {
    suspended.add(SyncSuspension.isSuspended);
    return const [];
  }
}

/// Guards the restore's unbind (D9, D15): a backup restored onto a bound
/// database leaves it unbound, with an empty queue and a floor above every
/// stamp the restore wrote, and no archive can bind or pair the database it
/// is restored onto.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final gateway = _SuspensionProbeGateway();

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_restore_unbind');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    GetIt.I.registerSingleton<CounterService>(
      await CounterService.getInstance(),
    );
    GetIt.I.registerSingleton<AlertGateway>(gateway);
  });

  tearDownAll(() async {
    await GetIt.I.reset();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  const binding = SyncBinding(
    spaceId: 'space-1',
    ownerUid: 'owner-1',
    accountUid: 'account-1',
  );

  Future<void> insertEvent(AppDatabase db, String id) {
    final now = DateTime.now();
    return db.calendarEventDao.upsert(
      CalendarEventsCompanion.insert(
        id: id,
        title: 'Leg day',
        category: 'gym',
        startDate: DateTime.utc(2026, 1, 1),
        ruleKind: 'daily',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('a restore leaves the database unbound, unqueued and floored', () async {
    final db = await AppDatabase.getInstance();
    await (await SettingsService.getInstance()).setSyncBinding(binding);
    await db.folderDao.createFolder(name: 'Errands');
    await insertEvent(db, 'e1');
    expect(await db.syncOutboxDao.count(), greaterThan(0));
    final backup = await BackupService.getInstance();
    final archive = jsonEncode(await backup.exportAllData());
    gateway.suspended.clear();

    final result = await backup.importFromJson(archive);

    expect(result.success, isTrue, reason: result.error);
    expect(await (await SyncBindingService.getInstance()).read(), isNull);
    expect(await db.userSettingsDao.getValue(SettingsKeys.syncSpaceId), isNull);
    expect(await db.syncOutboxDao.count(), 0);
    final floor = await db.syncDao.getValue(SyncDao.keyBindFloor);
    expect(floor, isNotNull);
    expect(
      floor!.compareTo((await db.syncOutboxDao.maxHlc())!),
      greaterThanOrEqualTo(0),
    );
    // Every stamp the import minted is at or below the stored clock.
    expect(floor, await db.syncDao.getValue(SyncDao.keyLastHlc));
    expect(SyncSuspension.isSuspended, isFalse);
    expect(gateway.suspended, isNotEmpty);
    expect(gateway.suspended, everyElement(isTrue));
  });

  test('a restore failing after the unbind leaves nothing queued above '
      'the floor', () async {
    final db = await AppDatabase.getInstance();
    await (await SettingsService.getInstance()).setSyncBinding(binding);
    final backup = await BackupService.getInstance();
    final data = await backup.exportAllData();
    data['folders'] = [
      {JsonKeys.id: 'f1', JsonKeys.name: 'Restored'},
    ];
    // The second note's null title throws halfway, after the first note and
    // the folder were written.
    data['notes'] = [
      {JsonKeys.folderId: 'f1', JsonKeys.title: 'Kept', JsonKeys.content: 'a'},
      {JsonKeys.folderId: 'f1', JsonKeys.title: null, JsonKeys.content: 'b'},
    ];
    var notified = 0;
    final sub = CalendarEventService.externalChanges.listen((_) => notified++);
    addTearDown(sub.cancel);

    final result = await backup.importFromJson(jsonEncode(data));
    await pumpEventQueue();

    expect(result.success, isFalse);
    expect(await (await SyncBindingService.getInstance()).read(), isNull);
    expect(await db.syncOutboxDao.count(), 0);
    final floor = await db.syncDao.getValue(SyncDao.keyBindFloor);
    expect(floor, isNotNull);
    expect(
      floor!.compareTo((await db.syncOutboxDao.maxHlc())!),
      greaterThanOrEqualTo(0),
    );
    expect(SyncSuspension.isSuspended, isFalse);
    expect(notified, 1);
  });

  test('an archive never pairs or binds the database it lands on', () async {
    final db = await AppDatabase.getInstance();
    final backup = await BackupService.getInstance();
    final data = await backup.exportAllData();
    (data['settings'] as Map<String, dynamic>).addAll({
      SettingsKeys.pairingPairId: 'pair-from-elsewhere',
      SettingsKeys.syncSpaceId: 'space-from-elsewhere',
      'restore_probe': 'kept',
    });

    final result = await backup.importFromJson(jsonEncode(data));

    expect(result.success, isTrue, reason: result.error);
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.pairingPairId),
      isNull,
    );
    expect(await db.userSettingsDao.getValue(SettingsKeys.syncSpaceId), isNull);
    expect(await db.userSettingsDao.getValue('restore_probe'), 'kept');
  });
}
