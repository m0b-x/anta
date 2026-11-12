import 'dart:async';

import 'package:anta/models/share_settings.dart';
import 'package:anta/services/share_service.dart';

/// A [ShareService] stand-in for the surfaces and blocs that read one: an
/// availability the test sets, a record of every share write, and the
/// receiver's settings in memory.
///
/// [changes] replays the current value to every new listener, as the real
/// service does — a fake that stayed silent until the next change would let
/// a start-path bug through.
class FakeShareService implements ShareService {
  FakeShareService({ShareAvailability availability = const ShareNotPaired()})
    : _availability = availability;

  ShareAvailability _availability;
  final StreamController<ShareAvailability> _controller =
      StreamController<ShareAvailability>.broadcast();

  /// Every share write as `(id, on)`, in order.
  final List<(String, bool)> eventShares = [];
  final List<(String, bool)> folderShares = [];

  /// `table/id` of every row the partner shares.
  final Set<String> partnerRows = {};

  ShareEventLook look = ShareEventLook.outlined;
  bool mine = true;
  ShareAlerts shareAlerts = ShareAlerts.own;
  Set<String> hidden = const {};

  /// Sets [availability] and tells every listener.
  void emit(ShareAvailability next) {
    _availability = next;
    _controller.add(next);
  }

  @override
  ShareAvailability get availability => _availability;

  @override
  Stream<ShareAvailability> get changes {
    late final StreamController<ShareAvailability> replay;
    StreamSubscription<ShareAvailability>? live;
    replay = StreamController<ShareAvailability>(
      onListen: () {
        replay.add(_availability);
        live = _controller.stream.listen(replay.add);
      },
      onCancel: () => live?.cancel(),
    );
    return replay.stream;
  }

  @override
  Future<bool> setEventShared(String id, bool on) async {
    if (_availability is! ShareReady) throw ShareRefused(_availability);
    eventShares.add((id, on));
    return true;
  }

  @override
  Future<bool> setFolderShared(String id, bool on) async {
    if (_availability is! ShareReady) throw ShareRefused(_availability);
    folderShares.add((id, on));
    return true;
  }

  @override
  Future<bool> isFromPartner(String table, String id) async =>
      partnerRows.contains('$table/$id');

  @override
  Future<ShareEventLook> eventLook() async => look;

  @override
  Future<void> setEventLook(ShareEventLook value) async => look = value;

  @override
  Future<bool> markMine() async => mine;

  @override
  Future<void> setMarkMine(bool value) async => mine = value;

  @override
  Future<ShareAlerts> alerts() async => shareAlerts;

  @override
  Future<void> setAlerts(ShareAlerts value) async => shareAlerts = value;

  @override
  Future<Set<String>> hiddenCategories() async => hidden;

  @override
  Future<void> setHiddenCategories(Set<String> ids) async => hidden = ids;
}
