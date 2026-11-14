import 'dart:async';
import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../constants/settings_keys.dart';
import '../database/database_lifecycle.dart';
import '../models/app_user.dart';
import '../models/pair_record.dart';
import '../models/share_settings.dart';
import '../utils/pairing_error.dart';
import 'alert_scheduler.dart';
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

/// Who ended a pair, as far as this device can tell, and the partner's name
/// as it stood ([PairingService.endingOf]).
typedef PairEnding = ({bool byPartner, String? name});

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

  /// The alert pass a change of what may ring on the partner's events is
  /// followed by — the one the Sharing page's own change runs
  /// (`ShareService.setAlerts`).
  late final Future<void> Function() _reconcileAlerts;

  static Future<void> _alertPass() =>
      AlertScheduler.reconcileAllQuietly(AlertReconcileReason.eventChanged);

  /// Told once an adoption has cleared the marks other pairs left
  /// ([_adopt]): every cache that holds a share flag reads again. Set by DI
  /// to the share service's own "after marks" — this service is what that
  /// one is built over, so it cannot ask for it itself.
  static Future<void> Function()? onMarksOfOtherPairsCleared;

  final Random _random = Random.secure();
  final StreamController<PairingStatus> _statusController =
      StreamController<PairingStatus>.broadcast();
  final StreamController<PairingError> _errorController =
      StreamController<PairingError>.broadcast();
  final StreamController<PairingStatus> _writtenController =
      StreamController<PairingStatus>.broadcast();

  StreamSubscription<InviteRecord?>? _inviteSub;
  StreamSubscription<PairRecord?>? _pairSub;

  PairingSettings _cached = PairingSettings.empty;
  PairProfile? _partner;

  /// Whether the pair listener attached now has shown its pair active: only
  /// then does a snapshot with no document mean the pair was removed.
  bool _pairSeenLive = false;

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
    Future<void> Function()? reconcileAlerts,
  }) async {
    if (_instance != null) return _instance!;
    return _create(auth, gateway, settings, reconcileAlerts: reconcileAlerts);
  }

  static Future<PairingService> _create(
    AuthService auth,
    PairingGateway gateway,
    SettingsService settings, {
    Future<void> Function()? reconcileAlerts,
  }) async {
    final service = PairingService._();
    service._auth = auth;
    service._gateway = gateway;
    service._settings = settings;
    service._reconcileAlerts = reconcileAlerts ?? _alertPass;
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

  /// The status after every write of the stored pairing, this device's own
  /// included — a redeem, an unpair — which [changes] leaves to the caller
  /// that made it. Apart from [changes] so `PairingBloc`, which answers its
  /// own actions from their result, never sees one twice; `ShareService`
  /// follows it so a share row appears and leaves with the pair.
  Stream<PairingStatus> get written => _writtenController.stream;

  bool get isAvailable => _auth.isAvailable && _gateway.isAvailable;

  PairingStatus get status => _statusFrom(_cached);

  /// Whether this database holds a pair, from the built service's cache
  /// alone; null while none is built. A surface on the capture path reads
  /// it to tell "never paired" without building anything for it.
  static bool? get pairedInMemory {
    final service = _instance;
    return service == null ? null : service._cached.pairId != null;
  }

  /// [written] of the built service, null while none is built: what a
  /// surface that read [pairedInMemory] as "not paired" follows to learn of
  /// a pairing made while it is open — a listener on memory, no read and no
  /// build for an account that never pairs.
  static Stream<PairingStatus>? get writtenInMemory => _instance?.written;

  /// Whether the stored pair is the signed-in account's — the rule
  /// `PairingSharePartnerSource.pairedLocally` reads by. Another account's
  /// pair left on this database, or one with nobody signed in, shares
  /// nothing for whoever holds the phone now.
  bool get pairedForSignedInAccount {
    final uid = _auth.currentUser?.uid;
    return uid != null && _cached.pairId != null && _cached.accountUid == uid;
  }

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

  /// Redeems [rawCode]: validate, then create the pair and claim the invite
  /// in one write ([PairingGateway.createPair]) — a claim that loses a race
  /// leaves no pair behind, and a code names one pair, once.
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
      // Claimed by this very account: an earlier try whose write landed
      // and whose answer did not, with the link too far gone to ask the
      // server then. The pair exists — it is asked for now, rather than the
      // person being told their own redeemed code is not valid.
      if (invite.redeemedBy == user.uid) {
        await reconcile();
        if (_pairedWith(invite.creatorUid)) return status;
      }
      throw const PairingException(PairingError.codeInvalid);
    }

    final PairRecord pair;
    try {
      pair = await _gateway.createPair(
        self: PairProfile.fromUser(user),
        // The creator's name is unknown here — only they can write their own
        // profile entry, which they do when their invite listener adopts.
        partner: PairProfile(uid: invite.creatorUid),
        inviteCode: code,
      );
    } on PairingException catch (e) {
      if (e.error == PairingError.codeInvalid) rethrow;
      if (e.error == PairingError.permissionDenied) {
        // An invite that ran out between the read above and the write is
        // refused by the rules as its read is: the same wrong code, not a
        // matter of permission. Anything else the rules refuse stays what
        // it is.
        if (await _inviteSpent(code)) {
          throw const PairingException(PairingError.codeInvalid);
        }
        rethrow;
      }
      // The write may have landed although its answer did not — the reply
      // lost, the read-back failed: the pair then exists and the invite is
      // spent, and another try would be told the code is not valid. The
      // server is asked once before the failure is believed.
      try {
        await reconcile();
      } on PairingException {
        throw e;
      }
      // Only the pair this redemption was for. Reconciliation adopts
      // whatever active pair the server shows — one made meanwhile from a
      // code of this account's own is real and stays, but it is no answer
      // to this call, whose code is still unspent.
      if (!_pairedWith(invite.creatorUid)) rethrow;
      return status;
    }

    await _adopt(pair, user);
    return status;
  }

  /// Whether this database is paired, and with [uid].
  bool _pairedWith(String uid) =>
      _cached.pairId != null && status.partner?.uid == uid;

  /// Whether [code] can no longer be redeemed: gone, claimed or run out —
  /// and a run-out invite refuses its read, which is how the rules say so.
  /// False when that cannot be told.
  Future<bool> _inviteSpent(String code) async {
    try {
      final invite = await _gateway.readInvite(code);
      return invite == null ||
          invite.isRedeemed ||
          invite.isExpiredAt(DateTime.now().toUtc());
    } on PairingException catch (e) {
      return e.error == PairingError.permissionDenied;
    }
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

  /// Whether the partner ended [pairId] — the pair a partner's rows were
  /// held under until a read forgot them — and their name as it stood (D35):
  /// what the leave notice is said by, and in.
  ///
  /// Recorded as ended, it is the ended notice's own answer
  /// ([_handleVanishedPair]): my Unpair, and my account's deletion, record
  /// no notice, and a read that failed raised none. Still recorded as this
  /// pair — the read came before its listener heard — its tombstone is read
  /// the same way; one that cannot be read answers "not the partner", as
  /// the listener does. Another pair recorded since was made by me.
  ///
  /// The read that forgot [pairId] asks once, and nothing of that pair can
  /// leave again: its record ([PairingSettings.endedPairId]) and the name
  /// kept for it past the ended notice's dismissal go with the answer.
  Future<PairEnding> endingOf(String? pairId) =>
      _ending(pairId, _cached, auth: _auth, gateway: _gateway, clear: _write);

  /// [endingOf] with no service built, for the check that runs with the app
  /// closed (`docs/cloud-shared-freshness.md` §6): one read of the stored
  /// pairing, at most one of the pair's own document, and the same record
  /// cleared with the answer.
  ///
  /// That isolate lives for seconds beside a database the app may open at
  /// any moment. A service built there is one call away from following the
  /// pair ([_attachListeners]) — a listener that outlives nothing, and
  /// whose every word is a write behind the app. So nothing is built: no
  /// instance, no stream, nothing for a database switch to reset.
  static Future<PairEnding> endingRead(
    String? pairId, {
    required AuthService auth,
    required PairingGateway gateway,
    required SettingsService settings,
  }) async => _ending(
    pairId,
    await settings.getPairingSettings(),
    auth: auth,
    gateway: gateway,
    clear: settings.setPairingSettings,
  );

  /// The one rule behind [endingOf] and [endingRead], over the pairing as
  /// its caller [held] it; [clear] writes it back without the ended pair's
  /// record.
  static Future<PairEnding> _ending(
    String? pairId,
    PairingSettings held, {
    required AuthService auth,
    required PairingGateway gateway,
    required Future<void> Function(PairingSettings next) clear,
  }) async {
    final name = held.partnerName;
    final current = held.pairId;
    if (current == null) {
      final kept = pairId != null && held.endedPairId == pairId;
      final PairEnding answer = (
        byPartner: kept || held.endedNoticePending,
        name: name,
      );
      // Answered from what is held: a record that could not be cleared costs
      // a name kept a little longer, never the leave's notice.
      if (kept) {
        try {
          await clear(_withoutEnding(held));
        } catch (e, st) {
          debugPrint('[PairingService] ended pair not cleared: $e\n$st');
        }
      }
      return answer;
    }
    if (pairId == null || current != pairId) {
      return (byPartner: false, name: name);
    }
    final uid = auth.currentUser?.uid;
    try {
      final ended = await gateway.readPair(pairId);
      final byPartner =
          ended == null ||
          (!ended.isActive && ended.endedBy != null && ended.endedBy != uid);
      return (byPartner: byPartner, name: name);
    } on PairingException {
      return (byPartner: false, name: name);
    }
  }

  /// Drops what this database remembers of a pairing, with no word to the
  /// server and no notice — for the account's own deletion, which ends and
  /// removes its pairs itself (cloud-multi-user-roadmap §6.1 g): a listener
  /// left on the pair would see it vanish and blame the partner.
  Future<PairingStatus> forget() async {
    _detachListeners();
    _partner = null;
    await _write(PairingSettings(accountUid: _cached.accountUid));
    _statusController.add(status);
    return status;
  }

  Future<PairingStatus> dismissEndedNotice() async {
    // The notice only exists in an unpaired state, so acknowledging it leaves
    // the account the settings belong to — and the ended pair with the name,
    // which a leave of what it shared is still told in (D35).
    final ended = _cached.endedPairId;
    await _write(
      PairingSettings(
        accountUid: _cached.accountUid,
        partnerName: ended == null ? null : _cached.partnerName,
        endedPairId: ended,
      ),
    );
    return status;
  }

  /// [settings] once the leave of the pair the partner ended is told: the
  /// name stays only while the ended notice still shows it.
  static PairingSettings _withoutEnding(PairingSettings settings) =>
      PairingSettings(
        accountUid: settings.accountUid,
        partnerName: settings.endedNoticePending ? settings.partnerName : null,
        pendingCode: settings.pendingCode,
        pendingExpiresAt: settings.pendingExpiresAt,
        endedNoticePending: settings.endedNoticePending,
      );

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
    await _writtenController.close();
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

  /// The stored pair is no longer active. While its document stands it is
  /// still readable — membership never shrinks — so the tombstone can say
  /// who ended it. A document that is gone says it too: only an account's
  /// deletion removes one (cloud-multi-user-roadmap §6.1 g), and one's own
  /// forgets the pairing here before it does ([forget]), so it was the
  /// partner's. A read that failed says nothing, and raises no notice.
  ///
  /// Accepted: another device of an account deleted elsewhere blames the
  /// partner for the hour its session outlives the account, and so does a
  /// device that never heard its own account end a pair the partner's
  /// deletion later removed.
  Future<void> _handleVanishedPair(String uid) async {
    final pairId = _cached.pairId;
    if (pairId == null) return;

    PairRecord? ended;
    var gone = false;
    try {
      ended = await _gateway.readPair(pairId);
      gone = ended == null;
    } on PairingException {
      ended = null;
    }

    final endedByPartner =
        gone || (ended?.endedBy != null && ended!.endedBy != uid);
    await _write(
      PairingSettings(
        accountUid: uid,
        partnerName: _cached.partnerName,
        endedNoticePending: endedByPartner,
        endedPairId: endedByPartner ? pairId : null,
      ),
    );
    _partner = null;
    _attachListeners();
  }

  Future<void> _adopt(PairRecord pair, AppUser user) async {
    final partner = pair.partnerProfileOf(user.uid);
    _partner = partner;

    // Stored with the pair below, in one write: none of its rows can
    // arrive under the choice made for another.
    final startAlertsAt = await _startAlertsChoiceOver(pair.pairId);

    // Read before the write below replaces the cache wholesale — otherwise
    // the consumed invite is never deleted. Nothing else removes it: no TTL
    // policy stands on `invites.expiresAt` (a TTL delete needs billing, and
    // the project stays on the free plan — `cloud-sync-phase-01-pairing.md`).
    final spentCode = _cached.pendingCode;

    // A mark of another pair is never a share ("we un-pair and pair again —
    // nothing is carried over"): whenever the pair stored becomes another,
    // the marks every other pair left go in the write that stores it. Not
    // at an unpair, and not while the pair is merely lost locally — the
    // shared reader clears when the server says there is no pair, and this
    // same pair found again keeps its own: only other pairs' are cleared.
    final marksCleared = await _write(
      PairingSettings(
        pairId: pair.pairId,
        accountUid: user.uid,
        partnerUid: pair.partnerUidOf(user.uid),
        // The cached name is this pair's only while the cache holds this
        // pair: one kept for a pair that ended (D35) is another person's.
        partnerName:
            partner?.displayName ??
            (_cached.pairId == pair.pairId ? _cached.partnerName : null),
      ),
      startAlertsAt: startAlertsAt,
      clearMarksOfOtherPairs: _cached.pairId != pair.pairId,
    );
    if (marksCleared > 0) {
      try {
        await onMarksOfOtherPairsCleared?.call();
      } catch (e, st) {
        // The marks are cleared and queued; a cache that missed it reads
        // them at its next load.
        debugPrint('[PairingService] caches not told of the marks: $e\n$st');
      }
    }
    // The pass a change of this choice by hand is followed by: what
    // "Category alerts too" armed on rows still stored — another account's
    // sign-in and a swapped pair remove none here — goes now, not at the
    // next pass something else asks for.
    if (startAlertsAt != null) {
      try {
        await _reconcileAlerts();
      } catch (e, st) {
        debugPrint('[PairingService] no alert pass after the reset: $e\n$st');
      }
    }

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
        // It stays, as a document nobody can redeem: the rules refuse a
        // claimed or a run-out code.
      }
    }

    _attachListeners();
  }

  /// What may ring on the partner's events is chosen for a pair (D38 of
  /// `docs/cloud-share-surfaces-roadmap.md`): "Category alerts too", chosen
  /// for one person, must not arm my category alerts on what the next one
  /// shares — nothing arms that the person did not ask for. So another pair
  /// starts from the shipped choice, "Only alerts I add", whatever stood:
  /// "Category alerts too" and "Off" alike. Each chooses again, and under
  /// that choice nothing rings that the person did not add themselves.
  ///
  /// Not taken: keeping "Off" across pairs. It is the quieter choice only
  /// until the person adds an alert on the new partner's event — which
  /// would then stay silent by a choice made for someone else.
  ///
  /// Answers the choice to start over at, stored with the pair by the one
  /// write that stores both ([SettingsService.setPairingSettings]); null
  /// when nothing is to change:
  ///
  /// - the same pair adopted again — a reconcile at launch — and the same
  ///   pair found again after it was lost locally, the server unreachable
  ///   for a moment, by the id this database last held
  ///   ([SettingsService.getLastPairId]): it keeps what was chosen for it;
  /// - the choice already standing at the shipped one: no write.
  ///
  /// Another id is another pair, a new pairing with the same person
  /// included; so is any pair for a database whose pairing rows were
  /// stripped in between — a restore, a handed-out copy.
  Future<ShareAlerts?> _startAlertsChoiceOver(String pairId) async {
    if (_cached.pairId == pairId) return null;
    if (await _settings.getLastPairId() == pairId) return null;
    final shipped = ShareAlerts.fromName(SettingsKeys.defaultShareAlerts);
    return await _settings.getShareAlerts() == shipped ? null : shipped;
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
    _pairSeenLive = false;

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
    final user = _auth.currentUser;
    if (pair == null) {
      // A document this listener showed live and now cannot read: removed —
      // a partner deleting their account ends the pair and removes it within
      // a round trip (cloud-multi-user-roadmap §6.1 g), so a device that was
      // briefly away hears only this. Never before a live one: the first
      // snapshot of a pair just written carries no server time yet and reads
      // as none. The server decides, as for a tombstone; unreachable, the
      // next reconcile will.
      if (!_pairSeenLive || user == null || _cached.pairId == null) return;
      try {
        await reconcile();
      } on PairingException {
        return;
      }
      _statusController.add(status);
      return;
    }
    if (user == null || pair.pairId != _cached.pairId) return;
    if (pair.isActive) _pairSeenLive = true;

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

  static final StreamController<PairingStatus> _writes =
      StreamController<PairingStatus>.broadcast();

  /// The writes of every service, this database's and each one opened
  /// after a switch, that change the stored pair: for what outlives the
  /// per-database instance and never builds one — the share census, whose
  /// `paired` reads the stored pair id alone. A partner-name refresh or a
  /// notice dismissed is not told, or each would reload every open page's
  /// shares.
  static Stream<PairingStatus> get writes => _writes.stream;

  /// Persists first, then swaps the cache — a failed write must not leave
  /// memory claiming a pairing that disk does not have.
  ///
  /// Answers how many marks of other pairs the write cleared
  /// ([SettingsService.setPairingSettings]).
  Future<int> _write(
    PairingSettings next, {
    ShareAlerts? startAlertsAt,
    bool clearMarksOfOtherPairs = false,
  }) async {
    final cleared = await _settings.setPairingSettings(
      next,
      startAlertsAt: startAlertsAt,
      clearMarksOfOtherPairs: clearMarksOfOtherPairs,
    );
    final pairChanged = next.pairId != _cached.pairId;
    _cached = next;
    if (!_writtenController.isClosed) _writtenController.add(status);
    if (pairChanged) _writes.add(status);
    return cleared;
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
    endedPartnerName: settings.endedNoticePending ? settings.partnerName : null,
  );
}
