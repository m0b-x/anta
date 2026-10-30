import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_report.dart';
import 'package:anta/utils/task_count.dart';

/// The report's one task grammar is the list grammar the preview draws, so
/// the risk is a box the preview shows but the count misses, or a custom
/// state counted as done.
void main() {
  test('an open box is a task, not ticked', () {
    expect(countTasks('- [ ] milk'), const ReportTaskCount(0, 1));
  });

  test('x and X are ticked', () {
    expect(countTasks('- [x] milk\n- [X] eggs'), const ReportTaskCount(2, 2));
  });

  test('a custom state is open', () {
    expect(
      countTasks('* [-] cancelled\n- [x] done'),
      const ReportTaskCount(1, 2),
    );
  });

  test('an ordered list without boxes holds no task', () {
    expect(countTasks('1. warm up\n2. squat'), isNull);
  });

  test('nested items count at every indent', () {
    const text = '- [x] shop\n  - [ ] milk\n    - [x] eggs\n\t- [ ] bread';
    expect(countTasks(text), const ReportTaskCount(2, 4));
  });

  test('a text with no task item, or none at all, is null', () {
    expect(countTasks('Focus on hamstrings.\n- a bullet'), isNull);
    expect(countTasks(''), isNull);
    expect(countTasks(null), isNull);
  });

  test('CRLF lines parse like LF ones', () {
    expect(countTasks('- [x] a\r\n- [ ] b\r\n'), const ReportTaskCount(1, 2));
  });

  test('the same text answers an equal count from the cache', () {
    const text = '- [x] one\n- [ ] two\n- [ ] three';
    final first = countTasks(text);
    final second = countTasks(text);
    expect(second, first);
    expect(identical(first, second), isTrue);
    expect(countTasks('no tasks here'), isNull);
    expect(countTasks('no tasks here'), isNull);
  });
}
