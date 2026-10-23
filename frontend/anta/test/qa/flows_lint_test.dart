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
            steps.isEmpty ? null : splitShellWords(steps.last).first,
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

/// The first positional word after the verb — both for `drag`.
List<String> actingTargets(List<String> words) {
  if (words.isEmpty || !_actingVerbs.contains(words.first)) return const [];
  final positional = _positional(words);
  return words.first == 'drag'
      ? positional.take(2).toList()
      : positional.take(1).toList();
}

/// An `expect`'s present and `--absent` targets.
List<String> expectTargets(List<String> words) {
  if (words.isEmpty || words.first != 'expect') return const [];
  final targets = <String>[];
  for (var i = 1; i < words.length; i++) {
    final word = words[i];
    if (word == '--absent' && i + 1 < words.length) {
      targets.add(words[++i]);
    } else if (word.startsWith('--')) {
      if (!word.contains('=')) i++;
    } else {
      targets.add(word);
    }
  }
  return targets;
}

/// The words after the verb that are not a flag or a flag's value. Every
/// flag a flow's acting step takes has a value except `--gone`, `--up` and
/// `--dump`.
List<String> _positional(List<String> words) {
  const bare = {'--gone', '--up', '--dump', '--wait-gone'};
  final positional = <String>[];
  for (var i = 1; i < words.length; i++) {
    final word = words[i];
    if (word.startsWith('--')) {
      if (!bare.contains(word) && !word.contains('=')) i++;
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
