import 'dart:async';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/models/share_notice.dart';
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
  ShareNoteLook notes = ShareNoteLook.avatar;
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
  Future<ShareChange> setFolderShared(String id, bool on) async {
    _ready();
    folderShares.add((id, on));
    return _answer();
  }

  @override
  Future<int> stopAll() async {
    stops++;
    await _held();
    return 1;
  }

  /// Every [overview]'s `withCounts`, in order.
  final List<bool> countReads = [];

  @override
  Future<ShareOverview> overview({bool withCounts = false}) async {
    overviews++;
    countReads.add(withCounts);
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

  /// Every [setCategoryShown] as `(id, shown)`, in order.
  final List<(String, bool)> shownSets = [];

  /// When set, every settings write throws it.
  Object? settingsFailure;

  /// When set, the next settings write waits on it before it stores, as a
  /// real one waits on the calendar's reload.
  Completer<void>? settingsHold;

  Future<void> _settingsHeld() async {
    final parked = settingsHold;
    settingsHold = null;
    if (parked != null) await parked.future;
  }

  @override
  Future<int> setCategoryShown(String id, bool shown) async {
    await _settingsHeld();
    final failure = settingsFailure;
    if (failure != null) throw failure;
    shownSets.add((id, shown));
    final wasHidden = hidden.contains(id);
    hidden = shown ? (Set.of(hidden)..remove(id)) : {...hidden, id};
    final armed = shown || wasHidden ? 0 : armedByCategory[id] ?? 0;
    // The service's own contract: a hide that took alerts off is said once
    // it is written.
    if (armed > 0) {
      ShareService.notify(
        ShareHiddenWithAlerts(
          categoryId: id,
          name: CalendarCategories.byId(id)?.name ?? id,
        ),
      );
    }
    return armed;
  }

  /// The partner's events holding an armed alert of mine, by the category
  /// they draw under: what [armedOnPartner] counts and a hide reports.
  Map<String, int> armedByCategory = {};

  /// Calls of [armedOnPartner], by the category asked for (null: all).
  final List<String?> armedReads = [];

  /// When set, [armedOnPartner] waits on it before it answers.
  Completer<void>? armedHold;

  @override
  Future<int> armedOnPartner({String? categoryId}) async {
    armedReads.add(categoryId);
    final parked = armedHold;
    if (parked != null) await parked.future;
    if (categoryId != null) return armedByCategory[categoryId] ?? 0;
    return armedByCategory.values.fold<int>(0, (sum, n) => sum + n);
  }

  /// Reads of [looks] and [alerts].
  int settingsReads = 0;

  @override
  Future<ShareLook> looks() async {
    settingsReads++;
    return ShareLook(eventLook: look, noteLook: notes, markMine: mine);
  }

  @override
  Future<ShareEventLook> eventLook() async => look;

  @override
  Future<void> setEventLook(ShareEventLook value) async {
    await _settingsHeld();
    final failure = settingsFailure;
    if (failure != null) throw failure;
    look = value;
  }

  @override
  Future<ShareNoteLook> noteLook() async => notes;

  @override
  Future<void> setNoteLook(ShareNoteLook value) async {
    await _settingsHeld();
    final failure = settingsFailure;
    if (failure != null) throw failure;
    notes = value;
  }

  @override
  Future<bool> markMine() async => mine;

  @override
  Future<void> setMarkMine(bool value) async => mine = value;

  @override
  Future<ShareAlerts> alerts() async {
    settingsReads++;
    return shareAlerts;
  }

  @override
  Future<void> setAlerts(ShareAlerts value) async => shareAlerts = value;

  @override
  Future<Set<String>> hiddenCategories() async => hidden;

  @override
  Future<void> setHiddenCategories(Set<String> ids) async => hidden = ids;
}
