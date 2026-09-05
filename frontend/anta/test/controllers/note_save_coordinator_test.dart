import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/optimized_note/optimized_note_event.dart';
import 'package:anta/controllers/note_save_coordinator.dart';
import 'package:anta/services/auto_save_service.dart';

/// The editor's persistence contract, driven through a real
/// [AutoSaveService] with the timings shortened.
///
/// Three rules are the whole point of this file. A brand-new note is
/// written the moment it holds anything, so a process death never costs
/// the user the first paragraph. A title that collides with a sibling
/// never blocks the save — the content lands under the note's existing
/// title and the user is told once, not once per keystroke. And the
/// dirty flag the app bar watches is published outside the frame that
/// detected the change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('early create', () {
    test('the first non-empty content persists the note', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        h.type('hello');
        async.flushMicrotasks();

        expect(h.creates, hasLength(1));
        expect(h.creates.single.folderId, 'folder-1');
        expect(h.creates.single.title, '');
        expect(h.creates.single.content, 'hello');
        expect(h.coordinator.isCreatingNewNote, isTrue);

        h.dispose();
      });
    });

    test('whitespace alone is not worth a note', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        h.type('   \n  ');
        async.flushMicrotasks();

        expect(h.events, isEmpty);
        expect(h.coordinator.isCreatingNewNote, isFalse);

        h.dispose();
      });
    });

    test('a title alone is enough', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        h.title = 'Named';
        h.coordinator.onContentChanged();
        async.flushMicrotasks();

        expect(h.creates.single.title, 'Named');
        expect(h.creates.single.content, '');

        h.dispose();
      });
    });

    test('further typing while the create is in flight creates once', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        h.type('hello');
        h.type('hello world');
        h.type('hello world again');
        async.flushMicrotasks();

        expect(h.creates, hasLength(1));

        h.dispose();
      });
    });

    test('typing through a title lookup still creates once', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        // A non-empty title sends the create through `titleExists`, so the
        // next two keystrokes land while that lookup is still in flight —
        // the window in which the coordinator used to dispatch one create
        // per keystroke.
        h.title = 'Named';
        h.type('a');
        h.type('ab');
        h.type('abc');
        async.flushMicrotasks();

        expect(h.creates, hasLength(1));
        expect(h.lookups, hasLength(1));
        expect(
          h.creates.single.content,
          'a',
          reason:
              'the create captures the content it saw before the lookup; '
              'the rest is picked up by auto-save once the id lands',
        );

        h.dispose();
      });
    });

    test('a pop mid-lookup waits for the create instead of dropping it', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        h.title = 'Named';
        h.type('draft');
        // No flush: the lookup is still pending, so the in-flight guard is
        // already raised when the page pops.
        var popped = false;
        unawaited(h.coordinator.saveBeforeExit().then((_) => popped = true));
        async.flushMicrotasks();

        expect(popped, isTrue);
        expect(h.creates, hasLength(1));
        expect(h.creates.single.content, 'draft');

        h.dispose();
      });
    });

    test('a colliding title creates the note untitled and warns', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();
        h.taken.add('taken');

        h.title = 'Taken';
        h.type('body');
        async.flushMicrotasks();

        expect(h.creates.single.title, '');
        expect(h.creates.single.content, 'body');
        expect(h.warnings, ['Taken']);
        expect(
          h.lookups.single.excludeId,
          isNull,
          reason: 'a note that does not exist yet excludes nothing',
        );

        h.dispose();
      });
    });

    test('content survives a lifecycle pause before the first keystroke '
        'reached the bloc', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        // Text present but never announced — the OS suspends us first.
        h.content = 'draft';
        h.coordinator.saveOnLifecyclePause();
        async.flushMicrotasks();

        expect(h.creates.single.content, 'draft');

        h.dispose();
      });
    });

    test('the created content keeps its leading whitespace', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        // An indented list item is the common case: trimming the text on
        // the way to the bloc silently re-levels the user's first line.
        h.type('  - a');
        async.flushMicrotasks();

        expect(h.creates.single.content, '  - a');

        h.dispose();
      });
    });

    test('a lifecycle pause mid-create does not release the pop early', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        final h = _Harness()
          ..lookupGate = gate
          ..coordinator.start();

        // A non-empty title parks the create inside `titleExists`.
        h.title = 'Named';
        h.type('draft');
        async.flushMicrotasks();
        expect(h.lookups, hasLength(1));
        expect(h.creates, isEmpty, reason: 'the create is still in the lookup');

        // The OS suspends us mid-create. Nothing new may start, and the
        // future the pop joins must stay the one that is still running.
        h.coordinator.saveOnLifecyclePause();
        async.flushMicrotasks();

        var popped = false;
        unawaited(h.coordinator.saveBeforeExit().then((_) => popped = true));
        async.flushMicrotasks();

        expect(
          popped,
          isFalse,
          reason: 'the pop must wait for the create that is actually running',
        );
        expect(h.creates, isEmpty);

        gate.complete();
        async.flushMicrotasks();

        expect(popped, isTrue);
        expect(h.creates, hasLength(1));
        expect(h.creates.single.content, 'draft');

        h.dispose();
      });
    });
  });

  group('updates', () {
    test('a change auto-saves against the note id', () {
      fakeAsync((async) {
        final h = _Harness.existing()..coordinator.start();

        h.type('v1');
        async.elapse(_Harness.debounce);

        expect(h.updates, hasLength(1));
        expect(h.updates.single.noteId, 'note-1');
        expect(h.updates.single.content, 'v1');
        expect(
          h.updates.single.title,
          isNull,
          reason: 'an unchanged title is not resent',
        );
        expect(h.lookups, isEmpty);

        h.dispose();
      });
    });

    test('a unique new title is saved as typed', () {
      fakeAsync((async) {
        final h = _Harness.existing()..coordinator.start();

        h.rename('Fresh');
        async.elapse(_Harness.debounce);

        expect(h.updates.single.title, 'Fresh');
        expect(h.lookups.single.title, 'Fresh');
        expect(
          h.lookups.single.excludeId,
          'note-1',
          reason: 'the note must not collide with itself',
        );
        expect(h.warnings, isEmpty);

        h.dispose();
      });
    });

    test('a title that only differs in case or padding is not looked up', () {
      fakeAsync((async) {
        final h = _Harness.existing()..coordinator.start();

        h.rename('  original  ');
        async.elapse(_Harness.debounce);

        expect(h.lookups, isEmpty);
        expect(h.updates.single.title, '  original  ');

        h.dispose();
      });
    });

    test('a colliding title keeps the original one and warns once', () {
      fakeAsync((async) {
        final h = _Harness.existing()..coordinator.start();
        h.taken.addAll(['taken', 'also taken']);

        h.rename('Taken');
        async.elapse(_Harness.debounce);

        expect(h.updates.single.title, 'Original');
        expect(h.updates.single.content, isNull);
        expect(h.warnings, ['Taken']);

        h.rename('Also Taken');
        async.elapse(_Harness.debounce);

        expect(h.updates.last.title, 'Original');
        expect(h.warnings, [
          'Taken',
        ], reason: 'the warning is one-shot until a unique title lands');

        h.rename('Unique');
        async.elapse(_Harness.debounce);
        expect(h.updates.last.title, 'Unique');

        h.rename('Taken');
        async.elapse(_Harness.debounce);
        expect(h.updates.last.title, 'Original');
        expect(h.warnings, [
          'Taken',
          'Taken',
        ], reason: 'a unique title re-arms the warning');

        h.dispose();
      });
    });

    test('clearing the title re-arms the duplicate warning', () {
      fakeAsync((async) {
        final h = _Harness.existing()..coordinator.start();
        h.taken.add('taken');

        h.rename('Taken');
        async.elapse(_Harness.debounce);
        expect(h.warnings, ['Taken']);

        // An empty title has nothing to look up, so the one-shot guard was
        // never lowered — and retyping the same taken title said nothing.
        h.rename('');
        async.elapse(_Harness.debounce);
        expect(h.lookups, hasLength(1));

        h.rename('Taken');
        async.elapse(_Harness.debounce);

        expect(h.warnings, ['Taken', 'Taken']);

        h.dispose();
      });
    });

    test('retyping the original title re-arms the duplicate warning', () {
      fakeAsync((async) {
        final h = _Harness.existing()..coordinator.start();
        h.taken.add('taken');

        h.rename('Taken');
        async.elapse(_Harness.debounce);
        expect(h.warnings, ['Taken']);

        h.rename('Original');
        async.elapse(_Harness.debounce);

        h.rename('Taken');
        async.elapse(_Harness.debounce);

        expect(h.warnings, ['Taken', 'Taken']);

        h.dispose();
      });
    });

    test('a note opened untitled falls back to an empty title', () {
      fakeAsync((async) {
        final h = _Harness.existing(originalTitle: null)..coordinator.start();
        h.taken.add('taken');

        h.rename('Taken');
        async.elapse(_Harness.debounce);

        expect(h.updates.single.title, '');

        h.dispose();
      });
    });

    test('forceSave writes the caller-supplied content immediately', () {
      fakeAsync((async) {
        final h = _Harness.existing()..coordinator.start();

        unawaited(h.coordinator.forceSave(content: 'checkpoint'));
        async.flushMicrotasks();

        expect(h.updates.single.content, 'checkpoint');

        h.dispose();
      });
    });

    test('forceSave is inert for a note that was never created', () {
      fakeAsync((async) {
        final h = _Harness();

        unawaited(h.coordinator.forceSave(content: 'checkpoint'));
        async.flushMicrotasks();

        expect(h.events, isEmpty);

        h.dispose();
      });
    });
  });

  group('lifecycle pause', () {
    test(
      'an existing note is force-saved without waiting for the debounce',
      () {
        fakeAsync((async) {
          final h = _Harness.existing()..coordinator.start();

          h.type('v1');
          h.coordinator.saveOnLifecyclePause();
          async.flushMicrotasks();

          expect(h.updates.single.content, 'v1');

          h.dispose();
        });
      },
    );

    test('a brand-new note is created on the spot', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        h.content = 'draft';
        h.coordinator.saveOnLifecyclePause();
        async.flushMicrotasks();

        expect(h.creates.single.content, 'draft');

        h.dispose();
      });
    });

    test('an empty new note is not created', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        h.coordinator.saveOnLifecyclePause();
        async.flushMicrotasks();

        expect(h.events, isEmpty);

        h.dispose();
      });
    });
  });

  group('saveBeforeExit', () {
    test('an empty new note leaves nothing behind', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        unawaited(h.coordinator.saveBeforeExit());
        async.flushMicrotasks();

        expect(h.events, isEmpty);

        h.dispose();
      });
    });

    test('a new note with content is created before the page pops', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();
        h.taken.add('taken');

        h.title = 'Taken';
        h.content = 'draft';
        var popped = false;
        unawaited(h.coordinator.saveBeforeExit().then((_) => popped = true));
        async.flushMicrotasks();

        expect(popped, isTrue);
        expect(
          h.creates.single.title,
          '',
          reason: 'the title lookup completes before the caller pops',
        );
        expect(h.creates.single.content, 'draft');

        h.dispose();
      });
    });

    test('an existing note is flushed', () {
      fakeAsync((async) {
        final h = _Harness.existing()..coordinator.start();

        h.type('v1');
        unawaited(h.coordinator.saveBeforeExit());
        async.flushMicrotasks();

        expect(h.updates.single.content, 'v1');

        h.dispose();
      });
    });

    test('a create already in flight is not repeated', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        h.type('draft');
        async.flushMicrotasks();
        unawaited(h.coordinator.saveBeforeExit());
        async.flushMicrotasks();

        expect(h.events, hasLength(1));

        h.dispose();
      });
    });
  });

  group('noteCreated', () {
    test('adopts the id and tracks, so the next change updates', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        h.type('hello');
        async.flushMicrotasks();
        expect(h.creates, hasLength(1));

        h.coordinator.noteCreated('note-9');
        expect(h.coordinator.effectiveNoteId, 'note-9');
        expect(h.coordinator.isCreatingNewNote, isFalse);

        h.type('hello world');
        async.elapse(_Harness.debounce);

        expect(h.updates.single.noteId, 'note-9');
        expect(h.updates.single.content, 'hello world');

        h.dispose();
      });
    });

    test('content typed while the create was in flight is still written', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        h.type('h');
        async.flushMicrotasks();
        expect(h.creates.single.content, 'h');

        // The rest of the word lands before the bloc reports the id, so
        // the auto-save baseline has to be what the create wrote ('h'),
        // not what the editor holds now.
        h.type('hello');
        h.coordinator.noteCreated('note-9');

        unawaited(h.coordinator.saveBeforeExit());
        async.flushMicrotasks();

        expect(h.updates, hasLength(1));
        expect(h.updates.single.noteId, 'note-9');
        expect(h.updates.single.content, 'hello');

        h.dispose();
      });
    });

    test('a title typed while the create was in flight is still written', () {
      fakeAsync((async) {
        final h = _Harness()..coordinator.start();

        h.type('body');
        async.flushMicrotasks();
        expect(h.creates.single.title, '');

        h.title = 'Named';
        h.coordinator.onContentChanged();
        h.coordinator.noteCreated('note-9');

        unawaited(h.coordinator.saveBeforeExit());
        async.flushMicrotasks();

        expect(h.updates.single.title, 'Named');

        h.dispose();
      });
    });
  });

  group('contentLoaded', () {
    test('the loaded text is a baseline, not an edit', () {
      fakeAsync((async) {
        final h = _Harness.existing()..coordinator.start();

        // The page loads the stored text into the editor, which fires its
        // text listener exactly like a keystroke would.
        h.type('the stored text');
        h.coordinator.contentLoaded();
        async.elapse(_Harness.debounce * 10);

        expect(h.events, isEmpty, reason: 'reading a note must not rewrite it');
        expect(h.coordinator.hasChanges.value, isFalse);

        h.dispose();
      });
    });

    test('an edit after the load still saves', () {
      fakeAsync((async) {
        final h = _Harness.existing()..coordinator.start();

        h.type('the stored text');
        h.coordinator.contentLoaded();

        h.type('the stored text, edited');
        async.elapse(_Harness.debounce);

        expect(h.updates.single.content, 'the stored text, edited');

        h.dispose();
      });
    });
  });

  group('hasChanges', () {
    test('markChanged flips it exactly once', () {
      fakeAsync((async) {
        final h = _Harness();
        final seen = <bool>[];
        h.coordinator.hasChanges.addListener(
          () => seen.add(h.coordinator.hasChanges.value),
        );

        h.coordinator.markChanged();
        h.coordinator.markChanged();

        expect(seen, [true]);
        expect(h.coordinator.hasChanges.value, isTrue);

        h.dispose();
      });
    });

    test('markChanged arms auto-save for a listener-bypassing edit', () {
      fakeAsync((async) {
        final h = _Harness.existing()..coordinator.start();

        // A checkbox toggled through the tap interceptor: the document
        // moved without the page's text listener ever running.
        h.content = 'v0 [x]';
        h.coordinator.markChanged();
        async.elapse(_Harness.debounce);

        expect(h.updates.single.content, 'v0 [x]');
        expect(h.coordinator.hasChanges.value, isFalse);

        h.dispose();
      });
    });

    test('markChanged on a note that does not exist yet only flags it', () {
      fakeAsync((async) {
        final h = _Harness();

        h.coordinator.markChanged();
        async.elapse(_Harness.debounce * 10);

        expect(h.coordinator.hasChanges.value, isTrue);
        expect(h.events, isEmpty);

        h.dispose();
      });
    });

    test('a completed save clears it', () {
      fakeAsync((async) {
        final h = _Harness.existing()..coordinator.start();

        h.type('v1');
        expect(h.coordinator.hasChanges.value, isTrue);

        async.elapse(_Harness.debounce);

        expect(h.coordinator.hasChanges.value, isFalse);
        expect(h.coordinator.saveStatus.value, SaveStatus.saved);

        h.dispose();
      });
    });

    testWidgets('a change detected mid-frame lands after it', (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      bool? duringBuild;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            h.coordinator.markChanged();
            duringBuild = h.coordinator.hasChanges.value;
            return const SizedBox.shrink();
          },
        ),
      );

      expect(
        duringBuild,
        isFalse,
        reason: 'writing a listenable mid-build would rebuild during layout',
      );
      expect(h.coordinator.hasChanges.value, isTrue);
    });
  });

  group('dispose', () {
    test('a pending save never reaches the bloc', () {
      fakeAsync((async) {
        final h = _Harness.existing()..coordinator.start();

        h.type('v1');
        h.coordinator.dispose();
        async.elapse(_Harness.debounce * 10);

        expect(h.events, isEmpty);
      });
    });
  });
}

typedef _Lookup = ({String title, String? excludeId});

class _Harness {
  _Harness({String? noteId, String? originalTitle, this.title = ''}) {
    coordinator = NoteSaveCoordinator(
      folderId: 'folder-1',
      noteId: noteId,
      originalTitle: originalTitle,
      title: () => title,
      content: () => content,
      titleExists: ({required String title, String? excludeId}) async {
        lookups.add((title: title, excludeId: excludeId));
        final gate = lookupGate;
        if (gate != null) await gate.future;
        return taken.contains(title.trim().toLowerCase());
      },
      dispatch: _dispatch,
      onDuplicateTitle: warnings.add,
      autoSaveFactory: ({required onSave, required onChangeDetected}) =>
          AutoSaveService(
            onSave: onSave,
            onChangeDetected: onChangeDetected,
            debounceDelay: debounce,
            saveInterval: interval,
          ),
    );
  }

  /// A note that already exists, opened with a stored title.
  factory _Harness.existing({String? originalTitle = 'Original'}) => _Harness(
    noteId: 'note-1',
    originalTitle: originalTitle,
    title: originalTitle ?? '',
  )..content = 'v0';

  static const Duration debounce = Duration(milliseconds: 100);
  static const Duration interval = Duration(seconds: 30);

  late final NoteSaveCoordinator coordinator;

  /// Titles already used by a sibling note, lower-cased.
  final Set<String> taken = <String>{};

  /// When set, every `titleExists` lookup suspends on this completer, so a
  /// test can hold a create inside its round trip and drive what happens
  /// while it is parked there.
  Completer<void>? lookupGate;

  final List<OptimizedNoteEvent> events = <OptimizedNoteEvent>[];
  final List<_Lookup> lookups = <_Lookup>[];
  final List<String> warnings = <String>[];

  String title;
  String content = '';

  List<CreateOptimizedNote> get creates =>
      events.whereType<CreateOptimizedNote>().toList();

  List<UpdateOptimizedNote> get updates =>
      events.whereType<UpdateOptimizedNote>().toList();

  /// The bloc's stand-in: records the event and completes the update's
  /// completer, which is what unblocks the auto-save write.
  void _dispatch(OptimizedNoteEvent event) {
    events.add(event);
    if (event is UpdateOptimizedNote) event.completer?.complete();
  }

  void type(String next) {
    content = next;
    coordinator.onContentChanged();
  }

  void rename(String next) {
    title = next;
    coordinator.onContentChanged();
  }

  void dispose() => coordinator.dispose();
}
