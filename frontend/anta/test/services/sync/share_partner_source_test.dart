import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/share_partner_source.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/utils/pairing_error.dart';

import '../../database/support/db_test_support.dart';
import '../pairing_support.dart';

/// Who an account shares with, as the reader of shared rows asks it
/// (`docs/cloud-sharing-foundations.md` §5): the server's answer, never the
/// stored one — and "could not be asked" never reads as "nobody".
void main() {
  late AppDatabase db;
  late SettingsService settings;
  late FakePairingGateway gateway;
  late PairingSharePartnerSource source;

  setUp(() async {
    db = await openTestDatabase();
    SettingsService.reset();
    settings = SettingsService.forTesting(db);
    gateway = FakePairingGateway();
    source = PairingSharePartnerSource(
      gateway: gateway,
      settings: () async => settings,
    );
  });

  tearDown(() async {
    SettingsService.reset();
    await db.close();
  });

  test('the partner is the other account of the active pair', () async {
    final pair = gateway.seedPair(['me', 'them']);

    expect(
      await source.activePartner('me'),
      SharePartner(pairId: pair.pairId, partnerUid: 'them'),
    );
    expect(
      await source.activePartner('them'),
      SharePartner(pairId: pair.pairId, partnerUid: 'me'),
    );
  });

  test('no active pair is an answer: null', () async {
    expect(await source.activePartner('me'), isNull);

    final pair = gateway.seedPair(['me', 'them']);
    await gateway.endPair(pairId: pair.pairId, endedBy: 'them');

    expect(await source.activePartner('me'), isNull);
  });

  test('of two active pairs a race left, the earlier one — the one pairing '
      'itself keeps — whichever order the server lists them in', () async {
    final first = gateway.seedPair(['me', 'them']);
    gateway.seedPair(['me', 'another']);

    expect(
      PairingSharePartnerSource.partnerOf(
        gateway.pairs.values.toList().reversed.toList(),
        'me',
      ),
      SharePartner(pairId: first.pairId, partnerUid: 'them'),
    );
  });

  test('a pair that cannot be asked about is never "no pair": the failure '
      'reaches the reader, which then removes nothing', () async {
    gateway.seedPair(['me', 'them']);
    for (final (error, failure) in const [
      (PairingError.offline, SyncGatewayFailure.offline),
      (PairingError.unavailable, SyncGatewayFailure.offline),
      (PairingError.permissionDenied, SyncGatewayFailure.permissionDenied),
      (PairingError.unknown, SyncGatewayFailure.unknown),
    ]) {
      gateway.failNext = error;
      await expectLater(
        source.activePartner('me'),
        throwsA(
          isA<SyncGatewayException>().having(
            (e) => e.failure,
            'failure',
            failure,
          ),
        ),
        reason: error.name,
      );
    }
  });

  test('whether the database says it is paired is its own stored pairing, '
      'for the account asked about only', () async {
    expect(await source.pairedLocally('me'), isFalse);

    await settings.setPairingSettings(
      const PairingSettings(
        pairId: 'pair-1',
        accountUid: 'me',
        partnerUid: 'them',
      ),
    );

    expect(await source.pairedLocally('me'), isTrue);
    expect(await source.pairedLocally('someone-else'), isFalse);
  });

  test('a pair that does not hold the account names no partner, whatever '
      'list it came in', () {
    final stray = PairRecord(
      pairId: 'p',
      members: const ['x', 'y'],
      isActive: true,
      createdAt: DateTime.utc(2026),
    );

    expect(PairingSharePartnerSource.partnerOf([stray], 'me'), isNull);
    expect(
      PairingSharePartnerSource.partnerOf([stray], 'x'),
      const SharePartner(pairId: 'p', partnerUid: 'y'),
    );
  });
}
