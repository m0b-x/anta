import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/shell_words.dart';
import '../../tool/qa/src/suite.dart';

/// The saved flows' house rules (docs/qa-pass-rework.md decision J): a flow
/// reaches a control by its semantics id, so neither a copy change nor the
/// locale moves the target; a label target is seeded or typed content the
/// suite lists in its `_labels.txt`.
void main() {
  const flowsDir = 'tool/qa/flows';
  final suites = Directory(flowsDir).listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('there are suites to lint', () {
    expect(
      suites.map(_nameOf),
      containsAll(<String>['alerts', 'alerts_pair', 'browser', 'calendar']),
    );
  });

  for (final dir in suites) {
    final suite = _nameOf(dir);
    group('suite $suite', () {
      final flows =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => isFlowFileName(_nameOf(f)))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      test('its manifest parses and names files that exist', () {
        final manifest = SuiteManifest.load(flowsDir, suite);
        final fixture = manifest.fixture;
        if (fixture != null) {
          expect(File(fixture).existsSync(), isTrue, reason: fixture);
        }
        final prelude = manifest.prelude;
        if (prelude != null) {
          final file = File('${dir.path}/$prelude');
          expect(file.existsSync(), isTrue, reason: file.path);
        }
        expect(flows, isNotEmpty);
      });

      test('every flow ends with errors', () {
        for (final flow in flows) {
          final steps = parseStepLines(flow.readAsStringSync());
          expect(
            steps.isEmpty ? null : stepVerb(splitShellWords(steps.last)),
            'errors',
            reason: '${_nameOf(flow)} must end with `errors`',
          );
        }
      });

      test('every acting target is an id, an index, a point, a placeholder '
          'or a listed label', () {
        final labels = _readLabels(File('${dir.path}/_labels.txt'));
        final misses = <String>[];
        final nth = <String>[];
        final files = [
          ...flows,
          for (final f in dir.listSync().whereType<File>())
            if (_nameOf(f) == '_prelude.txt') f,
        ];
        for (final file in files) {
          for (final line in parseStepLines(file.readAsStringSync())) {
            final where = '${_nameOf(file)}: $line';
            final words = splitShellWords(line);
            if (words.contains('--nth')) nth.add(where);
            for (final target in actingTargets(words)) {
              if (!isAllowedTarget(target, labels)) misses.add(where);
            }
            for (final target in expectTargets(words)) {
              if (target.startsWith('id:') && !isIdTarget(target)) {
                misses.add(where);
              }
            }
          }
        }
        expect(
          misses,
          isEmpty,
          reason:
              'label targets not in $suite/_labels.txt or malformed ids:\n'
              '${misses.join('\n')}\n'
              '--nth steps (it numbers hidden matches too):\n'
              '${nth.isEmpty ? '(none)' : nth.join('\n')}',
        );
      });
    });
  }

  group('target rules', () {
    test('ids, indexes, points and placeholders need no listing', () {
      for (final target in [
        'id:calendar-add-event',
        'id:holiday-restore-christmasDay-{{day+60}}',
        '#12',
        '120,480',
        '{{longdate+1}}',
      ]) {
        expect(isAllowedTarget(target, const {}), isTrue, reason: target);
      }
    });

    test('a label is allowed only when listed', () {
      expect(isAllowedTarget('Leg day', const {'Leg day'}), isTrue);
      expect(isAllowedTarget('Discard changes', const {'Leg day'}), isFalse);
      expect(isAllowedTarget('id:', const {}), isFalse);
      expect(isAllowedTarget('id:has space', const {}), isFalse);
    });

    test('drag lints both ends, the other verbs their first target', () {
      expect(actingTargets(splitShellWords('drag id:a "Row" --hold 0')), [
        'id:a',
        'Row',
      ]);
      expect(actingTargets(splitShellWords('tap "Day" --settle 2000')), [
        'Day',
      ]);
      expect(actingTargets(splitShellWords('wait id:x --gone')), ['id:x']);
      expect(actingTargets(splitShellWords('expect "Anything"')), isEmpty);
      expect(actingTargets(splitShellWords('key back')), isEmpty);
    });

    test('--wait, --wait-gone and --in targets are linted too', () {
      expect(
        actingTargets(
          splitShellWords('tap id:a --wait "Sheet" --wait-gone=Menu --shot s'),
        ),
        ['id:a', 'Sheet', 'Menu'],
      );
      expect(
        actingTargets(splitShellWords('scroll-to id:row --in "List" --up')),
        ['id:row', 'List'],
      );
      expect(
        actingTargets(splitShellWords('key back --wait-gone "Dialog"')),
        ['Dialog'],
      );
      expect(isAllowedTarget('Sheet', const {}), isFalse);
    });

    test('a leading global option does not hide the verb', () {
      expect(
        actingTargets(
          splitShellWords('--via native tap "Day" --wait id:x'),
        ),
        ['Day', 'id:x'],
      );
      expect(
        actingTargets(splitShellWords('-d emulator-5556 --verbose wait "Row"')),
        ['Row'],
      );
      expect(
        actingTargets(splitShellWords('--via=native swipe up --wait "Row"')),
        ['Row'],
      );
      expect(
        expectTargets(splitShellWords('--via=agent expect "A" --absent B')),
        ['A', 'B'],
      );
      expect(stepVerb(splitShellWords('--via native errors')), 'errors');
    });

    test('--ordered is a bare flag, not a value-taking one', () {
      expect(
        expectTargets(splitShellWords('expect --ordered "A" "B" --timeout 3')),
        ['A', 'B'],
      );
    });

    test('expect hands back its targets and its --absent ones', () {
      expect(
        expectTargets(
          splitShellWords('expect id:a "Text" --absent id:b --timeout 3'),
        ),
        ['id:a', 'Text', 'id:b'],
      );
    });

    test('a label file keeps "#" labels and drops "# " comments', () {
      final file = File(
        '${Directory.systemTemp.createTempSync('anta_flows_lint_').path}'
        '/_labels.txt',
      )..writeAsStringSync('# a comment\n#\n#3F51B5\n  Leg day  \n\n');
      addTearDown(() => file.parent.deleteSync(recursive: true));
      expect(_readLabels(file), {'#3F51B5', 'Leg day'});
    });
  });
}

/// The verbs whose target a flow acts on or waits for; `expect` is an
/// assertion and may read any text.
const Set<String> _actingVerbs = {
  'tap',
  'longpress',
  'wait',
  'scroll-to',
  'text',
  'drag',
};

final RegExp _idForm = RegExp(r'^id:[A-Za-z0-9_+{}-]+$');
final RegExp _indexForm = RegExp(r'^#\d+$');
final RegExp _pointForm = RegExp(r'^-?\d+\s*,\s*-?\d+$');

bool isIdTarget(String target) => _idForm.hasMatch(target);

bool isAllowedTarget(String target, Set<String> labels) {
  if (target.startsWith('id:')) return isIdTarget(target);
  return _indexForm.hasMatch(target) ||
      _pointForm.hasMatch(target) ||
      target.contains('{{') ||
      labels.contains(target);
}

/// The global options a step may lead with (`--via native tap …`), each
/// with whether it takes a value.
const Map<String, bool> _globalOptions = {
  '-d': true,
  '--device': true,
  '--via': true,
  '--verbose': false,
  '--no-verbose': false,
};

/// [words] without the global options in front of the verb.
List<String> _withoutGlobals(List<String> words) {
  var i = 0;
  while (i < words.length) {
    final word = words[i];
    final name = word.contains('=') ? word.substring(0, word.indexOf('=')) : word;
    final takesValue = _globalOptions[name];
    if (takesValue == null) break;
    i += takesValue && !word.contains('=') ? 2 : 1;
  }
  return words.sublist(i.clamp(0, words.length));
}

/// The verb a step runs, past any leading global option.
String? stepVerb(List<String> words) => _withoutGlobals(words).firstOrNull;

/// The options whose value is a target: what an acting verb waits for
/// afterwards, and the container `scroll-to` swipes in.
const Set<String> _targetOptions = {'--wait', '--wait-gone', '--in'};

/// The first positional word after the verb — both for `drag` — then the
/// targets of `--wait`, `--wait-gone` and `--in`, which any verb with
/// post-actions takes (`key back --wait-gone …` included).
List<String> actingTargets(List<String> words) {
  final step = _withoutGlobals(words);
  if (step.isEmpty) return const [];
  final options = _targetOptionValues(step);
  if (!_actingVerbs.contains(step.first)) return options;
  final positional = _positional(step);
  return [
    ...(step.first == 'drag' ? positional.take(2) : positional.take(1)),
    ...options,
  ];
}

/// An `expect`'s present and `--absent` targets.
List<String> expectTargets(List<String> words) {
  final step = _withoutGlobals(words);
  if (step.isEmpty || step.first != 'expect') return const [];
  final targets = <String>[];
  for (var i = 1; i < step.length; i++) {
    final word = step[i];
    if (word == '--absent' && i + 1 < step.length) {
      targets.add(step[++i]);
    } else if (word.startsWith('--')) {
      if (!word.contains('=') && !_bareFlags.contains(word)) i++;
    } else {
      targets.add(word);
    }
  }
  return targets;
}

/// The flags a flow's step may carry that take no value.
const Set<String> _bareFlags = {'--gone', '--up', '--dump', '--ordered', '--enter', '--replace'};

/// The values of [_targetOptions] in [step], `--wait=X` and `--wait X` alike.
List<String> _targetOptionValues(List<String> step) {
  final values = <String>[];
  for (var i = 1; i < step.length; i++) {
    final word = step[i];
    if (!word.startsWith('--')) continue;
    final eq = word.indexOf('=');
    final name = eq < 0 ? word : word.substring(0, eq);
    if (_targetOptions.contains(name)) {
      if (eq >= 0) {
        values.add(word.substring(eq + 1));
      } else if (i + 1 < step.length) {
        values.add(step[++i]);
      }
    } else if (eq < 0 && !_bareFlags.contains(word)) {
      i++;
    }
  }
  return values;
}

/// The words after the verb that are not a flag or a flag's value.
List<String> _positional(List<String> words) {
  final positional = <String>[];
  for (var i = 1; i < words.length; i++) {
    final word = words[i];
    if (word.startsWith('--')) {
      if (!_bareFlags.contains(word) && !word.contains('=')) i++;
      continue;
    }
    positional.add(word);
  }
  return positional;
}

/// One label per line; a comment is "#" alone or "# " and its text, so a
/// label such as a hex colour may start with "#".
Set<String> _readLabels(File file) {
  if (!file.existsSync()) return const {};
  return {
    for (final raw in file.readAsLinesSync())
      if (raw.trim() case final line
          when line.isNotEmpty && line != '#' && !line.startsWith('# '))
        line,
  };
}

String _nameOf(FileSystemEntity entity) =>
    entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
