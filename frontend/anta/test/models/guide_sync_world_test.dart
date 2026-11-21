import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/guide_sync_world.dart';
import 'package:anta/models/sync_guide_tries.dart';

/// The sync cards' world (`docs/guide-hub-roadmap.md` §11.4 `sync`,
/// `offline`): two phones of hers, each queueing what it changes and taking
/// in what the account holds when a beat lands, with the engine's rule for
/// one note edited on both — the later edit in the note, the other filed
/// beside it, on both phones.
void main() {
  const here = GuidePhone.here;
  const there = GuidePhone.there;
  final at = DateTime(2026, 11, 26, 9);

  GuideSyncNote seed(String id, {List<String> lines = const []}) =>
      GuideSyncNote(id: id, title: id, updatedAt: at, lines: lines, stamp: 1);

  GuideSyncWorld world({
    bool on = true,
    bool otherHasNotes = true,
    Set<GuidePhone> offline = const {},
    List<GuideSyncNote>? notes,
  }) => GuideSyncWorld(
    notes: notes ?? [seed('lisbon')],
    copyTitle: (title, at) => '$title (copy ${at.hour})',
    now: () => at,
    on: on,
    otherHasNotes: otherHasNotes,
    offline: offline,
  );

  List<String> ids(GuideSyncWorld world, GuidePhone phone) => [
    for (final note in world.notesOn(phone)) note.id,
  ];

  test('a note written with sync off stays on this phone', () {
    final sync = world(on: false, otherHasNotes: false);
    final note = sync.addNote(here, title: 'Groceries');
    expect(sync.waitingOn(here), 0);
    expect(sync.inFlightTo(there), isFalse);
    expect(sync.canMove, isFalse);
    sync.deliver();
    expect(ids(sync, here), ['lisbon', note.id]);
    expect(sync.notesOn(there), isEmpty);
  });

  test('turning sync on queues everything, and the beat carries it', () {
    final sync = world(on: false, otherHasNotes: false);
    final note = sync.addNote(here, title: 'Groceries');
    sync.turnOn();
    expect(sync.waitingOn(here), 2);
    expect(sync.inFlightTo(there), isTrue);
    expect(sync.notesOn(there), isEmpty, reason: 'only after the beat');
    sync.deliver();
    expect(ids(sync, there), ['lisbon', note.id]);
    expect(sync.waitingOn(here), 0);
    expect(sync.inFlightTo(there), isFalse);
  });

  test('with sync on a note reaches the other phone only after the beat', () {
    final sync = world();
    final note = sync.addNote(here, title: 'Groceries', lines: ['Milk']);
    expect(sync.noteOn(there, note.id), isNull);
    expect(sync.inFlightTo(there), isTrue);
    expect(sync.copies, isEmpty);
    sync.deliver();
    expect(sync.noteOn(there, note.id)?.lines, ['Milk']);
  });

  test('offline it waits, and the other phone gets nothing until airplane '
      'mode is off', () {
    final sync = world(offline: {here});
    final note = sync.addNote(here, title: 'Groceries');
    expect(sync.waitingOn(here), 1);
    expect(sync.hasWaited(note.id), isTrue);
    expect(sync.inFlightTo(there), isTrue, reason: 'held, still on its way');
    expect(sync.canMove, isFalse, reason: 'no beat sets out');
    sync.deliver();
    expect(sync.noteOn(there, note.id), isNull);

    sync.setOnline(here, true);
    expect(sync.canMove, isTrue);
    sync.deliver();
    expect(sync.noteOn(there, note.id), isNotNull);
    expect(sync.waitingOn(here), 0);
  });

  test('a tick made there comes back here', () {
    final sync = world();
    final note = sync.addNote(here, title: 'Groceries', lines: ['Milk']);
    sync.deliver();
    sync.tick(there, note.id, 0, true);
    expect(sync.noteOn(here, note.id)!.ticked, isEmpty);
    expect(sync.inFlightTo(here), isTrue);
    sync.deliver();
    final back = sync.noteOn(here, note.id)!;
    expect(back.ticked, {0});
    expect(back.editedOn, there);
    expect(sync.copies, isEmpty, reason: 'one edit is no conflict');
  });

  group('one note edited on both phones offline', () {
    void expectResolved(GuideSyncWorld sync, {required List<String> kept}) {
      expect(sync.copies, hasLength(1));
      final copyId = sync.copies.single;
      for (final phone in GuidePhone.values) {
        final notes = sync.notesOn(phone);
        expect(notes.map((n) => n.id), ['packing', copyId], reason: '$phone');
        expect(notes.first.lines, kept, reason: '$phone');
        expect(notes.last.title, 'packing (copy 9)', reason: '$phone');
        final everyLine = {for (final n in notes) ...n.lines};
        expect(
          everyLine,
          containsAll(['Passport', 'Sunscreen', 'Umbrella']),
          reason: 'no line lost on $phone',
        );
      }
    }

    GuideSyncWorld conflicted() {
      final sync = world(
        offline: {here, there},
        notes: [
          seed('packing', lines: ['Passport']),
        ],
      );
      sync.addLine(here, 'packing', 'Sunscreen');
      sync.addLine(there, 'packing', 'Umbrella');
      return sync;
    }

    test('both online at once: the later edit stays, the other is a copy '
        'on both phones', () {
      final sync = conflicted();
      expect(sync.canMove, isFalse);
      sync
        ..setOnline(here, true)
        ..setOnline(there, true)
        ..deliver();
      expectResolved(sync, kept: ['Passport', 'Umbrella']);
      expect(sync.notesOn(here).last.lines, ['Passport', 'Sunscreen']);
    });

    for (final first in GuidePhone.values) {
      test('${first.name} online first, the other after: the same end', () {
        final sync = conflicted();
        sync
          ..setOnline(first, true)
          ..deliver();
        expect(sync.copies, isEmpty, reason: 'nothing met yet');
        sync
          ..setOnline(first == here ? there : here, true)
          ..deliver();
        expectResolved(sync, kept: ['Passport', 'Umbrella']);
      });
    }

    test('the later edit wins whichever phone made it', () {
      final sync = world(
        offline: {here, there},
        notes: [
          seed('packing', lines: ['Passport']),
        ],
      );
      sync
        ..addLine(there, 'packing', 'Umbrella')
        ..addLine(here, 'packing', 'Sunscreen')
        ..setOnline(here, true)
        ..setOnline(there, true)
        ..deliver();
      expectResolved(sync, kept: ['Passport', 'Sunscreen']);
    });

    test('a second landing files nothing more', () {
      final sync = conflicted()
        ..setOnline(here, true)
        ..setOnline(there, true)
        ..deliver();
      expect(sync.deliver(), isEmpty);
      expect(sync.copies, hasLength(1));
      expect(sync.canMove, isFalse);
    });
  });
}
