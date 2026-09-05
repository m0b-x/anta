import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/controllers/note_editor_position_controller.dart';
import 'package:anta/services/note_position_service.dart';

/// Two things are pinned here.
///
/// The **join**: the stored position and the note's content arrive from
/// unrelated async sources, and the restore needs both. Every ordering has
/// to end in exactly one restore — zero means the user loses their place,
/// two means the caret jumps back after they moved it. The tests drive the
/// two sides in both orders through a gated loader.
///
/// The **absolute-line mapping**: positions are persisted as absolute line
/// numbers, so a note reopened with different sections folded still lands
/// on the same line of text. Today nothing folds, so the mapping is the
/// identity and a bug in it would be invisible — which is why the
/// collapsed-chunk case is asserted explicitly, against a real controller
/// with a real chunk.
class _Harness {
  _Harness({this.noteId = 'note-1'}) {
    controller = NoteEditorPositionController(
      noteId: noteId,
      loadPosition: (id) {
        loadCalls.add(id);
        return loadGate.future;
      },
      savePosition: (id, position) async {
        saves.add((id: id, position: position));
      },
      onRestore: restored.add,
    );
  }

  final String? noteId;
  final List<String> loadCalls = [];
  final List<({String id, NotePositionData position})> saves = [];
  final List<NotePositionData> restored = [];
  final Completer<NotePositionData> loadGate = Completer<NotePositionData>();

  late final NoteEditorPositionController controller;
}

NotePositionData _position({
  bool isPreviewMode = false,
  double previewScrollProgress = 0.0,
  int editorLineIndex = 0,
  int editorColumnOffset = 0,
}) => NotePositionData(
  isPreviewMode: isPreviewMode,
  previewScrollProgress: previewScrollProgress,
  editorLineIndex: editorLineIndex,
  editorColumnOffset: editorColumnOffset,
);

void main() {
  group('the restore join', () {
    test('position first: restores when the content lands', () {
      fakeAsync((async) {
        final h = _Harness();

        unawaited(h.controller.load());
        h.loadGate.complete(_position(editorLineIndex: 7));
        async.flushMicrotasks();

        expect(h.controller.saved?.editorLineIndex, 7);
        expect(h.restored, isEmpty);

        h.controller.contentReady();

        expect(h.restored, hasLength(1));
        expect(h.restored.single.editorLineIndex, 7);

        h.controller.dispose();
      });
    });

    test('content first: restores when the position lands', () {
      fakeAsync((async) {
        final h = _Harness();

        unawaited(h.controller.load());
        h.controller.contentReady();
        expect(h.restored, isEmpty);

        h.loadGate.complete(_position(editorLineIndex: 12));
        async.flushMicrotasks();

        expect(h.restored, hasLength(1));
        expect(h.restored.single.editorLineIndex, 12);

        h.controller.dispose();
      });
    });

    test('restores exactly once however often it is nudged', () {
      fakeAsync((async) {
        final h = _Harness();

        unawaited(h.controller.load());
        h.loadGate.complete(_position(editorLineIndex: 3));
        async.flushMicrotasks();

        h.controller.contentReady();
        h.controller.contentReady();
        h.controller.restoreWhenReady();
        h.controller.restoreWhenReady();

        expect(h.restored, hasLength(1));

        h.controller.dispose();
      });
    });

    test('the stored record survives the restore, for the preview flag', () {
      fakeAsync((async) {
        final h = _Harness();

        unawaited(h.controller.load());
        h.loadGate.complete(_position(isPreviewMode: true));
        async.flushMicrotasks();
        h.controller.contentReady();

        expect(h.restored, hasLength(1));
        // The settings that decide whether preview is reachable land on
        // their own schedule, so the flag is re-read after the restore.
        expect(h.controller.savedIsPreviewMode, isTrue);
        expect(h.controller.saved, isNotNull);

        h.controller.dispose();
      });
    });

    test('a load answering after dispose never restores', () {
      fakeAsync((async) {
        final h = _Harness();

        unawaited(h.controller.load());
        h.controller.contentReady();
        h.controller.dispose();

        h.loadGate.complete(_position(editorLineIndex: 4));
        async.flushMicrotasks();

        expect(h.restored, isEmpty);
      });
    });

    test('a read that throws never escapes and never opens the join', () {
      fakeAsync((async) {
        final restored = <NotePositionData>[];
        final controller = NoteEditorPositionController(
          noteId: 'note-1',
          loadPosition: (id) => Future<NotePositionData>.error(
            StateError('the position row is unreadable'),
          ),
          savePosition: (id, position) async {},
          onRestore: restored.add,
        );

        // The page fires this unawaited: an escaping error would land in
        // the zone rather than costing the user their place.
        unawaited(controller.load());
        async.flushMicrotasks();

        expect(controller.saved, isNull);
        expect(controller.savedIsPreviewMode, isNull);

        // And the join stays shut for good — a note with nothing readable
        // stored is a note that opens where it opens.
        controller.contentReady();
        controller.restoreWhenReady();

        expect(restored, isEmpty);

        controller.dispose();
      });
    });
  });

  group('a note with no id yet', () {
    test('does not load, does not save, and never restores', () {
      fakeAsync((async) {
        final h = _Harness(noteId: null);

        unawaited(h.controller.load());
        async.flushMicrotasks();

        expect(h.loadCalls, isEmpty);
        expect(h.controller.saved, isNull);
        expect(h.controller.savedIsPreviewMode, isNull);

        unawaited(h.controller.save(_position(editorLineIndex: 2)));
        async.flushMicrotasks();
        expect(h.saves, isEmpty);

        h.controller.contentReady();
        expect(h.restored, isEmpty);

        h.controller.dispose();
      });
    });

    test('starts saving once the early create hands over an id', () {
      fakeAsync((async) {
        final h = _Harness(noteId: null);

        h.controller.noteId = 'created-9';
        unawaited(h.controller.save(_position(editorLineIndex: 5)));
        async.flushMicrotasks();

        expect(h.saves, hasLength(1));
        expect(h.saves.single.id, 'created-9');
        expect(h.saves.single.position.editorLineIndex, 5);

        h.controller.dispose();
      });
    });
  });

  group('save', () {
    test('forwards the record under the note id', () {
      fakeAsync((async) {
        final h = _Harness();

        unawaited(
          h.controller.save(
            _position(
              isPreviewMode: true,
              previewScrollProgress: 0.42,
              editorLineIndex: 9,
              editorColumnOffset: 4,
            ),
          ),
        );
        async.flushMicrotasks();

        expect(h.saves, hasLength(1));
        expect(h.saves.single.id, 'note-1');
        expect(h.saves.single.position.isPreviewMode, isTrue);
        expect(h.saves.single.position.previewScrollProgress, 0.42);
        expect(h.saves.single.position.editorLineIndex, 9);
        expect(h.saves.single.position.editorColumnOffset, 4);

        h.controller.dispose();
      });
    });
  });

  group('the timers', () {
    test('scheduleScroll keeps only the latest request', () {
      fakeAsync((async) {
        final h = _Harness();
        final ran = <String>[];

        h.controller.scheduleScroll(
          const Duration(milliseconds: 100),
          () => ran.add('first'),
        );
        async.elapse(const Duration(milliseconds: 50));
        h.controller.scheduleScroll(
          const Duration(milliseconds: 100),
          () => ran.add('second'),
        );
        async.elapse(const Duration(milliseconds: 200));

        expect(ran, ['second']);

        h.controller.dispose();
      });
    });

    test('debounceSave coalesces and snapshots at fire time', () {
      fakeAsync((async) {
        final h = _Harness();
        int line = 0;

        for (int i = 1; i <= 4; i++) {
          line = i;
          h.controller.debounceSave(
            const Duration(milliseconds: 500),
            () => _position(editorLineIndex: line),
          );
          async.elapse(const Duration(milliseconds: 100));
        }
        expect(h.saves, isEmpty);

        line = 99;
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();

        expect(h.saves, hasLength(1));
        expect(h.saves.single.position.editorLineIndex, 99);

        h.controller.dispose();
      });
    });

    test('dispose cancels both the scroll and the save timer', () {
      fakeAsync((async) {
        final h = _Harness();
        final ran = <String>[];

        h.controller.scheduleScroll(
          const Duration(milliseconds: 100),
          () => ran.add('scroll'),
        );
        h.controller.debounceSave(
          const Duration(milliseconds: 100),
          () => _position(editorLineIndex: 1),
        );

        h.controller.dispose();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(ran, isEmpty);
        expect(h.saves, isEmpty);
      });
    });

    test('scheduling after dispose is inert', () {
      fakeAsync((async) {
        final h = _Harness()..controller.dispose();
        final ran = <String>[];

        h.controller.scheduleScroll(
          const Duration(milliseconds: 100),
          () => ran.add('scroll'),
        );
        h.controller.debounceSave(
          const Duration(milliseconds: 100),
          () => _position(),
        );
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(ran, isEmpty);
        expect(h.saves, isEmpty);
      });
    });

    test('a debounced save that fails dies inside the timer', () {
      fakeAsync((async) {
        final controller = NoteEditorPositionController(
          noteId: 'note-1',
          loadPosition: (id) async => _position(),
          savePosition: (id, position) =>
              Future<void>.error(StateError('the write failed')),
          onRestore: (_) {},
        );

        controller.debounceSave(const Duration(milliseconds: 100), _position);
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        controller.dispose();
      });
    });
  });

  group('absolute-line mapping', () {
    late CodeLineEditingController editor;

    /// 10 lines, so `collapseChunk(2, 8)` leaves untouched lines on both
    /// sides of the folded run.
    const document = 'L0\nL1\nL2\nL3\nL4\nL5\nL6\nL7\nL8\nL9';

    setUp(() {
      editor = CodeLineEditingController.fromText(document);
    });

    tearDown(() => editor.dispose());

    test('is the identity on a flat document', () {
      for (int i = 0; i < 10; i++) {
        editor.selection = CodeLineSelection.collapsed(index: i, offset: 1);

        final saved = NoteEditorPositionController.snapshot(
          controller: editor,
          isPreviewMode: false,
          previewScrollProgress: 0.0,
        );

        expect(saved.editorLineIndex, i);
        expect(saved.editorColumnOffset, 1);

        final target = NoteEditorPositionController.editorTarget(saved, editor);
        expect(target.index, i);
        expect(target.offset, 1);
      }
    });

    test('carries the preview half of the record through untouched', () {
      editor.selection = const CodeLineSelection.collapsed(index: 4, offset: 2);

      final saved = NoteEditorPositionController.snapshot(
        controller: editor,
        isPreviewMode: true,
        previewScrollProgress: 0.75,
      );

      expect(saved.isPreviewMode, isTrue);
      expect(saved.previewScrollProgress, 0.75);
      expect(saved.editorLineIndex, 4);
    });

    test('a caret below a collapsed chunk saves its absolute line', () {
      editor.collapseChunk(2, 8);
      // Lines 3–7 are now chunk children of line 2, so the visible
      // document is L0, L1, L2*, L8, L9 — five lines standing for ten.
      expect(editor.codeLines.length, 5);
      expect(editor.codeLines.lineCount, 10);
      expect(editor.codeLines[3].text, 'L8');

      editor.selection = const CodeLineSelection.collapsed(index: 3, offset: 2);

      final saved = NoteEditorPositionController.snapshot(
        controller: editor,
        isPreviewMode: false,
        previewScrollProgress: 0.0,
      );

      // The visible index is 3; what is stored is the line's real number.
      expect(saved.editorLineIndex, 8);
      expect(saved.editorColumnOffset, 2);

      final target = NoteEditorPositionController.editorTarget(saved, editor);
      expect(target.index, 3);
      expect(target.offset, 2);
    });

    test('an absolute line hidden in a chunk restores to its parent', () {
      editor.collapseChunk(2, 8);

      // Line 5 is folded away; the closest the caret can legally get is
      // the chunk's visible parent line.
      final target = NoteEditorPositionController.editorTarget(
        _position(editorLineIndex: 5, editorColumnOffset: 2),
        editor,
      );

      expect(target.index, 2);
      expect(editor.codeLines[target.index].text, 'L2');
      expect(target.offset, 2);
    });

    test('a saved position survives a fold applied after the save', () {
      editor.selection = const CodeLineSelection.collapsed(index: 9, offset: 1);
      final saved = NoteEditorPositionController.snapshot(
        controller: editor,
        isPreviewMode: false,
        previewScrollProgress: 0.0,
      );
      expect(saved.editorLineIndex, 9);

      editor.collapseChunk(2, 8);

      final target = NoteEditorPositionController.editorTarget(saved, editor);
      expect(editor.codeLines[target.index].text, 'L9');
      expect(target.offset, 1);
    });

    test('editorTarget clamps a record past the end of the document', () {
      final target = NoteEditorPositionController.editorTarget(
        _position(editorLineIndex: 999, editorColumnOffset: 999),
        editor,
      );

      expect(target.index, 9);
      expect(target.offset, 2);
    });

    test('editorTarget clamps a negative record to the start', () {
      final target = NoteEditorPositionController.editorTarget(
        _position(editorLineIndex: -3, editorColumnOffset: -7),
        editor,
      );

      expect(target.index, 0);
      expect(target.offset, 0);
    });

    test('editorTarget clamps the column to the line it lands on', () {
      final target = NoteEditorPositionController.editorTarget(
        _position(editorLineIndex: 4, editorColumnOffset: 40),
        editor,
      );

      expect(target.index, 4);
      expect(target.offset, 2);
    });
  });
}
