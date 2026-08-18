import 'dart:async';
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../database/database_lifecycle.dart';
import '../models/app_user.dart';
import '../models/pair_record.dart';
import '../utils/pairing_error.dart';
import 'auth_service.dart';
import 'pairing_gateway.dart';
import 'settings_service.dart';

/// What the Sharing page needs to know, resolved from the cached settings and
/// whatever the gateway last reported.
class PairingStatus extends Equatable {
  final String? pairId;
  final PairProfile? partner;
  final String? pendingCode;
  final DateTime? pendingExpiresAt;

  /// Set when the partner ended the link and the user has not acknowledged it
  /// yet. [endedPartnerName] may be null when the partner never published a
  /// profile — the notice still fires.
  final bool endedNoticePending;
  final String? endedPartnerName;

  const PairingStatus({
    this.pairId,
    this.partner,
    this.pendingCode,
    this.pendingExpiresAt,
    this.endedNoticePending = false,
    this.endedPartnerName,
  });

  static const PairingStatus empty = PairingStatus();

  bool get isPaired => pairId != null;

  bool get hasPendingInvite => pendingCode != null;

  @override
  List<Object?> get props => [
    pairId,
    partner,
    pendingCode,
    pendingExpiresAt,
    endedNoticePending,
    endedPartnerName,
  ];
}

/// Owns the pairing workflow: minting invites, redeeming them, reconciling the
/// cached `pairId` against the server, and tombstoning a link on unpair.
///
/// The locally stored `pairId` is a cache. The truth is "which active pair
/// contains my uid", which is why [reconcile] runs on load and after a sign-in
/// — without it a second device, a second local database, or two people
/// redeeming each other's codes silently fork into two pairs that never
/// converge.
class PairingService {
  /// Unambiguous when read aloud: no `0/O`, `1/I/L` or `U`. 8 characters over
  /// 30 symbols is ~6.5e11 combinations, which a 10-minute lifetime and a
  /// closed `list` rule put well out of brute-force range.
  static const String codeAlphabet = '23456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const int codeLength = 8;
  static const Duration inviteLifetime = Duration(minutes: 10);
  static const int _maxCodeAttempts = 5;

  /// A real race produces one extra pair. Capping the cleanup keeps a hostile
  /// pile of planted pairs from turning one reconcile into hundreds of writes;
  /// the next reconcile finishes whatever is left.
  static const int _maxTombstonesPerReconcile = 4;

  static PairingService? _instance;

  /// Memoized like `FirebaseAuthService._initFuture`: two overlapping
  /// `getInstance` calls would otherwise both construct, and the loser would
  /// be orphaned with live snapshot subscriptions nothing can cancel.
  static Future<PairingService>? _pending;

  late final AuthService _auth;
  late final PairingGateway _gateway;
  late final SettingsService _settings;

  final Random _random = Random.secure();
  final StreamController<PairingStatus> _statusController =
      StreamController<PairingStatus>.broadcast();
  final StreamController<PairingError> _errorController =
      StreamController<PairingError>.broadcast();

  StreamSubscription<InviteRecord?>? _inviteSub;
  StreamSubscription<PairRecord?>? _pairSub;

  PairingSettings _cached = PairingSettings.empty;
  PairProfile? _partner;

  PairingService._();

  static Future<PairingService> getInstance(
    AuthService auth,
    PairingGateway gateway,
  ) {
    final existing = _instance;
    if (existing != null) return Future<PairingService>.value(existing);
    return _pending ??= _createFrom(auth, gateway);
  }

  static Future<PairingService> _createFrom(
    AuthService auth,
    PairingGateway gateway,
  ) async {
    try {
      return await _create(auth, gateway, await SettingsService.getInstance());
    } finally {
      _pending = null;
    }
  }

  @visibleForTesting
  static Future<PairingService> forTesting({
    required AuthService auth,
    required PairingGateway gateway,
    required SettingsService settings,
  }) async {
    if (_instance != null) return _instance!;
    return _create(auth, gateway, settings);
  }

  static Future<PairingService> _create(
    AuthService auth,
    PairingGateway gateway,
    SettingsService settings,
  ) async {
    final service = PairingService._();
    service._auth = auth;
    service._gateway = gateway;
    service._settings = settings;
    service._cached = await settings.getPairingSettings();
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the singleton so the next [getInstance] rebinds to the active
  /// database. Pairing is per-database, so the listeners bound to the previous
  /// database's pair must go with it.
  static void reset() {
    _instance?._detachListeners();
    _instance = null;
    _pending = null;
  }

  /// Pushes a new status whenever a listener fires — a redeemed invite, a
  /// partner ending the link, a profile arriving.
  Stream<PairingStatus> get changes => _statusController.stream;

  /// Failures that arrive with no user action to attach them to: a snapshot
  /// listener dropping, or the background half of a redemption failing. They
  /// are reported rather than swallowed — a pairing that silently stops
  /// updating is the worst outcome for a trust feature.
  Stream<PairingError> get errors => _errorController.stream;

  bool get isAvailable => _auth.isAvailable && _gateway.isAvailable;

  PairingStatus get status => _statusFrom(_cached);

  /// Reconciles the cached state against the server. A failed reconcile is
  /// reported but never clears the cache: opening the Sharing page on a train
  /// must not read as "not paired".
  ///
  /// Deliberately does not re-read `user_settings`. The rows were loaded when
  /// the singleton bound to this database and every write goes through
  /// [_write], so re-reading could only lose a change a listener just made.
  Future<PairingStatus> load() async {
    // `finally`, because a reconcile that throws offline must still leave the
    // listeners bound. Otherwise one page open on a train leaves the device
    // permanently deaf to the partner unpairing.
    try {
      await reconcile();
    } finally {
      _attachListeners();
    }
    return status;
  }

  /// Aligns the cached pairing with the server. Throws [PairingException] when
  /// the network is the problem; the caller decides how loud that is.
  Future<void> reconcile() async {
    if (!isAvailable) return;
    final user = _auth.currentUser;
    if (user == null) return;

    // A different account signed in on this database. The stored pairId now
    // answers permission-denied to every read, so drop it rather than leave a
    // paired-looking row that cannot do anything.
    if (_cached.accountUid != null && _cached.accountUid != user.uid) {
      await _write(PairingSettings.empty);
    }

    await _dropExpiredInvite();

    final pairs = await _gateway.findActivePairs(user.uid);
    if (pairs.isEmpty) {
      if (_cached.pairId != null) await _handleVanishedPair(user.uid);
      return;
    }

    // Earliest wins. Both devices sort the same server-assigned timestamps,
    // so a both-sides-redeemed race converges without either asking the user.
    // The id breaks ties: `Timestamp` truncates to microseconds here, and two
    // devices disagreeing on the winner would tombstone each other's pick and
    // leave both unpaired.
    pairs.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.pairId.compareTo(b.pairId);
    });
    final winner = pairs.first;
    for (final loser in pairs.skip(1).take(_maxTombstonesPerReconcile)) {
      await _endQuietly(loser.pairId, user.uid);
    }
    await _adopt(winner, user);
  }

  /// Mints a fresh invite. Retries on collision because a taken code must not
  /// silently overwrite someone else's pending pair.
  Future<PairingStatus> generateInvite() async {
    final user = _requireUser();
    if (_cached.pairId != null) {
      throw const PairingException(PairingError.alreadyPaired);
    }

    for (var attempt = 0; attempt < _maxCodeAttempts; attempt++) {
      final code = _generateCode();
      final invite = await _gateway.createInvite(
        code: code,
        creatorUid: user.uid,
        lifetime: inviteLifetime,
      );
      if (invite == null) continue;
      // A fresh value, not `copyWith`: a lingering ended notice would
      // otherwise outrank the new code and hide it behind an "ended" row.
      await _write(
        PairingSettings(
          accountUid: user.uid,
          pendingCode: invite.code,
          pendingExpiresAt: invite.expiresAt,
        ),
      );
      _attachListeners();
      return status;
    }
    throw const PairingException(PairingError.unknown);
  }

  Future<PairingStatus> cancelInvite() async {
    final code = _cached.pendingCode;
    if (code == null) return status;
    await _gateway.deleteInvite(code);
    await _write(_cached.clearPendingInvite());
    _attachListeners();
    return status;
  }

  /// Redeems [rawCode]: validate, create the pair, then claim the invite.
  ///
  /// Deliberately not atomic. Security rules cannot verify a pair created in
  /// the same batch, and reconciliation already repairs a half-finished
  /// redemption — so the pair is created first and the claim stamps it
  /// afterwards, with the pair tombstoned again if the claim loses a race.
  Future<PairingStatus> redeem(String rawCode) async {
    final user = _requireUser();
    if (_cached.pairId != null) {
      throw const PairingException(PairingError.alreadyPaired);
    }

    final code = normalizeCode(rawCode);
    if (code.length != codeLength) {
      throw const PairingException(PairingError.codeInvalid);
    }

    InviteRecord? invite;
    try {
      invite = await _gateway.readInvite(code);
    } on PairingException catch (e) {
      // Rules deny a read of an expired invite, so "expired" reaches us as
      // permission-denied. Telling the user they lack permission when they
      // mistyped a code would be both wrong and alarming.
      if (e.error == PairingError.permissionDenied) {
        throw const PairingException(PairingError.codeInvalid);
      }
      rethrow;
    }
    if (invite == null || invite.isExpiredAt(DateTime.now().toUtc())) {
      throw const PairingException(PairingError.codeInvalid);
    }
    if (invite.creatorUid == user.uid) {
      throw const PairingException(PairingError.ownCode);
    }
    if (invite.isRedeemed) {
      throw const PairingException(PairingError.codeInvalid);
    }

    final pair = await _gateway.createPair(
      self: PairProfile.fromUser(user),
      // The creator's name is unknown here — only they can write their own
      // profile entry, which they do when their invite listener adopts.
      partner: PairProfile(uid: invite.creatorUid),
      inviteCode: code,
    );

    try {
      await _gateway.claimInvite(
        code: code,
        pairId: pair.pairId,
        redeemerUid: user.uid,
      );
    } catch (_) {
      await _endQuietly(pair.pairId, user.uid);
      rethrow;
    }

    await _adopt(pair, user);
    return status;
  }

  Future<PairingStatus> unpair() async {
    final user = _requireUser();
    final pairId = _cached.pairId;
    if (pairId == null) return status;
    await _gateway.endPair(pairId: pairId, endedBy: user.uid);
    // No ended notice for the person who pressed the button.
    await _write(PairingSettings(accountUid: user.uid));
    _attachListeners();
    return status;
  }

  Future<PairingStatus> dismissEndedNotice() async {
    // The notice only exists in an unpaired state, so acknowledging it leaves
    // nothing but the account the settings belong to.
    await _write(PairingSettings(accountUid: _cached.accountUid));
    return status;
  }

  /// Uppercases and drops everything outside [codeAlphabet], so a pasted
  /// `k7m2-p4xq` and a hand-typed `K7M2 P4XQ` resolve to the same code.
  static String normalizeCode(String raw) {
    final buffer = StringBuffer();
    for (final char in raw.toUpperCase().split('')) {
      if (codeAlphabet.contains(char)) buffer.write(char);
    }
    return buffer.toString();
  }

  /// `XXXX-XXXX` — grouped because the code gets read aloud.
  static String formatCode(String code) {
    if (code.length != codeLength) return code;
    return '${code.substring(0, 4)}-${code.substring(4)}';
  }

  Future<void> dispose() async {
    _detachListeners();
    await _statusController.close();
    await _errorController.close();
  }

  AppUser _requireUser() {
    if (!isAvailable) {
      throw const PairingException(PairingError.unavailable);
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw const PairingException(PairingError.notSignedIn);
    }
    return user;
  }

  String _generateCode() => List.generate(
    codeLength,
    (_) => codeAlphabet[_random.nextInt(codeAlphabet.length)],
  ).join();

  Future<void> _dropExpiredInvite() async {
    final expiresAt = _cached.pendingExpiresAt;
    if (expiresAt == null) return;
    if (expiresAt.isAfter(DateTime.now().toUtc())) return;
    await _write(_cached.clearPendingInvite());
  }

  /// The stored pair is no longer active. It is still readable — membership
  /// never shrinks — so the tombstone can say who ended it.
  Future<void> _handleVanishedPair(String uid) async {
    final pairId = _cached.pairId;
    if (pairId == null) return;

    PairRecord? ended;
    try {
      ended = await _gateway.readPair(pairId);
    } on PairingException {
      ended = null;
    }

    final endedByPartner = ended?.endedBy != null && ended!.endedBy != uid;
    await _write(
      PairingSettings(
        accountUid: uid,
        partnerName: _cached.partnerName,
        endedNoticePending: endedByPartner,
      ),
    );
    _partner = null;
    _attachListeners();
  }

  Future<void> _adopt(PairRecord pair, AppUser user) async {
    final partner = pair.partnerProfileOf(user.uid);
    _partner = partner;

    // Read before the write below replaces the cache wholesale — otherwise the
    // consumed invite is never deleted and cleanup falls entirely to a TTL
    // policy that has to be configured by hand.
    final spentCode = _cached.pendingCode;

    await _write(
      PairingSettings(
        pairId: pair.pairId,
        accountUid: user.uid,
        partnerUid: pair.partnerUidOf(user.uid),
        partnerName: partner?.displayName ?? _cached.partnerName,
      ),
    );

    // The redeemer could only fill in its own profile, so publishing ours is
    // what lets the other side show a name instead of a uid.
    final mine = pair.profiles[user.uid];
    final self = PairProfile.fromUser(user);
    if (mine == null ||
        mine.displayName != self.displayName ||
        mine.photoUrl != self.photoUrl) {
      try {
        await _gateway.writeProfile(pairId: pair.pairId, profile: self);
      } on PairingException {
        // Cosmetic; the link itself is already established.
      }
    }

    if (spentCode != null) {
      try {
        await _gateway.deleteInvite(spentCode);
      } on PairingException {
        // The TTL policy reaps it either way.
      }
    }

    _attachListeners();
  }

  Future<void> _endQuietly(String pairId, String uid) async {
    try {
      await _gateway.endPair(pairId: pairId, endedBy: uid);
    } on PairingException {
      // Best effort: the surviving pair is what matters, and the loser is
      // re-detected on the next reconcile.
    }
  }

  /// Rebinds the listeners to whatever the cache now points at. Callers that
  /// changed the status publish it themselves — this only moves subscriptions.
  void _attachListeners() {
    _detachListeners();

    final pairId = _cached.pairId;
    if (pairId != null && isAvailable) {
      _pairSub = _gateway
          .watchPair(pairId)
          .listen(_onPairChanged, onError: _reportStreamError);
    }

    final code = _cached.pendingCode;
    if (code != null && isAvailable) {
      _inviteSub = _gateway
          .watchInvite(code)
          .listen(_onInviteChanged, onError: _reportStreamError);
    }
  }

  /// A dropped snapshot listener means this device has stopped hearing about
  /// the pair. That has to reach the user: the alternative is a screen that
  /// keeps claiming everything is fine.
  ///
  /// A Firestore snapshot stream *terminates* on error, so rebinding is not
  /// optional — without it one transient permission error leaves the device
  /// permanently deaf.
  void _reportStreamError(Object error) {
    _errorController.add(
      error is PairingException ? error.error : PairingError.offline,
    );
    _attachListeners();
  }

  void _detachListeners() {
    _inviteSub?.cancel();
    _inviteSub = null;
    _pairSub?.cancel();
    _pairSub = null;
  }

  Future<void> _onInviteChanged(InviteRecord? invite) async {
    if (invite == null || !invite.isRedeemed) return;
    if (_cached.pairId != null) return;
    final user = _auth.currentUser;
    if (user == null) return;

    final pairId = invite.pairId!;
    PairRecord? pair;
    try {
      pair = await _gateway.readPair(pairId);
    } on PairingException catch (e) {
      // The partner redeemed but this device could not read the pair. Silence
      // would leave the row saying "waiting" forever.
      _errorController.add(e.error);
      return;
    }

    // The redeemer wrote this id; rules already stop us reading a pair we are
    // not in, and this rejects a pair that does not hold both accounts.
    if (pair == null ||
        !pair.isActive ||
        !pair.contains(user.uid) ||
        (invite.redeemedBy != null && !pair.contains(invite.redeemedBy!))) {
      return;
    }

    await _adopt(pair, user);
    _statusController.add(status);
  }

  Future<void> _onPairChanged(PairRecord? pair) async {
    if (pair == null) return;
    final user = _auth.currentUser;
    if (user == null || pair.pairId != _cached.pairId) return;

    if (!pair.isActive) {
      // Not necessarily a break-up: the dedup path tombstones the losing pair
      // of a both-sides-redeemed race, and this device may be watching the
      // loser. Ask the server what is actually live before telling the user
      // their partner walked away — otherwise the convergence mechanism's own
      // cleanup pops a false "X ended sharing" dialog.
      var confirmed = true;
      try {
        // A successful reconcile already adopts a surviving pair, or raises
        // the notice itself when nothing is left.
        await reconcile();
      } on PairingException {
        confirmed = false;
      }
      // Offline, so the server could not be asked. Trust the tombstone this
      // device actually saw; the next reconcile corrects it either way.
      if (!confirmed && _cached.pairId == pair.pairId) {
        await _handleVanishedPair(user.uid);
      }
      _statusController.add(status);
      return;
    }

    final partner = pair.partnerProfileOf(user.uid);
    if (partner == null) return;
    _partner = partner;
    if (partner.displayName != null &&
        partner.displayName != _cached.partnerName) {
      await _write(_cached.copyWith(partnerName: partner.displayName));
    }
    _statusController.add(status);
  }

  /// Persists first, then swaps the cache — a failed write must not leave
  /// memory claiming a pairing that disk does not have.
  Future<void> _write(PairingSettings next) async {
    await _settings.setPairingSettings(next);
    _cached = next;
  }

  PairingStatus _statusFrom(PairingSettings settings) => PairingStatus(
    pairId: settings.pairId,
    partner: settings.pairId == null
        ? null
        : _partner ??
              (settings.partnerUid == null
                  ? null
                  : PairProfile(
                      uid: settings.partnerUid!,
                      displayName: settings.partnerName,
                    )),
    pendingCode: settings.pendingCode,
    pendingExpiresAt: settings.pendingExpiresAt,
    endedNoticePending: settings.endedNoticePending,
    endedPartnerName: settings.endedNoticePending
        ? settings.partnerName
        : null,
  );
}
