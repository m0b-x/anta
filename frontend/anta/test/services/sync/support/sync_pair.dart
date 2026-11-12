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
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/share_partner_source.dart';
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
const int syncSchema = DatabaseSchema.syncSchemaVersion;

/// A wire version from before a note's body crossed as chunks — what a
/// test stores as the version a database last ran under when its next run
/// has to send every note again. Never "one below this build's": a later
/// wire changed no body, and a database at the body wire or above re-sends
/// nothing (`DatabaseSchema.bodyWireVersion`).
const int beforeBodyWire = DatabaseSchema.bodyWireVersion - 1;

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
  late final SyncStatusService status = SyncStatusService.detached(db, binding);
  final RecordingSyncApplyHooks hooks = RecordingSyncApplyHooks();
  final ManualSyncScheduler scheduler = ManualSyncScheduler();
  final StreamController<AppUser?> auth = StreamController.broadcast();

  /// Who `currentUser` answers with; a test signs out by setting null.
  AppUser? user;

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
    int schema, {
    String uid = syncUid,
    SharePartnerSource? partners,
  }) : binding = SyncBindingService.detached(db, settings),
       user = AppUser(uid: uid) {
    engine = SyncEngine.detached(
      db: db,
      gateway: gateway,
      binding: binding,
      status: status,
      hooks: hooks,
      deviceId: id,
      schema: schema,
      currentUser: () => user,
      // The `AuthService` contract: the current account first, then every
      // change — so a start meets the replay production hands it (record
      // §13, review 2026-11-09).
      authChanges: Stream<AppUser?>.multi((listener) {
        listener.add(user);
        final changes = auth.stream.listen(
          listener.add,
          onError: listener.addError,
          onDone: listener.close,
        );
        listener.onCancel = changes.cancel;
      }, isBroadcast: true),
      scheduler: scheduler,
      timing: timing,
      tables: tables,
      lifecycleState: () => lifecycleState,
      now: () => now(),
      build: () => build,
      partners: partners,
    );
    _statusSubscription = engine.status.listen(statuses.add);
  }

  /// The engine's wall clock — the quota retry and the full-pull age; a test
  /// pins it on either side of the quota's reset.
  DateTime Function() now = DateTime.now;

  /// The build the engine stores beside its pull parks; a test changes it
  /// between a stop and a start to stand for an update.
  String build = SyncEngine.build;

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

  /// [sync] for a drain cut by bytes, which waits
  /// [SyncEngine.minPartSpacing] between its parts on [scheduler]: the wall
  /// clock stands still, so every wait is the whole spacing, and each is
  /// fired as it comes. Returns how many waits fired with the report.
  Future<(SyncRunReport, int)> syncFiringSpacing() async {
    final clock = now;
    final at = clock();
    now = () => at;
    var done = false;
    var fired = 0;
    final run = sync().whenComplete(() => done = true);
    while (!done) {
      await Future<void>.delayed(Duration.zero);
      fired += scheduler.fire(SyncEngine.minPartSpacing);
    }
    now = clock;
    return (await run, fired);
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
  /// wrapped in a `DriftRemoteException`. [setup] runs on each of those
  /// file connections — a benchmark passes `configureSqliteConnection` to
  /// time the production pragmas; without it the files run SQLite's stock
  /// journal and synchronous modes. [wallAhead] puts the named device's wall
  /// clock that far ahead of the shared one, for a case about a device whose
  /// system clock is wrong. [buildSchema] is the schema both engines run at,
  /// for a case about an older build meeting this build's space, which is
  /// created at [syncSchema] whatever it is. [serverOnDeviceClock] puts the
  /// gateway's server time on the devices' shared clock, for a case that
  /// compares a stamp with the time a push landed.
  static Future<SyncPair> open({
    bool bind = true,
    bool background = false,
    DatabaseSetup? setup,
    SyncEngineTiming timing = const SyncEngineTiming(),
    List<SyncTableBinding<Object>>? tables,
    Map<String, Duration> wallAhead = const {},
    int buildSchema = syncSchema,
    bool serverOnDeviceClock = false,
  }) async {
    final gateway = FakeSyncGateway();
    final clock = _SharedClock();
    if (serverOnDeviceClock) gateway.wallClock = clock.call;
    final files = background
        ? await Directory.systemTemp.createTemp('anta_sync_pair_')
        : null;
    Future<SyncDevice> device(String id) async {
      final statements = StatementCounter();
      final executor = files == null
          ? NativeDatabase.memory()
          : NativeDatabase.createInBackground(
              File('${files.path}/$id.sqlite'),
              setup: setup,
            );
      final ahead = wallAhead[id] ?? Duration.zero;
      final db = AppDatabase.forTesting(
        executor.interceptWith(statements),
        deviceId: id,
        wallClock: () => clock().add(ahead),
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
        buildSchema,
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
  /// - every column the codec leaves out of the data;
  /// - a chunk's stamp: its rows carry the stamp of the note write that
  ///   stored them on each device — a fetched chunk its merged note's, a
  ///   written one the edit's that cut it — and its document is the text
  ///   alone.
  ///
  /// A tombstone carries no data, so the codec alone would call two rows
  /// equal while their columns had diverged — the convergence suite was
  /// blind to exactly that (R103). The stored row stands in for a
  /// tombstone, without the columns a merge is not expected to agree on:
  /// see [_tombstoneColumns].
  static Future<Map<String, String>> snapshot(SyncDevice device) async {
    final rows = <String, String>{};
    for (final binding in syncTableBindings) {
      final synced = syncedTables.singleWhere((t) => t.name == binding.table);
      final keys = [
        for (final row
            in await device.db
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
            ? _tombstoneColumns(row)
            : ({...envelope.data!}..remove(JsonKeys.ownerId));
        final stamp = synced.contentAddressed ? '' : '${envelope.hlc} ';
        rows['${binding.table}/${envelope.rowKey}'] =
            '$stamp${envelope.op.name} ${jsonEncode(data)}';
      }
    }
    return rows;
  }

  /// What a tombstoned row must still hold the same on both devices: every
  /// column but the ones a merge is not asked to converge —
  ///
  /// - `ownerId`, `deviceId` and `version`, left out of a live row's string
  ///   for the same reasons;
  /// - `deletedAt`, which the deleting device takes from `DateTime.now()`
  ///   and every merging one reconstructs from the stamp's wall time, and
  ///   `updatedAt`, which a merged tombstone dates at that same instant;
  /// - a note's `contentLength`, `chunkCount` and `isCompressed`, derived
  ///   from a body the deleting device dropped and the merging one never
  ///   received — §3.4 (4) has a tombstone write the stamps and the
  ///   deletion and keep the rest, so these stay where each device had
  ///   them.
  ///
  /// What is left is what a tombstoned row must still agree on: the data
  /// the two devices both saw while it was alive.
  static Map<String, Object?> _tombstoneColumns(Object row) {
    const apart = {
      JsonKeys.ownerId,
      'deviceId',
      'version',
      'deletedAt',
      'updatedAt',
      'contentLength',
      'chunkCount',
      'isCompressed',
    };
    final columns = (row as dynamic).toJson() as Map<String, Object?>;
    return {
      for (final entry in columns.entries)
        if (!apart.contains(entry.key)) entry.key: entry.value,
    };
  }
}

/// The account the owner of a [SharePair] is signed in as.
const String ownerUid = 'u1';

/// The account its partner is signed in as.
const String partnerUid = 'u2';

/// The pair the two are in.
const String sharePairId = 'pair-1';

/// A [SharePartnerSource] a test answers for: which pair each account is in
/// on the server, and whether its database says it is paired at all.
class FakePartners implements SharePartnerSource {
  /// What the server says, by account; an account with no entry has no
  /// active pair.
  final Map<String, SharePartner> pairs = {};

  /// The accounts whose own database says they are paired.
  final Set<String> local = {};

  /// When set, the server cannot be asked: every [activePartner] throws it.
  SyncGatewayException? failure;

  /// Every [activePartner] call's account, in order.
  final List<String> asked = [];

  @override
  Future<bool> pairedLocally(String uid) async => local.contains(uid);

  @override
  Future<SharePartner?> activePartner(String uid) async {
    asked.add(uid);
    final failed = failure;
    if (failed != null) throw failed;
    return pairs[uid];
  }
}

/// Two accounts, paired, each with one device bound to a space of its own,
/// over one fake gateway whose server clock is the devices' — the reader's
/// side of sharing (`docs/cloud-sharing-foundations.md` §5–§7). [owner]
/// shares; [partner] reads.
class SharePair {
  final FakeSyncGateway gateway;
  final FakePartners partners;
  final SyncDevice owner;
  final SyncDevice partner;
  final SyncSpaceRef ownerSpace;
  final SyncSpaceRef partnerSpace;

  SharePair._(
    this.gateway,
    this.partners,
    this.owner,
    this.partner,
    this.ownerSpace,
    this.partnerSpace,
  );

  static Future<SharePair> open() async {
    final gateway = FakeSyncGateway();
    final clock = _SharedClock();
    gateway.wallClock = clock.call;
    final partners = FakePartners();
    Future<SyncDevice> device(String id, String uid) async {
      final statements = StatementCounter();
      final db = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(statements),
        deviceId: id,
        wallClock: clock.call,
      );
      await db.customSelect('SELECT 1').get();
      SettingsService.reset();
      return SyncDevice._(
        id,
        db,
        statements,
        SettingsService.forTesting(db),
        gateway,
        const SyncEngineTiming(),
        null,
        syncSchema,
        uid: uid,
        partners: partners,
      );
    }

    final owner = await device('A', ownerUid);
    final partner = await device('B', partnerUid);
    Future<SyncSpaceRef> spaceOf(SyncDevice device, String uid) async {
      final space = (await gateway.createSpace(
        ownerUid: uid,
        name: 'Main',
        deviceId: device.id,
        schema: syncSchema,
      )).ref;
      await device.binding.bind(space: space, accountUid: uid);
      return space;
    }

    final pair = SharePair._(
      gateway,
      partners,
      owner,
      partner,
      await spaceOf(owner, ownerUid),
      await spaceOf(partner, partnerUid),
    );
    pair.join();
    return pair;
  }

  /// Makes the two accounts a pair, on the server and in what each database
  /// says of itself; [pairId] names it.
  void join({String pairId = sharePairId}) {
    gateway.pair(pairId, ownerUid, partnerUid);
    partners.pairs[ownerUid] = SharePartner(
      pairId: pairId,
      partnerUid: partnerUid,
    );
    partners.pairs[partnerUid] = SharePartner(
      pairId: pairId,
      partnerUid: ownerUid,
    );
    partners.local.addAll([ownerUid, partnerUid]);
  }

  /// Ends the pair [pairId] on the server; each device learns of it at its
  /// next shared read.
  void end({String pairId = sharePairId}) {
    gateway.endPair(pairId);
    partners.pairs.clear();
  }

  /// Runs the owner's sync, then the partner's: what the owner shared is in
  /// its space, and the partner has read it.
  Future<void> syncBoth() async {
    await owner.sync();
    await partner.sync();
  }

  Future<void> close() async {
    await owner._close();
    await partner._close();
    SettingsService.reset();
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
