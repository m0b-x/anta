import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/push_constants.dart';
import '../../constants/settings_keys.dart';
import '../../database/database_lifecycle.dart';
import '../../models/pair_record.dart';
import '../../utils/pairing_error.dart';
import '../pairing_gateway.dart';
import 'push_address_source.dart';
import 'push_relay.dart';

/// Keeps this device's entry in the pair's document true
/// (`docs/cloud-shared-freshness.md` §7): written while the open database is
/// paired and syncing and a relay is known, removed — and the address given
/// up — when the pair ends, at sign-out and when sync stops.
///
/// It acts on what the app already hears rather than asking for more: every
/// server answer of which pair the account is in ([heardPairs] — the shared
/// read of each sync run, the pairing's reconcile), the end of a pair this
/// device wrote ([endedByMe]), and a leave ([leave]). An install that holds
/// no address and hears an empty answer does nothing at all: no relay is
/// read, no address asked for, no statement run. Global like the gateways;
/// what it remembers is for the open database alone
/// ([DatabaseLifecycle.generation]), so a switch starts it over. Never
/// throws to its callers.
class PushRegistry {
  /// The most devices the rules let one member hold in a pair.
  static const int maxDevices = 5;

  final PairingGateway _gateway;
  final PushAddressSource _addresses;
  final PushRelay _relay;
  final Future<bool> Function(String uid) _shares;
  final Future<String?> Function() _storedPair;
  final Future<String> Function() _deviceId;
  final String? Function() _signedIn;
  final Future<SharedPreferences> _prefs;
  final DateTime Function() _clock;
  final Duration _leaveDeadline;
  final void Function()? _inUse;

  /// The pair this process wrote this device's entry into, for the
  /// database open then.
  ({int generation, String pairId, String uid})? _written;

  /// The address last written there.
  String? _writtenAddress;

  StreamSubscription<String>? _renewals;

  /// The calls in order, each after the one before: a leave must not
  /// overtake the write it undoes.
  Future<void> _chain = Future.value();

  /// [shares] answers whether the open database is paired and syncing as
  /// [uid], from local reads; [storedPair] the pair it holds or last held,
  /// for an end or a leave heard before anything in this process;
  /// [signedIn] the account signed in now; [inUse] is told each time an
  /// address is taken into use or confirmed, which is when a message can
  /// arrive for it.
  PushRegistry({
    required PairingGateway gateway,
    required PushAddressSource addresses,
    required PushRelay relay,
    required Future<bool> Function(String uid) shares,
    required Future<String?> Function() storedPair,
    required Future<String> Function() deviceId,
    required String? Function() signedIn,
    required Future<SharedPreferences> prefs,
    DateTime Function() clock = DateTime.now,
    Duration leaveDeadline = kPushLeaveDeadline,
    void Function()? inUse,
  }) : _inUse = inUse,
       _gateway = gateway,
       _addresses = addresses,
       _relay = relay,
       _shares = shares,
       _storedPair = storedPair,
       _deviceId = deviceId,
       _signedIn = signedIn,
       _prefs = prefs,
       _clock = clock,
       _leaveDeadline = leaveDeadline;

  /// The pair this device's entry stands in for the open database, as far
  /// as this process knows.
  ({String pairId, String uid})? get _current {
    final written = _written;
    if (written == null || written.generation != DatabaseLifecycle.generation) {
      return null;
    }
    return (pairId: written.pairId, uid: written.uid);
  }

  /// The server's answer of which active [pairs] [uid] is in. The earliest
  /// wins, as the pairing keeps it.
  Future<void> heardPairs(String uid, List<PairRecord> pairs) =>
      _queue('pair', () => _heard(uid, pairs));

  /// This device ended [pairId] as [uid], and the pair's document says so:
  /// the partner's phone is told at once, and this device's address dies
  /// with the pair.
  Future<void> endedByMe(String pairId, String uid) => _queue('end', () async {
    _relay.poke(pairId, urgent: true);
    if (!await _addresses.holds()) return;
    final current = _current;
    await _remove(pairId, uid);
    // A race's losing pair: the one this device stays in keeps its address.
    if (current != null && current.pairId != pairId) return;
    await _addresses.giveUp();
    _forget();
  });

  /// Sign-out, or sync stopped for the open database: the entry goes while
  /// [uid] can still write it, and the address with it. The whole of it —
  /// the wait for a call in flight included — is bounded, so a sign-out
  /// offline goes on; what did not finish by then finishes on its own.
  Future<void> leave(String? uid) {
    // Whatever is in flight for this account is not written after this.
    _forget();
    final step = _queue('leave', () async {
      if (!await _addresses.holds()) return;
      final pairId = _current?.pairId ?? await _storedPair();
      if (uid != null && pairId != null) await _remove(pairId, uid);
      await _addresses.giveUp();
      _forget();
    });
    final done = Completer<void>();
    final deadline = Timer(_leaveDeadline, () {
      if (done.isCompleted) return;
      debugPrint('[PushRegistry] leave: past its deadline');
      done.complete();
    });
    step.whenComplete(() {
      deadline.cancel();
      if (!done.isCompleted) done.complete();
    }).ignore();
    return done.future;
  }

  Future<void> _heard(String uid, List<PairRecord> pairs) async {
    final generation = DatabaseLifecycle.generation;
    final live = [
      for (final pair in pairs)
        if (pair.isActive && pair.contains(uid)) pair,
    ];
    if (live.isEmpty) {
      // Nothing is asked of anything unless this install holds an address.
      if (!await _addresses.holds()) return;
      final pairId = _current?.pairId ?? await _storedPair();
      if (pairId != null) await _remove(pairId, uid);
      await _addresses.giveUp();
      _forget();
      return;
    }
    live.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.pairId.compareTo(b.pairId);
    });
    final pair = live.first;
    final previous = _current;
    if (previous != null && previous.pairId != pair.pairId) {
      // A later pair carries a new address (decision n).
      await _remove(previous.pairId, previous.uid);
      await _addresses.giveUp();
      _forget();
    }
    if (!await _shares(uid)) return;
    if (await _relay.refresh() == null) return;
    final address = await _addresses.current();
    if (address == null) return;
    final deviceId = await _deviceId();
    // A leave, a switch or another account since the answer was asked for:
    // it no longer speaks for whoever holds the phone.
    if (_signedIn() != uid || DatabaseLifecycle.generation != generation) {
      return;
    }
    _written = (generation: generation, pairId: pair.pairId, uid: uid);
    _follow();
    _inUse?.call();
    final mine = pair.devicesOf(uid);
    final entry = mine[deviceId];
    if (entry != null &&
        entry.id == address &&
        entry.kind == _addresses.kind &&
        await _writtenRecently(pair.pairId, address)) {
      _writtenAddress = address;
      return;
    }
    await _write(pair.pairId, uid, deviceId, address, drop: _drops(mine, deviceId));
  }

  /// My devices this write takes out: each one sixty days older than the
  /// newest of mine — the server's stamps against each other, never against
  /// this phone's clock — and, when that still leaves no room beside this
  /// device, the oldest until there is.
  static List<String> _drops(
    Map<String, PairPushDevice> mine,
    String deviceId,
  ) {
    if (mine.isEmpty) return const [];
    final newest = mine.values
        .map((device) => device.at)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final drop = <String>[
      for (final MapEntry(key: id, value: device) in mine.entries)
        if (id != deviceId &&
            newest.difference(device.at) > kPushDeviceStale)
          id,
    ];
    final others =
        [
          for (final MapEntry(key: id, value: device) in mine.entries)
            if (id != deviceId && !drop.contains(id)) (id, device.at),
        ]..sort((a, b) {
          final byTime = a.$2.compareTo(b.$2);
          return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
        });
    for (var i = 0; others.length - i > maxDevices - 1; i++) {
      drop.add(others[i].$1);
    }
    return drop;
  }

  /// Whether this install wrote [address] into [pairId] less than seven
  /// days ago by its own clock.
  Future<bool> _writtenRecently(String pairId, String address) async {
    final stored = (await _prefs).getString(SettingsKeys.pushWritten);
    if (stored == null) return false;
    final parts = stored.split('|');
    if (parts.length != 3 || parts[0] != pairId || parts[1] != address) {
      return false;
    }
    final at = int.tryParse(parts[2]);
    if (at == null) return false;
    final since = _clock().difference(DateTime.fromMillisecondsSinceEpoch(at));
    return !since.isNegative && since < kPushDeviceRefresh;
  }

  /// Writes again when the platform names a new address while this device
  /// stands in a pair.
  void _follow() {
    _renewals ??= _addresses.addresses.listen((address) {
      if (_current == null || address == _writtenAddress) return;
      unawaited(
        _queue('renewal', () async {
          final again = _current;
          if (again == null || address == _writtenAddress) return;
          if (_signedIn() != again.uid) return;
          await _write(again.pairId, again.uid, await _deviceId(), address);
        }),
      );
    });
  }

  Future<void> _write(
    String pairId,
    String uid,
    String deviceId,
    String address, {
    List<String> drop = const [],
  }) async {
    final now = _clock();
    await _gateway.writePushDevice(
      pairId: pairId,
      uid: uid,
      deviceId: deviceId,
      device: PairPushDevice(id: address, kind: _addresses.kind, at: now),
      drop: drop,
    );
    _writtenAddress = address;
    await (await _prefs).setString(
      SettingsKeys.pushWritten,
      '$pairId|$address|${now.millisecondsSinceEpoch}',
    );
  }

  Future<void> _remove(String pairId, String uid) async {
    try {
      await _gateway.removePushDevices(
        pairId: pairId,
        uid: uid,
        deviceIds: [await _deviceId()],
      );
      await (await _prefs).remove(SettingsKeys.pushWritten);
    } on PairingException catch (e) {
      // The address is given up all the same, so an entry left behind
      // names nothing that can receive.
      debugPrint('[PushRegistry] entry not removed: ${e.error.name}');
    }
  }

  void _forget() {
    _written = null;
    _writtenAddress = null;
  }

  Future<void> _queue(String what, Future<void> Function() step) {
    final next = _chain.then((_) async {
      try {
        await step();
      } catch (e) {
        debugPrint('[PushRegistry] $what failed: $e');
      }
    });
    _chain = next;
    return next;
  }

  /// Stops following the platform's renewals.
  Future<void> dispose() async {
    await _renewals?.cancel();
    _renewals = null;
  }
}
