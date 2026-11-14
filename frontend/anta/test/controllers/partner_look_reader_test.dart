import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/controllers/partner_look_reader.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';

import '../database/support/db_test_support.dart';
import '../services/pairing_support.dart';
import '../support/fake_share_service.dart';

/// The ends of the reader's waits (`docs/cloud-share-surfaces-roadmap.md`
/// §16.9 B1, B2): a partner's folder page holds its first frame on
/// [PartnerLookReader.pending], so a read that fails or never answers must
/// end it; and a page asks [PartnerLookReader.start] on every build, so a
/// start that failed must not be asked again by the reader's own notify.
void main() {
  const audience = ShareAudience(
    id: 'pair-1',
    displayName: 'Maria',
    members: [AppUser(uid: 'maria', displayName: 'Maria')],
  );

  late Future<ShareService> Function() open;

  setUp(() {
    open = PartnerLookReader.openService;
    ShareService.publishLookForTesting(null);
  });

  tearDown(() => PartnerLookReader.openService = open);

  group('the hold (B1)', () {
    test('a look read that fails ends it, and says so', () async {
      PartnerLookReader.openService = () async => _Looks(
        audience,
        () => Future<ShareLook>.error(StateError('settings')),
      );
      final reader = PartnerLookReader();
      var told = 0;
      reader.addListener(() => told++);

      reader.start();
      expect(reader.pending, isTrue);
      await pumpEventQueue();

      expect(reader.pending, isFalse);
      expect(reader.value, isNull);
      expect(told, greaterThan(0), reason: 'the page must rebuild');
      reader.dispose();
    });

    test('a look read that never answers ends it at the bound', () {
      fakeAsync((async) {
        final never = Completer<ShareLook>();
        PartnerLookReader.openService = () async =>
            _Looks(audience, () => never.future);
        final reader = PartnerLookReader();
        var told = 0;
        reader.addListener(() => told++);

        reader.start();
        async.flushMicrotasks();
        async.elapse(
          AppConstants.partnerLookHoldLimit - const Duration(milliseconds: 1),
        );
        expect(reader.pending, isTrue);
        async.elapse(const Duration(milliseconds: 1));

        expect(reader.pending, isFalse);
        expect(told, greaterThan(0), reason: 'the page must rebuild');
        reader.dispose();
      });
    });

    test('a look that lands in time ends it with the look, and leaves no '
        'timer behind', () {
      fakeAsync((async) {
        PartnerLookReader.openService = () async =>
            FakeShareService(availability: const ShareReady(audience));
        final reader = PartnerLookReader()..start();
        async.flushMicrotasks();

        expect(reader.pending, isFalse);
        expect(reader.value?.name, 'Maria');
        expect(async.pendingTimers, isEmpty);
        reader.dispose();
      });
    });
  });

  group('a failed start (B2)', () {
    late int opens;

    setUp(() {
      opens = 0;
      // A reader that asks again on its own notify asks thousands of times
      // a second, each logged with its stack: past a few asks the service
      // never answers, which parks it, so a regression fails the count
      // instead of exhausting the VM.
      PartnerLookReader.openService = () async {
        opens++;
        if (opens > 5) return Completer<ShareService>().future;
        await Future<void>.delayed(Duration.zero);
        throw StateError('ShareService is not configured');
      };
    });

    test('is not asked again by the rebuild its own notify causes', () async {
      final reader = PartnerLookReader();
      // What the page's listener and builder do: rebuild, and start again.
      reader.addListener(reader.start);

      reader.start();
      await pumpEventQueue(times: 40);

      expect(opens, 1);
      expect(reader.pending, isFalse);
      reader.dispose();
    });

    test('is asked again by a new page state', () async {
      final reader = PartnerLookReader();
      // The page's rebuild asks with the state it builds from.
      var state = 'state 1';
      reader.addListener(() => reader.start(asker: state));

      reader.start(asker: state);
      await pumpEventQueue(times: 40);
      expect(opens, 1);

      state = 'state 2';
      reader.start(asker: state);
      await pumpEventQueue(times: 40);
      expect(opens, 2);
      reader.dispose();
    });

    test(
      'is asked again by a database switch, and by a pairing change',
      () async {
        final db = await openTestDatabase();
        addTearDown(() async {
          PairingService.reset();
          await db.close();
        });
        final reader = PartnerLookReader();
        reader.addListener(reader.start);

        reader.start();
        await pumpEventQueue(times: 40);
        expect(opens, 1);

        // Unpaired in memory before and after: only the database moved.
        expect(PairingService.pairedInMemory, isNull);
        DatabaseLifecycle.notifyDatabaseSwitching();
        reader.start();
        await pumpEventQueue(times: 40);
        expect(opens, 2, reason: 'a database switch');

        final settings = SettingsService.forTesting(db);
        await settings.setPairingSettings(
          const PairingSettings(pairId: 'pair-1', accountUid: 'me'),
        );
        await PairingService.forTesting(
          auth: FakeAuthService(user: const AppUser(uid: 'me')),
          gateway: FakePairingGateway(),
          settings: settings,
        );
        expect(PairingService.pairedInMemory, isTrue);
        reader.start();
        await pumpEventQueue(times: 40);
        expect(opens, 3, reason: 'a pairing change');
        reader.dispose();
      },
    );
  });
}

/// A share service paired with [audience] whose look read is [read].
class _Looks extends FakeShareService {
  _Looks(ShareAudience audience, this.read)
    : super(availability: ShareReady(audience));

  final Future<ShareLook> Function() read;

  @override
  Future<ShareLook> looks() => read();
}
