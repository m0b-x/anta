import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/account_closer.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_space_registry.dart';
import 'package:anta/services/sync/sync_space_service.dart';
import 'package:anta/services/sync/sync_suspension.dart';

import '../../database/support/db_test_support.dart';
import '../../support/fake_sync_gateway.dart';

const _uid = 'uid-1';
const _partner = 'uid-2';

Matcher _fails(SyncBindFailure failure) =>
    isA<SyncSpaceException>().having((e) => e.failure, 'failure', failure);

/// The fake, with the spaces a deletion marked in order and a hook before
/// every listing, every mark and every page, where a test scripts a failure
/// — or another device's write, or a wait — mid-job.
class _MarkingGateway extends FakeSyncGateway {
  final List<String> marked = [];
  FutureOr<void> Function(SyncSpaceRef space)? beforeMark;
  FutureOr<void> Function(SyncSpaceRef space, String table)? beforePage;

  /// Called with the listing's number, counted from one over the gateway's
  /// life.
  FutureOr<void> Function(int listing)? beforeList;
  int _listings = 0;

  @override
  Future<List<SyncSpaceInfo>> listSpaces(String ownerUid) async {
    await beforeList?.call(++_listings);
    return super.listSpaces(ownerUid);
  }

  @override
  Future<void> markSpaceDeleted(SyncSpaceRef space) async {
    await beforeMark?.call(space);
    await super.markSpaceDeleted(space);
    marked.add(space.spaceId);
  }

  @override
  Future<int> deleteRows(SyncSpaceRef space, String table, {int? limit}) async {
    await beforePage?.call(space, table);
    return super.deleteRows(space, table, limit: limit);
  }
}

/// The real binding service, with a hook before every read and every unbind.
class _WatchedBinding extends SyncBindingService {
  _WatchedBinding(
    super.db,
    super.settings, {
    super.registry,
    super.databaseName,
  }) : super.detached();

  FutureOr<void> Function()? beforeRead;
  FutureOr<void> Function()? beforeUnbind;

  @override
  Future<SyncBinding?> read() async {
    await beforeRead?.call();
    return super.read();
  }

  @override
  Future<void> unbind({bool raiseFloor = true}) async {
    await beforeUnbind?.call();
    await super.unbind(raiseFloor: raiseFloor);
  }
}

/// Records every account it is asked to close with the spaces that account
/// still had by then, and fails as scripted. Like the real one it asks
/// `stillWanted` once its own work is done, right before the account would
/// go, and is `withdrawn` on a no.
class _RecordingCloser implements AccountCloser {
  _RecordingCloser(this._gateway);

  final FakeSyncGateway _gateway;

  /// The accounts closed, in order.
  final List<String> closed = [];

  /// How many spaces each call found its account still holding.
  final List<int> spacesLeft = [];

  /// What each call was answered when it asked whether the account's own
  /// delete is still wanted.
  final List<bool> wanted = [];

  /// Thrown by the next call when set, then cleared; nothing is closed.
  AccountCloseFailure? failNext;

  /// Held by every call while set, between its start and its question — the
  /// time the real one spends on pairs and invites.
  Completer<void>? hold;

  int calls = 0;

  final StreamController<int> _entered = StreamController<int>.broadcast();

  /// Completes once a call is under way, at its [hold].
  Future<void> entered() => _entered.stream.first;

  @override
  Future<void> close(
    String accountUid, {
    required bool Function() stillWanted,
  }) async {
    calls++;
    spacesLeft.add((await _gateway.listSpaces(accountUid)).length);
    _entered.add(calls);
    await hold?.future;
    final answer = stillWanted();
    wanted.add(answer);
    if (!answer) {
      throw const AccountCloseException(AccountCloseFailure.withdrawn);
    }
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw AccountCloseException(failure);
    }
    closed.add(accountUid);
  }
}

/// "Delete account" (cloud-multi-user-roadmap §6.1): the service's local
/// phase — list → record → mark and record each space, this database's first
/// and unbound — and the end of the account's run, which closes the account
/// only once its last space is gone and only in the process that asked —
/// over an in-memory database bound through the real binding service and the
/// real `DatabaseManager` over a temporary directory.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseManager manager;
  late AppDatabase db;
  late SettingsService settings;
  late _WatchedBinding binding;
  late _MarkingGateway gateway;
  late _RecordingCloser closer;
  late SyncSpaceService service;

  /// The service's clock, moved by hand: a run's licence ages by it.
  late DateTime clock;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_account_delete');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    manager = await DatabaseManager.getInstance();
    await manager.setActiveDatabaseName('training');
    await manager.createDatabase('training');
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  SyncSpaceService serviceOver(AccountCloser? closer) => SyncSpaceService(
    gateway: gateway,
    database: () async => db,
    binding: () async => binding,
    databases: () async => manager,
    closer: closer,
    now: () => clock,
  );

  setUp(() async {
    clock = DateTime.utc(2026, 11, 11, 12);
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    binding = _WatchedBinding(
      db,
      settings,
      registry: manager.spaceRegistry,
      databaseName: 'training',
    );
    gateway = _MarkingGateway();
    closer = _RecordingCloser(gateway);
    service = serviceOver(closer);
  });

  tearDown(() async {
    await service.deletionRunsIdle();
    SettingsService.reset();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(SettingsKeys.syncBoundSpaces);
    await prefs.remove(SettingsKeys.syncPendingDeletions);
    await prefs.remove(SettingsKeys.syncPendingAccountDeletion);
    await db.close();
  });

  SyncSpaceRegistry registry() => manager.spaceRegistry;

  Future<SyncDeletionStatus> status([String account = _uid]) =>
      service.deletionStatus(account);

  /// Every run ended, and what the followed streams were sent delivered.
  Future<void> settled([SyncSpaceService? of]) async {
    await (of ?? service).deletionRunsIdle();
    await pumpEventQueue();
  }

  Future<List<SyncDeletionStatus>> follow([String account = _uid]) async {
    final statuses = <SyncDeletionStatus>[];
    final subscription = service.deletionStatusOf(account).listen(statuses.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    return statuses;
  }

  /// Every account the service names deleted from now on.
  List<String> deletedAccounts([SyncSpaceService? of]) {
    final deleted = <String>[];
    final subscription = (of ?? service).accountsDeleted.listen(deleted.add);
    addTearDown(subscription.cancel);
    return deleted;
  }

  Future<SyncSpaceInfo> createSpace(
    String name, {
    String owner = _uid,
    int schema = DatabaseSchema.syncSchemaVersion,
  }) => gateway.createSpace(
    ownerUid: owner,
    name: name,
    deviceId: 'other-device',
    schema: schema,
  );

  Future<SyncSpaceInfo> boundSpace(String name) async {
    final space = await createSpace(name);
    await binding.bind(space: space.ref, accountUid: _uid);
    return space;
  }

  void plantRows(SyncSpaceInfo space, String table, int count) {
    for (var i = 0; i < count; i++) {
      gateway.plant(
        space.ref,
        SyncEnvelope(
          table: table,
          rowKey: '$table-${i.toString().padLeft(4, '0')}',
          hlc: '000000000001:0000:other-device',
          deviceId: 'other-device',
          version: 1,
          op: OutboxOp.upsert,
          ownerId: space.ref.ownerUid,
          data: const {'name': 'row'},
        ),
      );
    }
  }

  group('deleteAccount', () {
    test(
      'marks every space of the account, empties them, then closes the '
      'account — with none of its spaces left, the record cleared, the '
      'account named; another account\'s space and every local row stay',
      () async {
        await db.folderDao.createFolder(name: 'Errands');
        final phone = await boundSpace('Phone');
        plantRows(phone, 'folders', 30);
        plantRows(phone, 'content_chunks', 45);
        final tablet = await createSpace('Tablet');
        plantRows(tablet, 'notes', 5);
        final theirs = await createSpace('Theirs', owner: _partner);
        plantRows(theirs, 'folders', 2);
        final deleted = deletedAccounts();

        await service.deleteAccount(accountUid: _uid);
        await settled();

        expect(await gateway.listSpaces(_uid), isEmpty);
        expect(await gateway.readSpace(theirs.ref), isNotNull);
        expect(gateway.rowsOf(theirs.ref, 'folders'), hasLength(2));
        expect(closer.closed, [_uid]);
        expect(closer.spacesLeft, [0]);
        expect(deleted, [_uid]);
        expect(registry().pendingAccountDeletion(), isNull);
        expect(registry().pendingDeletions(), isEmpty);
        expect(await binding.read(), isNull);
        expect(
          await status(),
          const SyncDeletionStatus(accountUid: _uid, removed: 80),
        );
        final folders = await db.folderDao.getAllFolders();
        expect(folders.map((f) => f.name), ['Errands']);
        expect(folders.single.ownerId, isNull);
      },
    );

    test('this database\'s own space is marked first and unbound at once, '
        'before any other space is touched', () async {
      await createSpace('Tablet');
      final phone = await boundSpace('Phone');
      await createSpace('Laptop');
      List<String>? markedAtUnbind;
      binding.beforeUnbind = () => markedAtUnbind = List.of(gateway.marked);

      await service.deleteAccount(accountUid: _uid);
      await settled();

      expect(markedAtUnbind, [phone.ref.spaceId]);
      expect(gateway.marked.first, phone.ref.spaceId);
      expect(gateway.marked, hasLength(3));
      expect(closer.closed, [_uid]);
    });

    test('an account with no space at all is closed at once', () async {
      final deleted = deletedAccounts();

      await service.deleteAccount(accountUid: _uid);
      await settled();

      expect(closer.closed, [_uid]);
      expect(deleted, [_uid]);
      expect(await status(), const SyncDeletionStatus(accountUid: _uid));
    });

    test(
      'a database bound to another account\'s space stays bound, and a '
      'space this database syncs with that is already gone is left',
      () async {
        final theirs = await createSpace('Theirs', owner: _partner);
        await binding.bind(space: theirs.ref, accountUid: _partner);
        await createSpace('Phone');

        await service.deleteAccount(accountUid: _uid);
        await settled();

        expect((await binding.read())?.ownerUid, _partner);
        expect(closer.closed, [_uid]);

        await binding.unbind();
        final mine = await boundSpace('Mine');
        gateway.consoleDeleteSpace(mine.ref);
        await service.deleteAccount(accountUid: _uid);
        await settled();
        expect(await binding.read(), isNull);
      },
    );

    test('the status reads the account\'s deletion from the record to the '
        'end: running throughout, then nothing', () async {
      final phone = await boundSpace('Phone');
      plantRows(phone, 'folders', 25);
      final statuses = await follow();
      statuses.clear();

      await service.deleteAccount(accountUid: _uid);
      await settled();

      expect(statuses.first.account, isTrue);
      expect(statuses.first.running, isTrue);
      expect(
        statuses.where((s) => s.account).every((s) => s.running),
        isTrue,
        reason: 'no moment reads as a deletion left waiting',
      );
      expect(
        statuses.last,
        const SyncDeletionStatus(accountUid: _uid, removed: 25),
      );
    });

    group('refused with nothing changed', () {
      Future<void> expectUntouched(SyncSpaceInfo space) async {
        expect(
          (await gateway.readSpace(space.ref))!.markedForDeletion,
          isFalse,
        );
        expect(registry().pendingAccountDeletion(), isNull);
        expect(registry().pendingDeletions(), isEmpty);
        expect(await binding.read(), isNotNull);
        expect(closer.calls, 0);
        expect(await status(), const SyncDeletionStatus(accountUid: _uid));
      }

      test('when the listing fails', () async {
        final phone = await boundSpace('Phone');
        gateway.failNextWith(SyncGatewayFailure.offline);

        await expectLater(
          service.deleteAccount(accountUid: _uid),
          throwsA(_fails(SyncBindFailure.offline)),
        );
        await settled();
        await expectUntouched(phone);
      });

      test('while a restore runs', () async {
        final phone = await boundSpace('Phone');

        await SyncSuspension.run(
          () => expectLater(
            service.deleteAccount(accountUid: _uid),
            throwsA(_fails(SyncBindFailure.suspended)),
          ),
        );
        await settled();
        await expectUntouched(phone);
      });

      test('when a newer build wrote to one of the spaces', () async {
        final phone = await boundSpace('Phone');
        await createSpace(
          'Tablet',
          schema: DatabaseSchema.syncSchemaVersion + 1,
        );

        await expectLater(
          service.deleteAccount(accountUid: _uid),
          throwsA(_fails(SyncBindFailure.appOutdated)),
        );
        await settled();
        await expectUntouched(phone);
      });

      test('where no closer is bound', () async {
        final phone = await boundSpace('Phone');
        final bare = serviceOver(null);

        await expectLater(
          bare.deleteAccount(accountUid: _uid),
          throwsA(_fails(SyncBindFailure.unknown)),
        );
        await expectUntouched(phone);
      });
    });

    test('a failure midway leaves marks and records in step and the account '
        'waiting; asked again, it goes on from there', () async {
      final phone = await boundSpace('Phone');
      final tablet = await createSpace('Tablet');
      final laptop = await createSpace('Laptop');
      gateway.beforeMark = (space) {
        if (space == tablet.ref) {
          throw const SyncGatewayException(SyncGatewayFailure.offline);
        }
      };

      await expectLater(
        service.deleteAccount(accountUid: _uid),
        throwsA(_fails(SyncBindFailure.offline)),
      );
      await settled();

      expect(gateway.marked, [phone.ref.spaceId]);
      expect(await binding.read(), isNull);
      expect(registry().pendingAccountDeletion(), _uid);
      expect(registry().pendingDeletions().map((d) => d.space), [phone.ref]);
      expect((await gateway.readSpace(tablet.ref))!.markedForDeletion, isFalse);
      expect(closer.calls, 0);
      final waiting = await status();
      expect(waiting.account, isTrue);
      expect(waiting.running, isFalse);
      expect(waiting.failure, isNull);
      // Waiting is still going: nothing of the account is bound meanwhile.
      await expectLater(
        service.bindExisting(tablet.ref, accountUid: _uid),
        throwsA(_fails(SyncBindFailure.accountDeleting)),
      );

      gateway.beforeMark = null;
      await service.deleteAccount(accountUid: _uid);
      await settled();

      expect(await gateway.listSpaces(_uid), isEmpty);
      expect(
        gateway.marked,
        containsAll([tablet.ref.spaceId, laptop.ref.spaceId]),
      );
      expect(closer.closed, [_uid]);
      expect(registry().pendingAccountDeletion(), isNull);
    });
  });

  group('closing the account', () {
    test('only a run of the process that asked closes it: a deletion '
        'resumed by a later process finishes the copies and waits', () async {
      final phone = await boundSpace('Phone');
      plantRows(phone, 'folders', 3);
      // As a process killed right after its local phase left it.
      await gateway.markSpaceDeleted(phone.ref);
      await registry().addPendingDeletion(
        SyncPendingDeletion(space: phone.ref, spaceName: 'Phone'),
      );
      await registry().setPendingAccountDeletion(_uid);
      await binding.unbind();

      final accounts = StreamController<String?>();
      addTearDown(accounts.close);
      service.followAccounts(accounts.stream);
      accounts.add(_uid);
      await pumpEventQueue();
      await settled();

      expect(await gateway.readSpace(phone.ref), isNull);
      expect(closer.calls, 0);
      expect(registry().pendingAccountDeletion(), _uid);
      expect(
        await status(),
        const SyncDeletionStatus(accountUid: _uid, removed: 3, account: true),
      );

      // "Finish deleting account": the same call, after a sign-in.
      await service.deleteAccount(accountUid: _uid);
      await settled();
      expect(closer.closed, [_uid]);
      expect(registry().pendingAccountDeletion(), isNull);
    });

    test('a sign-in gone stale by the end is no failure: the account waits, '
        'and the next call closes it', () async {
      await boundSpace('Phone');
      closer.failNext = AccountCloseFailure.recentSignInRequired;
      final deleted = deletedAccounts();

      await service.deleteAccount(accountUid: _uid);
      await settled();

      expect(await gateway.listSpaces(_uid), isEmpty);
      expect(closer.closed, isEmpty);
      expect(deleted, isEmpty);
      expect(
        await status(),
        const SyncDeletionStatus(accountUid: _uid, account: true),
      );

      await service.deleteAccount(accountUid: _uid);
      await settled();
      expect(closer.closed, [_uid]);
      expect(deleted, [_uid]);
    });

    test('a run already emptying a cloud copy when the call is made is '
        'joined, and ends the account too', () async {
      final phone = await boundSpace('Phone');
      plantRows(phone, 'folders', 2);
      final hold = gateway.holdDeleteRows = Completer<void>();
      await service.deleteCloudCopy();
      await pumpEventQueue();
      expect((await status()).running, isTrue);

      await service.deleteAccount(accountUid: _uid);
      gateway.holdDeleteRows = null;
      hold.complete();
      await settled();

      expect(closer.closed, [_uid]);
      expect(await gateway.listSpaces(_uid), isEmpty);
    });

    test(
      'a failed close licenses no later run: a cloud copy deleted '
      'afterwards, in the same process, leaves the account waiting',
      () async {
        await boundSpace('Phone');
        closer.failNext = AccountCloseFailure.offline;
        await service.deleteAccount(accountUid: _uid);
        await settled();
        expect(closer.calls, 1);

        final again = await boundSpace('Again');
        plantRows(again, 'folders', 1);
        await service.deleteCloudCopy();
        await settled();

        expect(await gateway.listSpaces(_uid), isEmpty);
        expect(closer.calls, 1);
        expect((await status()).account, isTrue);
      },
    );

    test(
      'after a stale sign-in no later run closes the account by itself',
      () async {
        await boundSpace('Phone');
        closer.failNext = AccountCloseFailure.recentSignInRequired;
        await service.deleteAccount(accountUid: _uid);
        await settled();

        await service.finishPendingDeletions(accountUid: _uid);
        await settled();

        expect(closer.calls, 1);
        expect((await status()).account, isTrue);
      },
    );

    for (final (failure, shown) in [
      (AccountCloseFailure.offline, SyncBindFailure.offline),
      (AccountCloseFailure.permissionDenied, SyncBindFailure.permissionDenied),
      (AccountCloseFailure.unknown, SyncBindFailure.unknown),
    ]) {
      test('a closer that fails as ${failure.name} is the run\'s failure, '
          'the account still recorded', () async {
        await boundSpace('Phone');
        closer.failNext = failure;

        await service.deleteAccount(accountUid: _uid);
        await settled();

        expect(
          await status(),
          SyncDeletionStatus(accountUid: _uid, failure: shown, account: true),
        );
        expect(registry().pendingAccountDeletion(), _uid);

        await service.deleteAccount(accountUid: _uid);
        await settled();
        expect(closer.closed, [_uid]);
        expect(await status(), const SyncDeletionStatus(accountUid: _uid));
      });
    }

    test('a space made since the call is never marked by the run: the '
        'account waits, and so does every later run of this process', () async {
      final phone = await boundSpace('Phone');
      plantRows(phone, 'folders', 1);
      SyncSpaceInfo? made;
      gateway.beforePage = (space, table) async {
        made ??= await createSpace('Made meanwhile');
      };

      await service.deleteAccount(accountUid: _uid);
      await settled();

      expect(await gateway.readSpace(phone.ref), isNull);
      expect((await gateway.readSpace(made!.ref))!.markedForDeletion, isFalse);
      expect(closer.calls, 0);
      expect(
        await status(),
        const SyncDeletionStatus(accountUid: _uid, removed: 1, account: true),
      );

      // Deleting that copy by hand, later in the same process, is a cloud
      // copy's deletion: it must not take the account with it.
      gateway.beforePage = null;
      await binding.bind(space: made!.ref, accountUid: _uid);
      await service.deleteCloudCopy();
      await settled();
      expect(await gateway.listSpaces(_uid), isEmpty);
      expect(closer.calls, 0);
      expect((await status()).account, isTrue);
    });

    test('a space marked elsewhere since the call is taken like any other, '
        'and the account closed after it', () async {
      final phone = await boundSpace('Phone');
      plantRows(phone, 'folders', 1);
      SyncSpaceInfo? other;
      gateway.beforePage = (space, table) async {
        if (other != null) return;
        final created = other = await createSpace('Marked elsewhere');
        plantRows(created, 'notes', 2);
        await gateway.markSpaceDeleted(created.ref);
      };

      await service.deleteAccount(accountUid: _uid);
      await settled();

      expect(await gateway.listSpaces(_uid), isEmpty);
      expect(closer.closed, [_uid]);
      expect(closer.spacesLeft, [0]);
      expect(
        await status(),
        const SyncDeletionStatus(accountUid: _uid, removed: 3),
      );
    });

    test('a space a newer build wrote to after the mark holds the account: '
        'the run ends as outdated and nothing is closed', () async {
      final phone = await boundSpace('Phone');
      // Raised behind the listing's back, as a newer build's push that
      // landed between the listing and the mark would leave it.
      gateway.beforeMark = (space) => gateway.consoleRestoreSpace(
        phone.ref,
        name: 'Phone',
        deviceId: 'newer-device',
        schema: DatabaseSchema.syncSchemaVersion + 1,
      );

      await service.deleteAccount(accountUid: _uid);
      await settled();

      expect(closer.calls, 0);
      final held = await status();
      expect(held.account, isTrue);
      expect(held.failure, SyncBindFailure.appOutdated);
      expect(held.pending.map((d) => d.space), [phone.ref]);
    });
  });

  group('the window after the sign-in', () {
    const window = SyncSpaceService.accountCloseWindow;
    const justPast = Duration(seconds: 1);

    /// A deletion asked for now, its run held at its first page; the
    /// returned function lets it go on.
    Future<void Function()> heldDeletion() async {
      final phone = await boundSpace('Phone');
      plantRows(phone, 'folders', 2);
      final page = gateway.holdDeleteRows = Completer<void>();
      await service.deleteAccount(accountUid: _uid);
      await pumpEventQueue();
      return () {
        gateway.holdDeleteRows = null;
        page.complete();
      };
    }

    test('at its edge the account is still closed', () async {
      final release = await heldDeletion();
      clock = clock.add(window);
      release();
      await settled();

      expect(closer.closed, [_uid]);
    });

    test('past it the copies are finished and the account waits, with no '
        'failure and its pairs untouched; the next call closes it', () async {
      final release = await heldDeletion();
      clock = clock.add(window + justPast);
      release();
      await settled();

      expect(await gateway.listSpaces(_uid), isEmpty);
      expect(closer.calls, 0);
      expect(
        await status(),
        const SyncDeletionStatus(accountUid: _uid, removed: 2, account: true),
      );

      await service.deleteAccount(accountUid: _uid);
      await settled();
      expect(closer.closed, [_uid]);
    });

    test('it is counted from the call, not from the end of a slow '
        'marking', () async {
      await boundSpace('Phone');
      gateway.beforeMark = (_) {
        clock = clock.add(window + justPast);
      };

      await service.deleteAccount(accountUid: _uid);
      await settled();

      expect(await gateway.listSpaces(_uid), isEmpty);
      expect(closer.calls, 0);
      expect((await status()).account, isTrue);
    });

    test('passing while the closer is at work, it is what the closer hears '
        'right before the account would go', () async {
      await boundSpace('Phone');
      final hold = closer.hold = Completer<void>();
      final entered = closer.entered();
      await service.deleteAccount(accountUid: _uid);
      await entered;

      clock = clock.add(window + justPast);
      hold.complete();
      await settled();

      expect(closer.wanted, [false]);
      expect(closer.closed, isEmpty);
      expect(
        await status(),
        const SyncDeletionStatus(accountUid: _uid, account: true),
      );
    });
  });

  group('a call that overlaps a run', () {
    test('still marking when the run reaches its end, it holds the close: '
        'the account goes by the call\'s own run, once', () async {
      final phone = await boundSpace('Phone');
      plantRows(phone, 'folders', 2);
      final page = gateway.holdDeleteRows = Completer<void>();
      await service.deleteAccount(accountUid: _uid);
      await pumpEventQueue();

      // A second call, stopped between its record and its marks.
      final marking = Completer<void>();
      binding.beforeRead = () => marking.future;
      final second = service.deleteAccount(accountUid: _uid);
      await pumpEventQueue();

      gateway.holdDeleteRows = null;
      page.complete();
      await service.deletionRunsIdle();
      expect(closer.calls, 0, reason: 'never while a call is marking');

      binding.beforeRead = null;
      marking.complete();
      await second;
      await settled();

      expect(closer.closed, [_uid]);
      expect(closer.spacesLeft, [0]);
      expect(registry().pendingAccountDeletion(), isNull);
      expect(registry().pendingDeletions(), isEmpty);
    });

    test('reaching the run while the closer is at work, its licence is not '
        'taken back by that attempt: a sign-in found stale leaves the newer '
        'one, and the run closes under it', () async {
      await boundSpace('Phone');
      final hold = closer.hold = Completer<void>();
      closer.failNext = AccountCloseFailure.recentSignInRequired;
      final entered = closer.entered();
      await service.deleteAccount(accountUid: _uid);
      await entered;

      // "Finish deleting account" after a new sign-in, the first attempt
      // still out.
      closer.hold = null;
      await service.deleteAccount(accountUid: _uid);
      hold.complete();
      await settled();

      expect(closer.calls, 2);
      expect(closer.closed, [_uid]);
      expect(registry().pendingAccountDeletion(), isNull);
    });

    test('a space it records while the closer is at work holds the '
        'account\'s own delete: the closer hears no, the run takes the '
        'space, and closes after it', () async {
      await boundSpace('Phone');
      final hold = closer.hold = Completer<void>();
      final entered = closer.entered();
      await service.deleteAccount(accountUid: _uid);
      await entered;

      // Another device made a copy meanwhile; the second call marks it.
      final made = await createSpace('Made meanwhile');
      plantRows(made, 'notes', 3);
      closer.hold = null;
      await service.deleteAccount(accountUid: _uid);
      hold.complete();
      await settled();

      expect(closer.wanted, [false, true]);
      expect(closer.spacesLeft, [0, 0]);
      expect(closer.closed, [_uid]);
      expect(await gateway.listSpaces(_uid), isEmpty);
      expect(
        await status(),
        const SyncDeletionStatus(accountUid: _uid, removed: 3),
      );
    });
  });

  group('no bind while the account is going', () {
    const refused = SyncBindFailure.accountDeleting;

    test('every way to bind is refused while the record stands, with '
        'nothing made, bound or switched', () async {
      final tablet = await createSpace('Tablet');
      await registry().setPendingAccountDeletion(_uid);

      await expectLater(
        service.start(accountUid: _uid),
        throwsA(_fails(refused)),
      );
      await expectLater(
        service.createAndBind(accountUid: _uid, name: 'New'),
        throwsA(_fails(refused)),
      );
      await expectLater(
        service.bindExisting(tablet.ref, accountUid: _uid),
        throwsA(_fails(refused)),
      );
      await expectLater(
        service.downloadIntoNewDatabase(tablet, accountUid: _uid),
        throwsA(_fails(refused)),
      );

      expect(await gateway.listSpaces(_uid), hasLength(1));
      expect(await binding.read(), isNull);
      expect(manager.getActiveDatabaseName(), 'training');
      expect(await manager.databaseExists('Tablet'), isFalse);
    });

    test('the refusal starts with the record, before the first mark', () async {
      await createSpace('Tablet');
      Object? answer;
      gateway.beforeMark = (_) async {
        try {
          answer = await service.createAndBind(accountUid: _uid, name: 'Late');
        } catch (e) {
          answer = e;
        }
      };

      await service.deleteAccount(accountUid: _uid);
      await settled();

      expect(answer, _fails(refused));
      expect(await binding.read(), isNull);
      expect(closer.closed, [_uid]);
      expect(closer.spacesLeft, [0]);
    });

    test('it ends with the deletion given up', () async {
      await registry().setPendingAccountDeletion(_uid);
      await service.abandonAccountDeletion(_uid);

      final created = await service.createAndBind(
        accountUid: _uid,
        name: 'Phone',
      );

      expect((await binding.read())?.spaceId, created.ref.spaceId);
    });

    test('another account\'s deletion refuses nothing of this one', () async {
      await registry().setPendingAccountDeletion(_partner);

      final created = await service.createAndBind(
        accountUid: _uid,
        name: 'Phone',
      );

      expect((await binding.read())?.spaceId, created.ref.spaceId);
    });
  });

  group('giving the account\'s deletion up', () {
    test('while the copies are being emptied: they are finished, the '
        'account stays, the closer is never called', () async {
      final phone = await boundSpace('Phone');
      plantRows(phone, 'folders', 2);
      final page = gateway.holdDeleteRows = Completer<void>();
      final deleted = deletedAccounts();
      await service.deleteAccount(accountUid: _uid);
      await pumpEventQueue();

      await service.abandonAccountDeletion(_uid);
      gateway.holdDeleteRows = null;
      page.complete();
      await settled();

      expect(await gateway.listSpaces(_uid), isEmpty);
      expect(closer.calls, 0);
      expect(deleted, isEmpty);
      expect(
        await status(),
        const SyncDeletionStatus(accountUid: _uid, removed: 2),
      );
    });

    test('while the closer is at work: asked right before the account '
        'would go, the closer hears no', () async {
      await boundSpace('Phone');
      final hold = closer.hold = Completer<void>();
      final entered = closer.entered();
      final deleted = deletedAccounts();
      await service.deleteAccount(accountUid: _uid);
      await entered;

      await service.abandonAccountDeletion(_uid);
      hold.complete();
      await settled();

      expect(closer.wanted, [false]);
      expect(closer.closed, isEmpty);
      expect(deleted, isEmpty);
      expect(await status(), const SyncDeletionStatus(accountUid: _uid));
    });

    test('and asking again while that run is still out: the later word is '
        'the one that counts', () async {
      await boundSpace('Phone');
      final hold = closer.hold = Completer<void>();
      final entered = closer.entered();
      await service.deleteAccount(accountUid: _uid);
      await entered;

      await service.abandonAccountDeletion(_uid);
      await service.deleteAccount(accountUid: _uid);
      hold.complete();
      await settled();

      expect(closer.wanted, [true]);
      expect(closer.closed, [_uid]);
      expect(registry().pendingAccountDeletion(), isNull);
    });

    test('abandonAccountDeletion drops the account\'s record and leaves its '
        'copies\' records to be finished', () async {
      await boundSpace('Phone');
      closer.failNext = AccountCloseFailure.offline;
      await service.deleteAccount(accountUid: _uid);
      await settled();
      final tablet = await createSpace('Tablet');
      await gateway.markSpaceDeleted(tablet.ref);
      await registry().addPendingDeletion(
        SyncPendingDeletion(space: tablet.ref, spaceName: 'Tablet'),
      );

      await service.abandonAccountDeletion(_uid);

      expect(registry().pendingAccountDeletion(), isNull);
      expect(registry().pendingDeletions().map((d) => d.space), [tablet.ref]);
      expect((await status()).account, isFalse);

      // What is left is a cloud copy's deletion, and ends as one.
      await service.finishPendingDeletions(accountUid: _uid);
      await settled();
      expect(await gateway.listSpaces(_uid), isEmpty);
      expect(closer.calls, 1);
    });

    test('abandoning with nothing recorded, or another account\'s record, '
        'changes nothing', () async {
      await service.abandonAccountDeletion(_uid);
      expect(registry().pendingAccountDeletion(), isNull);

      await registry().setPendingAccountDeletion(_partner);
      await service.abandonAccountDeletion(_uid);
      expect(registry().pendingAccountDeletion(), _partner);
    });

    test('another account signing in drops the record; the same account, '
        'or a sign-out, keeps it', () async {
      await registry().setPendingAccountDeletion(_uid);
      final accounts = StreamController<String?>();
      addTearDown(accounts.close);
      service.followAccounts(accounts.stream);

      accounts.add(_uid);
      await pumpEventQueue();
      expect(registry().pendingAccountDeletion(), _uid);

      accounts.add(null);
      await pumpEventQueue();
      expect(registry().pendingAccountDeletion(), _uid);

      accounts.add(_partner);
      await pumpEventQueue();
      expect(registry().pendingAccountDeletion(), isNull);
      expect((await status()).account, isFalse);
    });
  });
}
