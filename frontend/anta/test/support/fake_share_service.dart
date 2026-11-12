import 'dart:async';

import 'package:anta/models/share_overview.dart';
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

  final StreamController<void> _runs = StreamController<void>.broadcast();

  /// Sets [availability] and tells every listener.
  void emit(ShareAvailability next) {
    _availability = next;
    _controller.add(next);
  }

  /// A sync run of the open database ended.
  void endRun() => _runs.add(null);

  /// Whether anything still listens to [changes] or [runsEnded].
  bool get heard => _controller.hasListener || _runs.hasListener;

  /// When set, the next share write waits on it before it answers — what
  /// it answers is the [nextChange] of when it started.
  Completer<void>? hold;

  /// When set, every [refreshShared] lasts until it completes, as the
  /// engine's read does.
  Completer<void>? sharedRead;

  Future<void> _held() async {
    final parked = hold;
    hold = null;
    if (parked != null) await parked.future;
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

  /// What [overview] answers; the test sets it.
  ShareOverview shareOverview = ShareOverview.empty;

  /// What every share write answers; the test sets it.
  ShareChange nextChange = ShareChange.none;

  /// Every category write: a set from [setCategoriesShared], or the one
  /// category of [setCategoryShared] as `{id}` / `{}`.
  final List<Set<String>> categorySets = [];
  final List<ShareChange> undone = [];
  int overviews = 0;
  int stops = 0;
  int sharedReads = 0;

  void _ready() {
    if (_availability is! ShareReady) throw ShareRefused(_availability);
  }

  Future<ShareChange> _answer() async {
    final answer = nextChange;
    await _held();
    return answer;
  }

  @override
  Future<ShareChange> setEventShared(String id, bool on) async {
    _ready();
    eventShares.add((id, on));
    return _answer();
  }

  @override
  Future<ShareChange> setCategoryShared(String id, bool on) async {
    _ready();
    categorySets.add({if (on) id});
    return _answer();
  }

  @override
  Future<ShareChange> setCategoriesShared(Set<String> ids) async {
    _ready();
    categorySets.add(ids);
    return _answer();
  }

  @override
  Future<ShareChange> undo(ShareChange change) async {
    _ready();
    undone.add(change);
    return _answer();
  }

  @override
  Future<bool> setFolderShared(String id, bool on) async {
    _ready();
    folderShares.add((id, on));
    return true;
  }

  @override
  Future<int> stopAll() async {
    stops++;
    await _held();
    return 1;
  }

  @override
  Future<ShareOverview> overview() async {
    overviews++;
    return _availability is ShareNotPaired
        ? ShareOverview.empty
        : shareOverview;
  }

  @override
  Future<void> refreshShared() async {
    if (_availability is! ShareReady) return;
    sharedReads++;
    await sharedRead?.future;
  }

  @override
  Stream<void> get runsEnded => _runs.stream;

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
