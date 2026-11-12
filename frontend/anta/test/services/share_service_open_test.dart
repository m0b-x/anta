import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';

import 'pairing_support.dart';

/// "This database syncs", each ask parked until the test answers it, and
/// every listener of [changes] counted.
class _GatedSyncSource implements ShareSyncSource {
  final List<Completer<bool>> asks = [];
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int listening = 0;

  @override
  Future<bool> syncing() {
    final answer = Completer<bool>();
    asks.add(answer);
    return answer.future;
  }

  @override
  Future<bool> offline() async => false;

  @override
  Stream<void> get runsEnded => const Stream<void>.empty();

  @override
  Stream<void> get changes => Stream<void>.multi((controller) {
    listening++;
    final subscription = _changes.stream.listen(controller.add);
    controller.onCancel = () {
      listening--;
      return subscription.cancel();
    };
  });
}

/// `ShareService.getInstance` is generation-safe to its end (review finding
/// 2 of slice A): an open overtaken by another publishes nothing and leaves
/// nothing listening.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _GatedSyncSource sync;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_share_open');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    SharedPreferences.setMockInitialValues({'active_database': 'one'});
    DatabaseManager.resetForTesting();
    await DatabaseManager.getInstance();
  });

  setUp(() async {
    sync = _GatedSyncSource();
    final settings = await SettingsService.getInstance();
    await settings.setPairingSettings(
      const PairingSettings(
        pairId: 'pair-1',
        accountUid: 'me',
        partnerUid: 'maria-uid',
        partnerName: 'Maria',
      ),
    );
    ShareService.configure(
      ShareServiceWiring(
        pairing: () async => PairingService.forTesting(
          auth: FakeAuthService(user: const AppUser(uid: 'me')),
          gateway: FakePairingGateway(),
          settings: await SettingsService.getInstance(),
        ),
        sync: sync,
        markFolder: (_, _) async => false,
        foldersChanged: () {},
        requestRun: () async {},
        requestSharedRead: () async {},
      ),
    );
  });

  tearDown(() {
    ShareService.reset();
    ShareService.configure(null);
    PairingService.reset();
  });

  tearDownAll(() async {
    SettingsService.reset();
    await AppDatabase.deleteAllData();
    AppDatabase.resetSwitchAnnouncementForTesting();
    DatabaseManager.resetForTesting();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> parkedAt(int asks) async {
    for (var turn = 0; turn < 100 && sync.asks.length < asks; turn++) {
      await pumpEventQueue();
    }
    expect(sync.asks, hasLength(asks));
  }

  test('an open overtaken by a reset and a newer open is disposed, never '
      'published over the one that won', () async {
    final first = ShareService.getInstance();
    await parkedAt(1);

    // What a reset does while an open is in flight: the next caller starts
    // an open of its own rather than joining the first.
    ShareService.reset();
    final second = ShareService.getInstance();
    await parkedAt(2);

    sync.asks[1].complete(true);
    final winner = await second;
    sync.asks[0].complete(true);
    final loser = await first;

    expect(identical(loser, winner), isTrue);
    expect(identical(await ShareService.getInstance(), winner), isTrue);
    expect(sync.listening, 1, reason: 'only the published service listens');
    expect(winner.availability, isA<ShareReady>());
  });

  test('a first evaluation that throws publishes nothing and leaves nothing '
      'listening; the next open starts afresh', () async {
    final opening = ShareService.getInstance();
    await parkedAt(1);
    sync.asks[0].completeError(StateError('the binding was not read'));

    await expectLater(opening, throwsStateError);
    expect(sync.listening, 0);

    final retry = ShareService.getInstance();
    await parkedAt(2);
    sync.asks[1].complete(false);
    final share = await retry;

    expect(share.availability, isA<ShareNotSyncing>());
    expect(sync.listening, 1);
  });
}
