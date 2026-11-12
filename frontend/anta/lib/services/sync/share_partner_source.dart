import 'package:equatable/equatable.dart';

import '../../models/pair_record.dart';
import '../../utils/pairing_error.dart';
import '../pairing_gateway.dart';
import '../settings_service.dart';
import 'sync_gateway.dart';

/// The pair an account shares within: its id, which a shared row's document
/// names, and the other account in it, whose rows the reader asks for.
class SharePartner extends Equatable {
  final String pairId;
  final String partnerUid;

  const SharePartner({required this.pairId, required this.partnerUid});

  @override
  List<Object?> get props => [pairId, partnerUid];
}

/// Who the bound account is paired with, as the reader of shared rows asks
/// it (`docs/cloud-sharing-foundations.md` §5). A seam, so the engine holds
/// no pairing type and its tests decide the answer.
abstract interface class SharePartnerSource {
  /// Whether this database's own record says [uid] is paired. Local, no
  /// network, and only ever a hint: it lets an account that never paired
  /// skip the question below, and with it every read sharing would cost.
  Future<bool> pairedLocally(String uid);

  /// The active pair of [uid] as the server shows it now; null when it has
  /// none.
  ///
  /// Null is a statement, and the reader acts on it by removing every row
  /// another account shared: a pair that ended, or was removed with an
  /// account. So "could not be asked" is never null — it throws a
  /// [SyncGatewayException], and the reader then changes nothing.
  Future<SharePartner?> activePartner(String uid);
}

/// [SharePartnerSource] over the pairing collection and this database's
/// stored pairing.
class PairingSharePartnerSource implements SharePartnerSource {
  final PairingGateway _gateway;
  final Future<SettingsService> Function() _settings;

  PairingSharePartnerSource({
    required PairingGateway gateway,
    required Future<SettingsService> Function() settings,
  }) : _gateway = gateway,
       _settings = settings;

  @override
  Future<bool> pairedLocally(String uid) async {
    final stored = await (await _settings()).getPairingSettings();
    return stored.pairId != null && stored.accountUid == uid;
  }

  @override
  Future<SharePartner?> activePartner(String uid) async {
    final List<PairRecord> pairs;
    try {
      pairs = await _gateway.findActivePairs(uid);
    } on PairingException catch (error) {
      throw SyncGatewayException(switch (error.error) {
        PairingError.permissionDenied => SyncGatewayFailure.permissionDenied,
        PairingError.offline ||
        PairingError.unavailable => SyncGatewayFailure.offline,
        _ => SyncGatewayFailure.unknown,
      }, 'the pair was not read: ${error.error.name}');
    }
    return partnerOf(pairs, uid);
  }

  /// The pair [uid] shares within among its active [pairs]: the earliest,
  /// the id breaking a tie — the one `PairingService.reconcile` keeps when a
  /// race left two, so both sides read the same pair while the other is
  /// still being ended.
  static SharePartner? partnerOf(List<PairRecord> pairs, String uid) {
    final live = [
      for (final pair in pairs)
        if (pair.isActive &&
            pair.contains(uid) &&
            pair.partnerUidOf(uid) != null)
          pair,
    ];
    if (live.isEmpty) return null;
    live.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.pairId.compareTo(b.pairId);
    });
    final pair = live.first;
    return SharePartner(
      pairId: pair.pairId,
      partnerUid: pair.partnerUidOf(uid)!,
    );
  }
}
