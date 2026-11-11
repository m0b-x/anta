import '../../models/pair_record.dart';
import '../../utils/auth_error.dart';
import '../../utils/pairing_error.dart';
import '../auth_service.dart';
import '../pairing_gateway.dart';

/// Why [AccountCloser.close] stopped short. Whatever it had removed stays
/// removed, and a later call goes on from there.
enum AccountCloseFailure {
  /// No connection reached the cloud.
  offline,

  /// The cloud refused: the rules that let a pair or an invite be removed
  /// are not deployed, or the account is no longer the one signed in.
  permissionDenied,

  /// The sign-in is too old for the account to be deleted. Everything else
  /// is done; the way on is `AuthService.reauthenticate`, never a retry.
  recentSignInRequired,

  /// The caller no longer wants the account gone — it was asked right
  /// before the account's own delete and said no. Its pairs and invites are
  /// removed already; the account stays.
  withdrawn,

  unknown,
}

class AccountCloseException implements Exception {
  final AccountCloseFailure failure;

  const AccountCloseException(this.failure);

  @override
  String toString() => 'AccountCloseException(${failure.name})';
}

/// The end of an account's deletion (cloud-multi-user-roadmap §6.1): what the
/// account holds outside its spaces, then the account itself. An interface so
/// `SyncSpaceService`, which owns the deletion run, is built and tested
/// without the identity or pairing behind it.
abstract interface class AccountCloser {
  /// Ends and removes every pair [accountUid] is a member of, removes every
  /// invite it created or redeemed, then deletes the sign-in account, which
  /// ends the session. The account last: it is what reaches the rest, and
  /// the same person signing in again would be a new one.
  ///
  /// [stillWanted] is asked once, immediately before the account's own
  /// delete — the one step nothing undoes — and a no ends the call as
  /// [AccountCloseFailure.withdrawn]: the walks before it take several
  /// round trips, in which the person may have signed out to keep the
  /// account.
  ///
  /// The caller has emptied the account's spaces first; this call never
  /// looks at them. Throws [AccountCloseException].
  Future<void> close(String accountUid, {required bool Function() stillWanted});
}

/// [AccountCloser] over the bound identity and the pairing gateway.
final class PairedAccountCloser implements AccountCloser {
  /// A walk still finding documents after this many pages is not
  /// converging — deletes that keep not landing — and ends as a failure
  /// rather than a loop. An account holds a handful of pairs and invites.
  static const int maxPages = 50;

  final AuthService _auth;
  final PairingGateway _pairing;
  final Future<void> Function()? _forgetLocalPairing;

  /// [forgetLocalPairing] drops what the open database remembers of the
  /// pairing before the pairs are touched (`PairingService.forget`): a
  /// listener left on the pair would watch this call remove it and raise
  /// "your partner ended sharing" on the device that did it.
  const PairedAccountCloser({
    required AuthService auth,
    required PairingGateway pairing,
    Future<void> Function()? forgetLocalPairing,
  }) : _auth = auth,
       _pairing = pairing,
       _forgetLocalPairing = forgetLocalPairing;

  /// Every call below acts as whoever is signed in: under another account
  /// the walks would find nothing, and the delete would take the wrong one.
  void _ensureSignedInAs(String accountUid) {
    if (_auth.currentUser?.uid != accountUid) {
      throw const AccountCloseException(AccountCloseFailure.permissionDenied);
    }
  }

  @override
  Future<void> close(
    String accountUid, {
    required bool Function() stillWanted,
  }) async {
    _ensureSignedInAs(accountUid);
    try {
      await _forgetLocalPairing?.call();
      await _removePairs(accountUid);
      await _removeInvites(accountUid);
      // Again, and the caller's word with it: the walks above were awaits,
      // and the session or the intent may have changed in any of them.
      _ensureSignedInAs(accountUid);
      if (!stillWanted()) {
        throw const AccountCloseException(AccountCloseFailure.withdrawn);
      }
      await _auth.deleteAccount();
    } on PairingException catch (e) {
      throw AccountCloseException(switch (e.error) {
        PairingError.offline => AccountCloseFailure.offline,
        PairingError.permissionDenied => AccountCloseFailure.permissionDenied,
        _ => AccountCloseFailure.unknown,
      });
    } on RecentSignInRequiredException {
      throw const AccountCloseException(
        AccountCloseFailure.recentSignInRequired,
      );
    } on AuthException catch (e) {
      throw AccountCloseException(switch (e.error) {
        AuthError.offline => AccountCloseFailure.offline,
        _ => AccountCloseFailure.unknown,
      });
    }
  }

  /// An active pair is ended before it is removed: the rules delete only an
  /// ended one, and the tombstone is what a partner's listening device
  /// hears.
  Future<void> _removePairs(String accountUid) async {
    for (var page = 0; page < maxPages; page++) {
      final pairs = await _pairing.findPairs(accountUid);
      if (pairs.isEmpty) return;
      for (final pair in pairs) {
        if (pair.isActive) await _end(pair, accountUid);
        await _pairing.deletePair(pair.pairId);
      }
    }
    throw const AccountCloseException(AccountCloseFailure.unknown);
  }

  /// Ends [pair]. A refusal is read back before it counts: the partner may
  /// have ended or removed the pair since the page listed it, and the rules
  /// refuse to end one that is not active.
  Future<void> _end(PairRecord pair, String accountUid) async {
    try {
      await _pairing.endPair(pairId: pair.pairId, endedBy: accountUid);
    } on PairingException catch (e) {
      if (e.error != PairingError.permissionDenied) rethrow;
      final now = await _pairing.readPair(pair.pairId);
      if (now != null && now.isActive) rethrow;
    }
  }

  Future<void> _removeInvites(String accountUid) async {
    for (var page = 0; page < maxPages; page++) {
      final codes = await _pairing.findOwnInvites(accountUid);
      if (codes.isEmpty) return;
      for (final code in codes) {
        await _pairing.deleteInvite(code);
      }
    }
    throw const AccountCloseException(AccountCloseFailure.unknown);
  }
}
