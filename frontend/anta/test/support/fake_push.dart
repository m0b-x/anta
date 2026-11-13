import 'dart:async';

import 'package:anta/models/pair_record.dart';
import 'package:anta/services/push/push_address_source.dart';
import 'package:anta/services/push/push_relay.dart';

/// A [PushAddressSource] whose address the test names. Its [addresses]
/// replays the last one to a new listener, as the app's does.
class FakePushAddressSource implements PushAddressSource {
  /// The address the next registration names; null when the platform
  /// cannot name one.
  String? next = 'fid-1';

  /// What [giveUp] makes the next registration name.
  String? renewed = 'fid-2';

  int registrations = 0;
  int giveUps = 0;
  bool held = false;
  String? _last;

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  @override
  String get kind => PairPushDevice.kindFid;

  @override
  Stream<String> get addresses {
    late final StreamController<String> replay;
    StreamSubscription<String>? live;
    replay = StreamController<String>(
      onListen: () {
        final last = _last;
        if (last != null) replay.add(last);
        live = _controller.stream.listen(replay.add);
      },
      onCancel: () => live?.cancel(),
    );
    return replay.stream;
  }

  /// Every call of [giveUp] and [holds], held or not: what the registry asks
  /// of an install that holds nothing must be nothing.
  int giveUpCalls = 0;
  int holdsCalls = 0;

  /// While set, [current] and [giveUp] wait for it — a platform that does
  /// not answer.
  Completer<void>? stall;

  @override
  Future<bool> holds() async {
    holdsCalls++;
    return held;
  }

  @override
  Future<void> payOwed() async {}

  @override
  Future<String?> current() async {
    if (stall case final waiting?) await waiting.future;
    if (_last != null) return _last;
    registrations++;
    final address = next;
    if (address == null) return null;
    held = true;
    _last = address;
    _controller.add(address);
    return address;
  }

  /// The platform renews the installation by itself.
  void renew(String address) {
    _last = address;
    _controller.add(address);
  }

  @override
  Future<void> giveUp() async {
    giveUpCalls++;
    if (stall case final waiting?) await waiting.future;
    if (!held) return;
    giveUps++;
    held = false;
    _last = null;
    next = renewed;
  }
}

/// A [PushRelay] that records each poke instead of sending it.
class FakePushRelay implements PushRelay {
  FakePushRelay({this.address});

  @override
  Uri? address;

  /// What `config/push` names when [refresh] reads it.
  Uri? configured;
  int refreshes = 0;

  final List<({String pair, bool urgent})> pokes = [];

  @override
  Future<Uri?> refresh() async {
    refreshes++;
    if (configured != null) address = configured;
    return address;
  }

  @override
  void poke(String pairId, {required bool urgent}) {
    if (address == null) return;
    pokes.add((pair: pairId, urgent: urgent));
  }

  @override
  void flush() {}
}
