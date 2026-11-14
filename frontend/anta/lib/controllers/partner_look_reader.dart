import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../models/partner_look.dart';
import '../models/share_settings.dart';
import '../services/pairing_service.dart';
import '../services/share_service.dart';

/// The [PartnerLook] one browser surface hands its rows — the browser page,
/// All notes, the search page (`docs/cloud-share-surfaces-roadmap.md` §6.7)
/// — read once for the page, never per row, the way the calendar's pages
/// read theirs.
///
/// Nothing is asked until [start]: a page calls it when [mayShare] says so,
/// so an account that never paired makes no call and no await for it — the
/// value stays null and the rows build the tree they always built. From then on
/// it follows [ShareService.changes] for who the partner is, and [refresh]
/// reads the notes look and the mark switch again on the pop back from the
/// page that sets them.
class PartnerLookReader extends ValueNotifier<PartnerLook?> {
  PartnerLookReader()
    : _heard = _knownAvailability(),
      _looks = ShareService.publishedLook,
      super(null) {
    value = _build();
  }

  /// Where the service comes from; a test hands in its fake.
  @visibleForTesting
  static Future<ShareService> Function() openService = ShareService.getInstance;

  /// The service a browser page acts through — its folder share entry — by
  /// the same road as the look, so one fake answers a test of both.
  static Future<ShareService> service() => openService();

  /// Whether a page should [start] one: the database holds something shared
  /// (`FolderStorageService.holdsShared`), the census says a pair is stored
  /// ([paired], `FolderStorageService.holdsPair` — for a page that offers a
  /// folder's share entry), or a pair is known from memory — the pairing or
  /// the share service already built. Answered without a statement, so an
  /// account that never paired asks nothing.
  static bool mayShare({required bool holdsShared, bool paired = false}) =>
      holdsShared ||
      paired ||
      PairingService.pairedInMemory == true ||
      _knownAvailability()?.audience != null;

  /// What the share service built for the open database last evaluated, so
  /// a page pushed from another draws its first frame from it, with
  /// [ShareService.publishedLook], instead of growing a face a frame later.
  static ShareAvailability? _knownAvailability() =>
      PairingService.pairedInMemory == false
      ? null
      : ShareService.knownAvailability;

  ShareService? _service;
  StreamSubscription<ShareAvailability>? _availability;
  bool _started = false;
  bool _disposed = false;
  bool _holdEnded = false;
  Timer? _holdLimit;

  /// Started and still without a look: what a page that holds its first
  /// frame for the look waits on. The first open or read that fails ends
  /// the wait, and so does [AppConstants.partnerLookHoldLimit] — the page
  /// then draws as it would with no look known, never a blank ground.
  bool get pending => _started && value == null && !_holdEnded;

  void _endHold() {
    _holdLimit?.cancel();
    _holdLimit = null;
    if (_disposed || _holdEnded) return;
    _holdEnded = true;
    notifyListeners();
  }

  /// What the last failed start was asked under — the page state that
  /// asked, the pairing and the database — so only a change outside the
  /// reader asks again: a page starts it on every build, and the rebuild
  /// its own notify causes would otherwise ask once per frame.
  (Object?, bool?, int)? _failedUnder;

  /// What [ShareService.changes] last said, or the service's last value.
  ShareAvailability? _heard;
  ShareLook? _looks;

  /// Whether this database can share now, as last heard; null before
  /// anything was — the share entry of a folder is then absent.
  ShareAvailability? get availability => _heard;

  /// Bumped by every [refresh], so a slow read never lands over a newer one.
  int _reads = 0;

  /// Starts following sharing, once. An account the pairing already knows
  /// is unpaired starts nothing: its rows have no partner to name. [asker]
  /// is the page state asking; after a failed start only a new one, a
  /// pairing change or a database switch asks again.
  void start({Object? asker}) {
    if (_started || _disposed) return;
    final paired = PairingService.pairedInMemory;
    if (paired == false) return;
    final under = (asker, paired, ShareService.databaseGeneration);
    if (under == _failedUnder) return;
    _started = true;
    if (value == null && !_holdEnded) {
      _holdLimit ??= Timer(AppConstants.partnerLookHoldLimit, _endHold);
    }
    unawaited(_open(under));
  }

  Future<void> _open((Object?, bool?, int) under) async {
    try {
      final service = await openService();
      if (_disposed) return;
      _service = service;
      _availability = service.changes.listen(
        (availability) {
          _heard = availability;
          _publish();
        },
        onError: (Object e, StackTrace st) =>
            debugPrint('[PartnerLookReader] availability: $e\n$st'),
      );
      await refresh();
    } catch (e, st) {
      // The rows keep the look they had; the next page state asks again.
      debugPrint('[PartnerLookReader] sharing not read: $e\n$st');
      _started = false;
      _failedUnder = under;
      if (!_disposed) {
        _holdEnded = true;
        _holdLimit?.cancel();
        _holdLimit = null;
        notifyListeners();
      }
    }
  }

  /// Reads the notes look and the mark switch again — one statement — and
  /// repaints when either moved. Nothing before [start] took.
  Future<void> refresh() async {
    final service = _service;
    if (service == null) return;
    final read = ++_reads;
    try {
      final looks = await service.looks();
      if (_disposed || read != _reads) return;
      _looks = looks;
      _publish();
    } catch (e, st) {
      debugPrint('[PartnerLookReader] look not read: $e\n$st');
      _endHold();
    }
  }

  PartnerLook? _build() {
    final heard = _heard;
    final looks = _looks;
    if (heard == null || looks == null) return null;
    final audience = heard.audience;
    return PartnerLook(
      noteLook: looks.noteLook,
      partner: audience?.members.firstOrNull,
      name: audience?.displayName,
      markMine: looks.markMine,
      unpaired: audience == null,
    );
  }

  ShareAvailability? _told;

  /// Repaints when the look moved, or when only whether the database can
  /// share did — the share entry reads that.
  void _publish() {
    if (_disposed) return;
    final next = _build();
    if (next == null) return;
    _holdLimit?.cancel();
    _holdLimit = null;
    if (next != value) {
      _told = _heard;
      value = next;
    } else if (_heard != _told) {
      _told = _heard;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _holdLimit?.cancel();
    unawaited(_availability?.cancel());
    super.dispose();
  }
}
