import 'dart:io';

import 'errors.dart';
import 'paths.dart';
import 'seed.dart';

/// When `qa pass` puts the suite's fixture back.
enum ReseedMode {
  /// Before every flow, so no flow can see what an earlier one left behind.
  flow,

  /// Once before the first flow: the alerts fixtures are clock-relative and
  /// their flows consume one seed in order.
  suite,

  /// Never; the flows run on whatever the app holds.
  none,
}

/// A flow directory's `_suite.txt`: what `qa pass` needs to make every
/// flow start from a known state.
class SuiteManifest {
  const SuiteManifest({
    required this.suite,
    this.fixture,
    this.reseed = ReseedMode.flow,
    this.shard = true,
    this.settings = const [],
    this.prelude,
  });

  /// The manifest's file name inside a flow directory.
  static const String fileName = '_suite.txt';

  static const List<String> knownKeys = [
    'fixture',
    'reseed',
    'shard',
    'settings',
    'prelude',
  ];

  final String suite;

  /// The seed fixture, relative to the package root as written.
  final String? fixture;
  final ReseedMode reseed;

  /// Whether `--shard i/n` may split this suite across devices.
  final bool shard;

  /// `--setting key=value` overrides applied with every reseed.
  final List<String> settings;

  /// A step file in the suite directory, run after each reseed.
  final String? prelude;

  /// Parses `key=value` lines; `#` starts a comment line. Every key but
  /// `settings` may appear once, and an unknown key is refused so a typo
  /// cannot silently fall back to a default.
  factory SuiteManifest.parse(String text, {required String suite}) {
    String? fixture;
    ReseedMode? reseed;
    bool? shard;
    String? prelude;
    final settings = <String>[];
    final seen = <String>{};
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final where = '$fileName of "$suite", line ${i + 1}';
      final eq = line.indexOf('=');
      if (eq <= 0) {
        throw UsageFailure('$where: expected key=value, got "$line"');
      }
      final key = line.substring(0, eq).trim();
      final value = line.substring(eq + 1).trim();
      if (!knownKeys.contains(key)) {
        throw UsageFailure(
          '$where: unknown key "$key" (known: ${knownKeys.join(', ')})',
        );
      }
      if (key != 'settings' && !seen.add(key)) {
        throw UsageFailure('$where: "$key" is set twice');
      }
      if (value.isEmpty) {
        throw UsageFailure('$where: "$key" has no value');
      }
      switch (key) {
        case 'fixture':
          fixture = value;
        case 'reseed':
          reseed = ReseedMode.values.where((m) => m.name == value).firstOrNull ??
              (throw UsageFailure(
                '$where: reseed must be flow, suite or none (got "$value")',
              ));
        case 'shard':
          shard = switch (value) {
            'yes' => true,
            'no' => false,
            _ => throw UsageFailure(
                '$where: shard must be yes or no (got "$value")',
              ),
          };
        case 'settings':
          try {
            parseSettingOverride(value);
          } on UsageFailure catch (e) {
            throw UsageFailure('$where: ${e.message}');
          }
          settings.add(value);
        case 'prelude':
          prelude = value;
      }
    }
    return SuiteManifest(
      suite: suite,
      fixture: fixture,
      reseed: reseed ?? ReseedMode.flow,
      shard: shard ?? true,
      settings: settings,
      prelude: prelude,
    );
  }

  /// Reads `tool/qa/flows/<suite>/_suite.txt`.
  static SuiteManifest load(String flowsDir, String suite) {
    final file = File(joinPath(flowsDir, [suite, fileName]));
    if (!file.existsSync()) {
      throw UsageFailure(
        'no $fileName in ${joinPath(flowsDir, [suite])} — `qa pass` needs one '
        '(fixture=…, reseed=flow|suite|none, shard=yes|no); `qa flows $suite` '
        'runs the directory without it',
      );
    }
    return SuiteManifest.parse(file.readAsStringSync(), suite: suite);
  }
}

/// A file in a flow directory whose name starts with `_` is the suite's
/// own (its manifest, its prelude), never a flow.
bool isFlowFileName(String name) =>
    name.endsWith('.txt') && !name.startsWith('_');

/// A flow's name: its file name without `.txt`.
String flowNameOf(String fileName) => fileName.endsWith('.txt')
    ? fileName.substring(0, fileName.length - 4)
    : fileName;

/// Parses `--shard i/n` into its 1-based index and count.
(int, int) parseShard(String raw) {
  final match = RegExp(r'^(\d+)/(\d+)$').firstMatch(raw.trim());
  // tryParse: a digit run past 64 bits is a typo to refuse, not a crash.
  final index = match == null ? null : int.tryParse(match.group(1)!);
  final count = match == null ? null : int.tryParse(match.group(2)!);
  if (index == null || count == null || count < 1 || index < 1 || index > count) {
    throw UsageFailure('--shard takes i/n with 1 <= i <= n (got "$raw"), e.g. --shard 2/3');
  }
  return (index, count);
}

/// The flows shard [index] of [count] runs: every one whose 0-based
/// position modulo [count] is `index - 1`, so shards interleave and each
/// gets a spread of short and long flows rather than one block.
List<T> shardOf<T>(List<T> flows, int index, int count) => [
      for (var i = 0; i < flows.length; i++)
        if (i % count == index - 1) flows[i],
    ];

/// Picks the flows a pass runs out of [available] (flow names, any order):
/// all of them, or those [wanted] names, sorted by name, then the shard.
List<String> selectFlows(
  List<String> available, {
  required SuiteManifest manifest,
  List<String> wanted = const [],
  (int, int)? shard,
}) {
  final sorted = [...available]..sort();
  var picked = sorted;
  if (wanted.isNotEmpty) {
    final names = wanted.map(flowNameOf).toSet();
    final unknown = names.where((n) => !sorted.contains(n)).toList();
    if (unknown.isNotEmpty) {
      throw UsageFailure(
        'no flow ${unknown.map((n) => '"$n"').join(', ')} in "${manifest.suite}" '
        '(have: ${sorted.join(', ')})',
      );
    }
    picked = sorted.where(names.contains).toList();
  }
  if (shard != null) {
    final (index, count) = shard;
    if (count > 1 && !manifest.shard) {
      throw UsageFailure(
        '"${manifest.suite}" says shard=no in its ${SuiteManifest.fileName} — '
        'its flows share one seed in order, so it runs whole on one device',
      );
    }
    picked = shardOf(picked, index, count);
  }
  return picked;
}
