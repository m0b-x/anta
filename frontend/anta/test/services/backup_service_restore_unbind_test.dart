// An isolate-backed file database: the calendar round trip's slowest case
// ran 14 s in its own file and past 30 s under whole-suite load.
@Timeout(Duration(minutes: 2))
library;

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
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/alert_gateway.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/database_replacing.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/services/sync/sync_space_service.dart';
import 'package:anta/services/sync/sync_suspension.dart';

import '../support/fake_sync_gateway.dart';
import 'support/backup_archive.dart';

/// Records whether sync was suspended each time the restore's reconcile
/// reaches the platform — the last step inside the restore.
class _SuspensionProbeGateway extends NoOpAlertGateway {
  final List<bool> suspended = [];

  /// Whether the marker another isolate reads stood at the same moments.
  final List<bool> replacing = [];

  @override
  Future<String> refreshArmContext() async {
    suspended.add(SyncSuspension.isSuspended);
    replacing.add(await DatabaseReplacing.standing());
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
    final archive = jsonEncode(await exportBackupArchive());
    gateway.suspended.clear();
    gateway.replacing.clear();
    expect(await DatabaseReplacing.standing(), isFalse);

    final result = await backup.importFromJson(archive);

    expect(result.success, isTrue, reason: result.error);
    // The check's own isolate reads no static of this one: the restore
    // stood the marker for it, and took it off as it ended.
    expect(gateway.replacing, isNotEmpty);
    expect(gateway.replacing, everyElement(isTrue));
    expect(await DatabaseReplacing.standing(), isFalse);
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
    final counters = await CounterService.getInstance();
    final laps = await counters.addCounter(name: 'Laps');
    final backup = await BackupService.getInstance();
    final data = await exportBackupArchive();
    data['folders'] = [
      {JsonKeys.id: 'f1', JsonKeys.name: 'Restored'},
    ];
    data['notes'] = [
      {JsonKeys.folderId: 'f1', JsonKeys.title: 'Kept', JsonKeys.content: 'a'},
    ];
    data['publicHolidays'] = [];
    // A database error in the last section, after the folder and the note
    // were written: the holiday wipe meets a row the trigger will not
    // delete, and the transaction rolls back. (A null title is refused
    // before the unbind, and a bad row is skipped.)
    await (await PublicHolidayService.getInstance()).addCustom(
      DateTime.utc(2026, 5, 5),
      'Kept holiday',
    );
    await db.customStatement(
      'CREATE TEMP TRIGGER unbind_fault BEFORE DELETE ON public_holidays '
      "BEGIN SELECT RAISE(ABORT, 'unbind fault'); END",
    );
    addTearDown(() => db.customStatement('DROP TRIGGER unbind_fault'));
    // A tap still pending: the restore's flush writes it after the unbind and
    // before the transaction, so the rollback cannot take its queue entry
    // back — only the clear can.
    await counters.incrementGlobal(laps);
    var notified = 0;
    final sub = CalendarEventService.externalChanges.listen((_) => notified++);
    addTearDown(sub.cancel);

    final result = await backup.importFromJson(jsonEncode(data));
    await pumpEventQueue();

    expect(result.success, isFalse);
    expect(result.error, contains('unbind fault'));
    expect(await (await SyncBindingService.getInstance()).read(), isNull);
    expect(await db.syncOutboxDao.count(), 0);
    final tap = (await db.counterDao.getAllValues()).singleWhere(
      (v) => v.counterId == laps && v.noteId.isEmpty,
    );
    final floor = await db.syncDao.getValue(SyncDao.keyBindFloor);
    expect(floor, isNotNull);
    expect(
      floor!.compareTo(tap.hlcTimestamp),
      greaterThanOrEqualTo(0),
      reason: 'the flushed tap stands at or below the floor',
    );
    expect(
      floor.compareTo((await db.syncOutboxDao.maxHlc())!),
      greaterThanOrEqualTo(0),
    );
    expect(SyncSuspension.isSuspended, isFalse);
    expect(notified, 1);
  });

  test('a restore releases the install registry\'s claim, and the bind is '
      'offered again (record §3.6)', () async {
    final db = await AppDatabase.getInstance();
    final gateway = FakeSyncGateway();
    final spaces = SyncSpaceService(gateway: gateway);
    final space = await gateway.createSpace(
      ownerUid: 'account-1',
      name: 'Phone',
      deviceId: 'other-device',
      schema: DatabaseSchema.syncSchemaVersion,
    );
    await db.folderDao.createFolder(name: 'Errands');
    await spaces.bindExisting(space.ref, accountUid: 'account-1');
    final registry = (await DatabaseManager.getInstance()).spaceRegistry;
    expect(registry.claims(), hasLength(1));
    final backup = await BackupService.getInstance();
    final archive = jsonEncode(await exportBackupArchive());

    final result = await backup.importFromJson(archive);

    expect(result.success, isTrue, reason: result.error);
    expect(registry.claims(), isEmpty);
    expect(
      await spaces.start(accountUid: 'account-1'),
      SyncBindStartPick(spaces: [space], holdsData: true),
    );
  });

  test('an archive never pairs or binds the database it lands on', () async {
    final db = await AppDatabase.getInstance();
    final backup = await BackupService.getInstance();
    // The last pair this database was in (share surfaces D38) is a pairing
    // row: in no export, and written back by no restore.
    await db.userSettingsDao.setValue(SettingsKeys.pairingLastPair, 'here');
    final data = await exportBackupArchive();
    expect(
      (data['settings'] as Map<String, dynamic>).keys,
      isNot(contains(SettingsKeys.pairingLastPair)),
    );
    (data['settings'] as Map<String, dynamic>).addAll({
      SettingsKeys.pairingPairId: 'pair-from-elsewhere',
      SettingsKeys.pairingLastPair: 'pair-from-elsewhere',
      SettingsKeys.syncSpaceId: 'space-from-elsewhere',
      'restore_probe': 'kept',
    });

    final result = await backup.importFromJson(jsonEncode(data));

    expect(result.success, isTrue, reason: result.error);
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.pairingPairId),
      isNull,
    );
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.pairingLastPair),
      isNot('pair-from-elsewhere'),
    );
    expect(await db.userSettingsDao.getValue(SettingsKeys.syncSpaceId), isNull);
    expect(await db.userSettingsDao.getValue('restore_probe'), 'kept');
  });
}
