import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import 'package:anta/constants/json_keys.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/synced_tables.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/sync_status_service.dart';
import 'package:anta/services/sync/sync_table_binding.dart';
import 'package:anta/services/sync/sync_tables.dart';

import '../../../database/support/db_test_support.dart';
import '../../../support/fake_sync_gateway.dart';
import '../../../support/manual_sync_scheduler.dart';
import '../../../support/recording_sync_apply_hooks.dart';

/// The account both devices are signed in as, and the space's owner.
const String syncUid = 'u1';

/// This build's schema, as the engines report it to the space.
const int syncSchema = 43;

/// One wall clock for both databases that moves a millisecond on every
/// read, so every stamp either device mints sorts after every stamp minted
/// before it — the tests decide who wrote last by the order they write in.
class _SharedClock {
  int _ms = DateTime.utc(2026, 10, 24, 8).millisecondsSinceEpoch;

  DateTime call() => DateTime.fromMillisecondsSinceEpoch(++_ms);
}

/// One device of a sync test: its database, the services the engine reads
/// through, the recorder of its hooks, its scheduler and its engine.
class SyncDevice {
  final String id;
  final AppDatabase db;
  final StatementCounter statements;
  final SettingsService settings;
  final SyncBindingService binding;
  late final SyncStatusService status = SyncStatusService.detached(
    db,
    binding,
  );
  final RecordingSyncApplyHooks hooks = RecordingSyncApplyHooks();
  final ManualSyncScheduler scheduler = ManualSyncScheduler();
  final StreamController<AppUser?> auth = StreamController.broadcast();

  /// Who `currentUser` answers with; a test signs out by setting null.
  AppUser? user = const AppUser(uid: syncUid);

  /// What the app's lifecycle reads as when the engine starts; null, as with
  /// no binding, leaves the foreground to the lifecycle calls.
  AppLifecycleState? lifecycleState;

  /// Every status the engine emitted, in order.
  final List<SyncStatus> statuses = [];
  late final SyncEngine engine;
  late final StreamSubscription<SyncStatus> _statusSubscription;

  SyncDevice._(
    this.id,
    this.db,
    this.statements,
    this.settings,
    FakeSyncGateway gateway,
    SyncEngineTiming timing,
    List<SyncTableBinding<Object>>? tables,
  ) : binding = SyncBindingService.detached(db, settings) {
    engine = SyncEngine.detached(
      db: db,
      gateway: gateway,
      binding: binding,
      status: status,
      hooks: hooks,
      deviceId: id,
      schema: syncSchema,
      currentUser: () => user,
      authChanges: auth.stream,
      scheduler: scheduler,
      timing: timing,
      tables: tables,
      lifecycleState: () => lifecycleState,
    );
    _statusSubscription = engine.status.listen(statuses.add);
  }

  /// Runs "Sync now" and waits until the engine is idle again and its last
  /// status has reached [statuses].
  Future<SyncRunReport> sync() async {
    final report = await engine.syncNow();
    await engine.whenIdle;
    await Future<void>.delayed(Duration.zero);
    return report;
  }

  /// Lets a signal or a timer callback reach the engine, then waits for
  /// whatever it started.
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await engine.whenIdle;
  }

  Future<void> _close() async {
    await engine.dispose();
    await _statusSubscription.cancel();
    await auth.close();
    await db.close();
  }
}

/// Two devices, one fake gateway, one space owned by [syncUid].
class SyncPair {
  final FakeSyncGateway gateway;
  final SyncSpaceRef space;
  final SyncDevice a;
  final SyncDevice b;

  /// The files of a [open] with `background: true`, deleted by [close].
  final Directory? _files;

  SyncPair._(this.gateway, this.space, this.a, this.b, this._files);

  /// Opens both databases and creates the space; binds both unless [bind]
  /// is false, for a test that writes before the bind. [tables] replaces
  /// both engines' table bindings, for a test that wraps one to make its
  /// merge fail. [background] opens each database on a file in its own
  /// isolate, as the app does, where a SQLite error reaches the engine
  /// wrapped in a `DriftRemoteException`.
  static Future<SyncPair> open({
    bool bind = true,
    bool background = false,
    SyncEngineTiming timing = const SyncEngineTiming(),
    List<SyncTableBinding<Object>>? tables,
  }) async {
    final gateway = FakeSyncGateway();
    final clock = _SharedClock();
    final files = background
        ? await Directory.systemTemp.createTemp('anta_sync_pair_')
        : null;
    Future<SyncDevice> device(String id) async {
      final statements = StatementCounter();
      final executor = files == null
          ? NativeDatabase.memory()
          : NativeDatabase.createInBackground(File('${files.path}/$id.sqlite'));
      final db = AppDatabase.forTesting(
        executor.interceptWith(statements),
        deviceId: id,
        wallClock: clock.call,
      );
      await db.customSelect('SELECT 1').get();
      // forTesting hands out the singleton: reset it so the second device
      // gets its own settings over its own database (record, S3a as built).
      SettingsService.reset();
      final settings = SettingsService.forTesting(db);
      return SyncDevice._(
        id,
        db,
        statements,
        settings,
        gateway,
        timing,
        tables,
      );
    }

    final a = await device('A');
    final b = await device('B');
    final space = (await gateway.createSpace(
      ownerUid: syncUid,
      name: 'Main',
      deviceId: 'A',
      schema: syncSchema,
    )).ref;
    final pair = SyncPair._(gateway, space, a, b, files);
    if (bind) {
      await pair.bind(a);
      await pair.bind(b);
    }
    return pair;
  }

  Future<void> bind(SyncDevice device) =>
      device.binding.bind(space: space, accountUid: syncUid);

  Future<void> close() async {
    await a._close();
    await b._close();
    SettingsService.reset();
    await _files?.delete(recursive: true);
  }

  /// Every synced row of [device] as the push would send it, keyed
  /// `table/rowKey`: stamp, operation and data — nothing else, so two
  /// devices compare equal while they differ in:
  ///
  /// - `ownerId`, dropped from the data: a row written after the bind is
  ///   unowned where it was written and owned by the account where it was
  ///   merged, the same owner either way (the envelope carries it);
  /// - the envelope's `deviceId` and `version`, left out of the string;
  /// - every column the codec leaves out of the data.
  static Future<Map<String, String>> snapshot(SyncDevice device) async {
    final rows = <String, String>{};
    for (final binding in syncTableBindings) {
      final synced = syncedTables.singleWhere((t) => t.name == binding.table);
      final keys = [
        for (final row in await device.db
            .customSelect(
              'SELECT ${synced.rowKeySql} AS k FROM ${binding.table}',
            )
            .get())
          row.read<String>('k'),
      ];
      if (keys.isEmpty) continue;
      for (final row in await binding.loadByKeys(device.db, keys)) {
        final envelope = await binding.encode(
          device.db,
          row,
          boundUid: syncUid,
        );
        final data = envelope.data == null
            ? null
            : ({...envelope.data!}..remove(JsonKeys.ownerId));
        rows['${binding.table}/${envelope.rowKey}'] =
            '${envelope.hlc} ${envelope.op.name} ${jsonEncode(data)}';
      }
    }
    return rows;
  }
}

/// A note written as the storage service writes one: the preview derived
/// from the body, as the merge derives it on the other device.
Future<Note> writeNote(
  SyncDevice device, {
  required String folderId,
  required String title,
  required String body,
}) {
  return device.db.noteDao.createNote(
    folderId: folderId,
    title: title,
    preview: NoteMetadata.generatePreview(body),
    content: body,
  );
}

/// An auto-save of [body] over the note [id], preview derived likewise.
Future<void> editNote(SyncDevice device, String id, String body) {
  return device.db.noteDao.updateNote(
    id: id,
    preview: NoteMetadata.generatePreview(body),
    content: body,
  );
}

/// A live folder envelope as another client would push it.
SyncEnvelope folderEnvelope(
  String id,
  String hlc, {
  String name = 'Pushed',
  String deviceId = 'C',
  bool deleted = false,
  Map<String, Object?>? data,
}) {
  return SyncEnvelope(
    table: 'folders',
    rowKey: id,
    hlc: hlc,
    deviceId: deviceId,
    version: 3,
    op: deleted ? OutboxOp.tombstone : OutboxOp.upsert,
    ownerId: syncUid,
    data: deleted
        ? null
        : data ??
              {
                JsonKeys.id: id,
                JsonKeys.name: name,
                JsonKeys.parentId: null,
                'position': 0,
                'createdAtMs': 0,
                'updatedAtMs': 0,
                JsonKeys.noteSortOrder: null,
                JsonKeys.subfolderSortOrder: null,
                JsonKeys.label: ItemLabel.none.storageName,
              },
  );
}

/// A one-time-a-day event as the calendar's editor would store it.
CalendarEventsCompanion eventRow(String id, {String title = 'Leg day'}) {
  return CalendarEventsCompanion.insert(
    id: id,
    title: title,
    category: 'gym',
    startDate: DateTime.utc(2026, 1, 1),
    ruleKind: 'daily',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

/// The built-in birthday category as the seed writes it.
CalendarCategoriesCompanion birthdayCategory({String name = 'Birthday'}) {
  return CalendarCategoriesCompanion(
    id: const Value('birthday'),
    name: Value(name),
    colorValue: const Value(0xFFE91E63),
    iconKey: const Value('cake'),
    isBuiltIn: const Value(true),
    createdAt: Value(DateTime.utc(2026, 1, 1)),
    updatedAt: Value(DateTime.utc(2026, 1, 1)),
  );
}
