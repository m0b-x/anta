@Tags(['benchmark'])
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/tables/notes_binding.dart';

import 'support/sync_pair.dart';

/// How long the browser's queries wait while the phone that installed the
/// chunked wire first runs its cutover: 40 notes of 300 KB written on A and
/// synced by both; then B is put back as the older build left it — every
/// chunk row without a hash, as every row written before v46 is; the space
/// holding each note as the whole-body document the older build pushed; its
/// `wire_version` one below the schema. B's next run reads every note again
/// (the whole bodies, met at equal stamps, re-queue their notes) and then
/// drains them, re-cutting each legacy note on its way out
/// (`ContentChunkDao.hashLegacy`) and hashing its manifest. A trivial select
/// is issued on B every 10 ms through the whole run, pull and drain
/// together; the longest one is the longest the database was held.
///
/// Both databases are files on background isolates with
/// `configureSqliteConnection`'s pragmas, as the app opens them. **Tagged
/// `benchmark` and excluded from the default run**: a wall-clock number on a
/// loaded machine is no pass/fail signal. Run it alone:
///
/// ```powershell
/// flutter test --tags benchmark --run-skipped test/services/sync/sync_cutover_stall_benchmark_test.dart
/// ```
void main() {
  const noteCount = 40;
  const noteChars = 300 * 1000;

  test('the cutover run of a phone holding $noteCount legacy notes of 300 KB '
      'holds the database briefly through its pull and its drain', () async {
    final pair = await SyncPair.open(
      background: true,
      setup: configureSqliteConnection,
    );
    try {
      final folder = await pair.a.db.folderDao.createFolder(name: 'Logs');
      final random = Random(7);
      final ids = [
        for (var n = 0; n < noteCount; n++)
          (await writeNote(
            pair.a,
            folderId: folder.id,
            title: 'Log $n',
            body: _body(random, n, noteChars),
          )).id,
      ];
      await pair.a.syncFiringSpacing();
      await pair.b.syncFiringSpacing();
      expect(await pair.b.db.noteDao.getNoteCount(null), noteCount);

      for (final id in ids) {
        final manifest = pair.gateway.rowsOf(pair.space, 'notes')[id]!;
        pair.gateway.plant(
          pair.space,
          SyncEnvelope(
            table: manifest.table,
            rowKey: manifest.rowKey,
            hlc: manifest.hlc,
            deviceId: manifest.deviceId,
            version: manifest.version,
            op: manifest.op,
            ownerId: manifest.ownerId,
            data: {...manifest.data!}
              ..remove(NotesBinding.chunksKey)
              ..remove(NotesBinding.bodyHashKey)
              ..[JsonKeys.content] = await pair.a.db.contentChunkDao
                  .loadContent(id),
          ),
        );
      }
      await pair.b.db.customStatement(
        'UPDATE content_chunks SET content_hash = NULL',
      );
      await pair.b.db.syncDao.setValue(
        SyncDao.keyWireVersion,
        '${syncSchema - 1}',
      );

      final run = await _probed(
        pair.b,
        () async => (await pair.b.syncFiringSpacing()).$1,
      );

      expect(run.report.failure, isNull);
      expect(
        await pair.b.db.syncDao.getValue(SyncDao.keyWireVersion),
        '$syncSchema',
      );
      expect(run.report.pushedRows, greaterThanOrEqualTo(noteCount));
      expect(await pair.b.db.syncOutboxDao.count(), 0);
      for (final id in ids) {
        expect(
          await pair.b.db.contentChunkDao.hashesOf(id),
          everyElement(isNotNull),
          reason: id,
        );
      }
      // ignore: avoid_print
      print(
        '\n=== cutover run, pull and drain: $noteCount legacy notes x '
        '$noteChars chars ===\n'
        '${run.table('${run.report.pulledRows} rows pulled in '
        '${run.report.pages} pages, ${run.report.pushedRows} pushed')}',
      );
    } finally {
      await pair.close();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// What [_probed] measured around one run.
typedef _Probe = ({
  SyncRunReport report,
  Duration run,
  int probes,
  Duration longest,
  Duration longestGap,
  Duration longestHeld,
  Duration held,
  int transactions,
});

extension on _Probe {
  String table(String rows) =>
      '  run           ${run.inMilliseconds} ms ($rows)\n'
      '  probes        $probes\n'
      '  longest wait  ${longest.inMilliseconds} ms\n'
      '  longest gap   ${longestGap.inMilliseconds} ms\n'
      '  longest tx    ${longestHeld.inMilliseconds} ms\n'
      '  all tx        ${held.inMilliseconds} ms in $transactions\n';
}

/// [run] with a trivial select issued on [device] every 10 ms until it
/// ends, and the longest any transaction stayed open meanwhile — what the
/// select waits behind, apart from the isolate being busy.
Future<_Probe> _probed(
  SyncDevice device,
  Future<SyncRunReport> Function() run,
) async {
  final db = device.db;
  var done = false;
  var longest = Duration.zero;
  var longestGap = Duration.zero;
  var probes = 0;
  final open = Stopwatch();
  var longestHeld = Duration.zero;
  var held = Duration.zero;
  var transactions = 0;
  device.statements.onTransaction = (begins) {
    if (begins) {
      open
        ..reset()
        ..start();
      return;
    }
    transactions++;
    held += open.elapsed;
    if (open.elapsed > longestHeld) longestHeld = open.elapsed;
  };
  final probing = () async {
    final gap = Stopwatch()..start();
    while (!done) {
      final wait = Stopwatch()..start();
      await db.customSelect('SELECT 1').get();
      wait.stop();
      probes++;
      if (wait.elapsed > longest) longest = wait.elapsed;
      if (gap.elapsed > longestGap) longestGap = gap.elapsed;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gap.reset();
    }
  }();
  final watch = Stopwatch()..start();
  final report = await run();
  watch.stop();
  done = true;
  await probing;
  device.statements.onTransaction = null;
  return (
    report: report,
    run: watch.elapsed,
    probes: probes,
    longest: longest,
    longestGap: longestGap,
    longestHeld: longestHeld,
    held: held,
    transactions: transactions,
  );
}

/// [length] code units of prose that no other note shares, so every note
/// cuts into chunks of its own.
String _body(Random random, int note, int length) {
  const words = [
    'squat',
    'bench',
    'press',
    'row',
    'deadlift',
    'rest',
    'tempo',
    'set',
    'reps',
    'warm-up',
    'cool-down',
    'felt',
    'heavy',
    'light',
    'easy',
    'hard',
  ];
  final out = StringBuffer();
  var line = 0;
  while (out.length < length) {
    out.write('- note $note line ${line++}:');
    for (var i = 0; i < 8; i++) {
      out
        ..write(' ')
        ..write(words[random.nextInt(words.length)])
        ..write(random.nextInt(200));
    }
    out.write('\n');
  }
  return out.toString().substring(0, length);
}
