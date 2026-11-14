import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/utils/share_leave_voice.dart';

/// One bar per leave of the partner's share: the front-most page that
/// leaves says it, a leave under pages that all stay is said at once —
/// decided by who leaves, asked of the pages in front through the probe
/// each handed over when it opened.
void main() {
  /// A page that answers its probe from [gone] — whether its own row is
  /// gone when asked — and counts the times it was asked.
  final pages = <String, _Page>{};
  _Page page(String name) => pages.putIfAbsent(name, () => _Page(name));

  late List<String> said;

  void open(String name) =>
      ShareLeaveVoice.open(page(name), () async => page(name).probe());

  Future<void> leave(String name, {bool ownerUnknown = false}) =>
      ShareLeaveVoice.leave(
        page(name),
        (forShare) => said.add(forShare ? '$name:share' : name),
        ownerUnknown: ownerUnknown,
      );

  setUp(() => said = []);

  tearDown(() {
    ShareLeaveVoice.reset();
    pages.clear();
  });

  group('her folder and her note in it, both leave', () {
    test('the folder first: only the note speaks, when its own leave '
        'lands', () async {
      open('folder');
      open('note');
      page('note').gone = true;

      await leave('folder');
      expect(said, isEmpty, reason: 'the note in front leaves too');
      await leave('note');

      expect(said, ['note:share'], reason: 'the folder was silenced for it');
    });

    test('the note first: the folder under it, heard while the note is '
        'still closing, stays silent', () async {
      open('folder');
      open('note');

      await leave('note');
      ShareLeaveVoice.popped(page('note'));
      await leave('folder');

      expect(said, ['note']);
      expect(page('note').asked, 0, reason: 'a page that left is not asked');
    });
  });

  group('her folder F, a page of mine, her other folder G', () {
    test('F alone leaves: F speaks at once, over the pages that '
        'stay', () async {
      open('F');
      open('mine');
      open('G');

      final leaving = leave('F');
      await leaving;

      expect(said, ['F']);
      expect(page('mine').asked, 1);
      expect(page('G').asked, 1);
    });

    test('both leave, F heard first: one bar, G\'s', () async {
      open('F');
      open('mine');
      open('G');
      page('G').gone = true;

      await leave('F');
      await leave('G');

      expect(said, ['G:share']);
    });

    test('both leave, G heard first: one bar, G\'s', () async {
      open('F');
      open('mine');
      open('G');
      page('G').gone = true;

      await leave('G');
      await leave('F');

      expect(said, ['G']);
    });

    test('a leave heard while F still asks counts as leaving for the page '
        'under F', () async {
      open('H');
      open('F');
      open('mine');
      final answer = Completer<bool>();
      ShareLeaveVoice.open(page('mine'), () => answer.future);

      final fLeaving = leave('F');
      await leave('H');
      expect(said, isEmpty, reason: 'F is leaving, in front of H');
      answer.complete(false);
      await fLeaving;

      expect(said, ['F']);
    });
  });

  group('an editor that has not learned whose its note is', () {
    test('above her folder, the folder heard first: one bar, with the '
        'share\'s words', () async {
      open('folder');
      open('editor');
      page('editor').gone = true;

      await leave('folder');
      await leave('editor', ownerUnknown: true);

      expect(said, ['editor:share']);
    });

    test('above her folder, the editor heard first: one bar, with the '
        'share\'s words', () async {
      open('folder');
      open('editor');
      page('folder').gone = true;

      await leave('editor', ownerUnknown: true);
      await leave('folder');

      expect(said, ['editor:share']);
    });

    test('over nothing that leaves: its own words', () async {
      open('folder');
      open('editor');

      await leave('editor', ownerUnknown: true);

      expect(said, ['editor']);
    });
  });

  test('her folder under my own note that stays: the folder speaks at '
      'once, over it', () async {
    open('folder');
    open('my note');

    await leave('folder');

    expect(said, ['folder']);
  });

  test('a page of mine in front that loses its own row in the same run: '
      'it speaks in its own words, the folder under it is silent', () async {
    open('folder');
    open('my note');
    page('my note').gone = true;

    await leave('folder');
    // A page that knows the note is mine ignores the owed share line.
    await ShareLeaveVoice.leave(page('my note'), (_) => said.add('my note'));

    expect(said, ['my note']);
  });

  test('a probe that throws counts as staying: two bars rather than '
      'none', () async {
    open('folder');
    ShareLeaveVoice.open(page('broken'), () async => throw StateError('x'));

    await leave('folder');

    expect(said, ['folder']);
  });

  test('the note first and gone: the folder, now in front, speaks too — two '
      'closings, two lines', () async {
    open('folder');
    open('note');

    await leave('note');
    ShareLeaveVoice.exit(page('note'));
    await leave('folder');

    expect(said, ['note', 'folder']);
  });

  test('a page popped by the person is no longer counted, before its '
      'closing ends', () async {
    open('folder');
    open('note');
    page('note').gone = true;
    ShareLeaveVoice.popped(page('note'));

    await leave('folder');

    expect(said, ['folder']);
    expect(page('note').asked, 0);
  });

  test('a page that spoke stops silencing once its route is gone', () async {
    open('folder');
    open('note');
    await leave('note');
    ShareLeaveVoice.exit(page('note'));

    open('other');
    await leave('other');

    expect(said, ['note', 'other']);
  });

  test('a page never opened — unrecorded — speaks', () async {
    await leave('stray');

    expect(said, ['stray']);
  });

  test('nothing in front: said at once, and no page is asked', () {
    open('mine');
    open('folder');

    unawaited(leave('folder'));

    expect(said, ['folder'], reason: 'synchronously, before any await');
    expect(page('mine').asked, 0);
  });

  test('a database switch empties the registry', () async {
    open('folder');
    open('note');
    await leave('note');

    DatabaseLifecycle.notifyDatabaseSwitching();
    await leave('folder');

    expect(said, ['note', 'folder'], reason: 'the note left with the old db');
  });

  // Re-check finding 1: a probe whose read stalls held the leave for good,
  // its page counted as leaving, and silenced every later leave under it.
  test('a probe that never answers counts as staying once its bound has '
      'passed, and silences nothing after', () {
    fakeAsync((async) {
      open('outer');
      open('folder');
      ShareLeaveVoice.open(page('stalled'), () => Completer<bool>().future);

      var done = false;
      leave('folder').then((_) => done = true);
      async.flushMicrotasks();
      // Both pages go, as they do: the folder closes itself, the person
      // closes the other.
      ShareLeaveVoice.exit(page('folder'));
      ShareLeaveVoice.exit(page('stalled'));
      async.elapse(
        AppConstants.shareLeaveProbeLimit - const Duration(milliseconds: 1),
      );
      expect(said, isEmpty, reason: 'still within the bound');

      async.elapse(const Duration(milliseconds: 1));
      expect(said, ['folder']);
      expect(done, isTrue);

      leave('outer');
      async.flushMicrotasks();
      expect(said, ['folder', 'outer']);
    });
  });

  // Re-check finding 2: the registry was emptied by a switch while a leave
  // asked, and the bar was said for the database that closed.
  test('a database switch while a leave asks: nothing is said for the old '
      'database', () async {
    final answer = Completer<bool>();
    open('folder');
    ShareLeaveVoice.open(page('slow'), () => answer.future);

    final pending = leave('folder');
    await pumpEventQueue();
    DatabaseLifecycle.notifyDatabaseSwitching();
    answer.complete(false);
    await pending;

    expect(said, isEmpty);
  });

  // The last review's sequences, and the lead's: a leave is silenced only by
  // a page in front that has left or is still there to leave, and a leave
  // silenced for a page that then goes without leaving is said after all.
  group('whoever closes what during an ask: one bar', () {
    test('the page in front speaks on its own leave and is disposed while '
        'its stalled probe is out: the bound does not make the page under '
        'it speak too', () {
      fakeAsync((async) {
        open('folder');
        ShareLeaveVoice.open(page('note'), () => Completer<bool>().future);

        leave('folder');
        async.elapse(const Duration(milliseconds: 300));
        leave('note');
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 300));
        ShareLeaveVoice.exit(page('note'));
        async.elapse(AppConstants.shareLeaveProbeLimit);

        expect(said, ['note']);
      });
    });

    test('the page in front closed by the person while asked, then '
        'answering "gone": it will never speak, so the page under it does', () {
      fakeAsync((async) {
        final answer = Completer<bool>();
        open('folder');
        ShareLeaveVoice.open(page('note'), () => answer.future);

        leave('folder');
        async.flushMicrotasks();
        ShareLeaveVoice.popped(page('note'));
        ShareLeaveVoice.exit(page('note'));
        async.elapse(const Duration(milliseconds: 200));
        answer.complete(true);
        async.elapse(AppConstants.shareLeaveProbeLimit);

        expect(said, ['folder']);
      });
    });

    test('silenced for a page in front that answered "gone", which the '
        'person then pops before its own leave lands: said at the pop, '
        'once', () async {
      open('folder');
      open('note');
      page('note').gone = true;

      await leave('folder');
      expect(said, isEmpty);

      ShareLeaveVoice.popped(page('note'));
      expect(said, ['folder']);
      ShareLeaveVoice.exit(page('note'));
      expect(said, ['folder']);
    });

    test(
      'silenced for a page in front that then leaves by itself: that '
      'page speaks, in the share\'s words, and the kept line never',
      () async {
        open('folder');
        open('note');
        page('note').gone = true;

        await leave('folder');
        await leave('note');
        ShareLeaveVoice.exit(page('note'));

        expect(said, ['note:share']);
      },
    );

    test('a database switch between the silencing and the pop: nothing is '
        'said', () async {
      open('folder');
      open('note');
      page('note').gone = true;

      await leave('folder');
      DatabaseLifecycle.notifyDatabaseSwitching();
      ShareLeaveVoice.popped(page('note'));

      expect(said, isEmpty);
    });

    test('two leaves silenced for one page in front, which is popped: one '
        'bar, the front-most silenced page\'s', () async {
      open('outer');
      open('folder');
      open('note');
      page('note').gone = true;

      await leave('outer');
      await leave('folder');
      ShareLeaveVoice.popped(page('note'));
      ShareLeaveVoice.exit(page('note'));

      expect(said, ['folder']);
    });

    // Finding 8's missing pin.
    test('a later leave under a stalled page that is still open speaks '
        'after its own bound', () {
      fakeAsync((async) {
        open('outer');
        open('folder');
        ShareLeaveVoice.open(page('stalled'), () => Completer<bool>().future);

        leave('folder');
        async.elapse(AppConstants.shareLeaveProbeLimit);
        expect(said, ['folder']);
        ShareLeaveVoice.exit(page('folder'));

        leave('outer');
        async.elapse(
          AppConstants.shareLeaveProbeLimit - const Duration(milliseconds: 1),
        );
        expect(said, ['folder']);
        async.elapse(const Duration(milliseconds: 1));
        expect(said, ['folder', 'outer']);
      });
    });

    // Leg 9 verification, finding 4: a route removed from under gets no
    // pop, only its disposal.
    test('a kept leave is said when its page is disposed without ever being '
        'popped', () async {
      open('folder');
      open('note');
      page('note').gone = true;

      await leave('folder');
      ShareLeaveVoice.exit(page('note'));

      expect(said, ['folder']);
    });

    // Finding 5: the reverse of the case above tells the front-most
    // silenced page's leave from the last silenced one's.
    test('the folder silenced first, then the outer folder, for one popped '
        'page: the folder\'s bar', () async {
      open('outer');
      open('folder');
      open('note');
      page('folder').gone = true;
      page('note').gone = true;

      await leave('folder');
      await leave('outer');
      ShareLeaveVoice.popped(page('note'));
      ShareLeaveVoice.exit(page('note'));

      expect(said, ['folder']);
    });
  });

  // Leg 9 verification, finding 1: a leave silenced by several pages in
  // front is said only when none of them is left to speak.
  group('a leave silenced by several pages in front', () {
    test('the front-most is popped, the next then leaves by itself: one bar, '
        'its — in the share\'s words, the outer\'s leave having moved to '
        'it', () async {
      open('outer');
      open('folder');
      open('note');
      page('folder').gone = true;
      page('note').gone = true;

      await leave('outer');
      ShareLeaveVoice.popped(page('note'));
      ShareLeaveVoice.exit(page('note'));
      await leave('folder');
      ShareLeaveVoice.exit(page('folder'));

      expect(said, ['folder:share']);
    });

    test('the next one is asking the front-most when it is popped: one '
        'bar', () async {
      open('outer');
      open('folder');
      var asks = 0;
      final second = Completer<bool>();
      ShareLeaveVoice.open(page('note'), () {
        asks++;
        return asks == 1 ? Future.value(true) : second.future;
      });
      page('folder').gone = true;

      await leave('outer');
      final folder = leave('folder');
      await pumpEventQueue();
      ShareLeaveVoice.popped(page('note'));
      ShareLeaveVoice.exit(page('note'));
      second.complete(true);
      await folder;

      expect(said, hasLength(1));
    });

    test('both popped before either leaves: the outer\'s bar, once', () async {
      open('outer');
      open('folder');
      open('note');
      page('folder').gone = true;
      page('note').gone = true;

      await leave('outer');
      ShareLeaveVoice.popped(page('note'));
      ShareLeaveVoice.exit(page('note'));
      expect(said, isEmpty);
      ShareLeaveVoice.popped(page('folder'));
      ShareLeaveVoice.exit(page('folder'));

      expect(said, ['outer']);
    });

    // Leg 11: a page that drops a leave it was among the silencers of
    // speaks for that leave too — in the share's words.
    test(
      'kept with the top page, the middle one among its others leaves '
      'while the top stays: the middle speaks in the share\'s words',
      () async {
        open('outer');
        open('middle');
        open('top');
        page('middle').gone = true;
        page('top').gone = true;

        await leave('outer');
        page('top').gone = false;
        await leave('middle');

        expect(said, ['middle:share']);
      },
    );
  });

  // Finding 7: a bare reset while an ask is out left the count of asks
  // below zero, and later pages that left were no longer counted.
  test('a reset while an ask is out: a later page that speaks and is '
      'disposed during another ask still silences it', () {
    fakeAsync((async) {
      final answer = Completer<bool>();
      open('folder');
      ShareLeaveVoice.open(page('note'), () => answer.future);
      leave('folder');
      async.flushMicrotasks();
      ShareLeaveVoice.reset();
      answer.complete(false);
      async.flushMicrotasks();
      said.clear();

      open('f2');
      ShareLeaveVoice.open(page('n2'), () => Completer<bool>().future);
      leave('f2');
      async.elapse(const Duration(milliseconds: 300));
      leave('n2');
      async.elapse(const Duration(milliseconds: 300));
      ShareLeaveVoice.exit(page('n2'));
      async.elapse(AppConstants.shareLeaveProbeLimit);

      expect(said, ['n2']);
    });
  });
}

class _Page {
  _Page(this.name);

  final String name;
  bool gone = false;
  int asked = 0;

  bool probe() {
    asked++;
    return gone;
  }

  @override
  String toString() => name;
}
