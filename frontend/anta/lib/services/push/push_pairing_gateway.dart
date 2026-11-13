import 'dart:async';

import '../../models/pair_record.dart';
import '../pairing_gateway.dart';
import 'push_registry.dart';

/// The app's [PairingGateway], telling the [PushRegistry] what it already
/// learns: each server answer of which pair an account is in — the sync
/// run's shared read and the pairing's reconcile both ask it — and each pair
/// this device ends. So the registry follows the pairing without a read of
/// its own, and an account that never paired gives it nothing to do. What
/// it is told is never awaited: the caller's answer does not wait on push.
class PushPairingGateway implements PairingGateway {
  final PairingGateway _inner;
  final PushRegistry Function() _registry;

  PushPairingGateway(this._inner, {required PushRegistry Function() registry})
    : _registry = registry;

  @override
  bool get isAvailable => _inner.isAvailable;

  @override
  Future<InviteRecord?> createInvite({
    required String code,
    required String creatorUid,
    required Duration lifetime,
  }) => _inner.createInvite(
    code: code,
    creatorUid: creatorUid,
    lifetime: lifetime,
  );

  @override
  Future<InviteRecord?> readInvite(String code) => _inner.readInvite(code);

  @override
  Stream<InviteRecord?> watchInvite(String code) => _inner.watchInvite(code);

  @override
  Future<void> deleteInvite(String code) => _inner.deleteInvite(code);

  @override
  Future<PairRecord> createPair({
    required PairProfile self,
    required PairProfile partner,
    required String inviteCode,
  }) => _inner.createPair(self: self, partner: partner, inviteCode: inviteCode);

  @override
  Future<List<PairRecord>> findActivePairs(String uid) async {
    final pairs = await _inner.findActivePairs(uid);
    unawaited(_registry().heardPairs(uid, pairs));
    return pairs;
  }

  @override
  Future<PairRecord?> readPair(String pairId) => _inner.readPair(pairId);

  @override
  Stream<PairRecord?> watchPair(String pairId) => _inner.watchPair(pairId);

  @override
  Future<void> endPair({required String pairId, required String endedBy}) async {
    await _inner.endPair(pairId: pairId, endedBy: endedBy);
    unawaited(_registry().endedByMe(pairId, endedBy));
  }

  @override
  Future<void> writeProfile({
    required String pairId,
    required PairProfile profile,
  }) => _inner.writeProfile(pairId: pairId, profile: profile);

  @override
  Future<List<PairRecord>> findPairs(String uid) => _inner.findPairs(uid);

  @override
  Future<void> deletePair(String pairId) => _inner.deletePair(pairId);

  @override
  Future<List<String>> findOwnInvites(String uid) =>
      _inner.findOwnInvites(uid);

  @override
  Future<void> writePushDevice({
    required String pairId,
    required String uid,
    required String deviceId,
    required PairPushDevice device,
    Iterable<String> drop = const [],
  }) => _inner.writePushDevice(
    pairId: pairId,
    uid: uid,
    deviceId: deviceId,
    device: device,
    drop: drop,
  );

  @override
  Future<void> removePushDevices({
    required String pairId,
    required String uid,
    required Iterable<String> deviceIds,
  }) => _inner.removePushDevices(
    pairId: pairId,
    uid: uid,
    deviceIds: deviceIds,
  );

  @override
  Future<String?> readPushRelay() => _inner.readPushRelay();
}
