import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../database/database_lifecycle.dart';
import '../models/app_user.dart';
import '../models/sync_binding.dart';
import '../services/auth_service.dart';
import '../services/folder_storage_service.dart';
import '../services/pairing_service.dart';
import '../services/settings_service.dart';
import '../services/share_service.dart';
import '../services/sync/sync_status.dart';

/// Whether this database syncs as the signed-in account, and why not: the
/// setup card's sync row names only what Sync & sharing draws in that state.
/// No `paused`: the engine's own pauses (space deleted, no access, app
/// outdated) are known only to an engine built for them, and the card builds
/// nothing to ask.
enum GuideSetupSync {
  /// Bound to a space of the signed-in account.
  on,

  /// Not bound: "Sync this database" turns it on.
  off,

  /// Bound to another account's space: the page says it is paused and draws
  /// no "Sync this database".
  otherAccount,
}

/// What the sync guide's "Your setup" card says (`docs/guide-hub-roadmap.md`
/// D48): four facts of this phone as they stand now. A null fact is not
/// known yet, and its row claims nothing until it is.
@immutable
class GuideSetupFacts extends Equatable {
  const GuideSetupFacts({
    this.signedIn,
    this.accountName,
    this.sync,
    this.paired,
    this.partnerName,
    this.shared,
  }) : unavailable = false;

  /// A platform or build without sync: the card is one line, and nothing
  /// else is read.
  const GuideSetupFacts.unavailable()
    : unavailable = true,
      signedIn = null,
      accountName = null,
      sync = null,
      paired = null,
      partnerName = null,
      shared = null;

  /// Nobody signed in: no account to sync as, to pair or to share for —
  /// every fact known, without a read.
  static const GuideSetupFacts signedOut = GuideSetupFacts(
    signedIn: false,
    sync: GuideSetupSync.off,
    paired: false,
    shared: 0,
  );

  final bool unavailable;
  final bool? signedIn;

  /// The account's name or address; null when it has neither.
  final String? accountName;

  /// Whether this database is bound to a space of the signed-in account —
  /// what the engine itself checks before a run ([SyncPause.forAccount]).
  final GuideSetupSync? sync;

  /// Whether the stored pair is the signed-in account's.
  final bool? paired;

  /// The partner's published name; null when they never published one.
  final String? partnerName;

  /// How many of her categories, events and folders she shares — what the
  /// Sharing page lists as hers.
  final int? shared;

  @override
  List<Object?> get props => [
    unavailable,
    signedIn,
    accountName,
    sync,
    paired,
    partnerName,
    shared,
  ];
}

/// Where [GuideSetupReader] asks each fact: the app's services, or a test's
/// fakes. Every in-memory answer is a function, so it is asked at the moment
/// of the read rather than when the reader was built.
class GuideSetupSources {
  const GuideSetupSources({
    required this.auth,
    required this.storedPairing,
    required this.binding,
    required this.share,
    this.pairedInMemory = _pairedInMemory,
    this.knownSharing = _knownSharing,
    this.storedPair = _noCensus,
    this.pairingWrites = _pairingWrites,
  });

  /// The bound identity; null where none is registered, which reads as a
  /// build without sync.
  final AuthService? auth;

  /// The stored pairing of the open database, read through the settings:
  /// an account that never paired builds no pairing service to learn so.
  final Future<PairingSettings> Function() storedPairing;

  /// The stored binding of the open database.
  final Future<SyncBinding?> Function() binding;

  /// The share service of the open database; asked only once a pair of
  /// the signed-in account is known.
  final Future<ShareService> Function() share;

  /// [PairingService.pairedInMemory].
  final bool? Function() pairedInMemory;

  /// [ShareService.knownAvailability].
  final ShareAvailability? Function() knownSharing;

  /// Whether the share census held now says a pair is stored; null while
  /// none is held.
  final bool? Function() storedPair;

  /// [PairingService.writes].
  final Stream<PairingStatus> Function() pairingWrites;

  /// Over the app's registrations. The pairing and the binding are read
  /// through the settings, never through the pairing or the binding
  /// service: the one is built only for an account that holds a pair, the
  /// other's build squares the install's claims and may write.
  factory GuideSetupSources.app() {
    final getIt = GetIt.I;
    final auth = getIt.isRegistered<AuthService>()
        ? getIt<AuthService>()
        : null;
    final folders = getIt.isRegistered<FolderStorageService>()
        ? getIt<FolderStorageService>()
        : null;
    return GuideSetupSources(
      auth: auth,
      storedPairing: () async =>
          (await SettingsService.getInstance()).getPairingSettings(),
      binding: () async =>
          (await SettingsService.getInstance()).getSyncBinding(),
      share: ShareService.getInstance,
      storedPair: () =>
          folders == null || !folders.censusKnown ? null : folders.holdsPair,
    );
  }

  static bool? _pairedInMemory() => PairingService.pairedInMemory;
  static ShareAvailability? _knownSharing() => ShareService.knownAvailability;
  static bool? _noCensus() => null;
  static Stream<PairingStatus> _pairingWrites() => PairingService.writes;
}

/// Reads [GuideSetupFacts] for the sync book's hub, and follows them while
/// the hub is alive — owned by the hub page's `State`, as
/// `PartnerLookReader` is by a browser page's.
///
/// Nothing it asks reaches the network: the account and the pair come from
/// memory, the binding and the shares from this database. An account that
/// never paired builds nothing: the pair is known from memory — the share
/// or pairing service already built, or the share census — or from the
/// stored pairing, and the binding is its one other read. A paired account's
/// share count is asked once per change of the share service, the account
/// or the database, and once after each screen a setup row opens
/// ([stepOpened]). The first frame is drawn from memory alone ([value]
/// before [start]); a fact that needs a read stays null until it lands.
class GuideSetupReader extends ValueNotifier<GuideSetupFacts> {
  GuideSetupReader([GuideSetupSources? sources])
    : _sources = sources ?? GuideSetupReader.sources(),
      super(const GuideSetupFacts()) {
    value = _fromMemory();
  }

  /// Where a reader built without sources asks; a page's suite hands in
  /// its fakes here.
  @visibleForTesting
  static GuideSetupSources Function() sources = GuideSetupSources.app;

  final GuideSetupSources _sources;

  StreamSubscription<AppUser?>? _account;
  StreamSubscription<PairingStatus>? _pairWrites;
  StreamSubscription<ShareAvailability>? _sharing;

  /// The share service followed now, and what it last said; both dropped
  /// with the pair, the account or the database they belong to.
  ShareService? _share;
  ShareAvailability? _heard;

  /// The count the share service's overview last answered; dropped with
  /// the service, by its changes and the account's, and by [stepOpened].
  int? _shared;

  /// The account the facts were last read for, so the replay of it that a
  /// new listener of the identity hears asks nothing again.
  AppUser? _seen;

  /// The database the followed service belongs to.
  int _generation = DatabaseLifecycle.generation;

  /// Bumped by every [refresh] and [stepOpened], so a slow read never lands
  /// over a newer one or over a step.
  int _reads = 0;
  bool _started = false;
  bool _disposed = false;

  AuthService? get _auth {
    final auth = _sources.auth;
    return auth != null && auth.isAvailable ? auth : null;
  }

  GuideSetupFacts _fromMemory() {
    final auth = _auth;
    if (auth == null) return const GuideSetupFacts.unavailable();
    final user = auth.currentUser;
    if (user == null) return GuideSetupFacts.signedOut;
    final name = _nameOf(user);
    final known = _sources.knownSharing();
    if (known?.audience case final audience?) {
      return GuideSetupFacts(
        signedIn: true,
        accountName: name,
        // Not syncing says nothing of why: the binding's read tells.
        sync: known is ShareReady ? GuideSetupSync.on : null,
        paired: true,
        partnerName: audience.displayName,
      );
    }
    final paired = _pairedFromMemory();
    return GuideSetupFacts(
      signedIn: true,
      accountName: name,
      paired: paired,
      shared: paired == false ? 0 : null,
    );
  }

  /// What memory alone says of the signed-in account's pair: true when the
  /// share service names an audience; false when no pair is held at all —
  /// the pairing service's cache, or no pair in the share census; null when
  /// only the stored pairing can say. A share service that says "not
  /// paired" is not believed alone: it may not have caught up with a pair
  /// just made.
  bool? _pairedFromMemory() {
    if (_sources.knownSharing()?.audience != null) return true;
    final inMemory = _sources.pairedInMemory();
    if (inMemory == false) return false;
    if (inMemory == null && _sources.storedPair() == false) return false;
    return null;
  }

  static String? _nameOf(AppUser user) => user.displayName ?? user.email;

  static GuideSetupSync _syncOver(SyncBinding? binding, AppUser user) =>
      binding == null
      ? GuideSetupSync.off
      : SyncPause.forAccount(binding, user.uid) == SyncPause.accountMismatch
      ? GuideSetupSync.otherAccount
      : GuideSetupSync.on;

  /// A setup row opened its screen, where she may share something: a share
  /// does not change what the share service says, so the next read asks
  /// for the count again — and a read already out is dropped, or the count
  /// it asked before would land as the new one.
  void stepOpened() {
    _shared = null;
    _reads++;
  }

  /// Starts following the account and the stored pair, and reads what
  /// memory did not answer. Nothing on a build without sync.
  void start() {
    final auth = _auth;
    if (_started || _disposed || auth == null) return;
    _started = true;
    _seen = auth.currentUser;
    _account = auth.authStateChanges.listen((user) {
      if (user == _seen) return;
      _seen = user;
      _shared = null;
      unawaited(refresh());
    }, onError: _logged);
    // Every database's pairing writes, so a pair made or ended reaches an
    // account that never built a pairing service.
    _pairWrites = _sources.pairingWrites().listen(
      (_) => unawaited(refresh()),
      onError: _logged,
    );
    unawaited(refresh());
  }

  /// Reads the facts again — on the hub's return to the front, when she may
  /// have done a step — and publishes them once all are read.
  Future<void> refresh() async {
    final auth = _auth;
    if (!_started || _disposed || auth == null) return;
    final read = ++_reads;
    final generation = DatabaseLifecycle.generation;
    if (generation != _generation) {
      // A switch: what the followed service says is the old database's.
      _generation = generation;
      _dropSharing();
    }
    bool current() =>
        !_disposed &&
        read == _reads &&
        generation == DatabaseLifecycle.generation;
    try {
      final next = await _read(auth, current);
      if (next != null && current()) value = next;
    } catch (e, st) {
      // The card keeps what it showed; the next return or change asks again.
      debugPrint('[GuideSetupReader] setup not read: $e\n$st');
    }
  }

  /// The facts as they stand, or null when a newer read or a switch
  /// overtook this one.
  Future<GuideSetupFacts?> _read(
    AuthService auth,
    bool Function() current,
  ) async {
    final user = auth.currentUser;
    if (user == null) {
      _dropSharing();
      return GuideSetupFacts.signedOut;
    }
    var paired = _pairedFromMemory();
    if (paired == null) {
      final stored = await _sources.storedPairing();
      if (!current()) return null;
      paired = stored.pairId != null && stored.accountUid == user.uid;
    }
    if (!paired) {
      _dropSharing();
      final binding = await _sources.binding();
      if (!current()) return null;
      return GuideSetupFacts(
        signedIn: true,
        accountName: _nameOf(user),
        sync: _syncOver(binding, user),
        paired: false,
        shared: 0,
      );
    }
    final share = _share ?? await _openSharing(current);
    if (share == null) return null;
    final availability = share.availability;
    _heard = availability;
    var sync = GuideSetupSync.on;
    if (availability is! ShareReady) {
      final binding = await _sources.binding();
      if (!current()) return null;
      sync = _syncOver(binding, user);
    }
    final audience = availability.audience;
    if (audience == null) {
      // Not caught up with the stored pair yet: its changes, still followed,
      // say when it is.
      return GuideSetupFacts(
        signedIn: true,
        accountName: _nameOf(user),
        sync: sync,
        paired: true,
      );
    }
    var shared = _shared;
    if (shared == null) {
      final overview = await share.overview();
      if (!current()) return null;
      shared = _shared =
          overview.categories.length +
          overview.events.length +
          overview.folderCount;
    }
    return GuideSetupFacts(
      signedIn: true,
      accountName: _nameOf(user),
      sync: sync,
      paired: true,
      partnerName: audience.displayName,
      shared: shared,
    );
  }

  /// Opens the share service and follows it: it already follows the
  /// pairing, the account and the binding, so a partner's name arriving or
  /// sync turned off reaches the card through it.
  Future<ShareService?> _openSharing(bool Function() current) async {
    final share = await _sources.share();
    if (!current()) return null;
    _share = share;
    // Taken before the listen, so its replay asks nothing again.
    _heard = share.availability;
    _sharing = share.changes.listen(
      (availability) {
        if (availability == _heard) return;
        _heard = availability;
        _shared = null;
        unawaited(refresh());
      },
      onError: _logged,
      // Its database was switched away.
      onDone: _dropSharing,
    );
    return share;
  }

  void _dropSharing() {
    unawaited(_sharing?.cancel());
    _sharing = null;
    _share = null;
    _heard = null;
    _shared = null;
  }

  static void _logged(Object e, StackTrace st) =>
      debugPrint('[GuideSetupReader] a source failed: $e\n$st');

  @override
  void dispose() {
    _disposed = true;
    unawaited(_account?.cancel());
    unawaited(_pairWrites?.cancel());
    _dropSharing();
    super.dispose();
  }
}
