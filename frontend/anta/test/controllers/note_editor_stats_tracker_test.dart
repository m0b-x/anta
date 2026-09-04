import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/controllers/note_editor_stats_tracker.dart';
import 'package:anta/widgets/note_editor_chrome.dart';

/// The stats bar sits on the typing path, so the only interesting thing
/// about it is *when* it counts. Two rules, both asserted here: ordinary
/// keystrokes coalesce into one count after the user pauses, and a change
/// big enough to be a paste or a block delete counts immediately — that is
/// the one a reader would notice the bar failing to reflect.
///
/// [_Harness.snapshots] is the number the debounce exists to keep down, so
/// most assertions are about it rather than about the published value.
class _Harness {
  _Harness() {
    tracker = NoteEditorStatsTracker(
      snapshot: () {
        snapshots++;
        return (lineCount: lineCount, charCount: charCount);
      },
    );
    tracker.stats.addListener(() => published.add(tracker.stats.value));
  }

  /// What the editor would answer if it were asked right now.
  int lineCount = 1;
  int charCount = 0;

  int snapshots = 0;
  final List<NoteEditorStats> published = [];

  late final NoteEditorStatsTracker tracker;

  /// The editor grew to [length] code units, spread over [lines] lines.
  void edit({required int length, int lines = 1}) {
    charCount = length;
    lineCount = lines;
    tracker.onTextChanged(length);
  }
}

void main() {
  test('starts empty without asking the editor anything', () {
    final h = _Harness();

    expect(h.tracker.stats.value, emptyNoteEditorStats);
    expect(h.snapshots, 0);

    h.tracker.dispose();
  });

  group('set', () {
    test('publishes the exact numbers at once', () {
      final h = _Harness();

      h.tracker.set((lineCount: 120, charCount: 4000));

      expect(h.published, [(lineCount: 120, charCount: 4000)]);
      // The caller already knew the answer; nothing was recounted.
      expect(h.snapshots, 0);

      h.tracker.dispose();
    });

    test('supersedes a pending debounce', () {
      fakeAsync((async) {
        final h = _Harness()..edit(length: 10);

        h.tracker.set((lineCount: 120, charCount: 4000));
        async.elapse(const Duration(seconds: 1));

        expect(h.snapshots, 0);
        expect(h.published, [(lineCount: 120, charCount: 4000)]);

        h.tracker.dispose();
      });
    });

    test('moves the baseline, so the next keystroke still debounces', () {
      fakeAsync((async) {
        final h = _Harness();

        // A long note landing must not make the very next keystroke look
        // like a 4,000-character paste.
        h.tracker.set((lineCount: 120, charCount: 4000));
        h.edit(length: 4001, lines: 120);

        expect(h.snapshots, 0);

        async.elapse(NoteEditorStatsTracker.debounceDelay);

        expect(h.snapshots, 1);
        expect(h.published.last, (lineCount: 120, charCount: 4001));

        h.tracker.dispose();
      });
    });
  });

  group('onTextChanged', () {
    test('coalesces a burst of keystrokes into one count', () {
      fakeAsync((async) {
        final h = _Harness();

        for (int i = 1; i <= 10; i++) {
          h.edit(length: i);
          async.elapse(const Duration(milliseconds: 50));
        }
        expect(h.snapshots, 0);
        expect(h.published, isEmpty);

        async.elapse(NoteEditorStatsTracker.debounceDelay);

        expect(h.snapshots, 1);
        expect(h.published, [(lineCount: 1, charCount: 10)]);

        h.tracker.dispose();
      });
    });

    test('does not count one tick early', () {
      fakeAsync((async) {
        final h = _Harness()..edit(length: 7);

        async.elapse(
          NoteEditorStatsTracker.debounceDelay -
              const Duration(milliseconds: 1),
        );
        expect(h.snapshots, 0);

        async.elapse(const Duration(milliseconds: 1));
        expect(h.snapshots, 1);

        h.tracker.dispose();
      });
    });

    test('a delta past the threshold counts on the spot', () {
      fakeAsync((async) {
        final h = _Harness();

        h.edit(
          length: MarkdownConstants.contentChangeDeltaThreshold + 1,
          lines: 30,
        );

        expect(h.snapshots, 1);
        expect(h.published, [
          (
            lineCount: 30,
            charCount: MarkdownConstants.contentChangeDeltaThreshold + 1,
          ),
        ]);

        async.elapse(const Duration(seconds: 1));
        expect(h.snapshots, 1);

        h.tracker.dispose();
      });
    });

    test('a delta exactly at the threshold still debounces', () {
      fakeAsync((async) {
        final h = _Harness();

        h.edit(length: MarkdownConstants.contentChangeDeltaThreshold);
        expect(h.snapshots, 0);

        async.elapse(NoteEditorStatsTracker.debounceDelay);
        expect(h.snapshots, 1);

        h.tracker.dispose();
      });
    });

    test('a big delta drops the debounce it interrupted', () {
      fakeAsync((async) {
        final h = _Harness()..edit(length: 10);

        async.elapse(const Duration(milliseconds: 100));
        h.edit(length: 900, lines: 12);

        expect(h.snapshots, 1);

        async.elapse(const Duration(seconds: 1));
        expect(h.snapshots, 1);
        expect(h.published, [(lineCount: 12, charCount: 900)]);

        h.tracker.dispose();
      });
    });

    test('a large deletion counts immediately too', () {
      fakeAsync((async) {
        final h = _Harness()..tracker.set((lineCount: 90, charCount: 3000));

        h.edit(length: 100, lines: 3);

        expect(h.snapshots, 1);
        expect(h.published.last, (lineCount: 3, charCount: 100));

        h.tracker.dispose();
      });
    });
  });

  group('refresh', () {
    test('counts now and drops the pending debounce', () {
      fakeAsync((async) {
        final h = _Harness()..edit(length: 10);

        h.lineCount = 2;
        h.charCount = 10;
        h.tracker.refresh();

        expect(h.snapshots, 1);
        expect(h.published, [(lineCount: 2, charCount: 10)]);

        async.elapse(const Duration(seconds: 1));
        expect(h.snapshots, 1);

        h.tracker.dispose();
      });
    });
  });

  group('dispose', () {
    test('cancels a pending count', () {
      fakeAsync((async) {
        final h = _Harness()..edit(length: 10);

        h.tracker.dispose();
        async.elapse(const Duration(seconds: 1));

        expect(h.snapshots, 0);
        expect(h.published, isEmpty);
      });
    });

    test('makes every later call inert', () {
      fakeAsync((async) {
        final h = _Harness()..tracker.dispose();

        h.edit(length: 900, lines: 12);
        h.tracker.refresh();
        h.tracker.set((lineCount: 5, charCount: 5));
        async.elapse(const Duration(seconds: 1));

        expect(h.snapshots, 0);
        expect(h.published, isEmpty);
      });
    });
  });
}
