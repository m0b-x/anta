import 'package:flutter/foundation.dart';

import 'calendar_guide_demo.dart';
import 'sync_guide_tries.dart';

/// One note as one phone holds it on a sync card's stage: its title, its
/// lines — a task list's, whose ticked lines are [ticked] — and the edit it
/// stands at. [stamp] stands in for the note's clock stamp, the one the
/// app's merge orders two edits by; [editedOn] is the phone that made that
/// edit, so a step can tell a tick made there from one made here.
@immutable
final class GuideSyncNote {
  const GuideSyncNote({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.lines = const [],
    this.ticked = const {},
    this.stamp = 0,
    this.editedOn = GuidePhone.here,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final List<String> lines;
  final Set<int> ticked;
  final int stamp;
  final GuidePhone editedOn;

  /// Its text — the title, the lines and their ticks — the same as
  /// [other]'s: two versions that say the same file no copy.
  bool sameText(GuideSyncNote other) =>
      title == other.title &&
      listEquals(lines, other.lines) &&
      setEquals(ticked, other.ticked);

  GuideSyncNote _edited({
    required int stamp,
    required GuidePhone on,
    required DateTime at,
    List<String>? lines,
    Set<int>? ticked,
  }) => GuideSyncNote(
    id: id,
    title: title,
    updatedAt: at,
    lines: List.unmodifiable(lines ?? this.lines),
    ticked: Set.unmodifiable(ticked ?? this.ticked),
    stamp: stamp,
    editedOn: on,
  );
}

/// The two phones of a sync card (`docs/guide-hub-roadmap.md` §11.4 `sync`,
/// `offline`; D46): each phone's notes, whether it is online, what it has
/// changed and not yet sent, and the account's copy in between — the
/// engine's rules in miniature, so the stage cannot promise what the app
/// does not do. Pure Dart, owned by the card's world
/// ([GuideShareWorld.sync]) and gone with the page (D41).
///
/// A phone that syncs queues each change it makes ([waitingOn]); [deliver]
/// — the stage's beat (D47) — runs every phone that is online as the engine
/// runs: it takes in what the account holds, then sends what waits. Taking
/// in follows the merge: the later edit stays in the note, and when the
/// other side had an edit of its own the account had not seen, that edit is
/// filed beside it as a copy titled by [copyTitle] (the engine's
/// `fileConflictCopy`), so no line is lost — on the phone that met the
/// conflict, and on the other once the copy travels.
final class GuideSyncWorld {
  GuideSyncWorld({
    required List<GuideSyncNote> notes,
    required this.copyTitle,
    required DateTime Function() now,
    bool on = true,
    bool otherHasNotes = true,
    Set<GuidePhone> offline = const {},
  }) : _now = now,
       _on = on,
       _offline = {...offline} {
    for (final note in notes) {
      _notes[GuidePhone.here]!.add(note);
      _seen[GuidePhone.here]![note.id] = note.stamp;
      if (otherHasNotes) {
        _notes[GuidePhone.there]!.add(note);
        _seen[GuidePhone.there]![note.id] = note.stamp;
        _cloud[note.id] = note;
      }
    }
  }

  /// The title the app files a conflict's other edit under, at the moment
  /// it is filed (`conflictCopyTitle`).
  final String Function(String title, DateTime at) copyTitle;
  final DateTime Function() _now;

  final Map<GuidePhone, List<GuideSyncNote>> _notes = {
    for (final phone in GuidePhone.values) phone: [],
  };
  final Map<GuidePhone, Set<String>> _outbox = {
    for (final phone in GuidePhone.values) phone: {},
  };

  /// The highest stamp of another phone's edit each phone has taken in, per
  /// note: an older edit kept out is filed as a copy only once.
  final Map<GuidePhone, Map<String, int>> _seen = {
    for (final phone in GuidePhone.values) phone: {},
  };

  /// The account's copy of every note, as the phones last sent it.
  final Map<String, GuideSyncNote> _cloud = {};

  final Set<GuidePhone> _offline;
  bool _on;

  /// The stamps start past the seed's, so every edit on the stage is later.
  int _clock = 1;

  final Set<String> _added = {};
  final Set<String> _waited = {};
  final List<String> _copies = [];

  /// Whether this phone syncs its database — the other phone always does.
  bool get on => _on;

  bool syncs(GuidePhone phone) => phone == GuidePhone.there || _on;

  bool isOnline(GuidePhone phone) => !_offline.contains(phone);

  /// The notes on [phone], in the order its list shows them.
  List<GuideSyncNote> notesOn(GuidePhone phone) =>
      List.unmodifiable(_notes[phone]!);

  GuideSyncNote? noteOn(GuidePhone phone, String id) {
    for (final note in _notes[phone]!) {
      if (note.id == id) return note;
    }
    return null;
  }

  /// The changes [phone] made and has not sent yet: none while it does not
  /// sync, since it queues nothing then.
  int waitingOn(GuidePhone phone) => _outbox[phone]!.length;

  /// The notes she made with the stage's New note, in the order made.
  List<String> get added => List.unmodifiable(_added);

  /// A note she made waited on its phone for a connection.
  bool get waitedAny => _waited.isNotEmpty;

  bool hasWaited(String id) => _waited.contains(id);

  /// The conflict copies filed so far, by id.
  List<String> get copies => List.unmodifiable(_copies);

  /// She turns on "Sync this database": every note of this phone is queued,
  /// as a bind queues every row.
  void turnOn() {
    if (_on) return;
    _on = true;
    _outbox[GuidePhone.here]!.addAll([
      for (final note in _notes[GuidePhone.here]!) note.id,
    ]);
  }

  /// Airplane mode on [phone], or off.
  void setOnline(GuidePhone phone, bool online) {
    if (online) {
      _offline.remove(phone);
    } else {
      _offline.add(phone);
    }
  }

  /// A new note on [phone], at the end of its list.
  GuideSyncNote addNote(
    GuidePhone phone, {
    required String title,
    List<String> lines = const [],
  }) {
    final note = GuideSyncNote(
      id: '${GuideDemoCalendar.idPrefix}new-${_added.length + 1}',
      title: title,
      updatedAt: _now(),
      lines: List.unmodifiable(lines),
      stamp: ++_clock,
      editedOn: phone,
    );
    _notes[phone]!.add(note);
    _added.add(note.id);
    _queue(phone, note.id);
    return note;
  }

  /// The lines she added on each phone, wherever they stand now.
  final Map<GuidePhone, int> _linesAdded = {
    for (final phone in GuidePhone.values) phone: 0,
  };

  int linesAddedOn(GuidePhone phone) => _linesAdded[phone]!;

  /// [line] added at the end of [id] on [phone].
  void addLine(GuidePhone phone, String id, String line) {
    _linesAdded[phone] = _linesAdded[phone]! + 1;
    _edit(phone, id, (note, stamp, at) {
      return note._edited(
        stamp: stamp,
        on: phone,
        at: at,
        lines: [...note.lines, line],
      );
    });
  }

  /// The task line [index] of [id] ticked on [phone], or un-ticked.
  void tick(GuidePhone phone, String id, int index, bool done) =>
      _edit(phone, id, (note, stamp, at) {
        return note._edited(
          stamp: stamp,
          on: phone,
          at: at,
          ticked: done
              ? {...note.ticked, index}
              : ({...note.ticked}..remove(index)),
        );
      });

  void _edit(
    GuidePhone phone,
    String id,
    GuideSyncNote Function(GuideSyncNote note, int stamp, DateTime at) edit,
  ) {
    final list = _notes[phone]!;
    final at = list.indexWhere((note) => note.id == id);
    assert(at >= 0, id);
    list[at] = edit(list[at], ++_clock, _now());
    _queue(phone, id);
  }

  void _queue(GuidePhone phone, String id) {
    if (!syncs(phone)) return;
    _outbox[phone]!.add(id);
    if (!isOnline(phone)) _waited.add(id);
  }

  /// Something not yet on [phone] is on its way there: a change another
  /// phone has not sent, or one the account holds that [phone] lacks.
  /// Nothing travels to a phone that does not sync.
  bool inFlightTo(GuidePhone phone) {
    if (!syncs(phone)) return false;
    for (final other in GuidePhone.values) {
      if (other != phone && _outbox[other]!.isNotEmpty) return true;
    }
    return _accountAhead(phone);
  }

  /// The account holds a note [phone] lacks, or a later edit of one.
  bool _accountAhead(GuidePhone phone) => _cloud.values.any((remote) {
    final local = noteOn(phone, remote.id);
    return local == null || remote.stamp > local.stamp;
  });

  /// A beat would carry something now: a phone online with changes to
  /// send, or one online that lacks what the account holds. While every
  /// phone that could is offline, nothing sets out (spec §4).
  bool get canMove => GuidePhone.values.any(
    (phone) =>
        syncs(phone) &&
        isOnline(phone) &&
        (_outbox[phone]!.isNotEmpty || _accountAhead(phone)),
  );

  /// The beat's landing: every phone that syncs and is online takes in what
  /// the account holds, then sends what waits — over again until nothing
  /// moves, so what one phone sends reaches the other within the one beat.
  /// Returns the copies a conflict filed.
  List<String> deliver() {
    final before = _copies.length;
    for (var round = 0; round < GuidePhone.values.length + 1; round++) {
      var moved = false;
      for (final phone in GuidePhone.values) {
        if (!syncs(phone) || !isOnline(phone)) continue;
        moved = _pull(phone) || moved;
        moved = _push(phone) || moved;
      }
      if (!moved) break;
    }
    return _copies.sublist(before);
  }

  bool _pull(GuidePhone phone) {
    var moved = false;
    final list = _notes[phone]!;
    final outbox = _outbox[phone]!;
    final seen = _seen[phone]!;
    for (final remote in _cloud.values.toList()) {
      final at = list.indexWhere((note) => note.id == remote.id);
      if (at < 0) {
        list.add(remote);
        seen[remote.id] = remote.stamp;
        moved = true;
        continue;
      }
      final local = list[at];
      if (remote.stamp == local.stamp) continue;
      if (remote.stamp > local.stamp) {
        // The newer edit wins; this phone's own edit, never sent, is filed
        // beside it rather than lost.
        if (outbox.contains(local.id) && !local.sameText(remote)) {
          _fileCopy(phone, local, after: at);
        }
        list[list.indexWhere((note) => note.id == remote.id)] = remote;
        outbox.remove(remote.id);
        moved = true;
      } else if (remote.stamp > (seen[remote.id] ?? 0) &&
          !local.sameText(remote)) {
        // An older edit from elsewhere, kept out by this phone's newer one:
        // filed beside it, once.
        _fileCopy(phone, remote, after: at);
        moved = true;
      }
      if (remote.stamp > (seen[remote.id] ?? 0)) seen[remote.id] = remote.stamp;
    }
    return moved;
  }

  bool _push(GuidePhone phone) {
    final outbox = _outbox[phone]!;
    if (outbox.isEmpty) return false;
    for (final id in outbox) {
      final note = noteOn(phone, id)!;
      final remote = _cloud[id];
      if (remote == null || note.stamp > remote.stamp) _cloud[id] = note;
    }
    outbox.clear();
    return true;
  }

  /// [loser]'s text as a new note of [phone], right after the note it lost
  /// to, under the app's conflict title and queued like any local note.
  void _fileCopy(GuidePhone phone, GuideSyncNote loser, {required int after}) {
    final at = _now();
    final copy = GuideSyncNote(
      id: '${loser.id}-copy-${_copies.length + 1}',
      title: copyTitle(loser.title, at),
      updatedAt: at,
      lines: loser.lines,
      ticked: loser.ticked,
      stamp: ++_clock,
      editedOn: phone,
    );
    _notes[phone]!.insert(after + 1, copy);
    _copies.add(copy.id);
    _outbox[phone]!.add(copy.id);
  }
}
