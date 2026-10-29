import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the one route a synced write takes: every HLC a local write stamps
/// comes from `CrdtWrite` (`lib/database/crdt/crdt_write.dart`), the only code
/// that also queues the row in `sync_outbox`.
///
/// A source scan rather than a type-level fence, because the compiler cannot
/// draw this line: every DAO is an accessor on `AppDatabase`, so the clock
/// (`db.hlc`, which the merge paths must reach), every table and the outbox
/// table itself are in scope everywhere, and Dart has no friend visibility to
/// narrow them to one library. A stamp minted beside the helper still
/// compiles, still passes every behavioural test of its own table — and is a
/// write the push never hears of.
///
/// **It is a heuristic.** It reads text, so a determined bypass — the clock
/// passed around under another name, a table name built at run time — gets
/// past it. What it catches is the ordinary slip at review time; the proof
/// that each write queues its row is the per-table suites
/// (`sync_outbox_test.dart`, `sync_outbox_calendar_test.dart`).
void main() {
  /// Files that own the clock or the outbox, and what each may do.
  const owners = {
    // The helper: mints every stamp and writes every entry.
    'lib/database/crdt/crdt_write.dart': {_May.clock, _May.outbox},
    // The clock itself.
    'lib/database/crdt/hlc.dart': {_May.clock},
    // Declares `hlc`, `migrationBackfillHlc` and the outbox table and DAO.
    'lib/database/database.dart': {_May.clock, _May.backfill, _May.outbox},
    // Backfills rows that predate their CRDT columns, and creates the outbox
    // table — never a row in it.
    'lib/database/migrations/database_migrations.dart': {
      _May.backfill,
      _May.outboxSchema,
    },
    // The push side's view: reads, acknowledges, clears.
    'lib/database/daos/sync_outbox_dao.dart': {_May.outbox},
    // The table definition the DAO and the helper are generated from.
    'lib/database/tables/sync_outbox_table.dart': {_May.outbox},
    // The merge, the engine, the bind and the restore retire, re-seed or
    // read the queue through the DAO — never a stamp, never a row.
    'lib/database/crdt/crdt_merge.dart': {_May.outboxRetire},
    'lib/services/backup_service.dart': {_May.outboxRetire},
    'lib/services/sync/sync_binding_service.dart': {_May.outboxRetire},
    'lib/services/sync/sync_engine.dart': {_May.outboxRetire},
    'lib/services/sync/sync_puller.dart': {_May.outboxRetire},
    'lib/services/sync/sync_pusher.dart': {_May.outboxRetire},
    'lib/services/sync/sync_status_service.dart': {_May.outboxRetire},
  };

  /// The only places a local device may advance the clock from a remote
  /// stamp, each with the call it may make: the merge helper's clock step,
  /// which the puller calls once a pulled page committed and which follows
  /// the stamp that page stored (A5 review R98); the raise a merge makes
  /// inside the page's own transaction, which keeps the drift guard because
  /// that transaction can still roll back with nothing stored (A10 review
  /// R157); and the chunk merge that predates them.
  const merges = {
    ('lib/database/crdt/crdt_merge.dart', 'advanceClock', 'adopt'),
    (
      'lib/database/crdt/crdt_merge.dart',
      'advanceClockInTransaction',
      'update',
    ),
    ('lib/database/daos/content_chunk_dao.dart', 'mergeChunk', 'update'),
  };
  final mergeSites = {for (final merge in merges) (merge.$1, merge.$2)};

  final units = [
    for (final file in Directory('lib').listSync(recursive: true))
      if (file is File &&
          file.path.endsWith('.dart') &&
          !file.path.endsWith('.g.dart'))
        ..._units(file),
  ];
  Set<_May> may(_Unit unit) => owners[unit.path] ?? const {};

  test('the scan sees the code it guards, member by member', () {
    final seen = {for (final u in units) (u.path, u.name)};
    expect(
      seen,
      containsAll([
        ('lib/database/daos/calendar_event_dao.dart', 'tombstoneEventCascade'),
        ('lib/services/calendar_event_service.dart', 'deleteById'),
        ...mergeSites,
      ]),
    );
  });

  test('the clock is used only by its owners and the merges', () {
    final clock = [
      // The clock's own API on anything called `hlc` — not `.hlc` on a stamp
      // or an outbox row, which is a value, not the clock.
      RegExp(r'\bhlc ?\. ?(now|receive|update|adopt|nodeId)\b'),
      RegExp(r'\b(db|_db|database|_database|attachedDatabase) ?\. ?hlc\b'),
      RegExp(r'\) ?\. ?hlc\b'),
      RegExp(r'\bHybridLogicalClock\b'),
      RegExp(r'\bHlcTimestamp ?\('),
      RegExp(r'\bHlcTimestamp ?\. ?zero ?\('),
      RegExp(r'\bgenerateHlc ?\('),
    ];
    final backfill = RegExp(r'\bmigrationBackfillHlc ?\(');
    // `adopt` as well as `update`, and which of the two a site makes is
    // part of what is pinned: the page advance follows a far-ahead stamp it
    // has already stored (A5 review R98) where a raise inside the page's
    // transaction may not (A10 review R157).
    final advance = RegExp(r'\b\w+ ?\. ?hlc ?\. ?(update|adopt) ?\(');

    final strays = <String>[];
    final advancing = <(String, String?, String)>{};
    for (final unit in units) {
      final rights = may(unit);
      var text = unit.text;
      if (mergeSites.contains((unit.path, unit.name))) {
        for (final call in advance.allMatches(text)) {
          advancing.add((unit.path, unit.name, call.group(1)!));
        }
        text = text.replaceAll(advance, '');
      }
      if (!rights.contains(_May.clock)) {
        for (final pattern in clock) {
          if (pattern.hasMatch(text)) strays.add('$unit: ${pattern.pattern}');
        }
      }
      if (!rights.contains(_May.backfill) && backfill.hasMatch(text)) {
        strays.add('$unit: migrationBackfillHlc');
      }
    }

    expect(
      strays,
      isEmpty,
      reason:
          'take the stamp from CrdtWrite (stampLocal / newStamp) so the row '
          'is queued in the same transaction; only a merge advances the clock',
    );
    expect(
      advancing,
      merges,
      reason:
          'each merge must advance the clock from the remote stamp with the '
          'call listed for it; a missing or a swapped one either lost its '
          '`hlc.adopt` / `hlc.update` call, traded one for the other or the '
          'scan stopped seeing it',
    );
  });

  test('the outbox is named only by its owners', () {
    final names = [
      RegExp(r'\bsyncOutbox\b'),
      // `\bsyncOutbox\b` does not see it — the word does not end at the `x`
      // — so without this the DAO's own methods were reachable from
      // anywhere, `clear()`, which drops the whole queue, included.
      RegExp(r'\bsyncOutboxDao\b'),
      RegExp(r'\bSyncOutboxCompanion\b'),
      RegExp(r'\$SyncOutboxTable\b'),
      RegExp(r'sync_outbox', caseSensitive: false),
    ];
    final rowWrite = RegExp(
      r'\b(insert|replace|update|delete)\b[^;]*?\bsync_outbox\b',
      caseSensitive: false,
    );
    // What `_May.outboxRetire` allows: entries retired, re-seeded, dropped,
    // read or counted through the DAO, and the one receiver the pusher
    // binds to a local to page the queue through. Every other method of it
    // is a stray, and the table, its companion and the raw name stay out of
    // reach — so none of these files can add an entry of its own, which is
    // `CrdtWrite`'s alone.
    //
    // The receiver is named, never `= <anything>.syncOutboxDao`: an alias
    // alternative let an allow-listed file bind the DAO and then call
    // anything at all on it unchecked (A7 review R138).
    final retires = RegExp(
      r'\bsyncOutboxDao ?\. ?(ackThrough|requeueRow|requeueAll|clear|count'
      r'|maxHlc|pending|pendingForTable|watchQueued) ?\('
      r'|\bfinal outbox = _e\._db\.syncOutboxDao;',
    );

    final strays = <String>[];
    for (final unit in units) {
      final rights = may(unit);
      if (rights.contains(_May.outbox)) continue;
      if (rights.contains(_May.outboxSchema)) {
        if (rowWrite.hasMatch(unit.text)) strays.add('$unit: a row write');
        continue;
      }
      final text = rights.contains(_May.outboxRetire)
          ? unit.text.replaceAll(retires, '')
          : unit.text;
      for (final pattern in names) {
        if (pattern.hasMatch(text)) {
          strays.add('$unit: ${pattern.pattern}');
        }
      }
    }

    expect(
      strays,
      isEmpty,
      reason:
          'queue through CrdtWrite (enqueue / enqueueMany / enqueueIn); '
          'retire entries through SyncOutboxDao',
    );
  });

  test('every stamp minted is queued in the same member or its helper', () {
    final enqueues = RegExp(r'\benqueue\w* ?\(');
    final byName = <(String, String), _Unit>{
      for (final u in units)
        if (u.name != null) (u.path, u.name!): u,
    };
    bool queues(_Unit unit) => enqueues.hasMatch(unit.text);

    final strays = <String>[];
    for (final unit in units) {
      if (may(unit).contains(_May.clock)) continue;
      if (!RegExp(r'\bnewStamp ?\(').hasMatch(unit.text)) continue;
      if (queues(unit)) continue;
      final helpers = {
        for (final m in RegExp(r'\b(_\w+) ?\(').allMatches(unit.text))
          m.group(1)!,
      };
      final followed = helpers.any((name) {
        final helper = byName[(unit.path, name)];
        return helper != null && helper != unit && queues(helper);
      });
      if (!followed) strays.add('$unit');
    }

    expect(
      strays,
      isEmpty,
      reason:
          'a stamp from newStamp() must be queued with enqueue / enqueueMany '
          '/ enqueueIn in the same transaction; stampLocal() queues itself',
    );
  });
}

enum _May { clock, backfill, outbox, outboxRetire, outboxSchema }

/// One top-level or class-member declaration: its name and its source,
/// normalised for matching.
class _Unit {
  final String path;
  final int line;
  final String? name;
  final String text;

  const _Unit(this.path, this.line, this.name, this.text);

  @override
  String toString() => '$path:$line ${name ?? '<unnamed>'}';
}

/// A declaration starts on a line indented zero or two spaces — the house
/// format for top-level and class-member declarations — that opens with an
/// identifier; closing brackets and annotations belong to the unit around
/// them. Every such line resets the member a match is attributed to.
final _declaration = RegExp(r'^ {0,2}[A-Za-z_$]');

final _prose = RegExp(r'^\s*(//|(import|export|part|library)\b)');

final _nameOf = [
  RegExp(r'\b(?:get|set) ([A-Za-z_$][\w$]*)'),
  RegExp(r'\b(?:class|mixin|extension|enum|typedef) ([A-Za-z_$][\w$]*)'),
  RegExp(r'([A-Za-z_$][\w$]*) ?(?:<[^>()]*>)? ?\('),
  RegExp(r'([A-Za-z_$][\w$]*) ?[=;]'),
];

List<_Unit> _units(File file) {
  final path = file.path.replaceAll(r'\', '/');
  final units = <_Unit>[];
  int? start;
  String? name;
  final body = StringBuffer();

  void close() {
    final at = start;
    if (at != null) units.add(_Unit(path, at, name, _normalise(body)));
    body.clear();
  }

  final lines = file.readAsLinesSync();
  for (final (i, raw) in lines.indexed) {
    // Whole-line comments, doc comments included, are prose about the code,
    // and a directive's URI (`'../crdt/hlc.dart'`) is a path, not a call.
    final line = _prose.hasMatch(raw) ? '' : raw;
    if (_declaration.hasMatch(line)) {
      close();
      start = i + 1;
      name = null;
      for (final pattern in _nameOf) {
        final m = pattern.firstMatch(line);
        if (m != null) {
          name = m.group(1);
          break;
        }
      }
    }
    body.writeln(line);
  }
  close();
  return units;
}

/// Collapses whitespace and joins adjacent, concatenated and interpolated
/// string literals, so `'sync_' 'outbox'`, `'sync_' + 'outbox'` and
/// `'sync_${'outbox'}'` all read as `sync_outbox`.
String _normalise(StringBuffer source) {
  return source
      .toString()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'''['"] ?(\+ ?)?['"]'''), '')
      .replaceAll(RegExp(r'''\$\{ ?['"]'''), '')
      .replaceAll(RegExp(r'''['"] ?\}'''), '');
}
