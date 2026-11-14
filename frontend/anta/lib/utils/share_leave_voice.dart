import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../database/database_lifecycle.dart';

/// Whether a page closes on the run being announced now: asked of the pages
/// in front of a page that leaves, with the predicate the page itself
/// decides its own leave by.
typedef LeavesToo = Future<bool> Function();

/// One line for one leave of the partner's share (share surfaces §6.12,
/// N6): when it ends, every page of hers that is open closes — her folder's
/// pages, her note's editor — and each has its words, but the person is
/// told once: **the front-most page that leaves says it; a leave under
/// pages that all stay is said at once, over them.**
///
/// Decided by who leaves, never by frames, timers or who is hers. Every
/// folder page and note editor takes its place when it opens ([open]),
/// handing over a [LeavesToo] probe, and is taken off when it is disposed
/// ([exit]) or popped by the person ([popped]). When its own leave lands it
/// calls [leave], which is silenced only by a page in front that has left
/// or is still there to leave: one that has already left in this pass
/// (said, or still asking — and, while any leave is still asking, one that
/// left and is gone since), or one still open whose probe answers, when
/// asked now, that its own row is gone. The reloads that make a page leave
/// run after the sync run's hooks, when every removal of that run is
/// already in the database, so that answer is final for the pass. A probe
/// that throws, or has not answered within
/// [AppConstants.shareLeaveProbeLimit], counts as staying: two bars are
/// better than none, and a leave held for good would silence every later
/// leave under its page. That is the bound's price: a probe answering
/// "gone" after it, whose page then leaves, makes two bars.
///
/// A leave silenced only by pages whose probes answered "gone" is kept
/// with the front-most of them, not dropped: **it is said only when none
/// of them is left to speak.** If one of them leaves by itself it speaks —
/// in the share's words when the leave was kept with it — and the kept
/// leave is forgotten. If the page it is kept with goes without leaving —
/// popped by the person, or disposed — the leave moves to the next of them
/// still open, and is said, once, when none is. A database switch empties
/// the registry, kept leaves with it. Of two leaves kept with one page, the
/// front-most silenced page's stays.
///
/// A page of mine in front that loses its own row in the same run for its
/// own reason — my note deleted on another device — is a page that leaves:
/// it speaks in its own words and her page under it is silent. A page that
/// leaves without having learned whose its row was (an editor over cold
/// caches) says the share's words when a leave under it was silenced for it
/// or a page under it leaves too ([leave]'s `ownerUnknown`).
///
/// A page that spoke keeps its place until its route is gone. Both pages
/// close through `Navigator.pop`, `removeRoute` and `removeRouteBelow`,
/// which no `PopScope` can refuse, so a page that spoke is always disposed
/// soon after. The registry is emptied when the database switches; a page
/// that outlives a switch is unrecorded and speaks on its own leave, and a
/// leave still asking across a switch says nothing.
///
/// What an account that never paired pays: one list entry and one closure
/// per open folder page or editor, added and removed — no read, no notify,
/// no rebuild. A probe is only ever called at a leave.
abstract final class ShareLeaveVoice {
  /// How long a page in front is given to answer. A widget suite whose
  /// fake clock runs ahead of the database's real reads lengthens it, or a
  /// read that lands in one real millisecond counts as stalled.
  @visibleForTesting
  static Duration probeLimit = AppConstants.shareLeaveProbeLimit;

  static final List<Object> _present = [];
  static final Map<Object, LeavesToo> _probes = {};

  /// When each present page opened: the later, the nearer the front, kept
  /// past the page's own place so two silenced leaves can be told apart.
  static final Map<Object, int> _order = {};
  static int _opened = 0;

  /// Pages whose own leave is in hand: asking the pages around them, or
  /// said and still closing.
  static final Set<Object> _leaving = {};

  /// Pages that left and are gone while some leave was still asking: they
  /// silence the pages under them until the last ask ends.
  static final Set<Object> _left = {};

  /// Leaves still asking the pages around them.
  static int _asks = 0;

  /// The leave silenced for each page, kept until a page that silenced it
  /// leaves by itself (dropped: that page speaks), or until every one of
  /// them has gone without leaving (said after all).
  static final Map<Object, _Kept> _kept = {};

  /// Pages whose own leave is still asking the pages around them.
  static final Set<Object> _asking = {};

  /// Pages disposed while their leave was still asking, kept counted until
  /// it ends so a page under them stays silent meanwhile.
  static final Set<Object> _exited = {};

  /// [page] opened; the latest opened is in front. [leavesToo] is asked
  /// only when a page under it leaves.
  static void open(Object page, LeavesToo leavesToo) {
    DatabaseLifecycle.registerResetHandler(reset);
    if (!_present.contains(page)) {
      _present.add(page);
      _order[page] = _opened++;
    }
    _probes[page] = leavesToo;
  }

  /// [page] is disposed.
  static void exit(Object page) {
    if (_asking.contains(page)) {
      _exited.add(page);
      return;
    }
    if (!_leaving.contains(page)) _sayKept(page);
    _forget(page);
  }

  /// [page]'s route was popped: by the person, it is in front no more; on
  /// its own leave it stays in front until it is gone.
  static void popped(Object page) {
    if (_leaving.contains(page)) return;
    _sayKept(page);
    _forget(page);
  }

  /// [page] goes without leaving, so it speaks for no leave: the leave kept
  /// with it moves to the next page in front that silenced it and is still
  /// there to leave, and is said only when none is. A database switch
  /// empties [_kept] before any page of the closed one can go.
  static void _sayKept(Object page) {
    for (final kept in _kept.values) {
      kept.others.remove(page);
    }
    final kept = _kept.remove(page);
    if (kept == null) return;
    final next = kept.others.indexWhere(_present.contains);
    if (next < 0) {
      kept.say(kept.forShare);
      return;
    }
    _keep(
      kept.others[next],
      _Kept(kept.say, kept.forShare, kept.order, kept.others.sublist(next + 1)),
    );
  }

  static bool _hasLeft(Object page) =>
      _leaving.contains(page) || _left.contains(page);

  /// [page]'s own leave: [say] unless a page in front of it leaves too —
  /// at once when nothing stands in front or a page in front has already
  /// left, else once the pages in front have answered. `forShare` is true
  /// when a leave under [page] was silenced for it, or, with
  /// [ownerUnknown], when a page under it leaves too: a page that never
  /// learned whose its row was then knows the share ended under it.
  static Future<void> leave(
    Object page,
    void Function(bool forShare) say, {
    bool ownerUnknown = false,
  }) async {
    // A leave speaks only for the database it began under: a switch while
    // it asks empties the registry, and the old database's bar must not be
    // said over the new one.
    final generation = DatabaseLifecycle.generation;
    // A leave silenced for this page, or by it among others, is dropped:
    // this page speaks for it.
    final among = _kept.length;
    _kept.removeWhere((_, kept) => kept.others.contains(page));
    var forShare = _kept.remove(page) != null || _kept.length < among;
    final at = _present.indexOf(page);
    if (at < 0) {
      say(forShare);
      return;
    }
    final order = _order[page]!;
    _leaving.add(page);
    final front = _present.sublist(at + 1);
    if (front.any(_leaving.contains)) {
      _forget(page);
      return;
    }
    final under = ownerUnknown && !forShare ? _present.sublist(0, at) : null;
    if (front.isNotEmpty || (under != null && under.isNotEmpty)) {
      _asking.add(page);
      _asks++;
      final answers = await Future.wait(front.map(_leavesToo));
      final underLeaves = under == null
          ? false
          : (await Future.wait(under.map(_leavesToo))).any((leaves) => leaves);
      if (DatabaseLifecycle.generation != generation) return;
      // A bare reset while this leave asked has zeroed the count already.
      if (_asks > 0) _asks--;
      _asking.remove(page);
      // A "gone" counts only from a page still there to leave: one the
      // person closed meanwhile will never speak. Front-most first.
      final gone = [
        for (var i = front.length - 1; i >= 0; i--)
          if (answers[i] && _present.contains(front[i])) front[i],
      ];
      final leftInFront = front.any(_hasLeft);
      final silenced = gone.isNotEmpty || leftInFront;
      if (silenced) {
        // A page in front that left speaks; else the leave waits with the
        // pages that answered "gone", for one of them to speak.
        if (!leftInFront) {
          _keep(gone.first, _Kept(say, forShare, order, gone.sublist(1)));
        }
        _forget(page);
      } else {
        forShare = forShare || underLeaves;
        if (_exited.contains(page)) _forget(page);
      }
      if (_asks == 0) _left.clear();
      if (silenced) return;
    }
    say(forShare);
  }

  /// Keeps [kept] with [front]: of two leaves silenced for one page, the
  /// front-most silenced page's.
  static void _keep(Object front, _Kept kept) {
    final held = _kept[front];
    if (held == null || held.order < kept.order) _kept[front] = kept;
  }

  static Future<bool> _leavesToo(Object page) async {
    if (_leaving.contains(page)) return true;
    final probe = _probes[page];
    if (probe == null) return false;
    try {
      // Rewrapped: a probe typed narrower than `Future<bool>` (one that
      // only throws) would refuse the timeout's answer.
      return await probe()
          .then<bool>((leaves) => leaves)
          .timeout(probeLimit, onTimeout: () => false);
    } catch (e, stackTrace) {
      debugPrint('[ShareLeaveVoice] probe failed: $e\n$stackTrace');
      return false;
    }
  }

  static void _forget(Object page) {
    if (_leaving.remove(page) && _asks > 0) _left.add(page);
    _present.remove(page);
    _probes.remove(page);
    _order.remove(page);
    _kept.remove(page);
    _asking.remove(page);
    _exited.remove(page);
  }

  /// Empties the registry: the pages it counted belong to the database that
  /// is closing.
  @visibleForTesting
  static void reset() {
    _present.clear();
    _probes.clear();
    _order.clear();
    _leaving.clear();
    _left.clear();
    _asks = 0;
    _kept.clear();
    _asking.clear();
    _exited.clear();
  }
}

/// A leave silenced for a page in front, with what it is said with should
/// every page that silenced it go without leaving.
class _Kept {
  _Kept(this.say, this.forShare, this.order, this.others);

  final void Function(bool forShare) say;
  final bool forShare;

  /// When the silenced page opened.
  final int order;

  /// The other pages in front that answered "gone", front-most first: the
  /// leave moves to the next of them when the page it is kept with goes.
  final List<Object> others;
}
