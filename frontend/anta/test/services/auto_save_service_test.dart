import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/auto_save_service.dart';

/// Auto-save is the editor's only guarantee that typed text survives, so the
/// timing rules are the contract: a debounce that coalesces a burst of
/// keystrokes into one write, a periodic sweep that catches a user who keeps
/// typing past the debounce, a force-save that never races an in-flight write,
/// and a bounded retry ladder behind an error status.
///
/// Every timing number below is read off the service (`debounceDelay`,
/// `saveInterval`) or off its observed retry ladder — nothing here hardcodes a
/// duration the service does not itself declare. The one exception is the
/// deliberately long `saveInterval` used by the retry group, which exists only
/// to keep the periodic sweep out of the ladder's way.
class _RecordedSave {
  final String? title;
  final String? content;

  const _RecordedSave(this.title, this.content);
}

class _FakeSaver {
  final List<_RecordedSave> calls = [];

  /// Number of upcoming saves that should throw. `-1` fails forever.
  int failures = 0;

  /// Number of upcoming saves that should raise [SaveHeld] — the page holding
  /// a write while a synced change is filed. `-1` holds forever.
  int holds = 0;

  /// Number of upcoming saves that should raise [SaveRefused] — the row the
  /// write was for is a tombstone. `-1` refuses forever.
  int refusals = 0;

  /// Runs after each save is recorded and before it answers, so a test can
  /// move the baseline exactly while a write is in flight.
  void Function()? duringSave;

  /// When set, every save suspends on this completer, which lets a test hold
  /// a write in flight and observe what the service does meanwhile.
  Completer<void>? gate;

  int get callCount => calls.length;

  _RecordedSave get last => calls.last;

  Future<void> call(String? title, String? content) async {
    calls.add(_RecordedSave(title, content));
    duringSave?.call();
    final pending = gate;
    if (pending != null) await pending.future;
    if (holds != 0) {
      if (holds > 0) holds--;
      throw const SaveHeld('held by the test');
    }
    if (refusals != 0) {
      if (refusals > 0) refusals--;
      throw const SaveRefused('refused by the test');
    }
    if (failures != 0) {
      if (failures > 0) failures--;
      throw StateError('save failed');
    }
  }
}

class _Harness {
  final _FakeSaver saver = _FakeSaver();
  final List<SaveStatus> statuses = [];
  final List<bool> changeFlags = [];

  late final AutoSaveService service;

  String content = 'v0';

  _Harness({Duration? saveInterval, Duration? debounceDelay}) {
    service = AutoSaveService(
      onSave: (title, content) => saver(title, content),
      onChangeDetected: changeFlags.add,
      saveInterval: saveInterval ?? const Duration(seconds: 30),
      debounceDelay: debounceDelay ?? const Duration(seconds: 5),
    );
    service.saveStatusNotifier.addListener(_recordStatus);
  }

  void _recordStatus() => statuses.add(service.saveStatusNotifier.value);

  void track({String title = 'Title', String? initial}) {
    content = initial ?? content;
    service.startTracking(title, content, contentProvider: () => content);
  }

  void type(String next, {String title = 'Title'}) {
    content = next;
    service.onContentChanged(title);
  }

  void dispose() {
    service.saveStatusNotifier.removeListener(_recordStatus);
    service.dispose();
  }
}

void main() {
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
  });

  group('declared timings', () {
    test('the shipped defaults are a 5 s debounce and a 30 s interval', () {
      final h = _Harness();

      expect(h.service.debounceDelay, const Duration(seconds: 5));
      expect(h.service.saveInterval, const Duration(seconds: 30));

      h.dispose();
    });

    test('a fresh service is idle with nothing pending', () {
      final h = _Harness();

      expect(h.service.saveStatusNotifier.value, SaveStatus.saved);
      expect(h.service.hasPendingChanges, isFalse);
      expect(h.saver.callCount, 0);

      h.dispose();
    });
  });

  group('debounce coalescing', () {
    test('a burst of changes produces exactly one save', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        for (int i = 1; i <= 8; i++) {
          h.type('v$i');
          async.elapse(const Duration(milliseconds: 200));
        }
        expect(h.saver.callCount, 0);

        async.elapse(h.service.debounceDelay);

        expect(h.saver.callCount, 1);
        expect(h.saver.last.content, 'v8');
        expect(h.service.hasPendingChanges, isFalse);

        h.dispose();
      });
    });

    test('the debounce does not fire one tick early', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.type('v1');
        async.elapse(h.service.debounceDelay - const Duration(milliseconds: 1));
        expect(h.saver.callCount, 0);

        async.elapse(const Duration(milliseconds: 1));
        expect(h.saver.callCount, 1);

        h.dispose();
      });
    });

    test('each change restarts the debounce window', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.type('v1');
        async.elapse(h.service.debounceDelay - const Duration(milliseconds: 1));
        h.type('v2');
        async.elapse(h.service.debounceDelay - const Duration(milliseconds: 1));
        expect(h.saver.callCount, 0);

        async.elapse(const Duration(milliseconds: 1));
        expect(h.saver.callCount, 1);
        expect(h.saver.last.content, 'v2');

        h.dispose();
      });
    });

    test('a later burst saves again from the new baseline', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        h.type('v2');
        async.elapse(h.service.debounceDelay);

        expect(h.saver.callCount, 2);
        expect(h.saver.calls[0].content, 'v1');
        expect(h.saver.calls[1].content, 'v2');

        h.dispose();
      });
    });

    test('only the fields that actually changed are sent', () {
      fakeAsync((async) {
        final h = _Harness()..track(title: 'Title', initial: 'v0');

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.last.title, isNull);
        expect(h.saver.last.content, 'v1');

        h.service.onContentChanged('Renamed');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 2);
        expect(h.saver.last.title, 'Renamed');
        expect(h.saver.last.content, isNull);

        h.dispose();
      });
    });
  });

  group('periodic interval save', () {
    test('the interval timer saves without waiting for the debounce', () {
      fakeAsync((async) {
        final h = _Harness(debounceDelay: const Duration(minutes: 5))
          ..track(initial: 'v0');

        h.type('v1');
        async.elapse(h.service.saveInterval);

        expect(h.saver.callCount, 1);
        expect(h.saver.last.content, 'v1');

        h.dispose();
      });
    });

    test('the interval timer keeps firing for later changes', () {
      fakeAsync((async) {
        final h = _Harness(debounceDelay: const Duration(minutes: 5))
          ..track(initial: 'v0');

        h.type('v1');
        async.elapse(h.service.saveInterval);
        h.type('v2');
        async.elapse(h.service.saveInterval);

        expect(h.saver.callCount, 2);
        expect(h.saver.last.content, 'v2');

        h.dispose();
      });
    });

    test('the interval is a no-op while nothing is pending', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.content = 'changed behind the service back';
        async.elapse(h.service.saveInterval * 5);

        expect(h.saver.callCount, 0);
        expect(h.service.saveStatusNotifier.value, SaveStatus.saved);

        h.dispose();
      });
    });

    test('stopTracking cancels both the debounce and the interval', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.type('v1');
        h.service.stopTracking();
        async.elapse(h.service.saveInterval * 10);

        expect(h.saver.callCount, 0);

        h.dispose();
      });
    });

    test('startTracking re-baselines and restarts the interval', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.type('v1');
        h.track(title: 'Other', initial: 'other content');
        expect(h.service.hasPendingChanges, isFalse);

        async.elapse(h.service.saveInterval * 3);
        expect(h.saver.callCount, 0);

        h.type('other content edited', title: 'Other');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 1);
        expect(h.saver.last.content, 'other content edited');

        h.dispose();
      });
    });
  });

  group('unchanged content', () {
    test('a debounce that finds no change writes nothing', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.service.onContentChanged('Title');
        expect(h.service.hasPendingChanges, isTrue);

        async.elapse(h.service.debounceDelay);

        expect(h.saver.callCount, 0);
        expect(h.service.hasPendingChanges, isFalse);
        expect(h.service.saveStatusNotifier.value, SaveStatus.saved);
        expect(h.changeFlags, [true, false]);

        h.dispose();
      });
    });

    test('re-saving identical content after a real save is skipped', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 1);

        h.service.onContentChanged('Title');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 1);

        h.dispose();
      });
    });

    test('content edited and reverted within one window writes nothing', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.type('v1');
        async.elapse(const Duration(milliseconds: 500));
        h.type('v0');
        async.elapse(h.service.debounceDelay);

        expect(h.saver.callCount, 0);
        expect(h.service.saveStatusNotifier.value, SaveStatus.saved);

        h.dispose();
      });
    });
  });

  group('forceSave', () {
    test('it awaits an in-flight save instead of starting a second one', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');
        final gate = Completer<void>();
        h.saver.gate = gate;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 1);
        expect(h.service.saveStatusNotifier.value, SaveStatus.saving);

        h.content = 'v2';
        unawaited(h.service.forceSave());
        async.flushMicrotasks();

        expect(
          h.saver.callCount,
          1,
          reason: 'forceSave must not open a second concurrent write',
        );

        gate.complete();
        async.flushMicrotasks();

        expect(h.saver.callCount, 2);
        expect(h.saver.calls[0].content, 'v1');
        expect(h.saver.calls[1].content, 'v2');

        h.dispose();
      });
    });

    test('text typed while it waits lands in the forced save', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');
        final gate = Completer<void>();
        h.saver.gate = gate;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 1);

        unawaited(h.service.forceSave());
        async.flushMicrotasks();

        // Typed while the first write is in flight and the forced save is
        // parked behind it. Reading the provider before that wait would
        // stamp 'v1' as saved and lose this on the pop that follows.
        h.content = 'v2';

        gate.complete();
        async.flushMicrotasks();

        expect(h.saver.callCount, 2);
        expect(h.saver.calls[1].content, 'v2');

        h.dispose();
      });
    });

    test('it is dropped, not queued, when the content did not move', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');
        final gate = Completer<void>();
        h.saver.gate = gate;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 1);

        unawaited(h.service.forceSave());
        gate.complete();
        async.flushMicrotasks();

        expect(h.saver.callCount, 1);
        expect(h.service.saveStatusNotifier.value, SaveStatus.saved);

        h.dispose();
      });
    });

    test('it cancels the pending debounce so the burst saves once', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.type('v1');
        async.elapse(const Duration(milliseconds: 500));
        unawaited(h.service.forceSave());
        async.flushMicrotasks();
        expect(h.saver.callCount, 1);

        async.elapse(h.service.debounceDelay * 2);
        expect(h.saver.callCount, 1);

        h.dispose();
      });
    });

    test('explicit title and content override the tracked values', () {
      fakeAsync((async) {
        final h = _Harness()..track(title: 'Title', initial: 'v0');

        unawaited(
          h.service.forceSave(title: 'Explicit', content: 'explicit body'),
        );
        async.flushMicrotasks();

        expect(h.saver.callCount, 1);
        expect(h.saver.last.title, 'Explicit');
        expect(h.saver.last.content, 'explicit body');

        h.dispose();
      });
    });

    test('a title-only forceSave still reads content from the provider', () {
      fakeAsync((async) {
        final h = _Harness()..track(title: 'Title', initial: 'v0');

        h.content = 'v1';
        unawaited(h.service.forceSave(title: 'Renamed'));
        async.flushMicrotasks();

        expect(h.saver.callCount, 1);
        expect(h.saver.last.title, 'Renamed');
        expect(h.saver.last.content, 'v1');

        h.dispose();
      });
    });

    test('without a tracked provider it is a no-op', () {
      fakeAsync((async) {
        final h = _Harness();

        unawaited(h.service.forceSave());
        async.flushMicrotasks();

        expect(h.saver.callCount, 0);

        h.dispose();
      });
    });
  });

  group('a write that waits', () {
    test('a keystroke made while it waits stays pending and is written '
        'next, never marked saved (S4b-1 review H1)', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');
        final gate = Completer<void>();
        h.saver.gate = gate;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        // Its debounce runs out while v1 is still in flight and is dropped.
        h.type('v2');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 1);

        h.saver.gate = null;
        gate.complete();
        async.flushMicrotasks();

        expect(h.service.hasPendingChanges, isTrue);
        expect(h.service.saveStatusNotifier.value, SaveStatus.unsaved);
        expect(h.service.isSavedContent('v1'), isTrue);

        async.elapse(h.service.debounceDelay);
        expect(h.saver.calls.map((c) => c.content), ['v1', 'v2']);
        expect(h.service.hasPendingChanges, isFalse);
        expect(h.service.saveStatusNotifier.value, SaveStatus.saved);

        h.dispose();
      });
    });

    test('a title-only write leaves a body baseline adopted meanwhile '
        '(M6)', () {
      fakeAsync((async) {
        final h = _Harness()..track(title: 'Title', initial: 'v0');
        final gate = Completer<void>();
        h.saver.gate = gate;

        h.service.onContentChanged('Renamed');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.last.content, isNull);
        h.content = 'theirs';
        h.service.adoptSavedContent('theirs');

        gate.complete();
        async.flushMicrotasks();

        expect(h.service.isSavedContent('theirs'), isTrue);
        expect(h.service.hasPendingChanges, isFalse);
        expect(h.service.saveStatusNotifier.value, SaveStatus.saved);

        h.dispose();
      });
    });

    test('a body write in flight leaves the baseline a merge adopted '
        'meanwhile, and its own text stays unsaved (R1)', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');
        final gate = Completer<void>();
        h.saver.gate = gate;

        // Through the seam, where the coordinator calls it: inside `onSave`,
        // past the hold and the title lookup, just before the dispatch.
        h.saver.duringSave = h.service.writeIssued;

        h.type('mine');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.last.content, 'mine');
        // The write has gone out, and the merge is filed and adopted while
        // the save is still finishing: the row holds the merged body.
        h.service.adoptSavedContent('theirs');

        h.saver.gate = null;
        gate.complete();
        async.flushMicrotasks();

        expect(
          h.service.isSavedContent('theirs'),
          isTrue,
          reason: 'the row holds the merged body, not the written one',
        );
        expect(h.service.isSavedContent('mine'), isFalse);
        expect(h.service.hasPendingChanges, isTrue);
        expect(h.service.saveStatusNotifier.value, SaveStatus.unsaved);

        async.elapse(h.service.debounceDelay);
        expect(h.saver.calls.map((c) => c.content), ['mine', 'mine']);

        h.dispose();
      });
    });

    test('a baseline adopted before the write went out is replaced by what '
        'the write landed (R1)', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');
        final gate = Completer<void>();
        h.saver.gate = gate;

        // The page held this write while it filed a merge, so the adoption
        // is older than the row the write then wrote — both inside `onSave`,
        // in the coordinator's own order.
        h.saver.duringSave = () {
          h.service.adoptSavedContent('theirs');
          h.service.writeIssued();
        };

        h.type('mine');
        async.elapse(h.service.debounceDelay);

        h.saver.gate = null;
        gate.complete();
        async.flushMicrotasks();

        expect(h.service.isSavedContent('mine'), isTrue);
        expect(h.service.hasPendingChanges, isFalse);
        expect(h.service.saveStatusNotifier.value, SaveStatus.saved);

        async.elapse(h.service.debounceDelay);
        expect(
          h.saver.callCount,
          1,
          reason: 'no second write of the same text',
        );

        h.dispose();
      });
    });

    test('a keystroke made while it waits keeps its own debounce deadline '
        '(R14)', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');
        final gate = Completer<void>();
        h.saver.gate = gate;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        // Typed the moment the write started, so its deadline is a whole
        // debounce away and the write lands well before it.
        h.type('v2');
        async.elapse(const Duration(seconds: 2));
        h.saver.gate = null;
        gate.complete();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 3));
        expect(
          h.saver.calls.map((c) => c.content),
          ['v1', 'v2'],
          reason: "v2's own deadline, not a fresh debounce from the landing",
        );

        h.dispose();
      });
    });

    test('the text it keeps pending is announced as a change (R15)', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');
        final gate = Completer<void>();
        h.saver.gate = gate;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        h.content = 'v2';
        h.changeFlags.clear();

        h.saver.gate = null;
        gate.complete();
        async.flushMicrotasks();

        expect(h.changeFlags, [true]);

        h.dispose();
      });
    });

    test('a stopped service does not re-arm over text a write did not '
        'carry', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');
        final gate = Completer<void>();
        h.saver.gate = gate;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        h.content = 'v2';
        h.service.stopTracking();
        gate.complete();
        async.flushMicrotasks();
        async.elapse(h.service.debounceDelay * 4);

        expect(h.saver.callCount, 1);

        h.dispose();
      });
    });
  });

  group('retry ladder', () {
    _Harness failing() =>
        _Harness(saveInterval: const Duration(minutes: 10))
          ..track(initial: 'v0');

    test('a failing save is retried three times and then abandoned', () {
      fakeAsync((async) {
        final h = failing();
        h.saver.failures = -1;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 1);

        async.elapse(const Duration(seconds: 2));
        expect(h.saver.callCount, 2);

        async.elapse(const Duration(seconds: 4));
        expect(h.saver.callCount, 3);

        async.elapse(const Duration(seconds: 8));
        expect(h.saver.callCount, 4);

        async.elapse(const Duration(minutes: 5));
        expect(
          h.saver.callCount,
          4,
          reason: 'the ladder is capped at three retries',
        );
        expect(h.service.saveStatusNotifier.value, SaveStatus.error);
        expect(h.service.hasPendingChanges, isTrue);

        h.dispose();
      });
    });

    test('the retry delays double: 2 s, 4 s, then 8 s', () {
      fakeAsync((async) {
        final h = failing();
        h.saver.failures = -1;

        h.type('v1');
        async.elapse(h.service.debounceDelay);

        async.elapse(const Duration(milliseconds: 1999));
        expect(h.saver.callCount, 1);
        async.elapse(const Duration(milliseconds: 1));
        expect(h.saver.callCount, 2);

        async.elapse(const Duration(milliseconds: 3999));
        expect(h.saver.callCount, 2);
        async.elapse(const Duration(milliseconds: 1));
        expect(h.saver.callCount, 3);

        async.elapse(const Duration(milliseconds: 7999));
        expect(h.saver.callCount, 3);
        async.elapse(const Duration(milliseconds: 1));
        expect(h.saver.callCount, 4);

        h.dispose();
      });
    });

    test('a retry that succeeds clears the error and the pending flag', () {
      fakeAsync((async) {
        final h = failing();
        h.saver.failures = 1;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        expect(h.service.saveStatusNotifier.value, SaveStatus.error);

        async.elapse(const Duration(seconds: 2));

        expect(h.saver.callCount, 2);
        expect(h.saver.last.content, 'v1');
        expect(h.service.saveStatusNotifier.value, SaveStatus.saved);
        expect(h.service.hasPendingChanges, isFalse);

        h.dispose();
      });
    });

    test('a successful save resets the ladder back to the first rung', () {
      fakeAsync((async) {
        final h = failing();
        h.saver.failures = 1;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        async.elapse(const Duration(seconds: 2));
        expect(h.saver.callCount, 2);

        h.saver.failures = -1;
        h.type('v2');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 3);

        async.elapse(const Duration(milliseconds: 1999));
        expect(h.saver.callCount, 3);
        async.elapse(const Duration(milliseconds: 1));
        expect(
          h.saver.callCount,
          4,
          reason: 'the ladder must restart at 2 s after a success',
        );

        h.dispose();
      });
    });

    test('stopTracking cancels a scheduled retry', () {
      fakeAsync((async) {
        final h = failing();
        h.saver.failures = -1;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 1);

        h.service.stopTracking();
        async.elapse(const Duration(minutes: 1));

        expect(h.saver.callCount, 1);

        h.dispose();
      });
    });

    test('a fresh edit during the ladder saves the newest content', () {
      fakeAsync((async) {
        final h = failing();
        h.saver.failures = 1;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 1);

        h.type('v2');
        async.elapse(h.service.debounceDelay);

        expect(h.saver.last.content, 'v2');
        expect(h.service.saveStatusNotifier.value, SaveStatus.saved);

        h.dispose();
      });
    });

    test('a refused write stays unsaved, spends no rung and arms nothing '
        '(A6 review R115)', () {
      fakeAsync((async) {
        final h = failing();
        h.saver.refusals = -1;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 1);
        expect(h.service.saveStatusNotifier.value, SaveStatus.unsaved);
        expect(h.service.hasPendingChanges, isTrue);
        expect(h.changeFlags.last, isTrue);

        // The row is a tombstone: the delete handler owns the text now, and
        // nothing may write it again — no rung, no re-armed debounce.
        async.elapse(const Duration(seconds: 30));
        expect(h.saver.callCount, 1);
        expect(h.service.saveStatusNotifier.value, SaveStatus.unsaved);

        // And the ladder is untouched, so a real failure still gets three.
        h.saver.refusals = 0;
        h.saver.failures = -1;
        h.type('v2');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 2);
        expect(h.service.saveStatusNotifier.value, SaveStatus.error);
        async.elapse(const Duration(seconds: 2));
        expect(h.saver.callCount, 3);
        async.elapse(const Duration(seconds: 4));
        expect(h.saver.callCount, 4);
        async.elapse(const Duration(seconds: 8));
        expect(h.saver.callCount, 5);

        h.dispose();
      });
    });

    test('a held write stays unsaved without the error status, re-arms the '
        'debounce and spends no rung (L8)', () {
      fakeAsync((async) {
        final h = failing();
        h.saver.holds = 3;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 1);
        expect(h.service.saveStatusNotifier.value, SaveStatus.unsaved);
        expect(h.service.hasPendingChanges, isTrue);

        async.elapse(h.service.debounceDelay);
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 3, reason: 'the debounce keeps trying');
        expect(h.service.saveStatusNotifier.value, SaveStatus.unsaved);

        // The ladder was never entered, so a real failure after three holds
        // still gets all three rungs.
        h.saver.failures = -1;
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 4);
        expect(h.service.saveStatusNotifier.value, SaveStatus.error);
        async.elapse(const Duration(seconds: 2));
        expect(h.saver.callCount, 5);
        async.elapse(const Duration(seconds: 4));
        expect(h.saver.callCount, 6);
        async.elapse(const Duration(seconds: 8));
        expect(h.saver.callCount, 7);

        h.dispose();
      });
    });
  });

  group('status transitions', () {
    test('a successful save walks unsaved, saving, saved', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.type('v1');
        expect(h.statuses, [SaveStatus.unsaved]);

        async.elapse(h.service.debounceDelay);

        expect(h.statuses, [
          SaveStatus.unsaved,
          SaveStatus.saving,
          SaveStatus.saved,
        ]);

        h.dispose();
      });
    });

    test('a failing save ends on error', () {
      fakeAsync((async) {
        final h = _Harness(saveInterval: const Duration(minutes: 10))
          ..track(initial: 'v0');
        h.saver.failures = -1;

        h.type('v1');
        async.elapse(h.service.debounceDelay);

        expect(h.statuses, [
          SaveStatus.unsaved,
          SaveStatus.saving,
          SaveStatus.error,
        ]);

        h.dispose();
      });
    });

    test('a recovered save returns to saved', () {
      fakeAsync((async) {
        final h = _Harness(saveInterval: const Duration(minutes: 10))
          ..track(initial: 'v0');
        h.saver.failures = 1;

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        async.elapse(const Duration(seconds: 2));

        expect(h.statuses, [
          SaveStatus.unsaved,
          SaveStatus.saving,
          SaveStatus.error,
          SaveStatus.saving,
          SaveStatus.saved,
        ]);

        h.dispose();
      });
    });

    test('an unchanged save collapses straight back to saved', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.service.onContentChanged('Title');
        async.elapse(h.service.debounceDelay);

        expect(h.statuses, [SaveStatus.unsaved, SaveStatus.saved]);

        h.dispose();
      });
    });

    test('onChangeDetected mirrors the pending flag', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.type('v1');
        expect(h.changeFlags, [true]);
        expect(h.service.hasPendingChanges, isTrue);

        async.elapse(h.service.debounceDelay);

        expect(h.changeFlags, [true, false]);
        expect(h.service.hasPendingChanges, isFalse);

        h.dispose();
      });
    });

    test('repeated identical statuses are not re-notified', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.type('v1');
        h.type('v2');
        h.type('v3');

        expect(h.statuses, [SaveStatus.unsaved]);

        h.dispose();
      });
    });

    test('a fresh baseline reads as saved — loading a note announces itself '
        'like an edit, and re-baselining on what was loaded is the only '
        'thing that answers it', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: '');

        // The load: the controller notifies, the page reports a change.
        h.type('the stored note');
        expect(h.statuses, [SaveStatus.unsaved]);

        h.track(initial: 'the stored note');

        expect(h.statuses, [SaveStatus.unsaved, SaveStatus.saved]);
        expect(h.service.hasPendingChanges, isFalse);

        // And nothing was scheduled to clear it later instead.
        async.elapse(h.service.saveInterval * 2);
        expect(h.saver.callCount, 0);
        expect(h.statuses, [SaveStatus.unsaved, SaveStatus.saved]);

        h.dispose();
      });
    });

    test('a fresh baseline taken while a write is in flight leaves the '
        'status to that write', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');
        h.saver.gate = Completer<void>();

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        expect(h.statuses.last, SaveStatus.saving);

        h.track(initial: 'v1');
        expect(
          h.statuses.last,
          SaveStatus.saving,
          reason: 'the write has not landed; claiming saved would be a guess',
        );

        h.saver.gate!.complete();
        async.flushMicrotasks();
        expect(h.statuses.last, SaveStatus.saved);

        h.dispose();
      });
    });
  });

  group('dispose', () {
    test('disposing stops every timer', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.type('v1');
        h.dispose();
        async.elapse(const Duration(minutes: 10));

        expect(h.saver.callCount, 0);
      });
    });

    test('a save that lands after dispose does not blow up', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');
        final gate = Completer<void>();
        h.saver.gate = gate;

        h.content = 'v1';
        Object? error;
        unawaited(h.service.forceSave().catchError((Object e) => error = e));
        async.flushMicrotasks();
        expect(h.saver.callCount, 1);

        h.dispose();
        gate.complete();
        async.flushMicrotasks();

        expect(error, isNull);
      });
    });

    test('a change announced after dispose is ignored', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.dispose();
        h.type('v1');
        async.elapse(const Duration(minutes: 10));

        expect(h.changeFlags, isEmpty);
        expect(h.saver.callCount, 0);
      });
    });

    test('tracking cannot be restarted after dispose', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.dispose();
        h.track(initial: 'v1');
        async.elapse(const Duration(minutes: 10));

        expect(
          async.pendingTimers,
          isEmpty,
          reason: 'a dead service must not leave an interval timer running',
        );
        expect(h.saver.callCount, 0);
      });
    });

    test('a save started before dispose is not restarted afterwards', () {
      fakeAsync((async) {
        final h = _Harness()..track(initial: 'v0');

        h.type('v1');
        async.elapse(h.service.debounceDelay);
        expect(h.saver.callCount, 1);

        h.dispose();
        async.elapse(const Duration(minutes: 10));

        expect(h.saver.callCount, 1);
      });
    });
  });
}
