import 'dart:async';

import 'package:flutter/foundation.dart';

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
  /// (`FolderStorageService.holdsShared`), or a pair is known from memory —
  /// the pairing or the share service already built. Answered without a
  /// statement, so an account that never paired asks nothing.
  static bool mayShare({required bool holdsShared}) =>
      holdsShared ||
      PairingService.pairedInMemory == true ||
      _knownAvailability()?.audience != null;

  /// What the share service built for the open database last evaluated, so
  /// a page pushed from another draws its first frame from it, with
  /// [ShareService.publishedLook], instead of growing a face a frame later.
  static ShareAvailability? _knownAvailability() =>
      PairingService.pairedInMemory == false
      ? null
      : ShareService.knownAvailability;

  /// The database generation [resolve] last asked under: whether this
  /// database is paired is asked once per process and database, never
  /// again by a later menu.
  static int? _askedGeneration;

  /// Drops the record of [resolve] having asked, as a new process would.
  @visibleForTesting
  static void forgetAsked() => _askedGeneration = null;

  /// Whether nothing in memory says if this database is paired — no
  /// pairing or share service built, and no [resolve] asked yet: what a
  /// folder's share entry must learn before its menu or sheet opens.
  static bool get pairingUnknown =>
      PairingService.pairedInMemory == null &&
      ShareService.knownAvailability == null &&
      _askedGeneration != ShareService.databaseGeneration;

  ShareService? _service;
  StreamSubscription<ShareAvailability>? _availability;
  bool _started = false;
  bool _disposed = false;
  bool _failed = false;

  /// Started and still without a look: what a page that holds its first
  /// frame for the look waits on. A read that failed ends the wait.
  bool get pending => _started && value == null && !_failed;

  /// What [ShareService.changes] last said, or the service's last value.
  ShareAvailability? _heard;
  ShareLook? _looks;

  /// Whether this database can share now, as last heard; null before
  /// anything was — the share entry of a folder is then absent.
  ShareAvailability? get availability => _heard;

  /// Learns whether this database is paired when nothing in memory says
  /// ([pairingUnknown]) — the share service's own local reads, no network
  /// — so the first folder menu or row sheet of a process opens with its
  /// share entry in place, the way the calendar's editors ask. A pair
  /// found is followed from then on ([start]); none costs nothing more.
  Future<void> resolve() async {
    if (_disposed || !pairingUnknown) return;
    _askedGeneration = ShareService.databaseGeneration;
    try {
      final service = await openService();
      if (_disposed) return;
      final availability = service.availability;
      if (availability.audience == null) return;
      _heard = availability;
      _looks ??= await service.looks();
      if (_disposed) return;
      _publish();
      start();
    } catch (e, st) {
      debugPrint('[PartnerLookReader] pairing not read: $e\n$st');
    }
  }

  /// Bumped by every [refresh], so a slow read never lands over a newer one.
  int _reads = 0;

  /// Starts following sharing, once. An account the pairing already knows
  /// is unpaired starts nothing: its rows have no partner to name.
  void start() {
    if (_started || _disposed) return;
    if (PairingService.pairedInMemory == false) return;
    _started = true;
    unawaited(_open());
  }

  Future<void> _open() async {
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
      if (!_disposed) {
        _failed = true;
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
    unawaited(_availability?.cancel());
    super.dispose();
  }
}
